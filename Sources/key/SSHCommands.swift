import Foundation
import KeyCore

let sshUsage = """
    Usage:
      key ssh new [LABEL]   make an SSH key in the Secure Enclave (default label: \(SSHCommands.defaultLabel))
      key ssh ls            list Secure Enclave SSH keys and their files in ~/.ssh
      key ssh rm LABEL      delete a key after Touch ID
      key ssh add [USER@]HOST [--port N] [--key LABEL]
                            install a key on HOST with its password, then log in with the key
      key ssh password HOST [SSH ARGS...]
                            run ssh with key login turned off, so HOST asks for its password
    """

/// SSH keys that live in the Secure Enclave. Each signature, so each connection, needs Touch ID.
struct SSHCommands {
    static let defaultLabel = "default"

    let enclave = SecureEnclave()

    func run(_ args: [String]) throws {
        guard FileManager.default.fileExists(atPath: SecureEnclave.provider) else {
            throw UsageError(description: "Secure Enclave SSH keys need macOS 26 or later (\(SecureEnclave.provider) is missing).")
        }
        guard let command = args.first else { throw UsageError(description: sshUsage) }
        let rest = Array(args.dropFirst())
        switch (command, rest.count) {
        case ("new", 0): try new(Self.defaultLabel)
        case ("new", 1): try new(rest[0])
        case ("ls", 0): try list()
        case ("rm", 1): try remove(rest[0])
        case ("add", _): try add(rest)
        case ("password", 1...): try password(rest)
        case ("-h", _), ("--help", _), ("help", _): print(sshUsage)
        default: throw UsageError(description: sshUsage)
        }
    }

    private func new(_ label: String) throws {
        guard IdentityListing.isValidLabel(label) else {
            throw UsageError(description: "Use only letters, digits, dots, hyphens and underscores in a label.")
        }
        guard try !enclave.identities().contains(where: { $0.label == label }) else {
            throw UsageError(description: "A key labelled \(label) already exists. See `key ssh ls`.")
        }
        let handle = try enclave.create(label)
        let publicKey = try String(contentsOf: enclave.publicKeyFile(handle), encoding: .utf8)
        print("Made the SSH key \(label). Its handle file is \(handle.path).")
        print("Public key:")
        print(publicKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func list() throws {
        let files = enclave.publicKeysByFingerprint()
        for identity in try enclave.identities() {
            let file = files[identity.fingerprint].map { $0.deletingPathExtension().path } ?? "no handle file in ~/.ssh"
            print("\(identity.label)  \(identity.fingerprint)  \(file)")
        }
    }

    private func add(_ args: [String]) throws {
        var target: SSHTarget?
        var port: Int?
        var label = Self.defaultLabel
        var rest = args[...]
        while let arg = rest.popFirst() {
            switch arg {
            case "--port":
                guard let value = rest.popFirst().flatMap(Int.init), (1...65535).contains(value) else {
                    throw UsageError(description: "--port takes a number from 1 to 65535.")
                }
                port = value
            case "--key":
                guard let value = rest.popFirst() else { throw UsageError(description: sshUsage) }
                label = value
            default:
                guard target == nil, let parsed = SSHTarget(parsing: arg) else {
                    throw UsageError(description: "Give one host as [USER@]HOST, using letters, digits, dots, hyphens and underscores.\n\n\(sshUsage)")
                }
                target = parsed
            }
        }
        guard let target else { throw UsageError(description: sshUsage) }

        let hosts = SSHHosts()
        if !hosts.managedHosts().contains(target.host) {
            let options = try hosts.handWrittenOptions(for: target.host)
            guard options.isEmpty else {
                throw UsageError(description: """
                    ~/.ssh/config already sets these for \(target.host), so key ssh add leaves it alone:
                    \(options.map { "  " + $0 }.joined(separator: "\n"))
                    """)
            }
        }

        let (handle, created) = try handleFile(label)
        if created { print("Made the SSH key \(label) for this and later hosts.") }

        print("Enter the password for \(target.destination) one last time.")
        try hosts.install(publicKey: enclave.publicKeyFile(handle), on: target, port: port)

        let entry = ManagedHosts.Entry(target: target, port: port, identityFile: tildePath(handle))
        let previous = try hosts.write(entry)

        print("Logging in with the key alone. Touch ID will ask to confirm.")
        guard try hosts.keyLoginWorks(target.host) else {
            try hosts.restore(previous)
            throw SSHHostsError(description: """
                The key login to \(target.host) failed, so its Host block was removed again.
                The key is still listed in the server's ~/.ssh/authorized_keys.
                The server needs OpenSSH 8.2 or later to accept Secure Enclave keys.
                """)
        }
        print("Done. `ssh \(target.host)` now uses the key \(label), with Touch ID for each connection.")
    }

    /// Replaces this process with ssh, so the session behaves exactly like a plain `ssh` call.
    /// Turning off public key login skips the Secure Enclave key and any agent keys, so a host
    /// that still allows passwords asks for one. The rest of ~/.ssh/config, such as User and
    /// Port, still applies.
    private func password(_ args: [String]) throws -> Never {
        let argv = [SSHHosts.ssh, "-o", "PubkeyAuthentication=no"] + args
        let cArgs = argv.map { strdup($0) } + [nil]
        execv(SSHHosts.ssh, cArgs)
        throw SubprocessError(description: "Could not start ssh: \(String(cString: strerror(errno)))")
    }

    /// The handle file for the key with this label. Makes the default key if it does not exist yet.
    private func handleFile(_ label: String) throws -> (URL, created: Bool) {
        if label == Self.defaultLabel, try !enclave.identities().contains(where: { $0.label == label }) {
            return (try enclave.create(label), true)
        }
        let identity = try enclave.identity(label)
        guard let publicKey = enclave.publicKeysByFingerprint()[identity.fingerprint] else {
            throw SecureEnclaveError(description: "The key \(label) has no handle file in ~/.ssh.")
        }
        return (publicKey.deletingPathExtension(), false)
    }

    /// `~/.ssh/…` rather than the full home path, so the config reads like a hand-written one.
    private func tildePath(_ file: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return file.path.hasPrefix(home + "/") ? "~" + file.path.dropFirst(home.count) : file.path
    }

    private func remove(_ label: String) throws {
        let identity = try enclave.identity(label)
        try Authentication.require("delete the SSH key “\(label)”")
        try enclave.delete(identity)
        print("Deleted the SSH key \(label). Servers that trusted it no longer accept it, and still list it in authorized_keys.")
    }
}

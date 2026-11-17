import Foundation
import KeyCore

let sshUsage = """
    Usage:
      key ssh new [LABEL]   make an SSH key in the Secure Enclave (default label: \(SSHCommands.defaultLabel))
      key ssh ls            list Secure Enclave SSH keys and their files in ~/.ssh
      key ssh rm LABEL      delete a key after Touch ID
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

    private func remove(_ label: String) throws {
        let identity = try enclave.identity(label)
        try Authentication.require("delete the SSH key “\(label)”")
        try enclave.delete(identity)
        print("Deleted the SSH key \(label). Servers that trusted it no longer accept it, and still list it in authorized_keys.")
    }
}

import Foundation
import KeyCore

struct SSHHostsError: Error, CustomStringConvertible {
    let description: String
}

/// Moves a host from password login to a Secure Enclave key: installs the public key on the
/// server, writes a `Host` block into a file this tool owns, and checks that the key logs in.
struct SSHHosts {
    static let ssh = "/usr/bin/ssh"
    static let sshCopyID = "/usr/bin/ssh-copy-id"
    /// Relative paths in an Include are read from ~/.ssh.
    static let include = "Include config.d/key-cli"

    let sshDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
    var config: URL { sshDirectory.appendingPathComponent("config") }
    var backup: URL { sshDirectory.appendingPathComponent("config.key-cli-backup") }
    var managed: URL { sshDirectory.appendingPathComponent("config.d/key-cli") }

    func managedHosts() -> [String] {
        ManagedHosts.hosts(in: read(managed) ?? "")
    }

    /// Options the user's own config sets for this host, found by comparing what ssh resolves
    /// with and without it. Hosts this tool already manages are not checked.
    func handWrittenOptions(for host: String) throws -> [String] {
        let watched = ["user", "hostname", "port", "identityfile", "identitiesonly", "securitykeyprovider"]
        func resolved(_ extra: [String]) throws -> [String] {
            try Subprocess.check(Self.ssh, extra + ["-G", host])
                .split(separator: "\n").map(String.init)
                .filter { line in watched.contains { line.hasPrefix($0 + " ") } }
        }
        let withConfig = try resolved([])
        let without = Set(try resolved(["-F", "/dev/null"]))
        return withConfig.filter { !without.contains($0) }
    }

    /// Appends the public key to the server's authorized_keys, using the password one last time.
    /// `-f` skips ssh-copy-id's trial login with the key, which would fail before the config
    /// below exists. Allowing only password methods stops keys in the agent from using up
    /// the server's login attempts.
    func install(publicKey: URL, on target: SSHTarget, port: Int?) throws {
        guard FileManager.default.fileExists(atPath: Self.sshCopyID) else {
            throw SSHHostsError(description: "\(Self.sshCopyID) is missing.")
        }
        var args = ["-f", "-i", publicKey.path, "-o", "PreferredAuthentications=password,keyboard-interactive"]
        if let port { args += ["-p", String(port)] }
        args.append(target.destination)
        guard try Subprocess.interactive(Self.sshCopyID, args) == 0 else {
            throw SSHHostsError(description: "ssh-copy-id could not install the key on \(target.destination). Nothing was changed on this Mac.")
        }
    }

    /// Writes the host's block and makes sure ~/.ssh/config includes the file.
    /// Returns the file as it was, for `restore`.
    func write(_ entry: ManagedHosts.Entry) throws -> String? {
        let fm = FileManager.default
        try fm.createDirectory(at: managed.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let previous = read(managed)
        try save(ManagedHosts.setting(entry, in: previous ?? ""), to: managed)

        let current = read(config) ?? ""
        if let updated = ConfigInclude.adding(Self.include, to: current) {
            if fm.fileExists(atPath: config.path), !fm.fileExists(atPath: backup.path) {
                try fm.copyItem(at: config, to: backup)
                print("Backed up ~/.ssh/config to \(backup.path).")
            }
            try save(updated, to: config)
            print("Added `\(Self.include)` to ~/.ssh/config.")
        }
        return previous
    }

    /// Puts the managed file back as `write` found it. The Include line stays; it is harmless.
    func restore(_ previous: String?) throws {
        if let previous {
            try save(previous, to: managed)
        } else {
            try FileManager.default.removeItem(at: managed)
        }
    }

    /// Logs in with the key alone and runs `true`. Touch ID is asked for here.
    func keyLoginWorks(_ host: String) throws -> Bool {
        let args = [
            "-o", "PreferredAuthentications=publickey",
            "-o", "PasswordAuthentication=no",
            "-o", "KbdInteractiveAuthentication=no",
            host, "true",
        ]
        return try Subprocess.interactive(Self.ssh, args) == 0
    }

    private func read(_ file: URL) -> String? {
        try? String(contentsOf: file, encoding: .utf8)
    }

    /// Writes through a symlink, such as a config kept in a dotfiles repository, and keeps
    /// the file's permissions. A new file is readable only by its owner.
    private func save(_ text: String, to file: URL) throws {
        let target = file.resolvingSymlinksInPath()
        let permissions = (try? FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions]) ?? 0o600
        try Data(text.utf8).write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
    }
}

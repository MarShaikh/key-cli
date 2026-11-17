import Foundation
import KeyCore

struct SecureEnclaveError: Error, CustomStringConvertible {
    let description: String
}

/// SSH keys held in the Secure Enclave, through the tools macOS 26 and later ship:
/// `sc_auth` makes and deletes the key, and OpenSSH reaches it through ssh-keychain.dylib.
///
/// The private key never leaves the chip. On disk there is only a handle file, which tells
/// OpenSSH which Secure Enclave key to ask for, and the public key.
struct SecureEnclave {
    static let provider = "/usr/lib/ssh-keychain.dylib"
    static let scAuth = "/usr/sbin/sc_auth"
    static let sshKeygen = "/usr/bin/ssh-keygen"

    let sshDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")

    func identities() throws -> [SecureEnclaveIdentity] {
        let sha1 = try Subprocess.check(Self.scAuth, ["list-ctk-identities"])
        let ssh = try Subprocess.check(Self.scAuth, ["list-ctk-identities", "-t", "ssh"])
        guard let identities = IdentityListing.identities(sha1: sha1, ssh: ssh) else {
            throw SecureEnclaveError(description: "The 2 sc_auth listings disagree; run the command again.")
        }
        return identities
    }

    func identity(_ label: String) throws -> SecureEnclaveIdentity {
        let matches = try identities().filter { $0.label == label }
        switch matches.count {
        case 1: return matches[0]
        case 0: throw SecureEnclaveError(description: "No SSH key labelled \(label). See `key ssh ls`.")
        default: throw SecureEnclaveError(description: "\(matches.count) keys are labelled \(label); remove the extras with `sc_auth delete-ctk-identity -h HASH`.")
        }
    }

    /// Where `new` saves the handle file. The public key sits next to it with `.pub` added.
    func handleFile(_ label: String) -> URL {
        sshDirectory.appendingPathComponent("id_ecdsa_sk_rk_\(label)")
    }

    /// Makes a key that needs Touch ID for every signature, then writes its handle file.
    func create(_ label: String) throws -> URL {
        let handle = handleFile(label)
        for file in [handle, publicKeyFile(handle)] where FileManager.default.fileExists(atPath: file.path) {
            throw SecureEnclaveError(description: "\(file.path) already exists; move it away first.")
        }
        try scAuth(["create-ctk-identity", "-l", label, "-k", "p-256-ne", "-t", "bio", "-N", label])
        do {
            try writeHandle(for: identity(label), to: handle)
        } catch {
            throw SecureEnclaveError(description: "Made the key \(label) but could not save its handle file: \(error). Run `key ssh rm \(label)`, then try again.")
        }
        return handle
    }

    /// Deletes the key from the Secure Enclave, and its handle files if `new` made them.
    func delete(_ identity: SecureEnclaveIdentity) throws {
        try scAuth(["delete-ctk-identity", "-h", identity.hash])
        let handle = handleFile(identity.label)
        if (try? fingerprint(ofPublicKey: publicKeyFile(handle))) == identity.fingerprint {
            try FileManager.default.removeItem(at: handle)
            try FileManager.default.removeItem(at: publicKeyFile(handle))
        }
    }

    /// Public key files in ~/.ssh, by fingerprint, so `ls` can show which file holds each key.
    func publicKeysByFingerprint() -> [String: URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: sshDirectory, includingPropertiesForKeys: nil)) ?? []
        var result: [String: URL] = [:]
        for file in files where file.pathExtension == "pub" {
            if let found = try? fingerprint(ofPublicKey: file), result[found] == nil {
                result[found] = file
            }
        }
        return result
    }

    func publicKeyFile(_ handle: URL) -> URL {
        handle.appendingPathExtension("pub")
    }

    /// `ssh-keygen -K` saves a handle file for every Secure Enclave key, named after the label,
    /// and asks before overwriting. So it runs in an empty folder, and only the file whose
    /// fingerprint matches is kept.
    private func writeHandle(for identity: SecureEnclaveIdentity, to handle: URL) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("key-cli-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: work) }

        // ssh-keygen asks for a PIN, which the Secure Enclave does not use. A forced askpass
        // that prints nothing answers it without a prompt in the terminal.
        try Subprocess.check(
            Self.sshKeygen, ["-w", Self.provider, "-K", "-N", ""],
            environment: ["SSH_ASKPASS": "/usr/bin/true", "SSH_ASKPASS_REQUIRE": "force"],
            in: work)

        let saved = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
        guard let publicKey = saved.first(where: {
            $0.pathExtension == "pub" && (try? fingerprint(ofPublicKey: $0)) == identity.fingerprint
        }) else {
            throw SecureEnclaveError(description: "ssh-keygen did not save the key \(identity.label).")
        }
        try fm.createDirectory(at: sshDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.moveItem(at: publicKey.deletingPathExtension(), to: handle)
        try fm.moveItem(at: publicKey, to: publicKeyFile(handle))
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: handle.path)
    }

    /// sc_auth exits 0 even when it fails, for example when Touch ID is cancelled,
    /// and prints "Error: …" instead, so that line counts as a failure.
    private func scAuth(_ args: [String]) throws {
        let result = try Subprocess.run(Self.scAuth, args)
        let output = result.stdout + result.stderr
        if result.status != 0 || output.contains("Error:") {
            throw SecureEnclaveError(description: "sc_auth \(args[0]) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    private func fingerprint(ofPublicKey file: URL) throws -> String? {
        let output = try Subprocess.check(Self.sshKeygen, ["-l", "-f", file.path])
        return KeyCore.fingerprint(fromKeygenLine: output)
    }
}

/// A key that `sc_auth create-ctk-identity` made in the Secure Enclave.
public struct SecureEnclaveIdentity: Equatable {
    public let label: String
    /// The SHA-1 hash that `sc_auth delete-ctk-identity -h` takes.
    public let hash: String
    /// The `SHA256:` fingerprint that `ssh-keygen -l` prints for the same key.
    public let fingerprint: String

    public init(label: String, hash: String, fingerprint: String) {
        self.label = label
        self.hash = hash
        self.fingerprint = fingerprint
    }
}

public enum IdentityListing {
    /// One row of `sc_auth list-ctk-identities`, with or without `-t ssh`.
    public struct Row: Equatable {
        public let hash: String
        public let label: String
    }

    static let keyTypes: Set<String> = ["p-256", "p-384", "p-521", "p-256-ne", "p-384-ne"]

    /// Reads the table `sc_auth list-ctk-identities` prints.
    ///
    /// Columns after the label can be empty and the date format follows the locale,
    /// so only the first 4 columns are read: key type, hash, protection, label.
    /// A label that contains spaces keeps only its first word.
    public static func rows(_ text: String) -> [Row] {
        text.split(separator: "\n").compactMap { line in
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard columns.count >= 4, keyTypes.contains(columns[0]) else { return nil }
            return Row(hash: columns[1], label: columns[3])
        }
    }

    /// Joins the default listing (SHA-1 hashes) with the `-t ssh` listing (fingerprints).
    /// Both list the same identities in the same order, so rows pair up by position.
    /// Returns nil if the 2 listings disagree, for example when a key was added between them.
    public static func identities(sha1: String, ssh: String) -> [SecureEnclaveIdentity]? {
        let hashes = rows(sha1)
        let fingerprints = rows(ssh)
        guard hashes.count == fingerprints.count else { return nil }
        var result: [SecureEnclaveIdentity] = []
        for (hash, fingerprint) in zip(hashes, fingerprints) {
            guard hash.label == fingerprint.label else { return nil }
            result.append(SecureEnclaveIdentity(label: hash.label, hash: hash.hash, fingerprint: fingerprint.hash))
        }
        return result
    }

    /// Labels this tool creates: letters, digits, dots, hyphens and underscores,
    /// so they are safe in a file name and survive the listing's column split.
    public static func isValidLabel(_ label: String) -> Bool {
        !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}

/// The fingerprint from one line of `ssh-keygen -l -f FILE` output,
/// such as `256 SHA256:WJ45… ssh: (ECDSA-SK)`.
public func fingerprint(fromKeygenLine line: String) -> String? {
    line.split(whereSeparator: \.isWhitespace).map(String.init).first { $0.hasPrefix("SHA256:") }
}

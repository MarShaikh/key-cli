import Foundation

/// The `[user@]host` that `key ssh add` sets up.
public struct SSHTarget: Equatable {
    public let user: String?
    public let host: String

    public init(user: String?, host: String) {
        self.user = user
        self.host = host
    }

    /// Accepts letters, digits, dots, hyphens and underscores, and no leading hyphen.
    /// The values go into ~/.ssh/config and onto the ssh command line, so a space, newline,
    /// wildcard or leading hyphen could add options the user never asked for.
    public init?(parsing text: String) {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false).map(String.init)
        switch parts.count {
        case 1: (user, host) = (nil, parts[0])
        case 2: (user, host) = (parts[0], parts[1])
        default: return nil
        }
        guard Self.isSafe(host), user.map(Self.isSafe) ?? true else { return nil }
    }

    /// `user@host`, or `host` without a user, as ssh takes it.
    public var destination: String {
        user.map { "\($0)@\(host)" } ?? host
    }

    static func isSafe(_ word: String) -> Bool {
        !word.isEmpty && !word.hasPrefix("-")
            && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }
    }
}

/// Adds an `Include` line to ~/.ssh/config.
public enum ConfigInclude {
    /// Puts the line just before the first `Host` or `Match`, so it applies to every host
    /// and comes after includes that must stay at the top, such as OrbStack's.
    /// ssh keeps the first value it reads for an option, so the included blocks also win
    /// over a later `Host *`. Returns nil if the line is already there.
    public static func adding(_ include: String, to config: String) -> String? {
        var lines = config.components(separatedBy: "\n")
        if lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == include }) { return nil }
        if let first = lines.firstIndex(where: startsBlock) {
            lines.insert(include, at: first)
            return lines.joined(separator: "\n")
        }
        if lines.last == "" { lines.removeLast() }
        lines.append(include)
        return lines.joined(separator: "\n") + "\n"
    }

    static func startsBlock(_ line: String) -> Bool {
        let keyword = line.split(whereSeparator: \.isWhitespace).first?.lowercased()
        return keyword == "host" || keyword == "match"
    }
}

/// The file `key ssh add` owns, with one `Host` block for each host it set up.
public enum ManagedHosts {
    public static let provider = "/usr/lib/ssh-keychain.dylib"
    static let header = "# Written by `key ssh add`. Edit with care: the tool rewrites these blocks."

    public struct Entry: Equatable {
        public let target: SSHTarget
        public let port: Int?
        /// Written as given, such as `~/.ssh/id_ecdsa_sk_rk_default`.
        public let identityFile: String

        public init(target: SSHTarget, port: Int?, identityFile: String) {
            self.target = target
            self.port = port
            self.identityFile = identityFile
        }

        var block: String {
            var lines = ["Host \(target.host)", "  HostName \(target.host)"]
            if let user = target.user { lines.append("  User \(user)") }
            if let port { lines.append("  Port \(port)") }
            lines += [
                "  IdentityFile \(identityFile)",
                "  IdentitiesOnly yes",
                "  SecurityKeyProvider \(ManagedHosts.provider)",
            ]
            return lines.joined(separator: "\n")
        }
    }

    /// The file with `entry` added, or with its old block for the same host replaced.
    public static func setting(_ entry: Entry, in file: String) -> String {
        var blocks = self.blocks(in: file)
        if let existing = blocks.firstIndex(where: { host(of: $0) == entry.target.host }) {
            blocks[existing] = entry.block
        } else {
            blocks.append(entry.block)
        }
        return ([header] + blocks).joined(separator: "\n\n") + "\n"
    }

    /// The hosts with a block in the file, in file order.
    public static func hosts(in file: String) -> [String] {
        blocks(in: file).compactMap(host)
    }

    /// Each block runs from a `Host` line to the line before the next one. Text before the
    /// first block is the header, which `setting` writes again.
    static func blocks(in file: String) -> [String] {
        var blocks: [[String]] = []
        for line in file.components(separatedBy: "\n") {
            if line.hasPrefix("Host ") {
                blocks.append([line])
            } else if !blocks.isEmpty {
                blocks[blocks.count - 1].append(line)
            }
        }
        return blocks.map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func host(of block: String) -> String? {
        block.split(separator: "\n").first.flatMap { $0.split(separator: " ").dropFirst().first.map(String.init) }
    }
}

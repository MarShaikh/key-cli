import Foundation

/// Items written by the old zsh `key` function through /usr/bin/security.
/// Their ACL trusts `security`, so only `security` can read or delete them without a dialog.
/// That trust is also the hole adoption closes: anyone at the Mac can run it.
struct LegacyKeychain {
    let account = NSUserName()

    func read(_ name: String) throws -> Data {
        var out = try run(["find-generic-password", "-a", account, "-s", name, "-w"], notFound: name)
        if out.last == UInt8(ascii: "\n") { out.removeLast() }
        return out
    }

    func delete(_ name: String) throws {
        _ = try run(["delete-generic-password", "-a", account, "-s", name], notFound: name)
    }

    private func run(_ args: [String], notFound name: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // security exits 44 when the item does not exist.
        guard process.terminationStatus == 0 else { throw KeychainError.notFound(name) }
        return data
    }
}

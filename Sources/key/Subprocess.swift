import Foundation

struct SubprocessError: Error, CustomStringConvertible {
    let description: String
}

enum Subprocess {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    /// Runs a tool to completion and captures its output. Stdin is /dev/null.
    static func run(
        _ path: String, _ args: [String],
        environment: [String: String] = [:], in directory: URL? = nil
    ) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Read stderr on another thread so neither pipe fills up and blocks the tool.
        var errData = Data()
        let errDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            errData = stderr.fileHandleForReading.readDataToEndOfFile()
            errDone.signal()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        errDone.wait()
        process.waitUntilExit()
        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self))
    }

    /// Like `run`, but throws with the tool's own error message if it exits non-zero.
    @discardableResult
    static func check(
        _ path: String, _ args: [String],
        environment: [String: String] = [:], in directory: URL? = nil
    ) throws -> String {
        let result = try run(path, args, environment: environment, in: directory)
        guard result.status == 0 else {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            throw SubprocessError(description: "\(name) failed: \(message.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result.stdout
    }
}

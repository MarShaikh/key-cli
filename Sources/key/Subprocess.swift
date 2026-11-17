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

    /// Runs a tool attached to this terminal, so it can ask for a password, and returns its exit status.
    ///
    /// Foundation's Process puts the child in a new process group, which the terminal treats
    /// as a background job: ssh then cannot turn off echo or read the password, and stops.
    /// posix_spawn keeps the child in this process group, in the foreground.
    static func interactive(_ path: String, _ args: [String]) throws -> Int32 {
        let argv = ([path] + args).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, path, nil, nil, argv, environ)
        guard spawned == 0 else {
            throw SubprocessError(description: "Could not start \(path): \(String(cString: strerror(spawned)))")
        }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else { throw SubprocessError(description: "Lost track of \(path).") }
        }
        // The exit code sits in bits 8 to 15 when the low 7 bits are 0; otherwise a signal ended it.
        return status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
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

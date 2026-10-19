import Foundation

struct UsageError: Error, CustomStringConvertible {
    let description: String
}

let usage = """
    Usage:
      key set NAME          store a key (prompts without echo, or reads piped stdin)
      key get NAME          print a key after Touch ID   (also: getkey NAME)
      key rm NAME           delete a key after Touch ID
      key ls                list stored key names
      key adopt NAME...     move keys stored by the old zsh function under Touch ID
      key NAME              same as `key set NAME`
    """

struct Commands {
    let keychain = Keychain()
    let legacy = LegacyKeychain()

    func run(_ args: [String]) throws {
        guard let command = args.first else { throw UsageError(description: usage) }
        let rest = Array(args.dropFirst())
        switch command {
        case "set": try set(one(rest))
        case "get": try get(one(rest))
        case "rm": try remove(one(rest))
        case "ls": try list()
        case "adopt": try adopt(rest)
        case "-h", "--help", "help": print(usage)
        case _ where rest.isEmpty && !command.hasPrefix("-"): try set(command)
        default: throw UsageError(description: usage)
        }
    }

    private func set(_ name: String) throws {
        // Overwriting destroys the old key, so it needs the same proof as reading it.
        if try keychain.names().contains(name) {
            try Authentication.require("replace the key “\(name)”")
        }
        guard let secret = SecretInput.read(prompt: "Enter key for \(name): ") else {
            throw UsageError(description: "Key cannot be empty.")
        }
        try keychain.write(name, secret)
        print("Key added successfully for service: \(name)")
    }

    private func get(_ name: String) throws {
        try Authentication.require("read the key “\(name)”")
        let secret = try keychain.read(name)
        FileHandle.standardOutput.write(secret)
        if isatty(STDOUT_FILENO) != 0 { print() }
    }

    private func remove(_ name: String) throws {
        try Authentication.require("delete the key “\(name)”")
        do {
            try keychain.delete(name)
        } catch KeychainError.notOwned {
            try legacy.delete(name)
        }
        print("Deleted key: \(name)")
    }

    private func list() throws {
        for name in try keychain.names() { print(name) }
    }

    private func adopt(_ names: [String]) throws {
        guard !names.isEmpty else { throw UsageError(description: usage) }
        try Authentication.require("move \(names.count == 1 ? "a key" : "\(names.count) keys") under Touch ID")
        let owned = Set(try keychain.names())
        var failed = false
        for name in names {
            if owned.contains(name) {
                print("\(name): already adopted")
                continue
            }
            do {
                let secret = try legacy.read(name)
                try legacy.delete(name)
                do {
                    try keychain.write(name, secret)
                } catch {
                    // The old item is gone; hand the secret back rather than lose it.
                    fputs("\(name): could not re-store (\(error)). Its value follows; store it with `key set \(name)`.\n", stderr)
                    FileHandle.standardOutput.write(secret + Data("\n".utf8))
                    failed = true
                    continue
                }
                print("\(name): adopted")
            } catch {
                fputs("\(name): \(error)\n", stderr)
                failed = true
            }
        }
        if failed { exit(1) }
    }

    private func one(_ rest: [String]) throws -> String {
        guard rest.count == 1, let name = rest.first, !name.isEmpty else { throw UsageError(description: usage) }
        return name
    }
}

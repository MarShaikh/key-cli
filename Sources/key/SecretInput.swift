import Foundation

enum SecretInput {
    /// Reads a secret without echoing it, or from stdin when piped (`pbpaste | key set NAME`).
    static func read(prompt: String) -> Data? {
        let text: String
        if isatty(STDIN_FILENO) != 0 {
            var buffer = [CChar](repeating: 0, count: 4096)
            guard readpassphrase(prompt, &buffer, buffer.count, RPP_ECHO_OFF) != nil else { return nil }
            text = String(cString: buffer)
        } else {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
        }
        return text.isEmpty ? nil : Data(text.utf8)
    }
}

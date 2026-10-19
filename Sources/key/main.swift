import Foundation

// `getkey NAME` is a symlink to this binary; keep that spelling working.
var args = Array(CommandLine.arguments.dropFirst())
if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "getkey" {
    args.insert("get", at: 0)
}

do {
    try Commands().run(args)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}

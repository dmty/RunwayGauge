import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else {
    printHelp(to: FileHandle.standardError)
    exit(1)
}

switch command {
case "help", "--help", "-h":
    printHelp(to: FileHandle.standardOutput)
    exit(0)

case "poll":
    let force = args.contains("--force")
    await PollCommand.run(force: force)
    exit(0)

case "write":
    let accountId = parseFlagValue(args, name: "--account-id")
    WriteCommand.run(accountIdFlag: accountId)
    exit(0)

default:
    fputs("unknown command: \(command)\n", stderr)
    printHelp(to: FileHandle.standardError)
    exit(1)
}

private func parseFlagValue(_ args: [String], name: String) -> String? {
    if let idx = args.firstIndex(of: name), args.index(after: idx) < args.endIndex {
        return args[args.index(after: idx)]
    }
    if let glued = args.first(where: { $0.hasPrefix("\(name)=") }) {
        return String(glued.dropFirst(name.count + 1))
    }
    return nil
}

private func printHelp(to handle: FileHandle) {
    let text = """
    runwaygauge-helper — write / poll Claude usage for RunwayGauge

    Usage:
      runwaygauge-helper write [--account-id acc_…]
      runwaygauge-helper poll [--force]
      runwaygauge-helper --help

    write  Read statusline JSON on stdin; commit usage file (min interval 30s).
           Soft-exits 0 on all failures.
    poll   Refresh pinned Keychain accounts (skip if file age < 600s unless --force).
           Never refreshes OAuth tokens.

    """
    if let data = text.data(using: .utf8) {
        try? handle.write(contentsOf: data)
    }
}

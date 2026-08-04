import Foundation

struct SetupResult: Sendable {
    var succeeded: Bool
    var output: String
}

enum HelperSetup {
    private static let launchAgentPlistName = "com.mirabilia.macusagewidget.claudeusage.plist"
    private static let jqSearchPaths = [
        "/opt/homebrew/bin/jq",
        "/usr/local/bin/jq",
        "/usr/bin/jq",
        "/bin/jq",
    ]
    private static let processPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    private static let maxOutputBytes = 8192

    static var bundledHelpersURL: URL? {
        Bundle.main.url(forResource: "Helpers", withExtension: nil)
    }

    static var installDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacUsageWidget/helpers", isDirectory: true)
    }

    static func isInstalled(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) -> Bool {
        let home = homeDirectoryURL ?? fileManager.homeDirectoryForCurrentUser
        let plist = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(launchAgentPlistName)
        return fileManager.fileExists(atPath: plist.path)
    }

    static func runSetup() async -> SetupResult {
        guard let bootstrap = Bundle.main.url(
            forResource: "install-helpers-from-bundle",
            withExtension: "sh"
        ) else {
            return SetupResult(
                succeeded: false,
                output: "Bootstrap script not found in app bundle."
            )
        }
        guard let helpers = bundledHelpersURL else {
            return SetupResult(
                succeeded: false,
                output: "Helpers directory not found in app bundle."
            )
        }
        guard findJQ(fileManager: .default) != nil else {
            return SetupResult(
                succeeded: false,
                output: "jq is required but was not found. Install with: brew install jq"
            )
        }

        let destination = installDirectoryURL
        return await Task.detached(priority: .userInitiated) {
            runBootstrap(bootstrap: bootstrap, helpers: helpers, destination: destination)
        }.value
    }

    static func findJQ(fileManager: FileManager = .default) -> URL? {
        jqSearchPaths
            .map { URL(fileURLWithPath: $0) }
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func runBootstrap(
        bootstrap: URL,
        helpers: URL,
        destination: URL
    ) -> SetupResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [bootstrap.path, helpers.path, destination.path]

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = processPath
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return SetupResult(
                succeeded: false,
                output: "Failed to launch installer: \(error.localizedDescription)"
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let rawOutput = String(data: data, encoding: .utf8) ?? ""
        let capped = capOutput(rawOutput)
        let status = process.terminationStatus

        let summary: String
        let succeeded: Bool
        switch status {
        case 0:
            summary = "Setup completed successfully."
            succeeded = true
        case 10:
            summary = "Setup partially failed: statusline installation failed."
            succeeded = false
        case 11:
            summary = "Setup partially failed: poller installation failed."
            succeeded = false
        case 12:
            summary = "Setup failed: both statusline and poller installation failed."
            succeeded = false
        default:
            summary = "Setup failed (exit code \(status))."
            succeeded = false
        }

        return SetupResult(succeeded: succeeded, output: "\(summary)\n\n\(capped)")
    }

    private static func capOutput(_ output: String) -> String {
        guard let data = output.data(using: .utf8), data.count > maxOutputBytes else {
            return output
        }
        var bytes = Array(data.suffix(maxOutputBytes))
        while let first = bytes.first, (first & 0xC0) == 0x80 {
            bytes.removeFirst()
        }
        while !bytes.isEmpty {
            if let decoded = String(bytes: bytes, encoding: .utf8) {
                return decoded
            }
            bytes.removeLast()
        }
        return ""
    }
}

import Foundation
import UsageCore

struct SetupResult: Sendable {
    var succeeded: Bool
    var output: String
}

struct HelperDiagnostics: Sendable {
    var launchAgentInstalled: Bool
    var installedDirectory: String
    var installedDirectoryExists: Bool
    var bundledHelpersAvailable: Bool
    var helperBinaryAvailable: Bool
    var configuredFingerprint: String?
    var hasLegacyUsageWarning: Bool
}

enum HelperSetup {
    private static let launchAgentPlistName = "com.mirabilia.runwaygauge.claudeusage.plist"
    private static let helperBinaryName = "runwaygauge-helper"
    private static let configuredFingerprintKey = "helperConfiguredFingerprint"
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
            .appendingPathComponent("RunwayGauge/helpers", isDirectory: true)
    }

    static func helperBinaryURL(in helpersDirectory: URL) -> URL {
        helpersDirectory.appendingPathComponent(helperBinaryName)
    }

    static func isHelperBinaryAvailable(
        in helpersDirectory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        fileManager.isExecutableFile(atPath: helperBinaryURL(in: helpersDirectory).path)
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
        guard isHelperBinaryAvailable(in: helpers) else {
            return SetupResult(
                succeeded: false,
                output: "runwaygauge-helper binary not found in app bundle."
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

    static func fingerprint(
        for registry: AccountRegistry,
        home: URL? = nil
    ) -> String {
        let configDirectories = Set(registry.accounts.compactMap { account -> String? in
            guard account.sourceKind == .claudeOAuth,
                  let configDir = account.credentials.configDir else {
                return nil
            }
            return AccountValidation.normalizePath(configDir, home: home)
        })
        return (["helper-config-v1"] + configDirectories.sorted())
            .joined(separator: "\n")
    }

    static func markConfigured(registry: AccountRegistry) {
        UserDefaults.standard.set(
            fingerprint(for: registry),
            forKey: configuredFingerprintKey
        )
    }

    static func needsReconfiguration(
        registry: AccountRegistry,
        diagnostics: HelperDiagnostics
    ) -> Bool {
        diagnostics.hasLegacyUsageWarning
            || diagnostics.configuredFingerprint != fingerprint(for: registry)
    }

    static func diagnostics(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL? = nil
    ) -> HelperDiagnostics {
        let bundled = bundledHelpersURL
        let bundledHelpersAvailable = bundled.map {
            fileManager.fileExists(atPath: $0.path)
                && isHelperBinaryAvailable(in: $0, fileManager: fileManager)
        } ?? false
        return HelperDiagnostics(
            launchAgentInstalled: isInstalled(
                fileManager: fileManager,
                homeDirectoryURL: homeDirectoryURL
            ),
            installedDirectory: installDirectoryURL.path,
            installedDirectoryExists: fileManager.fileExists(atPath: installDirectoryURL.path),
            bundledHelpersAvailable: bundledHelpersAvailable,
            helperBinaryAvailable: isHelperBinaryAvailable(
                in: installDirectoryURL,
                fileManager: fileManager
            ),
            configuredFingerprint: UserDefaults.standard.string(
                forKey: configuredFingerprintKey
            ),
            hasLegacyUsageWarning: AccountStore.hasLegacyUsageWarning(
                home: homeDirectoryURL
            )
        )
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

        let (summary, succeeded) = exitSummaries[status]
            ?? ("Setup failed (exit code \(status)).", false)
        return SetupResult(succeeded: succeeded, output: "\(summary)\n\n\(capped)")
    }

    private static let exitSummaries: [Int32: (String, Bool)] = [
        0: ("Setup completed successfully.", true),
        10: ("Setup partially failed: statusline installation failed.", false),
        11: ("Setup partially failed: poller installation failed.", false),
        12: ("Setup failed: both statusline and poller installation failed.", false),
    ]

    private static func capOutput(_ output: String) -> String {
        // ponytail: char truncate; byte-safe trim if installer logs clip mid-emoji
        guard output.count > maxOutputBytes else { return output }
        return String(output.suffix(maxOutputBytes))
    }
}

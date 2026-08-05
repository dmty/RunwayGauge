import SwiftUI
import UsageCore
import WidgetKit

struct AppBootstrapResult: Sendable {
    var registry: AccountRegistry
    var discoveryWarning: String?
}

enum RegistryCommitOrdering {
    static func preferred(
        current: AccountRegistry?,
        committed: AccountRegistry
    ) -> AccountRegistry {
        guard let current, current.revision > committed.revision else {
            return committed
        }
        return current
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var registry: AccountRegistry?
    @Published private(set) var bootstrapError: String?
    @Published private(set) var isBootstrapping = true
    @Published var actionError: String?
    @Published var setupOutput: String?
    @Published var isSettingUpHelpers = false

    init() {
        Task { await bootstrap() }
    }

    var canMutateRegistry: Bool {
        registry != nil && bootstrapError == nil
    }

    var helpersNeedReconfiguration: Bool {
        guard HelperSetup.isInstalled(), let registry else { return false }
        return HelperSetup.needsReconfiguration(
            registry: registry,
            diagnostics: HelperSetup.diagnostics()
        )
    }

    func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let result = try await Self.bootstrapRegistry(home: home)
            registry = result.registry
            actionError = result.discoveryWarning
            bootstrapError = nil
        } catch {
            bootstrapError = error.localizedDescription
        }
    }

    static func bootstrapRegistry(
        home: URL,
        discoverKeychain: @escaping @Sendable () async throws -> [KeychainItemDescriptor] = {
            try await KeychainDiscovery.discover()
        }
    ) async throws -> AppBootstrapResult {
        let descriptors: [KeychainItemDescriptor]
        let discoveryWarning: String?
        do {
            descriptors = try await discoverKeychain()
            discoveryWarning = nil
        } catch {
            descriptors = []
            discoveryWarning = "Keychain discovery unavailable: \(error.localizedDescription)"
        }

        let discovered = ClaudeOAuthSource().discover(
            home: home,
            keychainItems: descriptors
        )
        var registry = try await Task.detached(priority: .userInitiated) {
            try AccountStore.bootstrapIfMissing(home: home, discovered: discovered)
        }.value
        // Validate only the in-memory copy so malformed-but-decodable registries
        // produce a durable bootstrap error without changing their bytes.
        try AccountValidation.validateAndRepair(&registry, home: home)
        return AppBootstrapResult(
            registry: registry,
            discoveryWarning: discoveryWarning
        )
    }

    func mutate(
        _ body: @escaping @Sendable (inout AccountRegistry) throws -> Void
    ) async -> Bool {
        guard canMutateRegistry else { return false }
        do {
            let url = AccountStore.url()
            let committed = try await Task.detached(priority: .userInitiated) {
                try AccountStore.mutate(at: url, body)
            }.value
            registry = RegistryCommitOrdering.preferred(
                current: registry,
                committed: committed
            )
            actionError = nil
            WidgetCenter.shared.reloadTimelines(ofKind: "UsageWidget")
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func runHelperSetup() async {
        guard canMutateRegistry, let registry else { return }
        isSettingUpHelpers = true
        setupOutput = nil
        let result = await HelperSetup.runSetup()
        if result.succeeded {
            HelperSetup.markConfigured(registry: registry)
        }
        setupOutput = result.output
        isSettingUpHelpers = false
    }
}

struct StatusView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isInstalled = HelperSetup.isInstalled()

    private var now: Date { Date() }
    private var displayedAccount: Account? {
        model.registry.flatMap { AccountSelection.displayedAccount(at: now, in: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Runway Gauge").font(.headline)

            Text("Add widgets from Notification Center → Edit Widgets.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                if model.isBootstrapping {
                    ProgressView("Preparing account registry…")
                } else if let bootstrapError = model.bootstrapError {
                    Text("Account registry could not be loaded.")
                        .font(.callout).bold()
                    Text(bootstrapError)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Text("The existing registry was preserved. Registry changes are disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let account = displayedAccount {
                    Text(account.label).font(.caption).bold()
                    Text(usagePath(for: account))
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                    Text(statusLine(for: account)).font(.callout)
                } else {
                    Text("No pinned account selected.").font(.callout)
                }
            }

            Text("Refresh this window to re-check.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            Button {
                Task { await model.runHelperSetup(); isInstalled = HelperSetup.isInstalled() }
            } label: {
                HStack(spacing: 8) {
                    if model.isSettingUpHelpers {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        isInstalled ? "Reconfigure data collection" : "Set up data collection",
                        systemImage: "gearshape"
                    )
                }
            }
            .disabled(model.isSettingUpHelpers || !model.canMutateRegistry)

            if model.helpersNeedReconfiguration {
                Text("Account changes require helper reconfiguration.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let setupOutput = model.setupOutput {
                ScrollView {
                    Text(setupOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            SettingsLink {
                Label("Account settings", systemImage: "person.2")
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
        .onAppear {
            isInstalled = HelperSetup.isInstalled()
        }
    }

    private func usagePath(for account: Account) -> String {
        (try? UsageStore.usageURL(accountId: account.id).path) ?? "Invalid account path"
    }

    private func statusLine(for account: Account) -> String {
        let now = self.now
        let path = usagePath(for: account)
        switch UsageStore.state(
            for: UsageStore.load(accountId: account.id),
            now: now,
            path: path
        ) {
        case .empty:
            return "No usage data yet for this account."
        case .unreadable:
            return "File exists but could not be read or decoded."
        case .data(let record, let freshness):
            let formatter = UsageFormatter(timeZone: .current)
            let windows = record.windows
                .map { "\($0.label) \(Int($0.usedPercent.rounded()))%" }
                .joined(separator: ", ")
            switch freshness {
            case .fresh:
                return "OK — \(windows), written by \(record.origin)."
            case .stale(let age):
                return "Stale (\(formatter.ageDescription(age))) — \(windows), written by \(record.origin)."
            }
        }
    }
}

@main
struct RunwayGaugeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Runway Gauge") {
            StatusView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

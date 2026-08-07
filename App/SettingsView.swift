import SwiftUI
import UsageCore

enum DiscoveredAccountMerge {
    static func merge(
        _ discovered: [DiscoveredAccount],
        into registry: inout AccountRegistry,
        home: URL,
        now: Date = Date()
    ) {
        pruneStaleKeychainAccounts(discovered, from: &registry, now: now)

        for item in discovered {
            if registry.accounts.contains(where: {
                $0.sourceKind == item.sourceKind && $0.credentials == item.credentials
            }) {
                continue
            }

            if item.sourceKind == .claudeOAuth,
               let discoveredKeychain = item.credentials.keychain,
               let index = registry.accounts.firstIndex(where: { account in
                   account.sourceKind == .claudeOAuth
                       && sameKeychain(account.credentials.keychain, discoveredKeychain)
               }) {
                if registry.accounts[index].credentials.configDir == nil {
                    registry.accounts[index].credentials.configDir = item.credentials.configDir
                }
                continue
            }

            if item.sourceKind == .claudeOAuth,
               let discoveredConfig = item.credentials.configDir {
                let normalized = AccountValidation.normalizePath(discoveredConfig, home: home)
                if let index = registry.accounts.firstIndex(where: { account in
                    account.sourceKind == .claudeOAuth
                        && account.credentials.configDir.map {
                            AccountValidation.normalizePath($0, home: home) == normalized
                        } == true
                }) {
                    if registry.accounts[index].credentials.keychain == nil,
                       let discoveredKeychain = item.credentials.keychain {
                        registry.accounts[index].credentials.keychain = discoveredKeychain
                    }
                    continue
                }
            }

            registry.accounts.append(Account(
                id: "acc_\(UUID().uuidString)",
                label: item.label,
                sourceKind: item.sourceKind,
                pinned: false,
                credentials: item.credentials
            ))
        }
    }

    /// Drop Keychain-only rows whose credentials disappeared, and clear dead
    /// Keychain refs on accounts that still have a config directory.
    private static func pruneStaleKeychainAccounts(
        _ discovered: [DiscoveredAccount],
        from registry: inout AccountRegistry,
        now: Date
    ) {
        let liveKeychains = Set(
            discovered.compactMap { item -> String? in
                item.credentials.keychain.map(fingerprint(for:))
            }
        )

        var index = 0
        while index < registry.accounts.count {
            let account = registry.accounts[index]
            guard account.sourceKind == .claudeOAuth,
                  let keychain = account.credentials.keychain
            else {
                index += 1
                continue
            }
            if liveKeychains.contains(fingerprint(for: keychain)) {
                index += 1
                continue
            }

            let hasConfig = account.credentials.configDir.map {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false

            if hasConfig {
                registry.accounts[index].credentials.keychain = nil
                index += 1
            } else {
                try? AccountSelection.deleteAccount(id: account.id, now: now, in: &registry)
            }
        }
    }

    private static func fingerprint(for keychain: KeychainReference) -> String {
        let service = keychain.service.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = keychain.account?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(service)\0\(account)"
    }

    private static func sameKeychain(
        _ lhs: KeychainReference?,
        _ rhs: KeychainReference
    ) -> Bool {
        guard let lhs else { return false }
        return fingerprint(for: lhs) == fingerprint(for: rhs)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    @State private var isDiscovering = false
    @State private var customLabel = ""
    @State private var customConfigDirectory = "~/.claude"
    @State private var customService = ClaudeOAuthSource.genericKeychainService
    @State private var customKeychainAccount = ""
    @State private var editingAccount: Account?
    @State private var deleteCandidate: Account?
    @State private var pendingStubPin: Account?
    @State private var deleteUsageFile = false
    @State private var accessMessage: String?

    var body: some View {
        Form {
            bootstrapSection
            if let registry = model.registry {
                accountsSection(registry)
                discoverySection
                customClaudeSection
                placeholdersSection
                rotationSection(registry)
                helpersSection
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 720, minHeight: 620)
        .sheet(item: $editingAccount) { account in
            EditAccountView(account: account) { label, config, service, keychainAccount in
                await update(
                    account,
                    label: label,
                    config: config,
                    service: service,
                    keychainAccount: keychainAccount
                )
            }
        }
        .sheet(item: $deleteCandidate) { account in
            DeleteAccountView(
                account: account,
                deleteUsageFile: $deleteUsageFile,
                onDelete: { await delete(account) }
            )
        }
        .confirmationDialog(
            "Pin an unfinished source?",
            isPresented: Binding(
                get: { pendingStubPin != nil },
                set: { if !$0 { pendingStubPin = nil } }
            ),
            presenting: pendingStubPin
        ) { account in
            Button("Pin \(account.label)") {
                Task { await setPinned(account, true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This source is a placeholder and cannot collect usage yet.")
        }
        .alert(
            "Keychain access",
            isPresented: Binding(
                get: { accessMessage != nil },
                set: { if !$0 { accessMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accessMessage ?? "")
        }
    }

    private var bootstrapSection: some View {
        Section("Account registry") {
            if model.isBootstrapping {
                ProgressView("Discovering accounts and preparing the registry…")
            } else if let error = model.bootstrapError {
                Label("Registry unavailable", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error).textSelection(.enabled)
                Text("The malformed or unsupported registry remains untouched. Destructive actions are disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let registry = model.registry {
                LabeledContent("Revision", value: "\(registry.revision)")
                Text(AccountStore.url().path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let error = model.actionError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func accountsSection(_ registry: AccountRegistry) -> some View {
        Section("Accounts") {
            if registry.accounts.isEmpty {
                Text("No accounts configured. Discover or add one below.")
                    .foregroundStyle(.secondary)
            }
            ForEach(registry.accounts) { account in
                AccountRow(
                    account: account,
                    isSelected: registry.prefs.selectedAccountId == account.id,
                    sourceHealth: sourceHealth(account),
                    usageHealth: usageHealth(account),
                    onSelect: { Task { await select(account) } },
                    onSetPinned: { pinned in requestPin(account, pinned) },
                    onEdit: { editingAccount = account },
                    onDelete: {
                        deleteUsageFile = false
                        deleteCandidate = account
                    },
                    onTestAccess: { Task { await testAccess(account) } }
                )
            }
        }
        .disabled(!model.canMutateRegistry)
    }

    private var discoverySection: some View {
        Section("Discovery") {
            Button {
                Task { await refreshDiscovery() }
            } label: {
                if isDiscovering {
                    ProgressView()
                } else {
                    Label("Refresh Claude accounts", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isDiscovering || !model.canMutateRegistry)
            Text("Discovery reads Keychain attributes only and does not request credential data.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var customClaudeSection: some View {
        Section("Add custom Claude account") {
            TextField("Label", text: $customLabel)
            TextField("Config directory", text: $customConfigDirectory)
            TextField("Keychain service", text: $customService)
            TextField("Keychain account (optional)", text: $customKeychainAccount)
            Button("Add Claude account") {
                Task { await addClaude() }
            }
            .disabled(customLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .disabled(!model.canMutateRegistry)
    }

    private var placeholdersSection: some View {
        Section("Coming soon") {
            Text("API sources are created unpinned until their collectors are available.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Add OpenAI placeholder") {
                    Task { await addStub(kind: .openAIAPI, label: "OpenAI") }
                }
                Button("Add Anthropic placeholder") {
                    Task { await addStub(kind: .anthropicAPI, label: "Anthropic API") }
                }
            }
        }
        .disabled(!model.canMutateRegistry)
    }

    private func rotationSection(_ registry: AccountRegistry) -> some View {
        Section("Widget rotation") {
            Toggle(
                "Rotate pinned accounts",
                isOn: Binding(
                    get: { registry.prefs.rotateEnabled },
                    set: { value in
                        Task {
                            await model.mutate {
                                $0.prefs.rotateEnabled = value
                                $0.prefs.rotationAnchorAt = Date().timeIntervalSince1970
                            }
                        }
                    }
                )
            )
            LabeledContent("Interval (seconds)") {
                TextField(
                    "Seconds",
                    value: Binding(
                        get: { registry.prefs.rotateIntervalSec },
                        set: { value in
                            let clamped = min(86_400, max(300, value))
                            Task {
                                await model.mutate {
                                    $0.prefs.rotateIntervalSec = clamped
                                    $0.prefs.rotationAnchorAt = Date().timeIntervalSince1970
                                }
                            }
                        }
                    ),
                    format: .number
                )
                .frame(width: 100)
            }
            Text("Allowed range: 300–86,400 seconds.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!model.canMutateRegistry)
    }

    private var helpersSection: some View {
        Section("Helper installation") {
            let diagnostics = HelperSetup.diagnostics()
            LabeledContent(
                "LaunchAgent",
                value: diagnostics.launchAgentInstalled ? "Installed" : "Not installed"
            )
            LabeledContent(
                "Installed helper directory",
                value: diagnostics.installedDirectoryExists ? "Present" : "Missing"
            )
            Text(diagnostics.installedDirectory)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            LabeledContent(
                "Bundled helpers",
                value: diagnostics.bundledHelpersAvailable ? "Available" : "Missing"
            )
            LabeledContent(
                "Installed helper binary",
                value: diagnostics.helperBinaryAvailable ? "Present" : "Missing"
            )
            LabeledContent(
                "Legacy usage file",
                value: diagnostics.hasLegacyUsageWarning ? "Needs attention" : "Clear"
            )
            if diagnostics.hasLegacyUsageWarning {
                Text("A legacy usage file remains after registry creation. Re-run helper setup after resolving or archiving it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if model.helpersNeedReconfiguration {
                Label(
                    "Helper inputs changed. Reconfigure helpers to update installed statuslines and polling.",
                    systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                )
                    .foregroundStyle(.orange)
            }
            Button(diagnostics.launchAgentInstalled ? "Reconfigure helpers" : "Set up helpers") {
                Task { await model.runHelperSetup() }
            }
            .disabled(model.isSettingUpHelpers || !model.canMutateRegistry)
            if let output = model.setupOutput {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    private func refreshDiscovery() async {
        isDiscovering = true
        defer { isDiscovering = false }
        do {
            let descriptors = try await KeychainDiscovery.discover()
            let discovered = ClaudeOAuthSource().discover(
                home: FileManager.default.homeDirectoryForCurrentUser,
                keychainItems: descriptors
            )
            await mergeDiscovered(discovered)
        } catch {
            model.actionError = error.localizedDescription
        }
    }

    private func mergeDiscovered(_ discovered: [DiscoveredAccount]) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        _ = await model.mutate { registry in
            DiscoveredAccountMerge.merge(discovered, into: &registry, home: home)
        }
    }

    private func addClaude() async {
        let label = customLabel
        let config = optional(customConfigDirectory)
        let service = optional(customService)
        let keychainAccount = optional(customKeychainAccount)
        let account = Account(
            id: "acc_\(UUID().uuidString)",
            label: label,
            sourceKind: .claudeOAuth,
            pinned: false,
            credentials: AccountCredentials(
                configDir: config,
                keychain: service.map {
                    KeychainReference(service: $0, account: keychainAccount)
                }
            )
        )
        let added = await model.mutate { registry in
            registry.accounts.append(account)
        }
        if added {
            customLabel = ""
            customKeychainAccount = ""
        }
    }

    private func addStub(kind: SourceKind, label: String) async {
        let account = Account(
            id: "acc_\(UUID().uuidString)",
            label: label,
            sourceKind: kind,
            pinned: false,
            credentials: AccountCredentials()
        )
        _ = await model.mutate { $0.accounts.append(account) }
    }

    private func select(_ account: Account) async {
        _ = await model.mutate {
            try AccountSelection.select(id: account.id, now: Date(), in: &$0)
        }
    }

    private func requestPin(_ account: Account, _ pinned: Bool) {
        if pinned, account.sourceKind != .claudeOAuth {
            pendingStubPin = account
        } else {
            Task { await setPinned(account, pinned) }
        }
    }

    private func setPinned(_ account: Account, _ pinned: Bool) async {
        pendingStubPin = nil
        _ = await model.mutate {
            try AccountSelection.setPinned(id: account.id, pinned: pinned, now: Date(), in: &$0)
        }
    }

    private func update(
        _ account: Account,
        label: String,
        config: String,
        service: String,
        keychainAccount: String
    ) async -> Bool {
        let normalizedConfig = optional(config)
        let normalizedService = optional(service)
        let normalizedAccount = optional(keychainAccount)
        return await model.mutate { registry in
            guard let index = registry.accounts.firstIndex(where: { $0.id == account.id }) else {
                return
            }
            registry.accounts[index].label = label
            if account.sourceKind == .claudeOAuth {
                registry.accounts[index].credentials.configDir = normalizedConfig
                registry.accounts[index].credentials.keychain = normalizedService.map {
                    KeychainReference(service: $0, account: normalizedAccount)
                }
            }
        }
    }

    private func delete(_ account: Account) async -> Bool {
        let shouldDeleteUsage = deleteUsageFile
        let deleted = await model.mutate {
            try AccountSelection.deleteAccount(id: account.id, now: Date(), in: &$0)
        }
        if deleted, shouldDeleteUsage, let url = try? UsageStore.usageURL(accountId: account.id) {
            try? await Task.detached {
                try FileManager.default.removeItem(at: url)
            }.value
        }
        if deleted { deleteCandidate = nil }
        return deleted
    }

    private func testAccess(_ account: Account) async {
        guard let reference = account.credentials.keychain else {
            accessMessage = "This account has no Keychain reference."
            return
        }
        accessMessage = await KeychainDiscovery.testAccess(
            service: reference.service,
            account: reference.account
        ).message
    }

    private func sourceHealth(_ account: Account) -> String {
        guard let source = SourceCatalog.adapter(for: account.sourceKind) else { return "Unsupported source" }
        switch source.validate(account, fileSystem: LocalSourceFileSystem()) {
        case .ready: return "Ready"
        case .statuslineOnly(let reason): return "Statusline only — \(reason)"
        case .pollerOnly(let reason): return "Poller only — \(reason)"
        case .unavailable(let reason): return "Unavailable — \(reason)"
        case .comingSoon: return "Coming soon"
        }
    }

    private func usageHealth(_ account: Account) -> String {
        switch UsageStore.load(accountId: account.id) {
        case .missing: return "No usage file"
        case .unreadable: return "Usage file unreadable"
        case .record(let record): return record.windows.isEmpty ? "No usage windows" : "Usage available"
        }
    }

    private func optional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct AccountRow: View {
    let account: Account
    let isSelected: Bool
    let sourceHealth: String
    let usageHealth: String
    let onSelect: () -> Void
    let onSetPinned: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onTestAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(account.label).font(.headline)
                    Text(sourceLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Pinned",
                    isOn: Binding(
                        get: { account.pinned },
                        set: { value in onSetPinned(value) }
                    )
                )
                    .toggleStyle(.checkbox)
                Button(isSelected ? "Selected" : "Select", action: onSelect)
                    .disabled(isSelected || !account.pinned)
            }
            Text(connectionSummary)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            LabeledContent("Source health", value: sourceHealth)
            LabeledContent("Usage health", value: usageHealth)
            HStack {
                Button("Rename / edit", action: onEdit)
                if account.credentials.keychain != nil {
                    Button("Test access", action: onTestAccess)
                }
                Spacer()
                Button("Delete…", role: .destructive, action: onDelete)
            }
        }
        .padding(.vertical, 4)
    }

    private var sourceLabel: String {
        switch account.sourceKind {
        case .claudeOAuth: "Claude OAuth"
        case .openAIAPI: "OpenAI API"
        case .anthropicAPI: "Anthropic API"
        default: account.sourceKind.rawValue
        }
    }

    private var connectionSummary: String {
        let config = account.credentials.configDir ?? "no config directory"
        let keychain = account.credentials.keychain.map {
            "\($0.service) / \($0.account ?? "any account")"
        } ?? "no Keychain reference"
        return "\(config) · \(keychain)"
    }
}

private struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account
    let onSave: (String, String, String, String) async -> Bool

    @State private var label: String
    @State private var config: String
    @State private var service: String
    @State private var keychainAccount: String
    @State private var isSaving = false

    init(
        account: Account,
        onSave: @escaping (String, String, String, String) async -> Bool
    ) {
        self.account = account
        self.onSave = onSave
        _label = State(initialValue: account.label)
        _config = State(initialValue: account.credentials.configDir ?? "")
        _service = State(initialValue: account.credentials.keychain?.service ?? "")
        _keychainAccount = State(initialValue: account.credentials.keychain?.account ?? "")
    }

    var body: some View {
        Form {
            TextField("Label", text: $label)
            if account.sourceKind == .claudeOAuth {
                TextField("Config directory", text: $config)
                TextField("Keychain service", text: $service)
                TextField("Keychain account", text: $keychainAccount)
                Text("Saving changes never reads or modifies the credential itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    isSaving = true
                    Task {
                        if await onSave(label, config, service, keychainAccount) {
                            dismiss()
                        }
                        isSaving = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
        .padding()
        .frame(width: 480)
    }
}

private struct DeleteAccountView: View {
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @Binding var deleteUsageFile: Bool
    let onDelete: () async -> Bool
    @State private var isDeleting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(account.label)?").font(.headline)
            Text("The account registry entry will be removed. Claude credentials are never deleted.")
            Toggle("Also delete this account’s usage file", isOn: $deleteUsageFile)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Delete", role: .destructive) {
                    isDeleting = true
                    Task {
                        if await onDelete() { dismiss() }
                        isDeleting = false
                    }
                }
                .disabled(isDeleting)
            }
        }
        .padding()
        .frame(width: 440)
    }
}

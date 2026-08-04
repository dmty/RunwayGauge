import SwiftUI
import UsageCore

struct StatusView: View {
    private let url = UsageStore.url(source: "claude-code")

    @State private var isInstalled = HelperSetup.isInstalled()
    @State private var setupOutput: String?
    @State private var setupOutcome: SetupOutcome?
    @State private var isRunning = false

    private var now: Date { Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Runway Gauge").font(.headline)

            Text("Add widgets from Notification Center → Edit Widgets.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Data file").font(.caption).bold()
                Text(url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Text(statusLine).font(.callout)
            }

            Text("Refresh this window to re-check.")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Divider()

            Button {
                isRunning = true
                setupOutput = nil
                setupOutcome = nil
                Task {
                    let result = await HelperSetup.runSetup()
                    setupOutcome = Self.outcome(from: result)
                    setupOutput = result.output
                    isInstalled = HelperSetup.isInstalled()
                    isRunning = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Label(
                        isInstalled ? "Re-run setup" : "Set up data collection",
                        systemImage: "gearshape"
                    )
                }
            }
            .disabled(isRunning)

            if let setupOutcome {
                Text(setupOutcome.label)
                    .font(.caption)
                    .foregroundStyle(setupOutcome.color)
            }

            if let setupOutput {
                ScrollView {
                    Text(setupOutput)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(24)
        .frame(width: 500, alignment: .leading)
        .onAppear {
            isInstalled = HelperSetup.isInstalled()
        }
    }

    private var statusLine: String {
        let now = self.now
        switch UsageStore.state(for: UsageStore.load(from: url), now: now, path: url.path) {
        case .empty:
            return "No usage data yet — start a Claude Code session."
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

    private enum SetupOutcome {
        case success, partial, failure

        var label: String {
            switch self {
            case .success: "Setup succeeded"
            case .partial: "Setup partially failed"
            case .failure: "Setup failed"
            }
        }

        var color: Color {
            switch self {
            case .success: .green
            case .partial: .orange
            case .failure: .red
            }
        }
    }

    private static func outcome(from result: SetupResult) -> SetupOutcome {
        if result.succeeded { return .success }
        if result.output.contains("partially failed") { return .partial }
        return .failure
    }
}

@main
struct RunwayGaugeApp: App {
    var body: some Scene {
        WindowGroup("Runway Gauge") {
            StatusView()
        }
        .windowResizability(.contentSize)
    }
}

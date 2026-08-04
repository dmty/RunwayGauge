import SwiftUI

@main
struct MacUsageWidgetApp: App {
    var body: some Scene {
        WindowGroup("Usage Widget") {
            VStack(spacing: 8) {
                Text("Usage Widget").font(.headline)
                Text("Widgets are added from Notification Center → Edit Widgets.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(width: 360)
        }
        .windowResizability(.contentSize)
    }
}

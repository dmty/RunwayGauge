import Foundation
import Testing
@testable import RunwayGauge

@Suite("HelperSetupTests")
struct HelperSetupTests {
    private struct Fixture {
        let home: URL
        let bundled: URL
        let installed: URL

        init() throws {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "RunwayGauge-HelperSetupTests-\(UUID().uuidString)")
            home = root.appending(path: "home")
            bundled = root.appending(path: "bundle/Helpers")
            installed = root.appending(path: "installed/helpers")
            for dir in [bundled.appending(path: "lib"), installed.appending(path: "lib")] {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            try write("binary-v2", to: "runwaygauge-helper", in: bundled, executable: true)
            try write("lib-v1", to: "lib/paths.sh", in: bundled)
        }

        func write(_ text: String, to path: String, in dir: URL, executable: Bool = false) throws {
            let url = dir.appending(path: path)
            try Data(text.utf8).write(to: url)
            if executable {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
        }

        func installLaunchAgent() throws {
            let agents = home.appending(path: "Library/LaunchAgents")
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            try Data().write(to: agents.appending(path: "com.mirabilia.runwaygauge.claudeusage.plist"))
        }

        func outdated() -> Bool {
            HelperSetup.installedHelpersOutdated(
                bundled: bundled,
                installed: installed,
                homeDirectoryURL: home
            )
        }
    }

    @Test("stale installed helper binary is outdated")
    func staleBinary() throws {
        let f = try Fixture()
        try f.installLaunchAgent()
        try f.write("binary-v1", to: "runwaygauge-helper", in: f.installed, executable: true)
        try f.write("lib-v1", to: "lib/paths.sh", in: f.installed)
        #expect(f.outdated())
    }

    @Test("stale installed script is outdated")
    func staleScript() throws {
        let f = try Fixture()
        try f.installLaunchAgent()
        try f.write("binary-v2", to: "runwaygauge-helper", in: f.installed, executable: true)
        try f.write("lib-v0", to: "lib/paths.sh", in: f.installed)
        #expect(f.outdated())
    }

    @Test("matching install is current")
    func matching() throws {
        let f = try Fixture()
        try f.installLaunchAgent()
        try f.write("binary-v2", to: "runwaygauge-helper", in: f.installed, executable: true)
        try f.write("lib-v1", to: "lib/paths.sh", in: f.installed)
        #expect(!f.outdated())
    }

    @Test("never set up is left alone")
    func notSetUp() throws {
        let f = try Fixture()
        #expect(!f.outdated())
    }
}

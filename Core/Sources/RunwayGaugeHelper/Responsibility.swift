import Darwin
import Foundation

/// macOS charges container access to the responsible process, not the caller. Run from a
/// statusline that is the terminal or editor hosting Claude Code, so each write into the
/// widget container raised an "access data from other apps" prompt in that app's name.
/// Disclaimed, the helper answers for itself and shares the widget's team signature.
enum Responsibility {
    private static let marker = "RUNWAYGAUGE_DISCLAIMED"
    private typealias SetDisclaim = @convention(c) (
        UnsafeMutablePointer<posix_spawnattr_t?>, Int32
    ) -> Int32

    /// Replaces this process with a disclaimed copy of itself. Returns only when that
    /// already happened or could not be done; callers carry on either way.
    static func disclaim() {
        guard getenv(marker) == nil,
              let path = Bundle.main.executablePath,
              // Private SPI, so resolved at runtime: RTLD_DEFAULT.
              let symbol = dlsym(
                  UnsafeMutableRawPointer(bitPattern: -2), "responsibility_spawnattrs_setdisclaim"
              )
        else { return }

        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else { return }
        defer { posix_spawnattr_destroy(&attr) }
        guard posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETEXEC)) == 0,
              unsafeBitCast(symbol, to: SetDisclaim.self)(&attr, 1) == 0
        else { return }

        var environment = ProcessInfo.processInfo.environment
        environment[marker] = "1"
        let envp = environment.map { strdup("\($0)=\($1)") } + [nil]
        posix_spawn(nil, path, nil, &attr, CommandLine.unsafeArgv, envp)
    }
}

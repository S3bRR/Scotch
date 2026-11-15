import Foundation
import Darwin

/// Prevents two Scotch processes from replacing the same runtime concurrently.
public final class InstallationLock {
    private var descriptor: Int32 = -1
    public init(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let opened = Darwin.open(url.path, O_CREAT | O_RDWR, 0o600)
        guard opened >= 0 else { throw UpdateActivityError.busy("Unable to open the runtime installation lock.") }
        var record = flock(l_start: 0, l_len: 0, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        guard fcntl(opened, F_SETLK, &record) != -1 else {
            Darwin.close(opened)
            throw UpdateActivityError.busy("Another Scotch process is installing a runtime.")
        }
        descriptor = opened
    }
    deinit { if descriptor >= 0 { Darwin.close(descriptor) } }
}

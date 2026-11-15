import Foundation
import Darwin

/// Read only executable names for global idle checks. Prefix ownership is read
/// from a suspected Wine process's kernel environment without exposing argv or
/// any other environment value to logs or callers.
public enum WineProcessInspector {
    private static func candidates() -> [(pid_t, String)]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
                let fields = line.trimmingCharacters(in: .whitespaces).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                guard fields.count == 2, let pid = pid_t(fields[0]), pid != getpid() else { return nil }
                let name = String(fields[1]).trimmingCharacters(in: .whitespaces)
                let leaf = URL(fileURLWithPath: name).lastPathComponent.lowercased()
                let windows = leaf.hasSuffix(".exe")
                guard windows || leaf == "scotchcmd" || leaf == "wine" || leaf == "wine64" || leaf.hasPrefix("wine64-") || leaf.hasPrefix("wineserver") || leaf == "wine-preloader" else { return nil }
                return (pid, name)
            }
        } catch { return nil }
    }
    public static var hasWineProcesses: Bool {
        guard let processes = candidates() else { return true }
        return processes.contains { _, name in
            let leaf = URL(fileURLWithPath: name.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
            // A live device host has a wineserver, which is checked separately.
            // Rosetta can leave an orphan device host after that server exits;
            // it has no Windows application session to protect or terminate.
            return leaf != "winedevice.exe"
        }
    }

    private static func prefix(of pid: pid_t) -> String? {
        var argmax: Int32 = 0, size = MemoryLayout<Int32>.size
        var maximum = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&maximum, 2, &argmax, &size, nil, 0) == 0, argmax > 0, argmax < 4_194_304 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(argmax))
        var query = [CTL_KERN, KERN_PROCARGS2, pid]
        size = bytes.count
        guard sysctl(&query, 3, &bytes, &size, nil, 0) == 0, size > 4 else { return nil }
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc >= 0, argc < 65536 else { return nil }
        var cursor = 4
        func skipString() { while cursor < size && bytes[cursor] != 0 { cursor += 1 }; if cursor < size { cursor += 1 } }
        skipString() // kernel executable path
        while cursor < size && bytes[cursor] == 0 { cursor += 1 }
        for _ in 0..<argc { skipString() }
        while cursor < size {
            if bytes[cursor] == 0 { cursor += 1; continue }
            let start = cursor
            while cursor < size && bytes[cursor] != 0 { cursor += 1 }
            let key = Array("WINEPREFIX=".utf8)
            if cursor - start >= key.count, bytes[start..<start + key.count].elementsEqual(key) {
                return String(bytes: bytes[start + key.count..<cursor], encoding: .utf8)
            }
            cursor += 1
        }
        return nil
    }
    private static func ownedPIDs(in bottle: URL) -> [pid_t] {
        let expected = bottle.resolvingSymlinksInPath().standardizedFileURL.path
        return (candidates() ?? []).compactMap { pid, name in
            guard URL(fileURLWithPath: name).lastPathComponent.lowercased() != "scotchcmd" else { return nil }
            guard let value = prefix(of: pid), value.hasPrefix("/"),
                  URL(fileURLWithPath: value).resolvingSymlinksInPath().standardizedFileURL.path == expected else { return nil }
            return pid
        }
    }
    /// Called only by the existing explicit Stop Bottle path, after wineserver
    /// shutdown. Orphaned Wine/CEF processes can otherwise survive it and keep
    /// a stale black window or Steam singleton alive. Never signal by name.
    public static func stopRemainingProcesses(in bottle: URL) async {
        for pid in ownedPIDs(in: bottle) { _ = kill(pid, SIGTERM) }
        for _ in 0..<20 {
            if ownedPIDs(in: bottle).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        // Re-read ownership immediately before escalation to avoid stale PIDs.
        for pid in ownedPIDs(in: bottle) { _ = kill(pid, SIGKILL) }
    }
}

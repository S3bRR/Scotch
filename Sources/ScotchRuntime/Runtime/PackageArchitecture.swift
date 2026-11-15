import Foundation
import ScotchDomain

/// Archive hashes establish identity; these checks also catch an approved asset
/// that accidentally contains Linux/ARM DLLs or the wrong Windows bitness.
enum PackageArchitecture {
    static func windowsDLLs(in directory: URL, machine: UInt16) throws {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        var count = 0
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension.lowercased() == "dll" else { continue }
            try verifyPE(at: file, machine: machine)
            count += 1
        }
        guard count > 0 else { throw RuntimeInstallerError.installFailed("No Windows DLLs in approved runtime package") }
    }
    static func verifyPE(at file: URL, machine: UInt16) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 64) ?? Data()
        guard header.count == 64, header[0] == 0x4d, header[1] == 0x5a else { throw invalid(file) }
        let offset = header[60..<64].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
        guard offset < 64 * 1024 * 1024 else { throw invalid(file) }
        try handle.seek(toOffset: UInt64(offset))
        let pe = try handle.read(upToCount: 6) ?? Data()
        guard pe.count == 6, Array(pe.prefix(4)) == [0x50, 0x45, 0, 0], UInt16(pe[4]) | (UInt16(pe[5]) << 8) == machine else { throw invalid(file) }
    }
    private static func invalid(_ file: URL) -> RuntimeInstallerError { .installFailed("Wrong architecture or invalid Windows DLL: \(file.lastPathComponent)") }
}

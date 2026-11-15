import Foundation
import CryptoKit
import ScotchDomain

/// Bounded PE inspection, including delay imports and adjacent DLLs. No code is
/// executed and no system directory, Steam library or unrelated folder is scanned.
public enum ExecutableGraphicsInspector {
    public static func inspect(_ executable: URL) -> ExecutableGraphicsAnalysis {
        var result = ExecutableGraphicsAnalysis(architecture: .unknown, apis: [], imports: [], fingerprint: "", limited: false, explanation: "")
        do {
            let root = executable.resolvingSymlinksInPath().deletingLastPathComponent()
            var queue: [(URL, Int)] = [(executable, 0)]
            var seen = Set<String>(), imports = Set<String>(), bytes = 0
            var digest = SHA256()
            while !queue.isEmpty {
                let (file, depth) = queue.removeFirst()
                let canonical = file.resolvingSymlinksInPath()
                guard seen.insert(canonical.path.lowercased()).inserted else { continue }
                guard seen.count <= 48 else { result.limited = true; break }
                let size = try canonical.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 64 * 1024 * 1024, bytes + size <= 128 * 1024 * 1024 else {
                    result.limited = true
                    if depth == 0 { throw InspectionError.invalid }
                    continue
                }
                let data = try Data(contentsOf: canonical, options: .mappedIfSafe)
                bytes += data.count
                digest.update(data: Data(canonical.lastPathComponent.lowercased().utf8)); digest.update(data: data)
                let pe: PE
                do { pe = try PE(data: data) }
                catch { if depth == 0 { throw error }; result.limited = true; continue }
                if depth == 0 { result.architecture = pe.architecture }
                let names = try pe.imports()
                imports.formUnion(names)
                let entries = try FileManager.default.contentsOfDirectory(at: canonical.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                if entries.count > 5000 { result.limited = true; continue }
                let index = Dictionary(entries.map { ($0.lastPathComponent.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
                for name in names.sorted() {
                    guard let local = index[name] else {
                        if !isPlatformModule(name) { result.limited = true }
                        continue
                    }
                    let resolved = local.resolvingSymlinksInPath()
                    guard resolved.path.hasPrefix(root.path + "/") else { result.limited = true; continue }
                    // App-supplied API wrappers may implement their own routing.
                    if api(for: name) != nil { result.limited = true }
                    if depth < 3 { queue.append((resolved, depth + 1)) }
                    else if !seen.contains(resolved.path.lowercased()) { result.limited = true }
                }
            }
            result.imports = imports.sorted()
            result.apis = Set(imports.compactMap(api))
            result.fingerprint = digest.finalize().map { String(format: "%02x", $0) }.joined()
            result.explanation = result.apis.isEmpty ? "No graphics API was identified in the executable's imports." : "Detected " + result.apis.map(\.rawValue).sorted().joined(separator: ", ") + " in executable/DLL imports."
            if result.limited { result.explanation += " Inspection was incomplete or found an application-supplied graphics wrapper." }
        } catch {
            result.limited = true
            result.explanation = "This file could not be fully inspected as a supported Windows executable. Keep the bottle setting."
        }
        return result
    }

    private static func api(for module: String) -> GraphicsAPI? {
        switch module {
        case "d3d9.dll": .d3d9
        case "d3d10.dll", "d3d10_1.dll", "d3d10core.dll": .d3d10
        case "d3d11.dll": .d3d11
        case "d3d12.dll", "d3d12core.dll": .d3d12
        case "opengl32.dll", "libgallium_wgl.dll": .openGL
        case "vulkan-1.dll": .vulkan
        default: nil
        }
    }

    private static func isPlatformModule(_ name: String) -> Bool {
        if api(for: name) != nil || name.hasPrefix("api-ms-win-") || name.hasPrefix("ext-ms-win-") { return true }
        return Set(["ntdll.dll", "kernel32.dll", "kernelbase.dll", "user32.dll", "gdi32.dll", "gdi32full.dll", "msvcrt.dll", "ucrtbase.dll", "advapi32.dll", "sechost.dll", "ole32.dll", "oleaut32.dll", "combase.dll", "shell32.dll", "shlwapi.dll", "comdlg32.dll", "comctl32.dll", "version.dll", "winmm.dll", "winspool.drv", "imm32.dll", "setupapi.dll", "cfgmgr32.dll", "rpcrt4.dll", "ws2_32.dll", "winhttp.dll", "wininet.dll", "crypt32.dll", "bcrypt.dll", "ncrypt.dll", "secur32.dll", "normaliz.dll", "userenv.dll", "uxtheme.dll", "dwmapi.dll", "dwrite.dll", "d2d1.dll", "dxgi.dll", "d3dcompiler_47.dll", "dinput8.dll", "xinput1_4.dll", "xinput1_3.dll"]).contains(name)
    }

    private enum InspectionError: Error { case invalid }
    private struct PE {
        let data: Data
        let optional: Int
        let directories: Int
        let sectionTable: Int
        let sectionCount: Int
        let directoryCount: Int
        let architecture: WindowsArchitecture
        init(data: Data) throws {
            self.data = data
            guard data.count >= 64, data[0] == 0x4d, data[1] == 0x5a else { throw InspectionError.invalid }
            let pe = Int(try Self.uint(data, 60, 4))
            guard try Self.uint(data, pe, 4) == 0x4550 else { throw InspectionError.invalid }
            let machine = try Self.uint(data, pe + 4, 2)
            architecture = machine == 0x8664 ? .x64 : machine == 0x14c ? .x86 : .unsupported
            sectionCount = Int(try Self.uint(data, pe + 6, 2))
            let optionalSize = Int(try Self.uint(data, pe + 20, 2))
            optional = pe + 24
            let magic = try Self.uint(data, optional, 2)
            guard [0x10b, 0x20b].contains(magic), sectionCount <= 96 else { throw InspectionError.invalid }
            guard machine != 0x8664 || magic == 0x20b, machine != 0x14c || magic == 0x10b else { throw InspectionError.invalid }
            directories = optional + (magic == 0x20b ? 112 : 96)
            directoryCount = Int(try Self.uint(data, optional + (magic == 0x20b ? 108 : 92), 4))
            sectionTable = optional + optionalSize
            guard directoryCount <= 16, directories + directoryCount * 8 <= sectionTable, sectionTable + sectionCount * 40 <= data.count else { throw InspectionError.invalid }
        }
        static func uint(_ data: Data, _ offset: Int, _ count: Int) throws -> UInt32 {
            guard offset >= 0, count <= 4, offset <= data.count - count else { throw InspectionError.invalid }
            return (0..<count).reduce(0) { $0 | UInt32(data[offset + $1]) << (8 * $1) }
        }
        func u(_ offset: Int, _ count: Int = 4) throws -> UInt32 { try Self.uint(data, offset, count) }
        func fileOffset(_ rva: UInt32) throws -> Int {
            if rva < (try u(optional + 60)), Int(rva) < data.count { return Int(rva) }
            for i in 0..<sectionCount {
                let section = sectionTable + i * 40
                let address = try u(section + 12), rawSize = try u(section + 16)
                if rva >= address, UInt64(rva) < UInt64(address) + UInt64(rawSize) {
                    let offset = UInt64(try u(section + 20)) + UInt64(rva - address)
                    guard offset < data.count else { throw InspectionError.invalid }
                    return Int(offset)
                }
            }
            throw InspectionError.invalid
        }
        func imports() throws -> Set<String> {
            var names = Set<String>()
            for (index, stride, nameField) in [(1, 20, 12), (13, 32, 4)] {
                guard index < directoryCount else { continue }
                let rva = try u(directories + index * 8), size = try u(directories + index * 8 + 4)
                guard rva != 0, size != 0 else { continue }
                let start = try fileOffset(rva)
                let count = min(Int(size) / stride, 1024)
                guard count > 0 else { throw InspectionError.invalid }
                var terminated = false
                for i in 0..<count {
                    let entry = start + i * stride
                    let name = try u(entry + nameField)
                    if name == 0 { terminated = true; break }
                    if index == 13, try u(entry) & 1 == 0 { throw InspectionError.invalid }
                    let offset = try fileOffset(name)
                    guard let end = data[offset..<min(data.count, offset + 260)].firstIndex(of: 0),
                          let module = String(data: data[offset..<end], encoding: .ascii),
                          !module.contains("/"), !module.contains("\\"), !module.isEmpty else { throw InspectionError.invalid }
                    names.insert(module.lowercased())
                }
                guard terminated else { throw InspectionError.invalid }
            }
            return names
        }
    }
}

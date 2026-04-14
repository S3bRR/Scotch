import Foundation

extension FileHandle {
    func extract<T>(_ type: T.Type, offset: UInt64 = 0) -> T? {
        do {
            try self.seek(toOffset: offset)
            if let data = try self.read(upToCount: MemoryLayout<T>.size) {
                return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
            }
            return nil
        } catch {
            return nil
        }
    }
}

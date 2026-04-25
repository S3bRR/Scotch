import Foundation

extension FileHandle {
    func extract<T>(_ type: T.Type, offset: UInt64 = 0) -> T? {
        do {
            try self.seek(toOffset: offset)
            guard let data = try self.read(upToCount: MemoryLayout<T>.size),
                  data.count == MemoryLayout<T>.size else {
                return nil
            }
            return data.withUnsafeBytes { $0.loadUnaligned(as: T.self) }
        } catch {
            return nil
        }
    }
}

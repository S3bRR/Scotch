import Foundation
import CryptoKit

enum SHA256Checksum {
    static func parse(_ manifest: String, targetFileName: String) -> String? {
        let targetCandidates = targetFileCandidates(for: targetFileName)

        for rawLine in manifest.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Common format: SHA256 (file.tar.gz) = <hash>
            if line.uppercased().hasPrefix("SHA256"),
               let open = line.firstIndex(of: "("),
               let close = line[open...].firstIndex(of: ")"),
               let equals = line[close...].firstIndex(of: "=") {
                let fileName = line[line.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
                let hash = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
                if targetCandidates.contains(normalizeFileName(fileName)),
                   let normalized = normalizeHash(hash) {
                    return normalized
                }
            }

            // Common format: <hash>  file.tar.gz
            let tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if tokens.count == 1 {
                if let normalized = normalizeHash(tokens[0]) {
                    return normalized
                }
                continue
            }

            if let hash = normalizeHash(tokens[0]) {
                let fileTokens = tokens.dropFirst()
                for token in fileTokens {
                    if targetCandidates.contains(normalizeFileName(token)) {
                        return hash
                    }
                }
            }
        }

        return nil
    }

    static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var digest = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty {
                break
            }
            digest.update(data: chunk)
        }

        let result = digest.finalize()
        return result.map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizeHash(_ value: String) -> String? {
        let cleaned = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter(\.isHexDigit)
        guard cleaned.count == 64 else {
            return nil
        }
        return cleaned
    }

    private static func targetFileCandidates(for pathLike: String) -> Set<String> {
        let full = normalizeFileName(pathLike)
        let base = normalizeFileName(URL(fileURLWithPath: pathLike).lastPathComponent)
        return Set([full, base])
    }

    private static func normalizeFileName(_ raw: String) -> String {
        var value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if value.hasPrefix("*") {
            value.removeFirst()
        }
        if value.hasPrefix("./") {
            value = String(value.dropFirst(2))
        }
        return value
    }
}

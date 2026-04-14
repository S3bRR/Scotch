import Foundation

public enum DLLInstallError: Error {
    case destinationMissing(URL)
    case sourceMissing(URL)
    case sourceHasNoDLLs(URL)
}

public extension LocalFileSystem {
    func replaceDLLs(
        in destinationDirectory: URL,
        from sourceDirectory: URL,
        makeOriginalCopy: Bool = true,
        requireAtLeastOneDLL: Bool = true
    ) throws {
        guard fileExists(at: destinationDirectory) else {
            throw DLLInstallError.destinationMissing(destinationDirectory)
        }
        guard fileExists(at: sourceDirectory) else {
            throw DLLInstallError.sourceMissing(sourceDirectory)
        }
        let enumerator = FileManager.default.enumerator(
            at: sourceDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var replacedCount = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension.lowercased() == "dll" else { continue }
            let destination = destinationDirectory.appending(path: fileURL.lastPathComponent)
            try replaceFile(at: destination, with: fileURL, makeOriginalCopy: makeOriginalCopy)
            replacedCount += 1
        }

        if requireAtLeastOneDLL && replacedCount == 0 {
            throw DLLInstallError.sourceHasNoDLLs(sourceDirectory)
        }
    }

    func restoreOriginalDLLs(in directory: URL) throws {
        guard fileExists(at: directory) else { return }
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "orig" {
                let originalTarget = fileURL.deletingPathExtension()
                if fileExists(at: originalTarget) {
                    try removeItem(at: originalTarget)
                }
                try moveItem(at: fileURL, to: originalTarget)
            } else if fileURL.pathExtension == "scotch-injected" {
                let injectedDLL = fileURL.deletingPathExtension()
                if fileExists(at: injectedDLL) {
                    try removeItem(at: injectedDLL)
                }
                try removeItem(at: fileURL)
            }
        }
    }

    func replaceFile(at target: URL, with source: URL, makeOriginalCopy: Bool = true) throws {
        if fileExists(at: target) {
            if makeOriginalCopy {
                let backup = target.appendingPathExtension("orig")
                if fileExists(at: backup) {
                    try removeItem(at: backup)
                }
                try moveItem(at: target, to: backup)
            } else {
                try removeItem(at: target)
            }
        } else if makeOriginalCopy {
            let marker = target.appendingPathExtension("scotch-injected")
            if !fileExists(at: marker) {
                try Data().write(to: marker)
            }
        }

        try copyItem(at: source, to: target)
    }
}

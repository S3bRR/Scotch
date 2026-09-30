import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
struct RuntimeResourceProbe {
    static func main() {
        do {
            try validateResources()
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func validateResources() throws {
        for (name, extensionName, subdirectory) in [
            ("libscotch_gpu_spoof", "dylib" as String?, "VulkanSpoof" as String?),
            ("libMoltenVK_shim", "c" as String?, "VulkanSpoof" as String?),
            ("cabextract", nil, nil)
        ] {
            guard let url = RuntimeResources.bundled.url(forResource: name, withExtension: extensionName, subdirectory: subdirectory) else {
                throw NSError(domain: "ScotchResourceProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing runtime resource: \(name)"])
            }
            print(url.path)
        }
    }
}

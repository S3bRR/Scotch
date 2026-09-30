import Foundation
import ScotchDomain
import ScotchInfrastructure

struct WineBundleSigning: Sendable {
    let processRunner: ProcessRunner

    func signAndVerify(at bundleURL: URL) async throws {
        do {
            // The launcher is a shell script. Sign the bundle after writing its
            // executable and Info.plist, without imposing hardened-runtime flags.
            _ = try await processRunner.captureProcess(
                specification(["--force", "--deep", "--sign", "-"], at: bundleURL),
                outputFileHandle: nil
            )
            try await verify(at: bundleURL)
        } catch {
            throw RuntimeInstallerError.installFailed("Wine.app signing failed: \(error.localizedDescription)")
        }
    }

    func verify(at bundleURL: URL) async throws {
        _ = try await processRunner.captureProcess(
            specification(["--verify", "--deep", "--strict"], at: bundleURL),
            outputFileHandle: nil
        )
    }

    /// Repairs wrappers created by older Scotch releases or an interrupted update.
    /// Always verify again so replacing or editing Wine.app invalidates readiness.
    func ensureSigned(at bundleURL: URL) async throws {
        do {
            try await verify(at: bundleURL)
        } catch ProcessRunnerError.nonZeroExit {
            try await signAndVerify(at: bundleURL)
        }
    }

    private func specification(_ arguments: [String], at bundleURL: URL) -> ProcessSpecification {
        ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: arguments + [bundleURL.path(percentEncoded: false)],
            displayName: "codesign Wine.app",
            timeout: 60
        )
    }
}

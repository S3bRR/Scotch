import Foundation
import ScotchDomain
import ScotchInfrastructure

public actor RosettaService: RosettaServiceProtocol {
    private let rosettaRuntimePath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
    private let processRunner: ProcessRunner

    public init(processRunner: ProcessRunner = DefaultProcessRunner()) {
        self.processRunner = processRunner
    }

    public func isInstalled() async -> Bool {
        FileManager.default.fileExists(atPath: rosettaRuntimePath)
    }

    public func installIfNeeded() async throws -> Bool {
        if await isInstalled() {
            return true
        }

        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/usr/sbin/softwareupdate"),
            arguments: ["--install-rosetta", "--agree-to-license"],
            displayName: "softwareupdate --install-rosetta",
            timeout: 15 * 60
        )

        do {
            _ = try await processRunner.captureProcess(spec, outputFileHandle: nil)
            return true
        } catch ProcessRunnerError.nonZeroExit {
            return false
        }
    }
}

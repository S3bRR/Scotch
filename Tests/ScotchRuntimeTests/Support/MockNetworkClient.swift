import Foundation
import ScotchInfrastructure

/// Actor-based mock for `NetworkClient`. Mirrors the `RecordingProcessRunner` pattern:
/// callers configure handlers and inspect captured requests.
final actor MockNetworkClient: NetworkClient {
    private var dataHandler: (@Sendable (NetworkRequest) async throws -> Data)?
    private var downloadHandler: (@Sendable (NetworkRequest) async throws -> URL)?
    private(set) var capturedRequests: [NetworkRequest] = []

    init() {}

    func setDataHandler(_ handler: @escaping @Sendable (NetworkRequest) async throws -> Data) {
        self.dataHandler = handler
    }

    func setDownloadHandler(_ handler: @escaping @Sendable (NetworkRequest) async throws -> URL) {
        self.downloadHandler = handler
    }

    func data(for request: NetworkRequest) async throws -> Data {
        capturedRequests.append(request)
        guard let handler = dataHandler else {
            throw NetworkClientError.transportFailure(url: request.url, underlying: "no dataHandler set")
        }
        return try await handler(request)
    }

    func download(from request: NetworkRequest) async throws -> URL {
        capturedRequests.append(request)
        guard let handler = downloadHandler else {
            throw NetworkClientError.transportFailure(url: request.url, underlying: "no downloadHandler set")
        }
        return try await handler(request)
    }
}

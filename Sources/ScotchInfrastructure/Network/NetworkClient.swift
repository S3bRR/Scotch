import Foundation

public enum NetworkClientError: LocalizedError, Sendable {
    case invalidURL(String)
    case nonSuccessStatus(url: URL, status: Int)
    case transportFailure(url: URL, underlying: String)
    case exhaustedRetries(url: URL, attempts: Int, underlying: String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "Invalid URL: \(raw)"
        case .nonSuccessStatus(let url, let status):
            return "\(url.absoluteString) returned HTTP \(status)."
        case .transportFailure(let url, let underlying):
            return "\(url.absoluteString) transport failure: \(underlying)"
        case .exhaustedRetries(let url, let attempts, let underlying):
            return "\(url.absoluteString) failed after \(attempts) attempts: \(underlying)"
        }
    }
}

public struct NetworkRequest: Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let timeout: TimeInterval?

    public init(
        url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.timeout = timeout
    }
}

public struct RetryPolicy: Sendable {
    public let maxAttempts: Int
    public let backoff: @Sendable (Int) -> Duration

    public init(maxAttempts: Int, backoff: @escaping @Sendable (Int) -> Duration) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
    }

    /// 3 attempts with quadratic backoff (attempt² × 0.4s) — matches the inline retry shape
    /// previously in `RuntimeInstallerService.downloadAsset`.
    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        backoff: { attempt in
            .nanoseconds(Int64(attempt * attempt) * 400_000_000)
        }
    )

    /// Single-attempt policy used by callers that handle their own retry semantics.
    public static let none = RetryPolicy(
        maxAttempts: 1,
        backoff: { _ in .zero }
    )
}

public protocol NetworkClient: Sendable {
    /// Performs a request and returns the body. Retries idempotent transport errors and 5xx/429 per the client policy.
    func data(for request: NetworkRequest) async throws -> Data

    /// Downloads to a temporary file and returns its URL. Caller must move or delete the file.
    func download(from request: NetworkRequest) async throws -> URL
}

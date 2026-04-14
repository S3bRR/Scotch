import Foundation

/// `@unchecked Sendable`: the underlying `URLSession` is thread-safe; all stored properties
/// are immutable after init.
public final class DefaultNetworkClient: NetworkClient, @unchecked Sendable {
    private let session: URLSession
    private let userAgent: String
    private let retry: RetryPolicy

    public init(
        userAgent: String = "Scotch",
        defaultRequestTimeout: TimeInterval = 30,
        defaultResourceTimeout: TimeInterval = 600,
        retry: RetryPolicy = .default
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = defaultRequestTimeout
        config.timeoutIntervalForResource = defaultResourceTimeout
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        self.userAgent = userAgent
        self.retry = retry
    }

    /// Test-only initializer that accepts a pre-built `URLSession` (e.g. one wired to a stub URLProtocol).
    public init(session: URLSession, userAgent: String = "Scotch", retry: RetryPolicy = .default) {
        self.session = session
        self.userAgent = userAgent
        self.retry = retry
    }

    public func data(for request: NetworkRequest) async throws -> Data {
        try await retrying(url: request.url) {
            let urlRequest = self.makeURLRequest(from: request)
            let (data, response) = try await self.session.data(for: urlRequest)
            try Self.validate(response: response, url: request.url)
            return data
        }
    }

    public func download(from request: NetworkRequest) async throws -> URL {
        try await retrying(url: request.url) {
            let urlRequest = self.makeURLRequest(from: request)
            let (tempURL, response) = try await self.session.download(for: urlRequest)
            do {
                try Self.validate(response: response, url: request.url)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            return tempURL
        }
    }

    private func makeURLRequest(from request: NetworkRequest) -> URLRequest {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        if let timeout = request.timeout {
            urlRequest.timeoutInterval = timeout
        }
        return urlRequest
    }

    private static func validate(response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NetworkClientError.nonSuccessStatus(url: url, status: http.statusCode)
        }
    }

    private func retrying<T: Sendable>(
        url: URL,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 1...retry.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt >= retry.maxAttempts || !Self.isRetryable(error) {
                    break
                }
                try? await Task.sleep(for: retry.backoff(attempt))
            }
        }
        if let networkError = lastError as? NetworkClientError {
            switch networkError {
            case .nonSuccessStatus(_, let status) where !(500..<600).contains(status) && status != 429:
                throw networkError
            default:
                throw NetworkClientError.exhaustedRetries(
                    url: url,
                    attempts: retry.maxAttempts,
                    underlying: networkError.errorDescription ?? "unknown"
                )
            }
        }
        if let lastError {
            throw NetworkClientError.transportFailure(url: url, underlying: (lastError as NSError).localizedDescription)
        }
        throw NetworkClientError.transportFailure(url: url, underlying: "no response")
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let networkError = error as? NetworkClientError {
            switch networkError {
            case .nonSuccessStatus(_, let status):
                return (500..<600).contains(status) || status == 429
            case .transportFailure, .exhaustedRetries, .invalidURL:
                return false
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet,
                 NSURLErrorResourceUnavailable:
                return true
            default:
                return false
            }
        }
        return false
    }
}

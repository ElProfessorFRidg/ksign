//
//  NBFetchService.swift
//  NimbleJSON
//

import Foundation

/// Reuses connections and HTTP validators across source requests.
public final class NBFetchService: @unchecked Sendable {
    public enum NBFetchServiceError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case httpError(Int)
        case noData
        case parsingError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL: return "The URL is invalid."
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            case .httpError(let status): return "The server returned HTTP \(status)."
            case .noData: return "No data received."
            case .parsingError(let detail): return "Failed to parse data: \(detail)"
            }
        }
    }

    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "KsignSourceResponses"
        )
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    private func request(for url: URL, refresh: Bool) -> URLRequest {
        URLRequest(
            url: url,
            cachePolicy: refresh ? .reloadRevalidatingCacheData : .useProtocolCachePolicy,
            timeoutInterval: 30
        )
    }

    private func decode<T: Decodable>(_ data: Data, response: URLResponse?) throws -> T {
        if let response = response as? HTTPURLResponse, !(200..<300).contains(response.statusCode) {
            throw NBFetchServiceError.httpError(response.statusCode)
        }
        guard !data.isEmpty else { throw NBFetchServiceError.noData }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NBFetchServiceError.parsingError(String(describing: error))
        }
    }

    public func fetch<T: Decodable & Sendable>(from url: URL, refresh: Bool = false) async throws -> T {
        let (data, response) = try await session.data(for: request(for: url, refresh: refresh))
        return try decode(data, response: response)
    }

    public func fetch<T: Decodable>(
        from urlString: String,
        completion: @escaping @Sendable (Result<T, Error>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(NBFetchServiceError.invalidURL))
            return
        }
        fetch(from: url, completion: completion)
    }

    public func fetch<T: Decodable>(
        from url: URL,
        completion: @escaping @Sendable (Result<T, Error>) -> Void
    ) {
        session.dataTask(with: request(for: url, refresh: false)) { [self] data, response, error in
            if let error {
                completion(.failure(NBFetchServiceError.networkError(error)))
                return
            }
            guard let data else {
                completion(.failure(NBFetchServiceError.noData))
                return
            }
            // Missing keys, invalid types and corrupt JSON must all finish the request.
            // The previous decoder catch could leave callers waiting forever.
            do {
                completion(.success(try decode(data, response: response)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}


import Foundation
import SwiftUI

// The checks exercise JSON and networking, independent of UIKit color rendering.
extension Color: Decodable {
    public init(from decoder: Decoder) throws {
        _ = try decoder.singleValueContainer().decode(String.self)
        self = .clear
    }
}
extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct Payload: Decodable, Sendable { let value: String }

final class FixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        if path == "/slow" { return } // Cancelled by the test.
        let body: String
        switch path {
        case "/missing": body = "{}"
        case "/type": body = #"{"value":42}"#
        case "/corrupt": body = "{"
        default: body = #"{"value":"ready"}"#
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: path == "/http-error" ? 503 : 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct SourceLoadingChecks {
    static func main() async throws {
        let fixture = #"""
        {
          "apps": [{
            "name": "Example", "bundleIdentifier": "example.app",
            "versions": [
              {"version":"1.0","buildVersion":"2","date":"2026-11-16T12:00:00Z",
               "downloadURL":"https://github.com/example/app/releases/download/v1.0%2Bbuild.2/app.ipa",
               "screenshots":["https://example.com/new.png"]},
              {"version":"1.0","buildVersion":"1","date":"2026-11-15T12:00:00Z",
               "downloadURL":"https://github.com/example/app/releases/download/v1.0%2Bbuild.1/app.ipa",
               "screenshots":{"iphone":[{"imageURL":"https://example.com/old.png"}]}}
            ]
          }],
          "news": [
            {"identifier":"old","title":"Old release","caption":"","appID":"example.app",
             "imageURL":"https://example.com/banner.png",
             "url":"https://github.com/example/app/releases/tag/v1.0%2Bbuild.1"},
            {"identifier":"download","title":"New release","caption":"","appID":"example.app",
             "url":"https://github.com/example/app/releases/download/v1.0%2Bbuild.2/app.ipa"},
            {"identifier":"dated","title":"Dated release","caption":"","appID":"example.app",
             "date":"2026-11-15T12:00:00Z"},
            {"identifier":"explicit","title":"Own gallery","caption":"","appID":"example.app",
             "imageURLs":["https://example.com/own.png"],
             "url":"https://github.com/example/app/releases/tag/v1.0%2Bbuild.1"},
            {"identifier":"unrelated","title":"Other news","caption":"","appID":"example.app",
             "url":"https://example.com/other"}
          ]
        }
        """#
        let repository = try JSONDecoder().decode(ASRepository.self, from: Data(fixture.utf8))
        let news = repository.news!
        precondition(news[0].allImageURLs.map(\.lastPathComponent) == ["banner.png", "old.png"])
        precondition(news[1].allImageURLs.map(\.lastPathComponent) == ["new.png"])
        precondition(news[2].allImageURLs.map(\.lastPathComponent) == ["old.png"])
        precondition(news[3].allImageURLs.map(\.lastPathComponent) == ["own.png"])
        precondition(news[4].allImageURLs.isEmpty)
        precondition(repository.apps[0].currentScreenshotURLs.map(\.lastPathComponent) == ["new.png"])
        print("Release galleries: exact build, tag/download URL, timestamp, explicit gallery and unmatched news passed.")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = NBFetchService(session: session)
        let value: Payload = try await service.fetch(from: URL(string: "https://fixture.invalid/valid")!)
        precondition(value.value == "ready")

        for path in ["missing", "type", "corrupt", "http-error"] {
            let finished = DispatchSemaphore(value: 0)
            service.fetch(from: URL(string: "https://fixture.invalid/\(path)")!) { (result: Result<Payload, Error>) in
                guard case .failure = result else { preconditionFailure("Expected failure: \(path)") }
                finished.signal()
            }
            precondition(finished.wait(timeout: .now() + 3) == .success, "Request hung for \(path)")
        }
        let cancelled = Task { () throws -> Payload in
            try await service.fetch(from: URL(string: "https://fixture.invalid/slow")!)
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancellation did not propagate")
        } catch let error as URLError {
            precondition(error.code == .cancelled)
        }
        print("Networking: valid JSON, missing keys, wrong types, corrupt JSON, HTTP errors and cancellation passed.")
    }
}


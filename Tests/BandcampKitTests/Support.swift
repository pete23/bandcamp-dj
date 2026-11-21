import Foundation
import Testing

@testable import BandcampKit

func fixture(_ name: String, ext: String = "json") throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Answers requests from a handler and records them.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URLRequest, Int) throws -> (Data, Int)
    private let headers: @Sendable (URLRequest) -> [String: String]

    /// `handler` gets the request and its index, and returns a body and status.
    init(
        headers: @escaping @Sendable (URLRequest) -> [String: String] = { _ in [:] },
        _ handler: @escaping @Sendable (URLRequest, Int) throws -> (Data, Int)
    ) {
        self.headers = headers
        self.handler = handler
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let index = lock.withLock {
            recorded.append(request)
            return recorded.count - 1
        }
        let (data, status) = try handler(request, index)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers(request))!
        return (data, response)
    }
}

/// Serves the summary, then collection pages in order.
func collectionTransport(pages: [String]) -> StubTransport {
    StubTransport { request, _ in
        if request.url == BandcampClient.summaryURL { return (try fixture("collection_summary"), 200) }
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as! [String: Any]
        let token = body["older_than_token"] as! String
        let page = token.hasPrefix("1763200000") ? 1 : 0
        return (try fixture(pages[page]), 200)
    }
}

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "bandcamp-sync-tests-\(UUID().uuidString)")
}

func date(_ string: String) -> Date {
    CollectionPage.parseDate(string)!
}

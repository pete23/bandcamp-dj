import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

/// Talks to Bandcamp's unofficial fan API using the browser `identity` cookie.
public struct BandcampClient: Sendable {
    static let summaryURL = URL(string: "https://bandcamp.com/api/fan/2/collection_summary")!
    static let collectionItemsURL = URL(
        string: "https://bandcamp.com/api/fancollection/1/collection_items")!

    let identity: String
    let transport: any HTTPTransport
    let now: @Sendable () -> Date

    public init(
        identity: String,
        transport: any HTTPTransport = URLSession.shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.identity = identity
        self.transport = transport
        self.now = now
    }

    public func fanID() async throws -> Int {
        struct Summary: Decodable { let fan_id: Int? }
        let (data, status) = try await send(URLRequest(url: Self.summaryURL))
        guard (200..<300).contains(status),
            let fanID = (try? JSONDecoder().decode(Summary.self, from: data))?.fan_id
        else { throw BandcampError.unauthorized }
        return fanID
    }

    /// The most recent `limit` purchases, newest first.
    public func purchases(limit: Int) async throws -> [Purchase] {
        guard limit > 0 else { return [] }
        let fanID = try await fanID()
        var token = "\(Int(now().timeIntervalSince1970))::a::"
        var result: [Purchase] = []

        while result.count < limit {
            var request = URLRequest(url: Self.collectionItemsURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "fan_id": fanID, "older_than_token": token, "count": limit - result.count,
            ] as [String: Any])

            let (data, status) = try await send(request)
            guard (200..<300).contains(status) else { throw BandcampError.http(status: status) }
            let page: CollectionPage
            do {
                page = try JSONDecoder().decode(CollectionPage.self, from: data)
            } catch {
                throw BandcampError.decoding(String(describing: error))
            }
            result += try page.purchases()

            guard page.more_available, let next = page.last_token, !page.items.isEmpty else { break }
            token = next
        }

        return Array(result.sorted { $0.purchasedAt > $1.purchasedAt }.prefix(limit))
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        var request = request
        request.setValue("identity=\(identity)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await transport.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

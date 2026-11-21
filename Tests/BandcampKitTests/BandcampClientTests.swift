import Foundation
import Testing

@testable import BandcampKit

let fixedNow: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_763_800_000) }

@Suite struct BandcampClientTests {
    @Test func fanIDSendsCookie() async throws {
        let transport = collectionTransport(pages: [])
        let client = BandcampClient(identity: "secret", transport: transport)

        #expect(try await client.fanID() == 4242)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Cookie") == "identity=secret")
    }

    @Test func fanIDUnauthorizedOnHTTPError() async throws {
        let client = BandcampClient(identity: "bad", transport: StubTransport { _, _ in (Data("{}".utf8), 401) })
        await #expect(throws: BandcampError.unauthorized) { try await client.fanID() }
    }

    @Test func fanIDUnauthorizedWhenMissing() async throws {
        let body = Data(#"{"error": true, "error_message": "not logged in"}"#.utf8)
        let client = BandcampClient(identity: "bad", transport: StubTransport { _, _ in (body, 200) })
        await #expect(throws: BandcampError.unauthorized) { try await client.fanID() }
    }

    @Test func paginatesUntilNoMoreAvailable() async throws {
        let transport = collectionTransport(pages: ["collection_items_page1", "collection_items_page2"])
        let client = BandcampClient(identity: "secret", transport: transport, now: fixedNow)

        let purchases = try await client.purchases(limit: 50)

        #expect(purchases.map(\.saleItemID) == [222, 111, 333, 444])
        let bodies = try transport.requests.dropFirst().map {
            try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: Any]
        }
        #expect(bodies.count == 2)
        #expect(bodies[0]["fan_id"] as? Int == 4242)
        #expect(bodies[0]["older_than_token"] as? String == "1763800000::a::")
        #expect(bodies[0]["count"] as? Int == 50)
        #expect(bodies[1]["older_than_token"] as? String == "1763200000:111:a::")
        #expect(bodies[1]["count"] as? Int == 48)
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "identity=secret" })
        #expect(transport.requests.last?.httpMethod == "POST")
    }

    @Test func stopsAtLimit() async throws {
        let transport = collectionTransport(pages: ["collection_items_page1", "collection_items_page2"])
        let client = BandcampClient(identity: "secret", transport: transport, now: fixedNow)

        let purchases = try await client.purchases(limit: 2)

        #expect(purchases.map(\.saleItemID) == [222, 111])
        #expect(transport.requests.count == 2)
    }

    @Test func truncatesToLimitSortedNewestFirst() async throws {
        let transport = collectionTransport(pages: ["collection_items_page1", "collection_items_page2"])
        let client = BandcampClient(identity: "secret", transport: transport, now: fixedNow)

        let purchases = try await client.purchases(limit: 1)

        #expect(purchases.map(\.saleItemID) == [222])
    }

    @Test func stopsWhenMoreAvailableIsFalse() async throws {
        let transport = collectionTransport(pages: ["collection_items_page2"])
        let client = BandcampClient(identity: "secret", transport: transport, now: fixedNow)

        let purchases = try await client.purchases(limit: 10)

        #expect(purchases.count == 2)
        #expect(transport.requests.count == 2)
    }

    @Test func mapsFields() async throws {
        let transport = collectionTransport(pages: ["collection_items_page1", "collection_items_page2"])
        let purchases = try await BandcampClient(identity: "s", transport: transport, now: fixedNow)
            .purchases(limit: 10)

        let single = try #require(purchases.first { $0.saleItemID == 222 })
        #expect(single.itemType == .track)
        #expect(single.artist == "Artist B")
        #expect(single.title == "A Single")
        #expect(single.purchasedAt == Date(timeIntervalSince1970: 1_795_255_200))
        #expect(single.itemURL == URL(string: "https://artistb.bandcamp.com/track/a-single"))
        #expect(single.redownloadURL == URL(string: "https://bandcamp.com/download?from=collection&payment_id=222&sig=def"))

        let package = try #require(purchases.first { $0.saleItemID == 333 })
        #expect(package.itemType == .package)
        #expect(package.redownloadURL == URL(string: "https://bandcamp.com/download?from=collection&payment_id=333&sig=ghi"))

        let other = try #require(purchases.first { $0.saleItemID == 444 })
        #expect(other.itemType == .other("subscription"))
        #expect(other.itemURL == nil)
        #expect(other.redownloadURL == nil)
    }

    @Test func parsesDates() {
        #expect(CollectionPage.parseDate("21 Nov 2026 10:00:00 GMT") == Date(timeIntervalSince1970: 1_795_255_200))
        #expect(CollectionPage.parseDate("01 Oct 2026 18:45:12 GMT") == Date(timeIntervalSince1970: 1_790_880_312))
        #expect(CollectionPage.parseDate("2026-11-21") == nil)
    }

    @Test func httpErrorFromCollectionItems() async throws {
        let transport = StubTransport { request, _ in
            request.url == BandcampClient.summaryURL ? (try fixture("collection_summary"), 200) : (Data(), 503)
        }
        let client = BandcampClient(identity: "s", transport: transport, now: fixedNow)
        await #expect(throws: BandcampError.http(status: 503)) { try await client.purchases(limit: 5) }
    }

    @Test func decodingError() async throws {
        let transport = StubTransport { request, _ in
            request.url == BandcampClient.summaryURL
                ? (try fixture("collection_summary"), 200) : (Data(#"{"items": "nope"}"#.utf8), 200)
        }
        let client = BandcampClient(identity: "s", transport: transport, now: fixedNow)
        await #expect {
            try await client.purchases(limit: 5)
        } throws: { error in
            if case BandcampError.decoding = error { true } else { false }
        }
    }

    @Test func itemTypeRoundTripsUnknownValues() throws {
        let encoded = try JSONEncoder().encode([Purchase.ItemType.album, .other("subscription")])
        #expect(String(decoding: encoded, as: UTF8.self) == #"["album","subscription"]"#)
        #expect(try JSONDecoder().decode([Purchase.ItemType].self, from: encoded) == [.album, .other("subscription")])
    }
}

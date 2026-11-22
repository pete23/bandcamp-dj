import Foundation
import Testing

@testable import BandcampKit

private let pageURL = URL(string: "https://bandcamp.com/download?from=collection&payment_id=1&sig=x&sitem_id=2")!

private func purchase(redownloadURL: URL? = pageURL) -> Purchase {
    Purchase(
        saleItemID: 2, itemType: .album, artist: "Donato Dozzy", title: "Astro", purchasedAt: Date(),
        itemURL: nil, redownloadURL: redownloadURL)
}

/// Serves the download page, a statdownload answer and the file itself.
private func downloadTransport(
    page: String = "download_page", stat: String? = nil, fileType: String = "application/zip"
) -> StubTransport {
    StubTransport(headers: { request in
        request.url?.host() == "p4.bcbits.com" ? ["Content-Type": fileType] : [:]
    }) { request, _ in
        let url = request.url!
        if url.host() == "bandcamp.com" { return (try fixture(page, ext: "html"), 200) }
        if url.path.hasPrefix("/statdownload/") {
            let body = stat ?? #"if ( window.Downloads ) { Downloads.statResult ( {"result":"ok","download_url":"https://p4.bcbits.com/download/album/abc/1?id=920216280"} ) };"#
            return (Data(body.utf8), 200)
        }
        if url.host() == "p4.bcbits.com" { return (Data("PK\u{03}\u{04}zipdata".utf8), 200) }
        return (Data(), 404)
    }
}

@Suite struct DownloadTests {
    @Test func parsesDownloadPage() throws {
        let html = String(decoding: try fixture("download_page", ext: "html"), as: UTF8.self)
        let page = try DownloadPage.parse(html: html)

        #expect(page.digital_items.count == 1)
        #expect(page.digital_items[0].title == "Astro")
        #expect(page.digital_items[0].downloads["mp3-320"]?.size_mb == "95.5MB")
        #expect(page.digital_items[0].downloads["mp3-320"]?.url.contains("&sig=fake&") == true)
    }

    @Test func pageWithoutBlobIsDecodingError() {
        #expect {
            try DownloadPage.parse(html: "<html>Log in</html>")
        } throws: { error in
            if case BandcampError.decoding = error { true } else { false }
        }
    }

    @Test(arguments: [
        ("&quot;a&quot; &amp; &lt;b&gt;", "\"a\" & <b>"),
        ("it&#39;s &#x41;&#66;", "it's AB"),
        ("caf&#233;", "café"),
        ("AT&T &unknown; & done", "AT&T &unknown; & done"),
    ])
    func unescapesHTML(input: String, expected: String) {
        #expect(DownloadPage.unescapeHTML(input[...]) == expected)
    }

    @Test func picksRequestedFormat() async throws {
        let client = BandcampClient(identity: "secret", transport: downloadTransport())

        let option = try #require(try await client.downloadOption(for: purchase(), format: .alac))

        #expect(option.format == .alac)
        #expect(option.size == "444.3MB")
        #expect(option.url.absoluteString.contains("enc=alac"))
    }

    @Test func missingFormatListsAvailable() async throws {
        let client = BandcampClient(identity: "secret", transport: downloadTransport())

        await #expect(throws: BandcampError.formatUnavailable(
            format: "wav", available: ["alac", "flac", "mp3-320", "mp3-v0"])) {
            try await client.downloadOption(for: purchase(), format: .wav)
        }
    }

    @Test func noDigitalDownload() async throws {
        let client = BandcampClient(identity: "s", transport: downloadTransport(page: "download_page_merch"))
        #expect(try await client.downloadOption(for: purchase(), format: .mp3320) == nil)
        #expect(try await client.downloadOption(for: purchase(redownloadURL: nil), format: .mp3320) == nil)
    }

    @Test func downloadResolvesThroughStatdownload() async throws {
        let transport = downloadTransport()
        let client = BandcampClient(identity: "secret", transport: transport)
        let option = try #require(try await client.downloadOption(for: purchase(), format: .mp3320))

        let file = try await client.download(option)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(try Data(contentsOf: file) == Data("PK\u{03}\u{04}zipdata".utf8))
        let stat = try #require(transport.requests.first { $0.url!.path.hasPrefix("/statdownload/") })
        #expect(stat.url!.host() == "popplers5.bandcamp.com")
        #expect(stat.url!.path == "/statdownload/album")
        #expect(stat.url!.query()!.contains("enc=mp3-320"))
        #expect(stat.url!.query()!.contains(".vrs=1"))
        #expect(transport.requests.last?.url?.host() == "p4.bcbits.com")
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie") == "identity=secret" })
    }

    @Test func downloadFallsBackToOriginalURL() async throws {
        let transport = StubTransport { request, _ in
            request.url!.path.hasPrefix("/statdownload/") ? (Data("garbage".utf8), 200) : (Data("file".utf8), 200)
        }
        let client = BandcampClient(identity: "s", transport: transport)
        let url = URL(string: "https://popplers5.bandcamp.com/download/track?enc=mp3-320&id=1")!

        let file = try await client.download(DownloadOption(format: .mp3320, url: url, size: nil))
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(transport.requests.last?.url == url)
    }

    @Test func htmlInsteadOfFileIsAnError() async throws {
        let client = BandcampClient(identity: "s", transport: downloadTransport(fileType: "text/html; charset=utf-8"))
        let option = try #require(try await client.downloadOption(for: purchase(), format: .mp3320))

        await #expect(throws: BandcampError.notAFile) { try await client.download(option) }
    }

    @Test func statDownloadURLParsing() {
        #expect(BandcampClient.statDownloadURL(
            #"if ( window.Downloads ) { Downloads.statResult ( {"result":"ok","download_url":"https://x/y"} ) };"#)
            == URL(string: "https://x/y"))
        #expect(BandcampClient.statDownloadURL(#"{"result":"err"}"#) == nil)
        #expect(BandcampClient.statDownloadURL("nothing") == nil)
    }

    @Test(arguments: [
        ("95.5MB", Int64(100_139_008)),
        ("1.5 GB", Int64(1_610_612_736)),
        ("800KB", Int64(819_200)),
        ("lots", nil),
    ] as [(String, Int64?)])
    func approximateBytes(label: String, expected: Int64?) {
        let option = DownloadOption(format: .mp3320, url: URL(string: "https://x")!, size: label)
        #expect(option.approximateBytes == expected)
    }

    @Test func downloadReportsProgressWithSizeFallback() async throws {
        let client = BandcampClient(identity: "s", transport: downloadTransport())
        let option = try #require(try await client.downloadOption(for: purchase(), format: .mp3320))
        let reports = Reports()

        let file = try await client.download(option) { reports.add($0, $1) }
        defer { try? FileManager.default.removeItem(at: file) }

        // The stub knows the size, so it reports it rather than Bandcamp's label.
        #expect(reports.last?.0 == 11)
        #expect(reports.last?.1 == 11)
    }
}

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [(Int64, Int64?)] = []
    func add(_ received: Int64, _ expected: Int64?) { lock.withLock { all.append((received, expected)) } }
    var last: (Int64, Int64?)? { lock.withLock { all.last } }
}

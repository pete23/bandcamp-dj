import BandcampKit
import Foundation
import Testing

@testable import SyncKit

/// Serves a download page offering mp3-320 at `fileURL`, then `file` from there.
final class FakeBandcamp: HTTPTransport, @unchecked Sendable {
    static let fileURL = "https://popplers5.bandcamp.com/download/album?enc=mp3-320&id=1&sig=x"

    let file: Data
    let offersDownload: Bool
    private let lock = NSLock()
    private var fileRequests = 0

    init(file: Data, offersDownload: Bool = true) {
        self.file = file
        self.offersDownload = offersDownload
    }

    var downloads: Int { lock.withLock { fileRequests } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let body: Data
        if url.host() == "bandcamp.com" {
            let downloads = offersDownload ? #"{"mp3-320": {"size_mb": "1MB", "url": "\#(Self.fileURL)"}}"# : "[]"
            let blob = #"{"digital_items": [{"title": "T", "downloads": \#(downloads)}]}"#
                .replacingOccurrences(of: "\"", with: "&quot;")
            body = Data(#"<div data-blob="\#(blob)"></div>"#.utf8)
        } else if url.path.hasPrefix("/statdownload/") {
            body = Data("no".utf8)
        } else {
            lock.withLock { fileRequests += 1 }
            body = file
        }
        return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func purchase(_ type: Purchase.ItemType = .album, artist: String = "Artist", title: String = "Title") -> Purchase {
    Purchase(
        saleItemID: 42, itemType: type, artist: artist, title: title, purchasedAt: Date(timeIntervalSince1970: 0),
        itemURL: nil, redownloadURL: URL(string: "https://bandcamp.com/download?id=42"))
}

/// A zip holding `01 Song.mp3` and `cover.jpg`, made with ditto.
private func makeZip() throws -> Data {
    let fm = FileManager.default
    let work = fm.temporaryDirectory.appending(path: "zip-\(UUID().uuidString)")
    let content = work.appending(path: "content")
    try fm.createDirectory(at: content, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: work) }
    try Data("mp3".utf8).write(to: content.appending(path: "01 Song.mp3"))
    try Data("jpg".utf8).write(to: content.appending(path: "cover.jpg"))
    let zip = work.appending(path: "album.zip")
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/ditto")
    process.arguments = ["-c", "-k", content.path, zip.path]
    try process.run()
    process.waitUntilExit()
    return try Data(contentsOf: zip)
}

@Suite struct DownloaderTests {
    let destination = FileManager.default.temporaryDirectory.appending(path: "downloads-\(UUID().uuidString)")

    func downloader(_ transport: FakeBandcamp) -> Downloader {
        Downloader(client: BandcampClient(identity: "s", transport: transport), format: .mp3320, destination: destination)
    }

    func contents(_ folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    @Test func unzipsAlbumIntoItsOwnFolder() async throws {
        let transport = FakeBandcamp(file: try makeZip())
        var announced: [DownloadOption] = []

        let outcome = try await downloader(transport).download(purchase()) { announced.append($0) }

        let folder = destination.appending(path: "Artist - Title", directoryHint: .isDirectory)
        #expect(outcome == .downloaded(folder))
        #expect(try contents(folder) == [".bandcamp-purchase.json", "01 Song.mp3", "cover.jpg"])
        #expect(try Data(contentsOf: folder.appending(path: "01 Song.mp3")) == Data("mp3".utf8))
        #expect(announced.map(\.size) == ["1MB"])
        #expect(try contents(destination) == ["Artist - Title"])
    }

    @Test func writesManifest() async throws {
        _ = try await downloader(FakeBandcamp(file: try makeZip())).download(purchase())

        let manifest = destination.appending(path: "Artist - Title/.bandcamp-purchase.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(Purchase.self, from: Data(contentsOf: manifest)) == purchase())
    }

    @Test func singleTrackIsSavedAsAFile() async throws {
        let outcome = try await downloader(FakeBandcamp(file: Data("ID3audio".utf8)))
            .download(purchase(.track, title: "Song"))

        let folder = destination.appending(path: "Artist - Song", directoryHint: .isDirectory)
        #expect(outcome == .downloaded(folder))
        #expect(try contents(folder) == [".bandcamp-purchase.json", "Artist - Song.mp3"])
    }

    @Test func skipsExistingFolderWithoutDownloading() async throws {
        let transport = FakeBandcamp(file: try makeZip())
        let downloader = downloader(transport)
        _ = try await downloader.download(purchase())

        let again = try await downloader.download(purchase())

        #expect(again == .alreadyDownloaded(downloader.folder(for: purchase())))
        #expect(transport.downloads == 1)
        #expect(downloader.isDownloaded(purchase()))
    }

    @Test func noDigitalDownload() async throws {
        let outcome = try await downloader(FakeBandcamp(file: Data(), offersDownload: false)).download(purchase())
        #expect(outcome == .noDownload)
        let leftovers = FileManager.default.fileExists(atPath: destination.path) ? try contents(destination) : []
        #expect(leftovers.isEmpty)
    }

    @Test func badZipLeavesNoFolderBehind() async throws {
        let transport = FakeBandcamp(file: Data("PK\u{03}\u{04}not really a zip".utf8))

        await #expect(throws: DownloadError.self) { try await downloader(transport).download(purchase()) }
        #expect(try contents(destination).isEmpty)
    }

    @Test(arguments: [
        ("AC/DC - Back: In Black", "AC-DC - Back- In Black"),
        ("...Hidden", "Hidden"),
        ("  ", "Untitled"),
        ("Line\nBreak", "Line-Break"),
    ])
    func safeNames(input: String, expected: String) {
        #expect(Downloader.safeName(input) == expected)
    }
}

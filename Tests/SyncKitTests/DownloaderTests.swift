import BandcampKit
import Foundation
import Testing

@testable import SyncKit

/// Serves a download page offering mp3-320 at `fileURL`, then `file` from there.
final class FakeBandcamp: HTTPTransport, @unchecked Sendable {
    static let fileURL = "https://popplers5.bandcamp.com/download/album?enc=mp3-320&id=1&sig=x"

    let file: Data
    let offersDownload: Bool
    /// Download page requests for these purchase IDs fail.
    let failing: Set<Int>
    let delay: Duration
    private let lock = NSLock()
    private var fileRequests = 0
    private var inFlight = 0
    private var mostInFlight = 0

    init(file: Data, offersDownload: Bool = true, failing: Set<Int> = [], delay: Duration = .zero) {
        self.file = file
        self.offersDownload = offersDownload
        self.failing = failing
        self.delay = delay
    }

    var downloads: Int { lock.withLock { fileRequests } }
    var peakConcurrency: Int { lock.withLock { mostInFlight } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = request.url!
        let body: Data
        if url.host() == "bandcamp.com" {
            if let id = Int(url.query()?.split(separator: "=").last ?? ""), failing.contains(id) {
                return (Data(), HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            }
            let downloads = offersDownload ? #"{"mp3-320": {"size_mb": "1MB", "url": "\#(Self.fileURL)"}}"# : "[]"
            let blob = #"{"digital_items": [{"title": "T", "downloads": \#(downloads)}]}"#
                .replacingOccurrences(of: "\"", with: "&quot;")
            body = Data(#"<div data-blob="\#(blob)"></div>"#.utf8)
        } else if url.path.hasPrefix("/statdownload/") {
            body = Data("no".utf8)
        } else {
            lock.withLock {
                fileRequests += 1
                inFlight += 1
                mostInFlight = max(mostInFlight, inFlight)
            }
            try await Task.sleep(for: delay)
            lock.withLock { inFlight -= 1 }
            body = file
        }
        return (body, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

private func purchase(
    _ type: Purchase.ItemType = .album, artist: String = "Artist", title: String = "Title", id: Int = 42
) -> Purchase {
    Purchase(
        saleItemID: id, itemType: type, artist: artist, title: title, purchasedAt: Date(timeIntervalSince1970: 0),
        itemURL: nil, redownloadURL: URL(string: "https://bandcamp.com/download?id=\(id)"))
}

/// Collects progress reports from concurrent callbacks.
final class Recorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [T] = []
    func append(_ value: T) { lock.withLock { recorded.append(value) } }
    var values: [T] { lock.withLock { recorded } }
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
        let progress = Recorder<Downloader.Progress>()

        let outcome = try await downloader(transport).download(purchase()) { progress.append($0) }

        let folder = destination.appending(path: "Artist - Title", directoryHint: .isDirectory)
        #expect(outcome == .downloaded(folder))
        #expect(try contents(folder) == [".bandcamp-purchase.json", "01 Song.mp3", "cover.jpg"])
        #expect(try Data(contentsOf: folder.appending(path: "01 Song.mp3")) == Data("mp3".utf8))
        #expect(progress.values.first == .preparing)
        #expect(progress.values.contains(.downloading(received: 0, expected: 1_048_576)))
        #expect(progress.values.last == .unzipping)
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

    @Test func downloadAllRespectsParallelLimit() async throws {
        let transport = FakeBandcamp(file: Data("ID3".utf8), delay: .milliseconds(50))
        let purchases = (1...7).map { purchase(.track, title: "Song \($0)", id: $0) }

        let results = await downloader(transport).downloadAll(purchases, parallel: 3)

        #expect(transport.downloads == 7)
        #expect(transport.peakConcurrency == 3)
        #expect(results.allSatisfy { if case .finished(.downloaded) = $0 { true } else { false } })
    }

    @Test func downloadAllKeepsGoingAfterFailure() async throws {
        let transport = FakeBandcamp(file: Data("ID3".utf8), failing: [2])
        let purchases = (1...3).map { purchase(.track, title: "Song \($0)", id: $0) }
        let updates = Recorder<(Int, DownloadStatus)>()

        let results = await downloader(transport).downloadAll(purchases, parallel: 2) { updates.append(($0, $1)) }

        #expect(results[1] == .failed("Bandcamp returned HTTP 500."))
        #expect(results[0] == .finished(.downloaded(destination.appending(path: "Artist - Song 1", directoryHint: .isDirectory))))
        #expect(results[2] == .finished(.downloaded(destination.appending(path: "Artist - Song 3", directoryHint: .isDirectory))))
        // Every purchase's last update is its final status.
        for index in 0..<3 {
            #expect(updates.values.last { $0.0 == index }?.1 == results[index])
        }
        #expect(updates.values.contains { $0.0 == 0 && $0.1 == .active(.preparing) })
    }

    @Test func downloadAllWithNothingToDo() async {
        #expect(await downloader(FakeBandcamp(file: Data())).downloadAll([], parallel: 6).isEmpty)
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

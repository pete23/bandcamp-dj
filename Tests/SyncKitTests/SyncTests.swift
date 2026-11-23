import BandcampKit
import Foundation
import MusicLibraryKit
import Testing

@testable import SyncKit

private func purchase(_ title: String, id: Int) -> Purchase {
    Purchase(
        saleItemID: id, itemType: .album, artist: "Artist", title: title,
        purchasedAt: Date(timeIntervalSince1970: 0), itemURL: nil, redownloadURL: nil)
}

@Suite struct SyncTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sync-\(UUID().uuidString)")
    let index = LibraryIndex(tracks: [
        Track(persistentID: "1", title: "Song", artist: "Artist", albumArtist: "Artist", album: "In Library"),
    ])

    var sync: Sync {
        Sync(client: BandcampClient(identity: "s"), folder: folder) { files in files.map { _ in "ID" } }
    }

    /// Writes `purchase`'s download folder with one track, as `Downloader` would.
    func download(_ purchase: Purchase, imported: Bool = false) throws {
        let url = sync.downloader.folder(for: purchase)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data().write(to: url.appending(path: "01 Song.mp3"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(purchase).write(to: url.appending(path: Downloader.manifestName))
        if imported { try Data("{}".utf8).write(to: url.appending(path: Importer.receiptName)) }
    }

    @Test func stagesFollowTheLibraryThenTheDownloadFolder() throws {
        let inLibrary = purchase("In Library", id: 1), downloaded = purchase("Downloaded", id: 2)
        let imported = purchase("Imported", id: 3), missing = purchase("Missing", id: 4)
        try download(inLibrary)
        try download(downloaded)
        try download(imported, imported: true)

        let items = try sync.items(for: [inLibrary, downloaded, imported, missing], index: index)

        #expect(items.map(\.stage.description) == [
            "In Music: Artist – In Library (album)", "Downloaded, not imported", "Imported", "Not downloaded",
        ])
        #expect(items.map(\.isInMusic) == [true, false, true, false])
        guard case .downloaded(let folder) = items[1].stage else { Issue.record("not downloaded"); return }
        #expect(folder.purchase == downloaded)
        #expect(folder.audioFiles.map(\.lastPathComponent) == ["01 Song.mp3"])
    }

    @Test func foldersToImportAreTheDownloadedOnesInOrder() throws {
        let purchases = ["B", "In Library", "Imported", "Missing", "A"].enumerated().map { purchase($1, id: $0) }
        for p in purchases where p.title != "Missing" { try download(p, imported: p.title == "Imported") }
        // As straight after downloading: B and A were missing when surveyed.
        let items = purchases.map { SyncItem(purchase: $0, stage: $0.title == "In Library" ? .imported : .missing) }

        #expect(try sync.foldersToImport(items).map(\.purchase.title) == ["B", "A"])
    }

    @Test func importAllReportsEachFolderAndCarriesOnAfterFailures() async throws {
        let calls = Recorder<String>()
        let importer = Importer(source: folder) { files in
            calls.append(files[0].deletingLastPathComponent().lastPathComponent)
            if files[0].path.contains("Bad") { throw CocoaError(.fileReadUnknown) }
            return files.map { _ in "ID" }
        }
        for (id, title) in ["Bad", "Good"].enumerated() { try download(purchase(title, id: id)) }
        let updates = Recorder<String>()

        let results = try await importer.importAll(try importer.folders()) { index, status in
            updates.append("\(index) \(status)")
        }

        #expect(calls.values == ["Artist - Bad", "Artist - Good"])
        guard case .failed = results[0] else { Issue.record("expected a failure"); return }
        #expect(results[1] == .finished(.imported(added: 1, of: 1)))
        #expect(updates.values.first == "0 importing")
        #expect(updates.values.count == 4)
    }

    @Test func importAllStopsWhenNotAllowedToControlMusic() async throws {
        let importer = Importer(source: folder) { _ in throw MusicAppError.notAuthorized }
        for (id, title) in ["A", "B"].enumerated() { try download(purchase(title, id: id)) }

        await #expect(throws: MusicAppError.self) { try await importer.importAll(try importer.folders()) }
        #expect(try importer.folders().allSatisfy { !$0.isImported })
    }

    @Test func importableSkipsImportedFoldersAndOnesInTheLibrary() throws {
        try download(purchase("In Library", id: 1))
        try download(purchase("Imported", id: 2), imported: true)
        try download(purchase("New", id: 3))

        #expect(try sync.importer.importable(index: index).map(\.purchase.title) == ["New"])
    }
}

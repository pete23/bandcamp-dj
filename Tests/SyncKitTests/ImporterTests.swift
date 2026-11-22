import BandcampKit
import Foundation
import Testing

@testable import SyncKit

private func purchase(title: String = "Title", id: Int = 42) -> Purchase {
    Purchase(
        saleItemID: id, itemType: .album, artist: "Artist", title: title,
        purchasedAt: Date(timeIntervalSince1970: 0), itemURL: nil, redownloadURL: nil)
}

@Suite struct ImporterTests {
    let source = FileManager.default.temporaryDirectory.appending(path: "imports-\(UUID().uuidString)")

    /// Writes a downloaded folder like `Downloader` does, holding `files` (paths may have subfolders).
    @discardableResult
    func makeFolder(_ name: String, files: [String], purchase: Purchase = purchase()) throws -> URL {
        let folder = source.appending(path: name, directoryHint: .isDirectory)
        for file in files {
            let url = folder.appending(path: file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(purchase).write(to: folder.appending(path: Downloader.manifestName))
        return folder
    }

    /// An importer whose Music adds every file except those named in `refusing`.
    func importer(refusing: Set<String> = [], calls: Recorder<[String]> = Recorder()) -> Importer {
        Importer(source: source) { files in
            calls.append(files.map(\.lastPathComponent))
            return files.map { refusing.contains($0.lastPathComponent) ? nil : "ID-" + $0.lastPathComponent }
        }
    }

    @Test func findsFoldersWithManifestsAndTheirAudioInTrackOrder() throws {
        try makeFolder("B - Album", files: ["10 Ten.mp3", "2 Two.mp3", "cover.jpg", "CD2/1 One.M4A"], purchase: purchase(title: "Album"))
        try makeFolder("A - Single", files: ["A - Single.wav"], purchase: purchase(title: "Single", id: 7))
        try FileManager.default.createDirectory(at: source.appending(path: "Not ours"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appending(path: ".partial-9"), withIntermediateDirectories: true)

        let folders = try importer().folders()

        #expect(folders.map(\.purchase.title) == ["Single", "Album"])
        #expect(folders[1].audioFiles.map { $0.pathComponents.suffix(2).joined(separator: "/") }
            == ["B - Album/2 Two.mp3", "B - Album/10 Ten.mp3", "CD2/1 One.M4A"])
        #expect(folders.allSatisfy { !$0.isImported })
    }

    @Test func missingSourceHasNoFolders() throws {
        #expect(try importer().folders().isEmpty)
    }

    @Test func importWritesReceiptAndMarksFolderImported() throws {
        let url = try makeFolder("Artist - Title", files: ["1 One.mp3", "2 Two.mp3"])
        let importer = importer(refusing: ["2 Two.mp3"])
        let folder = try #require(try importer.folder(at: url))

        #expect(try importer.importFolder(folder) == .imported(added: 1, of: 2))

        let receipt = try JSONDecoder.iso8601.decode(
            Importer.Receipt.self, from: Data(contentsOf: url.appending(path: Importer.receiptName)))
        #expect(receipt.persistentIDs == ["ID-1 One.mp3"])
        #expect(receipt.notAdded == ["2 Two.mp3"])
        #expect(try importer.folder(at: url)?.isImported == true)
    }

    @Test func nothingAddedThrowsAndLeavesNoReceipt() throws {
        let url = try makeFolder("Artist - Title", files: ["1 One.mp3"])
        let importer = importer(refusing: ["1 One.mp3"])
        let folder = try #require(try importer.folder(at: url))

        #expect(throws: ImportError.self) { try importer.importFolder(folder) }
        #expect(try importer.folder(at: url)?.isImported == false)
    }

    @Test func folderWithoutAudioIsNotSentToMusic() throws {
        let url = try makeFolder("Artist - Title", files: ["cover.jpg"])
        let calls = Recorder<[String]>()
        let importer = importer(calls: calls)

        #expect(try importer.importFolder(try #require(try importer.folder(at: url))) == .noAudio)
        #expect(calls.values.isEmpty)
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

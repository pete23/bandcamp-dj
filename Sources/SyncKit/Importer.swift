import BandcampKit
import Foundation
import MusicLibraryKit

/// Adds folders written by `Downloader` to the Music library.
///
/// Each imported folder gets a receipt listing what Music added, so re-runs skip it even when the
/// library match for its purchase is imperfect (which would otherwise import it twice).
public struct Importer: Sendable {
    /// A downloaded purchase.
    public struct Folder: Sendable, Equatable {
        public var url: URL
        public var purchase: Purchase
        /// In path order, which is track order for Bandcamp's zips.
        public var audioFiles: [URL]
        public var isImported: Bool
    }

    public enum Outcome: Sendable, Equatable {
        case imported(added: Int, of: Int)
        case noAudio
    }

    /// What was imported from a folder, written into it.
    struct Receipt: Codable {
        var importedAt: Date
        var persistentIDs: [String]
        /// Files Music didn't add, relative to the folder.
        var notAdded: [String]
    }

    public static let receiptName = ".bandcamp-imported.json"
    static let audioExtensions: Set = ["mp3", "m4a", "aac", "aif", "aiff", "wav"]

    /// Adds files to Music, returning a persistent ID (or nil) for each.
    public typealias AddFiles = @Sendable ([URL]) throws -> [String?]

    public let source: URL
    let add: AddFiles

    public init(source: URL, add: @escaping AddFiles = MusicApp.add) {
        self.source = source
        self.add = add
    }

    /// The downloaded purchases in `source`, by folder name. Folders without a manifest are ignored.
    public func folders() throws -> [Folder] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return [] }
        return try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap(folder(at:))
    }

    /// The downloaded purchase in `url`, or nil if it has no manifest.
    public func folder(at url: URL) throws -> Folder? {
        let manifest = url.appending(path: Downloader.manifestName)
        guard let data = try? Data(contentsOf: manifest) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Folder(
            url: url,
            purchase: try decoder.decode(Purchase.self, from: data),
            audioFiles: Self.audioFiles(in: url),
            isImported: FileManager.default.fileExists(atPath: url.appending(path: Self.receiptName).path))
    }

    /// Adds the folder's audio files to Music and writes its receipt. Throws if Music added none,
    /// leaving no receipt so a later run tries again.
    public func importFolder(_ folder: Folder) throws -> Outcome {
        guard !folder.audioFiles.isEmpty else { return .noAudio }
        let ids = try add(folder.audioFiles)
        let added = ids.compactMap { $0 }
        guard !added.isEmpty else { throw ImportError.nothingAdded(folder.audioFiles.count) }

        let base = folder.url.standardizedFileURL.path + "/"
        let receipt = Receipt(
            importedAt: Date(), persistentIDs: added,
            notAdded: zip(folder.audioFiles, ids).filter { $0.1 == nil }.map {
                String($0.0.standardizedFileURL.path.dropFirst(base.count))
            })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(receipt).write(to: folder.url.appending(path: Self.receiptName))
        return .imported(added: added.count, of: folder.audioFiles.count)
    }

    static func audioFiles(in folder: URL) -> [URL] {
        let files = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: .skipsHiddenFiles)
        return (files?.allObjects as? [URL] ?? [])
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

public enum ImportError: Error, CustomStringConvertible, LocalizedError {
    case nothingAdded(Int)

    public var description: String {
        switch self {
        case .nothingAdded(let count): "Music didn't add any of the \(count) files."
        }
    }

    public var errorDescription: String? { description }
}

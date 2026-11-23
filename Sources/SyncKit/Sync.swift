import BandcampKit
import Foundation
import MusicLibraryKit

/// Where a purchase has got to on its way into Music.
public struct SyncItem: Codable, Sendable, Equatable, Identifiable {
    public enum Stage: Codable, Sendable, Equatable {
        /// Not in Music and not downloaded.
        case missing
        /// In the download folder, not yet imported.
        case downloaded(folder: Importer.Folder)
        /// Imported by us, though the library match may not find it under the name Music gave it.
        case imported
        case inMusic(match: LibraryMatch)
    }

    public var purchase: Purchase
    public var stage: Stage

    public var id: Int { purchase.saleItemID }

    public var isInMusic: Bool {
        switch stage {
        case .imported, .inMusic: true
        case .missing, .downloaded: false
        }
    }
}

extension SyncItem.Stage: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missing: "Not downloaded"
        case .downloaded: "Downloaded, not imported"
        case .imported: "Imported"
        case .inMusic(let match):
            "In Music: \(match.artist) – \(match.title) (\(match.kind.rawValue)\(match.reason == .bandcampSite ? ", via Bandcamp link" : ""))"
        }
    }
}

/// The steps of a sync, shared by the command line and the app: see where recent purchases have
/// got to, download the missing ones, and import the downloads into Music. Front ends add the
/// asking (for the identity cookie) and the showing.
public struct Sync: Sendable {
    // Defaults the command line and the app share.
    public static let defaultFolder = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Downloads/bandcamp-sync", directoryHint: .isDirectory)
    public static let defaultFormat = DownloadFormat.mp3320
    /// How many recent purchases to check.
    public static let defaultLimit = 50
    /// Most downloads at once.
    public static let defaultParallel = 6

    public let downloader: Downloader
    public let importer: Importer

    public init(
        client: BandcampClient, format: DownloadFormat = Sync.defaultFormat, folder: URL,
        addToMusic: @escaping Importer.AddFiles = MusicApp.add
    ) {
        downloader = Downloader(client: client, format: format, destination: folder)
        importer = Importer(source: folder, add: addToMusic)
    }

    /// Each purchase checked against the library, then the download folder.
    public func items(for purchases: [Purchase], index: LibraryIndex) throws -> [SyncItem] {
        try purchases.map { try item(for: $0, index: index) }
    }

    public func item(for purchase: Purchase, index: LibraryIndex) throws -> SyncItem {
        if let match = index.match(purchase) { return SyncItem(purchase: purchase, stage: .inMusic(match: match)) }
        guard let folder = try importer.folder(at: downloader.folder(for: purchase)) else {
            return SyncItem(purchase: purchase, stage: .missing)
        }
        return SyncItem(purchase: purchase, stage: folder.isImported ? .imported : .downloaded(folder: folder))
    }

    /// The download folders of `items` that are there and not yet imported, in the same order;
    /// for importing straight after downloading.
    public func foldersToImport(_ items: [SyncItem]) throws -> [Importer.Folder] {
        try items.filter { !$0.isInMusic }
            .compactMap { try importer.folder(at: downloader.folder(for: $0.purchase)) }
            .filter { !$0.isImported }
    }
}

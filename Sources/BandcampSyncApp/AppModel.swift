import BandcampKit
import Foundation
import MusicLibraryKit
import Observation
import SyncKit

/// One purchase in the window: where it's got to, and what's happening to it right now.
struct Row: Identifiable {
    enum Activity: Equatable {
        case queued
        case downloading(Downloader.Progress)
        case importing
        case failed(String)
    }

    var item: SyncItem
    var activity: Activity?

    var id: Int { item.id }
}

/// The window's state. The work itself is `Sync`'s, exactly as the command line does it: this
/// only asks for the identity cookie, keeps the rows and feeds them progress.
@MainActor @Observable
final class AppModel {
    enum Phase { case idle, checking, syncing }

    let preferences = Preferences()
    private(set) var rows: [Row] = []
    private(set) var phase = Phase.idle
    private(set) var checkedAt: Date?
    var error: String?
    /// Set while waiting for the user to enter the identity cookie.
    private(set) var identityRequest: PromptReason?

    private var identityAnswer: CheckedContinuation<String?, Never>?
    private var identity: String?
    private var purchases: [Purchase] = []
    private var index: LibraryIndex?

    var notInMusic: [Row] { rows.filter { !$0.item.isInMusic } }
    var canSync: Bool { phase == .idle && !notInMusic.isEmpty }

    private func makeSync(_ identity: String) -> Sync {
        Sync(client: BandcampClient(identity: identity), format: preferences.format, folder: preferences.folder)
    }

    /// Fetches recent purchases and sees where each has got to.
    func check() async {
        guard phase == .idle else { return }
        phase = .checking
        error = nil
        defer { phase = .idle }
        do {
            let limit = preferences.limit
            (identity, purchases) = try await withIdentity(
                credentials: Credentials(),
                interactive: true,
                prompt: { reason in await self.askForIdentity(reason) },
                operation: { ($0, try await BandcampClient(identity: $0).purchases(limit: limit)) })
            index = try await Self.readLibrary()
            try restage()
            checkedAt = Date()
        } catch BandcampError.aborted {
            // The user cancelled the cookie sheet.
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Re-reads each purchase's stage from the library read last time and the download folder,
    /// e.g. after the folder setting changes.
    func restage() throws {
        guard let identity, let index else { return }
        rows = try makeSync(identity).items(for: purchases, index: index).map { Row(item: $0) }
    }

    /// Downloads what's missing, then imports everything downloaded and not yet in Music.
    func sync() async {
        guard canSync, let identity, index != nil else { return }
        phase = .syncing
        error = nil
        defer {
            phase = .idle
            for i in rows.indices where rows[i].activity == .queued { rows[i].activity = nil }
        }
        let sync = makeSync(identity)
        for i in rows.indices where !rows[i].item.isInMusic { rows[i].activity = .queued }

        let downloads = rows.indices.filter { rows[$0].item.stage == .missing }
        let purchases = downloads.map { rows[$0].item.purchase }
        let parallel = preferences.parallel
        do {
            for try await (i, status) in Self.stream({ update in
                _ = await sync.downloader.downloadAll(purchases, parallel: parallel, update: update)
            }) {
                let row = downloads[i]
                switch status {
                case .queued: rows[row].activity = .queued
                case .active(let progress): rows[row].activity = .downloading(progress)
                case .finished(.noDownload): rows[row].activity = .failed("No digital download")
                case .finished: refresh(row, with: sync, activity: .queued)
                case .failed(let message): rows[row].activity = .failed(message)
                }
            }

            let folders = try sync.foldersToImport(rows.map(\.item))
            let imports = folders.compactMap { folder in rows.firstIndex { $0.id == folder.purchase.saleItemID } }
            for try await (i, status) in Self.stream({ update in
                _ = try await sync.importer.importAll(folders, update: update)
            }) {
                let row = imports[i]
                switch status {
                case .queued: rows[row].activity = .queued
                case .importing: rows[row].activity = .importing
                case .finished(.imported): refresh(row, with: sync, activity: nil)
                case .finished(.noAudio): rows[row].activity = .failed("No audio files in the download")
                case .failed(let message): rows[row].activity = .failed(message)
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func refresh(_ row: Int, with sync: Sync, activity: Row.Activity?) {
        if let index, let item = try? sync.item(for: rows[row].item.purchase, index: index) { rows[row].item = item }
        rows[row].activity = activity
    }

    /// Where a row's files are, if it has been downloaded.
    func folder(for row: Row) -> URL? {
        let url = Downloader.folder(for: row.item.purchase, in: preferences.folder)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Identity

    private func askForIdentity(_ reason: PromptReason) async -> String? {
        identityRequest = reason
        return await withCheckedContinuation { identityAnswer = $0 }
    }

    /// The cookie the user entered, or nil if they cancelled.
    func answerIdentity(_ value: String?) {
        identityRequest = nil
        identityAnswer?.resume(returning: value)
        identityAnswer = nil
    }

    // MARK: Off the main actor

    nonisolated private static func readLibrary() async throws -> LibraryIndex {
        LibraryIndex(tracks: try MusicLibrary.tracks())
    }

    /// Runs `work` off the main actor and yields the updates it reports, in order, ending when
    /// it's done or throws. (Hopping to the main actor per update could reorder them.)
    private static func stream<Status: Sendable>(
        _ work: @escaping @Sendable (@escaping @Sendable (Int, Status) -> Void) async throws -> Void
    ) -> AsyncThrowingStream<(Int, Status), any Error> {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: (Int, Status).self)
        Task.detached {
            do {
                try await work { continuation.yield(($0, $1)) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }
}

/// The settings window's values, kept in user defaults. Defaults are the command line's.
@MainActor @Observable
final class Preferences {
    private let defaults = UserDefaults.standard

    var format: DownloadFormat {
        didSet { defaults.set(format.rawValue, forKey: "format") }
    }
    var folder: URL {
        didSet { defaults.set(folder.path, forKey: "folder") }
    }
    var limit: Int {
        didSet { defaults.set(limit, forKey: "limit") }
    }
    var parallel: Int {
        didSet { defaults.set(parallel, forKey: "parallel") }
    }

    init() {
        format = defaults.string(forKey: "format").flatMap(DownloadFormat.init(rawValue:)) ?? Sync.defaultFormat
        folder = defaults.string(forKey: "folder").map { URL(filePath: $0, directoryHint: .isDirectory) } ?? Sync.defaultFolder
        limit = defaults.object(forKey: "limit") as? Int ?? Sync.defaultLimit
        parallel = defaults.object(forKey: "parallel") as? Int ?? Sync.defaultParallel
    }
}

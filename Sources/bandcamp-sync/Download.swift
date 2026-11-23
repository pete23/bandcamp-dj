import ArgumentParser
import BandcampKit
import Foundation
import MusicLibraryKit
import SyncKit

extension DownloadFormat: ExpressibleByArgument {}

struct Download: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download recent Bandcamp purchases that aren't in your Music library.",
        discussion: "Each purchase goes in its own folder; ones already downloaded there are skipped.")

    @Option(help: "How many recent purchases to check.")
    var limit = Sync.defaultLimit

    @Option(help: "Audio format.")
    var format = Sync.defaultFormat

    @Option(help: "Folder to download into. (default: ~/Downloads/bandcamp-sync)", transform: { URL(filePath: ($0 as NSString).expandingTildeInPath) })
    var to = Sync.defaultFolder

    @Option(help: "Most downloads to run at once.")
    var parallel = Sync.defaultParallel

    @Flag(name: .customLong("import"), help: "Then add the downloads to Music, as the import command does.")
    var importToMusic = false

    @Flag(help: "Show what would be downloaded without downloading.")
    var dryRun = false

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
        guard parallel > 0 else { throw ValidationError("--parallel must be at least 1.") }
    }

    func run() async throws {
        let (identity, purchases) = try await Terminal.recentPurchases(limit: limit)
        let sync = Sync(client: BandcampClient(identity: identity), format: format, folder: to)
        let missing = try sync.items(for: purchases, index: LibraryIndex(tracks: try MusicLibrary.tracks()))
            .filter { !$0.isInMusic }

        guard !missing.isEmpty else {
            print("All of the last \(purchases.count) purchases are already in Music.")
            return
        }
        print("\(missing.count) of the last \(purchases.count) purchases are not in Music.\n")

        let names = missing.map { "\($0.purchase.artist) – \($0.purchase.title)" }
        let initial = missing.map { item -> DownloadStatus in
            if case .downloaded(let folder) = item.stage { .finished(.alreadyDownloaded(folder.url)) } else { .queued }
        }
        if dryRun {
            for (status, name) in zip(initial, names) {
                print(status == .queued ? "Would download: \(name)" : "Already downloaded: \(name)")
            }
            return
        }

        let board = ProgressBoard(names: names, initial: initial, parallel: parallel)
        board.start()
        let pending = missing.indices.filter { initial[$0] == .queued }
        let results = await sync.downloader.downloadAll(pending.map { missing[$0].purchase }, parallel: parallel) {
            board.update(pending[$0], $1)
        }
        board.finish()

        let failures = zip(pending, results).compactMap { index, status -> String? in
            if case .failed(let message) = status { "  \(names[index]): \(message)" } else { nil }
        }
        let downloaded = results.filter { if case .finished(.downloaded) = $0 { true } else { false } }.count
        print("\nDownloaded \(downloaded) to \(to.path).")
        if !failures.isEmpty {
            Terminal.printError("\n\(failures.count) failed:\n" + failures.joined(separator: "\n"))
        }

        if importToMusic {
            let folders = try sync.foldersToImport(missing)
            if !folders.isEmpty {
                print()
                try await Import.importAll(folders, with: sync.importer)
            }
        }
        if !failures.isEmpty { throw ExitCode.failure }
    }
}

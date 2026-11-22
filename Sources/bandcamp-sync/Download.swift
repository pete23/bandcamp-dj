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
    var limit = 50

    @Option(help: "Audio format.")
    var format = DownloadFormat.mp3320

    @Option(help: "Folder to download into. (default: ~/Downloads/bandcamp-sync)", transform: { URL(filePath: ($0 as NSString).expandingTildeInPath) })
    var to = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Downloads/bandcamp-sync")

    @Option(help: "Most downloads to run at once.")
    var parallel = 6

    @Flag(help: "Show what would be downloaded without downloading.")
    var dryRun = false

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
        guard parallel > 0 else { throw ValidationError("--parallel must be at least 1.") }
    }

    func run() async throws {
        let (identity, purchases) = try await withIdentity(
            credentials: Credentials(),
            interactive: isatty(STDIN_FILENO) == 1,
            prompt: Terminal.promptForIdentity,
            saved: { Terminal.printError("Saved identity cookie to \($0.path).") },
            operation: { ($0, try await BandcampClient(identity: $0).purchases(limit: limit)) }
        )
        let index = LibraryIndex(tracks: try MusicLibrary.tracks())
        let missing = purchases.filter { index.match($0) == nil }
        let downloader = Downloader(client: BandcampClient(identity: identity), format: format, destination: to)

        guard !missing.isEmpty else {
            print("All of the last \(purchases.count) purchases are already in Music.")
            return
        }
        print("\(missing.count) of the last \(purchases.count) purchases are not in Music.\n")

        let names = missing.map { "\($0.artist) – \($0.title)" }
        if dryRun {
            for (purchase, name) in zip(missing, names) {
                print(downloader.isDownloaded(purchase) ? "Already downloaded: \(name)" : "Would download: \(name)")
            }
            return
        }

        let initial = missing.map { purchase -> DownloadStatus in
            downloader.isDownloaded(purchase) ? .finished(.alreadyDownloaded(downloader.folder(for: purchase))) : .queued
        }
        let board = ProgressBoard(names: names, initial: initial, parallel: parallel)
        board.start()
        let pending = missing.indices.filter { initial[$0] == .queued }
        let results = await downloader.downloadAll(pending.map { missing[$0] }, parallel: parallel) { index, status in
            board.update(pending[index], status)
        }
        board.finish()

        let failures = zip(pending, results).compactMap { index, status -> String? in
            if case .failed(let message) = status { "  \(names[index]): \(message)" } else { nil }
        }
        let downloaded = results.filter { if case .finished(.downloaded) = $0 { true } else { false } }.count
        print("\nDownloaded \(downloaded) to \(to.path).")
        if !failures.isEmpty {
            Terminal.printError("\n\(failures.count) failed:\n" + failures.joined(separator: "\n"))
            throw ExitCode.failure
        }
    }
}

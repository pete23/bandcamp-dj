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

    @Flag(help: "Show what would be downloaded without downloading.")
    var dryRun = false

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
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

        var failures = 0
        for purchase in missing {
            let name = "\(purchase.artist) – \(purchase.title)"
            if dryRun {
                print(downloader.isDownloaded(purchase) ? "Already downloaded: \(name)" : "Would download: \(name)")
                continue
            }
            do {
                let outcome = try await downloader.download(purchase) { option in
                    print("Downloading \(name) (\(option.size ?? "size unknown"))…")
                }
                switch outcome {
                case .downloaded(let folder): print("  → \(folder.path)")
                case .alreadyDownloaded: print("Already downloaded: \(name)")
                case .noDownload: print("No digital download: \(name)")
                }
            } catch {
                failures += 1
                Terminal.printError("Failed: \(name): \(error.localizedDescription)")
            }
        }
        if failures > 0 {
            Terminal.printError("\n\(failures) download\(failures == 1 ? "" : "s") failed.")
            throw ExitCode.failure
        }
    }
}

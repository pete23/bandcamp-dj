import ArgumentParser
import Foundation
import MusicLibraryKit
import SyncKit

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add downloaded purchases to your Music library.",
        discussion: """
            Imports each folder written by `download` whose purchase isn't in Music yet, by \
            scripting Music.app. Imported folders are marked and skipped on later runs. Unless \
            Music's \"Copy files to Music Media folder\" setting is on, Music plays the files from \
            the download folder, so keep it.
            """)

    @Option(help: "Folder the purchases were downloaded into. (default: ~/Downloads/bandcamp-sync)", transform: { URL(filePath: ($0 as NSString).expandingTildeInPath) })
    var from = Download.defaultFolder

    @Flag(help: "Show what would be imported without importing.")
    var dryRun = false

    func run() async throws {
        let importer = Importer(source: from)
        let folders = try importer.folders()
        guard !folders.isEmpty else {
            print("No downloaded purchases in \(from.path).")
            return
        }
        let index = LibraryIndex(tracks: try MusicLibrary.tracks())
        try Self.importAll(folders, with: importer, index: index, dryRun: dryRun)
    }

    /// Imports the folders not yet imported or in the library, printing a line for each.
    static func importAll(_ folders: [Importer.Folder], with importer: Importer, index: LibraryIndex, dryRun: Bool) throws {
        var imported = 0, skipped = 0
        var failures: [String] = []
        for folder in folders {
            let name = "\(folder.purchase.artist) – \(folder.purchase.title)"
            if folder.isImported || index.match(folder.purchase) != nil {
                skipped += 1
                continue
            }
            if dryRun {
                print("Would import: \(name) (\(folder.audioFiles.count) files)")
                continue
            }
            do {
                switch try importer.importFolder(folder) {
                case .imported(let added, let total) where added == total:
                    print("Imported: \(name) (\(added) tracks)")
                    imported += 1
                case .imported(let added, let total):
                    print("Imported \(added) of \(total) tracks: \(name)")
                    imported += 1
                case .noAudio:
                    failures.append("  \(name): no audio files in \(folder.url.lastPathComponent)")
                }
            } catch MusicAppError.notAuthorized {
                // Every other folder would fail the same way.
                throw MusicAppError.notAuthorized
            } catch {
                failures.append("  \(name): \(error.localizedDescription)")
            }
        }
        if dryRun { return }
        print("\nImported \(imported) purchases; \(skipped) were already in Music.")
        if !failures.isEmpty {
            Terminal.printError("\n\(failures.count) failed:\n" + failures.joined(separator: "\n"))
            throw ExitCode.failure
        }
    }
}

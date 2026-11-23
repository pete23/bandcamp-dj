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
    var from = Sync.defaultFolder

    @Flag(help: "Show what would be imported without importing.")
    var dryRun = false

    func run() async throws {
        let importer = Importer(source: from)
        guard !(try importer.folders().isEmpty) else {
            print("No downloaded purchases in \(from.path).")
            return
        }
        let folders = try importer.importable(index: LibraryIndex(tracks: try MusicLibrary.tracks()))
        guard !folders.isEmpty else {
            print("Every download in \(from.path) is already in Music.")
            return
        }
        if dryRun {
            for folder in folders { print("Would import: \(Self.name(folder)) (\(folder.audioFiles.count) files)") }
            return
        }
        try await Self.importAll(folders, with: importer)
    }

    /// Imports the folders, printing a line for each as it finishes.
    static func importAll(_ folders: [Importer.Folder], with importer: Importer) async throws {
        let results = try await importer.importAll(folders) { index, status in
            if case .finished(.imported(let added, let total)) = status {
                print(added == total
                    ? "Imported: \(name(folders[index])) (\(added) tracks)"
                    : "Imported \(added) of \(total) tracks: \(name(folders[index]))")
            }
        }
        let failures = zip(folders, results).compactMap { folder, status -> String? in
            switch status {
            case .finished(.noAudio): "  \(name(folder)): no audio files in \(folder.url.lastPathComponent)"
            case .failed(let message): "  \(name(folder)): \(message)"
            case .queued, .importing, .finished(.imported): nil
            }
        }
        print("\nImported \(folders.count - failures.count) of \(folders.count) purchases.")
        if !failures.isEmpty {
            Terminal.printError("\n\(failures.count) failed:\n" + failures.joined(separator: "\n"))
            throw ExitCode.failure
        }
    }

    static func name(_ folder: Importer.Folder) -> String {
        "\(folder.purchase.artist) – \(folder.purchase.title)"
    }
}

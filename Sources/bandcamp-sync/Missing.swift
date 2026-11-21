import ArgumentParser
import BandcampKit
import Foundation
import MusicLibraryKit
import SyncKit

struct Missing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List recent Bandcamp purchases that aren't in your Music library.")

    @Option(help: "How many recent purchases to check.")
    var limit = 50

    @Flag(help: "Also show purchases that are in the library, and what they matched.")
    var matched = false

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
    }

    func run() async throws {
        let purchases = try await withIdentity(
            credentials: Credentials(),
            interactive: isatty(STDIN_FILENO) == 1,
            prompt: Terminal.promptForIdentity,
            saved: { Terminal.printError("Saved identity cookie to \($0.path).") },
            operation: { try await BandcampClient(identity: $0).purchases(limit: limit) }
        )
        let index = LibraryIndex(tracks: try MusicLibrary.tracks())
        let all = purchases.map(index.status)
        let missingCount = all.filter(\.isMissing).count
        let statuses = matched ? all : all.filter(\.isMissing)

        if json {
            print(try Output.json(statuses))
            return
        }
        if !statuses.isEmpty {
            let header = ["Date", "Artist", "Title", "Type"] + (matched ? ["In Music"] : [])
            print(Output.table(header, statuses.map { status in
                let p = status.purchase
                let row = [Output.day(p.purchasedAt), p.artist, p.title, p.itemType.rawValue]
                guard matched else { return row }
                guard let m = status.match else { return row + ["MISSING"] }
                let via = m.reason == .bandcampSite ? ", via Bandcamp link" : ""
                return row + ["\(m.artist) – \(m.title) (\(m.kind.rawValue)\(via))"]
            }))
            print()
        }
        print("\(missingCount) of the last \(purchases.count) purchases are not in Music.")
    }
}

import ArgumentParser
import BandcampKit
import Foundation
import MusicLibraryKit
import SyncKit

struct Missing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List recent Bandcamp purchases that aren't in your Music library.",
        discussion: "Shows how far each has got: not downloaded, or downloaded and waiting to be imported.")

    @Option(help: "How many recent purchases to check.")
    var limit = Sync.defaultLimit

    @Option(help: "Folder purchases are downloaded into. (default: ~/Downloads/bandcamp-sync)", transform: { URL(filePath: ($0 as NSString).expandingTildeInPath) })
    var downloads = Sync.defaultFolder

    @Flag(help: "Also show purchases that are in the library, and what they matched.")
    var matched = false

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
    }

    func run() async throws {
        let (identity, purchases) = try await Terminal.recentPurchases(limit: limit)
        let sync = Sync(client: BandcampClient(identity: identity), folder: downloads)
        let all = try sync.items(for: purchases, index: LibraryIndex(tracks: try MusicLibrary.tracks()))
        let missingCount = all.filter { !$0.isInMusic }.count
        let items = matched ? all : all.filter { !$0.isInMusic }

        if json {
            print(try Output.json(items))
            return
        }
        if !items.isEmpty {
            print(Output.table(
                ["Date", "Artist", "Title", "Type", "Status"],
                items.map { item in
                    let p = item.purchase
                    return [Output.day(p.purchasedAt), p.artist, p.title, p.itemType.rawValue, item.stage.description]
                }))
            print()
        }
        print("\(missingCount) of the last \(purchases.count) purchases are not in Music.")
    }
}

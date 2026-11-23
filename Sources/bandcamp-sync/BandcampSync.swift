import ArgumentParser
import BandcampKit
import Foundation

@main
struct BandcampSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bandcamp-sync",
        abstract: "Sync your Bandcamp purchases into Apple Music.",
        subcommands: [List.self, Music.self, Missing.self, Download.self, Import.self]
    )
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List your recent Bandcamp purchases.")

    @Option(help: "How many purchases to show.")
    var limit = 10

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func validate() throws {
        guard limit > 0 else { throw ValidationError("--limit must be at least 1.") }
    }

    func run() async throws {
        let purchases = try await Terminal.recentPurchases(limit: limit).purchases
        if json {
            print(try Output.json(purchases))
        } else if purchases.isEmpty {
            print("No purchases found.")
        } else {
            print(Output.table(
                ["Date", "Artist", "Title", "Type"],
                purchases.map { [Output.day($0.purchasedAt), $0.artist, $0.title, $0.itemType.rawValue] }))
        }
    }
}

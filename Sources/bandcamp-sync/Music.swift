import ArgumentParser
import Foundation
import MusicLibraryKit

struct Music: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List the albums in your Music library, most recently added first.")

    @Flag(help: "List tracks instead of albums.")
    var tracks = false

    @Option(help: "Show at most this many.")
    var limit: Int?

    @Flag(help: "Print JSON instead of a table.")
    var json = false

    func validate() throws {
        if let limit, limit < 1 { throw ValidationError("--limit must be at least 1.") }
    }

    func run() throws {
        let all = try MusicLibrary.tracks(includeLocations: json && tracks)
        if tracks {
            let shown = all.sorted { a, b in
                let (addedA, addedB) = (a.addedAt ?? .distantPast, b.addedAt ?? .distantPast)
                if addedA != addedB { return addedA > addedB }
                return (a.album ?? "", a.discNumber ?? 0, a.trackNumber ?? 0)
                    < (b.album ?? "", b.discNumber ?? 0, b.trackNumber ?? 0)
            }.prefix(limit ?? .max)
            print(json ? try Output.json(Array(shown)) : Output.table(
                ["Added", "Artist", "Album", "#", "Title"],
                shown.map {
                    [Output.day($0.addedAt), $0.artist ?? "", $0.album ?? "",
                     $0.trackNumber.map(String.init) ?? "", $0.title]
                }))
        } else {
            let shown = Album.group(all).prefix(limit ?? .max)
            print(json ? try Output.json(Array(shown)) : Output.table(
                ["Added", "Artist", "Album", "Tracks"],
                shown.map { [Output.day($0.addedAt), $0.artist, $0.title, String($0.trackCount)] }))
        }
    }
}

import ArgumentParser
import BandcampKit
import Foundation

@main
struct BandcampSync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bandcamp-sync",
        abstract: "Sync your Bandcamp purchases into Apple Music.",
        subcommands: [List.self]
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
        let purchases = try await withIdentity(
            credentials: Credentials(),
            interactive: isatty(STDIN_FILENO) == 1,
            prompt: Terminal.promptForIdentity,
            saved: { Terminal.printError("Saved identity cookie to \($0.path).") },
            operation: { try await BandcampClient(identity: $0).purchases(limit: limit) }
        )
        print(json ? try Output.json(purchases) : Output.table(purchases))
    }
}

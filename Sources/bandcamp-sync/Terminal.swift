import BandcampKit
import Foundation

enum Terminal {
    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Asks for the identity cookie on the terminal without echoing it.
    static func promptForIdentity(_ reason: PromptReason) throws -> String? {
        if reason == .rejected {
            printError("Bandcamp rejected the saved identity cookie — it has probably expired.\n")
        }
        printError(Credentials.instructions + "\n")
        var buffer = [CChar](repeating: 0, count: 8192)
        guard readpassphrase("Paste identity cookie (empty to abort): ", &buffer, buffer.count,
                             RPP_REQUIRE_TTY) != nil
        else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}

enum Output {
    static func table(_ purchases: [Purchase]) -> String {
        guard !purchases.isEmpty else { return "No purchases found." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let rows = [["Date", "Artist", "Title", "Type"]] + purchases.map {
            [formatter.string(from: $0.purchasedAt), $0.artist, $0.title, $0.itemType.rawValue]
        }
        let widths = (0..<4).map { column in rows.map { $0[column].count }.max() ?? 0 }
        return rows.map { row in
            zip(row, widths).map { cell, width in
                cell + String(repeating: " ", count: width - cell.count)
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    static func json(_ purchases: [Purchase]) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(purchases), as: UTF8.self)
    }
}

import BandcampKit
import Foundation

enum Terminal {
    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// The most recent purchases and the identity cookie that fetched them, asking for the
    /// cookie when there is none or Bandcamp rejects it.
    static func recentPurchases(limit: Int) async throws -> (identity: String, purchases: [Purchase]) {
        try await withIdentity(
            credentials: Credentials(),
            interactive: isatty(STDIN_FILENO) == 1,
            prompt: promptForIdentity,
            saved: { printError("Saved identity cookie to \($0.path).") },
            operation: { ($0, try await BandcampClient(identity: $0).purchases(limit: limit)) }
        )
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
    static func table(_ header: [String], _ rows: [[String]]) -> String {
        let rows = [header] + rows
        let widths = header.indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        return rows.map { row in
            zip(row, widths).map { cell, width in
                cell + String(repeating: " ", count: width - cell.count)
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }.joined(separator: "\n")
    }

    static func day(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

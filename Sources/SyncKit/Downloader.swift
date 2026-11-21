import BandcampKit
import Foundation

/// Downloads purchases into `destination/<Artist> - <Title>/`, one folder per purchase.
///
/// A folder only appears once its download is complete (work happens in a hidden `.partial-…`
/// folder first), so an existing folder means "already downloaded" and re-runs skip it.
public struct Downloader: Sendable {
    public enum Outcome: Sendable, Equatable {
        case downloaded(URL)
        case alreadyDownloaded(URL)
        /// The purchase has no digital download (e.g. merch only).
        case noDownload
    }

    /// Written into each folder so the import step knows what it holds.
    public static let manifestName = ".bandcamp-purchase.json"

    public let client: BandcampClient
    public let format: DownloadFormat
    public let destination: URL

    public init(client: BandcampClient, format: DownloadFormat, destination: URL) {
        self.client = client
        self.format = format
        self.destination = destination
    }

    public func folder(for purchase: Purchase) -> URL {
        destination.appending(path: Self.safeName("\(purchase.artist) - \(purchase.title)"), directoryHint: .isDirectory)
    }

    public func isDownloaded(_ purchase: Purchase) -> Bool {
        FileManager.default.fileExists(atPath: folder(for: purchase).path)
    }

    /// Downloads one purchase. `willDownload` is told the size before the transfer starts.
    public func download(
        _ purchase: Purchase, willDownload: (DownloadOption) -> Void = { _ in }
    ) async throws -> Outcome {
        let folder = folder(for: purchase)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { return .alreadyDownloaded(folder) }
        guard let option = try await client.downloadOption(for: purchase, format: format) else { return .noDownload }

        willDownload(option)
        let file = try await client.download(option)
        defer { try? fm.removeItem(at: file) }

        let partial = destination.appending(path: ".partial-\(purchase.saleItemID)", directoryHint: .isDirectory)
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            if try Self.isZip(file) {
                try Self.unzip(file, into: partial)
            } else {
                let name = Self.safeName("\(purchase.artist) - \(purchase.title)") + "." + format.fileExtension
                try fm.moveItem(at: file, to: partial.appending(path: name))
            }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(purchase).write(to: partial.appending(path: Self.manifestName))
            try fm.moveItem(at: partial, to: folder)
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
        return .downloaded(folder)
    }

    static func isZip(_ file: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04])
    }

    static func unzip(_ file: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", file.path, folder.path]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw DownloadError.unzipFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// A file name without path separators or a leading dot, at most 200 characters.
    static func safeName(_ name: String) -> String {
        var safe = String(name.map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 })
            .trimmingCharacters(in: .whitespaces)
        while safe.hasPrefix(".") { safe.removeFirst() }
        if safe.isEmpty { safe = "Untitled" }
        return String(safe.prefix(200))
    }
}

public enum DownloadError: Error, CustomStringConvertible, LocalizedError {
    case unzipFailed(String)

    public var description: String {
        switch self {
        case .unzipFailed(let detail): "Couldn't unzip the download: \(detail)"
        }
    }

    public var errorDescription: String? { description }
}

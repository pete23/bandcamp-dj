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

    /// Where an in-flight download has got to.
    public enum Progress: Sendable, Equatable {
        /// Fetching the download page and resolving the file.
        case preparing
        case downloading(received: Int64, expected: Int64?)
        case unzipping
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

    /// Downloads one purchase, reporting progress along the way.
    public func download(
        _ purchase: Purchase, progress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> Outcome {
        let folder = folder(for: purchase)
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.path) { return .alreadyDownloaded(folder) }
        progress(.preparing)
        guard let option = try await client.downloadOption(for: purchase, format: format) else { return .noDownload }

        progress(.downloading(received: 0, expected: option.approximateBytes))
        let file = try await client.download(option) { received, expected in
            progress(.downloading(received: received, expected: expected))
        }
        defer { try? fm.removeItem(at: file) }

        let partial = destination.appending(path: ".partial-\(purchase.saleItemID)", directoryHint: .isDirectory)
        try? fm.removeItem(at: partial)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            if try Self.isZip(file) {
                progress(.unzipping)
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

    /// Downloads `purchases` with at most `parallel` at a time, reporting each one's status by
    /// its index. Failures are reported and don't stop the rest. Returns the final statuses.
    public func downloadAll(
        _ purchases: [Purchase], parallel: Int,
        update: @escaping @Sendable (Int, DownloadStatus) -> Void = { _, _ in }
    ) async -> [DownloadStatus] {
        var results = [DownloadStatus](repeating: .queued, count: purchases.count)
        await withTaskGroup(of: (Int, DownloadStatus).self) { group in
            var next = 0
            func start(_ index: Int, in group: inout TaskGroup<(Int, DownloadStatus)>) {
                group.addTask {
                    let status: DownloadStatus
                    do {
                        status = .finished(try await download(purchases[index]) { update(index, .active($0)) })
                    } catch {
                        status = .failed(error.localizedDescription)
                    }
                    update(index, status)
                    return (index, status)
                }
            }
            while next < min(max(parallel, 1), purchases.count) {
                start(next, in: &group)
                next += 1
            }
            for await (index, status) in group {
                results[index] = status
                if next < purchases.count {
                    start(next, in: &group)
                    next += 1
                }
            }
        }
        return results
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

/// One purchase's place in a batch of downloads.
public enum DownloadStatus: Sendable, Equatable {
    case queued
    case active(Downloader.Progress)
    case finished(Downloader.Outcome)
    case failed(String)

    public var isDone: Bool {
        switch self {
        case .queued, .active: false
        case .finished, .failed: true
        }
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

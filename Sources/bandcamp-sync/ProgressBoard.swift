import Foundation
import SyncKit

/// Shows every purchase in a batch with its live status, redrawn in place on a terminal.
/// When stdout isn't a terminal it prints one line per state change instead.
final class ProgressBoard: @unchecked Sendable {
    private let names: [String]
    private let parallel: Int
    private let live: Bool
    private let lock = NSLock()
    private var statuses: [DownloadStatus]
    private var drawnLines = 0
    private var overflowed = false
    private var ticker: Task<Void, Never>?
    private var finished = false

    init(names: [String], initial: [DownloadStatus], parallel: Int) {
        self.names = names
        self.statuses = initial
        self.parallel = parallel
        self.live = isatty(STDOUT_FILENO) == 1
    }

    func start() {
        guard live else {
            for (name, status) in zip(names, statuses) where status.isDone { print(Self.plain(status, name)) }
            return
        }
        Self.write("\u{1B}[?25l")  // hide cursor
        Self.restoreCursorOnInterrupt()
        redraw()
        ticker = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { break }
                self?.redraw()
            }
        }
    }

    func update(_ index: Int, _ status: DownloadStatus) {
        let previous = lock.withLock {
            let previous = statuses[index]
            statuses[index] = status
            return previous
        }
        // Without a live board, report starts and finishes but not every progress tick.
        if !live, status.isDone || previous == .queued {
            print(Self.plain(status, names[index]))
        }
    }

    func finish() {
        guard live else { return }
        ticker?.cancel()
        redraw()
        lock.withLock { finished = true }
        if lock.withLock({ overflowed }) {
            // The live view didn't fit; leave the whole list in the scrollback.
            print()
            for (name, status) in zip(names, lock.withLock { statuses }) {
                print(Self.line(status, name, width: Self.terminalSize().columns))
            }
        }
        Self.write("\u{1B}[?25h")
    }

    // MARK: Drawing

    private func redraw() {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        let (columns, rows) = Self.terminalSize()
        var lines = [header()]
        let all = Array(zip(statuses, names).enumerated())
        if all.count + 1 <= rows - 1 {
            lines += all.map { Self.line($0.element.0, $0.element.1, width: columns) }
        } else {
            // Too tall: active, failed and queued first (in purchase order), then a summary.
            overflowed = true
            let room = max(rows - 3, 1)
            func rank(_ status: DownloadStatus) -> Int {
                switch status {
                case .active: 0
                case .failed: 1
                case .queued: 2
                case .finished: 3
                }
            }
            let shown = all.sorted { (rank($0.element.0), $0.offset) < (rank($1.element.0), $1.offset) }
                .prefix(room).sorted { $0.offset < $1.offset }
            lines += shown.map { Self.line($0.element.0, $0.element.1, width: columns) }
            lines.append(Self.dim("  …and \(all.count - shown.count) more"))
        }

        var output = drawnLines > 0 ? "\u{1B}[\(drawnLines)A" : ""
        for line in lines { output += "\u{1B}[2K" + line + "\n" }
        // Clear anything left over from a taller previous frame.
        if drawnLines > lines.count { output += String(repeating: "\u{1B}[2K\n", count: drawnLines - lines.count) + "\u{1B}[\(drawnLines - lines.count)A" }
        drawnLines = lines.count
        Self.write(output)
    }

    private func header() -> String {
        var done = 0, active = 0, queued = 0, failed = 0
        for status in statuses {
            switch status {
            case .queued: queued += 1
            case .active: active += 1
            case .finished: done += 1
            case .failed: failed += 1
            }
        }
        var parts = ["\(done) done", "\(active) downloading", "\(queued) queued"]
        if failed > 0 { parts.append(Self.red("\(failed) failed")) }
        return Self.bold("\(statuses.count) purchases, \(parallel) at a time: ") + parts.joined(separator: ", ")
    }

    private static let statusWidth = 34

    static func line(_ status: DownloadStatus, _ name: String, width: Int) -> String {
        let (label, styled) = statusLabel(status)
        let padding = String(repeating: " ", count: max(statusWidth - label.count, 1))
        let room = max(width - statusWidth - 3, 10)
        let shortName = name.count > room ? String(name.prefix(room - 1)) + "…" : name
        return "  " + styled + padding + shortName
    }

    /// The plain text of the status column, and the same with colour.
    private static func statusLabel(_ status: DownloadStatus) -> (String, String) {
        switch status {
        case .queued:
            let text = "queued"
            return (text, dim(text))
        case .active(.preparing):
            return ("starting…", "starting…")
        case .active(.unzipping):
            return ("unzipping…", "unzipping…")
        case .active(.downloading(let received, let expected)):
            let text = progressBar(received: received, expected: expected)
            return (text, text)
        case .finished(.downloaded):
            let text = "✓ downloaded"
            return (text, green(text))
        case .finished(.alreadyDownloaded):
            let text = "✓ already downloaded"
            return (text, green(text))
        case .finished(.noDownload):
            let text = "– no digital download"
            return (text, dim(text))
        case .failed:
            let text = "✗ failed"
            return (text, red(text))
        }
    }

    static func progressBar(received: Int64, expected: Int64?) -> String {
        let mb = { (bytes: Int64) in String(format: "%.1f", Double(bytes) / 1_048_576) }
        guard let expected, expected > 0 else { return "\(mb(received)) MB" }
        let fraction = min(Double(received) / Double(expected), 1)
        let cells = 12
        let filled = Int((fraction * Double(cells)).rounded(.down))
        let bar = String(repeating: "█", count: filled) + String(repeating: "░", count: cells - filled)
        let percent = String(format: "%3d%%", Int(fraction * 100))
        return "\(percent) \(bar) \(mb(received))/\(mb(expected)) MB"
    }

    static func plain(_ status: DownloadStatus, _ name: String) -> String {
        switch status {
        case .queued: "Queued: \(name)"
        case .active: "Downloading: \(name)"
        case .finished(.downloaded(let folder)): "Downloaded: \(name) → \(folder.path)"
        case .finished(.alreadyDownloaded): "Already downloaded: \(name)"
        case .finished(.noDownload): "No digital download: \(name)"
        case .failed(let message): "Failed: \(name): \(message)"
        }
    }

    // MARK: Terminal

    static func terminalSize() -> (columns: Int, rows: Int) {
        var size = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 0 else { return (100, 40) }
        return (Int(size.ws_col), Int(size.ws_row))
    }

    private static func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    private static func restoreCursorOnInterrupt() {
        signal(SIGINT) { _ in
            let show = "\u{1B}[?25h\n"
            _ = show.withCString { Darwin.write(STDOUT_FILENO, $0, strlen($0)) }
            _exit(130)
        }
    }

    private static func bold(_ s: String) -> String { "\u{1B}[1m\(s)\u{1B}[0m" }
    private static func dim(_ s: String) -> String { "\u{1B}[2m\(s)\u{1B}[0m" }
    private static func green(_ s: String) -> String { "\u{1B}[32m\(s)\u{1B}[0m" }
    private static func red(_ s: String) -> String { "\u{1B}[31m\(s)\u{1B}[0m" }
}

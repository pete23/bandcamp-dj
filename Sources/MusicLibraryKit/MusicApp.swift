import Foundation

public enum MusicAppError: Error, CustomStringConvertible, LocalizedError {
    case notAuthorized
    case scriptFailed(String)

    public var description: String {
        switch self {
        case .notAuthorized:
            "Not allowed to control Music. Allow your terminal under System Settings → "
                + "Privacy & Security → Automation → Music, then try again."
        case .scriptFailed(let detail): "Music couldn't add the files: \(detail)"
        }
    }

    public var errorDescription: String? { description }
}

/// Adds files to the library by scripting Music.app, which launches it if needed. There is no
/// framework API for this: iTunesLibrary is read-only and MusicKit only covers the catalog.
public enum MusicApp {
    /// Adds `files` to the library, returning each one's persistent ID (16 hex digits, as in
    /// `Track`), or nil for a file Music didn't add.
    public static func add(_ files: [URL]) throws -> [String?] {
        guard !files.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/osascript")
        process.arguments = ["-e", script] + files.map(\.path)
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        // Read before waiting so a long reply can't fill the pipe and stall osascript.
        let reply = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            // -1743: the user (or nobody yet) hasn't allowed Apple events to Music.
            if detail.contains("-1743") { throw MusicAppError.notAuthorized }
            throw MusicAppError.scriptFailed(detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parse(reply, count: files.count)
    }

    /// One line per file: its persistent ID, or empty when it wasn't added.
    static func parse(_ reply: String, count: Int) -> [String?] {
        var lines = reply.split(separator: "\n", omittingEmptySubsequences: false).map {
            let id = $0.trimmingCharacters(in: .whitespaces)
            return id.isEmpty ? nil : id
        }
        lines = Array(lines.prefix(count))
        return lines + [String?](repeating: nil, count: count - lines.count)
    }

    /// Takes file paths as arguments and prints one persistent ID (or blank line) per path.
    /// Paths are turned into file references outside the `tell` block, where `POSIX file` works.
    static let script = """
        on run paths
            set ids to {}
            repeat with p in paths
                set f to POSIX file (p as text)
                set trackID to ""
                try
                    tell application "Music" to set added to add f to library playlist 1
                    if added is not missing value then
                        tell application "Music" to set trackID to persistent ID of added
                    end if
                on error message number n
                    -- Not being allowed to script Music fails every file; report it once.
                    if n is -1743 then error message number n
                end try
                set end of ids to trackID
            end repeat
            set AppleScript's text item delimiters to linefeed
            return ids as text
        end run
        """
}

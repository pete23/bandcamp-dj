import Foundation

/// Finds and stores the Bandcamp `identity` session cookie.
public struct Credentials: Sendable {
    public enum Source: Sendable, Equatable {
        case environment
        case file(URL)
    }

    public static let environmentVariable = "BANDCAMP_IDENTITY"

    public static let instructions = """
        bandcamp-sync uses your browser's Bandcamp session cookie. To find it:
          1. Open https://bandcamp.com in your browser and log in.
          2. Open the developer tools and find the site's cookies
             (Chrome: Application → Cookies; Safari/Firefox: Storage → Cookies).
          3. Copy the cookie named "identity" (just its value, or the whole row).
        """

    public static var defaultDirectory: URL {
        let home = ProcessInfo.processInfo.environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appending(path: ".config/bandcamp-sync", directoryHint: .isDirectory)
    }

    public let directory: URL
    public let environment: [String: String]

    public init(
        directory: URL = Credentials.defaultDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.directory = directory
        self.environment = environment
    }

    public var fileURL: URL { directory.appending(path: "identity") }

    /// The cookie and where it came from: the environment variable first, then the file.
    public func resolve() throws -> (identity: String, source: Source)? {
        if let value = environment[Self.environmentVariable].map(Self.normalize), !value.isEmpty {
            return (value, .environment)
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let value = Self.normalize(try String(contentsOf: fileURL, encoding: .utf8))
        return value.isEmpty ? nil : (value, .file(fileURL))
    }

    /// Writes the cookie to `fileURL`, readable only by the current user.
    @discardableResult
    public func save(_ identity: String) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard fm.createFile(
            atPath: fileURL.path, contents: Data((Self.normalize(identity) + "\n").utf8),
            attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: fileURL.path])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        return fileURL
    }

    /// Extracts the cookie value from whatever was pasted: the bare value, `identity=<value>`,
    /// a whole `Cookie` header, a tab-separated row copied from browser dev tools, or a value the
    /// dev tools showed URL-decoded (which is re-encoded).
    public static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = value.range(of: "identity=") {
            value = String(value[range.upperBound...].prefix { $0 != ";" && !$0.isNewline })
        } else if value.hasPrefix("identity\t") {
            value = String(value.split(separator: "\t").dropFirst().first ?? "")
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains(where: { $0 == "\t" || $0 == "{" || $0 == "\"" || $0 == " " }) {
            value = value.addingPercentEncoding(withAllowedCharacters: unencoded) ?? value
        }
        return value
    }

    private static let unencoded = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

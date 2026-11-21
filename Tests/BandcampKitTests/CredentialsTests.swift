import Foundation
import Testing

@testable import BandcampKit

@Suite struct CredentialsTests {
    let directory = temporaryDirectory()

    @Test func noneWhenNothingSet() throws {
        #expect(try Credentials(directory: directory, environment: [:]).resolve() == nil)
    }

    @Test func environmentWinsOverFile() throws {
        let credentials = Credentials(directory: directory, environment: ["BANDCAMP_IDENTITY": " from-env\n"])
        try credentials.save("from-file")

        let resolved = try #require(try credentials.resolve())
        #expect(resolved.identity == "from-env")
        #expect(resolved.source == .environment)
    }

    @Test func emptyEnvironmentFallsBackToFile() throws {
        let credentials = Credentials(directory: directory, environment: ["BANDCAMP_IDENTITY": ""])
        try credentials.save("from-file")

        let resolved = try #require(try credentials.resolve())
        #expect(resolved.identity == "from-file")
        #expect(resolved.source == .file(credentials.fileURL))
    }

    @Test func fileIsTrimmed() throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "  abc%09def \n\n".write(to: credentials.fileURL, atomically: true, encoding: .utf8)

        #expect(try credentials.resolve()?.identity == "abc%09def")
    }

    @Test func emptyFileIsNone() throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "\n".write(to: credentials.fileURL, atomically: true, encoding: .utf8)

        #expect(try credentials.resolve() == nil)
    }

    @Test func saveWritesPrivateFile() throws {
        let credentials = Credentials(directory: directory.appending(path: "nested"), environment: [:])

        let url = try credentials.save("identity=abc123\n")

        #expect(url == credentials.fileURL)
        #expect(try String(contentsOf: url, encoding: .utf8) == "abc123\n")
        let fm = FileManager.default
        #expect(try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
        #expect(try fm.attributesOfItem(atPath: credentials.directory.path)[.posixPermissions] as? Int == 0o700)
    }

    @Test func saveOverwrites() throws {
        let credentials = Credentials(directory: directory, environment: [:])
        try credentials.save("old")
        try credentials.save("new")

        #expect(try credentials.resolve()?.identity == "new")
        #expect(try FileManager.default.attributesOfItem(atPath: credentials.fileURL.path)[.posixPermissions] as? Int == 0o600)
    }

    @Test func defaultDirectoryIsDotConfig() {
        #expect(Credentials.defaultDirectory.path.hasSuffix("/.config/bandcamp-sync"))
    }
}

@Suite struct NormalizeTests {
    static let raw = "7%09Dizs6FSabc%2B%2F%3D%09%7B%22id%22%3A123%2C%22ex%22%3A0%7D"

    @Test(arguments: [
        raw,
        "  \(raw)\n",
        "identity=\(raw)",
        "Cookie: client_id=E8AD; identity=\(raw); js_logged_in=1",
        "identity\t\(raw)\t.bandcamp.com\t/\t21/08/2027, 21:00\t103 B",
        "7\tDizs6FSabc+/=\t{\"id\":123,\"ex\":0}",
    ])
    func extractsValue(pasted: String) {
        #expect(Credentials.normalize(pasted) == Self.raw)
    }
}

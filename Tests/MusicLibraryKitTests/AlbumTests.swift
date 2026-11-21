import Foundation
import Testing

@testable import MusicLibraryKit

private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }

private func track(
    _ title: String, artist: String? = "Artist", albumArtist: String? = nil, album: String? = "Album",
    compilation: Bool = false, year: Int? = nil, added: Date? = nil, comments: String? = nil
) -> Track {
    Track(
        persistentID: UUID().uuidString, title: title, artist: artist, albumArtist: albumArtist,
        album: album, isCompilation: compilation, year: year, addedAt: added, comments: comments)
}

@Suite struct AlbumTests {
    @Test func groupsByAlbumArtistAndTitle() {
        let albums = Album.group([
            track("1", artist: "Guest", albumArtist: "Main", album: "LP", added: day(1)),
            track("2", artist: "Main", albumArtist: "Main", album: "LP", added: day(1)),
            track("3", artist: "Main", album: "LP", added: day(1)),
            track("4", artist: "Other", album: "LP", added: day(1)),
        ])

        #expect(albums.map { "\($0.artist)/\($0.title)/\($0.trackCount)" } == ["Main/LP/3", "Other/LP/1"])
    }

    @Test func compilationsWithoutAlbumArtistAreVariousArtists() {
        let albums = Album.group([
            track("1", artist: "A", album: "Comp", compilation: true),
            track("2", artist: "B", album: "Comp", compilation: true),
        ])

        #expect(albums.count == 1)
        #expect(albums[0].artist == "Various Artists")
        #expect(albums[0].trackCount == 2)
    }

    @Test func missingNamesFallBack() {
        let albums = Album.group([track("1", artist: "  ", album: nil)])

        #expect(albums[0].artist == "Unknown Artist")
        #expect(albums[0].title == "Unknown Album")
    }

    @Test func sortsMostRecentlyAddedFirstUsingEarliestTrack() {
        let albums = Album.group([
            track("1", album: "Old", added: day(1)),
            track("2", album: "New", added: day(5)),
            track("3", album: "Old", added: day(9)),
            track("4", album: "Undated"),
            track("5", album: "Middle", added: day(3)),
        ])

        #expect(albums.map(\.title) == ["New", "Middle", "Old", "Undated"])
        #expect(albums[2].addedAt == day(1))
    }

    @Test func tiesKeepLibraryOrder() {
        let albums = Album.group(["C", "A", "B"].map { track("1", album: $0, added: day(1)) })
        #expect(albums.map(\.title) == ["C", "A", "B"])
    }

    @Test func takesFirstYearAndBandcampURL() {
        let albums = Album.group([
            track("1", year: 0, comments: "ripped from vinyl"),
            track("2", year: 2024, comments: "Visit https://label.bandcamp.com"),
            track("3", year: 2025, comments: "Visit https://other.bandcamp.com"),
        ])

        #expect(albums[0].year == 2024)
        #expect(albums[0].bandcampURL == URL(string: "https://label.bandcamp.com"))
    }

    @Test(arguments: [
        ("Visit https://bedrockrecords.bandcamp.com", "https://bedrockrecords.bandcamp.com"),
        ("Visit http://some-band.bandcamp.com/album/x\nmore", "http://some-band.bandcamp.com/album/x"),
        ("https://example.com", nil),
        ("", nil),
    ] as [(String, String?)])
    func bandcampURLFromComments(comments: String, expected: String?) {
        #expect(track("1", comments: comments).bandcampURL == expected.flatMap(URL.init(string:)))
    }

    @Test func trackRoundTripsJSON() throws {
        let original = track("1", year: 2026, added: day(3), comments: "c")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        #expect(try decoder.decode(Track.self, from: encoder.encode(original)) == original)
    }
}

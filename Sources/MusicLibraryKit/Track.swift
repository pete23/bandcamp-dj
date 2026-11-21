import Foundation

/// A song in the Music library.
public struct Track: Codable, Sendable, Equatable {
    /// Music's persistent ID as 16 hex digits (too big for a JSON number).
    public var persistentID: String
    public var title: String
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var isCompilation: Bool
    public var trackNumber: Int?
    public var discNumber: Int?
    public var year: Int?
    public var addedAt: Date?
    public var kind: String?
    public var comments: String?
    /// Nil when the track is only in iCloud.
    public var location: URL?

    public init(
        persistentID: String, title: String, artist: String? = nil, albumArtist: String? = nil,
        album: String? = nil, isCompilation: Bool = false, trackNumber: Int? = nil,
        discNumber: Int? = nil, year: Int? = nil, addedAt: Date? = nil, kind: String? = nil,
        comments: String? = nil, location: URL? = nil
    ) {
        self.persistentID = persistentID
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.isCompilation = isCompilation
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.year = year
        self.addedAt = addedAt
        self.kind = kind
        self.comments = comments
        self.location = location
    }

    /// The `https://<name>.bandcamp.com…` link Bandcamp writes into downloaded files' comments.
    public var bandcampURL: URL? {
        guard let comments,
            let match = comments.firstMatch(of: /https?:\/\/[A-Za-z0-9-]+\.bandcamp\.com[^\s]*/)
        else { return nil }
        return URL(string: String(match.output))
    }
}

/// Tracks grouped by album artist and album title.
public struct Album: Codable, Sendable, Equatable {
    public var artist: String
    public var title: String
    public var trackCount: Int
    /// When the earliest track was added.
    public var addedAt: Date?
    public var year: Int?
    public var bandcampURL: URL?

    public static let variousArtists = "Various Artists"
    public static let unknownArtist = "Unknown Artist"
    public static let unknownAlbum = "Unknown Album"

    /// Groups tracks into albums, most recently added first.
    public static func group(_ tracks: [Track]) -> [Album] {
        struct Key: Hashable { let artist: String, title: String }
        var albums: [Key: Album] = [:]
        var order: [Key] = []

        for track in tracks {
            let artist = nonEmpty(track.albumArtist)
                ?? (track.isCompilation ? variousArtists : nonEmpty(track.artist))
                ?? unknownArtist
            let title = nonEmpty(track.album) ?? unknownAlbum
            let key = Key(artist: artist, title: title)
            guard var album = albums[key] else {
                order.append(key)
                albums[key] = Album(
                    artist: artist, title: title, trackCount: 1, addedAt: track.addedAt,
                    year: track.year.flatMap { $0 > 0 ? $0 : nil }, bandcampURL: track.bandcampURL)
                continue
            }
            album.trackCount += 1
            if let added = track.addedAt, album.addedAt.map({ added < $0 }) ?? true { album.addedAt = added }
            if album.year == nil, let year = track.year, year > 0 { album.year = year }
            if album.bandcampURL == nil { album.bandcampURL = track.bandcampURL }
            albums[key] = album
        }

        // Stable sort keeps library order for albums added at the same moment.
        return order.map { albums[$0]! }.enumerated().sorted { lhs, rhs in
            let l = lhs.element.addedAt ?? .distantPast, r = rhs.element.addedAt ?? .distantPast
            return l != r ? l > r : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

private func nonEmpty(_ string: String?) -> String? {
    guard let trimmed = string?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
    return trimmed
}

import Foundation
import iTunesLibrary

public enum MusicLibraryError: Error, CustomStringConvertible, LocalizedError {
    case unavailable(String)

    public var description: String {
        switch self {
        case .unavailable(let detail):
            "Couldn't read the Music library: \(detail)\n"
                + "If access was denied, allow your terminal under System Settings → "
                + "Privacy & Security → Media & Apple Music."
        }
    }

    public var errorDescription: String? { description }
}

/// Reads the Music library through Apple's iTunesLibrary framework (read-only, no Music.app needed).
public enum MusicLibrary {
    /// All songs in the library, in library order.
    public static func tracks() throws -> [Track] {
        let library: ITLibrary
        do {
            library = try ITLibrary(apiVersion: "1.1")
        } catch {
            throw MusicLibraryError.unavailable(error.localizedDescription)
        }
        return library.allMediaItems
            .filter { $0.mediaKind == .kindSong }
            .map(Track.init)
    }
}

extension Track {
    init(_ item: ITLibMediaItem) {
        self.init(
            persistentID: String(format: "%016llX", item.persistentID.uint64Value),
            title: item.title,
            artist: item.artist?.name,
            albumArtist: item.album.albumArtist,
            album: item.album.title,
            isCompilation: item.album.isCompilation,
            trackNumber: item.trackNumber > 0 ? item.trackNumber : nil,
            discNumber: item.album.discNumber > 0 ? item.album.discNumber : nil,
            year: item.year > 0 ? item.year : nil,
            addedAt: item.addedDate,
            kind: item.kind,
            comments: item.comments,
            location: item.location)
    }
}

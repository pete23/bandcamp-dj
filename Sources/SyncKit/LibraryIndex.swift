import BandcampKit
import Foundation
import MusicLibraryKit

/// What a purchase matched in the library, and why we believe it.
public struct LibraryMatch: Codable, Sendable, Equatable {
    public enum Reason: String, Codable, Sendable {
        /// Title and artist agree.
        case artist
        /// Title agrees and the track comments link to the purchase's Bandcamp site.
        case bandcampSite
    }

    public enum Kind: String, Codable, Sendable { case album, track }

    public var kind: Kind
    public var artist: String
    public var title: String
    public var reason: Reason
}

public struct PurchaseStatus: Codable, Sendable, Equatable {
    public var purchase: Purchase
    /// Nil when the purchase isn't in the library.
    public var match: LibraryMatch?

    public var isMissing: Bool { match == nil }
}

/// Looks up Bandcamp purchases in a set of library tracks.
public struct LibraryIndex: Sendable {
    struct Candidate: Sendable {
        let kind: LibraryMatch.Kind
        let artist: String
        let title: String
        var artists: Set<String>
        var hosts: Set<String>
    }

    private var albums: [String: [Candidate]] = [:]
    private var tracks: [String: [Candidate]] = [:]

    public init(tracks libraryTracks: [Track]) {
        var albumCandidates: [String: Candidate] = [:]
        for track in libraryTracks {
            let artists = Set([track.artist, track.albumArtist].compactMap { $0.map(Self.normalize) })
                .subtracting([""])
            let hosts = Set([track.bandcampURL?.host()?.lowercased()].compactMap { $0 })

            let trackCandidate = Candidate(
                kind: .track, artist: track.artist ?? track.albumArtist ?? "", title: track.title,
                artists: artists, hosts: hosts)
            for key in Self.titleKeys(track.title) { tracks[key, default: []].append(trackCandidate) }

            guard let album = track.album, !Self.normalize(album).isEmpty else { continue }
            let albumArtist = track.albumArtist ?? (track.isCompilation ? Album.variousArtists : track.artist) ?? ""
            let id = Self.normalize(albumArtist) + "\u{0}" + Self.normalize(album)
            if var existing = albumCandidates[id] {
                existing.artists.formUnion(artists)
                existing.hosts.formUnion(hosts)
                albumCandidates[id] = existing
            } else {
                albumCandidates[id] = Candidate(
                    kind: .album, artist: albumArtist, title: album,
                    artists: artists.union([Self.normalize(albumArtist)]).subtracting([""]), hosts: hosts)
            }
        }
        for candidate in albumCandidates.values {
            for key in Self.titleKeys(candidate.title) { albums[key, default: []].append(candidate) }
        }
    }

    public func status(of purchase: Purchase) -> PurchaseStatus {
        PurchaseStatus(purchase: purchase, match: match(purchase))
    }

    public func match(_ purchase: Purchase) -> LibraryMatch? {
        // A single may be filed as a track of some album, or as its own one-track album.
        let pools = purchase.itemType == .track ? [tracks, albums] : [albums]
        let artist = Self.normalize(purchase.artist)
        let host = purchase.itemURL?.host()?.lowercased()

        for key in Self.titleKeys(purchase.title) {
            for pool in pools {
                let candidates = pool[key] ?? []
                if let hit = candidates.first(where: { Self.artistAgrees(artist, $0.artists) }) {
                    return LibraryMatch(kind: hit.kind, artist: hit.artist, title: hit.title, reason: .artist)
                }
                if let host, let hit = candidates.first(where: { $0.hosts.contains(host) }) {
                    return LibraryMatch(kind: hit.kind, artist: hit.artist, title: hit.title, reason: .bandcampSite)
                }
            }
        }
        return nil
    }

    static func artistAgrees(_ artist: String, _ candidates: Set<String>) -> Bool {
        guard !artist.isEmpty else { return false }
        if candidates.contains(artist) { return true }
        // "A & B" vs "A": one name contains the other on word boundaries.
        let padded = " \(artist) "
        return candidates.contains { " \($0) ".contains(padded) || padded.contains(" \($0) ") }
    }

    /// Exact key first, then a looser one without bracketed parts or an EP/LP suffix.
    static func titleKeys(_ title: String) -> [String] {
        let exact = normalize(title)
        var withoutBrackets = ""
        var closing: Character?
        for character in title {
            if let close = closing {
                if character == close { closing = nil }
            } else if character == "(" || character == "[" {
                closing = character == "(" ? ")" : "]"
                withoutBrackets.append(" ")
            } else {
                withoutBrackets.append(character)
            }
        }
        var loose = normalize(withoutBrackets)
        for suffix in [" ep", " lp", " single"] where loose.hasSuffix(suffix) && loose.count > suffix.count {
            loose.removeLast(suffix.count)
        }
        return [exact, loose].filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Lowercase, ASCII-fied (`é`→`e`, `æ`→`ae`), `&` as "and", punctuation as spaces, single-spaced.
    static func normalize(_ string: String) -> String {
        var ascii = string
        if !string.utf8.allSatisfy({ $0 < 0x80 }) {
            ascii = (string.applyingTransform(StringTransform("Latin-ASCII"), reverse: false) ?? string)
                .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
        }
        var result = ""
        var pendingSpace = false
        for scalar in ascii.lowercased().replacingOccurrences(of: "&", with: " and ").unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace && !result.isEmpty { result.append(" ") }
                result.unicodeScalars.append(scalar)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return result
    }
}

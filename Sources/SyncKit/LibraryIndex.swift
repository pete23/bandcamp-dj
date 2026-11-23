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

/// Looks up Bandcamp purchases in a set of library tracks.
public struct LibraryIndex: Sendable {
    struct Candidate: Sendable {
        let kind: LibraryMatch.Kind
        let artist: String
        let title: String
        var artists: Set<String>
        var hosts: Set<String>
    }

    /// Candidates under each title key, with how loose a key of theirs it is (0 = exact).
    private var albums: [String: [(rank: Int, candidate: Candidate)]] = [:]
    private var tracks: [String: [(rank: Int, candidate: Candidate)]] = [:]

    public init(tracks libraryTracks: [Track]) {
        var albumCandidates: [Candidate] = []
        var albumIndex: [String: Int] = [:]
        for track in libraryTracks {
            let artists = Set([track.artist, track.albumArtist].compactMap { $0 }.flatMap(Self.artistForms))
            let hosts = Set([track.bandcampURL?.host()?.lowercased()].compactMap { $0 })

            let trackCandidate = Candidate(
                kind: .track, artist: track.artist ?? track.albumArtist ?? "", title: track.title,
                artists: artists, hosts: hosts)
            for (rank, key) in Self.titleKeys(track.title, artists: artists).enumerated() {
                tracks[key, default: []].append((rank, trackCandidate))
            }

            guard let album = track.album, !Self.normalize(album).isEmpty else { continue }
            let albumArtist = track.albumArtist ?? (track.isCompilation ? Album.variousArtists : track.artist) ?? ""
            let id = Self.normalize(albumArtist) + "\u{0}" + Self.normalize(album)
            if let existing = albumIndex[id] {
                albumCandidates[existing].artists.formUnion(artists)
                albumCandidates[existing].hosts.formUnion(hosts)
            } else {
                albumIndex[id] = albumCandidates.count
                albumCandidates.append(Candidate(
                    kind: .album, artist: albumArtist, title: album,
                    artists: artists.union(Self.artistForms(albumArtist)), hosts: hosts))
            }
        }
        for candidate in albumCandidates {
            for (rank, key) in Self.titleKeys(candidate.title, artists: Self.artistForms(candidate.artist)).enumerated() {
                albums[key, default: []].append((rank, candidate))
            }
        }
    }

    public func match(_ purchase: Purchase) -> LibraryMatch? {
        // A single may be filed as a track of some album, or as its own one-track album.
        let pools = purchase.itemType == .track ? [tracks, albums] : [albums]
        let artist = Self.artistForms(purchase.artist)
        let host = purchase.itemURL?.host()?.lowercased()

        for key in Self.titleKeys(purchase.title, artists: artist) {
            for pool in pools {
                // Prefer candidates for which this is an exact key, then library order.
                let candidates = (pool[key] ?? []).enumerated()
                    .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
                    .map(\.element.candidate)
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

    static func artistAgrees(_ artist: Set<String>, _ candidates: Set<String>) -> Bool {
        artist.contains { name in
            if candidates.contains(name) { return true }
            // "A & B" vs "A": one name contains the other on word boundaries.
            let padded = " \(name) "
            return candidates.contains { " \($0) ".contains(padded) || padded.contains(" \($0) ") }
        }
    }

    /// A name normalized, and without any bracketed part ("Multiples (Surgeon x Speedy J)" → "multiples").
    static func artistForms(_ name: String) -> Set<String> {
        Set([normalize(name), normalize(withoutBrackets(name))]).subtracting([""])
    }

    /// Lookup keys for a title, most exact first:
    /// 1. the normalized title;
    /// 2. without bracketed parts or an EP/LP/single suffix;
    /// 3. each of those without a leading catalog number ("IT045 - …", "AM004: …") or the
    ///    artist's name ("Thomas Ragsdale Live in Margate"), if at least 3 characters remain.
    static func titleKeys(_ title: String, artists: Set<String> = []) -> [String] {
        let exact = normalize(title)
        var loose = normalize(withoutBrackets(title))
        for suffix in [" ep", " lp", " single"] where loose.hasSuffix(suffix) && loose.count > suffix.count {
            loose.removeLast(suffix.count)
        }
        var keys = [exact, loose]
        for key in [exact, loose] {
            var stripped = key
            for _ in 0..<2 {
                stripped = withoutCatalogNumber(stripped)
                if let name = artists.first(where: { stripped.hasPrefix($0 + " ") }) {
                    stripped.removeFirst(name.count + 1)
                }
            }
            if stripped.count >= 3 { keys.append(stripped) }
        }
        return keys.filter { !$0.isEmpty }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Drops a leading token like `it045` or `ihndigs024` (letters then digits) from a normalized title.
    static func withoutCatalogNumber(_ key: String) -> String {
        guard let space = key.firstIndex(of: " ") else { return key }
        let token = key[..<space]
        let letters = token.prefix { $0.isLetter }
        let rest = token.dropFirst(letters.count)
        let digits = rest.prefix { $0.isNumber }
        let tail = rest.dropFirst(digits.count)
        guard (1...10).contains(letters.count), (1...4).contains(digits.count), tail.count <= 1,
            tail.allSatisfy(\.isLetter)
        else { return key }
        return String(key[key.index(after: space)...])
    }

    static func withoutBrackets(_ text: String) -> String {
        var result = ""
        var closing: Character?
        for character in text {
            if let close = closing {
                if character == close { closing = nil }
            } else if character == "(" || character == "[" {
                closing = character == "(" ? ")" : "]"
                result.append(" ")
            } else {
                result.append(character)
            }
        }
        return result
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

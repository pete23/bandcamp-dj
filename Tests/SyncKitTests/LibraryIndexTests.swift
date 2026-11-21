import BandcampKit
import Foundation
import MusicLibraryKit
import Testing

@testable import SyncKit

private func purchase(
    _ artist: String, _ title: String, type: Purchase.ItemType = .album, site: String = "somewhere"
) -> Purchase {
    Purchase(
        saleItemID: 1, itemType: type, artist: artist, title: title, purchasedAt: Date(),
        itemURL: URL(string: "https://\(site).bandcamp.com/album/x"), redownloadURL: nil)
}

private func track(
    _ title: String, artist: String?, albumArtist: String? = nil, album: String?,
    compilation: Bool = false, site: String? = nil
) -> Track {
    Track(
        persistentID: "0", title: title, artist: artist, albumArtist: albumArtist, album: album,
        isCompilation: compilation, comments: site.map { "Visit https://\($0).bandcamp.com" })
}

@Suite struct LibraryIndexTests {
    let index = LibraryIndex(tracks: [
        track("Intro", artist: "Donato Dozzy", album: "Astro"),
        track("Song", artist: "Guest", albumArtist: "Main Act", album: "Shared Title"),
        track("A", artist: "Someone", album: "Comp", compilation: true),
        track("B", artist: "Eraserhead", album: "The Ferryman EP", site: "eraserheadmusic"),
        track("C", artist: "Siavash Amini & Eugene Thacker", album: "Songs for Sad Poets Vol. III"),
        track("D", artist: "Sigur Rós", album: "Ágætis byrjun"),
        track("E", artist: "Boards of Canada", album: "Inferno (Deluxe Edition) - EP"),
        track("BLAU (Live Apartamento Mix)", artist: "ASKALOTL", album: "Live Sets"),
        track("Lonely Single", artist: "Solo", album: "Lonely Single"),
    ])

    @Test func matchesAlbumByTitleAndArtist() {
        #expect(index.match(purchase("Donato Dozzy", "Astro"))
            == LibraryMatch(kind: .album, artist: "Donato Dozzy", title: "Astro", reason: .artist))
    }

    @Test func missingWhenNoTitleMatches() {
        #expect(index.match(purchase("Donato Dozzy", "Something Else")) == nil)
    }

    @Test func titleAloneIsNotEnough() {
        #expect(index.match(purchase("Different Artist", "Astro")) == nil)
    }

    @Test func artistCanBeAnyTrackArtistOrAlbumArtist() {
        #expect(index.match(purchase("Main Act", "Shared Title"))?.artist == "Main Act")
        #expect(index.match(purchase("Guest", "Shared Title"))?.artist == "Main Act")
    }

    @Test func compilationsMatchVariousArtists() {
        #expect(index.match(purchase("Various Artists", "Comp"))?.artist == "Various Artists")
    }

    @Test func bandcampSiteVouchesForDifferentArtist() {
        let match = index.match(purchase("Neighbourhood Witch", "The Ferryman EP", site: "eraserheadmusic"))
        #expect(match?.reason == .bandcampSite)
        #expect(match?.artist == "Eraserhead")
        #expect(index.match(purchase("Neighbourhood Witch", "The Ferryman EP", site: "elsewhere")) == nil)
    }

    @Test func artistContainedInCollaboration() {
        #expect(index.match(purchase("Siavash Amini", "Songs for Sad Poets Vol. III")) != nil)
        #expect(index.match(purchase("Amin", "Songs for Sad Poets Vol. III")) == nil)
    }

    @Test func ignoresCaseAccentsAndPunctuation() {
        #expect(index.match(purchase("sigur ros", "AGAETIS BYRJUN!")) != nil)
        #expect(index.match(purchase("DONATO-DOZZY", "astro.")) != nil)
    }

    @Test func looseMatchDropsBracketsAndEPSuffix() {
        #expect(index.match(purchase("Boards of Canada", "Inferno", type: .package)) != nil)
    }

    @Test func trackPurchasesMatchTracks() {
        let match = index.match(purchase("ASKALOTL", "BLAU (Live Apartamento Mix)", type: .track))
        #expect(match == LibraryMatch(
            kind: .track, artist: "ASKALOTL", title: "BLAU (Live Apartamento Mix)", reason: .artist))
    }

    @Test func albumPurchasesDontMatchTracks() {
        #expect(index.match(purchase("ASKALOTL", "BLAU (Live Apartamento Mix)")) == nil)
    }

    @Test func statusReportsMissing() {
        let status = index.status(of: purchase("Nobody", "Nothing"))
        #expect(status.isMissing)
        #expect(!index.status(of: purchase("Donato Dozzy", "Astro")).isMissing)
    }

    @Test(arguments: [
        ("Ágætis byrjun", "agaetis byrjun"),
        ("ugne&maria", "ugne and maria"),
        ("IHN018 // Start Here - Vol. 1", "ihn018 start here vol 1"),
        ("  Lots   of\tspace ", "lots of space"),
        ("one(15)", "one 15"),
    ])
    func normalizes(input: String, expected: String) {
        #expect(LibraryIndex.normalize(input) == expected)
    }

    @Test func titleKeys() {
        #expect(LibraryIndex.titleKeys("Astro") == ["astro"])
        #expect(LibraryIndex.titleKeys("Inferno (Deluxe) - EP") == ["inferno deluxe ep", "inferno"])
        #expect(LibraryIndex.titleKeys("EP") == ["ep"])
    }
}

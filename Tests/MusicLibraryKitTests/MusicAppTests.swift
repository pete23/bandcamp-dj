import Testing

@testable import MusicLibraryKit

@Suite struct MusicAppTests {
    @Test func parsesOneIDPerFileWithBlanksForFilesNotAdded() {
        #expect(MusicApp.parse("0123456789ABCDEF\n\nFEDCBA9876543210\n", count: 3)
            == ["0123456789ABCDEF", nil, "FEDCBA9876543210"])
    }

    @Test func padsAShortReply() {
        #expect(MusicApp.parse("0123456789ABCDEF", count: 2) == ["0123456789ABCDEF", nil])
    }

    @Test func addingNothingDoesNotRunMusic() throws {
        #expect(try MusicApp.add([]).isEmpty)
    }
}

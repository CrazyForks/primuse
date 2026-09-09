import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

final class DuplicateDetectorTests: XCTestCase {
    private func song(
        _ id: String,
        title: String,
        artist: String? = nil,
        albumArtist: String? = nil,
        album: String? = nil,
        duration: TimeInterval = 0,
        format: AudioFormat = .mp3,
        size: Int64 = 0,
        path: String? = nil
    ) -> Song {
        Song(
            id: id,
            title: title,
            albumTitle: album,
            artistName: artist,
            albumArtistName: albumArtist,
            duration: duration,
            fileFormat: format,
            filePath: path ?? "/\(id).\(format.rawValue)",
            sourceID: "webdav",
            fileSize: size
        )
    }

    func testUntaggedSongsWithTheSameFilenameTitleAreNotDuplicates() {
        // Fresh WebDAV rows: title inferred from the filename, no artist,
        // no album and no duration yet. Different files must stay apart.
        let songs = [
            song("a", title: "01. Intro", size: 588 * 1024, path: "/50 Cent/01. Intro.flac"),
            song("b", title: "01. Intro", size: 2_500 * 1024, path: "/James Bay/01. Intro.mp3"),
            song("c", title: "01. Intro", size: 1_200 * 1024, path: "/BMTH/01. Intro.mp3"),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: songs).isEmpty)
    }

    func testUntaggedSongsWithTheSameSizeAreNotDuplicates() {
        let songs = [
            song("a", title: "01. Intro", size: 4_200_000, path: "/Artist A/01. Intro.mp3"),
            song("b", title: "01. Intro", size: 4_200_000, path: "/Artist B/01. Intro.mp3"),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: songs).isEmpty)
    }

    func testSongsWithoutAnyComparableEvidenceNeverMerge() {
        let songs = [
            song("a", title: "01. Intro"),
            song("b", title: "01. Intro"),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: songs).isEmpty)
    }

    func testUntaggedSongsWithMatchingDurationAreNotDuplicates() {
        let songs = [
            song("a", title: "01. Intro", duration: 62.2),
            song("b", title: "01. Intro", duration: 62.9),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: songs).isEmpty)

        let differentSizes = [
            song("a", title: "01. Intro", duration: 62.2, size: 1_000),
            song("b", title: "01. Intro", duration: 62.9, size: 2_000),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: differentSizes).isEmpty)
    }

    func testTaggedVersionsInDifferentFormatsRemainDuplicates() {
        let songs = [
            song("flac", title: "Tired of Being Alone", artist: "Al Green", duration: 176.4, format: .flac, size: 30_000_000),
            song("mp3", title: "Tired of Being Alone", artist: "al green", duration: 177.1, format: .mp3, size: 7_000_000),
        ]
        let groups = DuplicateDetector.detect(in: songs)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.bestSong.id, "flac")
        XCTAssertEqual(groups.first?.redundantSongs.map(\.id), ["mp3"])
    }

    func testMissingTrackArtistUsesAlbumArtistButNotAlbumTitleAlone() {
        let sameAlbumArtist = [
            song("a", title: "Intro", albumArtist: "Artist", duration: 60, size: 1),
            song("b", title: "Intro", albumArtist: "artist", duration: 61, size: 2),
        ]
        XCTAssertEqual(DuplicateDetector.detect(in: sameAlbumArtist).count, 1)

        let differentAlbums = [
            song("a", title: "Intro", album: "Get Rich Or Die Tryin'", duration: 60, size: 1),
            song("b", title: "Intro", album: "Electric Light", duration: 60, size: 2),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: differentAlbums).isEmpty)

        let sameAlbumName = [
            song("a", title: "Intro", album: "Greatest Hits", duration: 60, size: 1),
            song("b", title: "Intro", album: "Greatest Hits", duration: 61, size: 2),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: sameAlbumName).isEmpty)
    }

    func testMatchingArtistAndSizeDoNotReplaceMissingOrInvalidDuration() {
        for duration in [0, -1, TimeInterval.nan, TimeInterval.infinity] {
            let songs = [
                song("a", title: "Intro", artist: "Artist", duration: duration, size: 4_200_000),
                song("b", title: "Intro", artist: "Artist", duration: duration, size: 4_200_000),
            ]
            XCTAssertTrue(DuplicateDetector.detect(in: songs).isEmpty, "duration: \(duration)")
        }
    }

    func testKnownDurationStillSeparatesDifferentRecordingsOfTheSameTitle() {
        let songs = [
            song("a", title: "Intro", artist: "Artist", duration: 30, size: 1),
            song("b", title: "Intro", artist: "Artist", duration: 95, size: 2),
        ]
        XCTAssertTrue(DuplicateDetector.detect(in: songs).isEmpty)
    }
}

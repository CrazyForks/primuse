import Foundation
import PrimuseKit
import XCTest
import UIKit
@testable import Primuse

@MainActor
final class LibraryReviewTests: XCTestCase {
    func testReviewNormalizationPersistenceAndDeletionTombstone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseReviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let subject = LibraryReviewSubject.album("album-1")
        let library = MusicLibrary(storageDirectory: directory)
        library.updateLibraryReview(
            for: subject,
            rating: 8,
            comment: "  值得反复听  ",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertNil(library.libraryReview(for: subject)?.rating)
        XCTAssertEqual(library.libraryReview(for: subject)?.comment, "值得反复听")
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("Review snapshot should persist")
        }

        let restored = MusicLibrary(storageDirectory: directory)
        XCTAssertEqual(restored.libraryReview(for: subject)?.comment, "值得反复听")
        restored.updateLibraryReview(
            for: subject,
            rating: nil,
            comment: "",
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        XCTAssertNil(restored.libraryReview(for: subject))
        XCTAssertEqual(restored.allLibraryReviews.count, 1)
        XCTAssertTrue(restored.allLibraryReviews[0].isDeleted)
    }

    func testNewerReviewWinsSnapshotReconciliationIncludingDeletion() {
        let subject = LibraryReviewSubject.song("song-1")
        let active = LibraryReview(
            subject: subject,
            rating: 5,
            comment: "旧评论",
            updatedAt: Date(timeIntervalSince1970: 100),
            deletedAt: nil
        )
        let deleted = LibraryReview(
            subject: subject,
            rating: nil,
            comment: "",
            updatedAt: Date(timeIntervalSince1970: 200),
            deletedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(
            LibraryReviewReconciliationPolicy.winner(local: active, remote: deleted),
            deleted
        )
        XCTAssertEqual(
            LibraryReviewReconciliationPolicy.winner(local: deleted, remote: active),
            deleted
        )
    }
}

@MainActor
final class MusicLibraryLikedMutationTests: XCTestCase {
    func testBatchLikedMembershipEmitsOnlyActualChangesAndRollbackDoesNotReenter() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseLikedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )

        try await exerciseLikedMutations(storageDirectory: storageDirectory)
        try FileManager.default.removeItem(at: storageDirectory)
    }

    private func exerciseLikedMutations(storageDirectory: URL) async throws {
        let library = MusicLibrary(storageDirectory: storageDirectory)
        let songs = [
            makeSong(id: "song-1", path: "/songs/remote-1.mp3"),
            makeSong(id: "song-2", path: "/songs/remote-2.mp3"),
        ]
        library.addSongs(songs, affectedSourceIDs: ["source-1"])
        library.ensurePlaylist(id: MusicLibrary.likedSongsPlaylistID, name: "Liked")
        let regular = library.createPlaylist(name: "Regular")

        var mutations: [(songID: String, previous: Bool, desired: Bool)] = []
        library.likedStateMutationHandler = { song, previous, desired in
            mutations.append((song.id, previous, desired))
        }

        library.add(songIDs: ["song-1", "song-2", "song-1"], toPlaylist: MusicLibrary.likedSongsPlaylistID)
        XCTAssertEqual(mutations.map(\.songID), ["song-1", "song-2"])
        XCTAssertEqual(mutations.map(\.desired), [true, true])

        library.add(songIDs: ["song-1", "song-2"], toPlaylist: MusicLibrary.likedSongsPlaylistID)
        XCTAssertEqual(mutations.count, 2, "Repeated membership must be idempotent")

        library.remove(songIDs: ["song-1", "song-1"], fromPlaylist: MusicLibrary.likedSongsPlaylistID)
        XCTAssertEqual(mutations.map(\.songID), ["song-1", "song-2", "song-1"])
        XCTAssertEqual(mutations.last?.previous, true)
        XCTAssertEqual(mutations.last?.desired, false)

        library.add(songIDs: ["song-1", "song-2"], toPlaylist: regular.id)
        library.remove(songIDs: ["song-1"], fromPlaylist: regular.id)
        XCTAssertEqual(mutations.count, 3, "Ordinary playlists must not trigger server favorites")

        library.setLiked(
            songID: "song-2",
            isLiked: false,
            propagatesServerMutation: false
        )
        XCTAssertEqual(mutations.count, 3, "Recovery changes must not recursively write to the server")

        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }
    }

    private func makeSong(id: String, path: String) -> Song {
        Song(
            id: id,
            title: id,
            fileFormat: .mp3,
            filePath: path,
            sourceID: "source-1"
        )
    }
}

@MainActor
final class MusicLibraryMetadataReplacementTests: XCTestCase {
    func testSourceListsKeepUnrelatedCachesAndTrackAssetsMigrationAndVisibility() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseSourceSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        let first = makeSong(id: "first", path: "/first.mp3")
        var second = makeSong(id: "second", path: "/second.mp3")
        second.sourceID = "source-2"
        library.addSongs([first, second], affectedSourceIDs: [first.sourceID, second.sourceID])
        for _ in 0..<200 where library.visibleSongs.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.visibleSongs.count, 2)
        let firstState = library.sourceSongListState(for: first.sourceID)
        let secondState = library.sourceSongListState(for: second.sourceID)
        let firstVersion = firstState.version
        let secondVersion = secondState.version
        let store = SongListSnapshotStore()
        let cached = await store.snapshot(scopeKey: first.sourceID, version: firstVersion, order: .duration, songs: firstState.songs)

        second.bitRate = 320
        await library.replaceSongsPreparedOffMain([second], maintenance: .deferred)
        XCTAssertEqual(firstState.version, firstVersion)
        XCTAssertNotEqual(secondState.version, secondVersion)
        XCTAssertEqual(secondState.replacedSongIDs, [second.id])
        let reused = await store.snapshot(scopeKey: first.sourceID, version: firstState.version, order: .duration, songs: firstState.songs)
        XCTAssertTrue(try XCTUnwrap(cached) === XCTUnwrap(reused))

        let secondMetadataVersion = secondState.version
        library.updateAssetReferences(songID: first.id, coverRef: "first-cover.jpg", lyricsRef: "first.lrc")
        library.updateMusicVideoReference(songID: first.id, mvPath: "/first.mp4")
        library.updateLyricsText([first.id: "Updated lyrics"])
        XCTAssertNotEqual(firstState.version, firstVersion)
        XCTAssertEqual(secondState.version, secondMetadataVersion)
        let refreshed = try XCTUnwrap(firstState.songs.first)
        XCTAssertEqual(refreshed.coverArtFileName, "first-cover.jpg")
        XCTAssertEqual(refreshed.lyricsFileName, "first.lrc")
        XCTAssertEqual(refreshed.mvPath, "/first.mp4")
        XCTAssertEqual(refreshed.lyricsText, "Updated lyrics")

        var moved = refreshed
        moved.sourceID = second.sourceID
        await library.replaceSongsPreparedOffMain([moved], maintenance: .deferred)
        XCTAssertTrue(firstState.songs.isEmpty)
        XCTAssertEqual(Set(secondState.songs.map(\.id)), [first.id, second.id])
        library.updateDisabledSourceIDs([second.sourceID])
        XCTAssertTrue(secondState.songs.isEmpty)
        library.updateDisabledSourceIDs([])
        XCTAssertTrue(secondState === library.sourceSongListState(for: second.sourceID))
        XCTAssertEqual(secondState.songs.count, 2)
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("Source snapshot fixture did not finish persistence")
        }
    }

    func testDeferredMaintenancePreservesMetadataUntilEnvironmentAllowsRebuild() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseDeferredMaintenance-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var allowsMaintenance = false
        let library = MusicLibrary(
            storageDirectory: directory,
            deferredMaintenanceAllowed: { allowsMaintenance }
        )
        var song = makeSong(id: "deferred", path: "/music/deferred.mp3")
        song.albumTitle = "Original"
        library.addSongs([song], affectedSourceIDs: [song.sourceID])
        await library.waitForPendingIndex()
        let revision = library.spotlightIndexRevision

        for album in ["Intermediate", "Latest"] {
            song.albumTitle = album
            song.duration = 193
            await library.replaceSongsPreparedOffMain([song], maintenance: .deferred)
            library.flushDeferredLibraryMaintenance()
        }
        XCTAssertEqual(library.song(id: song.id)?.albumTitle, "Latest")
        XCTAssertEqual(library.unobservedVisibleSong(id: song.id)?.duration, 193)
        XCTAssertEqual(library.albums.map(\.title), ["Original"])
        XCTAssertEqual(library.spotlightIndexRevision, revision)
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("Deferred grouping must not defer song persistence")
        }
        let restored = MusicLibrary(storageDirectory: directory)
        XCTAssertEqual(restored.song(id: song.id)?.albumTitle, "Latest")

        allowsMaintenance = true
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        for _ in 0..<100 where library.spotlightIndexRevision == revision {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.spotlightIndexRevision, revision + 1)
        await library.waitForPendingIndex()
        XCTAssertEqual(library.albums.map(\.title), ["Latest"])
        XCTAssertEqual(library.spotlightIndexRevision, revision + 1)
        library.flushDeferredLibraryMaintenance()
        XCTAssertEqual(library.spotlightIndexRevision, revision + 1)
    }

    func testExplicitIndexBarrierCompletesWhileAutomaticMaintenanceIsDeferred() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseMaintenanceBarrier-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory, deferredMaintenanceAllowed: { false })
        var song = makeSong(id: "barrier", path: "/music/barrier.mp3")
        song.albumTitle = "Before"
        library.addSongs([song], affectedSourceIDs: [song.sourceID])
        await library.waitForPendingIndex()
        song.albumTitle = "After"
        await library.replaceSongsPreparedOffMain([song], maintenance: .deferred)
        await library.waitForPendingIndex()
        XCTAssertEqual(library.albums.map(\.title), ["After"])
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("The index barrier must preserve song persistence")
        }
    }

    func testPreparedMetadataReplacementPatchesStableLibraryCaches() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseMetadataReplacementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let first = makeSong(id: "song-1", path: "/music/one.mp3")
        let second = makeSong(id: "song-2", path: "/music/two.mp3")
        library.addSongs([first, second], affectedSourceIDs: ["source-1"])

        for _ in 0..<200 where library.visibleSongs.count != 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(library.visibleSongs.map(\.id), ["song-1", "song-2"])

        let collectionRevision = library.visibleSongCollectionRevision
        let replacementToken = library.songReplacementToken
        let invalidationRevision = library.songListSnapshotInvalidationRevision
        var updated = first
        updated.duration = 193
        updated.bitRate = 320

        await library.replaceSongsPreparedOffMain([updated], maintenance: .deferred)

        XCTAssertEqual(library.song(id: first.id)?.duration, 193)
        XCTAssertEqual(library.unobservedVisibleSong(id: first.id)?.bitRate, 320)
        XCTAssertEqual(
            library.visibleSongs(forSourceID: first.sourceID).first(where: { $0.id == first.id })?.duration,
            193
        )
        XCTAssertEqual(library.visibleSongCollectionRevision, collectionRevision)
        XCTAssertNotEqual(library.songReplacementToken, replacementToken)
        XCTAssertEqual(library.lastReplacedSongIDs, [first.id])
        XCTAssertEqual(library.songListSnapshotInvalidationRevision, invalidationRevision)
        XCTAssertEqual(library.songs.map(\.id), ["song-1", "song-2"])

        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }
    }

    func testPreparedReplacementMarksPlayabilitySnapshotChange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimusePlayabilityReplacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        var song = makeSong(id: "playable", path: "")
        library.addSongs([song], affectedSourceIDs: [song.sourceID])

        let invalidationRevision = library.songListSnapshotInvalidationRevision
        song.duration = 193
        await library.replaceSongsPreparedOffMain([song], maintenance: .deferred)

        XCTAssertTrue(library.unobservedVisibleSong(id: song.id)?.isPlayable == true)
        XCTAssertEqual(
            library.songListSnapshotInvalidationRevision,
            invalidationRevision + 1
        )
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("The playability replacement did not finish persistence")
        }
    }

    func testSourceReplacementMarksMembershipSnapshotChange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseSourceReplacement-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        var song = makeSong(id: "moved", path: "/music/moved.mp3")
        library.addSongs([song], affectedSourceIDs: [song.sourceID])

        let invalidationRevision = library.songListSnapshotInvalidationRevision
        song.sourceID = "source-2"
        library.replaceSong(song)

        XCTAssertEqual(library.unobservedVisibleSong(id: song.id)?.sourceID, "source-2")
        XCTAssertEqual(
            library.songListSnapshotInvalidationRevision,
            invalidationRevision + 1
        )
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("The source replacement did not finish persistence")
        }
    }

    func testStructuralInvalidationSurvivesFollowingMetadataReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseReplacementInvalidation-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        var song = makeSong(id: "sequence", path: "/music/sequence.mp3")
        library.addSongs([song], affectedSourceIDs: [song.sourceID])
        let initialRevision = library.songListSnapshotInvalidationRevision

        song.sourceID = "source-2"
        library.replaceSong(song)
        var metadataOnly = song
        metadataOnly.albumTitle = "Updated"
        library.replaceSong(metadataOnly)

        XCTAssertEqual(
            library.songListSnapshotInvalidationRevision,
            initialRevision + 1,
            "A later metadata replacement must not erase structural invalidation"
        )
        XCTAssertEqual(library.song(id: song.id)?.albumTitle, "Updated")
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("The sequential replacements did not finish persistence")
        }
    }

    private func makeSong(id: String, path: String) -> Song {
        Song(
            id: id,
            title: id,
            fileFormat: .mp3,
            filePath: path,
            sourceID: "source-1"
        )
    }
}

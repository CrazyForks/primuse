import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

@MainActor
final class HomePresentationCacheTests: XCTestCase {
    private func signature(
        library: Int = 1, history: Int = 1, pins: String = "",
        recommendations: Bool = true
    ) -> HomeView.HomeSnapshotSignature {
        HomeView.HomeSnapshotSignature(
            libraryRevision: library, playlistRevision: 1, historyRevision: history,
            visibleSongCount: 2, visibleAlbumCount: 1, visibleArtistCount: 1,
            recentSongIDs: ["one"], dayStamp: 20260908,
            localeIdentifier: "zh-Hans_CN", timeZoneIdentifier: "Asia/Shanghai",
            quickAccess: pins, quickAccessLimit: 6, showsRecommendations: recommendations
        )
    }

    func testReturningToCompletedHomeReusesSnapshotButSameCountEditsInvalidateIt() {
        let model = HomeView.Model()
        let original = signature()
        model.isPrepared = true
        model.signature = original
        model.highlightsSignature = original
        model.recommendationSignature = original

        XCTAssertFalse(model.needsRefresh(for: signature()))
        XCTAssertTrue(model.needsRefresh(for: signature(library: 2)))
        XCTAssertTrue(model.needsRefresh(for: signature(history: 2)))
        XCTAssertTrue(model.needsRefresh(for: signature(pins: "changed-pins")))
    }

    func testLeavingDuringRefreshDoesNotMakePartialResultsReusable() {
        let model = HomeView.Model()
        let previous = signature(library: 1)
        let current = signature(library: 2)
        model.isPrepared = true
        model.signature = current
        model.highlightsSignature = current
        model.recommendationSignature = previous

        XCTAssertTrue(model.needsRefresh(for: current))
        model.recommendationSignature = current
        XCTAssertFalse(model.needsRefresh(for: current))
    }

    func testHiddenRecommendationsDoNotKeepHomeCachePending() {
        let model = HomeView.Model()
        let current = signature(recommendations: false)
        model.isPrepared = true
        model.signature = current
        model.highlightsSignature = current

        XCTAssertFalse(model.needsRefresh(for: current))
        XCTAssertTrue(model.needsRefresh(for: signature(recommendations: true)))
    }

    func testReturningToFoldersReusesIndexAndCatchesMissedMetadataOrNames() {
        let model = HomeDiscoveryModel()
        let song = Song(
            id: "one", title: "One", fileFormat: .mp3,
            filePath: "/Music/one.mp3", sourceID: "source"
        )
        let source = LibraryFolderSourceDescriptor(
            sourceID: "source", displayName: "Library",
            scanRoots: ["/Music"], pathSemantics: .hierarchical
        )
        let request = HomeDiscoveryModel.Request(
            collection: 1, playlists: 1, hierarchy: 1, names: 0, sources: [source]
        )
        let token = UUID()
        let names = ["source": ["/Music": "Music"]]
        XCTAssertTrue(model.needsRebuild(for: request, metadataToken: token, directoryNames: names))
        model.publish(
            index: LibraryFolderIndexBuilder.build(sources: [source], songs: [song]),
            songs: [song.id: song], covers: [:], request: request,
            metadataToken: token, directoryNames: names
        )
        let publishedRevision = model.revision

        XCTAssertFalse(model.needsRebuild(for: request, metadataToken: token, directoryNames: names))
        model.refreshHistory()
        XCTAssertEqual(model.revision, publishedRevision)
        XCTAssertEqual(model.songsByID[song.id]?.title, "One")
        XCTAssertTrue(model.needsRebuild(for: request, metadataToken: UUID(), directoryNames: names))
        XCTAssertTrue(model.needsRebuild(
            for: request, metadataToken: token,
            directoryNames: ["source": ["/Music": "Renamed"]]
        ))

        var updated = song
        updated.title = "Edited title"
        model.updateMetadata(song: updated)
        let handledToken = UUID()
        model.handledMetadataToken = handledToken
        XCTAssertEqual(model.songsByID[song.id]?.title, "Edited title")
        XCTAssertFalse(model.needsRebuild(for: request, metadataToken: handledToken, directoryNames: names))
    }

    func testFolderRequestIsOnlyReusableAfterSuccessfulPublication() {
        let model = HomeDiscoveryModel()
        let initial = HomeDiscoveryModel.Request(
            collection: 1, playlists: 1, hierarchy: 1, names: 0, sources: []
        )
        let changed = HomeDiscoveryModel.Request(
            collection: 1, playlists: 2, hierarchy: 1, names: 0, sources: []
        )
        let token = UUID()
        model.publish(
            index: LibraryFolderIndexBuilder.build(sources: [], songs: []),
            songs: [:], covers: [:], request: initial,
            metadataToken: token, directoryNames: [:]
        )

        XCTAssertTrue(model.needsRebuild(for: changed, metadataToken: token, directoryNames: [:]))
        XCTAssertFalse(model.needsRebuild(for: initial, metadataToken: token, directoryNames: [:]))
        model.publish(
            index: LibraryFolderIndexBuilder.build(sources: [], songs: []),
            songs: [:], covers: [:], request: changed,
            metadataToken: token, directoryNames: [:]
        )
        XCTAssertFalse(model.needsRebuild(for: changed, metadataToken: token, directoryNames: [:]))
    }
}

@MainActor
final class LibraryPreviewSessionTests: XCTestCase {
    func testSuccessfulSourceSyncAdvancesPreviewInvalidationRevision() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrimuseSourceSyncRevisionTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let initialRevision = library.sourceSyncCompletionRevision

        library.sourceSyncDidComplete()

        XCTAssertEqual(library.sourceSyncCompletionRevision, initialRevision + 1)
    }

    func testIdenticalMirrorPlaylistSnapshotDoesNotAdvanceRevision() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrimuseMirrorPlaylistNoopTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let songs = [
            Song(id: "one", title: "One", fileFormat: .mp3, filePath: "/songs/one.mp3", sourceID: "source"),
            Song(id: "two", title: "Two", fileFormat: .mp3, filePath: "/songs/two.mp3", sourceID: "source"),
        ]
        library.addSongs(songs, affectedSourceIDs: ["source"])
        let playlistID = ServerPlaylistIdentity.playlistID(
            sourceID: "source",
            serverPlaylistID: "favorites"
        )
        library.ensurePlaylist(id: playlistID, name: "Favorites")
        library.replaceMirrorPlaylistSongs(
            playlistID: playlistID,
            songIDs: ["one", "two"],
            coverArtPath: "cover-1"
        )
        let revision = library.playlistCollectionRevision
        let updatedAt = try XCTUnwrap(library.playlist(id: playlistID)?.updatedAt)

        library.replaceMirrorPlaylistSongs(
            playlistID: playlistID,
            songIDs: ["one", "two"],
            coverArtPath: "cover-1"
        )

        XCTAssertEqual(library.playlistCollectionRevision, revision)
        XCTAssertEqual(library.playlist(id: playlistID)?.updatedAt, updatedAt)

        library.replaceMirrorPlaylistSongs(
            playlistID: playlistID,
            songIDs: ["two", "one"],
            coverArtPath: "cover-1"
        )
        XCTAssertEqual(library.playlistCollectionRevision, revision + 1)
    }

    func testMergeOnlyServerFallbackPreservesMissingRowsAndLocalEnrichment() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrimuseServerFallbackMergeTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        var existing = Song(
            id: "one",
            title: "One",
            albumID: "provider-old",
            artistID: "provider-artist-old",
            albumTitle: "Album",
            artistName: "Artist",
            duration: 180,
            fileFormat: .mp3,
            filePath: "/songs/one.mp3",
            sourceID: "source",
            fileSize: 1_024,
            revision: "r1"
        )
        existing.lyricsText = "local lyrics"
        existing.replayGainTrackGain = -7.25
        let missingFromFallback = Song(
            id: "two",
            title: "Two",
            fileFormat: .mp3,
            filePath: "/songs/two.mp3",
            sourceID: "source"
        )
        library.addSongs([existing, missingFromFallback], affectedSourceIDs: ["source"])
        let locallyEnriched = try XCTUnwrap(library.song(id: existing.id))

        var incoming = existing
        incoming.albumID = "provider-new"
        incoming.artistID = "provider-artist-new"
        incoming.lyricsText = nil
        incoming.replayGainTrackGain = nil
        library.addSongs(
            [incoming],
            affectedSourceIDs: ["source"],
            pruneMissingSongs: false,
            mergeServerCatalogRows: true
        )

        XCTAssertEqual(library.song(id: existing.id), locallyEnriched)
        XCTAssertNotNil(library.song(id: missingFromFallback.id))
    }

    func testProgressiveServerPagesAreVisibleWithoutPruningEarlierRows() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrimuseProgressiveServerPageTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let existing = Song(
            id: "existing",
            title: "Existing",
            fileFormat: .mp3,
            filePath: "/songs/existing.mp3",
            sourceID: "source"
        )
        let firstPage = Song(
            id: "page-one",
            title: "Page One",
            fileFormat: .flac,
            filePath: "/songs/page-one.flac",
            sourceID: "source"
        )
        library.addSongs([existing], affectedSourceIDs: ["source"])

        library.addSongs(
            [firstPage],
            affectedSourceIDs: ["source"],
            notifyRemovals: false,
            pruneMissingSongs: false,
            mergeServerCatalogRows: true
        )
        library.addSongs(
            [firstPage],
            affectedSourceIDs: ["source"],
            notifyRemovals: false,
            pruneMissingSongs: false,
            mergeServerCatalogRows: true
        )

        XCTAssertNotNil(library.song(id: existing.id))
        XCTAssertNotNil(library.song(id: firstPage.id))
        XCTAssertEqual(library.songs.filter { $0.sourceID == "source" }.count, 2)
    }

    func testFormatAndCueReplacementSurvivesBareRowMergeAndPublishesContentChange() throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrimuseServerFormatReplacementTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        var existing = Song(
            id: "disc-track",
            title: "Track",
            albumTitle: "Album",
            artistName: "Artist",
            duration: 180,
            fileFormat: .mp3,
            filePath: "/music/disc.mp3",
            sourceID: "source",
            fileSize: 4_096,
            bitRate: 320,
            revision: "r1"
        )
        existing.lyricsText = "device enrichment"
        library.addSongs([existing], affectedSourceIDs: ["source"])

        let contentChanged = expectation(description: "content replacement notification")
        let token = NotificationCenter.default.addObserver(
            forName: .primuseSongContentChanged,
            object: nil,
            queue: nil
        ) { _ in
            contentChanged.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let incoming = Song(
            id: existing.id,
            title: existing.title,
            fileFormat: .flac,
            filePath: "/music/disc.flac",
            sourceID: existing.sourceID,
            fileSize: existing.fileSize,
            cueSheetPath: "/music/disc.cue",
            cueStartTime: 15,
            cueEndTime: 195,
            revision: existing.revision
        )
        library.addSongs(
            [incoming],
            affectedSourceIDs: ["source"],
            mergeServerCatalogRows: true
        )

        XCTAssertEqual(XCTWaiter().wait(for: [contentChanged], timeout: 0), .completed)
        let replaced = try XCTUnwrap(library.song(id: existing.id))
        XCTAssertEqual(replaced.fileFormat, .flac)
        XCTAssertEqual(replaced.cueSheetPath, incoming.cueSheetPath)
        XCTAssertEqual(replaced.cueStartTime, incoming.cueStartTime)
        XCTAssertEqual(replaced.cueEndTime, incoming.cueEndTime)
        XCTAssertNil(replaced.lyricsText)
    }

    func testLargeSourceRemovalPublishesPrecomputedIDsAndRetainsOtherSources() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PrimuseLargeSourceRemovalTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let removedSongs = (0..<2_048).map { index in
            Song(
                id: "removed-\(index)",
                title: "Removed \(index)",
                fileFormat: .flac,
                filePath: "/removed/\(index).flac",
                sourceID: "large-source"
            )
        }
        let retainedSongs = (0..<32).map { index in
            Song(
                id: "retained-\(index)",
                title: "Retained \(index)",
                fileFormat: .mp3,
                filePath: "/retained/\(index).mp3",
                sourceID: "other-source"
            )
        }
        library.addSongs(
            removedSongs + retainedSongs,
            affectedSourceIDs: ["large-source", "other-source"]
        )

        let notification = expectation(description: "source-scoped song removal")
        let token = NotificationCenter.default.addObserver(
            forName: .primuseSongsRemoved,
            object: nil,
            queue: .main
        ) { note in
            XCTAssertEqual(
                Set((note.userInfo?["sourceIDs"] as? [String]) ?? []),
                ["large-source"]
            )
            XCTAssertEqual(
                (note.userInfo?["songIDs"] as? Set<String>)?.count,
                removedSongs.count
            )
            notification.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        let removedIDs = await library.removeSongsForSources(["large-source"])

        await fulfillment(of: [notification], timeout: 1)
        XCTAssertEqual(removedIDs.count, removedSongs.count)
        XCTAssertEqual(library.songs.map(\.id), retainedSongs.map(\.id))
        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }
    }
}

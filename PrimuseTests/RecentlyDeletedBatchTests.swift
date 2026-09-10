import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

@MainActor
final class RecentlyDeletedBatchTests: XCTestCase {
    func testBatchPurgeKeepsPlaylistTombstonesAndOnlyRemovesConfirmedSmartPlaylists() async throws {
        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseRecentlyDeletedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let first = library.createPlaylist(name: "First")
        let second = library.createPlaylist(name: "Second")
        let untouched = library.createPlaylist(name: "Untouched")
        library.deletePlaylists(ids: [first.id, second.id])

        let firstSmart = SmartPlaylist(name: "First Smart")
        let secondSmart = SmartPlaylist(name: "Second Smart")
        let untouchedSmart = SmartPlaylist(name: "Untouched Smart")
        library.saveSmartPlaylist(firstSmart)
        library.saveSmartPlaylist(secondSmart)
        library.saveSmartPlaylist(untouchedSmart)
        library.deleteSmartPlaylist(id: firstSmart.id)
        library.deleteSmartPlaylist(id: secondSmart.id)

        let plan = RecentlyDeletedPurgePlan(
            playlistIDs: [first.id, second.id],
            smartPlaylistIDs: [firstSmart.id, secondSmart.id],
            sourceIDs: [],
            scraperConfigurationIDs: []
        )
        library.permanentlyDeletePlaylists(ids: plan.playlistIDs)
        library.permanentlyDeleteSmartPlaylists(ids: plan.smartPlaylistIDs)

        let purgedPlaylists = Dictionary(
            uniqueKeysWithValues: library.allPlaylists.map { ($0.id, $0) }
        )
        XCTAssertTrue(purgedPlaylists[first.id]?.isPurged == true)
        XCTAssertTrue(purgedPlaylists[second.id]?.isPurged == true)
        XCTAssertTrue(purgedPlaylists[untouched.id]?.isDeleted == false)
        XCTAssertFalse(library.recentlyDeletedPlaylists.contains {
            plan.playlistIDs.contains($0.id)
        })
        XCTAssertEqual(library.allSmartPlaylists.map(\.id), [untouchedSmart.id])
        XCTAssertFalse(plan.deletesRemoteMedia)

        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }
    }

    // MARK: - Device-local song exclusions (WebDAV deletion refused)

    /// A WebDAV row whose source deletion the server refused. `identityKey`
    /// is `"<sourceID>:<filePath>"` when no cloud-account resolver is wired,
    /// which is the case for an isolated test library.
    private static func makeWebDAVSong(
        id: String = "webdav-duplicate",
        sourceID: String = "webdav-source",
        filePath: String = "/Music/Album/duplicate.flac"
    ) -> Song {
        Song(
            id: id,
            title: "Duplicate",
            artistName: "Tester",
            duration: 120,
            fileFormat: .flac,
            filePath: filePath,
            sourceID: sourceID
        )
    }

    private static func makeIsolatedStorageDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseDeviceLocalExclusionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testRemoveSongsFromThisDeviceDropsRowsWithoutWritingASyncedTombstone() throws {
        let storageDirectory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let library = MusicLibrary(storageDirectory: storageDirectory)
        let song = Self.makeWebDAVSong()
        library.addSongs([song])
        XCTAssertEqual(library.songs.map(\.id), [song.id])

        let remainingCounts = try library.removeSongsFromThisDevice([song])
        XCTAssertEqual(remainingCounts[song.sourceID], 0)
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertTrue(library.isExcludedOnThisDevice(song))
        // The tombstone set is merged across devices by snapshot sync, so a
        // device-local removal must never land in it.
        XCTAssertTrue(library.deletedSongIdentities.isEmpty)

        // A rescan of the same source on this device must not bring it back.
        library.addSongs([song])
        XCTAssertTrue(library.songs.isEmpty)
        XCTAssertTrue(library.deletedSongIdentities.isEmpty)
    }

    func testDeviceLocalExclusionSurvivesReopeningTheSameStorageDirectory() async throws {
        let storageDirectory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let song = Self.makeWebDAVSong()
        let library = MusicLibrary(storageDirectory: storageDirectory)
        library.addSongs([song])
        try library.removeSongsFromThisDevice([song])
        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }

        let reopened = MusicLibrary(storageDirectory: storageDirectory)
        XCTAssertTrue(reopened.isExcludedOnThisDevice(song))
        XCTAssertFalse(reopened.songs.contains { $0.id == song.id })
        reopened.addSongs([song])
        XCTAssertFalse(reopened.songs.contains { $0.id == song.id })
    }

    func testPortableSnapshotPreservesSongsHiddenOnlyOnSendingDevice() async throws {
        let storageDirectory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let song = Self.makeWebDAVSong()
        let library = MusicLibrary(storageDirectory: storageDirectory)
        library.addSongs([song])
        try library.removeSongsFromThisDevice([song])
        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }

        let identity = "\(song.sourceID):\(song.filePath)"
        let snapshotData = try Data(
            contentsOf: storageDirectory.appendingPathComponent("library-cache.json")
        )
        let snapshotText = try XCTUnwrap(String(data: snapshotData, encoding: .utf8))
        XCTAssertFalse(snapshotText.contains(identity))
        let snapshotObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: snapshotData) as? [String: Any]
        )
        let tombstones = snapshotObject["deletedSongIdentities"] as? [String] ?? []
        XCTAssertFalse(tombstones.contains(identity))
        let snapshotSongPaths = (snapshotObject["songs"] as? [[String: Any]] ?? [])
            .compactMap { $0["filePath"] as? String }
        XCTAssertTrue(snapshotSongPaths.contains(song.filePath))
        let receivingDirectory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: receivingDirectory) }
        try snapshotData.write(to: receivingDirectory.appendingPathComponent("library-cache.json"))
        let receivingLibrary = MusicLibrary(storageDirectory: receivingDirectory)
        XCTAssertEqual(receivingLibrary.songs.map(\.id), [song.id])
        XCTAssertFalse(receivingLibrary.isExcludedOnThisDevice(song))

        // The exclusion lives in its own device-local ledger file instead.
        let ledgerData = try Data(
            contentsOf: storageDirectory
                .appendingPathComponent("library-device-local-excluded-songs.json")
        )
        let ledger = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ledgerData) as? [String: Any]
        )
        XCTAssertEqual(ledger["identities"] as? [String], [identity])
    }

    /// The ledger stores `identityKey(for:)`, whose prefix is the resolved
    /// cloud-account identity when a resolver is wired. `loadSnapshot` runs
    /// from `init`, before AppServices installs that resolver, so the reopened
    /// library computes the raw `"<sourceID>:<filePath>"` form for the same
    /// song — the exclusion has to hold on both sides of that window.
    func testDeviceLocalExclusionRecordedWithResolverStillAppliesAfterReopen() async throws {
        let storageDirectory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let source = MusicSource(id: "webdav-source", name: "WebDAV", type: .webdav)
        let song = Self.makeWebDAVSong(sourceID: source.id)
        let library = MusicLibrary(storageDirectory: storageDirectory)
        library.sourceIdentityResolver = { $0 == source.id ? "account-1" : nil }
        library.addSongs([song])
        try library.removeSongsFromThisDevice([song])
        guard case .success = await library.persistNowAndWait() else {
            XCTFail("The isolated library did not finish persistence")
            return
        }

        // Reopened the way the app does it: no resolver yet at load time.
        let reopened = MusicLibrary(storageDirectory: storageDirectory)
        XCTAssertFalse(reopened.songs.contains { $0.id == song.id })
        XCTAssertTrue(reopened.isExcludedOnThisDevice(song))

        // Once AppServices installs the resolver the recorded key matches
        // directly, and a rescan of the same source still must not re-add it.
        reopened.sourceIdentityResolver = { $0 == source.id ? "account-1" : nil }
        reopened.addSongs([song])
        XCTAssertTrue(reopened.songs.isEmpty)
    }

    func testLocalExclusionPreservesPlaylistAndHistoryAcrossSyncAndReload() async throws {
        let directory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        let song = Self.makeWebDAVSong()
        library.addSongs([song])
        let playlist = library.createPlaylist(name: "Retained membership")
        library.add(songIDs: [song.id], toPlaylist: playlist.id)
        library.recordPlayback(of: song.id)
        try library.removeSongsFromThisDevice([song])
        library.addSongs([song])
        await library.waitForPendingIndex()
        XCTAssertNil(library.song(id: song.id))
        XCTAssertEqual(library.songForSynchronization(id: song.id)?.filePath, song.filePath)
        XCTAssertTrue(library.songs(forPlaylist: playlist.id).isEmpty)
        XCTAssertEqual(library.rawSongIDs(forPlaylist: playlist.id), [song.id])
        XCTAssertEqual(library.recentPlaybackSongIDsForSync, [song.id])

        let identity = SongIdentity(songID: song.id, title: song.title,
            artistName: song.artistName, duration: song.duration,
            cloudAccountID: nil, filePath: song.filePath)
        library.applyRemotePlaylist(playlist, songIDs: [song.id], identities: [identity])
        library.applyRemotePlaybackHistory(songIDs: [song.id], identities: [identity])
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("Snapshot did not persist")
        }
        let data = try Data(contentsOf: directory.appendingPathComponent("library-cache.json"))
        let receiverDirectory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: receiverDirectory) }
        try data.write(to: receiverDirectory.appendingPathComponent("library-cache.json"))
        let receiver = MusicLibrary(storageDirectory: receiverDirectory)
        XCTAssertEqual(receiver.songs(forPlaylist: playlist.id).map(\.id), [song.id])
        XCTAssertEqual(receiver.recentlyPlayedSongs().map(\.id), [song.id])

        let reopened = MusicLibrary(storageDirectory: directory)
        XCTAssertTrue(reopened.songs.isEmpty)
        XCTAssertEqual(reopened.rawSongIDs(forPlaylist: playlist.id), [song.id])
        XCTAssertEqual(reopened.recentPlaybackSongIDsForSync, [song.id])
        XCTAssertEqual(reopened.songForSynchronization(id: song.id)?.id, song.id)
    }

    func testFailedExclusionWriteLeavesLocalRowsAndMembershipIntact() async throws {
        let directory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        let song = Self.makeWebDAVSong()
        library.addSongs([song])
        let playlist = library.createPlaylist(name: "Unchanged")
        library.add(songIDs: [song.id], toPlaylist: playlist.id)
        let ledgerURL = directory.appendingPathComponent("library-device-local-excluded-songs.json")
        try FileManager.default.createDirectory(at: ledgerURL, withIntermediateDirectories: true)
        XCTAssertThrowsError(try library.removeSongsFromThisDevice([song]))
        XCTAssertEqual(library.songs.map(\.id), [song.id])
        XCTAssertFalse(library.isExcludedOnThisDevice(song))
        XCTAssertEqual(library.rawSongIDs(forPlaylist: playlist.id), [song.id])
        _ = await library.persistNowAndWait()
    }

    func testRemovingSourceDiscardsRetainedSnapshotRows() async throws {
        let directory = try Self.makeIsolatedStorageDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        let song = Self.makeWebDAVSong()
        library.addSongs([song])
        try library.removeSongsFromThisDevice([song])
        await library.removeSongsForSource(song.sourceID)
        XCTAssertNil(library.songForSynchronization(id: song.id))
        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("Snapshot did not persist")
        }
        let reopened = MusicLibrary(storageDirectory: directory)
        XCTAssertNil(reopened.songForSynchronization(id: song.id))
    }

    func testOnlyWebDAVPermissionFailuresOfferDeviceLocalRemoval() throws {
        let webdav = MusicSource(id: "webdav-source", name: "WebDAV", type: .webdav)
        let smb = MusicSource(id: "smb-source", name: "SMB", type: .smb)
        let permissionDenied = Self.makeWebDAVSong(id: "permission", filePath: "/Music/a.flac")
        let readOnly = Self.makeWebDAVSong(id: "read-only", filePath: "/Music/b.flac")
        let authenticationRequired = Self.makeWebDAVSong(id: "auth", filePath: "/Music/c.flac")
        let mixed = Self.makeWebDAVSong(id: "mixed", filePath: "/Music/d.flac")

        let webdavFailure = DuplicateCleanupService.SourceFailure(
            source: webdav,
            songs: [permissionDenied, readOnly, authenticationRequired, mixed],
            reasons: [.permissionDenied, .readOnly, .authenticationRequired, .unavailable],
            reasonsBySongID: [
                permissionDenied.id: [.permissionDenied],
                readOnly.id: [.readOnly],
                authenticationRequired.id: [.authenticationRequired],
                mixed.id: [.permissionDenied, .unavailable],
            ]
        )
        XCTAssertTrue(webdavFailure.supportsDeviceLocalRemoval)
        XCTAssertEqual(
            Set(webdavFailure.deviceLocalRemovableSongs.map(\.id)),
            [permissionDenied.id, readOnly.id]
        )

        let smbSong = Self.makeWebDAVSong(id: "smb-song", sourceID: smb.id, filePath: "/Music/e.flac")
        let smbFailure = DuplicateCleanupService.SourceFailure(
            source: smb,
            songs: [smbSong],
            reasons: [.permissionDenied],
            reasonsBySongID: [smbSong.id: [.permissionDenied]]
        )
        XCTAssertFalse(smbFailure.supportsDeviceLocalRemoval)
        XCTAssertTrue(smbFailure.deviceLocalRemovableSongs.isEmpty)
    }
}

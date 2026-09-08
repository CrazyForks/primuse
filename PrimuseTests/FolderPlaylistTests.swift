import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

@MainActor
final class FolderPlaylistTests: XCTestCase {
    func testIncrementalDirectoryDeletionPrunesNestedSongsAndSkipsConfirmedMissingPaths() async throws {
        let items = [indexed("root", parent: nil, directory: true),
                     indexed("gone", parent: "root", directory: true),
                     indexed("nested", parent: "gone", directory: true),
                     indexed("removed", parent: "nested"),
                     indexed("kept", parent: "other")]
        let index = Dictionary(uniqueKeysWithValues: items.map { ($0.stableKey, $0) })
        let connector = FolderPlaylistTestConnector(missingPaths: ["nested"])
        let scanner = ConnectorScanner(connector: connector, sourceID: "source")
        let result = try await scanner.reconcileChangedDirectories(
            ["root", "nested"], deletedStableKeys: ["gone"],
            existingSongs: [song("removed"), song("kept")], existingIndex: index, scanEpoch: 2
        )
        XCTAssertEqual(result.songs.map(\.id), ["kept"])
        XCTAssertEqual(Set(result.index.keys), ["root", "kept"])
    }

    func testFailedDirectoryListingDoesNotYieldAnEmptyReconciliation() async throws {
        let connector = FolderPlaylistTestConnector(missingPaths: ["unconfirmed"])
        let scanner = ConnectorScanner(connector: connector, sourceID: "source")
        let track = indexed("kept", parent: "unconfirmed")
        do {
            _ = try await scanner.reconcileChangedDirectories(
                ["unconfirmed"], deletedStableKeys: [], existingSongs: [song("kept")],
                existingIndex: ["kept": track], scanEpoch: 2
            )
            XCTFail("An unconfirmed missing path must fail rather than clear the library")
        } catch SourceError.pathNotFound { }
    }

    func testFolderPlaylistPersistsAndReconcilesWhileOrdinaryPlaylistStaysStatic() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrimuseFolderPlaylist-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = MusicLibrary(storageDirectory: directory)
        let source = MusicSource(id: "source", name: "NAS", type: .webdav, extraConfig: "[\"/Music\"]")
        let first = song("first")
        let second = song("second")
        library.addSongs([first, second], affectedSourceIDs: [source.id])
        await library.waitForPendingIndex()
        let nodeID = LibraryFolderNodeID(sourceID: source.id, kind: .folder, normalizedRelativePath: "/music/live")
        let playlist = library.createFolderPlaylist(
            name: "Live", nodeID: nodeID, cloudAccountID: nil, songIDs: [first.id]
        )
        let repeated = library.createFolderPlaylist(
            name: "Live", nodeID: nodeID, cloudAccountID: nil, songIDs: [first.id]
        )
        XCTAssertEqual(repeated.id, playlist.id)
        let ordinary = library.createPlaylist(name: "Static", songIDs: [first.id])
        let bindings = library.folderPlaylistBindings(for: source)
        let refreshed = FolderPlaylistMembershipPolicy.memberships(
            bindings: bindings, source: source, songs: [first, second], syncIndex: nil
        )
        library.applyFolderPlaylistMemberships(refreshed, expectedBindings: bindings)
        XCTAssertEqual(Set(library.songs(forPlaylist: playlist.id).map(\.id)), [first.id, second.id])
        XCTAssertEqual(library.songs(forPlaylist: ordinary.id).map(\.id), [first.id])
        library.remove(songID: first.id, fromPlaylist: playlist.id)
        library.replacePlaylistSongs(playlistID: playlist.id, songIDs: [])
        XCTAssertEqual(library.songs(forPlaylist: playlist.id).count, 2)

        guard case .success = await library.persistNowAndWait() else {
            return XCTFail("Folder binding and membership must finish persistence")
        }
        let restored = MusicLibrary(storageDirectory: directory)
        await restored.waitForPendingIndex()
        XCTAssertEqual(restored.playlist(id: playlist.id)?.folderBinding, playlist.folderBinding)
        XCTAssertEqual(Set(restored.songs(forPlaylist: playlist.id).map(\.id)), [first.id, second.id])

        restored.applyFolderPlaylistMemberships([playlist.id: []], expectedBindings: [:])
        XCTAssertEqual(restored.songs(forPlaylist: playlist.id).count, 2, "A stale binding cannot publish")
        let previousMemberships = [playlist.id: restored.rawSongIDs(forPlaylist: playlist.id)]
        let revisionBeforeDeletion = try XCTUnwrap(restored.playlist(id: playlist.id)?.syncRevision)
        restored.addSongs([second], affectedSourceIDs: [source.id])
        await restored.waitForPendingIndex()
        restored.applyFolderPlaylistMemberships(
            [playlist.id: [second.id]], expectedBindings: bindings, previousMemberships: previousMemberships
        )
        XCTAssertGreaterThan(try XCTUnwrap(restored.playlist(id: playlist.id)?.syncRevision), revisionBeforeDeletion,
                             "Deletion must publish even when library pruning already removed the song ID")
        restored.applyFolderPlaylistMemberships([playlist.id: []], expectedBindings: bindings)
        XCTAssertTrue(restored.songs(forPlaylist: playlist.id).isEmpty)
        XCTAssertEqual(restored.playlist(id: playlist.id)?.folderBinding, playlist.folderBinding)
        guard case .success = await restored.persistNowAndWait() else {
            return XCTFail("An authoritative empty directory must persist without deleting its playlist")
        }
    }

    private func song(_ id: String) -> Song {
        Song(id: id, title: id, fileFormat: .mp3, filePath: "/Music/Live/\(id).mp3", sourceID: "source")
    }

    private func indexed(_ key: String, parent: String?, directory: Bool = false) -> SourceSyncIndexedItem {
        SourceSyncIndexedItem(stableKey: key, path: key, parentPath: parent,
                             isDirectory: directory, songIDs: directory ? [] : [key],
                             size: 0, modifiedDate: nil, revision: nil)
    }
}

private actor FolderPlaylistTestConnector: MusicSourceConnector {
    let sourceID = "source"
    let missingPaths: Set<String>

    init(missingPaths: Set<String>) { self.missingPaths = missingPaths }
    func connect() async throws { }
    func disconnect() async { }
    func listFiles(at path: String) async throws -> [RemoteFileItem] {
        if missingPaths.contains(path) { throw SourceError.pathNotFound(path) }
        return []
    }
    func localURL(for path: String) async throws -> URL { throw SourceError.fileNotFound(path) }
    func streamData(for path: String) async throws -> AsyncThrowingStream<Data, Error> {
        .init { $0.finish() }
    }
    func scanAudioFiles(from path: String) async throws -> AsyncThrowingStream<RemoteFileItem, Error> {
        .init { $0.finish() }
    }
}

import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

@MainActor
final class FnMusicSourceTests: XCTestCase {
    func testRangeRefreshesBusinessAuthenticationFailure() async throws {
        let source = makeSource()
        let data = try await source.fetchRange(path: "/fnmusic/tracks/song.flac", offset: 0, length: 2)
        XCTAssertEqual(data, Data([1, 2]))
        let sourceID = await source.sourceID
        XCTAssertEqual(FnMusicSourceURLProtocol.loginCount(host: sourceID), 2)
    }

    func testPlaylistAndFavoriteConnectorsUseAuthenticatedLibraryEndpoints() async throws {
        let source = makeSource()
        let snapshot = try await source.fetchServerPlaylists()
        XCTAssertEqual(snapshot.playlists.map(\.id), ["playlist"])
        XCTAssertEqual(snapshot.playlists.first?.trackIDs, ["song"])
        XCTAssertTrue(snapshot.failedPlaylistIDs.isEmpty)
        let added = try await source.setServerFavorite(itemID: "song", isFavorite: true)
        XCTAssertEqual(added.itemIDs, ["song"])
        let removed = try await source.setServerFavorite(itemID: "song", isFavorite: false)
        XCTAssertTrue(removed.itemIDs.isEmpty)
    }

    func testMirrorPreservesFailedDetailsAndPrunesOnlyDeletedPlaylistsFromTheSameSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FnMusicMirror-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let library = MusicLibrary(storageDirectory: root)
        let source = MusicSource(id: "fn", name: "Feiniu", type: .fnMusic)
        library.addSongs([
            Song(id: "one", title: "One", fileFormat: .flac, filePath: "/fnmusic/tracks/one.flac", sourceID: source.id),
            Song(id: "two", title: "Two", fileFormat: .flac, filePath: "/fnmusic/tracks/two.flac", sourceID: source.id),
        ], affectedSourceIDs: [source.id])
        await library.waitForPendingIndex()
        func id(_ name: String, sourceID: String = "fn") -> String {
            ServerPlaylistIdentity.playlistID(sourceID: sourceID, serverPlaylistID: name)
        }
        for playlistID in [id("failed"), id("deleted"), id("other", sourceID: "elsewhere")] {
            library.ensurePlaylist(id: playlistID, name: playlistID)
            library.replaceMirrorPlaylistSongs(playlistID: playlistID, songIDs: ["one"], coverArtPath: nil)
        }
        let result = ServerPlaylistMirror.apply(snapshot: ServerPlaylistSnapshot(playlists: [
            ServerPlaylist(id: "new", name: "New", trackIDs: ["two", "one", "two"], reportedTrackCount: 3),
            ServerPlaylist(id: "empty", name: "Empty", trackIDs: [], reportedTrackCount: 0),
        ], failedPlaylistIDs: ["failed"]), source: source, library: library)
        XCTAssertEqual(result.syncedPlaylistCount, 2)
        XCTAssertEqual(library.songs(forPlaylist: id("new")).map(\.id), ["two", "one"])
        XCTAssertEqual(library.songs(forPlaylist: id("failed")).map(\.id), ["one"])
        XCTAssertNotNil(library.playlist(id: id("empty")))
        XCTAssertNil(library.playlist(id: id("deleted")))
        XCTAssertNotNil(library.playlist(id: id("other", sourceID: "elsewhere")))
    }

    private func makeSource() -> FnMusicSource {
        let host = UUID().uuidString.lowercased() + ".invalid"
        FnMusicSourceURLProtocol.register(host: host)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FnMusicSourceURLProtocol.self]
        return FnMusicSource(sourceID: host, host: host, port: 5667, useSSL: true,
                             basePath: nil, connectionMode: .address, accessCode: nil,
                             username: "qa", password: "test", session: URLSession(configuration: configuration))
    }
}

private final class FnMusicSourceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var states: [String: (logins: Int, favorite: Bool)] = [:]
    static func register(host: String) { lock.withLock { states[host] = (0, false) } }
    static func loginCount(host: String) -> Int { lock.withLock { states[host]?.logins ?? 0 } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let (status, headers, data): (Int, [String: String], Data) = Self.lock.withLock {
            var state = Self.states[url.host!]!
            defer { Self.states[url.host!] = state }
            let jsonHeaders = ["Content-Type": "application/json"]
            func json(_ payload: Any) -> Data { try! JSONSerialization.data(withJSONObject: payload) }
            func page(_ items: [[String: Any]]) -> Data { json(["code": 0, "data": ["list": items, "total": items.count]]) }
            switch url.lastPathComponent {
            case "password-login":
                state.logins += 1
                return (200, jsonHeaders, json(["code": 200, "data": ["userToken": "token-\(state.logins)"]]))
            case "stream":
                if state.logins == 1 { return (200, jsonHeaders, json(["code": 120001, "msg": "INVALID TOKEN"])) }
                return (206, ["Content-Type": "audio/flac", "Content-Range": "bytes 0-1/8", "Content-Length": "2"], Data([1, 2]))
            case "list" where url.path.contains("/playlist/list"):
                return (200, jsonHeaders, page([["guid": "playlist", "name": "Playlist", "trackCount": 1]]))
            case "list" where url.path.contains("/playlist-detail/"):
                return (200, jsonHeaders, page([["guid": "song"]]))
            case "list" where url.path.contains("/favorite-track/"):
                return (200, jsonHeaders, page(state.favorite ? [["guid": "song"]] : []))
            case "create", "delete":
                state.favorite = url.lastPathComponent == "create"
                return (200, jsonHeaders, json(["code": 0, "data": NSNull()]))
            default:
                return (404, jsonHeaders, Data())
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

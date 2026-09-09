import CryptoKit
import Foundation
import PrimuseKit
import XCTest
@testable import Primuse

@MainActor
final class FnMusicSourceTests: XCTestCase {
    func testLibraryIdentityEncodingPreservesExistingIDs() {
        for input in ["", "Artist:Album", "陈奕迅:十年", "a\u{0}b", String(repeating: "音乐", count: 500)] {
            let expected = SHA256.hash(data: Data(input.utf8)).prefix(16)
                .map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(MusicLibrary.hashID(input), expected)
        }
    }

    func testFailedAtomicScanDoesNotPublishPartialSongs() async throws {
        let fixture = try makeScanFixture(count: 250, failAfterPage: true)
        let old = Song(id: "old", title: "Old", fileFormat: .flac,
                       filePath: "/old.flac", sourceID: fixture.source.id)
        fixture.library.addSongs([old], affectedSourceIDs: [fixture.source.id])
        await fixture.library.waitForPendingIndex()
        fixture.library.ensurePlaylist(id: "saved", name: "Saved")
        fixture.library.replacePlaylistSongs(playlistID: "saved", songIDs: [old.id])
        XCTAssertEqual(fixture.library.rawSongIDs(forPlaylist: "saved"), [old.id])
        let baseline = fixture.library.songs
        let generation = fixture.library.songMutationGenerationForMaintenance
        var inspectedIDs: Set<String> = []
        fixture.scan.metadataInspectionHandler = { inspectedIDs.formUnion($0) }
        XCTAssertTrue(fixture.start())
        let deadline = Date().addingTimeInterval(10)
        while await !fixture.connector.isWaiting, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let reachedPage = await fixture.connector.isWaiting
        XCTAssertTrue(reachedPage)
        // Let the main-actor consumer drain the first page while the producer
        // remains blocked, so coalescing cannot hide an intermediate commit.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(inspectedIDs.count, 250)
        XCTAssertEqual(fixture.library.songs, baseline)
        XCTAssertEqual(fixture.library.songMutationGenerationForMaintenance, generation)
        await fixture.connector.release()
        await fixture.scan.waitForActiveScansToComplete()
        XCTAssertNotNil(fixture.scan.scanStates[fixture.source.id]?.failureMessage)
        XCTAssertEqual(fixture.library.songs, baseline)
        XCTAssertEqual(fixture.library.rawSongIDs(forPlaylist: "saved"), [old.id])
        XCTAssertEqual(fixture.library.songMutationGenerationForMaintenance, generation)
    }

    func testUnchangedFnMusicRescanDoesNotInvalidateLibrary() async throws {
        let fixture = try makeScanFixture(count: 500, failAfterPage: false)
        XCTAssertTrue(fixture.start())
        await fixture.scan.waitForActiveScansToComplete()
        await fixture.library.waitForPendingIndex()
        XCTAssertNil(fixture.scan.scanStates[fixture.source.id]?.failureMessage)
        XCTAssertEqual(fixture.library.songs.count, 500)
        let baseline = fixture.library.songs
        let generation = fixture.library.songMutationGenerationForMaintenance
        let searchRevision = fixture.library.searchRevision
        let spotlightRevision = fixture.library.spotlightIndexRevision
        XCTAssertTrue(fixture.start())
        await fixture.scan.waitForActiveScansToComplete()
        await fixture.library.waitForPendingIndex()
        XCTAssertNil(fixture.scan.scanStates[fixture.source.id]?.failureMessage)
        XCTAssertEqual(fixture.library.songs, baseline)
        XCTAssertEqual(fixture.library.songMutationGenerationForMaintenance, generation)
        XCTAssertEqual(fixture.library.searchRevision, searchRevision)
        XCTAssertEqual(fixture.library.spotlightIndexRevision, spotlightRevision)
    }

    func testDeferredForegroundResumeWaitsForBackoffAndStartsOnlyOnce() async throws {
        let resumeAfter = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970) + 1)
        let fixture = try makeScanFixture(count: 1, failAfterPage: false, resumeAfter: resumeAfter)
        defer { fixture.scan.cancelAllActiveScans() }
        fixture.resume()
        fixture.resume()
        try await Task.sleep(for: .milliseconds(100))
        let initialCount = await fixture.connector.scanCount
        XCTAssertEqual(initialCount, 0)
        let deadline = resumeAfter.addingTimeInterval(5)
        while fixture.library.songs.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.library.songs.count, 1)
        let finalCount = await fixture.connector.scanCount
        XCTAssertEqual(finalCount, 1)
    }

    func testSceneTransitionCancelsDeferredForegroundResume() async throws {
        let resumeAfter = Date(timeIntervalSince1970: ceil(Date().timeIntervalSince1970) + 1)
        let fixture = try makeScanFixture(count: 1, failAfterPage: false, resumeAfter: resumeAfter)
        fixture.resume()
        fixture.scan.cancelAllActiveScans()
        try await Task.sleep(for: .seconds(max(0, resumeAfter.timeIntervalSinceNow) + 1.3))
        let scanCount = await fixture.connector.scanCount
        XCTAssertEqual(scanCount, 0)
        XCTAssertTrue(fixture.scan.scanStates[fixture.source.id]?.canResume == true)
        XCTAssertTrue(fixture.library.songs.isEmpty)
    }

    func testExplicitScanBypassesAutomaticResumeBackoff() async throws {
        let fixture = try makeScanFixture(
            count: 1, failAfterPage: false, resumeAfter: Date().addingTimeInterval(300)
        )
        defer { fixture.scan.cancelAllActiveScans() }
        XCTAssertTrue(fixture.start())
        let deadline = Date().addingTimeInterval(5)
        while fixture.library.songs.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.library.songs.count, 1)
    }

    func testDeferredResumeKeepsManagedLocalImportIndependentOfNetwork() throws {
        let key = "local_import_source_id"
        let previous = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        let sourceID = UUID().uuidString
        UserDefaults.standard.set(sourceID, forKey: key)
        let source = MusicSource(
            id: sourceID, name: "Local fixture", type: .local,
            basePath: LocalImportService.musicDirectory.path
        )
        let now = Date(timeIntervalSince1970: 10_000)
        let resumeAfter = now.addingTimeInterval(300)
        let fixture = try makeScanFixture(
            count: 0, failAfterPage: false, source: source, resumeAfter: resumeAfter
        )
        XCTAssertTrue(LocalImportService.isManagedSource(source))
        XCTAssertEqual(fixture.scan.nextAutomaticResumeDate(at: now, sourceStore: fixture.store), resumeAfter)
        XCTAssertNil(fixture.scan.nextAutomaticResumeDate(
            at: now, sourceStore: fixture.store, networkSourcesOnly: true
        ))
        let network = try makeScanFixture(count: 0, failAfterPage: false, resumeAfter: resumeAfter)
        XCTAssertEqual(network.scan.nextAutomaticResumeDate(
            at: now, sourceStore: network.store, networkSourcesOnly: true
        ), resumeAfter)
        network.store.updateLocal(network.source.id) { $0.isEnabled = false }
        XCTAssertNil(network.scan.nextAutomaticResumeDate(at: now, sourceStore: network.store))
    }

    func testWebDAVDuplicateCleanupSurvivesRescanAndReloadWithoutSourceAccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DuplicateCleanup-\(UUID().uuidString)")
        var source = MusicSource(id: UUID().uuidString, name: "WebDAV fixture", type: .webdav)
        source.extraConfig = MusicSource.encodeScannedDirectories(["/"], into: nil, type: source.type)
        let fixture = try makeScanFixture(count: 2, failAfterPage: false, source: source, root: root)
        XCTAssertTrue(fixture.start())
        await fixture.scan.waitForActiveScansToComplete()
        await fixture.library.waitForPendingIndex()
        XCTAssertNil(fixture.scan.scanStates[source.id]?.failureMessage)
        XCTAssertEqual(Set(fixture.library.songs.map(\.id)), ["track-0", "track-1"])
        let redundant = try XCTUnwrap(fixture.library.songs.first { $0.id == "track-1" })
        // A source-side delete would fail before it can connect. Library-only
        // cleanup must still succeed when the share is unavailable.
        let unavailableManager = SourceManager(sourcesProvider: {
            throw SourceError.connectionFailed("Source access is unavailable")
        })
        let cleanup = DuplicateCleanupService(
            library: fixture.library, sourceManager: unavailableManager, sourcesStore: fixture.store
        )
        let revision = cleanup.completionRevision
        let task = try XCTUnwrap(cleanup.cleanup([redundant]))
        await task.value
        XCTAssertEqual(fixture.library.songs.map(\.id), ["track-0"])
        XCTAssertEqual(fixture.store.source(id: source.id)?.songCount, 1)
        XCTAssertEqual(cleanup.lastCompletedCount, 1)
        XCTAssertTrue(cleanup.lastFailedTitles.isEmpty)
        XCTAssertEqual(cleanup.completionRevision, revision + 1)

        XCTAssertTrue(fixture.start())
        await fixture.scan.waitForActiveScansToComplete()
        XCTAssertNil(fixture.scan.scanStates[source.id]?.failureMessage)
        XCTAssertEqual(fixture.library.songs.map(\.id), ["track-0"])
        XCTAssertEqual(fixture.store.source(id: source.id)?.songCount, 1)
        try await fixture.library.persistNowAndWait().get()

        let reloadedLibrary = MusicLibrary(storageDirectory: root.appendingPathComponent("library"))
        let reloadedStore = SourcesStore(storageDirectoryURL: root.appendingPathComponent("sources"))
        await reloadedLibrary.waitForPendingIndex()
        XCTAssertEqual(reloadedLibrary.songs.map(\.id), ["track-0"])
        XCTAssertEqual(reloadedStore.source(id: source.id)?.songCount, 1)
        XCTAssertTrue(fixture.scan.scanSource(
            source, sourceManager: fixture.manager, library: reloadedLibrary, sourceStore: reloadedStore
        ))
        await fixture.scan.waitForActiveScansToComplete()
        XCTAssertNil(fixture.scan.scanStates[source.id]?.failureMessage)
        XCTAssertEqual(reloadedLibrary.songs.map(\.id), ["track-0"])
        XCTAssertEqual(reloadedStore.source(id: source.id)?.songCount, 1)
        let scanCount = await fixture.connector.scanCount
        XCTAssertEqual(scanCount, 3)
    }

    private struct ScanFixture {
        let source: MusicSource
        let connector: FnMusicScanFixtureConnector
        let scan: ScanService
        let library: MusicLibrary
        let store: SourcesStore
        let manager: SourceManager

        @MainActor func start() -> Bool {
            scan.scanSource(source, sourceManager: manager, library: library, sourceStore: store)
        }

        @MainActor func resume() {
            scan.resumePendingScans(
                sourceManager: manager, library: library, sourceStore: store, scraperService: nil
            )
        }
    }

    private func makeScanFixture(
        count: Int,
        failAfterPage: Bool,
        source: MusicSource? = nil,
        resumeAfter: Date? = nil,
        root: URL? = nil
    ) throws -> ScanFixture {
        let root = root ?? FileManager.default.temporaryDirectory.appendingPathComponent("FnMusicScan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = source ?? MusicSource(id: UUID().uuidString, name: "Scan fixture", type: .fnMusic)
        let connector = FnMusicScanFixtureConnector(sourceID: source.id, count: count, failAfterPage: failAfterPage)
        let library = MusicLibrary(storageDirectory: root.appendingPathComponent("library"))
        let store = SourcesStore(storageDirectoryURL: root.appendingPathComponent("sources"))
        store.add(source)
        if let resumeAfter {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Primuse"), withIntermediateDirectories: true
            )
            var checkpoint = ScanCheckpointPreparationPolicy.preparingCheckpoint(
                existing: nil, directories: ["/"], mode: .automatic,
                scopeFingerprint: ScanService.scopeFingerprint(for: source, directories: ["/"])
            )
            checkpoint.automaticResumeAfter = resumeAfter
            try ScanCheckpointFileStore.writeSnapshot(
                [source.id: checkpoint], to: root.appendingPathComponent("Primuse/scan-checkpoints.json")
            )
        }
        let scan = ScanService(fileManager: FnMusicScanFileManager(root: root), connectorProvider: { _ in connector },
                               diagnosticProvider: { source, _ in
            SourceDiagnosticReport(source: source, startedAt: Date(), checks: [])
        })
        return ScanFixture(source: source, connector: connector, scan: scan, library: library, store: store,
                           manager: SourceManager(sourcesProvider: { [] }))
    }

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

private final class FnMusicScanFileManager: FileManager, @unchecked Sendable {
    let root: URL
    init(root: URL) { self.root = root; super.init() }
    override func urls(for directory: FileManager.SearchPathDirectory,
                       in domainMask: FileManager.SearchPathDomainMask) -> [URL] { [root] }
}

private actor FnMusicScanFixtureConnector: RefreshingMetadataSongConnector {
    let sourceID: String
    let count: Int
    let failAfterPage: Bool
    private(set) var isWaiting = false
    private(set) var scanCount = 0
    private var released = false

    init(sourceID: String, count: Int, failAfterPage: Bool) {
        self.sourceID = sourceID; self.count = count; self.failAfterPage = failAfterPage
    }
    func release() { released = true }
    func connect() async throws {}
    func disconnect() async {}
    func listFiles(at path: String) async throws -> [RemoteFileItem] { [] }
    func localURL(for path: String) async throws -> URL { throw SourceError.fileNotFound(path) }
    func streamData(for path: String) async throws -> AsyncThrowingStream<Data, Error> { .init { $0.finish() } }
    func scanAudioFiles(from path: String) async throws -> AsyncThrowingStream<RemoteFileItem, Error> {
        .init { $0.finish() }
    }
    func scanSongs(from path: String) async throws -> AsyncThrowingStream<ConnectorScannedSong, Error> {
        scanCount += 1
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for index in 0..<count {
                        try Task.checkCancellation()
                        var song = Song(id: "track-\(index)", title: "Track \(index)", fileFormat: .flac,
                                        filePath: "/fnmusic/tracks/\(index).flac", sourceID: sourceID)
                        song.dateAdded = Date(timeIntervalSince1970: 1_000)
                        continuation.yield(ConnectorScannedSong(song: song, displayName: song.title,
                                                               titleMetadataInspected: true))
                    }
                    if failAfterPage {
                        isWaiting = true
                        while !released { try await Task.sleep(for: .milliseconds(10)) }
                        throw SourceError.connectionFailed("Fixture page failed")
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
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

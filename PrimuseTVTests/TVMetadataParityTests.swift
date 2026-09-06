#if os(tvOS)
import Foundation
import PrimuseKit
import XCTest
@testable import PrimuseTV

@MainActor
final class TVMetadataParityTests: XCTestCase {
    private func song() -> Song {
        Song(id: UUID().uuidString, title: "Track", albumTitle: "Album", artistName: "Folder",
             albumArtistName: "Folder", duration: 120, fileFormat: .mp3,
             filePath: "/Music/Track.mp3", sourceID: "source", fileSize: 4096,
             lastModified: Date(timeIntervalSince1970: 100))
    }

    func testEmbeddedArtistReplacesDirectoryAlbumArtistFallback() {
        var metadata = FileMetadataReader.Metadata()
        metadata.artist = "Tagged Artist"
        let updated = TVMetadataEnricher.applying(metadata, to: song(), duration: 180)
        XCTAssertEqual(updated.artistName, "Tagged Artist")
        XCTAssertEqual(updated.albumArtistName, "Tagged Artist")
        metadata.albumArtist = "Compilation Artist"
        XCTAssertEqual(TVMetadataEnricher.applying(metadata, to: song(), duration: 180).albumArtistName,
                       "Compilation Artist")
    }

    func testMetadataRefreshPreservesUserIdentityAndUpdatesTechnicalFields() {
        var original = song()
        original.userMetadataEditedAt = Date()
        var metadata = FileMetadataReader.Metadata()
        metadata.title = "Embedded title"
        metadata.artist = "Embedded artist"
        metadata.albumArtist = "Embedded album artist"
        metadata.sampleRate = 96000
        let updated = TVMetadataEnricher.applying(metadata, to: original, duration: 180)
        XCTAssertEqual(updated.title, original.title)
        XCTAssertEqual(updated.artistName, original.artistName)
        XCTAssertEqual(updated.albumArtistName, original.albumArtistName)
        XCTAssertEqual(updated.sampleRate, 96000)
        XCTAssertEqual(updated.duration, 180)
    }

    func testEmbeddedAuthoredTranslationsReachTVPlayback() throws {
        var metadata = FileMetadataReader.Metadata()
        metadata.lyricsText = "[00:01.00]First line\n[00:03.00]Second line"
        metadata.lyricsLanguageCode = "en"
        metadata.translatedLyricsText = "[00:01.00]第一行\n[00:03.00]第二行"
        metadata.translatedLyricsLanguageCode = "zh-Hans"
        let parsed = try XCTUnwrap(FileMetadataReader.parsedEmbeddedLyrics(from: metadata))
        XCTAssertEqual(parsed.map { $0.manualTranslation?.languageCode }, ["zh-Hans", "zh-Hans"])
        XCTAssertTrue(parsed.first?.metadataLines?.contains("[la:en]") == true)
        let displayed = TVPlaybackCoordinator.toTVLyrics(parsed, duration: 120)
        XCTAssertEqual(displayed.map(\.translation), ["第一行", "第二行"])
        XCTAssertEqual(displayed.map(\.time), [1, 3])
    }

    func testSourceRoutesDoNotReadTranscodedServerFilesAsTags() {
        for type in [MusicSourceType.local, .smb, .nfs, .ftp, .webdav, .oneDrive, .dropbox] {
            XCTAssertTrue(TVPlaybackMetadataPolicy.supports(type), type.rawValue)
        }
        for type in [MusicSourceType.subsonic, .navidrome, .jellyfin, .emby, .plex, .fnMusic, .daoliyu] {
            XCTAssertFalse(TVPlaybackMetadataPolicy.supports(type), type.rawValue)
        }
        XCTAssertEqual(TVLyricsLoadingPolicy.strategy(for: .daoliyu), .daoLiYuService)
        for type in [MusicSourceType.jellyfin, .emby, .plex] {
            XCTAssertEqual(TVLyricsLoadingPolicy.strategy(for: type), .mediaServer)
        }
    }

    func testCompletedAbsencePersistsButFailedOrChangedMetadataMustRetry() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let inspections = TVMetadataInspectionStore(url: url)
        let original = song()
        await inspections.record(original, complete: false)
        let failed = await inspections.isCurrent(original)
        XCTAssertFalse(failed)
        await inspections.record(original, complete: true)
        await inspections.flush()
        let reloaded = TVMetadataInspectionStore(url: url)
        let completed = await reloaded.isCurrent(original)
        XCTAssertTrue(completed, "Missing optional artwork or lyrics is a valid inspected result")
        var changed = original
        changed.lastModified = Date(timeIntervalSince1970: 200)
        let changedBytes = await reloaded.isCurrent(changed)
        XCTAssertFalse(changedBytes)
        changed = original
        changed.artistName = "Snapshot replacement"
        let replaced = await reloaded.isCurrent(changed)
        XCTAssertFalse(replaced)
    }

    func testChangedSidecarInvalidatesInspection() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let inspections = TVMetadataInspectionStore(url: url)
        let original = song()
        func sidecars(_ size: Int64) -> SidecarDirectoryIndex<TVDirEntry> {
            .init([.init(name: "Track.lrc", isDir: false, size: size, path: "/Music/Track.lrc")])
        }
        await inspections.record(original, sidecars: sidecars(100), complete: true)
        let same = await inspections.isCurrent(original, sidecars: sidecars(100))
        let changed = await inspections.isCurrent(original, sidecars: sidecars(200))
        XCTAssertTrue(same)
        XCTAssertFalse(changed)
        await inspections.flush()
    }

    private struct ListedFiles: TVDirectoryLister {
        let entries: [TVDirEntry]
        var usesStableProviderSongIdentity = false
        func list(_ path: String) async throws -> [TVDirEntry] { entries }
    }

    func testRepeatedScanKeepsInspectedAssetReferencesWithoutReopeningSource() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let inspections = TVMetadataInspectionStore(url: url)
        let source = MusicSource(id: UUID().uuidString, name: "Offline NAS", type: .smb)
        let entries: [TVDirEntry] = [
            .init(name: "Track.mp3", isDir: false, size: 4096, path: "/Music/Track.mp3",
                  modifiedDate: Date(timeIntervalSince1970: 100)),
            .init(name: "Track.lrc", isDir: false, size: 100, path: "/Music/Track.lrc"),
            .init(name: "Track.jpg", isDir: false, size: 100, path: "/Music/Track.jpg"),
        ]
        var original = song()
        original.id = TVScanPipelinePolicy.songID(sourceID: source.id, path: original.filePath)
        original.sourceID = source.id
        original.coverArtFileName = "preserved-cover.jpg"
        original.lyricsFileName = "preserved-lyrics.json"
        await inspections.record(original, sidecars: .init(entries), complete: true)
        let scanner = TVSourceScanner(metadataInspections: inspections)
        var songs = [original]
        for _ in 0..<3 {
            let result = await scanner.scan(source: source, lister: ListedFiles(entries: entries),
                dirs: ["/Music"], credential: nil, existingSongs: songs,
                onSkeletonBatch: { _ in }, onMetadataBatch: { _ in })
            XCTAssertTrue(result.enumerationCompleted)
            XCTAssertEqual(result.metadataFailureCount, 0, "An offline source must not be reopened for inspected unchanged files")
            let updated = try XCTUnwrap(result.songs.first)
            XCTAssertEqual(updated.coverArtFileName, original.coverArtFileName)
            XCTAssertEqual(updated.lyricsFileName, original.lyricsFileName)
            songs = result.songs
        }
        await inspections.flush()
    }

    func testUnchangedCloudFileKeepsItsNewPathWhenInspectionIsReused() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let inspections = TVMetadataInspectionStore(url: url)
        let source = MusicSource(id: UUID().uuidString, name: "Cloud", type: .oneDrive)
        var original = song()
        original.sourceID = source.id
        original.id = TVScanPipelinePolicy.songID(sourceID: source.id, path: original.filePath,
                                                 providerID: "stable-file", usesStableProviderIdentity: true)
        await inspections.record(original, sidecars: .init([]), complete: true)
        let entry = TVDirEntry(name: "Renamed.mp3", isDir: false, size: original.fileSize,
                               path: "/Music/Renamed.mp3", providerID: "stable-file", modifiedDate: original.lastModified)
        let scanner = TVSourceScanner(metadataInspections: inspections)
        let result = await scanner.scan(source: source, lister: ListedFiles(entries: [entry], usesStableProviderSongIdentity: true),
            dirs: ["/Music"], credential: nil, existingSongs: [original],
            onSkeletonBatch: { _ in }, onMetadataBatch: { _ in })
        XCTAssertEqual(result.metadataFailureCount, 0)
        XCTAssertEqual(result.songs.first?.id, original.id)
        XCTAssertEqual(result.songs.first?.filePath, entry.path)
        await inspections.flush()
    }

    func testBuiltInArtistLookupRequiresExplicitOptInAndPreservesConfiguredSources() {
        let empty = ScraperSettings(sources: [])
        XCTAssertTrue(ArtworkFetchService.artistLookupSources(settings: empty, allowBuiltInFallback: false).isEmpty)
        XCTAssertEqual(ArtworkFetchService.artistLookupSources(settings: empty, allowBuiltInFallback: true).map(\.type), [.itunes])
        let configured = ScraperSourceConfig(id: "configured", type: .musicBrainz, isEnabled: true, priority: 0)
        let settings = ScraperSettings(sources: [configured])
        XCTAssertEqual(ArtworkFetchService.artistLookupSources(settings: settings, allowBuiltInFallback: true), [configured])
        XCTAssertTrue(empty.sources.isEmpty)
    }

    func testServerArtworkCacheSeparatesCredentialsAndEndpoints() {
        var source = MusicSource(id: "server", name: "Server", type: .navidrome, host: "example.invalid")
        let first = TVSourceAssetReader.cacheIdentity(source: source, credential: .init(password: "first"))
        let second = TVSourceAssetReader.cacheIdentity(source: source, credential: .init(password: "second"))
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(first.contains("first"))
        source.host = "another.invalid"
        XCTAssertNotEqual(first, TVSourceAssetReader.cacheIdentity(source: source, credential: .init(password: "first")))
    }
}
#endif

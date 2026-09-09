import AVFoundation
import Foundation
import MediaPlayer
import MusicKit
import PrimuseKit
import UIKit
import XCTest
@testable import Primuse

final class DeviceMusicPlaybackTests: XCTestCase {
    private struct Manifest: Decodable {
        let files: [Fixture]
    }

    private struct Fixture: Decodable {
        let name: String
        let path: String
        let format: String
        let duration: Double
    }

    @MainActor
    private func fixtureDirectory() throws -> URL {
        #if targetEnvironment(simulator)
        throw XCTSkip("This test requires an explicitly selected physical device.")
        #else
        guard ProcessInfo.processInfo.environment["PRIMUSE_DEVICE_PLAYBACK_QA"] == "1" else {
            throw XCTSkip("Opt-in playback test; requires an external fixture manifest.")
        }
        return try XCTUnwrap(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
            .appendingPathComponent("PlaybackValidation", isDirectory: true)
        #endif
    }

    @MainActor
    private func waitUntil(timeout: Double = 15, _ predicate: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return predicate()
    }

    @MainActor
    private func makePlayer(root: URL, sourceType: MusicSourceType = .local) throws -> AudioPlayerService {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "device-playback-\(UUID().uuidString)"))
        let settings = PlaybackSettingsStore(defaults: defaults)
        settings.prewarmQueueCount = 0
        settings.skipLeadingSilenceEnabled = false
        settings.skipTrailingSilenceEnabled = false
        settings.audioCacheEnabled = false
        let player = AudioPlayerService(
            playbackSettings: settings,
            playbackSessionStore: PlaybackSessionStore(url: root.appendingPathComponent("test-session.json"))
        )
        player.configurePlaybackMetadataBackfill(AppServices.shared.metadataBackfill) { _ in sourceType }
        return player
    }

    @MainActor
    private func writeResults(_ rows: [[String: Any]], name: String, root: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("\(name)-results.json"), options: .atomic)
    }

    @MainActor
    func testCarPlayAppleMusicPlaylistAdvancesWithoutLosingQueue() async throws {
        let root = try fixtureDirectory()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard MusicAuthorization.currentStatus == .authorized else { throw XCTSkip("Apple Music is not authorized.") }
        let services = AppServices.shared
        let library = services.musicLibrary
        let requestedID = ProcessInfo.processInfo.environment["PRIMUSE_CARPLAY_PLAYLIST_ID"]
        func candidate() -> PrimuseKit.Playlist? {
            library.playlists.first { playlist in
                if let requestedID, playlist.id != requestedID { return false }
                let songs = library.songs(forPlaylist: playlist.id).filteredPlayable()
                return songs.count >= 4 && songs.allSatisfy { $0.sourceID == AppleMusicLibraryService.systemSourceID }
            }
        }
        let loaded = await waitUntil(timeout: 30) { candidate() != nil }
        XCTAssertTrue(loaded, "A selected Apple Music playlist with at least four tracks must be available.")
        let playlist = try XCTUnwrap(candidate())
        let songs = library.songs(forPlaylist: playlist.id).filteredPlayable()
        let player = services.playerService
        let repeatMode = player.repeatMode
        let shuffleEnabled = player.shuffleEnabled
        let idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        player.pause()
        player.repeatMode = .off
        player.shuffleEnabled = false
        defer {
            player.pause()
            player.repeatMode = repeatMode
            player.shuffleEnabled = shuffleEnabled
            UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled
        }

        var results: [[String: Any]] = []
        func currentSystemTitle() -> String? { ApplicationMusicPlayer.shared.queue.currentEntry?.title }
        func matches(_ index: Int) -> Bool {
            player.currentSong?.id == songs[index].id && player.currentIndex == index
                && currentSystemTitle() == songs[index].title && player.isPlaying
        }
        let delegate = CarPlaySceneDelegate()
        let item = CarPlayHomeItem(id: playlist.id, title: playlist.name, target: .playlist(playlist.id, directly: true))
        delegate.activateHomeItem(item)
        let started = await waitUntil(timeout: 30) { matches(0) && player.currentTime > 0.5 }
        XCTAssertTrue(started, "CarPlay playlist selection must start its first track: \(player.lastPlaybackError ?? "no progress")")
        XCTAssertEqual(player.queue.map(\.id), songs.map(\.id))
        XCTAssertEqual(ApplicationMusicPlayer.shared.queue.entries.count, songs.count)
        results.append(["step": "playlist-start", "passed": started, "queueCount": player.queue.count,
                        "systemQueueCount": ApplicationMusicPlayer.shared.queue.entries.count,
                        "title": currentSystemTitle() ?? ""])
        try writeResults(results, name: "carplay-queue", root: root)
        guard started else { return }

        // Run the same home action again before the terminal boundary; it must
        // not detach the canonical queue from the active MusicKit request.
        let currentSlot = try XCTUnwrap(player.queueEntries.first?.id)
        let nativeEntry = ApplicationMusicPlayer.shared.queue.currentEntry?.id
        let previousTime = player.currentTime
        delegate.activateHomeItem(item)
        let restarted = await waitUntil(timeout: 30) {
            matches(0) && !player.isLoading && player.currentTime > previousTime + 0.5
                && ApplicationMusicPlayer.shared.queue.entries.count == songs.count
        }
        XCTAssertTrue(restarted)
        XCTAssertEqual(player.queueEntries.first?.id, currentSlot)
        XCTAssertEqual(ApplicationMusicPlayer.shared.queue.currentEntry?.id, nativeEntry)
        guard restarted else { return }
        player.seek(to: max(0, player.duration - 5))
        let advanced = await waitUntil(timeout: 25) { matches(1) && player.currentTime > 0.5 }
        XCTAssertTrue(advanced, "The first song ending must start the second song without a new tap.")
        XCTAssertEqual(player.queue.map(\.id), songs.map(\.id))
        results.append(["step": "natural-end", "passed": advanced, "queueCount": player.queue.count,
                        "index": player.currentIndex, "title": currentSystemTitle() ?? ""])
        try writeResults(results, name: "carplay-queue", root: root)
        guard advanced else { return }

        // Exercise the system path used by CarPlay, independently of the
        // app's own next() handler.
        try await ApplicationMusicPlayer.shared.skipToNextEntry()
        let skipped = await waitUntil(timeout: 30) { matches(2) && player.currentTime > 0.5 }
        XCTAssertTrue(skipped, "Next must select the third playlist entry after automatic advancement.")
        XCTAssertEqual(player.queue.map(\.id), songs.map(\.id))
        results.append(["step": "system-next", "passed": skipped, "queueCount": player.queue.count,
                        "index": player.currentIndex, "title": currentSystemTitle() ?? ""])
        try writeResults(results, name: "carplay-queue", root: root)
        guard skipped else { return }

        player.pause()
        let activeNativeEntry = ApplicationMusicPlayer.shared.queue.currentEntry?.id
        player.insertNextInQueue([songs[0]])
        let insertedID = player.queueEntries[3].id
        let updated = await waitUntil {
            ApplicationMusicPlayer.shared.queue.entries.count == songs.count + 1
        }
        XCTAssertTrue(updated, "Editing a paused queue must update the native successors.")
        XCTAssertEqual(ApplicationMusicPlayer.shared.queue.currentEntry?.id, activeNativeEntry)
        player.resume()
        try await ApplicationMusicPlayer.shared.skipToNextEntry()
        let insertedPlayed = await waitUntil {
            player.currentSong?.id == songs[0].id && player.currentIndex == 3
                && services.appleMusic.nowPlayingQueueEntryID == insertedID && player.isPlaying
        }
        XCTAssertTrue(insertedPlayed, "An inserted duplicate must advance to its own queue occurrence.")
        results.append(["step": "insert-duplicate-while-paused", "passed": updated && insertedPlayed])
        try writeResults(results, name: "carplay-queue", root: root)
        guard insertedPlayed else { return }

        await player.next()
        let appSkipped = await waitUntil(timeout: 30) {
            player.currentIndex == 4 && player.currentSong?.id == songs[3].id && player.isPlaying
        }
        XCTAssertTrue(appSkipped)
        results.append(["step": "app-next", "passed": appSkipped])
        player.clearQueue()
        XCTAssertTrue(player.queue.isEmpty)
        XCTAssertEqual(ApplicationMusicPlayer.shared.queue.entries.count, 1)
        results.append(["step": "clear-native-successors", "passed": player.queue.isEmpty
                        && ApplicationMusicPlayer.shared.queue.entries.count == 1])
        try writeResults(results, name: "carplay-queue", root: root)
        player.pause()
        player.setQueue(songs, startAt: min(3, songs.count - 1))
    }

    @MainActor
    func testLocalAudioFormatMatrix() async throws {
        let root = try fixtureDirectory()
        let idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        AppServices.shared.playerService.pause()
        let player = try makePlayer(root: root)
        defer { player.stop() }
        var results: [[String: Any]] = []
        let selected = ProcessInfo.processInfo.environment["PRIMUSE_DEVICE_PLAYBACK_CASES"]
            .map { Set($0.split(separator: ",").map(String.init)) }

        for fixture in manifest.files where selected == nil || selected!.contains(fixture.name) {
            let url = root.appendingPathComponent(fixture.path)
            let song = PrimuseKit.Song(
                id: "device-qa-\(fixture.name)", title: fixture.name,
                duration: fixture.duration, fileFormat: try XCTUnwrap(AudioFormat(rawValue: fixture.format)),
                filePath: url.path, sourceID: "device-qa-local"
            )
            player.setQueue([song])
            await player.play(song: song, from: url, bypassSystemMediaPlayback: true, shouldRecordPlaybackStart: false)
            let ready = await waitUntil { player.isPlaying && player.audioEngine.isActuallyPlaying || player.lastPlaybackError != nil }
            try await Task.sleep(for: .milliseconds(600))
            let initialTime = player.currentTime
            try await Task.sleep(for: .milliseconds(1500))
            let success = ready && player.currentTime > initialTime + 0.5 && player.isPlaying
                && player.audioEngine.isActuallyPlaying && player.currentSong?.id == song.id
                && player.lastPlaybackError == nil
            var row: [String: Any] = [
                "name": fixture.name, "success": success, "initialTime": initialTime, "time": player.currentTime,
                "engine": player.audioEngine.diagnosticInfo(), "error": player.lastPlaybackError ?? "",
                "queueIndex": player.currentIndex
            ]
            XCTAssertTrue(success, "\(fixture.name): \(row)")
            if success {
                XCTAssertEqual(player.duration, fixture.duration, accuracy: 0.5, "\(fixture.name) duration must reflect the actual media.")
            }

            if success && ["MP3-CBR", "ALAC-24-96", "FLAC-24-192", "DSD64-DSF", "Opus"].contains(fixture.name) {
                player.pause()
                XCTAssertFalse(player.isPlaying)
                player.resume()
                let resumed = await waitUntil { player.isPlaying && player.audioEngine.isActuallyPlaying }
                XCTAssertTrue(resumed, "\(fixture.name) resume")
                player.seek(to: 6, startPlaying: true)
                let sought = await waitUntil { !player.isLoading && player.currentTime >= 6.5 && player.isPlaying }
                XCTAssertTrue(sought, "\(fixture.name) seek: \(player.currentTime)")
                row["pauseResume"] = resumed
                row["seek"] = sought
            }
            player.pause()
            results.append(row)
            try writeResults(results, name: "local-formats", root: root)
        }
        XCTAssertFalse(results.isEmpty)
    }

    @MainActor
    func testCompleteAudioStreams() async throws {
        let root = try fixtureDirectory()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        var results: [[String: Any]] = []
        for fixture in manifest.files {
            let url = root.appendingPathComponent(fixture.path)
            let decoder = await FileFormatRouter.decoder(for: url)
            func countFrames(using decoder: any PrimuseAudioDecoder) async throws -> Int {
                var frames = 0
                for try await buffer in decoder.decode(from: url, outputFormat: format) {
                    XCTAssertEqual(buffer.format, format)
                    frames += Int(buffer.frameLength)
                }
                return frames
            }
            let frames: Int
            var fallback = false
            do {
                frames = try await countFrames(using: decoder)
            } catch {
                guard decoder is NativeAudioDecoder else { throw error }
                fallback = true
                frames = try await countFrames(using: FFmpegAudioDecoder())
            }
            let duration = Double(frames) / format.sampleRate
            XCTAssertEqual(duration, fixture.duration, accuracy: 0.5, fixture.name)
            results.append(["name": fixture.name, "decodedDuration": duration, "fallback": fallback])
            try writeResults(results, name: "complete-streams", root: root)
        }
    }

    @MainActor
    func testMP3RangeInputCanDecodeAndSeek() async throws {
        let root = try fixtureDirectory()
        let bytes = try Data(contentsOf: root.appendingPathComponent("MP3-CBR.mp3"))
        let decoder = NativeAudioDecoder()
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        for start in [0.0, 6.0] {
            let input = CloudInputSourceObjC(url: URL(string: "primuse-cloud://device-qa/music.mp3"), totalLength: Int64(bytes.count)) { offset, length, _ in
                guard offset >= 0, offset < bytes.count else { return Data() }
                let end = min(Int(offset + length), bytes.count)
                return bytes.subdata(in: Int(offset)..<end)
            }
            var frames = 0
            for try await buffer in decoder.decode(from: input, outputFormat: format, startingAt: start) {
                XCTAssertEqual(buffer.format.sampleRate, 48_000)
                XCTAssertGreaterThan(buffer.frameLength, 0)
                frames += Int(buffer.frameLength)
                if frames >= 16_000 { break }
            }
            XCTAssertGreaterThanOrEqual(frames, 16_000, "Range-backed MP3 seek at \(start)")
        }
    }

    @MainActor
    func testUnplayableLocalAssetsAndQueues() async throws {
        let root = try fixtureDirectory()
        let idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled }
        AppServices.shared.playerService.pause()
        let player = try makePlayer(root: root, sourceType: .appleMusicLibrary)
        defer { player.stop() }
        var results: [[String: Any]] = []
        let invalid = ["empty.m4a", "corrupt.m4a", "corrupt.flac", "html.mp3", "managed.movpkg", "missing.m4a"]
        for path in invalid {
            let url = root.appendingPathComponent(path)
            let song = PrimuseKit.Song(
                id: "device-qa-\(path)", title: path, duration: 12,
                fileFormat: AudioFormat.from(fileExtension: url.pathExtension) ?? .m4a,
                filePath: url.path, sourceID: "device-qa-apple-music-local"
            )
            let next = PrimuseKit.Song(id: "should-not-advance", title: "Next", duration: 12,
                                      fileFormat: .m4a, filePath: root.appendingPathComponent("AAC-M4A.m4a").path,
                                      sourceID: song.sourceID)
            player.repeatMode = .all
            player.setQueue([song, next])
            await player.play(song: song, from: url, bypassSystemMediaPlayback: true, shouldRecordPlaybackStart: false)
            let settled = await waitUntil { !player.isPlaying && !player.isLoading && player.lastPlaybackError != nil }
            try await Task.sleep(for: .seconds(1))
            let success = settled && player.currentSong?.id == song.id && player.currentIndex == 0
                && player.lastPlaybackError != nil && !player.isPlaying && !player.isLoading
            XCTAssertTrue(success, "\(path): index=\(player.currentIndex), error=\(player.lastPlaybackError ?? "nil")")
            results.append(["name": path, "success": success, "queueIndex": player.currentIndex,
                            "error": player.lastPlaybackError ?? ""])
            try writeResults(results, name: "invalid-assets", root: root)
        }
        let errorBeforeDelay = player.lastPlaybackError
        try await Task.sleep(for: .seconds(6))
        XCTAssertEqual(player.lastPlaybackError, errorBeforeDelay, "Terminal errors must remain visible.")
        XCTAssertNotNil(errorBeforeDelay)

        for (path, expected) in [("managed.movpkg", AppleMusicLocalAssetError.managedDownload),
                                 ("protected.m4p", .protectedContent), ("missing.m4a", .unavailable),
                                 ("empty.m4a", .invalidFile)] {
            let asset = AppleMusicLocalAsset(url: root.appendingPathComponent(path), isSong: true,
                                            isFileLocation: true, isProtected: false)
            XCTAssertThrowsError(try asset.validatedURL()) { error in
                XCTAssertEqual(error as? AppleMusicLocalAssetError, expected)
                XCTAssertEqual(PlaybackPipelineFailurePolicy.action(requestIsCurrent: true, error: error), .preserveCurrentItem)
            }
        }

        let localPlayer = try makePlayer(root: root)
        defer { localPlayer.stop() }
        let brokenQueue = (0..<3).map { i in
            PrimuseKit.Song(id: "broken-\(i)", title: "Broken \(i)", duration: 12,
                            fileFormat: .m4a, filePath: root.appendingPathComponent("corrupt.m4a").path,
                            sourceID: "device-qa-local")
        }
        for mode in [PrimuseKit.RepeatMode.one, .all] {
            localPlayer.repeatMode = mode
            localPlayer.setQueue(brokenQueue)
            await localPlayer.play(song: brokenQueue[0])
            let settled = await waitUntil(timeout: 25) { !localPlayer.isPlaying && !localPlayer.isLoading && localPlayer.lastPlaybackError != nil }
            let index = localPlayer.currentIndex
            try await Task.sleep(for: .seconds(3))
            XCTAssertTrue(settled)
            XCTAssertEqual(localPlayer.currentIndex, index, "All-failed queue must stop cycling.")
            XCTAssertFalse(localPlayer.isPlaying)
            XCTAssertFalse(localPlayer.isLoading)
            XCTAssertNotNil(localPlayer.lastPlaybackError)
            results.append(["name": "all-broken-\(mode)", "success": settled && localPlayer.currentIndex == index,
                            "queueIndex": index, "error": localPlayer.lastPlaybackError ?? ""])
            try writeResults(results, name: "invalid-assets", root: root)
        }
    }

    @MainActor
    func testAppleMusicPlaybackOnPhysicalDevice() async throws {
        let root = try fixtureDirectory()
        let idleTimerWasDisabled = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
        defer { UIApplication.shared.isIdleTimerDisabled = idleTimerWasDisabled }
        let services = AppServices.shared
        let appleMusic = services.appleMusic
        let player = services.playerService
        let auth = MusicAuthorization.currentStatus
        var results: [[String: Any]] = [["authorization": String(describing: auth),
                                       "syncEnabled": AppleMusicFeatureSettings.syncUserLibraryEnabled]]
        try writeResults(results, name: "apple-music", root: root)
        guard auth == .authorized else { throw XCTSkip("Apple Music access is not authorized on this device.") }
        let subscription = try await MusicSubscription.current
        results.append(["canPlayCatalogContent": subscription.canPlayCatalogContent,
                        "canBecomeSubscriber": subscription.canBecomeSubscriber])
        try writeResults(results, name: "apple-music", root: root)
        guard subscription.canPlayCatalogContent else { throw XCTSkip("This device has no catalog playback entitlement.") }

        var request = MusicLibraryRequest<MusicKit.Song>()
        request.limit = 50
        let response = try await request.response()
        var downloadRequest = MusicLibraryRequest<MusicKit.Song>()
        downloadRequest.limit = 5000
        downloadRequest.includeOnlyDownloadedContent = true
        let downloaded = try await downloadRequest.response()
        let downloadIDs = Set(downloaded.items.map(\.id))
        results.append(["librarySampleCount": response.items.count, "downloadedSampleCount": downloaded.items.count,
                        "downloadedListComplete": downloaded.items.count < downloadRequest.limit])

        var candidates = Array(downloaded.items.prefix(2))
        candidates += response.items.filter { !downloadIDs.contains($0.id) }.prefix(4)
        var catalogIDs = Set<MusicItemID>()
        for term in ["晴天 周杰伦", "Take Five Dave Brubeck", "Beethoven Symphony No. 5", "Billie Jean Michael Jackson"] {
            var search = MusicCatalogSearchRequest(term: term, types: [MusicKit.Song.self])
            search.limit = 3
            let matches = try await search.response()
            if let song = matches.songs.first, !candidates.contains(where: { $0.id == song.id }) {
                candidates.append(song)
                catalogIDs.insert(song.id)
            }
        }
        XCTAssertFalse(candidates.isEmpty, "No authorized library songs available for playback.")

        let originalSessionURL = PlaybackSessionStore().url
        let originalSession = try? Data(contentsOf: originalSessionURL)
        player.pause()
        defer {
            player.pause()
            appleMusic.stopAppleMusic()
            if let originalSession { try? originalSession.write(to: originalSessionURL, options: .atomic) }
        }

        for candidate in candidates {
            appleMusic.stopAppleMusic()
            let item = (try? await candidate.with([.audioVariants])) ?? candidate
            let primuseSong = AppleMusicLibraryService.toPrimuseSong(item)
            let cached = catalogIDs.contains(item.id) ? nil : await services.appleMusicLibrary.musicKitSong(amID: item.id.rawValue)
            let canUseLibraryRoute = !catalogIDs.contains(item.id) && AppleMusicFeatureSettings.syncUserLibraryEnabled && cached != nil
                && !services.musicLibrary.disabledSourceIDs.contains(AppleMusicLibraryService.systemSourceID)
            if canUseLibraryRoute {
                player.setQueue([primuseSong])
                await player.play(song: primuseSong)
            } else {
                await appleMusic.play(item)
            }
            func currentEntrySong() -> MusicKit.Song? {
                if case .song(let song) = ApplicationMusicPlayer.shared.queue.currentEntry?.item { return song }
                return nil
            }
            func identityMatches() -> Bool {
                if let actual = currentEntrySong() {
                    return actual.id == item.id
                        || services.appleMusicLibrary.canonicalForNowPlaying(actual).id == item.id
                        || actual.title == item.title && actual.artistName == item.artistName
                }
                guard let entry = ApplicationMusicPlayer.shared.queue.currentEntry else { return false }
                let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{feff}"))
                return entry.title.trimmingCharacters(in: trim) == item.title.trimmingCharacters(in: trim)
                    && (entry.subtitle?.contains(item.artistName) == true || item.artistName.isEmpty)
            }
            let ready = await waitUntil(timeout: 30) {
                appleMusic.playbackRequestState?.phase == .started
                    && identityMatches() && appleMusic.isAppleMusicPlaying
                    && ApplicationMusicPlayer.shared.state.playbackStatus == .playing
                    && ApplicationMusicPlayer.shared.playbackTime > 0.5
                    || appleMusic.lastPlaybackError != nil
            }
            let initialTime = ApplicationMusicPlayer.shared.playbackTime
            try await Task.sleep(for: .milliseconds(1500))
            let success = ready && identityMatches() && ApplicationMusicPlayer.shared.playbackTime > initialTime + 0.5 && appleMusic.isAppleMusicPlaying
                && ApplicationMusicPlayer.shared.state.playbackStatus == .playing && appleMusic.lastPlaybackError == nil
            XCTAssertTrue(success, "Apple Music \(item.id): \(appleMusic.lastPlaybackError ?? "no progress")")
            var row: [String: Any] = ["id": item.id.rawValue, "title": item.title, "success": success,
                "downloaded": downloadIDs.contains(item.id), "time": appleMusic.currentPlaybackTime,
                "declaredDuration": item.duration ?? 0, "playbackDuration": appleMusic.currentDuration,
                "actualID": currentEntrySong()?.id.rawValue ?? "", "actualTitle": currentEntrySong()?.title ?? "",
                "entryTitle": ApplicationMusicPlayer.shared.queue.currentEntry?.title ?? "",
                "entrySubtitle": ApplicationMusicPlayer.shared.queue.currentEntry?.subtitle ?? "",
                "initialTime": initialTime, "actualTime": ApplicationMusicPlayer.shared.playbackTime,
                "catalogSearchResult": catalogIDs.contains(item.id),
                "variantsAvailable": item.audioVariants?.map { String(describing: $0) } ?? [],
                "route": canUseLibraryRoute ? "primuse-library" : "catalog",
                "error": appleMusic.lastPlaybackError ?? ""]
            if success {
                XCTAssertTrue(appleMusic.pauseAppleMusic())
                let paused = await waitUntil { ApplicationMusicPlayer.shared.state.playbackStatus == .paused }
                XCTAssertTrue(paused)
                XCTAssertTrue(appleMusic.resumeAppleMusic())
                let resumed = await waitUntil { appleMusic.isAppleMusicPlaying && ApplicationMusicPlayer.shared.state.playbackStatus == .playing }
                XCTAssertTrue(resumed)
                let duration = appleMusic.currentDuration > 0 ? appleMusic.currentDuration : (item.duration ?? 60)
                let target = min(20, duration * 0.4)
                appleMusic.seekAppleMusic(to: target)
                let sought = await waitUntil { appleMusic.currentPlaybackTime >= target + 0.5 && appleMusic.isAppleMusicPlaying }
                XCTAssertTrue(sought)
                row["pauseResumeAndSeek"] = sought
            }
            _ = appleMusic.pauseAppleMusic()
            results.append(row)
            try writeResults(results, name: "apple-music", root: root)
        }
    }
}

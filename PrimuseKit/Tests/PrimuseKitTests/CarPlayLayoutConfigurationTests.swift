import Foundation
import Testing
@testable import PrimuseKit

struct CarPlayLayoutConfigurationTests {
    @Test func switchingPresetsPreservesPinnedCollectionsAndRestoresPresentation() {
        var config = CarPlayLayoutConfiguration()
        let folder = LibraryFolderNodeID(sourceID: "nas", kind: .folder, normalizedRelativePath: "/Music/Live")
        config.pinnedPlaylistIDs = ["commute", "favorites"]
        config.folderIDs = [folder]
        config.sectionOrder.reverse()
        config.opensNowPlayingAfterSelection = false

        config.apply(.focus)
        #expect(config.visibleSections == [.shortcuts])
        #expect(config.opensNowPlayingOnConnect)
        #expect(config.opensNowPlayingAfterSelection)
        #expect(config.minimalNowPlaying)
        #expect(config.pinnedPlaylistIDs == ["commute", "favorites"])
        #expect(config.folderIDs == [folder])
        #expect(config.matchingPreset == .focus)

        config.apply(.artwork)
        #expect(config.browseStyle == .cards)
        #expect(!config.playsCollectionsDirectly)
        #expect(!config.opensNowPlayingOnConnect)
        #expect(!config.minimalNowPlaying)
        config.browseStyle = .covers
        #expect(config.matchingPreset == nil)
    }

    @Test func decodingFutureOptionsKeepsKnownOrderAndUnavailablePins() throws {
        let data = Data(#"{"browseStyle":"future","sectionOrder":["albums","future","albums","shortcuts"],"hiddenSections":["future","playlists"],"pinnedPlaylistIDs":["offline","offline","active"],"opensNowPlayingAfterSelection":false}"#.utf8)
        let config = try JSONDecoder().decode(CarPlayLayoutConfiguration.self, from: data)
        #expect(config.browseStyle == .list)
        #expect(config.visibleSections == [.albums, .shortcuts, .recentlyAdded])
        #expect(config.pinnedPlaylistIDs == ["offline", "active"])
        #expect(!config.opensNowPlayingAfterSelection)
    }

    @Test func persistenceRoundTripAndCorruptionFallback() throws {
        let suite = "CarPlayLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var config = CarPlayLayoutConfiguration()
        config.apply(.artwork)
        config.sectionOrder = [.recentlyAdded, .shortcuts, .albums, .playlists]
        config.hiddenSections = []
        config.save(to: defaults)
        #expect(CarPlayLayoutConfiguration.load(from: defaults) == config)
        defaults.set(Data("broken".utf8), forKey: CarPlayLayoutConfiguration.storageKey)
        #expect(CarPlayLayoutConfiguration.load(from: defaults) == CarPlayLayoutConfiguration())
    }

    @Test func hiddenSectionsStayHiddenAndShortcutLimitCountsFolders() {
        var config = CarPlayLayoutConfiguration()
        config.hiddenSections = Set(CarPlayHomeSection.allCases)
        #expect(config.visibleSections.isEmpty)
        config.pinnedPlaylistIDs = (0..<11).map(String.init)
        #expect(config.canAddShortcut)
        config.folderIDs = [.init(sourceID: "drive", kind: .folder, normalizedRelativePath: "opaque-id")]
        #expect(!config.canAddShortcut)
    }
}

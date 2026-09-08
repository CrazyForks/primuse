#if os(iOS)
import PrimuseKit
import SwiftUI
import XCTest
@testable import Primuse

@MainActor
final class CarPlayEditorRenderingTests: XCTestCase {
    func testCanvasRendersMixedLayoutsAndFocusedPlayback() async throws {
        var cards = CarPlayLayoutBlock(id: "cards", kind: .custom, style: .cards)
        cards.title = "出发就听"
        cards.columns = 3
        var list = CarPlayLayoutBlock(id: "list", kind: .recentlyAdded, style: .list)
        list.title = "最近加入"
        let items = [
            CarPlayHomeItem(id: "1", title: "公路音乐", subtitle: "36 首歌曲", symbol: "music.note.list", target: .unavailable),
            CarPlayHomeItem(id: "2", title: "周末现场 · 长标题换行", subtitle: "音乐 / 演唱会", symbol: "folder.fill", target: .unavailable),
            CarPlayHomeItem(id: "3", title: "夜间电台", subtitle: "Ambient Radio", symbol: "radio", target: .unavailable)
        ]
        let blocks = [CarPlayHomeBlock(configuration: cards, items: items),
                      CarPlayHomeBlock(configuration: list, items: Array(items.prefix(2)))]
        var config = CarPlayLayoutConfiguration()
        config.blocks = [cards, list]
        let canvas = CarPlayEditorCanvas(blocks: blocks, configuration: config, selectedID: "cards", editing: true,
                                         playerPage: false, wide: false, previewItem: nil,
                                         select: { _ in }, activate: { _ in }, drop: { _, _, _ in false }, addContent: { _ in })
        try await render(canvas, size: CGSize(width: 1000, height: 600), name: "CarPlay-canvas-edit")
        let preview = CarPlayEditorCanvas(blocks: blocks, configuration: config, selectedID: nil, editing: false,
                                          playerPage: false, wide: true, previewItem: nil,
                                          select: { _ in }, activate: { _ in }, drop: { _, _, _ in false }, addContent: { _ in })
        try await render(preview, size: CGSize(width: 1120, height: 480), name: "CarPlay-canvas-wide")
        config.minimalNowPlaying = true
        let player = CarPlayEditorCanvas(blocks: [], configuration: config, selectedID: nil, editing: false,
                                         playerPage: true, wide: false, previewItem: items[1],
                                         select: { _ in }, activate: { _ in }, drop: { _, _, _ in false }, addContent: { _ in })
        try await render(player, size: CGSize(width: 800, height: 480), name: "CarPlay-focused-player")
    }

    func testEditorRendersAtPhoneAndTabletWidthsWithoutChangingPreferences() async throws {
        let suite = "CarPlayRenderTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CarPlaySettingsStore(defaults: defaults)
        let original = settings.configuration
        try await render(CarPlaySettingsView(settings: settings), size: CGSize(width: 390, height: 844), name: "CarPlay-editor-phone")
        try await render(CarPlaySettingsView(settings: settings), size: CGSize(width: 1194, height: 834), name: "CarPlay-editor-tablet")
        try await render(CarPlaySettingsView(settings: settings, showsLibrary: true), size: CGSize(width: 390, height: 844), name: "CarPlay-style-library")
        let model = CarPlayEditorModel(settings: settings)
        model.select(try XCTUnwrap(model.configuration.blocks.first?.id))
        try await render(CarPlaySettingsView(settings: settings, model: model), size: CGSize(width: 390, height: 844), name: "CarPlay-module-inspector")
        try await render(CarPlayModulePicker(model: model, close: {}), size: CGSize(width: 390, height: 660), name: "CarPlay-add-module")
        XCTAssertEqual(settings.configuration, original)
    }

    func testContinuousEditingUndoReorderVisibilityAndPersistence() throws {
        let suite = "CarPlayInteractionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = CarPlaySettingsStore(defaults: defaults)
        let model = CarPlayEditorModel(settings: settings)
        let original = model.configuration
        let id = try XCTUnwrap(original.blocks.first?.id)
        model.select(id)
        XCTAssertTrue(model.inspectorVisible)
        model.continuousChange(true)
        for limit in 1...60 { model.update(id) { $0.itemLimit = limit } }
        model.continuousChange(false)
        XCTAssertEqual(model.selected?.itemLimit, 60)
        model.undo()
        XCTAssertEqual(model.configuration, original, "A slider gesture must undo in one step")
        model.redo()
        XCTAssertEqual(model.selected?.itemLimit, 60)
        model.update(id) { $0.isVisible = false }
        model.move(id, before: nil)
        XCTAssertEqual(model.configuration.blocks.last?.id, id)
        XCTAssertFalse(try XCTUnwrap(model.configuration.blocks.last).isVisible)
        let snapshot = model.configuration
        XCTAssertFalse(model.drop(["carplay-block:deleted"], before: id))
        XCTAssertEqual(model.configuration, snapshot)
        model.flush()
        let restored = CarPlaySettingsStore(defaults: defaults)
        XCTAssertEqual(restored.configuration, model.configuration)
        model.undo()
        XCTAssertEqual(model.configuration.blocks.first?.id, id)
    }

    func testLargeLibraryProjectionIsReusedAcrossCanvasEdits() async throws {
        let suite = "CarPlayPerformanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CarPlayEditorModel(settings: CarPlaySettingsStore(defaults: defaults))
        let songs = (0..<20_000).map { index in
            Song(id: "s\(index)", title: "Track \(index)", artistName: "Artist", fileFormat: .flac, filePath: "/\(index).flac", sourceID: "test")
        }
        let catalog = CarPlayEditorCatalog()
        catalog.load(.init(songs: songs, albums: [], playlists: [], memberships: [:], stations: [], artistNames: .defaultValue))
        await catalog.waitForLoad()
        XCTAssertEqual(catalog.snapshot.searchItems[.song]?.count, 20_000)
        let projectionCount = catalog.projectionCount
        let id = try XCTUnwrap(model.configuration.blocks.first?.id)
        let start = ContinuousClock.now
        for index in 0..<200 {
            model.select(id)
            model.update(id) { $0.itemLimit = index % 60 + 1; $0.columns = index % 5 + 2 }
            let blocks = catalog.snapshot.blocks(for: model.configuration)
            XCTAssertLessThanOrEqual(blocks.flatMap(\.items).count, 180)
        }
        let duration = start.duration(to: .now)
        XCTAssertEqual(catalog.projectionCount, projectionCount, "Editing must not rebuild the source catalog")
        XCTAssertEqual(projectionCount, 1)
        model.flush()
        let attachment = XCTAttachment(string: "20,000 songs; 200 edits; source projections=\(projectionCount); edit duration=\(duration)")
        attachment.name = "CarPlay-editor-projection-performance"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLatestCatalogWinsAndUnavailableContentKeepsItsIdentity() async {
        let catalog = CarPlayEditorCatalog()
        let first = Song(id: "same", title: "Old", fileFormat: .mp3, filePath: "/one.mp3", sourceID: "test")
        var updated = first
        updated.title = "Renamed"
        catalog.load(.init(songs: [first], albums: [], playlists: [], memberships: [:], stations: [], artistNames: .defaultValue))
        catalog.load(.init(songs: [updated], albums: [], playlists: [], memberships: [:], stations: [], artistNames: .defaultValue))
        await catalog.waitForLoad()
        XCTAssertEqual(catalog.snapshot.searchItems[.song]?.first?.title, "Renamed")
        XCTAssertEqual(catalog.projectionCount, 1)
        let saved = CarPlayLayoutItem(id: "pinned", kind: .song, targetID: "missing", title: "Keep me")
        let resolved = catalog.snapshot.resolve(saved, directly: true)
        XCTAssertEqual(resolved.id, saved.id)
        XCTAssertEqual(resolved.title, saved.title)
        XCTAssertFalse(resolved.enabled)
    }

    func testCustomNowPlayingContentKeepsIdentityAndCanBeRemoved() throws {
        let suite = "CarPlayContentTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CarPlayEditorModel(settings: CarPlaySettingsStore(defaults: defaults))
        model.add(.custom)
        let blockID = try XCTUnwrap(model.selectedID)
        let item = CarPlayLayoutItem(kind: .nowPlaying, targetID: "nowPlaying", title: "正在播放")
        XCTAssertTrue(model.addContent(item, to: blockID, resolved: []))
        let savedID = try XCTUnwrap(model.selected?.items.first?.id)
        let catalog = CarPlayEditorCatalog.Snapshot()
        let playing = CarPlayHomeItem(id: "nowPlaying", title: "正在播放", subtitle: "Track", target: .nowPlaying)
        let resolved = try XCTUnwrap(catalog.blocks(for: model.configuration, nowPlaying: playing).first { $0.id == blockID })
        let content = try XCTUnwrap(resolved.items.first)
        XCTAssertEqual(content.id, savedID)
        XCTAssertEqual(content.subtitle, "Track")
        XCTAssertFalse(model.addContent(item, to: blockID, resolved: resolved.items))
        model.removeContent(content, from: blockID, resolved: resolved.items)
        XCTAssertTrue(try XCTUnwrap(model.selected).items.isEmpty)
        model.undo()
        XCTAssertEqual(model.selected?.items.first?.id, savedID)
        let stopped = try XCTUnwrap(catalog.blocks(for: model.configuration).first { $0.id == blockID }?.items.first)
        XCTAssertEqual(stopped.id, savedID)
        XCTAssertFalse(stopped.enabled)
    }

    private func render(_ view: some View, size: CGSize, name: String,
                        interact: ((UIView) async throws -> Void)? = nil) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "zh-Hans")))
        host.safeAreaRegions = []
        window.rootViewController = host
        window.frame = CGRect(origin: .zero, size: size)
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        try await interact?(host.view)
        host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            host.view.layer.render(in: context.cgContext)
        }
        XCTAssertEqual(image.size, size)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif

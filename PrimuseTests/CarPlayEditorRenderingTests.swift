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
        XCTAssertEqual(settings.configuration, original)
    }

    private func render(_ view: some View, size: CGSize, name: String) async throws {
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

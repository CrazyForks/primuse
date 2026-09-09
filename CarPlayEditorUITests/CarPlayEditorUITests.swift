import XCTest

@MainActor
final class CarPlayEditorUITests: XCTestCase {
    func testMainMenuAndCompactActionsPreview() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.welape.yuanyin")
        app.launchEnvironment["PRIMUSE_CARPLAY_UI_TESTS"] = "1"
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["carplay.addTab"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["carplay.previewMode"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["主菜单"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["正在播放"].exists)
        XCTAssertTrue(app.segmentedControls["carplay.presets"].isHittable)
        XCTAssertLessThan(app.segmentedControls["carplay.presets"].frame.maxY, app.otherElements["carplay.canvas"].firstMatch.frame.minY)
        XCTAssertFalse(app.buttons["carplay.previousStyle"].exists)
        XCTAssertFalse(app.buttons["carplay.nextStyle"].exists)
        XCTAssertFalse(app.buttons["分栏式"].exists)
        app.buttons["carplay.previewTab.tab.home"].tap()
        app.buttons["carplay.addModule"].tap()
        app.buttons["carplay.add.siri"].tap()
        app.buttons["完成"].firstMatch.tap()
        app.buttons["carplay.back"].tap()
        app.buttons["carplay.tabVisibility.tab.radio"].tap()
        app.buttons["carplay.addTab"].tap()
        app.buttons["歌曲"].firstMatch.tap()
        let songRow = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'carplay.menuRow.' AND label CONTAINS '歌曲'")).firstMatch
        if !songRow.exists { app.swipeUp() }
        let songButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'carplay.editTab.' AND label == %@", "歌曲"))
        let songID = String(songButtons.firstMatch.identifier.dropFirst("carplay.editTab.".count))
        app.buttons["carplay.renameTab." + songID].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        let field = alert.textFields.firstMatch
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "全部音乐")
        alert.buttons["保存"].tap()
        attach(app, "CarPlay-main-menu-device")
        XCTAssertTrue(app.buttons["carplay.previewSearch"].exists)
        app.buttons["carplay.previewSiri"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["carplay.previewAssistantRow"].firstMatch.waitForExistence(timeout: 3))
        attach(app, "CarPlay-siri-entry-device")
        app.terminate()
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = nil
        app.launch()
        XCTAssertTrue(app.buttons["全部音乐"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["carplay.previewTab.tab.radio"].exists)
        app.buttons["carplay.previewTab.tab.playlists"].tap()
        app.segmentedControls["carplay.presets"].buttons["胶囊式"].tap()
        XCTAssertTrue(app.buttons["carplay.previewTab.tab.playlists"].isHittable)
        XCTAssertTrue(app.buttons["carplay.previewSearch"].isHittable)
        XCTAssertTrue(app.buttons["carplay.previewSiri"].isHittable)
        attach(app, "CarPlay-capsules-menu-device")
        let expand = app.buttons["carplay.expand"]
        let canvas = app.otherElements["carplay.canvas"].firstMatch
        XCTAssertLessThan(abs(expand.frame.midY - canvas.frame.minY), 24)
        expand.tap()
        XCTAssertTrue(app.buttons["carplay.closePreview"].waitForExistence(timeout: 3))
        assertHidden(expand)
        attach(app, "CarPlay-fullscreen-preview-device")
        let visibleHome = app.buttons.matching(identifier: "carplay.previewTab.tab.home").allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visibleHome.count, 1)
        visibleHome.first?.tap()
        app.buttons["carplay.closePreview"].tap()
        XCTAssertTrue(app.buttons["carplay.addModule"].waitForExistence(timeout: 3))
        app.buttons["carplay.actions"].tap()
        app.buttons["carplay.playbackSettings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["carplay.playbackOptions"].firstMatch.waitForExistence(timeout: 3))
        assertHidden(app.buttons["carplay.previewSiri"])
        attach(app, "CarPlay-playback-settings-device")
        app.buttons["完成"].firstMatch.tap()
    }

    func testEditingDraggingPresetComparisonAndSavedLayout() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.welape.yuanyin")
        app.launchEnvironment["PRIMUSE_CARPLAY_UI_TESTS"] = "1"
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["carplay.previewTab.tab.home"].waitForExistence(timeout: 15))
        app.buttons["carplay.previewTab.tab.home"].tap()
        let shortcut = app.buttons["carplay.module.legacy.shortcuts"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 15))
        attach(app, "CarPlay-editor-device")
        shortcut.tap()
        let grid = app.buttons["carplay.layout.3"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3))
        grid.tap()
        let slider = app.sliders["carplay.itemLimit"]
        XCTAssertTrue(slider.exists)
        slider.adjust(toNormalizedSliderPosition: 0.75)
        attach(app, "CarPlay-inspector-device")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(shortcut.label.contains("3×3"), shortcut.label)
        app.buttons["carplay.actions"].tap()
        app.buttons["carplay.undo"].tap()
        XCTAssertTrue(shortcut.label.contains("24"), shortcut.label)
        app.buttons["carplay.actions"].tap()
        app.buttons["carplay.redo"].tap()
        app.buttons["carplay.visibility.legacy.shortcuts"].tap()
        XCTAssertTrue(shortcut.label.contains("已隐藏"), shortcut.label)
        app.buttons["carplay.visibility.legacy.shortcuts"].tap()

        let drag = app.descendants(matching: .any)["carplay.drag.legacy.recentlyAdded"].firstMatch
        let recent = app.buttons["carplay.module.legacy.recentlyAdded"]
        XCTAssertTrue(drag.exists)
        drag.press(forDuration: 0.8, thenDragTo: shortcut)
        let moved = NSPredicate { _, _ in recent.frame.minY < shortcut.frame.minY }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 4)
        attach(app, "CarPlay-modules-reordered-device")

        app.buttons["carplay.styles"].tap()
        let wall = app.buttons["carplay.preset.wall"]
        XCTAssertTrue(wall.waitForExistence(timeout: 3))
        wall.tap()
        attach(app, "CarPlay-style-library-device")
        wall.tap()
        XCTAssertTrue(app.segmentedControls["carplay.presets"].buttons["卡墙式"].exists)
        app.buttons["carplay.addModule"].tap()
        XCTAssertTrue(app.buttons["carplay.add.custom"].waitForExistence(timeout: 3))
        app.buttons["carplay.add.custom"].tap()
        app.buttons["完成"].firstMatch.tap()
        let custom = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'carplay.module.' AND label BEGINSWITH '封面墙'")).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        custom.tap()
        app.buttons["添加"].firstMatch.tap()
        let kinds = app.scrollViews["carplay.contentKinds"]
        XCTAssertTrue(kinds.waitForExistence(timeout: 3))
        kinds.swipeLeft()
        app.buttons["正在播放"].firstMatch.tap()
        let search = app.textFields["carplay.contentSearch"]
        search.tap()
        search.typeText("正在播放")
        XCTAssertTrue(app.buttons["添加内容"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["添加内容"].firstMatch.tap()
        app.buttons["完成"].firstMatch.tap()
        attach(app, "CarPlay-custom-content-device")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["carplay.actions"].tap()
        app.buttons["存为预设"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.textFields.firstMatch.tap()
        alert.textFields.firstMatch.typeText("通勤布局")
        alert.buttons["保存"].tap()
        app.terminate()
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = nil
        app.launch()
        XCTAssertTrue(app.buttons["carplay.styles"].waitForExistence(timeout: 10))
        app.buttons["carplay.styles"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["通勤布局"].waitForExistence(timeout: 3))
    }

    private func assertHidden(_ element: XCUIElement) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !element.isHittable }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 3), .completed)
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

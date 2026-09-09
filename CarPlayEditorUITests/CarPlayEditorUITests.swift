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
        XCTAssertFalse(app.segmentedControls["carplay.presets"].exists)
        app.buttons["carplay.actions"].tap()
        XCTAssertTrue(app.buttons["carplay.style.list"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["carplay.style.wall"].exists)
        XCTAssertTrue(app.buttons["carplay.style.capsules"].exists)
        XCTAssertTrue(app.buttons["carplay.styles"].exists)
        XCTAssertFalse(app.buttons["carplay.undo"].exists)
        XCTAssertFalse(app.buttons["carplay.redo"].exists)
        app.buttons["carplay.style.list"].tap()
        XCTAssertFalse(app.buttons["carplay.previousStyle"].exists)
        XCTAssertFalse(app.buttons["carplay.nextStyle"].exists)
        XCTAssertFalse(app.buttons["分栏式"].exists)
        let radio = app.buttons["carplay.editTab.tab.radio"]
        let library = app.buttons["carplay.editTab.tab.library"]
        dragBefore(app.descendants(matching: .any)["carplay.dragTab.tab.radio"].firstMatch, library)
        let tabMoved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            radio.frame.minY < library.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [tabMoved], timeout: 4), .completed)
        app.buttons["carplay.previewTab.tab.home"].tap()
        app.buttons["carplay.addModule"].tap()
        let moduleSearch = app.searchFields["搜索模块"]
        XCTAssertTrue(moduleSearch.waitForExistence(timeout: 3))
        moduleSearch.tap()
        moduleSearch.typeText("Siri")
        XCTAssertTrue(app.buttons["carplay.add.siri"].waitForExistence(timeout: 3))
        app.buttons["carplay.add.siri"].tap()
        app.navigationBars["添加模块"].buttons["关闭"].tap()
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
        app.buttons["carplay.actions"].tap()
        app.buttons["carplay.style.capsules"].tap()
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
        app.buttons["carplay.undoButton"].tap()
        XCTAssertTrue(shortcut.label.contains("24"), shortcut.label)
        app.buttons["carplay.redoButton"].tap()
        app.buttons["carplay.visibility.legacy.shortcuts"].tap()
        XCTAssertTrue(shortcut.label.contains("已隐藏"), shortcut.label)
        app.buttons["carplay.visibility.legacy.shortcuts"].tap()

        let drag = app.descendants(matching: .any)["carplay.drag.legacy.recentlyAdded"].firstMatch
        let recent = app.buttons["carplay.module.legacy.recentlyAdded"]
        XCTAssertTrue(drag.exists)
        dragBefore(drag, shortcut)
        let moved = NSPredicate { _, _ in recent.frame.minY < shortcut.frame.minY }
        expectation(for: moved, evaluatedWith: nil)
        waitForExpectations(timeout: 4)
        attach(app, "CarPlay-modules-reordered-device")

        app.buttons["carplay.actions"].tap()
        app.buttons["carplay.styles"].tap()
        let wall = app.buttons["carplay.preset.wall"]
        XCTAssertTrue(wall.waitForExistence(timeout: 3))
        wall.tap()
        attach(app, "CarPlay-style-library-device")
        wall.tap()
        app.buttons["carplay.actions"].tap()
        XCTAssertTrue(app.buttons["carplay.style.wall"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["carplay.style.wall"].label.contains("卡墙式"), app.buttons["carplay.style.wall"].label)
        app.buttons["carplay.style.wall"].tap()
        app.buttons["carplay.addModule"].tap()
        XCTAssertTrue(app.buttons["carplay.add.custom"].waitForExistence(timeout: 3))
        app.buttons["carplay.add.custom"].tap()
        app.buttons["完成"].firstMatch.tap()
        let custom = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'carplay.module.' AND label BEGINSWITH '封面墙'")).firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        custom.tap()
        let addContent = app.buttons["carplay.addContent"]
        reveal(addContent, in: app.collectionViews["carplay.inspector"])
        addContent.tap()
        let kinds = app.scrollViews["carplay.contentKinds"]
        XCTAssertTrue(kinds.waitForExistence(timeout: 3))
        kinds.swipeLeft()
        kinds.buttons["正在播放"].tap()
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
        XCTAssertTrue(app.buttons["carplay.actions"].waitForExistence(timeout: 10))
        app.buttons["carplay.actions"].tap()
        app.buttons["carplay.styles"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["通勤布局"].waitForExistence(timeout: 3))
    }

    func testContentSourceReorderingPreservesItemsAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.welape.yuanyin")
        app.launchEnvironment["PRIMUSE_CARPLAY_UI_TESTS"] = "1"
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = "1"
        app.launchEnvironment["PRIMUSE_CARPLAY_SOURCE_REORDER"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let inspector = app.descendants(matching: .any)["carplay.inspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 15))
        let first = app.descendants(matching: .any)["carplay.source.source.1"].firstMatch
        let last = app.descendants(matching: .any)["carplay.source.source.3"].firstMatch
        reveal(last, in: inspector)
        XCTAssertTrue(first.isHittable)
        XCTAssertTrue(last.isHittable)
        dragBefore(app.descendants(matching: .any)["carplay.dragSource.source.3"].firstMatch, first)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            last.exists && first.exists && last.frame.minY < first.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [moved], timeout: 4), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["carplay.source.source.2"].firstMatch.exists)
        attach(app, "CarPlay-sources-reordered-device")
        app.buttons["完成"].firstMatch.tap()
        app.terminate()
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = nil
        app.launch()
        XCTAssertTrue(inspector.waitForExistence(timeout: 15))
        reveal(first, in: inspector)
        XCTAssertLessThan(last.frame.minY, first.frame.minY)
        reveal(app.descendants(matching: .any)["carplay.source.source.2"].firstMatch, in: inspector)
        let slider = app.sliders["carplay.itemLimit"]
        for _ in 0..<4 {
            if slider.exists && slider.isHittable { break }
            inspector.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(slider.isHittable)
        slider.adjust(toNormalizedSliderPosition: 0.15)
        reveal(app.descendants(matching: .any)["carplay.source.source.4"].firstMatch, in: inspector)
    }

    private func reveal(_ element: XCUIElement, in scrollView: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)), withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func dragBefore(_ handle: XCUIElement, _ row: XCUIElement) {
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)), withVelocity: .slow, thenHoldForDuration: 0.6)
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

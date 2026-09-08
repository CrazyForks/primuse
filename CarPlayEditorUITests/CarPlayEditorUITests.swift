import XCTest

@MainActor
final class CarPlayEditorUITests: XCTestCase {
    func testEditingDraggingPresetComparisonAndSavedLayout() {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: "com.welape.yuanyin")
        app.launchEnvironment["PRIMUSE_CARPLAY_UI_TESTS"] = "1"
        app.launchEnvironment["PRIMUSE_CARPLAY_RESET"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
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
        app.buttons["carplay.undo"].tap()
        XCTAssertTrue(shortcut.label.contains("24"), shortcut.label)
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
        XCTAssertTrue(app.buttons["carplay.style.wall"].exists)
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
        app.scrollViews["carplay.presets"].swipeLeft()
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

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

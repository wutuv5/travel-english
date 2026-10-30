import XCTest

final class TranslationInteractionTests: XCTestCase {
    func testKeyboardDismissalAndTranslationWithoutInstalledResources() {
        let app = XCUIApplication()
        app.launch()
        let editor = app.textViews["translation.input"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        editor.tap()
        editor.typeText("Hello")
        let done = app.buttons["translation.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        let keyboardHidden = NSPredicate(format: "count == 0")
        expectation(for: keyboardHidden, evaluatedWith: app.keyboards)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["translation.submit"].isEnabled,
                      "Valid input must not be gated by downloaded resources")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "translation-screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPrepareResourcesOpensVisibleOperation() {
        let app = XCUIApplication()
        app.launch()
        let prepare = app.buttons["translation.prepareResources"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 10))
        prepare.tap()
        let close = app.buttons["translation.closeOperation"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(prepare.waitForExistence(timeout: 5))
    }
}

import XCTest

@MainActor
final class FocusRoutingUITests: XCTestCase {
    func testNestedScopeRoutesOnlyOnce() {
        let app = XCUIApplication()
        app.launchArguments = ["--focus-demo", "--focus-probe", "--nested-focus-scope"]
        app.launch()
        expectFocus(app.buttons["anchor-1"])
        XCUIRemote.shared.press(.right)
        expectFocus(app.buttons["anchor-2"])
        XCUIRemote.shared.press(.down)
        expectFocus(app.buttons["row0-item0"])
        expectEvents(app, ["row0-item0"])
        XCUIRemote.shared.press(.up)
        expectFocus(app.buttons["anchor-1"])
    }

    func testRemoteEntryCommitsOnlyTheIntendedItem() {
        let app = XCUIApplication()
        app.launchArguments = ["--focus-demo", "--focus-probe"]
        app.launch()
        let remote = XCUIRemote.shared
        expectFocus(app.buttons["anchor-1"])
        remote.press(.right)
        expectFocus(app.buttons["anchor-2"])
        remote.press(.down)
        expectFocus(app.buttons["row0-item0"])
        expectEvents(app, ["row0-item0"])
        remote.press(.right)
        expectFocus(app.buttons["row0-item1"])
        remote.press(.down)
        expectFocus(app.buttons["row1-item1"])
        remote.press(.down)
        expectFocus(app.buttons["row2-item0"])
        remote.press(.right)
        expectFocus(app.buttons["row2-item1"])
        remote.press(.up)
        expectFocus(app.buttons["row1-item1"])
        remote.press(.right)
        expectFocus(app.buttons["row1-item2"])
        remote.press(.down)
        expectFocus(app.buttons["row2-item0"])
        remote.press(.up)
        expectFocus(app.buttons["row1-item2"])
        remote.press(.up)
        expectFocus(app.buttons["row0-item1"])
        expectEvents(
            app,
            [
                "row0-item0",
                "row0-item1",
                "row1-item1",
                "row2-item0",
                "row2-item1",
                "row1-item1",
                "row1-item2",
                "row2-item0",
                "row1-item2",
                "row0-item1",
            ]
        )
        remote.press(.select)
        XCTAssertEqual(app.staticTexts["selection-status"].label, "Leading first · Remember on return: item 2")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func expectFocus(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func expectEvents(_ app: XCUIApplication, _ events: [String], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.staticTexts["focus-events"].value as? String, events.joined(separator: ","), file: file, line: line)
    }
}

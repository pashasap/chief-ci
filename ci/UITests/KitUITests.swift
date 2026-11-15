import XCTest

/// Kit (Chief) simulator proof. The app has no accessibility identifiers, so everything is found by the
/// visible label. Every PNG goes straight to the host disk (/tmp/kitshots) the moment it is taken.
/// Each step runs in its own XCTContext activity and never asserts, so one miss cannot end the run.
final class KitUITests: XCTestCase {
    static let link = "chief://pair?base=https%3A%2F%2Flocalhost%3A8443&token=kit-sim-invented-token-0001"
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws { continueAfterFailure = true }

    @MainActor
    func testScreens() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        step("01 launch unpaired") {
            app.launch()
            let up = app.buttons["Inbox"].waitForExistence(timeout: 60)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("01-unpaired-inbox")
            tab(app, "Settings")
            shot("02-unpaired-settings")
        }

        step("02 pair by pasting the link in Settings") {
            tab(app, "Settings")
            let field = pairingField(app)
            note("pairing field exists=\(field.exists) type=\(field.elementType.rawValue)")
            if field.exists {
                field.tap(); usleep(500_000)
                field.typeText(Self.link)
                shot("03-link-typed")
                let pair = app.buttons["Pair with this link"]
                if pair.exists { pair.tap() } else { app.buttons["Pair"].firstMatch.tap() }
            }
            var paired = waitText(app, "Paired", exact: true, timeout: 20)
            note("paired after paste=\(paired) message=\(messages(app))")
            if !paired {
                request("openurl")
                for name in ["Open", "Öffnen"] where springboard.buttons[name].waitForExistence(timeout: 5) {
                    shot("03b-openurl-confirmation"); springboard.buttons[name].tap(); break
                }
                paired = waitText(app, "Paired", exact: true, timeout: 20)
                note("paired after openurl=\(paired)")
            }
            dismissKeyboard(app)
            shot("04-settings-paired")
        }

        step("03 inbox with data") {
            tab(app, "Inbox")
            let data = waitText(app, "letting agent", timeout: 30)
            note("inbox shows fixture proposal=\(data)")
            sleep(1)
            shot("05-inbox-top")
            app.swipeUp(); sleep(1); shot("06-inbox-scrolled-1")
            app.swipeUp(); sleep(1); shot("07-inbox-scrolled-2")
            app.swipeUp(); sleep(1); shot("08-inbox-scrolled-3")
            dump(app, "inbox")
        }

        step("04 open a capture and one filed item") {
            let row = element(app, "Pick up the dry cleaning today")
            if scrollTo(app, row) {
                row.tap()
                note("capture sheet=\(app.navigationBars["Capture"].waitForExistence(timeout: 8))")
                sleep(1)
                shot("09-capture-sheet")
                dump(app, "capture")
                let item = element(app, "c1113-07-1")
                if item.waitForExistence(timeout: 3) {
                    item.tap()
                    note("item detail=\(app.navigationBars["Item"].waitForExistence(timeout: 8))")
                    sleep(1)
                    shot("10-item-detail")
                    dump(app, "item")
                    app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
                }
                let close = app.buttons["Close capture"]
                if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
                sleep(1)
            } else { note("capture row not found") }
        }

        step("05 suggestion controls") {
            toTop(app)
            let kicker = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "(Chief|Kit) suggests")).firstMatch
            note("suggest kicker exists=\(kicker.exists) label=\(kicker.exists ? kicker.label : "-")")
            let change = app.buttons["Change"].firstMatch
            if change.exists {
                change.tap(); sleep(1)
                shot("11-suggestion-change-open")
                app.buttons["Change"].firstMatch.tap(); sleep(1)
            }
        }

        step("06 question") {
            let option = app.buttons["Savings account"]
            if scrollTo(app, option) {
                shot("12-question")
                option.tap(); sleep(3)
                shot("13-question-answered")
            } else { note("question option not found"); shot("12-question-missing") }
        }

        step("07 approve a suggestion") {
            toTop(app)
            let approve = app.buttons["Approve"].firstMatch
            note("approve exists=\(approve.exists) enabled=\(approve.exists && approve.isEnabled)")
            if approve.exists {
                approve.tap(); sleep(1)
                shot("14-after-approve-1s")
                sleep(3)
                shot("15-after-approve-4s")
                dump(app, "after-approve")
            }
        }

        step("08 today and its four segments") {
            tab(app, "Today")
            _ = app.segmentedControls.firstMatch.waitForExistence(timeout: 10)
            sleep(1)
            let segments = app.segmentedControls.firstMatch.buttons
            note("segments=\(segments.allElementsBoundByIndex.map { $0.label })")
            shot("16-today-segment-1")
            for i in 1..<4 where segments.count > i {
                segments.element(boundBy: i).tap(); sleep(1)
                shot("1\(6 + i)-today-segment-\(i + 1)")
            }
            if segments.count > 0 { segments.element(boundBy: 0).tap(); sleep(1) }
            let task = element(app, "Pick up the dry cleaning")
            if task.exists {
                task.tap()
                sleep(2)
                shot("20-task-sheet")
                app.swipeDown(velocity: .fast); sleep(1)
            }
            let done = app.buttons["Mark done"].firstMatch
            note("mark done exists=\(done.exists)")
            if done.exists {
                done.tap(); usleep(800_000)
                shot("21-today-undo-bar")
                dump(app, "undo")
            }
        }

        step("09 brief and one result") {
            tab(app, "Brief")
            _ = waitText(app, "As recorded", timeout: 10)
            sleep(1)
            shot("22-brief")
            app.swipeUp(); sleep(1); shot("23-brief-scrolled")
            let result = app.buttons["Notes for the boiler service visit"]
            if scrollTo(app, result) {
                result.tap(); sleep(3)
                shot("24-result-sheet")
                app.swipeUp(); sleep(1)
                shot("25-result-sheet-scrolled")
                dump(app, "result")
                app.swipeDown(velocity: .fast); sleep(1)
                app.swipeDown(velocity: .fast); sleep(1)
            } else { note("result row not found") }
        }

        step("10 settings when paired") {
            tab(app, "Settings")
            sleep(1)
            shot("26-settings")
            app.swipeUp(); sleep(1); shot("27-settings-scrolled")
        }

        step("11 record screen up to the permission prompt") {
            tab(app, "Inbox")
            let record = app.buttons["Record a capture"]
            if record.exists {
                record.tap(); sleep(3)
                shot("28-record-first-screen")
                let deny = springboard.buttons["Don’t Allow"].exists ? springboard.buttons["Don’t Allow"] : springboard.buttons["Don't Allow"]
                if deny.exists { deny.tap(); sleep(2); shot("29-record-after-deny") }
                dump(app, "record")
            } else { note("record button not found") }
        }
        note("DONE")
    }

    // MARK: - Helpers

    @MainActor private func step(_ name: String, _ body: () -> Void) {
        note("STEP \(name)")
        XCTContext.runActivity(named: name) { _ in body() }
    }

    @MainActor private func tab(_ app: XCUIApplication, _ label: String) {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            .max(by: { $0.frame.minY < $1.frame.minY })
        if let b, b.exists { b.tap(); sleep(1) } else { note("tab \(label) not found") }
    }

    @MainActor private func pairingField(_ app: XCUIApplication) -> XCUIElement {
        for q in [app.textViews, app.textFields] where q["Pairing link"].exists { return q["Pairing link"] }
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Pairing link' OR placeholderValue == 'Pairing link'")).firstMatch
    }

    @MainActor private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor private func waitText(_ app: XCUIApplication, _ text: String, exact: Bool = false, timeout: Double) -> Bool {
        let p = exact ? NSPredicate(format: "label == %@", text) : NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(p).firstMatch.waitForExistence(timeout: timeout)
    }

    @MainActor private func messages(_ app: XCUIApplication) -> String {
        ["This link is not valid", "The server did not answer", "The server did not accept this link",
         "The server gave an unexpected answer"].filter { app.staticTexts[$0].exists }.joined(separator: ",")
    }

    @MainActor private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement) -> Bool {
        for _ in 0..<6 {
            if el.exists && el.isHittable { return true }
            app.swipeUp(); usleep(600_000)
        }
        return el.exists && el.isHittable
    }

    @MainActor private func toTop(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown(); usleep(300_000) }
    }

    @MainActor private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.count > 0 {
            let ret = app.keyboards.buttons["return"]
            if ret.exists { ret.tap() }
            app.navigationBars.firstMatch.tap()
        }
    }

    /// Visible text labels from one hierarchy snapshot, for comparing with the pixels.
    @MainActor private func dump(_ app: XCUIApplication, _ tag: String) {
        let lines = app.debugDescription.split(separator: "\n")
            .filter { $0.contains("StaticText") || $0.contains("Button") }
            .compactMap { line -> String? in
                guard let r = line.range(of: "label: '") else { return nil }
                return String(line[r.upperBound...].prefix(90))
            }
        note("dump \(tag): " + lines.prefix(60).joined(separator: " | "))
    }

    /// Asks the host (the workflow) to do something only it can do, and waits for the acknowledgement.
    private func request(_ what: String) {
        let ok = URL(fileURLWithPath: "/tmp/kitctl/\(what)-ok")
        note("REQUEST \(what)")
        for _ in 0..<20 where !FileManager.default.fileExists(atPath: ok.path) { usleep(500_000) }
        note("REQUEST \(what) acknowledged=\(FileManager.default.fileExists(atPath: ok.path))")
        sleep(2)
    }

    private func note(_ line: String) {
        print("KIT \(String(format: "%.1f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10000))) \(line)")
        fflush(stdout)
    }

    @MainActor private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let dir = URL(fileURLWithPath: "/tmp/kitshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
        note("shot \(name)")
    }
}

import XCTest

/// Kit (Chief) simulator proof against the build 4 sources. The app has no accessibility identifiers, so
/// everything is found by the visible label the Core screen builders declare. Every PNG goes straight to the
/// host disk (/tmp/kitshots) the moment it is taken. Steps never assert, so one miss cannot end the run.
/// Host requests (dark, light, stopstub, revokemic, openurl) are logged as "KIT ... REQUEST <x>"; the workflow
/// performs them and touches /tmp/kitctl/<x>-ok.
final class KitUITests: XCTestCase {
    static let link = "chief://pair?base=https%3A%2F%2Flocalhost%3A8443&token=kit-sim-invented-token-0001"
    static let largerText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws { continueAfterFailure = true }

    @MainActor
    func testScreens() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        step("01 launch unpaired") {
            app.launch()
            let up = app.buttons["Record a capture"].waitForExistence(timeout: 90)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("01-unpaired-inbox")
            dump(app, "unpaired-inbox")
        }

        step("02 pair by typing the link in Settings") {
            tab(app, "Settings")
            shot("02-unpaired-settings")
            let field = app.textFields["Pairing link"].exists ? app.textFields["Pairing link"] : app.textViews["Pairing link"]
            note("pairing field exists=\(field.exists)")
            if field.exists {
                field.tap(); usleep(500_000)
                field.typeText(Self.link)
                shot("03-link-typed")
                let pair = app.buttons["Pair with this link"]
                note("pair button exists=\(pair.exists) hittable=\(pair.exists && pair.isHittable)")
                if pair.exists { pair.tap() }
            }
            var paired = waitText(app, "Paired", timeout: 20)
            note("paired after typing=\(paired) messages=\(messages(app))")
            if !paired {
                request("openurl")
                for name in ["Open", "Öffnen"] where springboard.buttons[name].waitForExistence(timeout: 4) {
                    shot("03b-openurl-confirmation"); springboard.buttons[name].tap(); break
                }
                paired = waitText(app, "Paired", timeout: 20)
                note("paired after openurl=\(paired)")
            }
            dismissKeyboard(app)
            sleep(2)
            shot("04-settings-paired")
            dump(app, "settings-paired")
        }

        step("03 inbox with data") {
            tab(app, "Inbox")
            let data = waitText(app, "building manager", timeout: 30)
            note("inbox shows fixture proposal=\(data)")
            sleep(1)
            shot("05-inbox-top")
            frames(app, ["Approve", "Reject", "Change"])
            dump(app, "inbox-top")
            for i in 1...6 { app.swipeUp(); usleep(800_000); shot(String(format: "06-inbox-scroll-%02d", i)) }
            dump(app, "inbox-bottom")
        }

        step("04 open a recent capture and one filed item") {
            let row = element(app, "Pick up the dry cleaning today")
            if scrollTo(app, row) {
                row.tap()
                note("capture sheet=\(app.navigationBars["Capture"].waitForExistence(timeout: 8))")
                sleep(1)
                shot("07-capture-sheet")
                dump(app, "capture")
                let item = element(app, "c1113-07-1")
                if item.waitForExistence(timeout: 3) {
                    item.tap()
                    note("item detail=\(app.navigationBars["Item"].waitForExistence(timeout: 8))")
                    sleep(1)
                    shot("08-item-detail")
                    dump(app, "item")
                    app.navigationBars.buttons.element(boundBy: 0).tap(); sleep(1)
                }
                let close = app.buttons["Close capture"]
                if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
                sleep(1)
            } else { note("capture row not found"); shot("07-capture-row-missing") }
        }

        step("05 suggestion Change opens a field") {
            toTop(app)
            let change = app.buttons["Change"].firstMatch
            note("change exists=\(change.exists)")
            if change.exists {
                change.tap(); sleep(1)
                shot("09-suggestion-change-open")
                app.buttons["Change"].firstMatch.tap(); sleep(1)
            }
        }

        step("06 question") {
            let option = app.buttons["Savings account"]
            if scrollTo(app, option) {
                shot("10-question")
                option.tap(); sleep(3)
                shot("11-question-answered")
                dump(app, "after-answer")
            } else { note("question option not found"); shot("10-question-missing") }
        }

        step("07 approve the long suggestion") {
            toTop(app)
            let approve = app.buttons["Approve"].firstMatch
            note("approve exists=\(approve.exists) enabled=\(approve.exists && approve.isEnabled)")
            if approve.exists {
                approve.tap(); usleep(700_000)
                shot("12-after-approve-1s")
                sleep(4)
                shot("13-after-approve-5s")
                dump(app, "after-approve")
                note("queued line=\(waitText(app, "Queued as", timeout: 8))")
                shot("14-after-approve-queued")
            }
        }

        step("08 today, four segments, tick and undo, move") {
            tab(app, "Today")
            _ = app.segmentedControls.firstMatch.waitForExistence(timeout: 10)
            sleep(1)
            let segments = app.segmentedControls.firstMatch.buttons
            note("segments=\(segments.allElementsBoundByIndex.map { $0.label })")
            shot("15-today-1")
            dump(app, "today")
            for i in 1..<4 where segments.count > i {
                segments.element(boundBy: i).tap(); sleep(1)
                shot("15-today-\(i + 1)")
            }
            if segments.count > 0 { segments.element(boundBy: 0).tap(); sleep(1) }
            let done = app.buttons["Mark done"].firstMatch
            note("mark done exists=\(done.exists)")
            if done.exists {
                done.tap(); usleep(800_000)
                shot("16-today-after-tick")
                dump(app, "after-tick")
                let undo = app.buttons["Undo"].firstMatch
                note("undo exists=\(undo.exists)")
                if undo.exists { undo.tap(); sleep(2); shot("17-today-after-undo") }
            }
            let task = app.buttons["Pick up the dry cleaning"].firstMatch
            if task.exists {
                task.tap(); sleep(2)
                shot("18-task-sheet")
                dump(app, "task-sheet")
                let move = app.buttons["Move it"].firstMatch
                if move.exists {
                    move.tap(); sleep(1); shot("19-task-sheet-move")
                    let tomorrow = app.buttons["Tomorrow"].firstMatch
                    if tomorrow.exists { tomorrow.tap(); sleep(2); shot("20-after-move-tomorrow") }
                }
                if app.navigationBars.buttons["Done"].exists { app.navigationBars.buttons["Done"].tap() } else { app.swipeDown(velocity: .fast) }
                sleep(1)
                shot("21-today-after-move")
            } else { note("task row not found") }
        }

        step("09 brief, one result, full document and share") {
            tab(app, "Brief")
            _ = waitText(app, "As recorded", timeout: 10)
            sleep(1)
            shot("22-brief")
            dump(app, "brief")
            app.swipeUp(); sleep(1); shot("23-brief-scrolled")
            let result = app.buttons["Notes for the boiler service visit"]
            if scrollTo(app, result) {
                result.tap(); sleep(3)
                shot("24-result-sheet")
                dump(app, "result")
                let draft = app.buttons["Open the draft"]
                if scrollTo(app, draft) { draft.tap(); sleep(3) }
                app.swipeUp(); sleep(1)
                shot("25-result-sheet-draft")
                let share = app.buttons["Share"].firstMatch
                note("share exists=\(share.exists) enabled=\(share.exists && share.isEnabled)")
                if share.exists && share.isEnabled {
                    share.tap(); sleep(3); shot("26-share-sheet")
                    app.swipeDown(velocity: .fast); sleep(1)
                    if app.buttons["Close"].exists { app.buttons["Close"].firstMatch.tap(); sleep(1) }
                }
                if app.navigationBars.buttons["Done"].exists { app.navigationBars.buttons["Done"].tap() } else { app.swipeDown(velocity: .fast) }
                sleep(1)
            } else { note("result row not found") }
        }

        step("10 settings when paired, check server, diagnostics") {
            tab(app, "Settings")
            sleep(2)
            shot("27-settings")
            let check = app.buttons["Check server"]
            if check.exists { check.tap(); sleep(2) }
            shot("28-settings-checked")
            for i in 1...3 { app.swipeUp(); usleep(800_000); shot("29-settings-scroll-\(i)") }
            dump(app, "settings")
        }

        step("11 record: prompt, allow, type instead") {
            tab(app, "Inbox")
            let record = app.buttons["Record a capture"]
            guard record.exists else { note("record button not found"); return }
            record.tap(); sleep(2)
            shot("30-record-prompt")
            alerts("record")
            let allow = springboard.buttons["Allow"]
            if allow.waitForExistence(timeout: 4) { allow.tap(); sleep(2) }
            shot("31-record-after-allow")
            dump(app, "record")
            let typeInstead = app.buttons["Type instead"].firstMatch
            note("type instead exists=\(typeInstead.exists)")
            if typeInstead.exists {
                typeInstead.tap(); sleep(1)
                shot("32-type-instead-confirm")
                let inDialog = app.sheets.buttons["Type instead"]
                let all = app.buttons.matching(NSPredicate(format: "label == 'Type instead'")).allElementsBoundByIndex
                if inDialog.exists { inDialog.tap() } else if all.count > 1 { all.last!.tap() } else { typeInstead.tap() }
                sleep(2)
                let field = app.textFields["What is on your mind"].exists ? app.textFields["What is on your mind"] : app.textViews["What is on your mind"]
                note("typed field exists=\(field.exists)")
                shot("33-typed-capture-empty")
                if field.exists {
                    field.tap(); field.typeText("Book the window cleaner for the first week of December")
                    shot("34-typed-capture-filled")
                    app.buttons["Send"].firstMatch.tap(); sleep(4)
                }
            } else {
                let doneButton = app.buttons["Done"].firstMatch
                if doneButton.exists { doneButton.tap(); sleep(2) }
            }
            shot("35-after-typed-capture")
            toTop(app); sleep(3)
            shot("36-inbox-with-typed-capture")
            dump(app, "after-typed")
        }

        step("12 dark appearance") {
            request("dark")
            tab(app, "Inbox"); toTop(app); sleep(2)
            shot("40-dark-inbox")
            app.swipeUp(); sleep(1); shot("41-dark-inbox-scrolled")
            app.swipeUp(); sleep(1); shot("42-dark-inbox-scrolled-2")
            tab(app, "Today"); sleep(1); shot("43-dark-today")
            tab(app, "Brief"); sleep(1); shot("44-dark-brief")
            let result = app.buttons["Swimming pool monthly pass price"]
            if scrollTo(app, result) { result.tap(); sleep(3); shot("45-dark-result-sheet"); app.swipeDown(velocity: .fast); sleep(1) }
            tab(app, "Settings"); sleep(1); shot("46-dark-settings")
            app.swipeUp(); sleep(1); shot("47-dark-settings-scrolled")
            request("light")
        }

        step("13 larger text") {
            app.terminate()
            app.launchArguments = Self.largerText
            app.launch()
            note("relaunched larger=\(app.buttons["Record a capture"].waitForExistence(timeout: 30))")
            tab(app, "Inbox"); sleep(3)
            shot("50-xl-inbox")
            frames(app, ["Approve", "Reject", "Change", "Record a capture", "Inbox", "Today", "Brief", "Settings"])
            for i in 1...4 { app.swipeUp(); usleep(800_000); shot("51-xl-inbox-scroll-\(i)") }
            tab(app, "Today"); sleep(1); shot("52-xl-today")
            app.swipeUp(); sleep(1); shot("53-xl-today-scrolled")
            tab(app, "Brief"); sleep(1); shot("54-xl-brief")
            tab(app, "Settings"); sleep(1); shot("55-xl-settings")
            app.swipeUp(); sleep(1); shot("56-xl-settings-scrolled")
        }

        step("14 microphone denied") {
            app.terminate()
            request("revokemic")
            app.launchArguments = []
            app.launch()
            note("relaunched=\(app.buttons["Record a capture"].waitForExistence(timeout: 30))")
            let record = app.buttons["Record a capture"]
            if record.exists {
                record.tap(); sleep(3)
                alerts("record-denied")
                shot("60-record-mic-denied")
                dump(app, "record-denied")
                let doneButton = app.buttons["Done"].firstMatch
                note("way out Done exists=\(doneButton.exists)")
                if doneButton.exists { doneButton.tap(); sleep(2) }
                shot("61-after-denied-done")
            }
        }

        step("15 offline") {
            request("stopstub")
            tab(app, "Inbox"); toTop(app)
            app.swipeDown(velocity: .slow); sleep(4)
            shot("70-offline-inbox")
            dump(app, "offline-inbox")
            let approve = app.buttons["Approve"].firstMatch
            note("offline approve exists=\(approve.exists) enabled=\(approve.exists && approve.isEnabled)")
            if approve.exists { approve.tap(); sleep(2); shot("71-offline-approve-tapped") }
            app.swipeUp(); sleep(1); shot("72-offline-inbox-scrolled")
            tab(app, "Today"); sleep(1); shot("73-offline-today")
            let done = app.buttons["Mark done"].firstMatch
            note("offline mark done exists=\(done.exists) enabled=\(done.exists && done.isEnabled)")
            tab(app, "Brief"); sleep(1); shot("74-offline-brief")
            tab(app, "Settings"); sleep(1)
            if app.buttons["Check server"].exists { app.buttons["Check server"].tap(); sleep(4) }
            shot("75-offline-settings")
        }
        note("DONE")
    }

    // MARK: - Helpers

    @MainActor private func step(_ name: String, _ body: () -> Void) {
        note("STEP \(name)")
        XCTContext.runActivity(named: name) { _ in body() }
    }

    /// Bottom bar buttons: the Inbox one reads "Inbox, N need you" when something waits, so match by prefix.
    @MainActor private func tab(_ app: XCUIApplication, _ label: String) {
        let b = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
            .allElementsBoundByIndex.max(by: { $0.frame.minY < $1.frame.minY })
        if let b, b.exists { b.tap(); sleep(1) } else { note("tab \(label) not found") }
    }

    @MainActor private func element(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor private func waitText(_ app: XCUIApplication, _ text: String, timeout: Double) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
            .waitForExistence(timeout: timeout)
    }

    @MainActor private func messages(_ app: XCUIApplication) -> String {
        ["This link is not valid", "The server did not answer", "The server did not accept this link",
         "The server gave an unexpected answer", "Not paired"].filter { element(app, $0).exists }.joined(separator: ",")
    }

    @MainActor private func alerts(_ tag: String) {
        let a = springboard.alerts.allElementsBoundByIndex.map { $0.label + " [" + $0.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: "/") + "]" }
        note("alerts \(tag): \(a)")
    }

    @MainActor private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if el.exists && el.isHittable { return true }
            app.swipeUp(); usleep(600_000)
        }
        return el.exists && el.isHittable
    }

    @MainActor private func toTop(_ app: XCUIApplication) {
        for _ in 0..<5 { app.swipeDown(); usleep(300_000) }
    }

    @MainActor private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.count > 0 {
            let ret = app.keyboards.buttons["return"]
            if ret.exists { ret.tap() }
            if app.keyboards.count > 0 { app.navigationBars.firstMatch.tap() }
        }
    }

    /// Frames of the named buttons, to judge squeezing and clipping alongside the pixels.
    @MainActor private func frames(_ app: XCUIApplication, _ labels: [String]) {
        for label in labels {
            let els = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
                .allElementsBoundByIndex.prefix(3)
            note("frames \(label): " + els.map { "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: " ; "))
        }
        note("window \(app.windows.firstMatch.frame)")
    }

    /// Visible labels from one hierarchy snapshot, for comparing with the pixels.
    @MainActor private func dump(_ app: XCUIApplication, _ tag: String) {
        let lines = app.debugDescription.split(separator: "\n")
            .filter { $0.contains("StaticText") || $0.contains("Button") || $0.contains("TextField") }
            .compactMap { line -> String? in
                guard let r = line.range(of: "label: '") else { return nil }
                let kind = line.contains("Button") ? "B:" : (line.contains("TextField") ? "F:" : "")
                return kind + String(line[r.upperBound...].prefix(110))
            }
        note("dump \(tag): " + lines.prefix(80).joined(separator: " | "))
    }

    /// Asks the host (the workflow) to do something only it can do, and waits for the acknowledgement.
    private func request(_ what: String) {
        let ok = URL(fileURLWithPath: "/tmp/kitctl/\(what)-ok")
        note("REQUEST \(what)")
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: ok.path) { usleep(500_000) }
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

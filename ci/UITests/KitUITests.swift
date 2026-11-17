import XCTest

/// Kit (Chief) simulator proof. The app has no accessibility identifiers, so everything is found by the
/// visible label the Core screen builders declare. Every PNG is written atomically to /tmp/kitshots before
/// its shot line is logged, and the workflow mirrors each file into the upload directory as it appears.
///
/// The suite is split into two stop groups that run as separate CI steps, XL/offline/landscape first:
///   testXLOfflineLandscape - accessibility XL + XXXL, mic denied, offline, landscape
///   testLightActions       - light-mode actions, sheets, Share, typed capture, dark mode
/// Host-only work (appearance, deep link, stub stop, mic revoke, request-log pairing verdict) is requested as
/// "KIT ... REQUEST <x>"; the workflow performs it and touches /tmp/kitctl/<x>-ok. Pairing is judged from the
/// stub request log by ci/UITests/pairing_status.py, which writes /tmp/kitctl/<x>-status ("paired"|"notpaired").
final class KitUITests: XCTestCase {
    static let link = "chief://pair?base=https%3A%2F%2Flocalhost%3A8443&token=kit-sim-invented-token-0001"
    static let largerText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
    static let xxxlText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws { continueAfterFailure = true }

    /// Group 1 (runs first): XL, XXXL, mic denied, offline, landscape. The night's evidence, so it cannot be
    /// the part that a later group's timeout loses.
    @MainActor
    func testXLOfflineLandscape() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        step("01 launch unpaired (xl group)") {
            app.launch()
            let up = app.buttons["Record a capture"].waitForExistence(timeout: 90)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("xl-01-unpaired-inbox")
            dump(app, "xl-unpaired-inbox")
        }

        pairAndConfirm(app, prefix: "xl-")

        step("13a larger text XL light and dark") {
            app.terminate()
            app.launchArguments = Self.largerText
            app.launch()
            note("relaunched xl=\(app.buttons["Record a capture"].waitForExistence(timeout: 30))")
            tab(app, "Inbox"); _ = waitText(app, "building manager", timeout: 20); sleep(2)
            shot("50-xl-inbox")
            frames(app, ["Approve", "Reject", "Change", "Record a capture", "Inbox", "Today", "Brief", "Settings"])
            dump(app, "xl-inbox")
            for i in 1...4 { app.swipeUp(); usleep(800_000); shot("51-xl-inbox-scroll-\(i)") }
            tab(app, "Today"); sleep(1); shot("52-xl-today")
            app.swipeUp(); sleep(1); shot("53-xl-today-scrolled")
            tab(app, "Brief"); sleep(1); shot("54-xl-brief")
            tab(app, "Settings"); sleep(1); shot("55-xl-settings")
            app.swipeUp(); sleep(1); shot("56-xl-settings-scrolled")

            request("dark")
            tab(app, "Inbox"); toTop(app); sleep(2)
            shot("57-xl-dark-inbox")
            tab(app, "Today"); sleep(1); shot("58-xl-dark-today")
            tab(app, "Settings"); sleep(1); shot("59-xl-dark-settings")
            request("light")
        }

        step("13b larger text XXXL bottom bar, today, record") {
            app.terminate()
            app.launchArguments = Self.xxxlText
            app.launch()
            note("relaunched xxxl=\(app.buttons["Record a capture"].waitForExistence(timeout: 30))")
            tab(app, "Inbox"); sleep(2)
            shot("50b-xxxl-inbox")
            frames(app, ["Approve", "Reject", "Change", "Record a capture", "Inbox", "Today", "Brief", "Settings"])
            dump(app, "xxxl-inbox")
            app.swipeUp(); sleep(1); shot("51b-xxxl-inbox-scrolled")

            tab(app, "Today"); sleep(1)
            _ = app.segmentedControls.firstMatch.waitForExistence(timeout: 10)
            shot("52b-xxxl-today")
            dump(app, "xxxl-today")
            let segments = app.segmentedControls.firstMatch.buttons
            for i in 1..<4 where segments.count > i {
                segments.element(boundBy: i).tap(); sleep(1)
                shot("52b-xxxl-today-seg-\(i + 1)")
            }
            if segments.count > 0 { segments.element(boundBy: 0).tap(); sleep(1) }
            app.swipeUp(); sleep(1); shot("53b-xxxl-today-scrolled")

            let record = app.buttons["Record a capture"]
            if record.exists {
                record.tap(); sleep(2)
                let allow = springboard.alerts.buttons["Allow"].firstMatch
                if allow.waitForExistence(timeout: 3) { allow.tap(); sleep(2) }
                shot("54b-xxxl-record")
                dump(app, "xxxl-record")
                let doneButton = app.buttons["Done"].firstMatch
                if doneButton.exists { doneButton.tap(); sleep(2) }
                else if app.buttons["Discard"].firstMatch.exists { app.buttons["Discard"].firstMatch.tap(); sleep(2) }
            }

            tab(app, "Brief"); sleep(1); shot("55b-xxxl-brief")
            tab(app, "Settings"); sleep(1); shot("56b-xxxl-settings")
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

        step("15 offline and command failure") {
            request("stopstub")
            tab(app, "Inbox"); toTop(app)
            app.swipeDown(velocity: .slow); sleep(4)
            shot("70-offline-inbox")
            dump(app, "offline-inbox")
            let approve = app.buttons["Approve"].firstMatch
            note("offline approve exists=\(approve.exists) enabled=\(approve.exists && approve.isEnabled)")
            if approve.exists { approve.tap(); sleep(3); shot("71-offline-approve-tapped") }
            app.swipeUp(); sleep(1); shot("72-offline-inbox-scrolled")
            tab(app, "Today"); sleep(1); shot("73-offline-today")
            let done = app.buttons["Mark done"].firstMatch
            note("offline mark done exists=\(done.exists) enabled=\(done.exists && done.isEnabled)")
            if done.exists { done.tap(); sleep(3); shot("73b-offline-mark-done-tapped") }
            tab(app, "Brief"); sleep(1); shot("74-offline-brief")
            tab(app, "Settings"); sleep(1)
            if app.buttons["Check server"].exists { app.buttons["Check server"].tap(); sleep(4) }
            shot("75-offline-settings")
        }

        step("16 landscape cached screens") {
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
            tab(app, "Inbox"); toTop(app); shot("80-landscape-inbox"); frames(app, ["Record a capture", "Inbox", "Today", "Settings"])
            tab(app, "Today"); shot("81-landscape-today")
            tab(app, "Brief"); shot("82-landscape-brief")
            tab(app, "Settings"); shot("83-landscape-settings")
            XCUIDevice.shared.orientation = .portrait
        }
        note("DONE testXLOfflineLandscape")
    }

    /// Group 2: light-mode actions, sheets, Share, recording, dark mode.
    @MainActor
    func testLightActions() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        step("01 launch unpaired or paired") {
            app.launch()
            let up = app.buttons["Record a capture"].waitForExistence(timeout: 90)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("01-first-screen")
            dump(app, "first-screen")
        }

        pairAndConfirm(app, prefix: "")

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
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pick up the dry cleaning today")).firstMatch
            toTop(app)
            if scrollTo(app, row) {
                row.tap()
                let captureNav = app.navigationBars["Capture"].waitForExistence(timeout: 8)
                note("capture sheet=\(captureNav)")
                sleep(1)
                shot("07-capture-sheet")
                dump(app, "capture")
                if let captureSheet = topmostSheet(in: app, navBarTitle: "Capture") {
                    let item = captureSheet.buttons.matching(NSPredicate(format: "label CONTAINS %@", "c1113-07-1")).firstMatch
                    if item.waitForExistence(timeout: 3) && item.isHittable {
                        item.tap()
                        let itemNav = app.navigationBars["Item"].waitForExistence(timeout: 8)
                        note("item detail=\(itemNav)")
                        sleep(1)
                        shot("08-item-detail")
                        dump(app, "item")
                        let back = app.navigationBars["Item"].buttons.element(boundBy: 0)
                        if itemNav && back.exists && back.isHittable { back.tap(); sleep(1) }
                    } else {
                        note("filed item inside Capture sheet not hittable")
                    }
                } else {
                    note("Capture sheet container not found")
                }
                let close = app.buttons["Close capture"]
                if close.exists && close.isHittable { close.tap() } else { app.swipeDown(velocity: .fast) }
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
                let tomorrow = app.buttons["Tomorrow"].firstMatch
                if scrollTo(app, tomorrow) {
                    shot("19-task-sheet-move")
                    tomorrow.tap(); sleep(2); shot("20-after-move-tomorrow")
                } else { note("Tomorrow not hittable"); shot("19-task-move-missing") }
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
            guard scrollTo(app, result) else {
                note("result row not found")
                shot("22b-result-row-missing")
                XCTFail("Result row not found in Brief; Share was never reached")
                return
            }
            result.tap()
            let resultNav = app.navigationBars["Result"].waitForExistence(timeout: 8)
            note("result sheet nav=\(resultNav)")
            sleep(2)
            shot("24-result-sheet")
            dump(app, "result")

            guard let resultSheet = topmostSheet(in: app, navBarTitle: "Result") else {
                XCTFail("Topmost Result sheet container not found; refusing a background Share lookup")
                return
            }
            let draft = resultSheet.buttons["Open the draft"]
            if scrollTo(resultSheet, draft, container: resultSheet) { draft.tap(); sleep(3) }
            resultSheet.swipeUp(); sleep(1)
            shot("25-result-sheet-draft")

            let share = findHittableShareButton(in: resultSheet)
            note("topmost sheet share found=\(share != nil) hittable=\(share?.isHittable ?? false)")
            guard let share else {
                XCTFail("No hittable Share button inside the topmost Result sheet")
                return
            }
            share.tap()

            var ready = false
            let deadline = Date().addingTimeInterval(12)
            while Date() < deadline {
                if shareSheetIsPresented(app) { ready = true; break }
                usleep(250_000)
            }
            note("share sheet ready=\(ready) activity=\(app.otherElements["ActivityListView"].exists)")
            shot("26-share-sheet")
            dump(app, "share-sheet")
            XCTAssertTrue(ready, "Native Share sheet (ActivityListView or its Close control) did not appear")
            if let close = topmostShareCloseButton(in: app) {
                close.tap(); sleep(1)
            } else {
                app.swipeDown(velocity: .fast); sleep(1)
            }
            if app.navigationBars["Result"].buttons["Done"].exists {
                app.navigationBars["Result"].buttons["Done"].tap()
            } else {
                app.swipeDown(velocity: .fast)
            }
            sleep(1)
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
            guard record.exists else { note("record button not found"); shot("29b-record-missing"); return }
            record.tap(); sleep(2)
            shot("30-record-prompt")
            alerts("record")
            let allow = springboard.alerts.buttons["Allow"].firstMatch
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
        note("DONE testLightActions")
    }

    // MARK: - Pairing

    @MainActor private func pairAndConfirm(_ app: XCUIApplication, prefix: String) {
        step("02 pair by typing the link in Settings and confirm from the request log") {
            tab(app, "Settings")
            shot("\(prefix)02-settings-before-pair")
            let byLabel = NSPredicate(format: "label == 'Pairing link' OR placeholderValue == 'Pairing link'")
            var field = app.textFields.matching(byLabel).firstMatch
            for _ in 0..<6 where !field.exists && !app.textViews.matching(byLabel).firstMatch.exists {
                app.swipeUp(); usleep(600_000)
            }
            if !field.exists { field = app.textViews.matching(byLabel).firstMatch }
            note("pairing field exists=\(field.exists)")
            if field.exists {
                field.tap(); usleep(500_000)
                field.typeText(Self.link)
                shot("\(prefix)03-link-typed")
                let pair = app.buttons["Pair with this link"]
                note("pair button exists=\(pair.exists) hittable=\(pair.exists && pair.isHittable)")
                if pair.exists { pair.tap() }
            }
            dismissKeyboard(app)
            toTop(app)
            sleep(2)
            shot("\(prefix)03c-after-pair-tap")
            dump(app, "\(prefix)after-pair-tap")

            var visible = inspectVisiblePairingStatus(app)
            note("visible status after typing: paired=\(visible.paired) notPaired=\(visible.notPaired) messages=\(messages(app))")

            var logPaired = confirmPairingFromRequestLog(requestName: "checkpair")
            note("request-log pairing checkpair=\(logPaired)")

            if !logPaired {
                request("openurl")
                for name in ["Open", "Öffnen"] where springboard.buttons[name].waitForExistence(timeout: 4) {
                    shot("\(prefix)03b-openurl-confirmation"); springboard.buttons[name].tap(); break
                }
                dismissKeyboard(app)
                toTop(app)
                sleep(2)
                shot("\(prefix)03d-after-openurl")
                dump(app, "\(prefix)after-openurl")
                visible = inspectVisiblePairingStatus(app)
                note("visible status after openurl: paired=\(visible.paired) notPaired=\(visible.notPaired) messages=\(messages(app))")
                logPaired = confirmPairingFromRequestLog(requestName: "checkpairtwo")
                note("request-log pairing checkpairtwo=\(logPaired)")
            }

            toTop(app)
            dismissKeyboard(app)
            sleep(2)
            shot("\(prefix)04-settings-paired")
            dump(app, "\(prefix)settings-paired")
            note("pairing verdict: requestLog=\(logPaired) visiblePaired=\(visible.paired) visibleNotPaired=\(visible.notPaired)")
            XCTAssertTrue(logPaired,
                          "Pairing not proven by the stub request log (need GET /v1/health 200 and a GET /v1/snapshot 200/304 from the app)")
        }
    }

    /// Visible status is recorded but never decides pairing: a silent or stale label must not fail a paired device.
    @MainActor private func inspectVisiblePairingStatus(_ app: XCUIApplication) -> (paired: Bool, notPaired: Bool) {
        let pairedEl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Paired' OR label CONTAINS 'Pairing, Paired'")).firstMatch
        let notPairedEl = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Not paired' OR label CONTAINS 'Not paired'")).firstMatch
        return (pairedEl.exists, notPairedEl.exists)
    }

    private func confirmPairingFromRequestLog(requestName: String) -> Bool {
        request(requestName)
        let statusURL = URL(fileURLWithPath: "/tmp/kitctl/\(requestName)-status")
        let raw = (try? String(contentsOf: statusURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw == "paired"
    }

    // MARK: - Sheets and Share

    /// Innermost presented sheet container owning the named navigation bar.
    @MainActor private func topmostSheet(in app: XCUIApplication, navBarTitle: String) -> XCUIElement? {
        for query in [app.sheets, app.otherElements] {
            let containers = query.containing(.navigationBar, identifier: navBarTitle).allElementsBoundByIndex
            if let last = containers.last, last.exists { return last }
        }
        return nil
    }

    /// A Share button only counts inside the topmost sheet's own frame, so a background screen can never satisfy it.
    @MainActor private func findHittableShareButton(in sheet: XCUIElement) -> XCUIElement? {
        let predicate = NSPredicate(format: "label == 'Share'")
        for _ in 0..<6 {
            let frame = sheet.frame
            let candidates = sheet.buttons.matching(predicate).allElementsBoundByIndex
            if let match = candidates.last(where: {
                $0.exists && $0.isEnabled && $0.isHittable && frame.contains($0.frame)
            }) {
                return match
            }
            sheet.swipeUp(); usleep(500_000)
        }
        return nil
    }

    @MainActor private func shareSheetIsPresented(_ app: XCUIApplication) -> Bool {
        app.otherElements["ActivityListView"].exists || topmostShareCloseButton(in: app) != nil
    }

    /// Close control of the native activity list, never the underlying sheet's Done.
    @MainActor private func topmostShareCloseButton(in app: XCUIApplication) -> XCUIElement? {
        let containers = app.descendants(matching: .any).matching(identifier: "ActivityListView").allElementsBoundByIndex
        for container in containers.reversed() {
            let close = container.buttons["Close"]
            if close.exists && close.isHittable { return close }
        }
        let navClose = app.navigationBars["ActivityListView"].buttons["Close"]
        if navClose.exists && navClose.isHittable { return navClose }
        let window = app.windows.firstMatch.frame
        return app.buttons.matching(NSPredicate(format: "label == 'Close'")).allElementsBoundByIndex.last(where: {
            $0.exists && $0.isHittable && $0.frame.maxY > window.minY && $0.frame.minY < window.maxY * 0.45
        })
    }

    // MARK: - Helpers

    @MainActor private func step(_ name: String, _ body: () -> Void) {
        note("AUDIT begin \(name)")
        XCTContext.runActivity(named: name) { _ in body() }
        note("AUDIT stop \(name)")
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

    @MainActor private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement, container: XCUIElement? = nil) -> Bool {
        let scroller = container ?? app
        for _ in 0..<8 {
            if el.exists && el.isHittable { return true }
            scroller.swipeUp(); usleep(600_000)
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
        for _ in 0..<60 where !FileManager.default.fileExists(atPath: ok.path) { usleep(500_000) }
        note("REQUEST \(what) acknowledged=\(FileManager.default.fileExists(atPath: ok.path))")
        sleep(2)
    }

    private func note(_ line: String) {
        print("KIT \(String(format: "%.1f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 10000))) \(line)")
        fflush(stdout)
    }

    /// Writes the PNG atomically before logging the shot line, so a logged shot always exists on disk.
    @MainActor private func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let dir = URL(fileURLWithPath: "/tmp/kitshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("\(name).png")
        let tmp = dir.appendingPathComponent(".\(name).png.tmp")
        do {
            try png.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.moveItem(at: tmp, to: dest)
            note("shot \(name)")
        } catch {
            note("shot-write-failed \(name): \(error)")
        }
    }
}

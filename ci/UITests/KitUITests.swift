import XCTest

/// Kit (Chief) simulator proof. The app has no accessibility identifiers, so everything is found by the
/// visible label the Core screen builders declare. Every PNG is written atomically to /tmp/kitshots before
/// its shot line is logged, and the workflow mirrors each file into the upload directory as it appears.
///
/// The suite is split into three stop groups that run as separate CI steps, XL/XXXL layout first:
///   testXLLayout      - accessibility XL (light/dark) + XXXL (Inbox, Today 4 segments, Record, Brief, Settings)
///   testXLEnvironment - mic denied, offline, landscape
///   testLightActions  - light-mode actions, sheets, Share, typed capture, dark mode
/// Host-only work (appearance, deep link, stub stop, mic revoke, request-log pairing verdict) is requested as
/// "KIT ... REQUEST <x>"; the workflow performs it, verifies the resulting condition and writes
/// /tmp/kitctl/<x>-result ("ok" or "fail rc=..."), creating /tmp/kitctl/<x>-ok only when it verified. Pairing is
/// judged from the stub request log by ci/UITests/pairing_status.py, which writes /tmp/kitctl/<x>-status
/// ("paired"|"notpaired") from the action-specific checkpoint the host recorded when the action started.
final class KitUITests: XCTestCase {
    static let link = "chief://pair?base=https%3A%2F%2Flocalhost%3A8443&token=kit-sim-invented-token-0001"
    static let largerText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
    static let xxxlText = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
    static let bottomBar = ["Inbox", "Today", "Brief", "Settings"]
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    /// Height of the Record button at the group's own text size, so the XL and XXXL stops can report their ratio.
    var baseRecordHeight: CGFloat = 0

    override func setUpWithError() throws { continueAfterFailure = true }

    /// Group 1 (runs first): XL and XXXL layout. The night's primary evidence, so it cannot time out behind environment stops.
    @MainActor
    func testXLLayout() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        step("01 launch unpaired (xl-layout group)") {
            app.launch()
            let up = recordControl(app).waitForExistence(timeout: 90)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("xl-01-unpaired-inbox")
            scaleProbe(app, "baseline", nil)
            dump(app, "xl-unpaired-inbox")
        }

        pairAndConfirm(app, prefix: "xl-")
        step("KIT-01A Record enabled after API 2 sync and after offline same-container relaunch") {
            tab(app, "Inbox")
            XCTAssertTrue(waitText(app, "building manager", timeout: 20), "Synthetic snapshot did not reach Inbox")
            guard request("cacheonline") else { return }
            assertRecordAtZero(app, proof: "kit01a-after-api2-sync")
            guard request("stopstub") else { return }
            app.terminate()
            XCTAssertEqual(app.state, .notRunning, "Kit must terminate before the relaunch")
            app.launch()
            tab(app, "Inbox")
            XCTAssertTrue(waitText(app, "building manager", timeout: 20), "Synthetic snapshot did not reload offline")
            guard request("cacheoffline") else { return }
            assertRecordAtZero(app, proof: "kit01a-after-offline-relaunch")
            request("restartstub", timeout: 45)
        }

        step("13a larger text XL light and dark") {
            app.terminate()
            app.launchArguments = Self.largerText
            app.launch()
            note("relaunched xl=\(recordControl(app).waitForExistence(timeout: 30))")
            tab(app, "Inbox"); _ = waitText(app, "building manager", timeout: 20); sleep(2)
            shot("50-xl-inbox")
            scaleProbe(app, "xl", "effective_scale_xl")
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
            note("relaunched xxxl=\(recordControl(app).waitForExistence(timeout: 30))")
            tab(app, "Inbox"); sleep(2)
            shot("50b-xxxl-inbox")
            scaleProbe(app, "xxxl", "effective_scale_xxxl")
            frames(app, ["Approve", "Reject", "Change", "Record a capture", "Inbox", "Today", "Brief", "Settings"])
            assertBottomBar(app)
            dump(app, "xxxl-inbox")
            app.swipeUp(); sleep(1); shot("51b-xxxl-inbox-scrolled")

            tab(app, "Today"); sleep(1)
            let control = app.segmentedControls.firstMatch
            var segments = control.buttons
            if !control.waitForExistence(timeout: 3) {
                let predicate = NSPredicate(format: "label BEGINSWITH 'Today ' OR label BEGINSWITH 'Later ' OR label BEGINSWITH 'Waiting ' OR label BEGINSWITH 'Ideas '")
                let standalone = app.buttons.matching(predicate)
                note("xxxl segment buttons via accessibility=\(standalone.count)")
                segments = standalone
            }
            let controlAppeared = segments.count >= 4
            XCTAssertTrue(controlAppeared, "Today segmented control did not appear at XXXL")
            shot("52b-xxxl-today")
            dump(app, "xxxl-today")
            note("segments count=\(segments.count)")
            XCTAssertGreaterThanOrEqual(segments.count, 4, "Today shows \(segments.count) segment(s), four expected at XXXL")
            for i in 0..<min(4, segments.count) {
                let seg = segments.element(boundBy: i)
                note("segment \(i + 1) label=\(seg.label) selected=\(seg.isSelected)")
            }
            for i in 1..<4 where segments.count > i {
                segments.element(boundBy: i).tap(); sleep(1)
                shot("52b-xxxl-today-seg-\(i + 1)")
            }
            if segments.count > 0 { segments.element(boundBy: 0).tap(); sleep(1) }
            app.swipeUp(); sleep(1); shot("53b-xxxl-today-scrolled")

            let record = recordControl(app)
            if record.exists {
                let b = record.frame
                note("record exists=true frame=\(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))x\(Int(b.height)) hittable=\(record.isHittable)")
            } else {
                note("record exists=false")
            }
            XCTAssertTrue(record.exists, "Record a capture button missing at XXXL")
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
        note("DONE testXLLayout")
    }

    /// Group 2: mic denied, offline, landscape. It runs at the device's default text size - these stops prove
    /// environment behaviour, not layout, and keeping them on the default size keeps the group inside its budget.
    @MainActor
    func testXLEnvironment() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        note("xl-environment group runs at the device's default text size")

        step("01 launch unpaired (xl-environment group)") {
            app.launch()
            let up = recordControl(app).waitForExistence(timeout: 90)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("env-01-unpaired-inbox")
            dump(app, "env-unpaired-inbox")
        }

        pairAndConfirm(app, prefix: "env-")

        step("14 microphone denied") {
            app.terminate()
            request("revokemic")
            app.launchArguments = []
            app.launch()
            note("relaunched=\(recordControl(app).waitForExistence(timeout: 30))")
            let record = recordControl(app)
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
            let windowBefore = app.windows.firstMatch.frame
            note("window_before \(Int(windowBefore.minX)),\(Int(windowBefore.minY)) \(Int(windowBefore.width))x\(Int(windowBefore.height))")
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(3)
            let windowAfter = app.windows.firstMatch.frame
            note("window_after \(Int(windowAfter.minX)),\(Int(windowAfter.minY)) \(Int(windowAfter.width))x\(Int(windowAfter.height))")
            note("landscape_viewport=\(windowAfter.width > windowAfter.height)")
            tab(app, "Inbox"); toTop(app); shot("80-landscape-inbox"); frames(app, ["Record a capture", "Inbox", "Today", "Settings"])
            tab(app, "Today"); shot("81-landscape-today")
            tab(app, "Brief"); shot("82-landscape-brief")
            tab(app, "Settings"); shot("83-landscape-settings")
            XCUIDevice.shared.orientation = .portrait
        }
        note("DONE testXLEnvironment")
    }

    /// Group 3: light-mode actions, sheets, Share, recording, dark mode.
    @MainActor
    func testLightActions() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()

        step("01 launch unpaired or paired") {
            app.launch()
            let up = recordControl(app).waitForExistence(timeout: 90)
            note("launched=\(up) state=\(app.state.rawValue)")
            sleep(2)
            shot("01-first-screen")
            scaleProbe(app, "baseline-light", nil)
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
            if scrollTo(app, draft, container: resultSheet) { draft.tap(); sleep(3) }
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
            let record = recordControl(app)
            guard record.exists else { note("record button not found"); shot("29b-record-missing"); return }
            if !record.isEnabled {
                note("record disabled before the stop: label='\(record.label)'; waiting up to 20 s for the queue to drain")
                let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: record)
                _ = XCTWaiter.wait(for: [enabled], timeout: 20)
            }
            note("record pre-tap label='\(record.label)' enabled=\(record.isEnabled)")
            shot("30-record-prompt")
            if record.isEnabled { record.tap(); sleep(2) } else { note("record still disabled: 31-33 describe the disabled state, not a prompt sheet") }
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
        step("02 pair in Settings and confirm from the request log") {
            tab(app, "Settings")
            shot("\(prefix)02-settings-before-pair")
            guard request("markpair") else { return }
            let byLabel = NSPredicate(format: "label == 'Pairing link' OR placeholderValue == 'Pairing link'")
            var field = app.textFields.matching(byLabel).firstMatch
            for _ in 0..<6 where !field.exists && !app.textViews.matching(byLabel).firstMatch.exists {
                app.swipeUp(); usleep(600_000)
            }
            if !field.exists { field = app.textViews.matching(byLabel).firstMatch }
            let fieldReady = field.exists && field.isHittable
            note("pairing field hittable=\(fieldReady)")
            var tappedPair = false
            if fieldReady {
                field.tap(); usleep(500_000)
                field.typeText(Self.link)
                shot("\(prefix)03-link-typed")
                dismissKeyboard(app)
                // Start the drag inside the visible list, not on the keyboard or the raised bar.
                // The multiline field expands when filled; its Pair row can disappear from the AX tree.
                revealPairingRow(app)
                let pair = app.buttons.matching(NSPredicate(format: "label == 'Pair with this link' OR label == 'Pair'"))
                    .firstMatch
                for _ in 0..<5 where !pair.isHittable { revealPairingRow(app) }
                tappedPair = pair.exists && pair.isHittable && pair.isEnabled
                note("pair button hittable=\(tappedPair)")
                if tappedPair {
                    pair.tap()
                    shot("\(prefix)03c-after-pair-tap")
                }
            }
            var confirmed = tappedPair && confirmPairingFromRequestLog(requestName: "checkpair")
            if !confirmed {
                note("typed pairing unproved (pair button tapped=\(tappedPair)); trying fixture link")
                guard request("markopenurl") else { return }
                let opened = request("openurl", timeout: 60)
                for name in ["Open", "Öffnen"] where springboard.buttons[name].waitForExistence(timeout: 2) {
                    shot("\(prefix)03b-openurl-confirmation"); springboard.buttons[name].tap(); break
                }
                confirmed = confirmPairingFromRequestLog(requestName: "checkpairtwo") && opened
            }
            let visible = inspectVisiblePairingStatus(app)
            note("pairing verdict: requestLog=\(confirmed) visiblePaired=\(visible.paired) visibleNotPaired=\(visible.notPaired)")
            shot("\(prefix)04-settings-\(confirmed ? "paired" : "pairing-unproved")")
            dump(app, "\(prefix)after-pairing")
            XCTAssertTrue(confirmed, "Pairing requires fresh authenticated health and snapshot requests from the app")
        }
    }

    @MainActor private func revealPairingRow(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.46))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.26))
        start.press(forDuration: 0.05, thenDragTo: end)
        usleep(500_000)
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
        // The host polls for up to 120s. A shorter XCTest wait races the next request.
        guard request(requestName, timeout: 135) else { return false }
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

    /// The Record control in either state. Core relabels it while the last capture is being sent
    /// ("Record unavailable while the last capture is being sent"), so an exact-label query misses a control that is
    /// on screen, which is how the light group lost `30-record-prompt` on 18 November.
    @MainActor private func recordControl(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == 'Record a capture' OR label BEGINSWITH 'Record unavailable'"))
            .firstMatch
    }

    // MARK: - Helpers

    @MainActor private func assertRecordAtZero(_ app: XCUIApplication, proof: String) {
        tab(app, "Settings")
        let waiting = app.staticTexts["Waiting to send"].firstMatch
        for _ in 0..<6 where !waiting.exists || !waiting.isHittable {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.71))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.34))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        let zeroInRow = waiting.exists && waiting.isHittable && app.staticTexts.matching(identifier: "0")
            .allElementsBoundByIndex.contains { $0.isHittable && abs($0.frame.midY - waiting.frame.midY) < 15 }
        XCTAssertTrue(zeroInRow, "The Settings Waiting to send row must show 0")
        let record = recordControl(app)
        let enabled = record.exists && record.isEnabled && record.isHittable && record.label == "Record a capture"
        XCTAssertTrue(enabled, "Record must be enabled and hittable at zero waiting")
        note("record-proof \(proof) waiting_zero=\(zeroInRow) record_enabled_hittable=\(enabled)")
        shot(proof)
        dump(app, proof)
    }

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
            let hide = app.keyboards.buttons["Hide keyboard"].firstMatch
            if hide.exists && hide.isHittable { hide.tap() }
            let bar = app.navigationBars.firstMatch
            if app.keyboards.count > 0 && bar.exists && bar.isHittable { bar.tap() }
        }
    }

    /// Frames of the named buttons, to judge squeezing and clipping alongside the pixels. For a bottom-bar
    /// destination the bottommost match is the bar control itself, so it is logged on its own line with its size
    /// and hittability instead of being averaged in with same-labelled buttons from the content area.
    @MainActor private func frames(_ app: XCUIApplication, _ labels: [String]) {
        for label in labels {
            let els: [XCUIElement]
            if label == "Record a capture" {
                let r = recordControl(app)
                els = r.exists ? [r] : []
            } else {
                els = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
                    .allElementsBoundByIndex
            }
            note("frames \(label): " + els.prefix(3).map {
                "\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height)) hittable=\($0.isHittable) enabled=\($0.isEnabled) label='\($0.label.prefix(60))'"
            }.joined(separator: " ; "))
            if Self.bottomBar.contains(label), let bar = els.max(by: { $0.frame.minY < $1.frame.minY }) {
                note("bottom_bar \(label): \(Int(bar.frame.minX)),\(Int(bar.frame.minY)) \(Int(bar.frame.width))x\(Int(bar.frame.height)) hittable=\(bar.isHittable) min44=\(bar.frame.width >= 44 && bar.frame.height >= 44)")
            }
        }
        note("window \(app.windows.firstMatch.frame)")
    }

    /// Each bottom-bar destination must resolve to one hittable control of at least 44x44 pt. The bar control is the
    /// bottommost match, because a screen can also show a same-labelled button higher up.
    @MainActor private func assertBottomBar(_ app: XCUIApplication) {
        for label in Self.bottomBar {
            let candidates = app.buttons.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", label, label + ","))
                .allElementsBoundByIndex
            guard let bar = candidates.max(by: { $0.frame.minY < $1.frame.minY }), bar.exists else {
                XCTFail("bottom bar destination \(label) not found")
                continue
            }
            note("bottom_bar_check \(label): \(Int(bar.frame.minX)),\(Int(bar.frame.minY)) \(Int(bar.frame.width))x\(Int(bar.frame.height)) hittable=\(bar.isHittable)")
            XCTAssertTrue(bar.isHittable, "bottom bar \(label) is not hittable")
            XCTAssertTrue(bar.frame.width >= 44 && bar.frame.height >= 44,
                          "bottom bar \(label) is \(Int(bar.frame.width))x\(Int(bar.frame.height)) pt, under the 44 pt target")
        }
    }

    /// Requests a Dynamic Type category through launch arguments and records what the app actually rendered: the
    /// arguments, the measured heights of the Record button, the Inbox tab and a body label, and the ratio of the
    /// Record height to the group's baseline. A flag on its own is not evidence of the effective text size
    /// (episode 22); the measured heights are what the auditor compares with the pixels.
    @MainActor private func scaleProbe(_ app: XCUIApplication, _ tag: String, _ name: String?) {
        let record = recordControl(app)
        let inbox = app.buttons.matching(NSPredicate(format: "label == 'Inbox' OR label BEGINSWITH 'Inbox,'"))
            .allElementsBoundByIndex.max(by: { $0.frame.minY < $1.frame.minY })
        let body = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "building manager")).firstMatch
        let recordHeight = record.exists ? record.frame.height : 0
        if baseRecordHeight == 0 && recordHeight > 0 { baseRecordHeight = recordHeight }
        let ratio = baseRecordHeight > 0 ? recordHeight / baseRecordHeight : 0
        note("scaleprobe tag=\(tag) launchArguments=\(app.launchArguments) record_height=\(Int(recordHeight)) inbox_height=\(Int(inbox?.frame.height ?? 0)) text_height=\(Int(body.exists ? body.frame.height : 0)) baseline_height=\(Int(baseRecordHeight))")
        if let name { note("\(name)=\(String(format: "%.2f", ratio))") }
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

    /// Asks the host (the workflow) to do something only it can do, waits for the per-request result and returns
    /// whether the host verified the resulting condition. A host that only ran a command writes "fail rc=...", so a
    /// request can no longer look acknowledged after a failed simctl call. The stops that depend on the condition
    /// fail the test here instead of continuing with an unproven device state (episode 19).
    @discardableResult
    private func request(_ what: String, timeout: TimeInterval = 30) -> Bool {
        let result = URL(fileURLWithPath: "/tmp/kitctl/\(what)-result")
        note("REQUEST \(what)")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !FileManager.default.fileExists(atPath: result.path) { usleep(500_000) }
        let raw = (try? String(contentsOf: result, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ok = raw == "ok"
        note("REQUEST \(what) result=\(raw.isEmpty ? "absent" : raw) ok=\(ok)")
        switch what {
        case "dark", "revokemic", "stopstub", "markpair", "markopenurl", "cacheonline", "cacheoffline", "restartstub":
            XCTAssertTrue(ok, "host request \(what) did not verify (\(raw.isEmpty ? "no result file" : raw)); the condition this stop depends on is unproven")
        default:
            break
        }
        sleep(2)
        return ok
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

import CryptoKit
import Foundation
import UIKit
import XCTest

/// The journey player (D-20261126-p-66, issue #86). One test method per journey lives in `Journeys.swift` (generated);
/// `run_journeys.sh` runs each in its own xcodebuild run, so a hung journey costs only itself.
///
/// The app starts the way a user starts it: `app.launch()` with nothing added, no argument, no environment and no
/// state written from outside. After every step the player writes the screen, the element tree and a step record
/// with the sha256 digests of those bytes to `/tmp/journeys/<journey>/`. It does not judge the journey: the factory
/// does, on the server, from those files. A verb it does not play is recorded as `not supported`, never skipped.
///
/// Events (issue #88): a DEBUG build of the app appends `<UTC time> <event> <text>` lines to
/// `Library/Caches/factory-events/events.log` in its own container (`FactoryEvents.swift`). The player finds that
/// container by the bundle id the runner names (`JOURNEY_APP_ID`) and reads the file; it never writes it. Rule: an
/// `expect_event` step sees the lines written since the start of the last step before it that is not an
/// `expect_event` (the action that should cause the event), so several `expect_event` steps after one tap all look at
/// that tap. The lines it saw are written as `<NN>.events.log` beside the step record.
///
/// Relaunch (issue #89): `relaunch` ends the app and starts it again without reinstalling it, so its container, and
/// with it what the app saved, is kept; `launch` with `fresh: true` starts from the install the runner made after
/// uninstalling the app, so a fresh journey never sees what an earlier journey saved.
final class JourneyPlayerUITests: XCTestCase {
    private var relaunched: [String: Bool]?
    private var eventMark = 0
    private var markedAt = 1
    private var eventWindow = Data()

    override func setUpWithError() throws { continueAfterFailure = true }

    @MainActor
    func play(_ id: String, list: String) {
        let out = URL(fileURLWithPath: "/tmp/journeys").appendingPathComponent(id)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard let data = Data(base64Encoded: list),
              let doc = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let steps = doc["steps"] as? [[String: Any]] else {
            print("JOURNEY \(id) unreadable step list")
            return
        }
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let fresh = ProcessInfo.processInfo.environment["JOURNEY_FRESH"] == "1"
        let start = Date()
        for (offset, step) in steps.enumerated() {
            let index = offset + 1
            let verb = step["do"] as? String ?? ""
            let began = Date()
            if verb != "expect_event" {
                eventMark = eventLog().count
                markedAt = index
            }
            let (result, detail) = perform(step, verb: verb, index: index, app: app, fresh: fresh)
            let seconds = Date().timeIntervalSince(began)
            capture(id: id, index: index, step: step, result: result, detail: detail, fresh: fresh,
                    started: began.timeIntervalSince(start), seconds: seconds, app: app, out: out)
            print("JOURNEY \(id) step \(index) \(verb) \(result) \(detail)")
            if result != "pass" { break }
        }
        print("JOURNEY \(id) end")
    }

    @MainActor
    private func perform(_ step: [String: Any], verb: String, index: Int, app: XCUIApplication,
                         fresh: Bool) -> (String, String) {
        let timeout = (step["timeout_s"] as? NSNumber)?.doubleValue ?? (verb == "wait" ? 10 : 5)
        switch verb {
        case "launch":
            if index != 1 {
                return ("not supported", "a launch after the first step keeps the app's state: that is a relaunch")
            }
            if (step["fresh"] as? Bool) == true && !fresh {
                return ("not supported", "the runner did not install the app fresh before this journey")
            }
            app.launch()
            return app.wait(for: .runningForeground, timeout: 15)
                ? ("pass", "") : ("fail", "the app did not reach the foreground within 15 s")
        case "relaunch":
            if index == 1 { return ("not supported", "a journey starts with `launch`; `relaunch` needs a running app") }
            app.terminate()
            let stopped = app.wait(for: .notRunning, timeout: 15)
            app.launch()
            let shown = app.wait(for: .runningForeground, timeout: 15)
            relaunched = ["stopped": stopped, "foreground": shown]
            if !stopped { return ("fail", "the app did not stop within 15 s") }
            return shown ? ("pass", "") : ("fail", "the app did not reach the foreground within 15 s of the relaunch")
        case "tap":
            guard let query = query(step, app: app) else { return ("not supported", "the step names no target") }
            guard query.waitForExistence(timeout: timeout) else { return ("fail", notFound(step, timeout)) }
            guard hittable(query, timeout: timeout) else {
                return ("fail", "\(describe(step)) was found but could not be tapped within \(Int(timeout)) s")
            }
            query.tap()
            usleep(500_000)
            return ("pass", "")
        case "type":
            guard let text = step["text"] as? String else { return ("not supported", "the step has no text") }
            guard let query = query(step, app: app) else { return ("not supported", "the step names no target") }
            guard query.waitForExistence(timeout: timeout) else { return ("fail", notFound(step, timeout)) }
            query.tap()
            usleep(500_000)
            query.typeText(text)
            let value = (query.value as? String) ?? ""
            return value.contains(text) ? ("pass", "") : ("fail", "\(describe(step)) does not hold the typed text")
        case "wait":
            guard let query = query(step, app: app) else { return ("not supported", "the step names no target") }
            return query.waitForExistence(timeout: timeout) ? ("pass", "") : ("fail", notFound(step, timeout))
        case "expect":
            guard let query = query(step, app: app) else { return ("not supported", "the step names no target") }
            return query.waitForExistence(timeout: timeout) ? ("pass", "") : ("fail", notFound(step, timeout))
        case "expect_absent":
            guard let query = query(step, app: app) else { return ("not supported", "the step names no target") }
            let end = Date().addingTimeInterval(timeout)
            while query.exists && Date() < end { usleep(250_000) }
            return query.exists
                ? ("fail", "\(describe(step)) is still shown after \(Int(timeout)) s") : ("pass", "")
        case "expect_event":
            guard let event = step["event"] as? String else { return ("not supported", "the step names no event") }
            return expectEvent(event, containing: step["contains"] as? String, timeout: timeout)
        default:
            return ("not supported", "the player does not support `\(verb)`")
        }
    }

    private func expectEvent(_ event: String, containing wanted: String?, timeout: Double) -> (String, String) {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let log = eventLog()
            eventWindow = log.count >= eventMark ? log.subdata(in: eventMark..<log.count) : log
            let lines = String(decoding: eventWindow, as: UTF8.self).split(separator: "\n")
            let hit = lines.contains { line in
                let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
                guard parts.count >= 2, String(parts[1]) == event else { return false }
                return wanted.map { parts.count == 3 && parts[2].contains($0) } ?? true
            }
            if hit { return ("pass", "") }
            usleep(250_000)
        } while Date() < end
        let holding = wanted.map { " holding '\($0)'" } ?? ""
        let missing = eventLogURL() == nil ? " (the app wrote no event log)" : ""
        return ("fail", "no `\(event)` event\(holding) was logged since step \(markedAt) within \(Int(timeout)) s\(missing)")
    }

    /// The app's event log, found through the container metadata of the simulator (an app's data containers are
    /// siblings of the runner's own home folder), or nil before the app has written one.
    private func eventLogURL() -> URL? {
        guard let appID = ProcessInfo.processInfo.environment["JOURNEY_APP_ID"], !appID.isEmpty else { return nil }
        let containers = URL(fileURLWithPath: NSHomeDirectory()).deletingLastPathComponent()
        let folders = (try? FileManager.default.contentsOfDirectory(at: containers, includingPropertiesForKeys: nil)) ?? []
        for folder in folders {
            let meta = folder.appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let info = NSDictionary(contentsOf: meta), info["MCMMetadataIdentifier"] as? String == appID else { continue }
            let file = folder.appendingPathComponent("Library/Caches/factory-events/events.log")
            return FileManager.default.fileExists(atPath: file.path) ? file : nil
        }
        return nil
    }

    private func eventLog() -> Data {
        guard let url = eventLogURL() else { return Data() }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    @MainActor
    private func query(_ step: [String: Any], app: XCUIApplication) -> XCUIElement? {
        guard let target = step["target"] as? [String: Any] else { return nil }
        var parts: [NSPredicate] = []
        if let label = target["label"] as? String { parts.append(NSPredicate(format: "label == %@", label)) }
        if let identifier = target["identifier"] as? String {
            parts.append(NSPredicate(format: "identifier == %@", identifier))
        }
        if parts.isEmpty { return nil }
        let match = NSCompoundPredicate(andPredicateWithSubpredicates: parts)
        return app.descendants(matching: .any).matching(match).firstMatch
    }

    @MainActor
    private func hittable(_ element: XCUIElement, timeout: Double) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !element.isHittable && Date() < end { usleep(250_000) }
        return element.isHittable
    }

    private func describe(_ step: [String: Any]) -> String {
        let target = step["target"] as? [String: Any] ?? [:]
        return ["label", "identifier"].compactMap { key in (target[key] as? String).map { "\(key) '\($0)'" } }
            .joined(separator: ", ")
    }

    private func notFound(_ step: [String: Any], _ timeout: Double) -> String {
        "\(describe(step)) was not found within \(Int(timeout)) s"
    }

    @MainActor
    private func capture(id: String, index: Int, step: [String: Any], result: String, detail: String, fresh: Bool,
                         started: Double, seconds: Double, app: XCUIApplication, out: URL) {
        let stem = String(format: "%02d", index)
        let hex = { (bytes: Data) in SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
        var treeBytes = Data()
        if let snapshot = try? app.snapshot(),
           let data = try? JSONSerialization.data(withJSONObject: node(snapshot), options: [.sortedKeys]) {
            try? data.write(to: out.appendingPathComponent(stem + ".json"))
            treeBytes = data
        }
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: out.appendingPathComponent(stem + ".png"))
        var record: [String: Any] = [
            "journey": id,
            "index": index,
            "step": step,
            "result": result,
            "detail": detail,
            "fresh_install": fresh,
            "started_s": started,
            "seconds": seconds,
            "screen": ["file": stem + ".png", "sha256": hex(png)],
        ]
        record["tree"] = treeBytes.isEmpty ? NSNull() : ["file": stem + ".json", "sha256": hex(treeBytes)]
        if let relaunch = relaunched {
            record["relaunch"] = relaunch
            relaunched = nil
        }
        if step["do"] as? String == "expect_event" {
            try? eventWindow.write(to: out.appendingPathComponent(stem + ".events.log"))
            record["events"] = ["file": stem + ".events.log", "sha256": hex(eventWindow), "since_step": markedAt,
                                "log": eventLogURL() == nil ? "missing" : "found"]
            eventWindow = Data()
        }
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: out.appendingPathComponent(stem + ".step.json"))
        }
    }

    private func node(_ s: XCUIElementSnapshot) -> [String: Any] {
        [
            "type": Int(s.elementType.rawValue),
            "identifier": s.identifier,
            "label": s.label,
            "value": (s.value as? String) ?? "",
            "enabled": s.isEnabled,
            "frame": [Double(s.frame.minX), Double(s.frame.minY), Double(s.frame.width), Double(s.frame.height)],
            "children": s.children.map { node($0) },
        ]
    }
}

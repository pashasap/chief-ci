import Foundation
import UIKit
import XCTest

final class AuditFuzzUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    @MainActor
    func fuzzStop(_ id: String, steps: Int, seed: UInt64) {
        let out = URL(fileURLWithPath: "/tmp/audit-stops")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments = ["-auditStop", id]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        usleep(800_000)
        var state: UInt64 = seed == 0 ? 1 : seed
        var logSteps: [[String: Any]] = []
        for stepIdx in 0..<steps {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let running = app.state == .runningForeground
            let buttons = app.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isEnabled && $0.isHittable }
            let window = app.windows.firstMatch.frame
            var violations: [String] = []
            if !running { violations.append("not_running_foreground") }
            for btn in buttons.prefix(24) {
                let f = btn.frame
                if f.width > 0 && f.height > 0 && (f.maxX < -2 || f.minX > window.width + 2 || f.maxY < -2 || f.minY > window.height + 2) {
                    violations.append("control_outside_window")
                    break
                }
            }
            let trapped = running && buttons.isEmpty && app.navigationBars.buttons.count == 0
            var tapped = "none"
            if running && !buttons.isEmpty {
                let pick = Int((state >> 16) % UInt64(buttons.count))
                let target = buttons[pick]
                tapped = target.identifier.isEmpty ? target.label : target.identifier
                target.tap()
                usleep(250_000)
            }
            logSteps.append(["step": stepIdx, "app_running": running, "trapped": trapped, "tapped": tapped, "layout_violations": violations])
            if !running || trapped || !violations.isEmpty {
                let failPng = XCUIScreen.main.screenshot().pngRepresentation
                try? failPng.write(to: out.appendingPathComponent("fuzz-" + id + "-fail.png"))
                break
            }
        }
        let payload: [String: Any] = ["stop_id": id, "seed": Int(seed), "steps": logSteps]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            try? data.write(to: out.appendingPathComponent("fuzz-" + id + "-seed\(seed).json"))
        }
        app.terminate()
    }
    @MainActor func test_fuzz_001_home_bento() { fuzzStop("home-bento", steps: 15, seed: 1) }
    @MainActor func test_fuzz_002_inbox_universal_tiles() { fuzzStop("inbox-universal-tiles", steps: 15, seed: 1) }
    @MainActor func test_fuzz_003_tasks_ideas() { fuzzStop("tasks-ideas", steps: 15, seed: 1) }
}

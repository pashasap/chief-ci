import CoreGraphics
import Foundation
import UIKit
import XCTest

final class AuditFuzzUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func collectButtons(_ s: XCUIElementSnapshot, into out: inout [XCUIElementSnapshot]) {
        if s.elementType == .button && s.isEnabled && s.frame.width >= 4 && s.frame.height >= 4 {
            out.append(s)
        }
        for child in s.children { collectButtons(child, into: &out) }
    }

    @MainActor
    func fuzzStop(_ id: String, steps: Int, seed: UInt64) {
        let out = URL(fileURLWithPath: "/tmp/audit-stops")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let app = XCUIApplication()
        app.launchArguments = ["-auditStop", id]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 10)
        usleep(600_000)
        var state: UInt64 = seed == 0 ? 1 : seed
        var logSteps: [[String: Any]] = []
        defer {
            let payload: [String: Any] = ["stop_id": id, "seed": Int(seed), "steps": logSteps]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
                try? data.write(to: out.appendingPathComponent("fuzz-" + id + "-seed\(seed).json"))
            }
            app.terminate()
        }
        for stepIdx in 0..<steps {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let running = app.state == .runningForeground
            let snap = running ? (try? app.snapshot()) : nil
            let window = snap?.children.first(where: { $0.elementType == .window })?.frame ?? snap?.frame ?? CGRect(x: 0, y: 0, width: 393, height: 852)
            var allButtons: [XCUIElementSnapshot] = []
            if let snap { collectButtons(snap, into: &allButtons) }
            var violations: [String] = []
            if !running { violations.append("not_running_foreground") }
            for btn in allButtons.prefix(32) {
                let f = btn.frame
                if f.maxY > -2 && f.minY < window.height + 2 && (f.minX < -4 || f.maxX > window.width + 4) {
                    violations.append("control_outside_window")
                    break
                }
            }
            let buttons = allButtons.filter {
                let f = $0.frame
                return f.midX > 2 && f.midX < window.width - 2 && f.midY > 2 && f.midY < window.height - 2
            }
            let trapped = running && buttons.isEmpty
            var tapped = "none"
            if running && !buttons.isEmpty {
                let pick = Int((state >> 16) % UInt64(buttons.count))
                let target = buttons[pick]
                tapped = target.identifier.isEmpty ? target.label : target.identifier
                let pt = target.frame
                app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: pt.midX, dy: pt.midY)).tap()
                usleep(300_000)
            }
            logSteps.append(["step": stepIdx, "app_running": running, "trapped": trapped, "tapped": tapped, "layout_violations": violations])
            if !running || trapped || !violations.isEmpty {
                let failPng = XCUIScreen.main.screenshot().pngRepresentation
                try? failPng.write(to: out.appendingPathComponent("fuzz-" + id + "-fail.png"))
                break
            }
        }
    }
    @MainActor func test_fuzz_001_home_bento() { fuzzStop("home-bento", steps: 8, seed: 1) }
    @MainActor func test_fuzz_002_inbox_universal_tiles() { fuzzStop("inbox-universal-tiles", steps: 8, seed: 1) }
    @MainActor func test_fuzz_003_tasks_ideas() { fuzzStop("tasks-ideas", steps: 8, seed: 1) }
}

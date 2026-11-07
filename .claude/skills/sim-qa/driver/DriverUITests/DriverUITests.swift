import XCTest

/// A long-running UI test that drives the installed Volspire app from the shell.
///
/// The shell writes commands to `<io>/cmd.txt` (first line = a unique sequence id,
/// then one command per line); this loop runs them and writes `<io>/out.txt`
/// (first line = the same id, then each command's output). `scripts/drv.sh` wraps
/// that handshake. The io directory comes from `DRIVER_IO`, passed to the test
/// runner as `TEST_RUNNER_DRIVER_IO=...` on the xcodebuild command line.
///
/// Commands:
///   activate | launch | terminate
///   tap <label>[#n]        tap the n-th hittable element whose label/identifier matches
///   tapxy <x> <y>          tap at a point (points, window coordinates)
///   longxy <x> <y>         1s press at a point
///   drag <x1> <y1> <x2> <y2>
///   type <text>            type into the focused field
///   clear <label>          focus a field and delete its contents
///   wait <seconds>
///   swipeup | swipedown | swipeleft | swiperight
///   labels                 every labelled element: type, frame (pts), label, identifier
///   dump                   full accessibility tree
final class DriverUITests: XCTestCase {
    func testDrive() throws {
        continueAfterFailure = true
        let dir = ProcessInfo.processInfo.environment["DRIVER_IO"] ?? NSTemporaryDirectory() + "volspire-sim-qa/io"
        let app = XCUIApplication(bundleIdentifier: "com.volspire.app")
        let fm = FileManager.default
        var lastSeq = ""
        let cmdPath = dir + "/cmd.txt"
        let outPath = dir + "/out.txt"
        let deadline = Date().addingTimeInterval(60 * 60 * 3)
        while Date() < deadline {
            guard let data = fm.contents(atPath: cmdPath), let s = String(data: data, encoding: .utf8) else { usleep(200_000); continue }
            let lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let seq = lines.first, !seq.isEmpty, seq != lastSeq else { usleep(200_000); continue }
            lastSeq = seq
            var out = ""
            for line in lines.dropFirst() where !line.isEmpty {
                out += "> \(line)\n" + run(line, app) + "\n"
            }
            try? (seq + "\n" + out).write(toFile: outPath, atomically: true, encoding: .utf8)
        }
    }

    func find(_ q: String, _ app: XCUIApplication) -> XCUIElement? {
        // q: "label" or "label#index"
        var label = q; var idx = 0
        if let r = q.range(of: "#", options: .backwards), let i = Int(q[r.upperBound...]) { label = String(q[..<r.lowerBound]); idx = i }
        let pred = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        let all = app.descendants(matching: .any).matching(pred).allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        if idx < all.count { return all[idx] }
        let pred2 = NSPredicate(format: "label CONTAINS[c] %@", label)
        let all2 = app.descendants(matching: .any).matching(pred2).allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
        if idx < all2.count { return all2[idx] }
        return nil
    }

    /// Taps by coordinate rather than `element.tap()` — SwiftUI elements often
    /// fail XCUITest's own hittability/scroll-to-visible checks.
    func tapCenter(_ e: XCUIElement, _ app: XCUIApplication) -> CGRect {
        let f = e.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: f.midX, dy: f.midY)).tap()
        return f
    }

    func run(_ line: String, _ app: XCUIApplication) -> String {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let cmd = parts[0]; let arg = parts.count > 1 ? parts[1] : ""
        let n = arg.split(separator: " ").compactMap { Double($0) }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        switch cmd {
        case "activate": app.activate(); return "ok"
        case "launch": app.launch(); return "ok"
        case "terminate": app.terminate(); return "ok"
        case "tap":
            guard let e = find(arg, app) else { return "NOT FOUND" }
            let t = e.elementType.rawValue
            return "tapped \(t) \(tapCenter(e, app))"
        case "tapxy":
            guard n.count == 2 else { return "usage: tapxy x y" }
            origin.withOffset(CGVector(dx: n[0], dy: n[1])).tap(); return "ok"
        case "longxy":
            guard n.count == 2 else { return "usage: longxy x y" }
            origin.withOffset(CGVector(dx: n[0], dy: n[1])).press(forDuration: 1.0); return "ok"
        case "drag":
            guard n.count == 4 else { return "usage: drag x1 y1 x2 y2" }
            let a = origin.withOffset(CGVector(dx: n[0], dy: n[1]))
            let b = origin.withOffset(CGVector(dx: n[2], dy: n[3]))
            a.press(forDuration: 0.05, thenDragTo: b); return "ok"
        case "type":
            app.typeText(arg); return "ok"
        case "clear":
            guard let e = find(arg, app) else { return "NOT FOUND" }
            _ = tapCenter(e, app)
            if let v = e.value as? String { app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 5)) }
            return "ok"
        case "wait":
            usleep(UInt32((Double(arg) ?? 1) * 1_000_000)); return "ok"
        case "swipeup": app.swipeUp(); return "ok"
        case "swipedown": app.swipeDown(); return "ok"
        case "swipeleft": app.swipeLeft(); return "ok"
        case "swiperight": app.swipeRight(); return "ok"
        case "dump":
            return app.debugDescription
        case "labels":
            // One snapshot walk — far faster than querying descendants one by one.
            var s = ""
            guard let snap = try? app.snapshot() else { return "snap failed" }
            func walk(_ e: XCUIElementSnapshot) {
                let l = e.label; let id = e.identifier
                if !(l.isEmpty && id.isEmpty) || e.elementType == .textField || e.elementType == .secureTextField {
                    s += "\(e.elementType.rawValue)\t\(Int(e.frame.minX)),\(Int(e.frame.minY)),\(Int(e.frame.width))x\(Int(e.frame.height))\t\(l)\t\(id)\n"
                }
                for c in e.children { walk(c) }
            }
            walk(snap)
            return s
        default: return "unknown command: \(cmd)"
        }
    }
}

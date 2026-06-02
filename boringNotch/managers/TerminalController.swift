import AppKit
import CoreGraphics

// MARK: - Base

/// Abstract base for per-terminal-app controllers.
/// Subclasses handle app activation and keystroke delivery.
class TerminalController {
    let bundleIdentifier: String

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    /// Bring the terminal window that owns `claudePid` to the front.
    /// - Parameter claudePid: PID of the claude process running inside the terminal.
    func activate(claudePid: Int) {
        guard let app = runningApp() else { return }
        app.activate()
    }

    /// Send a single-digit keystroke (1-9) to the terminal after it is frontmost.
    /// Requires `AXIsProcessTrusted()` == true on the caller.
    func sendDigit(_ digit: Int) {
        guard digit >= 1, digit <= 9 else { return }
        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keyCode = keyCodes[digit - 1]
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)?.post(tap: .cgSessionEventTap)
        CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)?.post(tap: .cgSessionEventTap)
        print("[\(type(of: self))] sendDigit: sent \(digit)")
    }

    func runningApp() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }
}

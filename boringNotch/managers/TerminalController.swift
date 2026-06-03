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
    /// Uses NSWorkspace.openApplication so minimized windows are restored.
    func activate(claudePid: Int) {
        bringToFront {}
    }

    /// Activate the app (restoring minimized windows), then call `block` once frontmost.
    /// Polls `isActive` for up to 1 second before giving up.
    func activateThenRun(block: @escaping () -> Void) {
        bringToFront {
            var attempts = 0
            func poll() {
                attempts += 1
                let active = NSWorkspace.shared.runningApplications
                    .first { $0.bundleIdentifier == self.bundleIdentifier }?.isActive ?? false
                if active || attempts >= 20 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { block() }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { poll() }
                }
            }
            poll()
        }
    }

    // NSWorkspace.openApplication restores minimized windows; plain activate() does not.
    private func bringToFront(completion: @escaping () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            runningApp()?.activate()
            completion()
            return
        }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in
            DispatchQueue.main.async { completion() }
        }
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

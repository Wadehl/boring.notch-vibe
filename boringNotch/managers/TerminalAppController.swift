import AppKit
import CoreGraphics

/// Controller for macOS Terminal.app.
/// Activates the app then sends a digit via CGEvent session tap.
final class TerminalAppController: TerminalController {

    init() {
        super.init(bundleIdentifier: "com.apple.Terminal")
    }

    override func activate(claudePid: Int) {
        runningApp()?.activate()
    }

    /// Activate Terminal then deliver the digit keystroke.
    /// Caller is responsible for ensuring the digit is sent after Terminal is frontmost.
    func activateAndSend(digit: Int, completion: @escaping () -> Void) {
        guard let app = runningApp() else { return }
        app.activate()
        // Give Terminal ~400ms to become frontmost before injecting the keystroke
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.sendDigit(digit)
            completion()
        }
    }
}

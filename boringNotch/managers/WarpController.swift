import AppKit

/// Controller for Warp terminal.
/// Tab index lookup is delegated to the unsandboxed XPC Helper so the sandbox
/// cannot block access to Warp's group-container SQLite database.
final class WarpController: TerminalController {

    init() {
        super.init(bundleIdentifier: "dev.warp.Warp-Stable")
    }

    // MARK: - Activation

    /// Activate Warp and switch to the tab matching claudePid.
    func activateTab(claudePid: Int) {
        guard let app = runningApp() else {
            print("[WarpController] activateTab: Warp not running")
            return
        }
        print("[WarpController] activateTab: claudePid=\(claudePid)")
        app.activate()
        Task {
            let index = await XPCHelperClient.shared.warpTabIndex(forClaudePid: claudePid)
            print("[WarpController] activateTab: XPC returned tabIndex=\(index)")
            guard index > 0 else { return }
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("[WarpController] activateTab: sending Cmd+\(index)")
                    self.sendTabSwitch(index: index)
                }
            }
        }
    }

    /// Activate the correct Warp tab then send the option digit keystroke.
    func activateAndSend(claudePid: Int, digit: Int, completion: @escaping () -> Void) {
        guard let app = runningApp() else {
            print("[WarpController] activateAndSend: Warp not running")
            return
        }
        print("[WarpController] activateAndSend: claudePid=\(claudePid) digit=\(digit)")
        app.activate()
        Task {
            let index = await XPCHelperClient.shared.warpTabIndex(forClaudePid: claudePid)
            print("[WarpController] activateAndSend: XPC returned tabIndex=\(index)")
            await MainActor.run {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if index > 0 {
                        print("[WarpController] sending Cmd+\(index) to switch tab")
                        self.sendTabSwitch(index: index)
                    } else {
                        print("[WarpController] no valid tab index, skipping tab switch")
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        print("[WarpController] sending digit \(digit)")
                        self.sendDigit(digit)
                        completion()
                    }
                }
            }
        }
    }

    // MARK: - Tab switch keystroke

    /// Send Cmd+<index> to switch Warp tabs (index is 1-based).
    func sendTabSwitch(index: Int) {
        guard index >= 1, index <= 9 else { return }
        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let keyCode = keyCodes[index - 1]
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
        print("[WarpController] sendTabSwitch: Cmd+\(index)")
    }
}

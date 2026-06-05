//
//  BoringNotchXPCHelperProtocol.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation

/// The protocol that this service will vend as its API. This protocol will also need to be visible to the process hosting the service.
@objc protocol BoringNotchXPCHelperProtocol {
    func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void)
    func requestAccessibilityAuthorization()
    func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void)
    // Keyboard backlight / CoreBrightness access (performed by the helper)
    func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Screen brightness access (performed by the helper)
    func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void)
    func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void)
    func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void)
    // Send keystrokes to frontmost app via CGEvent (requires Accessibility, no sandbox)
    func sendKeystrokes(keyCodes: [Int32], keystrokeText: String?, targetPid: Int32, with reply: @escaping (Bool, String?) -> Void)
    // Run an AppleScript source string (no Accessibility required)
    func runAppleScript(_ source: String, with reply: @escaping (Bool, String?) -> Void)
    func writeToTty(_ ttyPath: String, byte: Int32, with reply: @escaping (Bool, String?) -> Void)
    // Query Warp's SQLite DB (unsandboxed) to get 1-based tab index for a claude pid
    func warpTabIndex(forClaudePid claudePid: Int32, with reply: @escaping (Int32) -> Void)
    // Write a file from the unsandboxed helper so it doesn't carry com.apple.quarantine
    func writeFile(atPath path: String, content: String, posixPermissions: Int32, with reply: @escaping (Bool, String?) -> Void)
}


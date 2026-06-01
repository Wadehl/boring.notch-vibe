//
//  BoringNotchXPCHelper.swift
//  BoringNotchXPCHelper
//
//  Created by Alexander on 2025-11-16.
//

import Foundation
import ApplicationServices
import IOKit
import CoreGraphics
import AppKit

class BoringNotchXPCHelper: NSObject, BoringNotchXPCHelperProtocol {
    
    @objc func isAccessibilityAuthorized(with reply: @escaping (Bool) -> Void) {
        reply(AXIsProcessTrusted())
    }

    @objc func requestAccessibilityAuthorization() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @objc func ensureAccessibilityAuthorization(_ promptIfNeeded: Bool, with reply: @escaping (Bool) -> Void) {
        if AXIsProcessTrusted() {
            reply(true)
            return
        }

        if promptIfNeeded {
            requestAccessibilityAuthorization()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            reply(AXIsProcessTrusted())
        }
    }
    
    private class KeyboardBrightnessClient {
        private static let keyboardID: UInt64 = 1
        private var clientInstance: NSObject?
        private let getSelector = NSSelectorFromString("brightnessForKeyboard:")
        private let setSelector = NSSelectorFromString("setBrightness:forKeyboard:")

        init() {
            var loaded = false
            let bundlePaths = [
                "/System/Library/PrivateFrameworks/CoreBrightness.framework",
                "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
            ]
            for path in bundlePaths where !loaded {
                if let bundle = Bundle(path: path) {
                    loaded = bundle.load()
                }
            }
            if loaded, let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
                clientInstance = cls.init()
            }
        }

        var isAvailable: Bool { clientInstance != nil }

        func currentBrightness() -> Float? {
            guard let clientInstance,
                  let fn: BrightnessGetter = methodIMP(on: clientInstance, selector: getSelector, as: BrightnessGetter.self)
            else { return nil }
            return fn(clientInstance, getSelector, Self.keyboardID)
        }

        func setBrightness(_ value: Float) -> Bool {
            guard let clientInstance,
                  let fn: BrightnessSetter = methodIMP(on: clientInstance, selector: setSelector, as: BrightnessSetter.self)
            else { return false }
            return fn(clientInstance, setSelector, value, Self.keyboardID).boolValue
        }

        private typealias BrightnessGetter = @convention(c) (NSObject, Selector, UInt64) -> Float
        private typealias BrightnessSetter = @convention(c) (NSObject, Selector, Float, UInt64) -> ObjCBool

        private func methodIMP<T>(on object: NSObject, selector: Selector, as type: T.Type) -> T? {
            guard let cls = object_getClass(object),
                  let method = class_getInstanceMethod(cls, selector)
            else { return nil }
            let imp = method_getImplementation(method)
            return unsafeBitCast(imp, to: type)
        }
    }

    private static let keyboardClient = KeyboardBrightnessClient()

    @objc func isKeyboardBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.isAvailable)
    }

    @objc func currentKeyboardBrightness(with reply: @escaping (NSNumber?) -> Void) {
        reply(Self.keyboardClient.currentBrightness().map { NSNumber(value: $0) })
    }

    @objc func setKeyboardBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        reply(Self.keyboardClient.setBrightness(value))
    }
    // MARK: - Screen Brightness (moved from client app into helper)

    @objc func isScreenBrightnessAvailable(with reply: @escaping (Bool) -> Void) {
        var b: Float = 0
        reply(displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) || ioServiceFor(displayID: CGMainDisplayID()) != nil)
    }

    @objc func currentScreenBrightness(with reply: @escaping (NSNumber?) -> Void) {
        var b: Float = 0
        if displayServicesGetBrightness(displayID: CGMainDisplayID(), out: &b) {
            reply(NSNumber(value: b))
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            var level: Float = 0
            if IODisplayGetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, &level) == kIOReturnSuccess {
                IOObjectRelease(io)
                reply(NSNumber(value: level))
                return
            }
            IOObjectRelease(io)
        }
        reply(nil)
    }

    @objc func setScreenBrightness(_ value: Float, with reply: @escaping (Bool) -> Void) {
        let clamped = max(0, min(1, value))
        if displayServicesSetBrightness(displayID: CGMainDisplayID(), value: clamped) {
            reply(true)
            return
        }
        if let io = ioServiceFor(displayID: CGMainDisplayID()) {
            let ok = IODisplaySetFloatParameter(io, 0, kIODisplayBrightnessKey as CFString, clamped) == kIOReturnSuccess
            IOObjectRelease(io)
            reply(ok)
            return
        }
        reply(false)
    }

    // MARK: - Private helpers for DisplayServices / IOKit access
    private func displayServicesGetBrightness(displayID: CGDirectDisplayID, out: inout Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesGetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        var tmp: Float = 0
        let r = fn(displayID, &tmp)
        if r == 0 { out = tmp; return true }
        return false
    }

    private func displayServicesSetBrightness(displayID: CGDirectDisplayID, value: Float) -> Bool {
        guard let sym = dlsym(DisplayServicesHandle.handle, "DisplayServicesSetBrightness") else { return false }
        typealias Fn = @convention(c) (CGDirectDisplayID, Float) -> Int32
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(displayID, value) == 0
    }

    private func ioServiceFor(displayID: CGDirectDisplayID) -> io_service_t? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
            if let vendorID = info[kDisplayVendorID] as? UInt32,
               let productID = info[kDisplayProductID] as? UInt32,
               vendorID == CGDisplayVendorNumber(displayID),
               productID == CGDisplayModelNumber(displayID) {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    @objc func sendKeystrokes(keyCodes: [Int32], keystrokeText: String?, targetPid: Int32, with reply: @escaping (Bool, String?) -> Void) {

        func postKey(_ keyCode: CGKeyCode, down: Bool) {
            let src = CGEventSource(stateID: .hidSystemState)
            let evt = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down)
            if targetPid > 0 {
                evt?.postToPid(targetPid)
            } else {
                evt?.post(tap: .cghidEventTap)
            }
        }

        func postChar(_ char: Character) {
            var utf16 = Array(String(char).utf16)
            let src = CGEventSource(stateID: .hidSystemState)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                if targetPid > 0 { down.postToPid(targetPid) } else { down.post(tap: .cghidEventTap) }
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                if targetPid > 0 { up.postToPid(targetPid) } else { up.post(tap: .cghidEventTap) }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }

        if let text = keystrokeText {
            for char in text { postChar(char) }
            // Return key (keyCode 36)
            postKey(36, down: true)
            postKey(36, down: false)
        } else {
            for code in keyCodes {
                let keyCode = CGKeyCode(code)
                postKey(keyCode, down: true)
                postKey(keyCode, down: false)
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        reply(true, nil)
    }

    @objc func writeToTty(_ ttyPath: String, byte: Int32, with reply: @escaping (Bool, String?) -> Void) {
        let fd = Darwin.open(ttyPath, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            reply(false, "open failed: \(String(cString: strerror(errno)))")
            return
        }
        defer { Darwin.close(fd) }
        var b = UInt8(byte & 0xFF)
        let written = Darwin.write(fd, &b, 1)
        if written == 1 {
            reply(true, nil)
        } else {
            reply(false, "write failed: \(String(cString: strerror(errno)))")
        }
    }

    @objc func activateAndSendKey(bundleId: String, keyCode: Int32, delayMs: Int32, with reply: @escaping (Bool, String?) -> Void) {
        let appName: String
        switch bundleId {
        case "com.apple.Terminal": appName = "Terminal"
        case "com.googlecode.iterm2": appName = "iTerm2"
        default: appName = bundleId
        }

        let script = """
        tell application "\(appName)"
            activate
        end tell
        delay \(Double(delayMs) / 1000.0)
        tell application "System Events"
            tell process "\(appName)"
                keystroke "\(keyCode)"
            end tell
        end tell
        """

        // Map keyCode back to character for keystroke
        let keyCharMap: [Int32: String] = [18:"1",19:"2",20:"3",21:"4",23:"5",22:"6",26:"7",28:"8",25:"9"]
        let keystrokeChar = keyCharMap[keyCode] ?? "1"

        let finalScript = """
        tell application "\(appName)"
            activate
        end tell
        delay \(Double(delayMs) / 1000.0)
        tell application "System Events"
            tell process "\(appName)"
                keystroke "\(keystrokeChar)"
            end tell
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", finalScript]
        let pipe = Pipe()
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if process.terminationStatus == 0 {
                reply(true, nil)
            } else {
                reply(false, errStr.isEmpty ? "osascript failed" : errStr)
            }
        } catch {
            reply(false, error.localizedDescription)
        }
    }


    @objc func runAppleScript(_ source: String, with reply: @escaping (Bool, String?) -> Void) {
        guard let script = NSAppleScript(source: source) else {
            reply(false, "Failed to create NSAppleScript")
            return
        }
        var errorDict: NSDictionary?
        script.executeAndReturnError(&errorDict)
        if let err = errorDict {
            let msg = err[NSAppleScript.errorMessage] as? String ?? err.description
            print("[XPCHelper] AppleScript error: \(err)")
            reply(false, msg)
        } else {
            reply(true, nil)
        }
    }

    // MARK: - Helper handle for private framework
    private enum DisplayServicesHandle {
        static let handle: UnsafeMutableRawPointer? = {
            let paths = [
                "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
                "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/Current/DisplayServices"
            ]
            for p in paths {
                if let h = dlopen(p, RTLD_LAZY) { return h }
            }
            return nil
        }()
    }
}

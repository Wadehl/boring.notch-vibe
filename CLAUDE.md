# boring.notch-vibe — Dev Notes

## Packaging (DMG)

The project uses ad-hoc code signing (`CODE_SIGN_IDENTITY[sdk=macosx*] = "-"`). After building, `MediaRemoteAdapter.framework` and other bundled frameworks carry a third-party Team ID that conflicts with ad-hoc signing, causing dyld to silently refuse to launch the app.

**Always re-sign the entire bundle after build, before packaging:**

```bash
APP="build/DerivedData/Build/Products/Release/boringNotch.app"

# 1. Re-sign with ad-hoc to unify Team ID across all nested frameworks
codesign --force --deep --sign - "$APP"

# 2. Clear quarantine so users don't get Gatekeeper blocked
xattr -dr com.apple.quarantine "$APP"

# 3. Package
STAGING="/tmp/boringNotch_dmg_staging"
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/boringNotch.app"
codesign --force --deep --sign - "$STAGING/boringNotch.app"
xattr -dr com.apple.quarantine "$STAGING/boringNotch.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "boringNotch" -srcfolder "$STAGING" -ov -format UDZO build/boringNotch.dmg
xattr -dr com.apple.quarantine build/boringNotch.dmg
cp build/boringNotch.dmg ~/Desktop/boringNotch.dmg
```

## Architecture: XPC Helper & Accessibility

The app uses `BoringNotchXPCHelper` (unsandboxed) for:
- **Accessibility permission prompt** — `AXIsProcessTrustedWithOptions(prompt:true)` must be called from a non-sandboxed process; the main app is sandboxed and the call silently fails there.
- **Keystroke injection** — `CGEvent.post(tap: .cghidEventTap)` requires Accessibility on the *calling* process (the XPC helper).
- **File writes without quarantine** — files written by the sandboxed main app get `com.apple.quarantine`; the XPC helper writes them clean.

**Do not move these to the main app process.** The main app is sandboxed (`com.apple.security.app-sandbox = true`).

### Why rebuilding breaks Accessibility auth (dev only)

The XPC helper is ad-hoc signed, so its TCC entry is keyed by binary hash. Every rebuild changes the hash → TCC no longer recognises it → Accessibility appears ungranted. This only affects local dev builds. Distributed DMG builds are stable because the binary doesn't change.

Workaround during development: after granting Accessibility, avoid rebuilding the XPC helper target unnecessarily, or re-grant via System Settings each time.

## Vibe-specific features (on top of upstream boringNotch)

- **AgentStatusManager** — watches Claude Code sessions via hook JSONL events and `~/.claude/projects/` JSONL files.
- **AgentInteractionView** — notch UI for permission prompts, plan approvals, and completion cards.
- **Hooks** — `on-event.sh` written by XPC helper (no quarantine), injected into `~/.claude/settings.json`.
- **Right-click notch** → Settings / Quit boringNotch.
- **Completion card** — title = user message, body = last pure-text assistant reply; tapping jumps to terminal then dismisses.
- **Auto-close notch** when all pending interactions are dismissed.

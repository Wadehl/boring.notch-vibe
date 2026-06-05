# boringNotch · Vibe Edition

> Built on top of [boring.notch](https://github.com/TheBoredTeam/boring.notch) — all original features intact, plus native AI agent integration.

---

## What's New in Vibe Edition

### Claude Code — Full Support ✅

boringNotch now acts as a live HUD for Claude Code sessions running in your terminal. No extra setup beyond installing the hooks (one-click from Settings → Claude Code).

**Features:**
- **Permission prompts** — when Claude Code asks to run a tool, the notch opens with the options (Yes / No / Always Allow). Click to answer, or use auto-input to send the keystroke directly to the terminal.
- **Plan approval** — ExitPlanMode prompts surface in the notch with the plan title and Approve / Reject options.
- **Completion card** — when a Claude Code session finishes, the notch shows the user's original message as the title and Claude's final reply as the body. Tap to jump back to the terminal.
- **Auto-close** — the notch returns to its closed state automatically once all interactions are dismissed.
- **Session tracking** — Settings → Claude Code shows all active Claude Code sessions with status (running / idle), working directory, and terminal app.

**Supported terminals:**
| Terminal | Auto-input | Tab focus |
|----------|-----------|-----------|
| Warp | ✅ | ✅ |
| Terminal.app | ✅ | ✅ |
| Others (iTerm2, etc.) | — | ✅ (window focus) |

**Hook setup:**
Settings → Claude Code → one-click install. Hooks are written to `~/.claude/settings.json` and the script to `~/.claude/boringnotch/hooks/on-event.sh`. A status panel shows whether each hook is active, with a one-click fix button if anything is misconfigured.

---

### Warp — Full Support ✅

Warp terminal is fully supported for auto-input and tab focus. boringNotch reads Warp's session metadata to identify which tab is running Claude Code and switches to it automatically when you respond to a prompt.

---

### Roadmap — Coming Soon

| Agent | Status | Notes |
|-------|--------|-------|
| **Codex** | 🚧 In progress | Reads `~/.codex/logs_2.sqlite`; interaction interception not yet supported |
| **Cursor** | 📋 Planned | — |
| **Other MCP agents** | 📋 Planned | — |

---

## Installation

1. Download `boringNotch.dmg` from Releases
2. Open the DMG and drag `boringNotch.app` to **Applications**
3. Run the included **Fix Quarantine** script (double-click), or run manually:
   ```bash
   xattr -dr com.apple.quarantine /Applications/boringNotch.app
   ```
4. Open `boringNotch.app` normally
5. Go to **Settings → Claude Code** and click **一键修复** to install hooks

> The quarantine step is required because the app is not notarized. This is a one-time step after installation.

---

## Accessibility Permission

boringNotch needs Accessibility permission to send keystrokes to your terminal when you respond to a Claude Code prompt.

- On first launch, you'll see a prompt — click **Request Accessibility** and grant it in System Settings
- After granting, the **Warp / 终端权限** section in Settings → Claude Code will show a green checkmark
- This permission is granted to `BoringNotchXPCHelper` (the helper process that handles keystrokes), not the main app — this is intentional and matches the upstream boringNotch design

---

## Original boringNotch Features

All upstream features are preserved:

- 🎵 Music controls & visualizer (Spotify, Apple Music, Now Playing)
- 📅 Calendar integration
- 📁 File shelf with AirDrop support
- 🖥️ System HUD replacement (volume, brightness)
- 🔔 Notification mirroring
- Multi-display support

# Agent Status Watcher — Design Spec

**Date:** 2026-05-31  
**Status:** Approved

---

## Overview

Extend boring.notch to display Claude Code and Codex agent task status in the notch area, similar to Dynamic Island notifications. The feature shows three states: running, waiting for input, and completed.

---

## Architecture

### Phase 1 — Feasibility (Python, throwaway)

```
agent-watcher/
  agent_watcher.py    # One-off proof-of-concept, prints state changes to terminal
```

Validates that the two data sources are reliable and the status mapping is correct. Not integrated into the app.

### Phase 2 — Production (Swift, in-app)

```
boringNotch/
  managers/
    AgentStatusManager.swift  # mirrors NowPlayingController pattern
  components/Notch/
    AgentStatusView.swift     # notch UI chip
```

### Data Flow (Phase 2)

```
~/.claude/sessions/*.json   ──┐
                              ├──► AgentStatusManager.swift ──► @Published agentSessions ──► SwiftUI
~/.codex/goals_1.sqlite     ──┘
```

Uses `DispatchSource.makeFileSystemObjectSource` for file watching (same approach as existing observers), plus a 1s timer fallback for SQLite.

---

## Data Sources

### Claude Code
- **File:** `~/.claude/sessions/<pid>.json`
- **Poll interval:** 1s
- **Key fields:** `pid`, `status` (`"busy"` | others), `cwd`, `updatedAt`, `sessionId`
- **Process check:** verify `pid` is still alive via `os.kill(pid, 0)`

### Codex
- **File:** `~/.codex/goals_1.sqlite`
- **Poll interval:** 1s
- **Table:** `thread_goals`
- **Key fields:** `thread_id`, `status` (`active` | `paused` | `blocked` | `complete`), `objective`, `updated_at_ms`

---

## Status Mapping

| Source | Raw Value | Unified Status | Notch Display |
|--------|-----------|----------------|---------------|
| Claude | `busy` | `running` | spinner animation |
| Claude | any non-busy / process gone | `waiting` or `done` | pause icon / checkmark |
| Codex | `active` | `running` | spinner animation |
| Codex | `paused`, `blocked`, `usage_limited`, `budget_limited` | `waiting` | pause icon |
| Codex | `complete` | `done` | checkmark |

---

## agent_watcher.py (Phase 1 — Throwaway)

- Polls both sources every 1 second
- Prints state changes to terminal (human-readable)
- On startup, prints current state of all active sessions
- No external dependencies — stdlib only (`json`, `sqlite3`, `os`, `pathlib`, `time`)
- Discarded after feasibility is confirmed

---

## Swift Integration (Phase 2 — Production)

`AgentStatusManager` implements the logic natively in Swift:

1. `DispatchSource.makeFileSystemObjectSource` watches `~/.claude/sessions/` for file changes (instant response)
2. 1s polling timer for `~/.codex/goals_1.sqlite` (SQLite WAL makes FSEvents unreliable)
3. `@Published var agentSessions: [AgentSession]` triggers SwiftUI refresh
4. `NotchHomeView` shows an agent status chip when any session is `running` or `waiting`

---

## Out of Scope (v1)

- Real-time log tailing / output preview
- Token usage display
- Multi-screen support
- Notifications / sounds

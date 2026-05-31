#!/usr/bin/env python3
"""
Feasibility probe: watches Claude Code and Codex agent status.
Prints state changes to terminal. Throwaway — logic will be rewritten in Swift.
"""

import json
import os
import sqlite3
import time
from pathlib import Path

CLAUDE_SESSIONS_DIR = Path.home() / ".claude" / "sessions"
CODEX_LOGS_DB = Path.home() / ".codex" / "logs_2.sqlite"
POLL_INTERVAL = 1.0

# A thread is considered "idle" if its last log entry is older than this
CODEX_IDLE_THRESHOLD_S = 5


def process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def claude_status(raw: str, pid: int) -> str:
    if not process_alive(pid):
        return "done"
    if raw == "busy":
        return "running"
    return "idle"


def read_claude_sessions() -> dict:
    """Returns {pid: status_dict}"""
    sessions = {}
    if not CLAUDE_SESSIONS_DIR.exists():
        return sessions
    for f in CLAUDE_SESSIONS_DIR.glob("*.json"):
        try:
            data = json.loads(f.read_text())
            pid = data.get("pid")
            if not pid:
                continue
            sessions[pid] = {
                "app": "claude-code",
                "pid": pid,
                "status": claude_status(data.get("status", ""), pid),
                "cwd": data.get("cwd", ""),
                "updatedAt": data.get("updatedAt", 0),
            }
        except Exception:
            pass
    return sessions


def read_codex_sessions() -> dict:
    """Returns {thread_id: status_dict} by reading recent log activity from logs_2.sqlite.
    A thread with log activity in the last CODEX_IDLE_THRESHOLD_S seconds is 'running',
    otherwise 'idle'. Threads with no logs in the last 60s are dropped from results.
    """
    sessions = {}
    if not CODEX_LOGS_DB.exists():
        return sessions
    try:
        now_s = int(time.time())
        cutoff_active = now_s - CODEX_IDLE_THRESHOLD_S
        cutoff_visible = now_s - 60  # stop showing threads quiet for >60s

        con = sqlite3.connect(f"file:{CODEX_LOGS_DB}?mode=ro", uri=True, timeout=1)
        con.row_factory = sqlite3.Row
        # Extract thread_id from the structured log body and get last-seen timestamp
        rows = con.execute("""
            SELECT
                SUBSTR(feedback_log_body,
                    INSTR(feedback_log_body, 'thread_id=') + 10, 36) AS thread_id,
                MAX(ts) AS last_ts
            FROM logs
            WHERE feedback_log_body LIKE '%thread_id=%'
              AND ts >= ?
            GROUP BY thread_id
            HAVING LENGTH(thread_id) = 36
            ORDER BY last_ts DESC
            LIMIT 20
        """, (cutoff_visible,)).fetchall()
        con.close()

        for row in rows:
            tid = row["thread_id"]
            last_ts = row["last_ts"]
            status = "running" if last_ts >= cutoff_active else "idle"
            sessions[tid] = {
                "app": "codex",
                "threadId": tid,
                "status": status,
                "updatedAt": last_ts,
            }
    except Exception as e:
        print(f"[codex] db error: {e}")
    return sessions


STATUS_ICON = {"running": "⚙️  running", "idle": "⏸  idle", "done": "✅ done"}


def fmt(session: dict) -> str:
    icon = STATUS_ICON.get(session["status"], session["status"])
    if session["app"] == "claude-code":
        cwd = Path(session["cwd"]).name or session["cwd"]
        return f"[claude-code pid={session['pid']}] {icon}  ({cwd})"
    else:
        tid = session["threadId"][:8]
        return f"[codex tid={tid}] {icon}"


def main():
    print("Agent Watcher started — polling every 1s. Ctrl+C to stop.\n")

    prev_claude: dict = {}
    prev_codex: dict = {}

    # Print initial state
    initial_claude = read_claude_sessions()
    initial_codex = read_codex_sessions()

    if not initial_claude and not initial_codex:
        print("(no active claude-code or codex sessions found)")
    else:
        for s in initial_claude.values():
            print(f"  {fmt(s)}")
        for s in initial_codex.values():
            print(f"  {fmt(s)}")
        print()

    prev_claude = initial_claude
    prev_codex = initial_codex

    try:
        while True:
            time.sleep(POLL_INTERVAL)

            cur_claude = read_claude_sessions()
            cur_codex = read_codex_sessions()

            # Detect Claude changes — only emit when status changes for a given pid
            all_pids = set(prev_claude) | set(cur_claude)
            for pid in all_pids:
                prev = prev_claude.get(pid)
                cur = cur_claude.get(pid)
                if cur is None:
                    # session file removed — process gone
                    if prev and prev["status"] != "done":
                        print(f"  {fmt({**prev, 'status': 'done'})}  [session ended]")
                elif prev is None or prev["status"] != cur["status"]:
                    print(f"  {fmt(cur)}")

            # Detect Codex changes — only emit when status changes for a given thread
            all_threads = set(prev_codex) | set(cur_codex)
            for tid in all_threads:
                prev = prev_codex.get(tid)
                cur = cur_codex.get(tid)
                if cur is None:
                    pass  # row won't disappear from DB
                elif prev is None or prev["status"] != cur["status"]:
                    print(f"  {fmt(cur)}")

            prev_claude = cur_claude
            prev_codex = cur_codex

    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()

//
//  AgentStatusManager.swift
//  boringNotch
//

import Combine
import Foundation
import SQLite3

// MARK: - Models

enum AgentApp: String {
    case claudeCode = "claude-code"
    case codex = "codex"
}

enum AgentStatus: String {
    case running
    case idle
    case done
}

struct AgentSession: Identifiable, Equatable {
    let id: String           // pid (claude) or threadId (codex)
    let app: AgentApp
    var status: AgentStatus
    var cwd: String?         // claude-code only
    var sessionId: String?   // claude-code sessionId for summary lookup
    var summary: String?     // latest user message as task summary
    var updatedAt: Date
}

// MARK: - Manager

@MainActor
final class AgentStatusManager: ObservableObject {

    static let shared = AgentStatusManager()

    @Published private(set) var sessions: [AgentSession] = []

    /// Summary of the most recently active Claude Code session
    var activeSessionSummary: String? {
        sessions.first { $0.status == .running && $0.app == .claudeCode }?.summary
        ?? sessions.first { $0.status == .idle && $0.app == .claudeCode }?.summary
    }

    var activeSessions: [AgentSession] {
        sessions.filter { $0.status != .done }
    }

    // App runs in a sandbox so homeDirectoryForCurrentUser returns the container path.
    // Use the real user home via getpwuid instead.
    private static var realHomeURL: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private let claudeSessionsDir: URL
    private let codexLogsDB: URL

    // DispatchSource watching ~/.claude/sessions/ for file changes
    private var claudeDirSource: DispatchSourceFileSystemObject?
    private var claudeDirFD: Int32 = -1

    // Timer for Codex SQLite polling (WAL makes FSEvents unreliable)
    private var codexTimer: DispatchSourceTimer?

    private let queue = DispatchQueue(label: "com.boringnotch.agentStatusManager", qos: .utility)

    // Codex: thread is "running" if it logged within this interval
    private let codexActiveThresholdSeconds: TimeInterval = 5
    // Codex: stop tracking threads silent for this long
    private let codexDropThresholdSeconds: TimeInterval = 60

    private init() {
        let home = Self.realHomeURL
        claudeSessionsDir = home.appendingPathComponent(".claude/sessions")
        codexLogsDB = home.appendingPathComponent(".codex/logs_2.sqlite")
        startClaudeWatcher()
        startCodexPoller()
    }

    deinit {
        claudeDirSource?.cancel()
        if claudeDirFD >= 0 { Darwin.close(claudeDirFD) }
        codexTimer?.cancel()
    }

    // MARK: - Claude Code

    private func startClaudeWatcher() {
        let path = claudeSessionsDir.path

        // Initial read — hop to main actor explicitly to satisfy isolation
        Task { @MainActor in self.refreshClaudeSessions() }

        // Watch the directory for any file changes
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        claudeDirFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in self?.refreshClaudeSessions() }
        }
        source.resume()
        claudeDirSource = source
    }

    private func refreshClaudeSessions() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: claudeSessionsDir,
            includingPropertiesForKeys: nil
        ) else {
            updateSessions(removing: .claudeCode, with: [])
            return
        }

        var updated: [AgentSession] = []
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        for file in jsonFiles {
            guard
                let data = try? Data(contentsOf: file),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let pid = json["pid"] as? Int
            else { continue }

            let rawStatus = json["status"] as? String ?? ""
            let cwd = json["cwd"] as? String
            let sessionId = json["sessionId"] as? String
            let updatedAtMs = json["updatedAt"] as? Double ?? 0
            let updatedAt = Date(timeIntervalSince1970: updatedAtMs / 1000)

            let status: AgentStatus
            if !isProcessAlive(pid: pid) {
                status = .done
            } else if rawStatus == "busy" {
                status = .running
            } else {
                status = .idle
            }

            let summary = sessionId.flatMap { readClaudeSummary(cwd: cwd, sessionId: $0) }

            updated.append(AgentSession(
                id: String(pid),
                app: .claudeCode,
                status: status,
                cwd: cwd,
                sessionId: sessionId,
                summary: summary,
                updatedAt: updatedAt
            ))
        }

        updateSessions(removing: .claudeCode, with: updated)
    }

    /// Reads the latest user message from the session JSONL as a task summary.
    private func readClaudeSummary(cwd: String?, sessionId: String) -> String? {
        // Session JSONL lives at ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl
        guard let cwd else { return nil }
        let encodedCwd = cwd.replacingOccurrences(of: "/", with: "-")
        let projectDir = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
        let jsonlFile = projectDir.appendingPathComponent("\(sessionId).jsonl")

        guard let content = try? String(contentsOf: jsonlFile, encoding: .utf8) else { return nil }

        var lastUserText: String?
        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "user",
                  let message = json["message"] as? [String: Any],
                  let contentVal = message["content"]
            else { continue }

            var text = ""
            if let str = contentVal as? String {
                text = str
            } else if let arr = contentVal as? [[String: Any]] {
                text = arr.compactMap { c -> String? in
                    guard c["type"] as? String == "text" else { return nil }
                    return c["text"] as? String
                }.joined(separator: " ")
            }

            // Skip image-only messages
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("[Image") {
                lastUserText = trimmed
                break
            }
        }
        return lastUserText.map { String($0.prefix(80)) }
    }

    // MARK: - Codex

    private func startCodexPoller() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.refreshCodexSessions()
        }
        timer.resume()
        codexTimer = timer
    }

    private func refreshCodexSessions() {
        let dbPath = codexLogsDB.path
        var db: OpaquePointer?

        // Open read-only
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            return
        }
        defer { sqlite3_close(db) }

        let nowTs = Int64(Date().timeIntervalSince1970)
        let cutoffActive = nowTs - Int64(codexActiveThresholdSeconds)
        let cutoffVisible = nowTs - Int64(codexDropThresholdSeconds)

        let sql = """
            SELECT
                SUBSTR(feedback_log_body,
                    INSTR(feedback_log_body, 'thread_id=') + 10, 36) AS thread_id,
                MAX(ts) AS last_ts
            FROM logs
            WHERE feedback_log_body LIKE '%thread_id=%'
              AND ts >= \(cutoffVisible)
            GROUP BY thread_id
            HAVING LENGTH(thread_id) = 36
            ORDER BY last_ts DESC
            LIMIT 20
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        var updated: [AgentSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard
                let tidPtr = sqlite3_column_text(statement, 0)
            else { continue }

            let tid = String(cString: tidPtr)
            let lastTs = sqlite3_column_int64(statement, 1)
            let status: AgentStatus = lastTs >= cutoffActive ? .running : .idle

            updated.append(AgentSession(
                id: tid,
                app: .codex,
                status: status,
                cwd: nil,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(lastTs))
            ))
        }

        updateSessions(removing: .codex, with: updated)
    }

    // MARK: - Helpers

    private func updateSessions(removing app: AgentApp, with newSessions: [AgentSession]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var kept = self.sessions.filter { $0.app != app }
            // Drop "done" claude sessions after a short grace period (they've already exited)
            let visible = newSessions.filter { $0.status != .done || $0.app == .claudeCode }
            kept.append(contentsOf: visible)
            self.sessions = kept
        }
    }

    private func isProcessAlive(pid: Int) -> Bool {
        Darwin.kill(Int32(pid), 0) == 0 || errno == EPERM
    }
}

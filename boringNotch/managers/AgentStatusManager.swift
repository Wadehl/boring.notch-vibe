//
//  AgentStatusManager.swift
//  boringNotch
//

import Combine
import Foundation
import SQLite3
import AppKit

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

enum PendingInteractionType: Equatable {
    case question       // AskUserQuestion
    case planApproval   // ExitPlanMode
    case permission     // tool permission prompt (y/n/a)
}

struct PendingInteractionOption: Equatable {
    let label: String
    let description: String
    var keystrokeText: String?  // if set, send this text directly instead of arrow+enter
}

struct PendingInteraction: Equatable {
    let sessionId: String
    let pid: Int               // claude process pid, for terminal focus
    let sessionSummary: String?
    let type: PendingInteractionType
    // For AskUserQuestion
    let question: String?
    let header: String?
    let options: [PendingInteractionOption]
    let multiSelect: Bool
    // For ExitPlanMode
    let planTitle: String?
    // For JSONL-based reply (multiSelect)
    let toolUseId: String?     // id of the tool_use block to answer
    let assistantUuid: String? // uuid of the assistant message (becomes parentUuid)
    let cwd: String?           // working dir, needed to locate the JSONL file
    let claudeVersion: String? // version field written into the JSONL line
}

struct AgentSession: Identifiable, Equatable {
    let id: String           // pid (claude) or threadId (codex)
    let app: AgentApp
    var status: AgentStatus
    var cwd: String?         // claude-code only
    var sessionId: String?   // claude-code sessionId for summary lookup
    var summary: String?     // session title / first prompt
    var lastUserMessage: String?  // most recent user message (truncated)
    var terminalAppName: String?  // e.g. "Warp", "iTerm2", "Terminal"
    var startedAt: Date
    var updatedAt: Date
}

// MARK: - Manager

@MainActor
final class AgentStatusManager: ObservableObject {

    static let shared = AgentStatusManager()

    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var pendingInteractions: [PendingInteraction] = []

    // Keys of interactions the user has dismissed; suppressed until a new one arrives
    private var dismissedInteractionKeys: Set<String> = []

    var pendingInteraction: PendingInteraction? { pendingInteractions.first }

    func dismissPendingInteraction(sessionId: String? = nil) {
        if let sessionId {
            if let idx = pendingInteractions.firstIndex(where: { $0.sessionId == sessionId }) {
                let key = "\(pendingInteractions[idx].sessionId)-\(pendingInteractions[idx].type)"
                dismissedInteractionKeys.insert(key)
                pendingInteractions.remove(at: idx)
            }
        } else {
            // Legacy: dismiss first
            if let first = pendingInteractions.first {
                dismissedInteractionKeys.insert("\(first.sessionId)-\(first.type)")
                pendingInteractions.removeFirst()
            }
        }
    }

    private let warpController = WarpController()
    private let terminalAppController = TerminalAppController()

    func selectOption(claudePid: Int, optionIndex: Int, sessionId: String? = nil) {
        print("[AgentStatusManager] selectOption index=\(optionIndex) claudePid=\(claudePid)")
        guard let terminal = terminalRunningApp(forPid: claudePid) else { return }
        let bundleId = terminal.bundleIdentifier ?? ""
        let digit = optionIndex + 1

        if bundleId == "com.apple.Terminal" {
            guard AXIsProcessTrusted() else {
                XPCHelperClient.shared.requestAccessibilityAuthorization()
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = "请在系统设置中允许 boringNotch 使用辅助功能，然后重启 boringNotch 以生效。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好的")
                alert.runModal()
                return
            }
            terminalAppController.activateAndSend(digit: digit) {}
        } else if bundleId.hasPrefix("dev.warp.") {
            guard AXIsProcessTrusted() else {
                XPCHelperClient.shared.requestAccessibilityAuthorization()
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = "请在系统设置中允许 boringNotch 使用辅助功能，然后重启 boringNotch 以生效。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好的")
                alert.runModal()
                return
            }
            warpController.activateAndSend(claudePid: claudePid, digit: digit) {}
        } else {
            focusTerminal(claudePid: claudePid, sessionId: sessionId, dismissOnSuccess: false)
        }
    }

    func sendMultiSelectAndFocus(claudePid: Int, optionIndices: [Int], sessionId: String?) {
        guard let terminal = terminalRunningApp(forPid: claudePid) else { return }
        guard AXIsProcessTrusted() else {
            XPCHelperClient.shared.requestAccessibilityAuthorization()
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "请在系统设置中允许 boringNotch 使用辅助功能，然后重启 boringNotch 以生效。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
        let bundleId = terminal.bundleIdentifier ?? ""
        let digits = optionIndices.map { $0 + 1 }

        if bundleId.hasPrefix("dev.warp.") {
            // Activate warp tab, then send all digits in sequence
            Task {
                let index = await XPCHelperClient.shared.warpTabIndex(forClaudePid: claudePid)
                await MainActor.run {
                    guard let app = self.warpController.runningApp() else { return }
                    app.activate()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if index > 0 { self.warpController.sendTabSwitch(index: index) }
                        var delay = index > 0 ? 0.3 : 0.0
                        for digit in digits {
                            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                                self.warpController.sendDigit(digit)
                            }
                            delay += 0.05
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.dismissPendingInteraction(sessionId: sessionId)
                        }
                    }
                }
            }
        } else if bundleId == "com.apple.Terminal" {
            terminalAppController.activate(claudePid: claudePid)
            var delay = 0.15
            for digit in digits {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    self.terminalAppController.sendDigit(digit)
                }
                delay += 0.05
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                self.dismissPendingInteraction(sessionId: sessionId)
            }
        } else {
            focusTerminal(claudePid: claudePid, sessionId: sessionId, dismissOnSuccess: true)
        }
    }

    func focusTerminal(claudePid: Int, sessionId: String? = nil, dismissOnSuccess: Bool = false) {
        print("[AgentStatusManager] focusTerminal called, claudePid=\(claudePid)")
        guard let terminal = terminalRunningApp(forPid: claudePid) else {
            print("[AgentStatusManager] ERROR: no terminal found for pid=\(claudePid)")
            return
        }
        let bundleId = terminal.bundleIdentifier ?? ""

        if bundleId.hasPrefix("dev.warp.") {
            warpController.activateTab(claudePid: claudePid)
        } else if bundleId == "com.apple.Terminal" {
            terminalAppController.activate(claudePid: claudePid)
        } else {
            activateAppByURL(terminal: terminal)
        }
        if dismissOnSuccess { dismissPendingInteraction(sessionId: sessionId) }
    }

    /// Writes a tool_result line directly into the session JSONL for multiSelect answers.
    /// `selectedLabels` is the ordered list of chosen option labels (comma-space joined).
    func submitMultiSelectAnswer(interaction: PendingInteraction, selectedLabels: [String]) {
        guard interaction.multiSelect,
              let toolUseId = interaction.toolUseId,
              let assistantUuid = interaction.assistantUuid,
              let cwd = interaction.cwd
        else { return }

        let questionText = interaction.question ?? ""
        let answersJoined = selectedLabels.joined(separator: ", ")

        // Build the content string matching Claude Code's format
        let contentStr = "Your questions have been answered: \"\(questionText)\"=\"\(answersJoined)\". You can now continue with these answers in mind."

        // Reconstruct the questions array for toolUseResult
        let questionsArray: [[String: Any]] = [[
            "question": questionText,
            "header": interaction.header ?? "",
            "multiSelect": true,
            "options": interaction.options.map { ["label": $0.label, "description": $0.description] }
        ]]

        let now = ISO8601DateFormatter().string(from: Date())
        let lineObj: [String: Any] = [
            "parentUuid": assistantUuid,
            "isSidechain": false,
            "promptId": UUID().uuidString,
            "type": "user",
            "message": [
                "role": "user",
                "content": [[
                    "type": "tool_result",
                    "content": contentStr,
                    "tool_use_id": toolUseId
                ] as [String: Any]]
            ] as [String: Any],
            "uuid": UUID().uuidString,
            "timestamp": now,
            "toolUseResult": [
                "questions": questionsArray,
                "answers": [questionText: answersJoined]
            ] as [String: Any],
            "sourceToolAssistantUUID": assistantUuid,
            "userType": "external",
            "entrypoint": "cli",
            "cwd": cwd,
            "sessionId": interaction.sessionId,
            "version": interaction.claudeVersion ?? "2.1.150",
        ]

        guard let lineData = try? JSONSerialization.data(withJSONObject: lineObj),
              var lineStr = String(data: lineData, encoding: .utf8)
        else { return }
        lineStr += "\n"

        let encodedCwd = encodeCwd(cwd)
        let jsonlFile = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
            .appendingPathComponent("\(interaction.sessionId).jsonl")

        queue.async {
            guard let fileHandle = try? FileHandle(forWritingTo: jsonlFile) else {
                print("[AgentStatusManager] submitMultiSelectAnswer: cannot open \(jsonlFile.path)")
                return
            }
            defer { fileHandle.closeFile() }
            fileHandle.seekToEndOfFile()
            if let data = lineStr.data(using: .utf8) {
                fileHandle.write(data)
                print("[AgentStatusManager] submitMultiSelectAnswer: wrote answer '\(answersJoined)' to \(jsonlFile.lastPathComponent)")
            }
            DispatchQueue.main.async { [weak self] in
                self?.dismissPendingInteraction(sessionId: interaction.sessionId)
            }
        }
    }

    private func activateAppByURL(terminal: NSRunningApplication) {
        if let bundleId = terminal.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
                if let error { print("[AgentStatusManager] NSWorkspace open error: \(error)") }
            }
        } else {
            terminal.activate()
        }
    }

    private func terminalRunningApp(forPid pid: Int) -> NSRunningApplication? {
        var searchPid = Int32(pid)
        for _ in 0..<12 {
            guard searchPid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: searchPid),
               let bundleId = app.bundleIdentifier,
               Self.knownTerminals[bundleId] != nil {
                return app
            }
            var kinfo = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, searchPid]
            guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 else { break }
            searchPid = kinfo.kp_eproc.e_ppid
        }
        return nil
    }

    /// Summary of the most recently active Claude Code session
    var activeSessionSummary: String? {
        sessions.first { $0.status == .running && $0.app == .claudeCode }?.summary
        ?? sessions.first { $0.status == .idle && $0.app == .claudeCode }?.summary
        ?? sessions.first { $0.status == .running }?.summary
        ?? sessions.first { $0.status == .idle }?.summary
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
    private let codexSessionIndex: URL

    // DispatchSource watching ~/.claude/sessions/ for file changes
    private var claudeDirSource: DispatchSourceFileSystemObject?
    private var claudeDirFD: Int32 = -1

    // Polling timer for Claude session JSON (catches waitingFor changes missed by FSEvents)
    private var claudePollingTimer: DispatchSourceTimer?

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
        codexSessionIndex = home.appendingPathComponent(".codex/session_index.jsonl")
        startClaudeWatcher()
        startClaudePoller()
        startCodexPoller()
    }

    deinit {
        claudeDirSource?.cancel()
        if claudeDirFD >= 0 { Darwin.close(claudeDirFD) }
        claudePollingTimer?.cancel()
        codexTimer?.cancel()
    }

    // MARK: - Claude Code

    private func startClaudeWatcher() {
        let path = claudeSessionsDir.path

        // Initial read
        Task { self.refreshClaudeSessionsBackground() }

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
            guard let self else { return }
            Task { self.refreshClaudeSessionsBackground() }
        }
        source.resume()
        claudeDirSource = source
    }

    // Poll every 2s as a fallback — FSEvents may miss in-place file rewrites
    private func startClaudePoller() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2.0)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            Task { self.refreshClaudeSessionsBackground() }
        }
        timer.resume()
        claudePollingTimer = timer
    }

    private func refreshClaudeSessionsBackground() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: claudeSessionsDir,
            includingPropertiesForKeys: nil
        ) else {
            updateSessions(removing: .claudeCode, with: [])
            return
        }

        var updated: [AgentSession] = []
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        // pid → waitingFor string from session json (for permission prompt detection)
        var sessionWaitingFor: [Int: String] = [:]

        for file in jsonFiles {
            guard
                let data = try? Data(contentsOf: file),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let pid = json["pid"] as? Int
            else { continue }

            let rawStatus = json["status"] as? String ?? ""
            let waitingFor = json["waitingFor"] as? String
            let cwd = json["cwd"] as? String
            let sessionId = json["sessionId"] as? String
            let startedAtMs = json["startedAt"] as? Double ?? 0
            let startedAt = Date(timeIntervalSince1970: startedAtMs / 1000)
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

            if let wf = waitingFor { sessionWaitingFor[pid] = wf }

            // Title from sessions-index firstPrompt; last user message as subtitle
            let summary = sessionId.flatMap { sid in
                readClaudeSessionTitle(cwd: cwd, sessionId: sid)
                ?? readClaudeSummary(cwd: cwd, sessionId: sid)
            }
            let lastUserMessage = sessionId.flatMap { sid in
                readClaudeSummary(cwd: cwd, sessionId: sid)
            }
            let terminalName = terminalAppName(forPid: pid)

            updated.append(AgentSession(
                id: String(pid),
                app: .claudeCode,
                status: status,
                cwd: cwd,
                sessionId: sessionId,
                summary: summary,
                lastUserMessage: lastUserMessage,
                terminalAppName: terminalName,
                startedAt: startedAt,
                updatedAt: updatedAt
            ))
        }

        // Detect pending interactions across all active sessions (one per session)
        var detectedInteractions: [PendingInteraction] = []
        for session in updated where session.status != .done {
            guard let pid = Int(session.id) else { continue }

            var interaction: PendingInteraction?

            // First: scan JSONL for AskUserQuestion / ExitPlanMode (authoritative)
            if let sid = session.sessionId, let cwd = session.cwd {
                interaction = detectPendingInteraction(cwd: cwd, sessionId: sid, pid: pid, sessionSummary: session.summary)
            }

            // Fallback: permission prompt
            if interaction == nil && sessionWaitingFor[pid] == "permission prompt" {
                if let sid = session.sessionId, let cwd = session.cwd {
                    interaction = detectPermissionInteraction(cwd: cwd, sessionId: sid, pid: pid, sessionSummary: session.summary)
                }
                if interaction == nil {
                    interaction = PendingInteraction(
                        sessionId: session.sessionId ?? session.id,
                        pid: pid,
                        sessionSummary: session.summary,
                        type: .permission,
                        question: nil,
                        header: nil,
                        options: [
                            PendingInteractionOption(label: "Yes", description: "Allow once", keystrokeText: "y"),
                            PendingInteractionOption(label: "No", description: "Deny", keystrokeText: "n"),
                        ],
                        multiSelect: false,
                        planTitle: nil,
                        toolUseId: nil,
                        assistantUuid: nil,
                        cwd: nil,
                        claudeVersion: nil
                    )
                }
            }

            if let interaction {
                detectedInteractions.append(interaction)
            }
        }

        updateSessions(removing: .claudeCode, with: updated, pendingInteractions: detectedInteractions)
    }

    /// Reads the session title from sessions-index.json (firstPrompt field), stripping XML tags.
    private func readClaudeSessionTitle(cwd: String?, sessionId: String) -> String? {
        guard let cwd else { return nil }
        let encodedCwd = encodeCwd(cwd)
        let indexFile = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
            .appendingPathComponent("sessions-index.json")

        guard
            let data = try? Data(contentsOf: indexFile),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]],
            let entry = entries.first(where: { $0["sessionId"] as? String == sessionId }),
            let firstPrompt = entry["firstPrompt"] as? String
        else { return nil }

        // Strip leading XML-style tags like <ide_selection>...</ide_selection>
        var cleaned = firstPrompt
        while cleaned.hasPrefix("<"), let close = cleaned.range(of: ">") {
            cleaned = String(cleaned[close.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Also strip trailing ellipsis marker
        if cleaned.hasSuffix("…") { cleaned = String(cleaned.dropLast()) }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(80))
    }

    /// Reads the latest user message from the session JSONL as a task summary (fallback).
    private func readClaudeSummary(cwd: String?, sessionId: String) -> String? {
        guard let cwd else { return nil }
        let encodedCwd = encodeCwd(cwd)
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

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.hasPrefix("[Image")
                && !trimmed.hasPrefix("Base directory")
                && !trimmed.hasPrefix("<context")
                && !trimmed.hasPrefix("<system") {
                lastUserText = trimmed
                break
            }
        }
        return lastUserText.map { String($0.prefix(80)) }
    }

    /// Scans the session JSONL tail to detect if Claude Code is waiting for user input.
    /// Returns a PendingInteraction if the last assistant tool_use is AskUserQuestion or ExitPlanMode
    /// and no user tool_result has been sent for it yet.
    private func detectPendingInteraction(cwd: String, sessionId: String, pid: Int, sessionSummary: String?) -> PendingInteraction? {
        let encodedCwd = encodeCwd(cwd)
        let jsonlFile = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
            .appendingPathComponent("\(sessionId).jsonl")

        guard let content = try? String(contentsOf: jsonlFile, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Walk backwards to find the last assistant message with an interactive tool_use
        var lastInteractiveTool: (id: String, name: String, input: [String: Any], assistantUuid: String)?
        var respondedToolIds: Set<String> = []
        var claudeVersion: String?

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            // Capture version from any line that has it
            if claudeVersion == nil, let v = obj["version"] as? String { claudeVersion = v }

            let msgType = obj["type"] as? String ?? ""

            // Collect tool_result ids from user messages (means user already responded)
            if msgType == "user" {
                let message = obj["message"] as? [String: Any] ?? [:]
                let msgContent = message["content"] as? [[String: Any]] ?? []
                for item in msgContent {
                    if item["type"] as? String == "tool_result",
                       let tid = item["tool_use_id"] as? String {
                        respondedToolIds.insert(tid)
                    }
                }
            }

            // Find last assistant interactive tool_use
            if msgType == "assistant" && lastInteractiveTool == nil {
                let assistantUuid = obj["uuid"] as? String ?? ""
                let message = obj["message"] as? [String: Any] ?? [:]
                let msgContent = message["content"] as? [[String: Any]] ?? []
                for item in msgContent {
                    guard item["type"] as? String == "tool_use",
                          let toolId = item["id"] as? String,
                          let toolName = item["name"] as? String,
                          ["AskUserQuestion", "ExitPlanMode"].contains(toolName)
                    else { continue }
                    let input = item["input"] as? [String: Any] ?? [:]
                    lastInteractiveTool = (id: toolId, name: toolName, input: input, assistantUuid: assistantUuid)
                    break
                }
            }

            // Once we have both, stop
            if lastInteractiveTool != nil { break }
        }

        guard let tool = lastInteractiveTool,
              !respondedToolIds.contains(tool.id)
        else { return nil }

        if tool.name == "AskUserQuestion" {
            let questions = tool.input["questions"] as? [[String: Any]] ?? []
            guard let q = questions.first else { return nil }
            let questionText = q["question"] as? String
            let header = q["header"] as? String
            let multiSelect = q["multiSelect"] as? Bool ?? false
            let rawOptions = q["options"] as? [[String: Any]] ?? []
            let options = rawOptions.map {
                PendingInteractionOption(
                    label: $0["label"] as? String ?? "",
                    description: $0["description"] as? String ?? "",
                    keystrokeText: nil
                )
            }
            return PendingInteraction(
                sessionId: sessionId,
                pid: pid,
                sessionSummary: sessionSummary,
                type: .question,
                question: questionText,
                header: header,
                options: options,
                multiSelect: multiSelect,
                planTitle: nil,
                toolUseId: tool.id,
                assistantUuid: tool.assistantUuid,
                cwd: cwd,
                claudeVersion: claudeVersion
            )
        } else if tool.name == "ExitPlanMode" {
            let planContent = tool.input["plan"] as? String ?? ""
            let planTitle = planContent.components(separatedBy: "\n")
                .first { $0.hasPrefix("# ") }
                .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
            return PendingInteraction(
                sessionId: sessionId,
                pid: pid,
                sessionSummary: sessionSummary,
                type: .planApproval,
                question: nil,
                header: nil,
                options: [],
                multiSelect: false,
                planTitle: planTitle,
                toolUseId: nil,
                assistantUuid: nil,
                cwd: nil,
                claudeVersion: nil
            )
        }

        return nil
    }

    /// Scans the session JSONL to find the last unanswered tool_use and builds a
    /// PendingInteraction for the permission prompt matching Claude Code's own option logic.
    private func detectPermissionInteraction(cwd: String, sessionId: String, pid: Int, sessionSummary: String?) -> PendingInteraction? {
        let encodedCwd = encodeCwd(cwd)
        let jsonlFile = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
            .appendingPathComponent("\(sessionId).jsonl")

        guard let content = try? String(contentsOf: jsonlFile, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }

        var lastToolUse: (id: String, name: String, input: [String: Any])?
        var respondedToolIds: Set<String> = []

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let msgType = obj["type"] as? String ?? ""

            if msgType == "user" {
                let message = obj["message"] as? [String: Any] ?? [:]
                let msgContent = message["content"] as? [[String: Any]] ?? []
                for item in msgContent {
                    if item["type"] as? String == "tool_result",
                       let tid = item["tool_use_id"] as? String {
                        respondedToolIds.insert(tid)
                    }
                }
            }

            if msgType == "assistant" && lastToolUse == nil {
                let message = obj["message"] as? [String: Any] ?? [:]
                let msgContent = message["content"] as? [[String: Any]] ?? []
                for item in msgContent {
                    guard item["type"] as? String == "tool_use",
                          let toolId = item["id"] as? String,
                          let toolName = item["name"] as? String
                    else { continue }
                    let input = item["input"] as? [String: Any] ?? [:]
                    lastToolUse = (id: toolId, name: toolName, input: input)
                    break
                }
            }

            if lastToolUse != nil { break }
        }

        guard let tool = lastToolUse, !respondedToolIds.contains(tool.id) else { return nil }

        let options = permissionOptions(toolName: tool.name, input: tool.input, cwd: cwd)
        let question = permissionQuestion(toolName: tool.name, input: tool.input)

        return PendingInteraction(
            sessionId: sessionId,
            pid: pid,
            sessionSummary: sessionSummary,
            type: .permission,
            question: question,
            header: tool.name,
            options: options,
            multiSelect: false,
            planTitle: nil,
            toolUseId: nil,
            assistantUuid: nil,
            cwd: nil,
            claudeVersion: nil
        )
    }

    /// Builds permission option labels matching Claude Code's rK4 / fK4 logic exactly.
    /// File tools (Write/Edit/Read/NotebookEdit) use rK4; Bash uses fK4.
    private func permissionOptions(toolName: String, input: [String: Any], cwd: String) -> [PendingInteractionOption] {
        let fileTools: Set<String> = ["Write", "Edit", "NotebookEdit", "Read"]
        let bashTools: Set<String> = ["Bash"]

        var opts: [PendingInteractionOption] = []
        opts.append(PendingInteractionOption(label: "Yes", description: "Allow once", keystrokeText: "y"))

        if toolName == "WebFetch" {
            // WebFetch has its own permission UI: Yes / Yes, and don't ask again for <domain> / No
            let url = input["url"] as? String ?? ""
            if let host = URL(string: url)?.host, !host.isEmpty {
                opts.append(PendingInteractionOption(
                    label: "Yes, and don't ask again for \(host)",
                    description: "Always allow this domain",
                    keystrokeText: "a"
                ))
            }
            opts.append(PendingInteractionOption(label: "No, and tell Claude what to do differently", description: "Deny", keystrokeText: "n"))
        } else if fileTools.contains(toolName) {
            let filePath = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? ""
            let opType: String = toolName == "Read" ? "read" : "write"
            let option2 = filePermissionOption2(filePath: filePath, operationType: opType, cwd: cwd)
            opts.append(option2)
            opts.append(PendingInteractionOption(label: "No", description: "Deny", keystrokeText: "n"))
        } else if bashTools.contains(toolName) {
            let command = input["command"] as? String ?? ""
            if let option2 = bashPermissionOption2(command: command, cwd: cwd) {
                opts.append(option2)
            }
            opts.append(PendingInteractionOption(label: "No", description: "Deny", keystrokeText: "n"))
        } else {
            // MCP tool or unknown tool
            let displayName = formatMcpToolName(toolName)
            let claudeDir = (cwd as NSString).appendingPathComponent(".claude")
            opts.append(PendingInteractionOption(
                label: "Yes, and don't ask again for \(displayName) commands in \(claudeDir)",
                description: "Always allow this MCP tool",
                keystrokeText: "a"
            ))
            opts.append(PendingInteractionOption(label: "No", description: "Deny", keystrokeText: "n"))
        }

        return opts
    }

    /// Mirrors rK4's option-2 logic for file-based tools.
    private func filePermissionOption2(filePath: String, operationType: String, cwd: String) -> PendingInteractionOption {
        let isRead = operationType == "read"

        // Is file inside .claude/ config folder?
        let homeStr = Self.realHomeURL.path
        let claudeFolder = homeStr + "/.claude"
        if filePath.hasPrefix(claudeFolder) && !isRead {
            return PendingInteractionOption(
                label: "Yes, and allow Claude to edit its own settings for this session",
                description: "Accept session for .claude folder",
                keystrokeText: "a"
            )
        }

        // Is file inside cwd (working directory)?
        let cwdNorm = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if filePath.hasPrefix(cwdNorm) || filePath == cwd {
            if isRead {
                return PendingInteractionOption(label: "Yes, during this session", description: "Allow all reads this session", keystrokeText: "a")
            } else {
                return PendingInteractionOption(label: "Yes, allow all edits during this session", description: "Allow all edits this session", keystrokeText: "a")
            }
        }

        // File is outside cwd — show the directory name
        let dir = (filePath as NSString).deletingLastPathComponent
        let dirName = (dir as NSString).lastPathComponent.isEmpty ? dir : (dir as NSString).lastPathComponent
        let displayDir = dirName.isEmpty ? "this directory" : dirName

        if isRead {
            return PendingInteractionOption(
                label: "Yes, allow reading from \(displayDir)/ during this session",
                description: "Allow reads from \(displayDir)",
                keystrokeText: "a"
            )
        } else {
            return PendingInteractionOption(
                label: "Yes, allow all edits in \(displayDir)/ during this session",
                description: "Allow all edits in \(displayDir)",
                keystrokeText: "a"
            )
        }
    }

    /// Mirrors fK4 + Py6's option-2 logic for Bash.
    /// Bash option 2 is only shown when Claude Code has generated "suggestions"
    /// (addRules/addDirectories). We approximate this by detecting if the command
    /// reads from an outside absolute path as its *primary* target argument.
    private func bashPermissionOption2(command: String, cwd: String) -> PendingInteractionOption? {
        // Commands with -exec can modify files — Claude Code explicitly refuses to
        // auto-allow these ("cannot be auto-allowed by a Bash(find:*) prefix rule").
        if command.contains("-exec") { return nil }

        let tokens = command.components(separatedBy: .whitespaces)
        let cwdNorm = cwd.hasSuffix("/") ? cwd : cwd + "/"

        // Flags whose *next* token is a value argument, not a target path.
        // Scanning the value as a path would produce spurious option-2 entries.
        let flagsWithValues: Set<String> = [
            "-name", "-iname", "-newer", "-path", "-ipath", "-regex",
            "-maxdepth", "-mindepth", "-type", "-user", "-group",
            "-size", "-mtime", "-atime", "-ctime", "-perm",
            "-o", "-and", "-or",
        ]

        var skipNext = false
        for token in tokens {
            if skipNext { skipNext = false; continue }
            if flagsWithValues.contains(token) { skipNext = true; continue }
            // Skip flags themselves
            if token.hasPrefix("-") { continue }

            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard t.hasPrefix("/"), !t.hasPrefix(cwdNorm), t != cwd else { continue }

            let parentDir = (t as NSString).deletingLastPathComponent
            let dirName = (parentDir as NSString).lastPathComponent
            let displayDir = dirName.isEmpty ? parentDir : dirName

            return PendingInteractionOption(
                label: "Yes, allow reading from \(displayDir)/ from this project",
                description: "Allow reads from \(displayDir)",
                keystrokeText: "a"
            )
        }

        return nil
    }

    /// Builds a short question string summarising the tool call for display.
    private func permissionQuestion(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            let cmd = (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let desc = input["description"] as? String
            if let desc, !desc.isEmpty { return "\(desc): \(cmd)" }
            return cmd.isEmpty ? "Bash command" : cmd
        case "Write", "Edit", "NotebookEdit":
            let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String) ?? ""
            return path.isEmpty ? toolName : "\(toolName)(\(path))"
        case "Read":
            let path = input["file_path"] as? String ?? ""
            return path.isEmpty ? "Read" : "Read(\(path))"
        case "WebFetch":
            let url = input["url"] as? String ?? ""
            let prompt = input["prompt"] as? String ?? ""
            if url.isEmpty { return "WebFetch" }
            if prompt.isEmpty { return url }
            return "url: \"\(url)\", prompt: \"\(prompt)\""
        default:
            // MCP tools use the pattern mcp__<serverName>__<toolName>
            return formatMcpToolName(toolName)
        }
    }

    /// Formats an MCP tool name from `mcp__server__tool` → `server - tool`.
    /// Falls back to the raw name for non-MCP tools.
    private func formatMcpToolName(_ toolName: String) -> String {
        guard toolName.hasPrefix("mcp__") else { return toolName }
        let parts = toolName.dropFirst(5).components(separatedBy: "__")
        guard parts.count >= 2 else { return toolName }
        let server = parts[0]
        let tool = parts[1...].joined(separator: "__")
        return "\(server) - \(tool)"
    }

    // Claude encodes the cwd by replacing every non-alphanumeric character with '-'
    private func encodeCwd(_ cwd: String) -> String {
        cwd.unicodeScalars.map { char in
            let c = char.value
            let isAlphaNum = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57)
            return isAlphaNum ? String(char) : "-"
        }.joined()
    }

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

        // Load Codex thread names once per refresh
        let threadNames = readCodexThreadNames()

        var updated: [AgentSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let tidPtr = sqlite3_column_text(statement, 0) else { continue }

            let tid = String(cString: tidPtr)
            let lastTs = sqlite3_column_int64(statement, 1)
            let status: AgentStatus = lastTs >= cutoffActive ? .running : .idle

            updated.append(AgentSession(
                id: tid,
                app: .codex,
                status: status,
                cwd: nil,
                sessionId: tid,
                summary: threadNames[tid],
                lastUserMessage: nil,
                terminalAppName: nil,
                startedAt: Date(timeIntervalSince1970: TimeInterval(lastTs)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(lastTs))
            ))
        }

        updateSessions(removing: .codex, with: updated)
    }

    /// Reads ~/.codex/session_index.jsonl and returns a [threadId: threadName] map.
    private func readCodexThreadNames() -> [String: String] {
        guard let content = try? String(contentsOf: codexSessionIndex, encoding: .utf8) else {
            return [:]
        }
        var map: [String: String] = [:]
        for line in content.components(separatedBy: "\n") {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String,
                  let name = json["thread_name"] as? String
            else { continue }
            map[id] = name
        }
        return map
    }

    // MARK: - Helpers

    private func updateSessions(removing app: AgentApp, with newSessions: [AgentSession], pendingInteractions: [PendingInteraction] = []) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var kept = self.sessions.filter { $0.app != app }
            let visible = newSessions.filter { $0.status != .done || $0.app == .claudeCode }
            kept.append(contentsOf: visible)
            self.sessions = kept
            if app == .claudeCode {
                // Filter out dismissed interactions; clear dismissed keys for interactions no longer present
                let incomingKeys = Set(pendingInteractions.map { "\($0.sessionId)-\($0.type)" })
                self.dismissedInteractionKeys = self.dismissedInteractionKeys.intersection(incomingKeys)
                let visible = pendingInteractions.filter { i in
                    !self.dismissedInteractionKeys.contains("\(i.sessionId)-\(i.type)")
                }
                self.pendingInteractions = visible
            }
        }
    }

    private func isProcessAlive(pid: Int) -> Bool {
        Darwin.kill(Int32(pid), 0) == 0 || errno == EPERM
    }

    private static let knownTerminals: [String: String] = [
        "dev.warp.Warp-Stable": "Warp",
        "dev.warp.Warp-Beta": "Warp",
        "com.googlecode.iterm2": "iTerm2",
        "com.apple.Terminal": "Terminal",
        "com.github.wez.wezterm": "WezTerm",
        "net.kovidgoyal.kitty": "Kitty",
        "io.alacritty": "Alacritty",
        "com.cursor.cursor": "Cursor",
        "com.microsoft.VSCode": "VSCode",
        "com.jetbrains.intellij": "IntelliJ",
    ]

    /// Walks the process tree upward from `pid` to find the nearest terminal or IDE app name.
    func terminalAppName(forPid pid: Int) -> String? {
        var searchPid = Int32(pid)
        for _ in 0..<12 {
            guard searchPid > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: searchPid),
               let bundleId = app.bundleIdentifier,
               let name = Self.knownTerminals[bundleId] {
                return name
            }
            var kinfo = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, searchPid]
            guard sysctl(&mib, 4, &kinfo, &size, nil, 0) == 0 else { break }
            searchPid = kinfo.kp_eproc.e_ppid
        }
        return nil
    }
}

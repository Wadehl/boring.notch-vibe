//
//  AgentStatusManager.swift
//  boringNotch
//

import Combine
import Defaults
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
    case completion     // Stop hook — response finished
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
    @Published private(set) var permissionMismatchWarning: String? = nil
    @Published private(set) var recentlyDoneSessions: Set<String> = []

    // Keys of interactions the user has dismissed; suppressed until a new one arrives
    private var dismissedInteractionKeys: Set<String> = []
    private var hookSourcedPermissionSessions: Set<String> = []
    // Persistent sessionId (UUID) → id (PID) cache — survives after session is removed from sessions[]
    private var sessionIdToPid: [String: String] = [:]

    var pendingInteraction: PendingInteraction? { pendingInteractions.first }

    func dismissPendingInteraction(sessionId: String? = nil) {
        if let sessionId {
            if let idx = pendingInteractions.firstIndex(where: { $0.sessionId == sessionId }) {
                let interaction = pendingInteractions[idx]
                if interaction.type != .completion {
                    let key = "\(interaction.sessionId)-\(interaction.type)"
                    dismissedInteractionKeys.insert(key)
                }
                pendingInteractions.remove(at: idx)
            }
            hookSourcedPermissionSessions.remove(sessionId)
        } else {
            // Legacy: dismiss first
            if let first = pendingInteractions.first {
                if first.type != .completion {
                    dismissedInteractionKeys.insert("\(first.sessionId)-\(first.type)")
                }
                hookSourcedPermissionSessions.remove(first.sessionId)
                pendingInteractions.removeFirst()
            }
        }
    }

    private let warpController = WarpController()
    private let terminalAppController = TerminalAppController()

    func selectOption(claudePid: Int, optionIndex: Int, sessionId: String? = nil) {
        print("[AgentStatusManager] selectOption index=\(optionIndex) claudePid=\(claudePid)")

        // Snapshot interaction before dismissal for mismatch monitoring.
        // Watch both "always allow" (index 1, 3-option) and "No" (last option) selections.
        let interactionSnapshot: PendingInteraction? = {
            guard let sid = sessionId,
                  let interaction = pendingInteractions.first(where: { $0.sessionId == sid }),
                  interaction.type == .permission,
                  interaction.toolUseId != nil,
                  interaction.cwd != nil,
                  (optionIndex == 1 && interaction.options.count == 3) ||
                  (optionIndex == interaction.options.count - 1)
            else { return nil }
            return interaction
        }()

        guard let terminal = terminalRunningApp(forPid: claudePid) else { return }
        let bundleId = terminal.bundleIdentifier ?? ""
        let digit = optionIndex + 1

        // Beta feature gate: auto-input must be enabled, otherwise just focus the terminal.
        guard Defaults[.claudeCodeAutoInput] else {
            focusTerminal(claudePid: claudePid, sessionId: sessionId, dismissOnSuccess: true)
            if let snap = interactionSnapshot {
                startOptionMismatchMonitor(interaction: snap, selectedIndex: optionIndex)
            }
            return
        }

        if bundleId == "com.apple.Terminal" {
            guard XPCHelperClient.shared.accessibilityAuthorized else {
                XPCHelperClient.shared.requestAccessibilityAuthorization()
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = "请在系统设置中允许 BoringNotchXPCHelper 使用辅助功能，然后重启 boringNotch 以生效。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好的")
                alert.runModal()
                return
            }
            terminalAppController.activateAndSend(digit: digit) {
                self.dismissPendingInteraction(sessionId: sessionId)
            }
        } else if bundleId.hasPrefix("dev.warp.") {
            guard XPCHelperClient.shared.accessibilityAuthorized else {
                XPCHelperClient.shared.requestAccessibilityAuthorization()
                let alert = NSAlert()
                alert.messageText = "需要辅助功能权限"
                alert.informativeText = "请在系统设置中允许 BoringNotchXPCHelper 使用辅助功能，然后重启 boringNotch 以生效。"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "好的")
                alert.runModal()
                return
            }
            warpController.activateAndSend(claudePid: claudePid, digit: digit) {
                self.dismissPendingInteraction(sessionId: sessionId)
            }
        } else {
            focusTerminal(claudePid: claudePid, sessionId: sessionId, dismissOnSuccess: false)
        }

        if let snap = interactionSnapshot {
            startOptionMismatchMonitor(interaction: snap, selectedIndex: optionIndex)
        }
    }

    func sendMultiSelectAndFocus(claudePid: Int, optionIndices: [Int], sessionId: String?) {
        guard let terminal = terminalRunningApp(forPid: claudePid) else { return }
        guard XPCHelperClient.shared.accessibilityAuthorized else {
            XPCHelperClient.shared.requestAccessibilityAuthorization()
            let alert = NSAlert()
            alert.messageText = "需要辅助功能权限"
            alert.informativeText = "请在系统设置中允许 BoringNotchXPCHelper 使用辅助功能，然后重启 boringNotch 以生效。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            alert.runModal()
            return
        }
        let bundleId = terminal.bundleIdentifier ?? ""
        let digits = optionIndices.map { $0 + 1 }

        if bundleId.hasPrefix("dev.warp.") {
            // Activate warp tab (restoring if minimized), then send all digits in sequence
            Task {
                let index = await XPCHelperClient.shared.warpTabIndex(forClaudePid: claudePid)
                await MainActor.run {
                    self.warpController.activateThenRun {
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

    private var hookEventsSource: DispatchSourceFileSystemObject?
    private var hookEventsFD: Int32 = -1
    private var hookEventsOffset: UInt64 = 0
    private var hookEventsTimer: DispatchSourceTimer?

    private let queue = DispatchQueue(label: "com.boringnotch.agentStatusManager", qos: .utility)
    private let hooksDir: URL
    private let eventsFile: URL

    // Codex: thread is "running" if it logged within this interval
    private let codexActiveThresholdSeconds: TimeInterval = 5
    // Codex: stop tracking threads silent for this long
    private let codexDropThresholdSeconds: TimeInterval = 60

    private init() {
        let home = Self.realHomeURL
        claudeSessionsDir = home.appendingPathComponent(".claude/sessions")
        codexLogsDB = home.appendingPathComponent(".codex/logs_2.sqlite")
        codexSessionIndex = home.appendingPathComponent(".codex/session_index.jsonl")
        // Hook script lives outside container (executable), events file lives inside container (readable by app)
        let containerHome = FileManager.default.homeDirectoryForCurrentUser
        hooksDir = home.appendingPathComponent(".claude/boringnotch/hooks")
        eventsFile = containerHome.appendingPathComponent("events.jsonl")
        installHooks()
        print("[HookMonitor] eventsFile=\(eventsFile.path)")
        startClaudeWatcher()
        startClaudePoller()
        startCodexPoller()
        startHookEventMonitor()
    }

    func reinstallHooks() {
        installHooks()
    }

    private func installHooks() {
        let scriptURL = hooksDir.appendingPathComponent("on-event.sh")
        let script = "#!/bin/sh\ncat >> \"\(eventsFile.path)\"\n"

        // Write the script via the unsandboxed XPC helper so the file doesn't get
        // com.apple.quarantine — sandboxed-written scripts are blocked by the kernel.
        Task {
            let result = await XPCHelperClient.shared.writeFile(
                atPath: scriptURL.path, content: script, posixPermissions: 0o755)
            if !result.success {
                print("[AgentStatusManager] installHooks: writeFile failed: \(result.error ?? "unknown")")
            }
            injectHookSettings(scriptPath: scriptURL.path)
        }
    }

    private func injectHookSettings(scriptPath: String) {
        let settingsURL = Self.realHomeURL.appendingPathComponent(".claude/settings.json")

        var root: [String: Any]
        if let data = try? Data(contentsOf: settingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        } else {
            root = [:]
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let hookEntry: [String: Any] = ["hooks": [["type": "command", "command": scriptPath]]]
        for event in ["PermissionRequest", "Stop", "SessionEnd"] {
            var list = hooks[event] as? [[String: Any]] ?? []
            let alreadyInstalled = list.contains { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
                return inner.contains { $0["command"] as? String == scriptPath }
            }
            if !alreadyInstalled { list.append(hookEntry) }
            hooks[event] = list
        }
        root["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              var str = String(data: data, encoding: .utf8)
        else { return }
        str += "\n"
        try? str.write(to: settingsURL, atomically: true, encoding: .utf8)
    }

    deinit {
        claudeDirSource?.cancel()
        if claudeDirFD >= 0 { Darwin.close(claudeDirFD) }
        claudePollingTimer?.cancel()
        codexTimer?.cancel()
        hookEventsSource?.cancel()
        if hookEventsFD >= 0 { Darwin.close(hookEventsFD) }
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
            if rawStatus != "idle" || waitingFor != nil {
                print("[Polling] pid=\(pid) rawStatus=\(rawStatus) waitingFor=\(waitingFor ?? "nil")")
            }

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

            // Permission detection:
            // - Bash: CC sets rawStatus=busy + waitingFor="permission prompt"
            // - File tools (Edit/Write/Read/NotebookEdit): CC sets rawStatus=idle, waitingFor=nil
            //   → detected by scanning JSONL for unanswered tool_use on idle sessions
            let isPermissionWait = sessionWaitingFor[pid] == "permission prompt"
            let isIdleWithPossiblePermission = session.status == .idle
            if interaction == nil && (isPermissionWait || isIdleWithPossiblePermission) {
                if let sid = session.sessionId, let cwd = session.cwd {
                    interaction = detectPermissionInteraction(cwd: cwd, sessionId: sid, pid: pid, sessionSummary: session.summary)
                }
                // Yes/No fallback only when CC explicitly signals a permission prompt
                // but the JSONL scan couldn't find the tool_use
                if interaction == nil && isPermissionWait {
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

    /// Reads the last assistant text reply from the session JSONL for use in the completion card.
    private func readLastAssistantMessage(cwd: String, sessionId: String) -> String? {
        let encodedCwd = encodeCwd(cwd)
        let jsonlFile = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
            .appendingPathComponent("\(sessionId).jsonl")

        guard let content = try? String(contentsOf: jsonlFile, encoding: .utf8) else { return nil }

        for line in content.components(separatedBy: "\n").reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let contentArr = message["content"] as? [[String: Any]]
            else { continue }

            let text = contentArr.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty { return String(text.prefix(80)) }
        }
        return nil
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
            toolUseId: tool.id,
            assistantUuid: nil,
            cwd: cwd,
            claudeVersion: nil
        )
    }

    // MARK: - Permission mismatch monitor

    /// Monitors tool_result after a permission choice that might be misaligned with CC's actual option count.
    ///
    /// - selectedIndex 1 in a 3-option dialog ("always allow", sends digit 2):
    ///   If CC only had 2 options, digit 2 = No → tool denied. Warn if result looks like denial.
    /// - selectedIndex == last option ("No"):
    ///   If CC had more options, digit N might map to Always instead of No → tool ran. Warn if result looks like execution.
    private func startOptionMismatchMonitor(interaction: PendingInteraction, selectedIndex: Int) {
        guard let toolUseId = interaction.toolUseId, let cwd = interaction.cwd else { return }
        let sessionId = interaction.sessionId
        let optionCount = interaction.options.count
        let isAlways = selectedIndex == 1 && optionCount == 3
        let isNo = selectedIndex == optionCount - 1
        guard isAlways || isNo else { return }

        var attempts = 0
        let maxAttempts = 16   // 8 s at 500 ms intervals

        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            attempts += 1
            guard let self, attempts <= maxAttempts else { timer.invalidate(); return }
            guard let result = self.findToolResult(sessionId: sessionId, toolUseId: toolUseId, cwd: cwd)
            else { return }
            timer.invalidate()

            let warning: String?
            if isAlways && self.looksLikeDenial(result) {
                // Sent digit 2 for "always allow" but CC treated it as No
                warning = "⚠️ 选项可能错位：CC 只有 2 个选项，'永远允许' 实际发送了 No，操作已被拒绝，请手动重试。"
            } else if isNo && !self.looksLikeDenial(result) {
                // Sent digit N for "No" but CC treated it as a middle option (always allow)
                warning = "⚠️ 选项可能错位：CC 有更多选项，'No' 实际触发了执行，请检查操作结果。"
            } else {
                warning = nil
            }

            if let warning {
                self.permissionMismatchWarning = warning
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                    self?.permissionMismatchWarning = nil
                }
            }
        }
    }

    /// Read the session JSONL and return the content string of the tool_result for the given toolUseId, if present.
    private func findToolResult(sessionId: String, toolUseId: String, cwd: String) -> String? {
        let encodedCwd = encodeCwd(cwd)
        let jsonlFile = Self.realHomeURL
            .appendingPathComponent(".claude/projects")
            .appendingPathComponent(encodedCwd)
            .appendingPathComponent("\(sessionId).jsonl")

        guard let raw = try? String(contentsOf: jsonlFile, encoding: .utf8) else { return nil }

        for line in raw.components(separatedBy: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "user",
                  let message = obj["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }

            for item in content {
                guard item["type"] as? String == "tool_result",
                      item["tool_use_id"] as? String == toolUseId
                else { continue }

                if let text = item["content"] as? String { return text }
                if let blocks = item["content"] as? [[String: Any]] {
                    return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
                }
                return ""
            }
        }
        return nil
    }

    /// Heuristic: does this tool_result look like CC denied the request rather than executing it?
    private func looksLikeDenial(_ content: String) -> Bool {
        let lower = content.lowercased()
        let denialKeywords = ["denied", "declined", "permission", "not allowed", "cancelled", "canceled", "refused", "rejected"]
        if denialKeywords.contains(where: { lower.contains($0) }) { return true }
        // Denial messages are short; real command output tends to be longer or empty (silent success)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count < 80 && !trimmed.isEmpty
    }

/// File tools (Write/Edit/Read/NotebookEdit) use rK4; Bash uses fK4.
    private func permissionOptions(toolName: String, input: [String: Any], cwd: String) -> [PendingInteractionOption] {
        let yes = PendingInteractionOption(label: "Yes", description: "Allow once", keystrokeText: "y")
        let no  = PendingInteractionOption(label: "No",  description: "Deny",       keystrokeText: "n")

        if toolName == "WebFetch" {
            // CC always shows 3 options for WebFetch: Yes / Yes don't ask domain / No
            let url = input["url"] as? String ?? ""
            if let host = URL(string: url)?.host, !host.isEmpty {
                let always = PendingInteractionOption(
                    label: "Yes, and don't ask again for \(host)",
                    description: "Always allow this domain",
                    keystrokeText: "a"
                )
                return [yes, always, no]
            }
            return [yes, no]
        }

        if toolName == "Bash" {
            let command = input["command"] as? String ?? ""
            // CC sets suggestions:[] for multiline commands that trigger safety checks
            // (e.g. "Newline followed by # inside a quoted argument"). Without suggestions,
            // CC only shows Yes/No. Mirror that by skipping the always option for multiline commands.
            guard !command.contains("\n") else { return [yes, no] }
            let prefix = bashCommandPrefix(command)
            // CC: ruleContent is "{prefix}:*" for prefix rules, or the exact command for direct rules.
            // Label: "Yes, and don't ask again for {ruleContent} commands in {cwd}"
            // Commands > 50 chars are shown as "similar" (matches generateShellSuggestionsLabel).
            let ruleContent: String
            if let prefix = prefix {
                ruleContent = "\(prefix):*"
            } else if command.count > 50 {
                ruleContent = "similar"
            } else {
                ruleContent = command
            }
            let label = "Yes, and don't ask again for \(ruleContent) commands in \(cwd)"
            let always = PendingInteractionOption(label: label, description: "Always allow", keystrokeText: "a")
            return [yes, always, no]
        }

        // File tools: CC's permissionOptions.tsx always returns 3 options.
        // Option 2 label varies by path context (inside/outside cwd, .claude/ folder, read vs write).
        let fileTools: Set<String> = ["Write", "Edit", "NotebookEdit", "Read"]
        if fileTools.contains(toolName) {
            let rawPath = (input["file_path"] as? String)
                ?? (input["notebook_path"] as? String)
                ?? ""
            let filePath = (rawPath as NSString).expandingTildeInPath
            let operationType = toolName == "Read" ? "read" : "write"

            let sessionLabel: String
            let claudeFolderSuffix = "/.claude/"
            let globalClaudeFolder = (("~/.claude") as NSString).expandingTildeInPath

            let inClaudeFolder = filePath.contains(claudeFolderSuffix)
            let inGlobalClaudeFolder = filePath.hasPrefix(globalClaudeFolder + "/") || filePath == globalClaudeFolder

            if (inClaudeFolder || inGlobalClaudeFolder) && operationType != "read" {
                sessionLabel = "Yes, and allow Claude to edit its own settings for this session"
            } else {
                let normalizedCwd = cwd.hasSuffix("/") ? cwd : cwd + "/"
                let inAllowedPath = !cwd.isEmpty && (filePath.hasPrefix(normalizedCwd) || filePath == cwd)
                if inAllowedPath {
                    sessionLabel = operationType == "read"
                        ? "Yes, during this session"
                        : "Yes, allow all edits during this session"
                } else {
                    let dirPath = (filePath as NSString).deletingLastPathComponent
                    let dirName = (dirPath as NSString).lastPathComponent
                    let displayDir = dirName.isEmpty ? filePath : dirName
                    sessionLabel = operationType == "read"
                        ? "Yes, allow reading from \(displayDir)/ during this session"
                        : "Yes, allow all edits in \(displayDir)/ during this session"
                }
            }

            let yesSession = PendingInteractionOption(
                label: sessionLabel,
                description: "Allow for this session",
                keystrokeText: "a"
            )
            return [yes, yesSession, no]
        }

        // Skill tool (SkillPermissionRequest): input["skill"] holds the skill name.
        // CC shows up to 4 options: Yes / don't ask exact / don't ask prefix (if space) / No.
        if toolName == "Skill" {
            let skill = input["skill"] as? String ?? ""
            var opts: [PendingInteractionOption] = [yes]
            if !skill.isEmpty {
                let exactLabel = "Yes, and don't ask again for \(skill) in \(cwd)"
                opts.append(PendingInteractionOption(
                    label: exactLabel, description: "Always allow this skill", keystrokeText: "a"
                ))
                // If skill has a space (e.g. "plugin arg"), add a prefix wildcard option
                if let spaceIdx = skill.firstIndex(of: " "), spaceIdx != skill.startIndex {
                    let commandPrefix = String(skill[skill.startIndex..<spaceIdx]) + ":*"
                    let prefixLabel = "Yes, and don't ask again for \(commandPrefix) commands in \(cwd)"
                    opts.append(PendingInteractionOption(
                        label: prefixLabel, description: "Always allow this skill family", keystrokeText: "s"
                    ))
                }
            }
            opts.append(no)
            return opts
        }

        // MCP / unknown tools (FallbackPermissionRequest): always 3 options.
        // CC shows: Yes / "don't ask again for {toolName} commands in {cwd}" / No.
        // Strip the " (MCP)" suffix that CC appends to userFacingName before stripping it.
        let displayName = toolName.hasSuffix(" (MCP)") ? String(toolName.dropLast(6)) : toolName
        let fallbackAlways = PendingInteractionOption(
            label: "Yes, and don't ask again for \(displayName) commands in \(cwd)",
            description: "Always allow this tool",
            keystrokeText: "a"
        )
        return [yes, fallbackAlways, no]
    }

    // Mirrors CC's getSimpleCommandPrefix + getFirstWordPrefix:
    // 1. Try two-word prefix: "git commit" → returns "git commit"
    // 2. Fall back to one-word prefix: "python3" → returns "python3"
    // 3. Returns nil if command starts with a shell wrapper or no valid prefix found.
    // Callers append ":*" to form the rule content.
    private func bashCommandPrefix(_ command: String) -> String? {
        // Shells/wrappers that CC refuses to auto-allow by prefix
        let blocked: Set<String> = [
            "sh","bash","zsh","fish","csh","tcsh","ksh","dash","cmd","powershell","pwsh",
            "env","xargs","command","builtin","noglob","nice","stdbuf","nohup","timeout",
            "time","watch","ionice","chrt","setsid","taskset","strace","ltrace","script",
            "flock","unshare","nsenter","sudo","doas","pkexec"
        ]

        var tokens = command.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Skip leading VAR=value tokens
        while let first = tokens.first, first.contains("=") {
            let varName = first.components(separatedBy: "=")[0]
            let validEnvVar = varName.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
            guard validEnvVar else { break }
            tokens.removeFirst()
        }

        guard let cmd = tokens.first, !cmd.isEmpty else { return nil }
        guard !blocked.contains(cmd) else { return nil }

        let wordRegex = "^[a-z][a-z0-9]*(-[a-z0-9]+)*$"

        // Two-word prefix: "git commit", "npm install"
        if tokens.count >= 2 {
            let sub = tokens[1]
            if sub.range(of: wordRegex, options: .regularExpression) != nil {
                return "\(cmd) \(sub)"
            }
        }

        // One-word prefix: "python3", "make"
        if cmd.range(of: wordRegex, options: .regularExpression) != nil {
            return cmd
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

    private func startHookEventMonitor() {
        let path = eventsFile.path

        // Ensure file exists so we can open it
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        // Start at end of file — ignore events written before this session
        hookEventsOffset = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        print("[HookMonitor] starting, offset=\(hookEventsOffset), path=\(path)")

        let fd = Darwin.open(path, O_EVTONLY)
        if fd >= 0 {
            hookEventsFD = fd
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.drainHookEvents()
            }
            source.resume()
            hookEventsSource = source
            print("[HookMonitor] DispatchSource armed (fd=\(fd))")
        } else {
            print("[HookMonitor] DispatchSource failed (fd=-1), polling only")
        }

        // Polling fallback: drain every 2s in case DispatchSource is blocked (sandbox)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.drainHookEvents()
        }
        timer.resume()
        hookEventsTimer = timer
    }

    private func drainHookEvents() {
        guard let allData = try? Data(contentsOf: eventsFile) else {
            print("[HookMonitor] drainHookEvents: Data(contentsOf:) failed")
            return
        }
        let currentSize = UInt64(allData.count)
        guard currentSize > hookEventsOffset else {
            print("[HookMonitor] drain: no new bytes (size=\(currentSize) offset=\(hookEventsOffset))")
            return
        }
        let newData = allData[Int(hookEventsOffset)...]
        hookEventsOffset = currentSize
        guard let text = String(data: newData, encoding: .utf8) else { return }
        print("[HookMonitor] drained \(newData.count) bytes")

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            handleHookEvent(obj)
        }
    }

    private func handleHookEvent(_ obj: [String: Any]) {
        guard let eventName = obj["hook_event_name"] as? String,
              let sessionId = obj["session_id"] as? String
        else { return }

        switch eventName.lowercased() {
        case "permissionrequest":
            handlePermissionRequestHook(obj, sessionId: sessionId)
        case "stop":
            let cwd = obj["cwd"] as? String
            handleResponseCompleteHook(sessionId: sessionId, cwd: cwd)
        case "sessionend":
            print("[HookMonitor] SessionEnd sid=\(sessionId.prefix(8)) (ignored)")
        default:
            print("[HookMonitor] unhandled event: \(eventName)")
        }
    }

    private func handlePermissionRequestHook(_ obj: [String: Any], sessionId: String) {
        let cwd = obj["cwd"] as? String ?? ""
        let toolName = obj["tool_name"] as? String ?? ""
        let toolInput = obj["tool_input"] as? [String: Any] ?? [:]
        let rawSuggestions = obj["permission_suggestions"] as? [[String: Any]] ?? []
        print("[HookMonitor] PermissionRequest tool=\(toolName) suggestions=\(rawSuggestions.map { $0["type"] as? String ?? "?" })")

        // AskUserQuestion and ExitPlanMode are interactive tools, not permission gates.
        // The JSONL scanner (detectPendingInteraction) handles them as .question/.planApproval.
        guard toolName != "AskUserQuestion" && toolName != "ExitPlanMode" else { return }

        let options: [PendingInteractionOption]
        if rawSuggestions.isEmpty {
            options = permissionOptions(toolName: toolName, input: toolInput, cwd: cwd)
        } else {
            let yes = PendingInteractionOption(label: "Yes", description: "Allow once", keystrokeText: "y")
            let no  = PendingInteractionOption(label: "No",  description: "Deny",       keystrokeText: "n")
            let alwaysOpts = rawSuggestions.compactMap { buildPermissionOption(from: $0) }
            // If all suggestions were unrecognized types (e.g. setMode for Edit/Write),
            // fall back to permissionOptions() which derives the correct labels from tool+input.
            if alwaysOpts.isEmpty {
                options = permissionOptions(toolName: toolName, input: toolInput, cwd: cwd)
            } else {
                options = [yes] + alwaysOpts + [no]
            }
        }

        let question = permissionQuestion(toolName: toolName, input: toolInput)
        let cwdOpt = cwd.isEmpty ? nil : cwd

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let pid = self.sessions.first { $0.sessionId == sessionId }.flatMap { Int($0.id) } ?? 0
            let summary = self.sessions.first { $0.sessionId == sessionId }?.summary

            let interaction = PendingInteraction(
                sessionId: sessionId,
                pid: pid,
                sessionSummary: summary,
                type: .permission,
                question: question,
                header: toolName,
                options: options,
                multiSelect: false,
                planTitle: nil,
                toolUseId: nil,
                assistantUuid: nil,
                cwd: cwdOpt,
                claudeVersion: nil
            )

            self.hookSourcedPermissionSessions.insert(sessionId)
            self.pendingInteractions.removeAll { $0.sessionId == sessionId && $0.type == .permission }
            let key = "\(sessionId)-\(PendingInteractionType.permission)"
            if !self.dismissedInteractionKeys.contains(key) {
                self.pendingInteractions.append(interaction)
            }
        }
    }

    private func buildPermissionOption(from suggestion: [String: Any]) -> PendingInteractionOption? {
        guard let type = suggestion["type"] as? String else { return nil }

        switch type {
        case "addRules":
            guard let rules = suggestion["rules"] as? [[String: Any]],
                  let first = rules.first,
                  let ruleContent = first["ruleContent"] as? String,
                  let toolName = first["toolName"] as? String else { return nil }
            if toolName == "Bash" {
                return PendingInteractionOption(
                    label: "Yes, and don't ask again for: \(ruleContent)",
                    description: "Always allow",
                    keystrokeText: "a"
                )
            } else {
                // File tools (Read/Edit/Write): CC always labels these "from this project"
                // regardless of destination (session vs localSettings) — matches shellPermissionHelpers.tsx
                let cleanPath = ruleContent
                    .replacingOccurrences(of: "^//+", with: "/", options: .regularExpression)
                    .replacingOccurrences(of: "/\\*\\*?$", with: "", options: .regularExpression)
                let dirname = URL(fileURLWithPath: cleanPath).lastPathComponent
                return PendingInteractionOption(
                    label: "Yes, allow reading from \(dirname)/ from this project",
                    description: "Allow directory",
                    keystrokeText: "a"
                )
            }
        case "addDirectories":
            guard let dirs = suggestion["directories"] as? [String],
                  let first = dirs.first else { return nil }
            let basename = URL(fileURLWithPath: first).lastPathComponent
            return PendingInteractionOption(
                label: "Yes, allow reading from \(basename)/ from this project",
                description: "Allow directory",
                keystrokeText: "a"
            )
        default:
            return nil
        }
    }

    private func handleResponseCompleteHook(sessionId: String, cwd: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let pid = self.sessionIdToPid[sessionId]
                ?? self.sessions.first { $0.sessionId == sessionId }?.id
                ?? sessionId
            let resolvedCwd = cwd ?? self.sessions.first { $0.sessionId == sessionId }?.cwd
            let lastReply = resolvedCwd.flatMap { self.readLastAssistantMessage(cwd: $0, sessionId: sessionId) }
            let summary = lastReply ?? self.sessions.first { $0.sessionId == sessionId }?.summary
            print("[HookMonitor] Stop sid=\(sessionId.prefix(8)) pid=\(pid) summary=\(summary ?? "nil")")

            // Badge in AgentStatusView for 5s
            self.recentlyDoneSessions.insert(pid)

            // Show completion notification card (opens notch)
            let notification = PendingInteraction(
                sessionId: sessionId,
                pid: Int(pid) ?? 0,
                sessionSummary: summary,
                type: .completion,
                question: nil,
                header: nil,
                options: [],
                multiSelect: false,
                planTitle: nil,
                toolUseId: nil,
                assistantUuid: nil,
                cwd: nil,
                claudeVersion: nil
            )
            self.pendingInteractions.removeAll { $0.sessionId == sessionId && $0.type == .completion }
            self.pendingInteractions.append(notification)

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.recentlyDoneSessions.remove(pid)
                self?.pendingInteractions.removeAll { $0.sessionId == sessionId && $0.type == .completion }
            }
        }
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
            // Update sessionId→pid cache so hook can find PID even after session is removed
            for s in visible {
                if let sid = s.sessionId { self.sessionIdToPid[sid] = s.id }
            }
            kept.append(contentsOf: visible)
            self.sessions = kept
            if app == .claudeCode {
                // Filter out dismissed interactions; clear dismissed keys for interactions no longer present
                let incomingKeys = Set(pendingInteractions.map { "\($0.sessionId)-\($0.type)" })
                self.dismissedInteractionKeys = self.dismissedInteractionKeys.intersection(incomingKeys)

                // Auto-resolve hook-owned permissions: if the JSONL scan no longer detects a pending
                // permission for a session, the user must have responded manually in the terminal.
                let detectedPermSessions = Set(pendingInteractions.filter { $0.type == .permission }.map { $0.sessionId })
                let toAutoResolve = self.hookSourcedPermissionSessions.filter { !detectedPermSessions.contains($0) }
                for sid in toAutoResolve {
                    self.hookSourcedPermissionSessions.remove(sid)
                    self.pendingInteractions.removeAll { $0.sessionId == sid && $0.type == .permission }
                }

                let visible = pendingInteractions.filter { i in
                    !self.dismissedInteractionKeys.contains("\(i.sessionId)-\(i.type)")
                    && !self.hookSourcedPermissionSessions.contains(i.sessionId)
                }
                let hookOwned = self.pendingInteractions.filter {
                    self.hookSourcedPermissionSessions.contains($0.sessionId)
                }
                let completionOwned = self.pendingInteractions.filter { $0.type == .completion }
                self.pendingInteractions = hookOwned + completionOwned + visible
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

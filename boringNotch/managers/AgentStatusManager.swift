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
    @Published private(set) var pendingInteraction: PendingInteraction?

    // When the user dismisses a pending interaction card, we suppress it until a new one arrives
    private var dismissedInteractionKey: String?

    func dismissPendingInteraction() {
        dismissedInteractionKey = pendingInteraction.map { "\($0.sessionId)-\($0.type)" }
        pendingInteraction = nil
    }

    private let warpController = WarpController()
    private let terminalAppController = TerminalAppController()

    func selectOption(claudePid: Int, optionIndex: Int) {
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
            terminalAppController.activateAndSend(digit: digit) {
                self.dismissPendingInteraction()
            }
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
            warpController.activateAndSend(claudePid: claudePid, digit: digit) {
                self.dismissPendingInteraction()
            }
        } else {
            focusTerminal(claudePid: claudePid, dismissOnSuccess: true)
        }
    }

    func focusTerminal(claudePid: Int, dismissOnSuccess: Bool = false) {
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
        if dismissOnSuccess { dismissPendingInteraction() }
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

        // Detect pending interaction across all active sessions
        var detectedInteraction: PendingInteraction?
        for session in updated where session.status != .done {
            guard let pid = Int(session.id) else { continue }

            // First: scan JSONL for AskUserQuestion / ExitPlanMode (authoritative)
            if let sid = session.sessionId, let cwd = session.cwd,
               let interaction = detectPendingInteraction(cwd: cwd, sessionId: sid, pid: pid, sessionSummary: session.summary) {
                detectedInteraction = interaction
                break
            }

            // Fallback: permission prompt — only when JSONL found no interactive tool_use
            // and session JSON explicitly says status=waiting + waitingFor=permission prompt
            if sessionWaitingFor[pid] == "permission prompt" {
                if let sid = session.sessionId, let cwd = session.cwd,
                   let interaction = detectPermissionInteraction(cwd: cwd, sessionId: sid, pid: pid, sessionSummary: session.summary) {
                    detectedInteraction = interaction
                } else {
                    // Last resort: no JSONL info available
                    detectedInteraction = PendingInteraction(
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
                        planTitle: nil
                    )
                }
                break
            }
        }

        updateSessions(removing: .claudeCode, with: updated, pendingInteraction: detectedInteraction)
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
            if !trimmed.isEmpty && !trimmed.hasPrefix("[Image") {
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
        var lastInteractiveTool: (id: String, name: String, input: [String: Any])?
        var respondedToolIds: Set<String> = []

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

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
                let message = obj["message"] as? [String: Any] ?? [:]
                let msgContent = message["content"] as? [[String: Any]] ?? []
                for item in msgContent {
                    guard item["type"] as? String == "tool_use",
                          let toolId = item["id"] as? String,
                          let toolName = item["name"] as? String,
                          ["AskUserQuestion", "ExitPlanMode"].contains(toolName)
                    else { continue }
                    let input = item["input"] as? [String: Any] ?? [:]
                    lastInteractiveTool = (id: toolId, name: toolName, input: input)
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
                planTitle: nil
            )
        } else if tool.name == "ExitPlanMode" {
            // Extract plan title from the plan content (first # heading)
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
                planTitle: planTitle
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
            planTitle: nil
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
    /// reads from outside cwd — the most common case that produces a suggestion.
    private func bashPermissionOption2(command: String, cwd: String) -> PendingInteractionOption? {
        // Extract the first meaningful path from the command that is outside cwd.
        // Claude Code's actual logic calls an LLM to extract a command prefix;
        // we use a heuristic: scan tokens for absolute paths outside cwd.
        let tokens = command.components(separatedBy: .whitespaces)
        let cwdNorm = cwd.hasSuffix("/") ? cwd : cwd + "/"

        for token in tokens {
            let t = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            guard t.hasPrefix("/"), !t.hasPrefix(cwdNorm), t != cwd else { continue }
            let parentDir = (t as NSString).deletingLastPathComponent
            let displayDir = (parentDir as NSString).lastPathComponent.isEmpty ? parentDir : (parentDir as NSString).lastPathComponent

            // Mirrors: "Yes, allow reading from <dir>/ from this project"
            return PendingInteractionOption(
                label: "Yes, allow reading from \(displayDir)/ from this project",
                description: "Allow reads from \(displayDir)",
                keystrokeText: "a"
            )
        }

        // No outside path found → no option 2 (Bash with no suggestions shows only Yes/No)
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
            return toolName
        }
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

    private func updateSessions(removing app: AgentApp, with newSessions: [AgentSession], pendingInteraction: PendingInteraction? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var kept = self.sessions.filter { $0.app != app }
            let visible = newSessions.filter { $0.status != .done || $0.app == .claudeCode }
            kept.append(contentsOf: visible)
            self.sessions = kept
            if app == .claudeCode {
                // Suppress if the user already dismissed this exact interaction
                if let incoming = pendingInteraction {
                    let key = "\(incoming.sessionId)-\(incoming.type)"
                    if key == self.dismissedInteractionKey {
                        // still dismissed — don't update
                    } else {
                        // New interaction or dismissal cleared — show it and clear dismissal key
                        self.dismissedInteractionKey = nil
                        self.pendingInteraction = incoming
                    }
                } else {
                    // No pending interaction: clear dismiss state so next one shows
                    self.dismissedInteractionKey = nil
                    self.pendingInteraction = nil
                }
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

//
//  AgentDebugView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct AgentDebugView: View {
    @ObservedObject var manager = AgentStatusManager.shared
    @State private var refreshID = UUID()
    @State private var isFixingHooks = false

    var body: some View {
        Form {
            hooksSection
            claudeSessionsSection
            codexSection
            warpSection
        }
        .id(refreshID)
        .accentColor(.effectiveAccent)
        .navigationTitle("Claude Code")
        .toolbar {
            Button {
                refreshID = UUID()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .controlSize(.regular)
        }
    }

    // MARK: - Hooks

    private var hooksSection: some View {
        Section {
            ForEach(hookItems, id: \.name) { item in
                HookStatusRow(item: item)
            }

            if !allHooksOK {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("检测到配置异常")
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Text("点击修复将重新生成脚本并注入 ~/.claude/settings.json")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        isFixingHooks = true
                        manager.reinstallHooks()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            isFixingHooks = false
                            refreshID = UUID()
                        }
                    } label: {
                        Label(isFixingHooks ? "修复中…" : "一键修复", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFixingHooks)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Hooks 配置")
        } footer: {
            if allHooksOK {
                Label("所有 Hooks 已就绪", systemImage: "checkmark.shield.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else {
                Text("Hooks 负责将 Claude Code 事件（权限请求、响应完成）实时推送到 boringNotch。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Claude Sessions

    private var claudeSessionsSection: some View {
        Section {
            let claudeSessions = manager.sessions.filter { $0.app == .claudeCode && $0.status != .done }
            if claudeSessions.isEmpty {
                Text("未检测到活跃的 Claude Code 会话")
                    .foregroundColor(.secondary)
                    .font(.callout)
            } else {
                ForEach(claudeSessions) { session in
                    SessionStatusRow(session: session)
                }
            }
        } header: {
            Text("Claude Code 会话")
        }
    }

    // MARK: - Codex

    private var codexSection: some View {
        Section {
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(.secondary)
                Text("Codex 交互拦截尚未支持")
                    .foregroundColor(.secondary)
                    .font(.callout)
                Spacer()
                customBadge(text: "Coming Soon")
            }

            let codexSessions = manager.sessions.filter { $0.app == .codex && $0.status != .done }
            if !codexSessions.isEmpty {
                ForEach(codexSessions) { session in
                    SessionStatusRow(session: session)
                }
            }

            let dbExists = FileManager.default.fileExists(atPath: realHome + "/.codex/logs_2.sqlite")
            HStack(spacing: 8) {
                Image(systemName: dbExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(dbExists ? .green : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("数据源：~/.codex/logs_2.sqlite")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Text(dbExists ? "已找到" : "未找到，请先运行 Codex")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Text("Codex")
                customBadge(text: "Coming Soon")
            }
        }
    }

    // MARK: - Warp

    private var warpSection: some View {
        Section {
            let warpInstalled = isWarpInstalled
            let axTrusted = AXIsProcessTrusted()

            HStack(spacing: 8) {
                Image(systemName: warpInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(warpInstalled ? .green : .secondary)
                Text("Warp 已安装")
                    .font(.callout)
                Spacer()
                if !warpInstalled {
                    Text("未找到")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                Image(systemName: axTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundColor(axTrusted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("辅助功能权限")
                        .font(.callout)
                    Text(axTrusted ? "已授权 — 自动输入可用" : "未授权 — 自动输入将不可用")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !axTrusted {
                    Button("前往授权") {
                        XPCHelperClient.shared.requestAccessibilityAuthorization()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        } header: {
            Text("Warp / 终端权限")
        } footer: {
            Text("自动输入功能需要辅助功能权限，用于向 Warp 或 Terminal.app 发送按键。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    private var scriptPath: String {
        realHome + "/.claude/boringnotch/hooks/on-event.sh"
    }

    private var hookItems: [HookItem] {
        let scriptExists = FileManager.default.fileExists(atPath: scriptPath)
        let scriptExecutable: Bool = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: scriptPath)
            let perms = (attrs?[.posixPermissions] as? Int) ?? 0
            return (perms & 0o111) != 0
        }()

        let settingsPath = realHome + "/.claude/settings.json"
        let (permOK, stopOK, sessionEndOK) = hooksInjected(settingsPath: settingsPath)

        return [
            HookItem(name: "on-event.sh 脚本",       ok: scriptExists,     detail: scriptExists ? "~/.claude/boringnotch/hooks/" : "文件缺失"),
            HookItem(name: "脚本可执行权限",           ok: scriptExecutable, detail: scriptExecutable ? "chmod 755 ✓" : "无执行权限"),
            HookItem(name: "PermissionRequest Hook", ok: permOK,           detail: permOK ? "已注入" : "未注入"),
            HookItem(name: "Stop Hook",              ok: stopOK,           detail: stopOK ? "已注入" : "未注入"),
            HookItem(name: "SessionEnd Hook",        ok: sessionEndOK,     detail: sessionEndOK ? "已注入" : "未注入"),
        ]
    }

    private var allHooksOK: Bool { hookItems.allSatisfy(\.ok) }

    private func hooksInjected(settingsPath: String) -> (Bool, Bool, Bool) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any]
        else { return (false, false, false) }

        func hasHook(_ event: String) -> Bool {
            guard let list = hooks[event] as? [[String: Any]] else { return false }
            return list.contains { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return false }
                return inner.contains { $0["command"] as? String == scriptPath }
            }
        }
        return (hasHook("PermissionRequest"), hasHook("Stop"), hasHook("SessionEnd"))
    }

    private var isWarpInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Stable") != nil
        || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.Warp-Beta") != nil
    }
}

// MARK: - Hook item model + row

private struct HookItem {
    let name: String
    let ok: Bool
    let detail: String
}

private struct HookStatusRow: View {
    let item: HookItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(item.ok ? .green : .red)
                .frame(width: 16)
            Text(item.name)
                .font(.callout)
            Spacer()
            Text(item.detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Session row

private struct SessionStatusRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.summary ?? session.app.rawValue)
                    .font(.callout)
                    .lineLimit(1)
                if let cwd = session.cwd {
                    Text(cwd)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(session.status.rawValue)
                .font(.caption2)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(statusColor.opacity(0.18))
                .clipShape(Capsule())
            if let terminal = session.terminalAppName {
                Text(terminal)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle:    return .orange
        case .done:    return .gray
        }
    }
}

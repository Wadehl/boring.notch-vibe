//
//  AgentDebugView.swift
//  boringNotch
//

import Defaults
import SwiftUI

struct AgentDebugView: View {
    @ObservedObject var manager = AgentStatusManager.shared
    @Default(.claudeCodeAutoInput) var autoInput
    @State private var refreshID = UUID()

    private static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Beta toggle
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Text("ClaudeCode 提示")
                            .font(.title2).bold()
                        Text("Beta")
                            .font(.caption2).bold()
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange)
                            .clipShape(Capsule())
                    }

                    Text("在 notch 中拦截 Claude Code 的权限请求，并提供快捷选项。")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Divider()

                    Toggle(isOn: $autoInput) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("自动输入（实验性）")
                                .font(.body)
                            Text("开启后点击选项会自动向终端发送按键。关闭则仅聚焦终端，由你手动输入。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if autoInput {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("自动输入功能仍在实验阶段，在选项数量与 CC 不一致时可能发送错误按键，请留意 notch 中的错位提示。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()

                // Debug info
                Group {
                    HStack {
                        Text("运行状态").font(.headline)
                        Spacer()
                        Button("刷新") { refreshID = UUID() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }

                    Text("Active Sessions (\(manager.sessions.count))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if manager.sessions.isEmpty {
                        Text("未检测到 Claude Code 会话")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(manager.sessions) { session in
                            sessionCard(session)
                        }
                    }
                }

                Divider()

                Group {
                    Text("数据源").font(.headline)

                    dataSourceRow(
                        label: "Claude sessions",
                        path: "~/.claude/sessions/",
                        exists: FileManager.default.fileExists(
                            atPath: Self.realHome + "/.claude/sessions")
                    )
                    dataSourceRow(
                        label: "Codex logs DB",
                        path: "~/.codex/logs_2.sqlite",
                        exists: FileManager.default.fileExists(
                            atPath: Self.realHome + "/.codex/logs_2.sqlite")
                    )
                }
            }
            .padding()
        }
        .id(refreshID)
        .navigationTitle("ClaudeCode 提示")
    }

    private func sessionCard(_ session: AgentSession) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor(session.status))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(session.app.rawValue)  ·  \(session.id.prefix(12))")
                    .font(.caption).bold()
                if let cwd = session.cwd {
                    Text(cwd).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(session.status.rawValue)
                .font(.caption2)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(statusColor(session.status).opacity(0.2))
                .clipShape(Capsule())
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func dataSourceRow(label: String, path: String, exists: Bool) -> some View {
        HStack {
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(exists ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).bold()
                Text(path).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func statusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .running: return .green
        case .idle:    return .orange
        case .done:    return .gray
        }
    }
}

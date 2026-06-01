//
//  AgentDebugView.swift
//  boringNotch
//

import SwiftUI

struct AgentDebugView: View {
    @ObservedObject var manager = AgentStatusManager.shared
    @State private var refreshID = UUID()

    private static var realHome: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Text("Agent Status Debug")
                        .font(.title2).bold()
                    Spacer()
                    Button("Refresh") {
                        refreshID = UUID()
                    }
                    .buttonStyle(.bordered)
                }

                Divider()

                // Raw sessions
                Group {
                    Text("Active Sessions (\(manager.sessions.count))")
                        .font(.headline)

                    if manager.sessions.isEmpty {
                        Text("No sessions detected")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(manager.sessions) { session in
                            sessionCard(session)
                        }
                    }
                }

                Divider()

                // Data source paths
                Group {
                    Text("Data Sources").font(.headline)

                    dataSourceRow(
                        label: "Claude sessions dir",
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

                Divider()

                // Raw file listing
                Group {
                    Text("Claude Session Files").font(.headline)
                    let sessionDir = URL(fileURLWithPath: Self.realHome + "/.claude/sessions")
                    let result = Result { try FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil) }
                    switch result {
                    case .failure(let err):
                        Text("Error: \(err.localizedDescription)")
                            .font(.caption).foregroundColor(.red)
                    case .success(let files) where files.isEmpty:
                        Text("Directory exists but is empty").foregroundColor(.secondary)
                    case .success(let files):
                        ForEach(files, id: \.path) { file in
                            if let data = try? Data(contentsOf: file),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(file.lastPathComponent).font(.caption).bold()
                                    Text("pid: \(json["pid"] as? Int ?? -1)  status: \(json["status"] as? String ?? "?")")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text("cwd: \((json["cwd"] as? String ?? "").split(separator: "/").last.map(String.init) ?? "")")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .id(refreshID)
        .navigationTitle("Agent Debug")
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

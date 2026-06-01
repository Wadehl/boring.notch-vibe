//
//  AgentStatusView.swift
//  boringNotch
//

import SwiftUI

// MARK: - App icon shapes (from official SVGs)

private let claudeColor = Color(red: 217/255, green: 119/255, blue: 87/255)
private let codexColor  = Color(red: 100/255, green: 160/255, blue: 240/255)

private struct ClaudeAppIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 24.0
            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: x*s, y: y*s, width: w*s, height: h*s))
            }
            let c = GraphicsContext.Shading.color(claudeColor)
            ctx.fill(r(3, 5, 18, 12.079), with: c)
            ctx.fill(r(6, 2.153, 1.488, 2.847), with: c)
            ctx.fill(r(16.51, 2.153, 1.49, 2.847), with: c)
            ctx.blendMode = .clear
            ctx.fill(r(6, 8.102, 1.488, 2.847), with: .color(.black))
            ctx.fill(r(16.51, 8.102, 1.49, 2.847), with: .color(.black))
            ctx.blendMode = .normal
            ctx.fill(r(0, 10.95, 3, 3.1), with: c)
            ctx.fill(r(21, 10.95, 3, 3.1), with: c)
            ctx.fill(r(3, 17.079, 1.488, 2.921), with: c)
            ctx.fill(r(6, 17.079, 1.488, 2.921), with: c)
            ctx.fill(r(15, 17.079, 1.488, 2.921), with: c)
            ctx.fill(r(18.512, 17.079, 1.488, 2.921), with: c)
        }
        .compositingGroup()
    }
}

// Codex SVG is a complex organic path — use SF Symbol as close proxy,
// tinted with the Codex brand color.
private struct CodexAppIcon: View {
    var body: some View {
        Image(systemName: "brain.head.profile")
            .resizable()
            .scaledToFit()
            .foregroundColor(codexColor)
    }
}

// MARK: - Main view

struct AgentStatusView: View {
    @ObservedObject var manager = AgentStatusManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(manager.sessions.filter { $0.status != .done }) { session in
                AgentSessionRow(session: session)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Session row

struct AgentSessionRow: View {
    let session: AgentSession
    @State private var spinnerRotation: Double = 0

    var body: some View {
        HStack(spacing: 8) {
            // App icon
            ZStack {
                Circle()
                    .fill(appColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Group {
                    if session.app == .claudeCode {
                        ClaudeAppIcon()
                    } else {
                        CodexAppIcon()
                    }
                }
                .frame(width: 16, height: 16)

                // Running indicator ring
                if session.status == .running {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(appColor.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                        .rotationEffect(.degrees(spinnerRotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                spinnerRotation = 360
                            }
                        }
                }
            }

            // Text
            VStack(alignment: .leading, spacing: 1) {
                if let summary = session.summary {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text(appLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                }
                Text(subtitleText)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Spacer()

            // Status badge
            Text(statusLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var subtitleText: String {
        if let cwd = session.cwd {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }
        return appLabel
    }

    private var appLabel: String {
        switch session.app {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private var appColor: Color {
        switch session.app {
        case .claudeCode: return claudeColor
        case .codex: return codexColor
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .running: return "running"
        case .idle:    return "waiting"
        case .done:    return "done"
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

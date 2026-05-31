//
//  AgentStatusView.swift
//  boringNotch
//

import SwiftUI

struct AgentStatusView: View {
    @ObservedObject var manager = AgentStatusManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(manager.sessions) { session in
                AgentSessionRow(session: session)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

struct AgentSessionRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            statusIndicator
            VStack(alignment: .leading, spacing: 1) {
                Text(appLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                if let cwd = session.cwd {
                    Text(URL(fileURLWithPath: cwd).lastPathComponent)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            Spacer()
            Text(statusLabel)
                .font(.caption2)
                .foregroundColor(statusColor.opacity(0.8))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.2))
                .frame(width: 22, height: 22)

            if session.status == .running {
                // Spinning arc for running state
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(statusColor, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .rotationEffect(.degrees(spinnerRotation))
                    .onAppear { startSpinner() }
            } else {
                Image(systemName: statusIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(statusColor)
            }
        }
    }

    @State private var spinnerRotation: Double = 0

    private func startSpinner() {
        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
            spinnerRotation = 360
        }
    }

    private var appLabel: String {
        switch session.app {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .running: return "running"
        case .idle:    return "waiting"
        case .done:    return "done"
        }
    }

    private var statusIcon: String {
        switch session.status {
        case .running: return "arrow.trianglehead.2.clockwise"
        case .idle:    return "pause.fill"
        case .done:    return "checkmark"
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

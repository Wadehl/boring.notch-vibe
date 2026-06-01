//
//  AgentStatusView.swift
//  boringNotch
//

import SwiftUI

// MARK: - App icon shapes (from official SVGs)

private let claudeColor = Color(red: 217/255, green: 119/255, blue: 87/255)

// Codex gradient: top #B1A7FF → mid #7A9DFF → bottom #3941FF
private let codexGradient = LinearGradient(
    stops: [
        .init(color: Color(red: 177/255, green: 167/255, blue: 1.0),    location: 0.0),
        .init(color: Color(red: 122/255, green: 157/255, blue: 1.0),    location: 0.5),
        .init(color: Color(red:  57/255, green:  65/255, blue: 1.0),    location: 1.0),
    ],
    startPoint: .top,
    endPoint: .bottom
)

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

private struct CodexShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        let ox = rect.minX + (rect.width  - 24*s) / 2
        let oy = rect.minY + (rect.height - 24*s) / 2
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x*s, y: oy + y*s)
        }
        var p = Path()
        p.move(to: pt(9.0640, 3.3440))
        p.addCurve(to: pt(11.3490, 3.0320), control1: pt(9.7866, 3.0467), control2: pt(10.5732, 2.9393))
        p.addCurve(to: pt(14.0220, 4.3070), control1: pt(12.3490, 3.1470), control2: pt(13.2400, 3.5720))
        p.addCurve(to: pt(14.0590, 4.3280), control1: pt(14.0320, 4.3170), control2: pt(14.0460, 4.3240))
        p.addCurve(to: pt(14.1020, 4.3280), control1: pt(14.0731, 4.3315), control2: pt(14.0879, 4.3315))
        p.addCurve(to: pt(17.1480, 4.6030), control1: pt(15.1186, 4.0655), control2: pt(16.1948, 4.1626))
        p.addLine(to: pt(17.1950, 4.6250))
        p.addLine(to: pt(17.3110, 4.6820))
        p.addCurve(to: pt(19.4990, 7.0810), control1: pt(18.3088, 5.1877), control2: pt(19.0870, 6.0410))
        p.addCurve(to: pt(19.8140, 8.6760), control1: pt(19.7080, 7.5910), control2: pt(19.8120, 8.1220))
        p.addCurve(to: pt(19.6800, 9.8990), control1: pt(19.8290, 9.0880), control2: pt(19.7839, 9.5000))
        p.addCurve(to: pt(19.7100, 10.0140), control1: pt(19.6696, 9.9399), control2: pt(19.6809, 9.9834))
        p.addCurve(to: pt(20.8930, 12.1840), control1: pt(20.3040, 10.6210), control2: pt(20.6980, 11.3440))
        p.addCurve(to: pt(20.0060, 16.0380), control1: pt(21.1820, 13.6090), control2: pt(20.8860, 14.8940))
        p.addLine(to: pt(19.8700, 16.2040))
        p.addCurve(to: pt(17.6690, 17.5920), control1: pt(19.2872, 16.8712), control2: pt(18.5222, 17.3536))
        p.addCurve(to: pt(17.5880, 17.6680), control1: pt(17.6314, 17.6030), control2: pt(17.6014, 17.6312))
        p.addCurve(to: pt(16.8480, 19.1620), control1: pt(17.3970, 18.2190), control2: pt(17.2050, 18.6910))
        p.addCurve(to: pt(13.1370, 21.0000), control1: pt(15.9480, 20.3490), control2: pt(14.6260, 21.0080))
        p.addCurve(to: pt(9.9800, 19.6980), control1: pt(11.9500, 20.9940), control2: pt(10.8980, 20.5600))
        p.addCurve(to: pt(9.8750, 19.6740), control1: pt(9.9519, 19.6717), control2: pt(9.9118, 19.6625))
        p.addCurve(to: pt(8.6710, 19.8120), control1: pt(9.4870, 19.7990), control2: pt(9.0950, 19.8170))
        p.addCurve(to: pt(6.7260, 19.3460), control1: pt(7.9957, 19.8066), control2: pt(7.3305, 19.6472))
        p.addCurve(to: pt(5.1160, 18.0110), control1: pt(6.0928, 19.0322), control2: pt(5.5416, 18.5751))
        p.addCurve(to: pt(4.7020, 17.3940), control1: pt(4.9640, 17.8090), control2: pt(4.8130, 17.6190))
        p.addCurve(to: pt(4.3320, 16.4330), control1: pt(4.5505, 17.0852), control2: pt(4.4266, 16.7637))
        p.addCurve(to: pt(4.3180, 14.1350), control1: pt(4.1322, 15.6806), control2: pt(4.1274, 14.8898))
        p.addCurve(to: pt(4.3240, 14.0790), control1: pt(4.3243, 14.1170), control2: pt(4.3263, 14.0979))
        p.addCurve(to: pt(4.2970, 14.0310), control1: pt(4.3206, 14.0604), control2: pt(4.3111, 14.0436))
        p.addCurve(to: pt(3.2630, 12.3800), control1: pt(3.8351, 13.5634), control2: pt(3.4820, 12.9997))
        p.addCurve(to: pt(3.0120, 11.1880), control1: pt(3.1174, 11.9983), control2: pt(3.0326, 11.5960))
        p.addCurve(to: pt(3.1530, 9.5880), control1: pt(2.9757, 10.6506), control2: pt(3.0232, 10.1108))
        p.addCurve(to: pt(5.0860, 6.9700), control1: pt(3.4900, 8.4760), control2: pt(4.1350, 7.6030))
        p.addCurve(to: pt(5.6870, 6.6400), control1: pt(5.2980, 6.8290), control2: pt(5.4990, 6.7190))
        p.addCurve(to: pt(6.3330, 6.4130), control1: pt(5.9020, 6.5510), control2: pt(6.1170, 6.4760))
        p.addCurve(to: pt(6.3980, 6.3470), control1: pt(6.3644, 6.4033), control2: pt(6.3888, 6.3785))
        p.addCurve(to: pt(7.2270, 4.7320), control1: pt(6.5620, 5.7580), control2: pt(6.8441, 5.2086))
        p.addCurve(to: pt(9.0640, 3.3440), control1: pt(7.7097, 4.1190), control2: pt(8.3425, 3.6409))
        p.closeSubpath()
        p.move(to: pt(12.5460, 13.9090))
        p.addCurve(to: pt(11.9447, 14.5450), control1: pt(12.2086, 13.9279), control2: pt(11.9447, 14.2071))
        p.addCurve(to: pt(12.5460, 15.1810), control1: pt(11.9447, 14.8829), control2: pt(12.2086, 15.1621))
        p.addLine(to: pt(16.1820, 15.1810))
        p.addCurve(to: pt(16.7633, 14.8737), control1: pt(16.4177, 15.1942), control2: pt(16.6414, 15.0760))
        p.addCurve(to: pt(16.7633, 14.2163), control1: pt(16.8851, 14.6715), control2: pt(16.8851, 14.4185))
        p.addCurve(to: pt(16.1820, 13.9090), control1: pt(16.6414, 14.0140), control2: pt(16.4177, 13.8958))
        p.addLine(to: pt(12.5460, 13.9090))
        p.closeSubpath()
        p.move(to: pt(8.4620, 9.2300))
        p.addCurve(to: pt(7.6035, 9.0100), control1: pt(8.2821, 8.9370), control2: pt(7.9021, 8.8396))
        p.addCurve(to: pt(7.3560, 9.8610), control1: pt(7.3048, 9.1804), control2: pt(7.1953, 9.5570))
        p.addLine(to: pt(8.6280, 12.0850))
        p.addLine(to: pt(7.3620, 14.2210))
        p.addCurve(to: pt(7.3547, 14.8574), control1: pt(7.2461, 14.4166), control2: pt(7.2433, 14.6592))
        p.addCurve(to: pt(7.9022, 15.1819), control1: pt(7.4662, 15.0556), control2: pt(7.6749, 15.1793))
        p.addCurve(to: pt(8.4570, 14.8700), control1: pt(8.1296, 15.1845), control2: pt(8.3411, 15.0656))
        p.addLine(to: pt(9.9110, 12.4150))
        p.addCurve(to: pt(9.9160, 11.7750), control1: pt(10.0277, 12.2181), control2: pt(10.0296, 11.9737))
        p.addLine(to: pt(8.4620, 9.2300))
        p.closeSubpath()
        return p
    }
}

private struct CodexAppIcon: View {
    var body: some View {
        CodexShape()
            .fill(codexGradient, style: FillStyle(eoFill: true))
    }
}

// MARK: - Main view

struct AgentStatusView: View {
    @ObservedObject var manager = AgentStatusManager.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(manager.sessions.filter { $0.status != .done }) { session in
                    AgentSessionRow(session: session)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Session row

struct AgentSessionRow: View {
    let session: AgentSession
    @State private var spinnerRotation: Double = 0
    @State private var isHovering = false
    @ObservedObject private var manager = AgentStatusManager.shared

    var body: some View {
        Button(action: focusTerminal) {
            HStack(spacing: 10) {
                // App icon with spinner
                ZStack {
                    Circle()
                        .fill(appColor.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Group {
                        if session.app == .claudeCode {
                            ClaudeAppIcon()
                        } else {
                            CodexAppIcon()
                        }
                    }
                    .frame(width: 17, height: 17)

                    if session.status == .running {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(appColor.opacity(0.7), lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(spinnerRotation))
                            .onAppear {
                                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                    spinnerRotation = 360
                                }
                            }
                    }
                }

                // Text block
                VStack(alignment: .leading, spacing: 2) {
                    // Title
                    Text(session.summary ?? appLabel)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)

                    // Last user message
                    if let msg = session.lastUserMessage ?? session.cwd.map({ URL(fileURLWithPath: $0).lastPathComponent }) {
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundColor(.gray.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    // Status line
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(statusLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(statusColor)
                        if isHovering {
                            Text("· click to jump")
                                .font(.system(size: 10))
                                .foregroundColor(.gray.opacity(0.5))
                                .transition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
                }

                Spacer()

                // Right column: terminal tag + duration
                VStack(alignment: .trailing, spacing: 4) {
                    if let terminal = session.terminalAppName {
                        Text(terminal)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(duration)
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(isHovering ? 0.06 : 0.03))
                    .animation(.easeInOut(duration: 0.15), value: isHovering)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cursor(.pointingHand)
    }

    private func focusTerminal() {
        print("[AgentSessionRow] focusTerminal tapped, session.id=\(session.id)")
        if let pid = Int(session.id) {
            manager.focusTerminal(claudePid: pid)
        } else {
            print("[AgentSessionRow] ERROR: could not parse pid from session.id=\(session.id)")
        }
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
        case .codex: return Color(red: 177/255, green: 167/255, blue: 1.0)
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .running: return "Running"
        case .idle:    return "Idling"
        case .done:    return "Done"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .running: return .green
        case .idle:    return .orange
        case .done:    return .gray
        }
    }

    private var duration: String {
        let elapsed = Date().timeIntervalSince(session.startedAt)
        if elapsed < 60 { return "\(Int(elapsed))s" }
        let mins = Int(elapsed / 60)
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h\(mins % 60)m"
    }
}

// MARK: - Cursor modifier (shared with AgentInteractionView)

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { inside in
            if inside { cursor.push() } else { NSCursor.pop() }
        }
    }
}

//
//  AgentStatusView.swift
//  boringNotch
//

import SwiftUI

// MARK: - App icon shapes (from official SVGs)

private let claudeColor = Color(red: 217/255, green: 119/255, blue: 87/255)
private let codexColor  = Color(red: 217/255, green: 119/255, blue: 87/255) // same brand orange family

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

// Codex icon: organic blob shape from official SVG (viewBox 0 0 24 24)
// Rendered via SwiftUI Path scaled to fit the canvas size.
private struct CodexShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x*s + rect.minX, y: y*s + rect.minY) }
        var p = Path()
        // Outer blob (traced from SVG fill-rule=evenodd outer contour)
        p.move(to: pt(8.086, 0.457))
        p.addCurve(to: pt(11.132, 0.042), control1: pt(9.169, 0.009), control2: pt(10.15, -0.1))
        p.addCurve(to: pt(14.696, 1.742), control1: pt(12.465, 0.195), control2: pt(13.653, 0.762))
        p.addCurve(to: pt(18.757, 2.108), control1: pt(15.918, 1.395), control2: pt(17.272, 1.517))
        p.addCurve(to: pt(21.675, 5.306), control1: pt(20.114, 2.811), control2: pt(21.087, 3.878))
        p.addCurve(to: pt(21.916, 8.963), control1: pt(22.097, 6.579), control2: pt(22.116, 7.744))
        p.addCurve(to: pt(23.494, 11.854), control1: pt(22.651, 9.573), control2: pt(23.228, 10.618))
        p.addCurve(to: pt(22.311, 16.994), control1: pt(23.879, 13.755), control2: pt(23.484, 15.469))
        p.addCurve(to: pt(19.377, 18.845), control1: pt(21.566, 17.726), control2: pt(20.518, 18.381))
        p.addCurve(to: pt(18.39, 20.837), control1: pt(19.122, 19.581), control2: pt(18.866, 20.209))
        p.addCurve(to: pt(13.442, 23.288), control1: pt(17.191, 22.419), control2: pt(15.428, 23.299))
        p.addCurve(to: pt(9.232, 21.552), control1: pt(11.859, 23.28), control2: pt(10.456, 22.701))
        p.addCurve(to: pt(7.628, 21.737), control1: pt(8.747, 21.184), control2: pt(8.225, 21.208))
        p.addCurve(to: pt(4.485, 19.956), control1: pt(6.32, 21.57), control2: pt(5.168, 20.953))
        p.addCurve(to: pt(2.339, 17.613), control1: pt(3.638, 19.225), control2: pt(2.882, 18.478))
        p.addCurve(to: pt(1.512, 15.508), control1: pt(1.935, 17.091), control2: pt(1.734, 16.333))
        p.addCurve(to: pt(1.495, 12.444), control1: pt(1.272, 14.408), control2: pt(1.261, 13.383))
        p.addCurve(to: pt(0.115, 10.242), control1: pt(1.066, 11.724), control2: pt(0.537, 10.968))
        p.addCurve(to: pt(0.303, 6.521), control1: pt(-0.533, 8.653), control2: pt(-0.23, 7.41))
        p.addCurve(to: pt(2.88, 3.028), control1: pt(0.753, 5.037), control2: pt(1.612, 3.873))
        p.addCurve(to: pt(5.635, 2.31), control1: pt(3.594, 2.492), control2: pt(4.516, 2.242))
        p.addCurve(to: pt(8.086, 0.457), control1: pt(6.315, 1.464), control2: pt(7.132, 0.846))
        p.closeSubpath()

        // Left chevron element
        p.move(to: pt(7.282, 8.307))
        p.addCurve(to: pt(6.61, 8.549), control1: pt(7.008, 8.089), control2: pt(6.717, 8.2))
        p.addCurve(to: pt(7.003, 9.314), control1: pt(6.503, 8.898), control2: pt(6.697, 9.201))
        p.addLine(to: pt(8.697, 12.279))
        p.addLine(to: pt(7.009, 15.127))
        p.addCurve(to: pt(7.856, 16.298), control1: pt(6.741, 15.628), control2: pt(7.189, 16.077))
        p.addCurve(to: pt(8.469, 15.991), control1: pt(8.116, 16.298), control2: pt(8.335, 16.188))
        p.addLine(to: pt(10.409, 12.719))
        p.addCurve(to: pt(10.402, 11.865), control1: pt(10.641, 12.434), control2: pt(10.638, 12.145))
        p.addLine(to: pt(8.462, 8.472))
        p.addCurve(to: pt(7.282, 8.307), control1: pt(8.208, 8.094), control2: pt(7.658, 8.091))
        p.closeSubpath()

        // Right dash element
        p.move(to: pt(12.728, 14.547))
        p.addCurve(to: pt(12.728, 16.242), control1: pt(12.259, 14.547), control2: pt(12.259, 16.242))
        p.addLine(to: pt(17.576, 16.242))
        p.addCurve(to: pt(17.576, 14.547), control1: pt(18.045, 16.242), control2: pt(18.045, 14.547))
        p.addLine(to: pt(12.728, 14.547))
        p.closeSubpath()

        return p
    }
}

private struct CodexAppIcon: View {
    var body: some View {
        CodexShape()
            .fill(codexColor, style: FillStyle(eoFill: true))
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

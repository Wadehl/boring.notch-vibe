//
//  AgentClosedNotchView.swift
//  boringNotch
//

import SwiftUI

// MARK: - Clawd icon (matches official Claude Code SVG, viewBox 0 0 24 24)

private let clawdColor = Color(red: 217/255, green: 119/255, blue: 87/255)

struct ClawdIcon: View {
    let size: CGFloat

    var body: some View {
        Canvas { ctx, canvasSize in
            let scale = canvasSize.width / 24.0

            func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path {
                Path(CGRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale))
            }

            let color = GraphicsContext.Shading.color(clawdColor)

            // Main body
            ctx.fill(r(3, 5, 18, 12.079), with: color)

            // Top antenna tabs (same x as eyes, above body)
            ctx.fill(r(6,     2.153, 1.488, 2.847), with: color)
            ctx.fill(r(16.51, 2.153, 1.49,  2.847), with: color)

            // Eye holes (cut via .clear)
            ctx.blendMode = .clear
            ctx.fill(r(6,     8.102, 1.488, 2.847), with: .color(.black))
            ctx.fill(r(16.51, 8.102, 1.49,  2.847), with: .color(.black))
            ctx.blendMode = .normal

            // Side arms (left/right bumps at mid-body)
            ctx.fill(r(0,  10.95, 3, 3.1), with: color)
            ctx.fill(r(21, 10.95, 3, 3.1), with: color)

            // Four bottom legs
            let legY: CGFloat = 17.079
            let legH: CGFloat = 2.921
            ctx.fill(r(3,      legY, 1.488, legH), with: color)
            ctx.fill(r(6,      legY, 1.488, legH), with: color)
            ctx.fill(r(15,     legY, 1.488, legH), with: color)
            ctx.fill(r(18.512, legY, 1.488, legH), with: color)
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

// MARK: - Glow wrapper

struct ClawdGlowIcon: View {
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        ClawdIcon(size: size)
            .shadow(color: clawdColor.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 8 : 4)
            .shadow(color: clawdColor.opacity(0.3), radius: 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Main closed-notch agent bar

struct AgentClosedNotchView: View {
    @ObservedObject var manager = AgentStatusManager.shared

    private var summary: String {
        manager.activeSessionSummary ?? "AI agents active"
    }

    private var count: Int {
        manager.activeSessions.count
    }

    var body: some View {
        HStack(spacing: 10) {
            ClawdGlowIcon(size: 18)
                .padding(.leading, 4)

            Text(summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

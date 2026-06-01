//
//  AgentClosedNotchView.swift
//  boringNotch
//

import SwiftUI

// MARK: - Clawd icon (matches official Claude Code SVG, viewBox 0 0 24 24)

private let clawdColor = Color(red: 217/255, green: 119/255, blue: 87/255)

// Two walk frames: legs in alternating positions
private enum ClawdFrame {
    case a // neutral: all legs down
    case b // walk: left legs raised, right legs lowered (stagger)
}

struct ClawdIcon: View {
    let size: CGFloat
    var frame: ClawdFrame = .a

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

            // Eye holes (cut via .clear blendMode)
            ctx.blendMode = .clear
            ctx.fill(r(6,     8.102, 1.488, 2.847), with: .color(.black))
            ctx.fill(r(16.51, 8.102, 1.49,  2.847), with: .color(.black))
            ctx.blendMode = .normal

            // Side arms (left/right bumps at mid-body)
            ctx.fill(r(0,  10.95, 3, 3.1), with: color)
            ctx.fill(r(21, 10.95, 3, 3.1), with: color)

            // Four bottom legs with walk animation
            // Frame A: all legs at y=17.079 (neutral)
            // Frame B: outer legs raised 1pt, inner legs lowered 1pt (stagger)
            let baseY: CGFloat = 17.079
            let legH: CGFloat = 2.921

            let (y1, h1, y2, h2, y3, h3, y4, h4): (CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
            switch frame {
            case .a:
                // Neutral: all legs same
                (y1, h1) = (baseY, legH)
                (y2, h2) = (baseY, legH)
                (y3, h3) = (baseY, legH)
                (y4, h4) = (baseY, legH)
            case .b:
                // Walk: outer legs raised (shorter, higher), inner legs lowered (longer)
                (y1, h1) = (baseY - 1.5, legH - 0.5) // leg 1 raised
                (y2, h2) = (baseY + 0.5, legH + 0.5) // leg 2 lowered
                (y3, h3) = (baseY + 0.5, legH + 0.5) // leg 3 lowered
                (y4, h4) = (baseY - 1.5, legH - 0.5) // leg 4 raised
            }

            ctx.fill(r(3,      y1, 1.488, h1), with: color)
            ctx.fill(r(6,      y2, 1.488, h2), with: color)
            ctx.fill(r(15,     y3, 1.488, h3), with: color)
            ctx.fill(r(18.512, y4, 1.488, h4), with: color)
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

// MARK: - Animated walking Clawd with glow

struct ClawdWalkingIcon: View {
    let size: CGFloat
    @State private var walkFrame: ClawdFrame = .a
    @State private var pulse = false

    var body: some View {
        ClawdIcon(size: size, frame: walkFrame)
            .shadow(color: clawdColor.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 8 : 4)
            .shadow(color: clawdColor.opacity(0.3), radius: 2)
            .onAppear {
                // Glow pulse
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
                // Walk cycle: toggle frame every 0.45s
                Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                    withAnimation(.linear(duration: 0.1)) {
                        walkFrame = walkFrame == .a ? .b : .a
                    }
                }
            }
    }
}

// MARK: - Main closed-notch agent bar

struct AgentClosedNotchView: View {
    let hasHardwareNotch: Bool
    @ObservedObject var manager = AgentStatusManager.shared

    private var summary: String {
        manager.activeSessionSummary ?? "AI agents active"
    }

    private var count: Int {
        manager.activeSessions.count
    }

    var body: some View {
        if hasHardwareNotch {
            // On notch screens: push icon left and count right, hide middle text under hardware notch
            HStack(spacing: 0) {
                ClawdWalkingIcon(size: 18)
                    .padding(.leading, 6)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .padding(.trailing, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // On non-notch screens: show full bar with summary text
            HStack(spacing: 10) {
                ClawdWalkingIcon(size: 18)
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
}

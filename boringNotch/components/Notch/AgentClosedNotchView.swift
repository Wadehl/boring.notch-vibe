//
//  AgentClosedNotchView.swift
//  boringNotch
//

import SwiftUI

// MARK: - Clawd icon (matches official Claude Code SVG, viewBox 0 0 24 24)

private let clawdColor = Color(red: 217/255, green: 119/255, blue: 87/255)

// Two walk frames: legs in alternating positions
fileprivate enum ClawdFrame {
    case a // neutral: all legs down
    case b // walk: left legs raised, right legs lowered (stagger)
}

struct ClawdIcon: View {
    let size: CGFloat
    fileprivate var walkFrame: ClawdFrame = .a

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
            // Frame A: legs 1&3 shift left 1px, legs 2&4 shift right 1px
            // Frame B: legs 1&3 shift right 1px, legs 2&4 shift left 1px
            let baseY: CGFloat = 17.079
            let legH: CGFloat = 2.921
            let shift: CGFloat = 1.0  // horizontal shift in SVG units

            let (x1, x2, x3, x4): (CGFloat, CGFloat, CGFloat, CGFloat)
            switch walkFrame {
            case .a:
                x1 = 3      - shift; x2 = 6      + shift
                x3 = 15     - shift; x4 = 18.512 + shift
            case .b:
                x1 = 3      + shift; x2 = 6      - shift
                x3 = 15     + shift; x4 = 18.512 - shift
            }

            ctx.fill(r(x1, baseY, 1.488, legH), with: color)
            ctx.fill(r(x2, baseY, 1.488, legH), with: color)
            ctx.fill(r(x3, baseY, 1.488, legH), with: color)
            ctx.fill(r(x4, baseY, 1.488, legH), with: color)
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
        ClawdIcon(size: size, walkFrame: walkFrame)
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

    private var summary: String? {
        manager.activeSessionSummary
    }

    private var count: Int {
        manager.activeSessions.count
    }

    var body: some View {
        if hasHardwareNotch {
            // On notch screens: icon flush-left, badge flush-right, notch covers the middle
            HStack(spacing: 0) {
                ClawdWalkingIcon(size: 16)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // On non-notch screens: show full bar with summary text
            HStack(spacing: 10) {
                ClawdWalkingIcon(size: 18)
                    .padding(.leading, 4)

                if let text = summary {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer()
                }

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

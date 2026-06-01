//
//  AgentClosedNotchView.swift
//  boringNotch
//

import SwiftUI

// MARK: - Pixel Claw'd logo (matches the Claude Code mascot aesthetic)

private let clawdColor = Color(red: 232/255, green: 120/255, blue: 88/255)

struct ClawdPixelIcon: View {
    let size: CGFloat

    // 9x10 pixel grid defining Claw'd silhouette
    private let pixels: [[Bool]] = [
        [false, false, true,  true,  true,  true,  true,  false, false],
        [false, true,  true,  true,  true,  true,  true,  true,  false],
        [true,  true,  false, true,  true,  true,  false, true,  true ],
        [true,  true,  true,  true,  true,  true,  true,  true,  true ],
        [true,  true,  false, false, false, false, false, true,  true ],
        [false, true,  true,  true,  true,  true,  true,  true,  false],
        [false, false, true,  true,  false, true,  true,  false, false],
        [false, true,  true,  false, false, false, true,  true,  false],
        [false, true,  false, false, false, false, false, true,  false],
        [false, true,  false, false, false, false, false, true,  false],
    ]

    var body: some View {
        let cols = pixels[0].count
        let rows = pixels.count
        let px = size / CGFloat(max(cols, rows))

        Canvas { ctx, _ in
            for (r, row) in pixels.enumerated() {
                for (c, on) in row.enumerated() where on {
                    let rect = CGRect(x: CGFloat(c) * px, y: CGFloat(r) * px, width: px, height: px)
                    ctx.fill(Path(rect), with: .color(clawdColor))
                }
            }
        }
        .frame(width: CGFloat(cols) * px, height: CGFloat(rows) * px)
    }
}

// MARK: - Glow wrapper

struct ClawdGlowIcon: View {
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        ClawdPixelIcon(size: size)
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

//
//  AgentClosedNotchView.swift
//  boringNotch
//

import Defaults
import SwiftUI

// MARK: - Clawd icon (matches official Claude Code SVG, viewBox 0 0 24 24)

private let clawdColor = Color(red: 217/255, green: 119/255, blue: 87/255)

private extension CGRect {
    func with(cornerRadius r: CGFloat) -> Path {
        Path(roundedRect: self, cornerRadius: r)
    }
}

// Two walk frames: legs in alternating positions
fileprivate enum ClawdFrame {
    case a // neutral: all legs down
    case b // walk: left legs raised, right legs lowered (stagger)
}

struct ClawdIcon: View {
    let size: CGFloat
    fileprivate var walkFrame: ClawdFrame = .a

    init(size: CGFloat) { self.size = size }
    fileprivate init(size: CGFloat, walkFrame: ClawdFrame) {
        self.size = size
        self.walkFrame = walkFrame
    }

    var body: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 24.0
            // Walk: left legs shift left, right legs shift right (frame A), then swap (frame B)
            let d: CGFloat = walkFrame == .a ? 0.7 : -0.7

            // Official Claude Code SVG (viewBox 0 0 24 24, fill-rule=evenodd) hand-parsed.
            // Absolute coordinates from: M20.998 10.949 H24 v3.102 h-3 v3.028 h-1.487 V20
            //   H18 v-2.921 h-1.487 V20 H15 v-2.921 H9 V20 H7.488 v-2.921 H6 V20
            //   H4.487 v-2.921 H3 V14.05 H0 V10.95 h3 V5 h17.998 v5.949 z
            //
            // Leg x-ranges in the static path:
            //   Right pair: 19.513..18 (leg1) and 16.513..15 (leg2)
            //   Left  pair: 7.488..9   (leg3) and 4.487..6   (leg4)
            // We replicate the body+arms without legs, then draw legs shifted.

            var p = Path()

            // Body + arms contour (no leg notches — we'll fill legs separately)
            // Right arm upper: (20.998,10.949)→(24,10.949)→(24,14.051)→(21,14.051)→(21,17.079)
            p.move(to:    .init(x: 20.998*s, y: 10.949*s))
            p.addLine(to: .init(x: 24*s,     y: 10.949*s))
            p.addLine(to: .init(x: 24*s,     y: 14.051*s))
            p.addLine(to: .init(x: 21*s,     y: 14.051*s))
            p.addLine(to: .init(x: 21*s,     y: 17.079*s))
            // Bottom-right, skip leg notches → straight across to left side
            p.addLine(to: .init(x: 3*s,      y: 17.079*s))
            // Left arm: (3,17.079)→(3,14.05)→(0,14.05)→(0,10.95)→(3,10.95)
            p.addLine(to: .init(x: 3*s,      y: 14.05*s))
            p.addLine(to: .init(x: 0,        y: 14.05*s))
            p.addLine(to: .init(x: 0,        y: 10.95*s))
            p.addLine(to: .init(x: 3*s,      y: 10.95*s))
            // Body top
            p.addLine(to: .init(x: 3*s,      y: 5*s))
            p.addLine(to: .init(x: 20.998*s, y: 5*s))
            p.closeSubpath()

            // Eye holes (evenodd punches them transparent)
            // Left eye:  M6 10.949 h1.488 V8.102 H6 z
            p.move(to:    .init(x: 6*s,     y: 10.949*s))
            p.addLine(to: .init(x: 7.488*s, y: 10.949*s))
            p.addLine(to: .init(x: 7.488*s, y: 8.102*s))
            p.addLine(to: .init(x: 6*s,     y: 8.102*s))
            p.closeSubpath()
            // Right eye: M16.51 10.949 H18 V8.102 h-1.49 z
            p.move(to:    .init(x: 16.51*s, y: 10.949*s))
            p.addLine(to: .init(x: 18*s,    y: 10.949*s))
            p.addLine(to: .init(x: 18*s,    y: 8.102*s))
            p.addLine(to: .init(x: 16.51*s, y: 8.102*s))
            p.closeSubpath()

            ctx.fill(p, with: .color(clawdColor), style: FillStyle(eoFill: true))

            // Legs drawn separately so walk animation can shift them
            // Static positions from SVG: right legs x=19.513..18 and 16.513..15; left x=9..7.488 and 6..4.487
            // Walk: right pair shifts +d, left pair shifts -d
            let legY = 17.079*s
            let legH = 2.921*s
            func leg(_ x1: CGFloat, _ x2: CGFloat) -> Path {
                Path(CGRect(x: x1*s, y: legY, width: (x2-x1)*s, height: legH))
            }
            ctx.fill(leg(15+d,    16.513+d), with: .color(clawdColor))  // right leg 1
            ctx.fill(leg(18+d,    19.513+d), with: .color(clawdColor))  // right leg 2
            ctx.fill(leg(7.488-d, 9-d),      with: .color(clawdColor))  // left leg 1
            ctx.fill(leg(4.487-d, 6-d),      with: .color(clawdColor))  // left leg 2
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}


// MARK: - Clawd with headphones: bounce + floating music notes

struct ClawdWithHeadphonesIcon: View {
    let size: CGFloat
    let headphoneColor: Color

    // Each note: (glyph, phase offset 0..1 within cycle, cycle duration)
    private let notes: [(String, Double, Double)] = [
        ("♪", 0.00, 2.2),
        ("♫", 0.36, 2.6),
        ("♩", 0.62, 2.0),
    ]

    // Bounce cycle duration
    private let bouncePeriod: Double = 0.72

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate

            // Bounce phase 0..1 repeating
            let bp = CGFloat(fmod(t / bouncePeriod, 1.0))
            let (bScaleX, bScaleY, bOffY) = bounceValues(bp)

            ZStack(alignment: .bottomLeading) {
                clawdWithHeadphones
                    .scaleEffect(x: bScaleX, y: bScaleY, anchor: .bottom)
                    .offset(y: bOffY)

                ForEach(Array(notes.enumerated()), id: \.offset) { i, note in
                    let (glyph, phaseOffset, dur) = note
                    // Each note has its own phase, offset so they stagger naturally
                    let np = fmod(t / dur + phaseOffset, 1.0)
                    let (nx, ny, nop) = noteValues(np, size: size)
                    Text(glyph)
                        .font(.system(size: size * 0.30))
                        .foregroundColor(.white)
                        .offset(x: nx, y: ny)
                        .opacity(nop)
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    // HTML keyframe curve approximated as piecewise lerp:
    // 0→0.30: squat; 0.30→0.55: spring up; 0.55→0.75: settle; 0.75→1.0: rest
    private func bounceValues(_ p: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
        switch p {
        case 0..<0.30:
            let t = p / 0.30
            return (lerp(1.0, 1.12, ease(t)),
                    lerp(1.0, 0.82, ease(t)),
                    lerp(0,   1.5,  ease(t)))
        case 0.30..<0.55:
            let t = (p - 0.30) / 0.25
            return (lerp(1.12, 0.93, ease(t)),
                    lerp(0.82, 1.10, ease(t)),
                    lerp(1.5, -3.0,  ease(t)))
        case 0.55..<0.75:
            let t = (p - 0.55) / 0.20
            return (lerp(0.93, 1.0, ease(t)),
                    lerp(1.10, 1.0, ease(t)),
                    lerp(-3.0, 0,   ease(t)))
        default:
            return (1.0, 1.0, 0)
        }
    }

    // Note: 0→0.15 invisible; 0.15→0.30 fade in; 0.30→0.70 visible float; 0.70→1.0 fade out
    private func noteValues(_ p: Double, size: CGFloat) -> (CGFloat, CGFloat, Double) {
        let travel = p  // 0..1
        let ox = CGFloat(-travel) * size * 0.6
        let oy = CGFloat(-travel) * size * 0.95
        let opacity: Double
        switch p {
        case 0..<0.15:  opacity = 0
        case 0.15..<0.30: opacity = (p - 0.15) / 0.15
        case 0.30..<0.70: opacity = 0.85
        case 0.70..<1.0:  opacity = (1.0 - p) / 0.30 * 0.85
        default:           opacity = 0
        }
        return (ox, oy, opacity)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * min(max(t, 0), 1)
    }
    private func ease(_ t: CGFloat) -> CGFloat {
        // smoothstep
        let t = min(max(t, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private var clawdWithHeadphones: some View {
        Canvas { ctx, canvasSize in
            let s = canvasSize.width / 24.0

            // Body
            var p = Path()
            p.move(to:    .init(x: 20.998*s, y: 10.949*s))
            p.addLine(to: .init(x: 24*s,     y: 10.949*s))
            p.addLine(to: .init(x: 24*s,     y: 14.051*s))
            p.addLine(to: .init(x: 21*s,     y: 14.051*s))
            p.addLine(to: .init(x: 21*s,     y: 17.079*s))
            p.addLine(to: .init(x: 3*s,      y: 17.079*s))
            p.addLine(to: .init(x: 3*s,      y: 14.05*s))
            p.addLine(to: .init(x: 0,        y: 14.05*s))
            p.addLine(to: .init(x: 0,        y: 10.95*s))
            p.addLine(to: .init(x: 3*s,      y: 10.95*s))
            p.addLine(to: .init(x: 3*s,      y: 5*s))
            p.addLine(to: .init(x: 20.998*s, y: 5*s))
            p.closeSubpath()
            // Eyes
            p.move(to:    .init(x: 6*s,     y: 10.949*s))
            p.addLine(to: .init(x: 7.488*s, y: 10.949*s))
            p.addLine(to: .init(x: 7.488*s, y: 8.102*s))
            p.addLine(to: .init(x: 6*s,     y: 8.102*s))
            p.closeSubpath()
            p.move(to:    .init(x: 16.51*s, y: 10.949*s))
            p.addLine(to: .init(x: 18*s,    y: 10.949*s))
            p.addLine(to: .init(x: 18*s,    y: 8.102*s))
            p.addLine(to: .init(x: 16.51*s, y: 8.102*s))
            p.closeSubpath()
            ctx.fill(p, with: .color(clawdColor), style: FillStyle(eoFill: true))

            // Static legs (no walk shift)
            let legY = 17.079*s; let legH = 2.921*s
            func leg(_ x1: CGFloat, _ x2: CGFloat) -> Path {
                Path(CGRect(x: x1*s, y: legY, width: (x2-x1)*s, height: legH))
            }
            ctx.fill(leg(15, 16.513), with: .color(clawdColor))
            ctx.fill(leg(18, 19.513), with: .color(clawdColor))
            ctx.fill(leg(7.488, 9),   with: .color(clawdColor))
            ctx.fill(leg(4.487, 6),   with: .color(clawdColor))

            // Headphones
            let hc = GraphicsContext.Shading.color(headphoneColor)
            ctx.fill(CGRect(x: 4*s,    y: 1.2*s, width: 16*s,  height: 1.3*s).with(cornerRadius: 0.65*s), with: hc)
            ctx.fill(Path(CGRect(x: 4*s,    y: 1.2*s, width: 1.5*s, height: 3.8*s)), with: hc)
            ctx.fill(Path(CGRect(x: 18.5*s, y: 1.2*s, width: 1.5*s, height: 3.8*s)), with: hc)
            ctx.fill(CGRect(x: 1.5*s,  y: 2.5*s, width: 4*s,   height: 5*s).with(cornerRadius: 1.2*s), with: hc)
            ctx.fill(CGRect(x: 18.5*s, y: 2.5*s, width: 4*s,   height: 5*s).with(cornerRadius: 1.2*s), with: hc)
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

// MARK: - Animated walking Clawd with glow

struct ClawdWalkingIcon: View {
    let size: CGFloat
    /// When non-nil, renders headphones in this color instead of plain Clawd
    var headphoneColor: Color? = nil
    @State private var walkFrame: ClawdFrame = .a
    @State private var pulse = false

    var body: some View {
        icon
            .shadow(color: clawdColor.opacity(pulse ? 0.9 : 0.4), radius: pulse ? 8 : 4)
            .shadow(color: clawdColor.opacity(0.3), radius: 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulse = true
                }
                Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { _ in
                    withAnimation(.linear(duration: 0.1)) {
                        walkFrame = walkFrame == .a ? .b : .a
                    }
                }
            }
    }

    @ViewBuilder
    private var icon: some View {
        if let color = headphoneColor {
            ClawdWithHeadphonesIcon(size: size, headphoneColor: color)
                .shadow(color: color.opacity(0.7), radius: 5)
        } else {
            ClawdIcon(size: size, walkFrame: walkFrame)
        }
    }
}

// MARK: - Main closed-notch agent bar

struct AgentClosedNotchView: View {
    let hasHardwareNotch: Bool
    @ObservedObject var manager = AgentStatusManager.shared
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.useMusicVisualizer) var useMusicVisualizer
    @Default(.coloredSpectrogram) var coloredSpectrogram

    private var summary: String? {
        manager.activeSessionSummary
    }

    private var count: Int {
        manager.activeSessions.count
    }

    /// When Claude is running AND media is playing, show Clawd with headphones
    private var headphoneColor: Color? {
        musicManager.isPlaying
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6)
            : nil
    }

    var body: some View {
        if hasHardwareNotch {
            HStack(spacing: 0) {
                ClawdWalkingIcon(size: 16, headphoneColor: headphoneColor)

                Spacer()

                rightWidget
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 10) {
                ClawdWalkingIcon(size: 18, headphoneColor: headphoneColor)
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

                rightWidget
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var rightWidget: some View {
        if musicManager.isPlaying {
            // Mirror the right-side spectrum from MusicLiveActivity
            spectrumView
                .frame(width: 20, height: 12)
        } else {
            Text("\(count)")
                .font(.system(size: hasHardwareNotch ? 10 : 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, hasHardwareNotch ? 5 : 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: hasHardwareNotch ? 4 : 5))
        }
    }

    @ViewBuilder
    private var spectrumView: some View {
        if useMusicVisualizer {
            Rectangle()
                .fill(
                    coloredSpectrogram
                        ? Color(nsColor: musicManager.avgColor).gradient
                        : Color.gray.gradient
                )
                .mask {
                    AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                        .frame(width: 16, height: 12)
                }
        } else {
            LottieAnimationContainer()
        }
    }
}

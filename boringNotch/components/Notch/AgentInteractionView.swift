//
//  AgentInteractionView.swift
//  boringNotch
//

import SwiftUI

private let iColor = Color(red: 217/255, green: 119/255, blue: 87/255)

struct AgentInteractionView: View {
    let interaction: PendingInteraction
    @ObservedObject private var manager = AgentStatusManager.shared
    @State private var isHoveringDismiss = false
    @State private var isHoveringCard = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main clickable card
            Button(action: focusTerminal) {
                VStack(alignment: .leading, spacing: 8) {
                    headerRow
                    contentSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(iColor.opacity(isHoveringCard ? 0.08 : 0))
                    .animation(.easeInOut(duration: 0.15), value: isHoveringCard)
            )
            .onHover { isHoveringCard = $0 }
            .cursor(.pointingHand)

            // Dismiss button — top-right corner
            Button(action: { manager.dismissPendingInteraction() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(isHoveringDismiss ? 0.9 : 0.4))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(isHoveringDismiss ? 0.15 : 0.07)))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
            .onHover { isHoveringDismiss = $0 }
            .cursor(.arrow)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            ClawdIcon(size: 16)
                .shadow(color: iColor.opacity(0.6), radius: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                if let summary = interaction.sessionSummary {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 28) // leave space for dismiss button
        }
    }

    private var headerTitle: String {
        switch interaction.type {
        case .permission: return "Claude Code 请求工具权限"
        default: return "Claude Code 正在等待你"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if interaction.type == .planApproval {
            planContent
        } else {
            questionContent
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question text (for permission: shows tool call summary e.g. "Write(/tmp/test.txt)")
            if let q = interaction.question {
                Text(q)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Options as compact chips
            if !interaction.options.isEmpty {
                optionChips
            }

            // Click hint
            clickHint
        }
    }

    private var optionChips: some View {
        let opts = Array(interaction.options.prefix(4))
        return FlowLayout(spacing: 4) {
            ForEach(opts.indices, id: \.self) { i in
                OptionChip(label: opts[i].label) {
                    print("[AgentInteractionView] option chip tapped: index=\(i) label=\(opts[i].label)")
                    manager.selectOption(claudePid: interaction.pid, optionIndex: i)
                }
            }
        }
    }

    private var planContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(interaction.planTitle ?? "Waiting for plan approval")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(2)
            clickHint
        }
    }

    private var clickHint: some View {
        HStack(spacing: 4) {
            Image(systemName: "cursorarrow.click")
                .font(.system(size: 9))
            Text("点击选项自动回复 · 点击卡片切换到终端")
                .font(.system(size: 10))
        }
        .foregroundColor(.gray.opacity(0.5))
        .padding(.top, 2)
    }

    // MARK: - Actions

    private func focusTerminal() {
        manager.focusTerminal(claudePid: interaction.pid)
    }
}

// MARK: - Option chip button

private struct OptionChip: View {
    let label: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isHovering ? .white : .white.opacity(0.75))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(isHovering ? iColor.opacity(0.35) : Color.white.opacity(0.1)))
                .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cursor(.pointingHand)
    }
}

// MARK: - Simple flow layout for option chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += lineH + spacing
                x = 0
                lineH = 0
            }
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
        return CGSize(width: maxWidth, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += lineH + spacing
                x = bounds.minX
                lineH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}

// MARK: - Simple flow layout for option chips
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
    @State private var selectedLabels: Set<String> = []

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
            Button(action: { manager.dismissPendingInteraction(sessionId: interaction.sessionId) }) {
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
                if interaction.type != .completion, let summary = interaction.sessionSummary {
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
        case .permission:   return "Claude Code 请求工具权限"
        case .completion:   return interaction.sessionSummary ?? "响应已完成"
        default:            return "Claude Code 正在等待你"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentSection: some View {
        if interaction.type == .planApproval {
            planContent
        } else if interaction.type == .completion {
            completionContent
        } else {
            questionContent
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let q = interaction.question {
                Text(q)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !interaction.options.isEmpty {
                if interaction.multiSelect {
                    multiSelectChips
                } else {
                    optionChips
                }
                if interaction.type == .permission {
                    permissionModeHint
                }
            }

            clickHint
        }
    }

    @ViewBuilder
    private var permissionModeHint: some View {
        let count = interaction.options.count
        if count >= 3 {
            Label("已识别 always allow 选项（可能存在选项数量差异）", systemImage: "exclamationmark.triangle")
                .font(.system(size: 9.5))
                .foregroundColor(.yellow.opacity(0.75))
        } else {
            Label("仅 Yes / No 模式", systemImage: "checkmark.shield")
                .font(.system(size: 9.5))
                .foregroundColor(.white.opacity(0.45))
        }
    }

    private var optionChips: some View {
        let opts = Array(interaction.options.prefix(4))
        return FlowLayout(spacing: 4) {
            ForEach(opts.indices, id: \.self) { i in
                OptionChip(label: opts[i].label) {
                    print("[AgentInteractionView] option chip tapped: index=\(i) label=\(opts[i].label)")
                    manager.selectOption(claudePid: interaction.pid, optionIndex: i, sessionId: interaction.sessionId)
                }
            }
        }
    }

    private var multiSelectChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            let opts = Array(interaction.options.prefix(4))
            FlowLayout(spacing: 4) {
                ForEach(opts.indices, id: \.self) { i in
                    let label = opts[i].label
                    let isSelected = selectedLabels.contains(label)
                    ToggleChip(label: label, isSelected: isSelected) {
                        if isSelected {
                            selectedLabels.remove(label)
                        } else {
                            selectedLabels.insert(label)
                        }
                    }
                }
            }

            if selectedLabels.isEmpty {
                Text("选择后点击确认发送，再在终端自行提交")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.4))
                    .padding(.top, 1)
            } else {
                let ordered = interaction.options.enumerated()
                    .filter { selectedLabels.contains($0.element.label) }
                    .map { $0 }
                Button(action: {
                    let indices = ordered.map(\.offset)
                    manager.sendMultiSelectAndFocus(
                        claudePid: interaction.pid,
                        optionIndices: indices,
                        sessionId: interaction.sessionId
                    )
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "return")
                            .font(.system(size: 9, weight: .bold))
                        Text("确认发送 · 请在终端自行提交")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(iColor.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .cursor(.pointingHand)
                .padding(.top, 2)
            }
        }
    }

    private var completionContent: some View {
        HStack(spacing: 14) {
            CheckmarkAnimationView()
            VStack(alignment: .leading, spacing: 3) {
                if let reply = interaction.agentReply {
                    Text(reply)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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
        if interaction.type == .completion {
            manager.dismissPendingInteraction(sessionId: interaction.sessionId)
        } else {
            manager.focusTerminal(claudePid: interaction.pid, sessionId: interaction.sessionId)
        }
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

// MARK: - Toggle chip (for multiSelect)

private struct ToggleChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(iColor)
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.75))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(isSelected ? iColor.opacity(0.25) : (isHovering ? Color.white.opacity(0.15) : Color.white.opacity(0.08))))
            .overlay(Capsule().strokeBorder(isSelected ? iColor.opacity(0.6) : Color.clear, lineWidth: 1))
            .animation(.easeInOut(duration: 0.12), value: isSelected)
            .animation(.easeInOut(duration: 0.12), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .cursor(.pointingHand)
    }
}

// MARK: - Simple flow layout for chips

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

// MARK: - Apple Pay-style checkmark animation

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to:    CGPoint(x: rect.width * 0.15, y: rect.height * 0.52))
        p.addLine(to: CGPoint(x: rect.width * 0.42, y: rect.height * 0.78))
        p.addLine(to: CGPoint(x: rect.width * 0.88, y: rect.height * 0.22))
        return p
    }
}

struct CheckmarkAnimationView: View {
    @State private var circleProgress: CGFloat = 0
    @State private var checkProgress: CGFloat  = 0
    @State private var scale: CGFloat          = 0.5

    private let green = Color(red: 52/255, green: 199/255, blue: 89/255)

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: circleProgress)
                .stroke(green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 32, height: 32)

            CheckmarkShape()
                .trim(from: 0, to: checkProgress)
                .stroke(green, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
        }
        .scaleEffect(scale)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                scale = 1.0
            }
            withAnimation(.easeOut(duration: 0.45)) {
                circleProgress = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.3)) {
                    checkProgress = 1.0
                }
            }
        }
    }
}

// MARK: - Simple flow layout for option chips
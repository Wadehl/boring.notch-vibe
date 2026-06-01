//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let baseTabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf)
]

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var agentManager = AgentStatusManager.shared
    @Namespace var animation

    private var hasActiveSessions: Bool {
        !agentManager.activeSessions.isEmpty
    }

    private var visibleTabs: [TabModel] {
        var t = baseTabs
        if hasActiveSessions {
            t.append(TabModel(label: "AI", icon: "square.stack.3d.up.fill", view: .agentStatus))
        }
        return t
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { tab in
                TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                    withAnimation(.smooth) {
                        coordinator.currentView = tab.view
                    }
                }
                .frame(height: 26)
                .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                .background {
                    if tab.view == coordinator.currentView {
                        Capsule()
                            .fill(Color(nsColor: .secondarySystemFill))
                            .matchedGeometryEffect(id: "capsule", in: animation)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "capsule", in: animation)
                            .hidden()
                    }
                }
            }
        }
        .clipShape(Capsule())
        .onAppear {
            if hasActiveSessions && coordinator.currentView != .agentStatus {
                coordinator.currentView = .agentStatus
            }
        }
        .onChange(of: hasActiveSessions) { _, active in
            withAnimation(.smooth) {
                if active {
                    coordinator.currentView = .agentStatus
                } else if coordinator.currentView == .agentStatus {
                    coordinator.currentView = .home
                }
            }
        }
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}

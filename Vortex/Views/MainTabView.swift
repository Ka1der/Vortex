import SwiftUI

/// Root tab navigation orchestrating the 4 Shadowrocket-style tabs
@MainActor
public struct MainTabView: View {
    @Bindable var tunnelManager: TunnelManager

    @MainActor
    public init(tunnelManager: TunnelManager) {
        self.tunnelManager = tunnelManager
    }

    @MainActor
    public init() {
        self.tunnelManager = .shared
    }

    public var body: some View {
        TabView {
            // Tab 1: Главная (Dashboard)
            HomeView(tunnelManager: tunnelManager)
                .tabItem {
                    Label("Главная", systemImage: "paperplane.fill")
                }
                .tag(0)

            // Tab 2: Маршрутизация (Routing Rules)
            RoutingView(tunnelManager: tunnelManager)
                .tabItem {
                    Label("Маршрутизация", systemImage: "arrow.triangle.branch")
                }
                .tag(1)

            // Tab 3: Данные (Data & Metrics)
            DataStatsView(tunnelManager: tunnelManager)
                .tabItem {
                    Label("Данные", systemImage: "chart.bar.xaxis")
                }
                .tag(2)

            // Tab 4: Настройки (Preferences)
            SettingsView(tunnelManager: tunnelManager)
                .tabItem {
                    Label("Настройки", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
        .tint(Theme.orange)
        .preferredColorScheme(.dark)
    }
}

import SwiftUI

@main
struct VortexApp: App {
    @State private var tunnelManager = TunnelManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView(tunnelManager: tunnelManager)
                .preferredColorScheme(.dark)
                .task {
                    RuleSetManager.shared.ensureBundledRulesCopied()
                    await RuleSetManager.shared.checkAndAutoUpdateIfNeeded()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task {
                            await RuleSetManager.shared.checkAndAutoUpdateIfNeeded()
                        }
                    }
                }
        }
    }
}

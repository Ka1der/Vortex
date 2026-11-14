import SwiftUI

@main
struct VortexApp: App {
    @State private var tunnelManager = TunnelManager.shared

    var body: some Scene {
        WindowGroup {
            MainTabView(tunnelManager: tunnelManager)
                .preferredColorScheme(.dark)
        }
    }
}

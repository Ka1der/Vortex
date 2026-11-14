import SwiftUI

@MainActor
public struct ContentView: View {
    @State private var tunnelManager = TunnelManager.shared

    public init() {}

    public var body: some View {
        MainTabView(tunnelManager: tunnelManager)
    }
}

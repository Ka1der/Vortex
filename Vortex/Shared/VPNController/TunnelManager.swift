import Foundation
import NetworkExtension
import Observation

/// Primary application controller orchestrating VPN tunnel lifecycle, routing modes, and node testing
@MainActor
@Observable
public final class TunnelManager {

    // MARK: - Singleton & Observable Properties

    public static let shared = TunnelManager()

    public var status: TunnelStatus = .disconnected
    public var activeNode: ServerNode? = nil
    public var globalMode: GlobalRoutingMode = .config
    public var localNodes: [ServerNode] = []
    public var subscriptions: [SubscriptionGroup] = []
    public var rules: [RoutingRule] = []

    // Live Metrics
    public var txBytes: Int64 = 0
    public var rxBytes: Int64 = 0
    public var txRate: Int64 = 0
    public var rxRate: Int64 = 0
    public var memoryUsageBytes: Int64 = 0
    public var isTestingPing: Bool = false
    public var errorMessage: String? = nil

    // MARK: - Internal State

    public var isConnected: Bool {
        return status == .connected
    }

    private var providerManager: NETunnelProviderManager?
    private let mockEngine = MockTunnelEngine()
    private var useMockEngine: Bool
    private var statsTask: Task<Void, Never>?
    private var previousTx: Int64 = 0
    private var previousRx: Int64 = 0

    // MARK: - Initialization

    public init(forceMock: Bool? = nil) {
        self.useMockEngine = forceMock ?? false

        // 1. Load persistent data from AppGroup and purge any legacy dummy servers
        loadDataFromStorage()

        // 2. Ensure binary rule-sets (.srs) are present in AppGroup storage & wire reload callback
        RuleSetManager.shared.onRuleSetsReloadRequested = { [weak self] in
            guard let self, self.status == .connected else { return }
            await self.reloadRules()
        }
        RuleSetManager.setupRuleSets()

        // 3. Setup mock engine callbacks
        Task { [weak self, mockEngine] in
            await mockEngine.setStatusChangeHandler { [weak self] newStatus in
                Task { @MainActor in
                    self?.status = newStatus
                    if newStatus == .connected {
                        self?.startStatsPolling()
                    } else if newStatus == .disconnected {
                        self?.stopStatsPolling()
                    }
                }
            }
        }

        // 4. Setup NetworkExtension manager if not forcing mock (iOS only)
        #if !os(macOS)
        if !self.useMockEngine {
            setupProviderManager()
        }
        #endif
    }

    // MARK: - Storage Sync

    public func loadDataFromStorage() {
        // One-time hard reset to ensure all legacy dummy servers from earlier builds are wiped
        let resetKey = "vortex_purged_all_dummy_servers_v3"
        if !AppGroup.userDefaults.bool(forKey: resetKey) {
            AppGroup.userDefaults.set(true, forKey: resetKey)
            try? AppGroup.saveNodes([])
            try? AppGroup.saveSubscriptions([])
            AppGroup.setActiveNodeId(nil)
        }

        // One-time hard reset to ensure all legacy default routing rules from earlier builds are wiped
        let resetRulesKey = "vortex_purged_default_rules_v3"
        if !AppGroup.userDefaults.bool(forKey: resetRulesKey) {
            AppGroup.userDefaults.set(true, forKey: resetRulesKey)
            try? AppGroup.saveRules([])
        }

        var nodes = AppGroup.loadNodes()
        var subs = AppGroup.loadSubscriptions()

        // Purge any server or subscription containing mock identifiers
        let hadDummies = nodes.contains(where: { isDummyNode($0) }) || subs.contains(where: { isDummySub($0) })
        if hadDummies {
            nodes.removeAll(where: { isDummyNode($0) })
            subs.removeAll(where: { isDummySub($0) })
            try? AppGroup.saveNodes(nodes)
            try? AppGroup.saveSubscriptions(subs)
        }

        self.localNodes = nodes
        self.subscriptions = subs
        self.rules = AppGroup.loadRules()
        self.globalMode = AppGroup.getGlobalRoutingMode()

        let savedNodeId = AppGroup.getActiveNodeId()
        if let savedId = savedNodeId,
           let found = allNodes.first(where: { $0.id == savedId }) {
            self.activeNode = found
        } else {
            self.activeNode = allNodes.first
            AppGroup.setActiveNodeId(self.activeNode?.id)
        }
    }

    private func isDummyNode(_ node: ServerNode) -> Bool {
        let name = node.name.lowercased()
        let addr = node.address.lowercased()
        if name.contains("vk call") || name.contains("amsterdam") || name.contains("frankfurt") ||
           name.contains("helsinki") || name.contains("singapore") || name.contains("new york") ||
           name.contains("vortex fast") || name.contains("tunnel relay") {
            return true
        }
        if addr.contains("198.51.100.") || addr.contains("turn.vk.com") || addr.contains("192.0.2.") {
            return true
        }
        return false
    }

    private func isDummySub(_ sub: SubscriptionGroup) -> Bool {
        let title = sub.title.lowercased()
        let url = sub.url.absoluteString.lowercased()
        if title.contains("vortex premium") || title.contains("demo") || title.contains("vip") {
            return true
        }
        if url.contains("vortex-vpn.io") || url.contains("vortex_demo") {
            return true
        }
        return false
    }

    /// Flattened collection of all local and subscription-derived nodes
    public var allNodes: [ServerNode] {
        var list = localNodes
        for sub in subscriptions {
            list.append(contentsOf: sub.nodes)
        }
        return list
    }

    // MARK: - NetworkExtension Setup

    private func setupProviderManager() {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                if let existing = managers.first {
                    self.providerManager = existing
                } else {
                    let newManager = NETunnelProviderManager()
                    let proto = NETunnelProviderProtocol()
                    let bundleId = Bundle.main.bundleIdentifier ?? "Kaider.Vortex"
                    let extId = bundleId.hasSuffix(".tunnel") ? bundleId : "\(bundleId).tunnel"
                    proto.providerBundleIdentifier = extId
                    proto.serverAddress = "Vortex Tunnel"
                    newManager.protocolConfiguration = proto
                    newManager.localizedDescription = "Vortex VPN"
                    newManager.isEnabled = true
                    self.providerManager = newManager
                }

                self.observeVPNStatus()
                self.syncStatusFromProvider()
            } catch {
                self.errorMessage = "NEPreferences: \(error.localizedDescription)"
            }
        }
    }

    private func observeVPNStatus() {
        NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.syncStatusFromProvider()
            }
        }
    }

    private func syncStatusFromProvider() {
        guard let manager = providerManager else { return }
        let neStatus = manager.connection.status
        self.status = TunnelStatus.from(neStatus: neStatus)

        if self.status == .connected {
            startStatsPolling()
        } else if self.status == .disconnected {
            stopStatsPolling()
        }
    }

    // MARK: - Connection Control

    /// Toggles the VPN tunnel state
    public func toggleTunnel() async {
        if isConnected || status == .connecting {
            await stopTunnel()
        } else {
            do {
                try await startTunnel()
            } catch {
                self.errorMessage = error.localizedDescription
                self.status = .disconnected
            }
        }
    }

    /// Starts the VPN connection
    public func startTunnel() async throws {
        guard let node = activeNode else {
            throw ConfigBuilderError.invalidNodeAddress("Не выбран активный сервер")
        }

        self.errorMessage = nil
        self.status = .connecting

        // Ensure binary rule-sets (.srs) are provisioned
        RuleSetManager.setupRuleSets()

        // 1. Build and save sing-box configuration in shared container
        let configJSON = try ConfigBuilder.buildConfig(
            node: node,
            mode: globalMode,
            rules: rules,
            mtu: AppGroup.getMTU(),
            remoteDns: AppGroup.getRemoteDNS(),
            directDns: AppGroup.getDirectDNS()
        )
        try AppGroup.saveSingBoxConfig(configJSON)

        // 2. Route via platform engine
        #if os(macOS)
        do {
            try MacTunnelEngine.shared.start(configJSON: configJSON)
            self.status = .connected
            self.errorMessage = nil
            startStatsPolling()
            return
        } catch {
            self.status = .disconnected
            self.errorMessage = "Ошибка запуска sing-box: \(error.localizedDescription)"
            return
        }
        #else
        guard let manager = providerManager else {
            self.status = .disconnected
            #if targetEnvironment(simulator)
            self.errorMessage = "Системный VPN недоступен в Simulator. Apple не поддерживает NetworkExtension в симуляторе. Запустите на реальном устройстве."
            #else
            self.errorMessage = "Служба VPN не инициализирована. На Mac (Designed for iPad) системный VPN блокируется Apple. Запустите на реальном iPhone/iPad."
            #endif
            return
        }

        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            guard let session = manager.connection as? NETunnelProviderSession else {
                throw ConfigBuilderError.invalidNodeAddress("Не удалось получить сессию туннеля")
            }
            try session.startVPNTunnel(options: nil)
        } catch {
            self.status = .disconnected
            #if targetEnvironment(simulator)
            self.errorMessage = "В iOS Simulator системный VPN заблокирован Apple (\(error.localizedDescription)). Для реального туннелирования трафика используйте физический iPhone/iPad."
            #else
            self.errorMessage = "Ошибка сохранения VPN-профиля (\(error.localizedDescription)). На Mac (Designed for iPad) Apple блокирует установку iOS VPN (Код 10). Для теста трафика запустите приложение на физическом iPhone/iPad."
            #endif
        }
        #endif
    }

    /// Stops the VPN connection
    public func stopTunnel() async {
        self.status = .disconnecting

        #if os(macOS)
        MacTunnelEngine.shared.stop()
        self.status = .disconnected
        stopStatsPolling()
        return
        #else
        if useMockEngine {
            try? await mockEngine.stop()
            self.status = .disconnected
            stopStatsPolling()
            return
        }

        if let session = providerManager?.connection as? NETunnelProviderSession {
            session.stopVPNTunnel()
        } else {
            try? await mockEngine.stop()
            self.status = .disconnected
            stopStatsPolling()
        }
        #endif
    }

    // MARK: - Configuration Updates

    /// Selects an active VPN node
    public func selectNode(_ node: ServerNode) {
        self.activeNode = node
        AppGroup.setActiveNodeId(node.id)

        // If currently connected, reload sing-box config dynamically
        if isConnected {
            Task {
                await reloadActiveConfig()
            }
        }
    }

    /// Updates global routing mode (.config, .proxy, .direct, .block)
    public func setRoutingMode(_ mode: GlobalRoutingMode) {
        self.globalMode = mode
        AppGroup.setGlobalRoutingMode(mode)

        if isConnected {
            Task {
                await reloadActiveConfig()
            }
        }
    }

    private func reloadActiveConfig() async {
        guard let node = activeNode else { return }
        do {
            let configJSON = try ConfigBuilder.buildConfig(
                node: node,
                mode: globalMode,
                rules: rules,
                mtu: AppGroup.getMTU(),
                remoteDns: AppGroup.getRemoteDNS(),
                directDns: AppGroup.getDirectDNS()
            )
            try AppGroup.saveSingBoxConfig(configJSON)

            // Send IPC reload message to extension if live
            _ = try? await sendProviderMessage(command: .reloadConfig)
        } catch {
            self.errorMessage = "Ошибка обновления конфига: \(error.localizedDescription)"
        }
    }

    /// Reloads routing rules and notifies the packet tunnel provider
    public func reloadRules() async {
        guard status == .connected else { return }
        await reloadActiveConfig()
        _ = try? await sendProviderMessage(command: .reloadRules)
    }

    // MARK: - Node Management

    public func addLocalNode(_ node: ServerNode) {
        localNodes.append(node)
        try? AppGroup.saveNodes(localNodes)
        if activeNode == nil {
            selectNode(node)
        }
    }

    public func deleteLocalNode(withId id: UUID) {
        localNodes.removeAll(where: { $0.id == id })
        try? AppGroup.saveNodes(localNodes)
        if activeNode?.id == id {
            activeNode = allNodes.first
            AppGroup.setActiveNodeId(activeNode?.id)
        }
    }

    // MARK: - Subscription Management

    public func addSubscription(title: String, url: URL) async throws {
        let fetcher = SubscriptionFetcher()
        let (userInfo, nodes) = try await fetcher.fetch(from: url)

        var newGroup = SubscriptionGroup(
            title: title.isEmpty ? (url.host ?? "Подписка") : title,
            url: url,
            lastUpdated: Date(),
            nodes: nodes
        )
        if let info = userInfo {
            newGroup.updateUserInfo(info)
        }

        subscriptions.append(newGroup)
        try? AppGroup.saveSubscriptions(subscriptions)

        if activeNode == nil, let first = nodes.first {
            selectNode(first)
        }
    }

    public func refreshSubscription(_ group: SubscriptionGroup) async throws {
        let fetcher = SubscriptionFetcher()
        let (userInfo, nodes) = try await fetcher.fetch(from: group.url, subscriptionId: group.id)

        guard let index = subscriptions.firstIndex(where: { $0.id == group.id }) else { return }

        subscriptions[index].nodes = nodes
        subscriptions[index].lastUpdated = Date()
        if let info = userInfo {
            subscriptions[index].updateUserInfo(info)
        }

        try? AppGroup.saveSubscriptions(subscriptions)

        // Update active node reference if it belongs to this subscription
        if let active = activeNode, let updated = nodes.first(where: { $0.id == active.id }) {
            self.activeNode = updated
        }
    }

    public func deleteSubscription(withId id: UUID) {
        subscriptions.removeAll(where: { $0.id == id })
        try? AppGroup.saveSubscriptions(subscriptions)
        if activeNode?.subscriptionId == id {
            activeNode = allNodes.first
            AppGroup.setActiveNodeId(activeNode?.id)
        }
    }

    // MARK: - Routing Rules Management

    /// Adds a new routing rule and synchronizes with storage & tunnel
    public func addRule(_ rule: RoutingRule) {
        rules.append(rule)
        try? AppGroup.saveRules(rules)
        if isConnected && globalMode == .config {
            Task { await reloadActiveConfig() }
        }
    }

    /// Updates an existing routing rule
    public func updateRule(_ rule: RoutingRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        try? AppGroup.saveRules(rules)
        if isConnected && globalMode == .config {
            Task { await reloadActiveConfig() }
        }
    }

    /// Deletes a routing rule by ID
    public func deleteRule(withId id: UUID) {
        rules.removeAll(where: { $0.id == id })
        try? AppGroup.saveRules(rules)
        if isConnected && globalMode == .config {
            Task { await reloadActiveConfig() }
        }
    }

    /// Toggles active state of a rule
    public func toggleRule(withId id: UUID, isEnabled: Bool) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].isEnabled = isEnabled
        try? AppGroup.saveRules(rules)
        if isConnected && globalMode == .config {
            Task { await reloadActiveConfig() }
        }
    }

    // MARK: - Parallel Ping & Connectivity Test

    /// Tests latency for all available nodes in parallel using real TCP handshakes
    public func testAllNodesLatency() async {
        isTestingPing = true
        defer { isTestingPing = false }

        let pingTester = NetworkPingTester.shared

        // Test local nodes
        await withTaskGroup(of: (UUID, Int?).self) { group in
            for node in localNodes {
                group.addTask {
                    let pingValue = await pingTester.ping(host: node.address, port: node.port)
                    return (node.id, pingValue)
                }
            }

            for await (nodeId, ping) in group {
                if let index = localNodes.firstIndex(where: { $0.id == nodeId }) {
                    localNodes[index].latencyMs = ping
                }
            }
        }
        try? AppGroup.saveNodes(localNodes)

        // Test subscription nodes
        for subIndex in subscriptions.indices {
            var subNodes = subscriptions[subIndex].nodes
            await withTaskGroup(of: (UUID, Int?).self) { group in
                for node in subNodes {
                    group.addTask {
                        let ping = await pingTester.ping(host: node.address, port: node.port)
                        return (node.id, ping)
                    }
                }
                for await (nodeId, ping) in group {
                    if let nIdx = subNodes.firstIndex(where: { $0.id == nodeId }) {
                        subNodes[nIdx].latencyMs = ping
                    }
                }
            }
            subscriptions[subIndex].nodes = subNodes
        }
        try? AppGroup.saveSubscriptions(subscriptions)

        // Sync active node latency
        if let activeId = activeNode?.id, let updated = allNodes.first(where: { $0.id == activeId }) {
            self.activeNode = updated
        }
    }

    // MARK: - IPC Communication

    /// Sends a control message to the tunnel provider extension
    public func sendProviderMessage(
        command: TunnelIPCMessage.Command,
        payload: [String: String]? = nil
    ) async throws -> [String: Any]? {
        let message = TunnelIPCMessage(command: command, payload: payload)

        if useMockEngine {
            // Mock responses for simulator
            switch command {
            case .getStatus:
                return ["status": status.rawValue]
            case .getStats:
                let stats = await mockEngine.getTrafficStats()
                return [
                    "txBytes": stats.txBytes,
                    "rxBytes": stats.rxBytes,
                    "memoryBytes": stats.memoryBytes
                ]
            case .reloadConfig, .reloadRules:
                return ["success": true]
            case .pingNode:
                return ["latency": 45]
            }
        }

        guard let session = providerManager?.connection as? NETunnelProviderSession,
              session.status == .connected || session.status == .connecting else {
            return nil
        }

        guard let messageData = message.encode() else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.sendProviderMessage(messageData) { responseData in
                    if let data = responseData,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        continuation.resume(returning: json)
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Periodic Traffic Polling

    private func startStatsPolling() {
        stopStatsPolling()

        previousTx = txBytes
        previousRx = rxBytes

        let engine = self.mockEngine
        let isMock = self.useMockEngine

        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
                guard let self = self else { break }

                if isMock {
                    let stats = await engine.getTrafficStats()
                    self.updateStats(tx: stats.txBytes, rx: stats.rxBytes, memory: stats.memoryBytes)
                } else {
                    if let response = try? await self.sendProviderMessage(command: .getStats),
                       let tx = response["txBytes"] as? Int64,
                       let rx = response["rxBytes"] as? Int64,
                       let mem = response["memoryBytes"] as? Int64 {
                        self.updateStats(tx: tx, rx: rx, memory: mem)
                    }
                }
            }
        }
    }

    private func updateStats(tx: Int64, rx: Int64, memory: Int64) {
        self.txRate = max(0, tx - self.previousTx)
        self.rxRate = max(0, rx - self.previousRx)
        self.previousTx = tx
        self.previousRx = rx
        self.txBytes = tx
        self.rxBytes = rx
        self.memoryUsageBytes = memory
    }

    private func stopStatsPolling() {
        statsTask?.cancel()
        statsTask = nil
        txRate = 0
        rxRate = 0
    }
}

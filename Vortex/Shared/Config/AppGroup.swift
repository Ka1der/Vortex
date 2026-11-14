import Foundation

/// Shared App Group storage and IPC coordinator between Host App and Packet Tunnel Extension
public enum AppGroup {
    /// App Group identifier used for entitlements and shared container
    public static let identifier = "group.com.vortex.vpn"

    /// Shared UserDefaults suite
    public static var userDefaults: UserDefaults {
        return UserDefaults(suiteName: identifier) ?? .standard
    }

    /// App Group shared directory URL.
    /// Uses system Group Container when entitled, with fallback to Application Support in non-entitled environments (e.g. tests / CLI).
    public static var containerURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: groupURL.path, isDirectory: &isDir), isDir.boolValue {
                return groupURL
            }
            do {
                try FileManager.default.createDirectory(at: groupURL, withIntermediateDirectories: true, attributes: nil)
                return groupURL
            } catch {
                // Non-sandboxed execution (e.g. unit tests without provisioning profile)
                // Fall back gracefully to Application Support container
            }
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let fallbackDir = appSupport.appendingPathComponent(identifier, isDirectory: true)
        if !FileManager.default.fileExists(atPath: fallbackDir.path) {
            try? FileManager.default.createDirectory(at: fallbackDir, withIntermediateDirectories: true, attributes: nil)
        }
        return fallbackDir
    }

    // MARK: - File URLs

    /// Location of active sing-box configuration JSON
    public static var configFileURL: URL {
        return containerURL.appendingPathComponent("config.json")
    }

    /// Location of saved local server nodes
    public static var nodesFileURL: URL {
        return containerURL.appendingPathComponent("nodes.json")
    }

    /// Location of saved remote subscriptions
    public static var subscriptionsFileURL: URL {
        return containerURL.appendingPathComponent("subscriptions.json")
    }

    /// Location of saved custom routing rules
    public static var rulesFileURL: URL {
        return containerURL.appendingPathComponent("rules.json")
    }

    /// Location of tunnel runtime diagnostic log
    public static var logFileURL: URL {
        return containerURL.appendingPathComponent("tunnel.log")
    }

    // MARK: - Rule-Set File URLs (sing-box 1.8+ / 1.10+)

    /// Directory inside App Group container where active binary rule-set (.srs) files reside
    public static var rulesDirectoryURL: URL {
        let dir = containerURL.appendingPathComponent("RuleSets", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
        return dir
    }

    /// Path to binary geoip-ru.srs
    public static var geoipRuURL: URL {
        return rulesDirectoryURL.appendingPathComponent("geoip-ru.srs")
    }

    /// Path to binary geosite-category-ru.srs
    public static var geositeRuURL: URL {
        return rulesDirectoryURL.appendingPathComponent("geosite-category-ru.srs")
    }

    /// Path to binary geosite-category-ads-all.srs
    public static var geositeAdsURL: URL {
        return rulesDirectoryURL.appendingPathComponent("geosite-category-ads-all.srs")
    }

    // MARK: - Keys

    public enum Keys {
        public static let activeNodeId = "vortex_active_node_id"
        public static let globalRoutingMode = "vortex_global_routing_mode"
        public static let mtu = "vortex_mtu"
        public static let remoteDns = "vortex_remote_dns"
        public static let directDns = "vortex_direct_dns"
        public static let isConnected = "vortex_is_connected"
        public static let lastActiveTimestamp = "vortex_last_active_timestamp"
        public static let memoryUsageBytes = "vortex_memory_usage_bytes"
        public static let txBytes = "vortex_tx_bytes"
        public static let rxBytes = "vortex_rx_bytes"
        public static let lastRuleSetUpdateDate = "vortex_last_ruleset_update_date"
        public static let autoUpdateRuleSets = "vortex_auto_update_rulesets"
        public static let ruleSetUpdateInterval = "vortex_ruleset_update_interval"
        public static let ruleSetFileSizes = "vortex_ruleset_file_sizes"
    }

    // MARK: - Configuration Persistence

    /// Atomically writes the sing-box JSON configuration to the shared container
    public static func saveSingBoxConfig(_ jsonString: String) throws {
        let data = Data(jsonString.utf8)
        try data.write(to: configFileURL, options: .atomic)
    }

    /// Reads the sing-box JSON configuration from the shared container
    public static func loadSingBoxConfig() -> String? {
        guard let data = try? Data(contentsOf: configFileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Node Persistence

    public static func saveNodes(_ nodes: [ServerNode]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(nodes)
        try data.write(to: nodesFileURL, options: .atomic)
    }

    public static func loadNodes() -> [ServerNode] {
        guard let data = try? Data(contentsOf: nodesFileURL),
              let nodes = try? JSONDecoder().decode([ServerNode].self, from: data) else {
            return []
        }
        return nodes
    }

    // MARK: - Subscription Persistence

    public static func saveSubscriptions(_ subscriptions: [SubscriptionGroup]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(subscriptions)
        try data.write(to: subscriptionsFileURL, options: .atomic)
    }

    public static func loadSubscriptions() -> [SubscriptionGroup] {
        guard let data = try? Data(contentsOf: subscriptionsFileURL),
              let subs = try? JSONDecoder().decode([SubscriptionGroup].self, from: data) else {
            return []
        }
        return subs
    }

    // MARK: - Routing Rules Persistence

    public static func saveRules(_ rules: [RoutingRule]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(rules)
        try data.write(to: rulesFileURL, options: .atomic)
    }

    public static func loadRules() -> [RoutingRule] {
        guard let data = try? Data(contentsOf: rulesFileURL),
              let rules = try? JSONDecoder().decode([RoutingRule].self, from: data) else {
            return []
        }
        return rules
    }

    // MARK: - Preferences & State Helpers

    public static func getActiveNodeId() -> UUID? {
        guard let uuidString = userDefaults.string(forKey: Keys.activeNodeId) else { return nil }
        return UUID(uuidString: uuidString)
    }

    public static func setActiveNodeId(_ id: UUID?) {
        if let id = id {
            userDefaults.set(id.uuidString, forKey: Keys.activeNodeId)
        } else {
            userDefaults.removeObject(forKey: Keys.activeNodeId)
        }
    }

    public static func getGlobalRoutingMode() -> GlobalRoutingMode {
        guard let raw = userDefaults.string(forKey: Keys.globalRoutingMode),
              let mode = GlobalRoutingMode(rawValue: raw) else {
            return .config
        }
        return mode
    }

    public static func setGlobalRoutingMode(_ mode: GlobalRoutingMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.globalRoutingMode)
    }

    public static func getMTU() -> Int {
        let mtu = userDefaults.integer(forKey: Keys.mtu)
        return mtu > 0 ? mtu : 1280 // Default to 1280 for STUN/TURN overhead
    }

    public static func setMTU(_ mtu: Int) {
        userDefaults.set(mtu, forKey: Keys.mtu)
    }

    public static func getRemoteDNS() -> String {
        return userDefaults.string(forKey: Keys.remoteDns) ?? "https://1.1.1.1/dns-query"
    }

    public static func setRemoteDNS(_ dns: String) {
        userDefaults.set(dns, forKey: Keys.remoteDns)
    }

    public static func getDirectDNS() -> String {
        return userDefaults.string(forKey: Keys.directDns) ?? "77.88.8.8"
    }

    public static func setDirectDNS(_ dns: String) {
        userDefaults.set(dns, forKey: Keys.directDns)
    }
}

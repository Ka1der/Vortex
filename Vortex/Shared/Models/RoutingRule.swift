import Foundation

/// Global routing operation mode
public enum GlobalRoutingMode: String, Codable, CaseIterable, Sendable {
    case config = "config" // Rule-based: routes according to domain/IP/Geo rules
    case proxy = "proxy"   // Global proxy: all traffic goes through VPN node
    case direct = "direct" // Direct: all traffic bypasses VPN
    case block = "block"   // Block: all traffic is dropped

    public var displayName: String {
        switch self {
        case .config:
            return "Конфигурация"
        case .proxy:
            return "Прокси"
        case .direct:
            return "Напрямую"
        case .block:
            return "Блокировка"
        }
    }

    public var englishName: String {
        switch self {
        case .config:
            return "Rule Config"
        case .proxy:
            return "Global Proxy"
        case .direct:
            return "Direct"
        case .block:
            return "Block"
        }
    }

    public var iconName: String {
        switch self {
        case .config:
            return "arrow.triangle.branch"
        case .proxy:
            return "network"
        case .direct:
            return "arrow.up.right"
        case .block:
            return "xmark.shield"
        }
    }
}

/// Matching criteria for a routing rule
public enum RuleType: String, Codable, CaseIterable, Sendable {
    case domain = "DOMAIN"
    case domainSuffix = "DOMAIN-SUFFIX"
    case domainKeyword = "DOMAIN-KEYWORD"
    case ipCidr = "IP-CIDR"
    case geoip = "GEOIP"
    case geosite = "GEOSITE"

    public var displayName: String {
        return self.rawValue
    }
}

/// Target action when a rule matches
public enum RuleAction: String, Codable, CaseIterable, Sendable {
    case proxy = "PROXY"
    case direct = "DIRECT"
    case block = "BLOCK"

    public var displayName: String {
        return self.rawValue
    }

    /// Corresponding sing-box outbound tag
    public var outboundTag: String {
        switch self {
        case .proxy:
            return "proxy-out"
        case .direct:
            return "direct-out"
        case .block:
            return "block-out"
        }
    }
}

/// Individual routing rule definition
public struct RoutingRule: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var type: RuleType
    public var value: String
    public var action: RuleAction
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        type: RuleType,
        value: String,
        action: RuleAction,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.type = type
        self.value = value
        self.action = action
        self.isEnabled = isEnabled
    }

    /// Baseline rules (empty by default)
    public static var defaultRules: [RoutingRule] {
        return []
    }
}

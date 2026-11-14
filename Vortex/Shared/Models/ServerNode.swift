import Foundation

/// Supported protocol types for proxy outbounds
public enum ProtocolType: String, Codable, CaseIterable, Sendable {
    case vless = "vless"
    case proprietary = "proprietary"
    case vkCall = "vkCall"

    public var displayName: String {
        switch self {
        case .vless:
            return "VLESS"
        case .proprietary:
            return "Vortex Proprietary"
        case .vkCall:
            return "VK Call Tunnel"
        }
    }
}

/// Network transport type for VLESS
public enum VLESSNetwork: String, Codable, CaseIterable, Sendable {
    case tcp = "tcp"
    case udp = "udp"
    case ws = "ws"
    case grpc = "grpc"
}

/// Security layer for VLESS
public enum VLESSSecurity: String, Codable, CaseIterable, Sendable {
    case reality = "reality"
    case tls = "tls"
    case none = "none"
}

/// Configuration payload for VLESS protocol
public struct VLESSConfig: Codable, Hashable, Sendable {
    public var uuid: String
    public var address: String
    public var port: Int
    public var flow: String? // e.g. "xtls-rprx-vision"
    public var security: String // "reality", "tls", "none"
    public var sni: String?
    public var publicKey: String? // pbk (Reality)
    public var shortId: String? // sid (Reality)
    public var fingerprint: String? // fp (e.g. "chrome", "firefox", "safari")
    public var network: String // "tcp", "udp", "ws", "grpc"
    public var wsPath: String?
    public var wsHeaders: [String: String]?
    public var grpcServiceName: String?

    public init(
        uuid: String,
        address: String,
        port: Int,
        flow: String? = "xtls-rprx-vision",
        security: String = "reality",
        sni: String? = nil,
        publicKey: String? = nil,
        shortId: String? = nil,
        fingerprint: String? = "chrome",
        network: String = "tcp",
        wsPath: String? = nil,
        wsHeaders: [String: String]? = nil,
        grpcServiceName: String? = nil
    ) {
        self.uuid = uuid
        self.address = address
        self.port = port
        self.flow = flow
        self.security = security
        self.sni = sni
        self.publicKey = publicKey
        self.shortId = shortId
        self.fingerprint = fingerprint
        self.network = network
        self.wsPath = wsPath
        self.wsHeaders = wsHeaders
        self.grpcServiceName = grpcServiceName
    }
}

/// Configuration payload for Vortex Proprietary protocol
public struct ProprietaryConfig: Codable, Hashable, Sendable {
    public var address: String
    public var port: Int
    public var secretKey: String
    public var obfuscationMode: String // e.g. "udp-mask", "tls-mimic"
    public var extraParams: [String: String]

    public init(
        address: String,
        port: Int,
        secretKey: String,
        obfuscationMode: String = "udp-mask",
        extraParams: [String: String] = [:]
    ) {
        self.address = address
        self.port = port
        self.secretKey = secretKey
        self.obfuscationMode = obfuscationMode
        self.extraParams = extraParams
    }
}

/// Credentials for TURN relay server
public struct TurnCredentials: Codable, Hashable, Sendable {
    public var username: String
    public var password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

/// Configuration payload for VK Call Tunnel
public struct VKCallConfig: Codable, Hashable, Sendable {
    public var callJoinLink: String
    public var relayAddress: String
    public var relayPort: Int
    public var turnCredentials: TurnCredentials?
    public var secretKey: String?

    public init(
        callJoinLink: String,
        relayAddress: String,
        relayPort: Int,
        turnCredentials: TurnCredentials? = nil,
        secretKey: String? = nil
    ) {
        self.callJoinLink = callJoinLink
        self.relayAddress = relayAddress
        self.relayPort = relayPort
        self.turnCredentials = turnCredentials
        self.secretKey = secretKey
    }
}

/// Polymorphic node configuration
public enum NodeConfiguration: Codable, Hashable, Sendable {
    case vless(VLESSConfig)
    case proprietary(ProprietaryConfig)
    case vkCall(VKCallConfig)

    private enum CodingKeys: String, CodingKey {
        case type
        case vlessConfig
        case proprietaryConfig
        case vkCallConfig
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ProtocolType.self, forKey: .type)
        switch type {
        case .vless:
            let config = try container.decode(VLESSConfig.self, forKey: .vlessConfig)
            self = .vless(config)
        case .proprietary:
            let config = try container.decode(ProprietaryConfig.self, forKey: .proprietaryConfig)
            self = .proprietary(config)
        case .vkCall:
            let config = try container.decode(VKCallConfig.self, forKey: .vkCallConfig)
            self = .vkCall(config)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .vless(let config):
            try container.encode(ProtocolType.vless, forKey: .type)
            try container.encode(config, forKey: .vlessConfig)
        case .proprietary(let config):
            try container.encode(ProtocolType.proprietary, forKey: .type)
            try container.encode(config, forKey: .proprietaryConfig)
        case .vkCall(let config):
            try container.encode(ProtocolType.vkCall, forKey: .type)
            try container.encode(config, forKey: .vkCallConfig)
        }
    }
}

/// Unified VPN Server Node model
public struct ServerNode: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var configuration: NodeConfiguration
    public var latencyMs: Int?
    public var subscriptionId: UUID?
    public var isConnected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        configuration: NodeConfiguration,
        latencyMs: Int? = nil,
        subscriptionId: UUID? = nil,
        isConnected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
        self.latencyMs = latencyMs
        self.subscriptionId = subscriptionId
        self.isConnected = isConnected
    }

    // MARK: - Convenience Accessors

    public var protocolType: ProtocolType {
        switch configuration {
        case .vless:
            return .vless
        case .proprietary:
            return .proprietary
        case .vkCall:
            return .vkCall
        }
    }

    public var address: String {
        switch configuration {
        case .vless(let config):
            return config.address
        case .proprietary(let config):
            return config.address
        case .vkCall(let config):
            return config.relayAddress
        }
    }

    public var port: Int {
        switch configuration {
        case .vless(let config):
            return config.port
        case .proprietary(let config):
            return config.port
        case .vkCall(let config):
            return config.relayPort
        }
    }

    public var isAvailable: Bool {
        guard let latency = latencyMs else { return false }
        return latency >= 0
    }

    /// Subtitle string conforming to Shadowrocket style:
    /// e.g. "VLESS / XTLS-RPRX-VISION / TCP", "VORTEX / UDP-MASK / UDP", "VK-CALL / TURN-RELAY / UDP"
    public var subtitle: String {
        switch configuration {
        case .vless(let config):
            var parts: [String] = ["VLESS"]
            if let flow = config.flow, !flow.isEmpty {
                parts.append(flow.uppercased())
            } else if !config.security.isEmpty && config.security != "none" {
                parts.append(config.security.uppercased())
            }
            parts.append(config.network.uppercased())
            return parts.joined(separator: " / ")

        case .proprietary(let config):
            let mode = config.obfuscationMode.isEmpty ? "PROPRIETARY" : config.obfuscationMode.uppercased()
            return "VORTEX / \(mode) / UDP"

        case .vkCall:
            return "VK-CALL / TURN-RELAY / UDP"
        }
    }

    /// Derived country flag emoji or network icon
    public var flag: String {
        // 1. Check if name already has an emoji flag
        for scalar in name.unicodeScalars {
            // Regional indicator symbol letters: 0x1F1E6...0x1F1FF
            if (0x1F1E6...0x1F1FF).contains(scalar.value) {
                // Extract contiguous regional indicator sequence
                let scalars = name.unicodeScalars.filter { (0x1F1E6...0x1F1FF).contains($0.value) }
                if scalars.count >= 2 {
                    return String(String.UnicodeScalarView(scalars.prefix(2)))
                }
            }
        }

        // 2. Look for two-letter country codes in brackets, prefixes or uppercase words
        let uppercaseName = name.uppercased()
        let knownCountryCodes = [
            "RU", "US", "NL", "DE", "FI", "GB", "UK", "FR", "JP", "SG",
            "HK", "TR", "SE", "CH", "PL", "CA", "AU", "KZ", "UA", "BY",
            "ES", "IT", "CZ", "AT", "NO", "DK", "EE", "LV", "LT", "GE",
            "AM", "AZ", "UZ", "MD", "IL", "AE", "KR", "IN", "BR", "ZA"
        ]

        for code in knownCountryCodes {
            let actualCode = (code == "UK") ? "GB" : code
            // Look for isolated word or surrounded by brackets / dashes / spaces
            let patterns = ["[\(code)]", "(\(code))", "\(code)-", "-\(code)", " \(code) ", " \(code)-", "[\(code)"]
            if patterns.contains(where: { uppercaseName.contains($0) }) || uppercaseName.hasPrefix("\(code) ") || uppercaseName.hasPrefix("\(code)-") {
                return flagEmoji(forCountryCode: actualCode)
            }
        }

        // 3. Fallback to generic network globe
        return "🌐"
    }

    private func flagEmoji(forCountryCode countryCode: String) -> String {
        let base: UInt32 = 127397
        var scalarView = String.UnicodeScalarView()
        for scalar in countryCode.uppercased().unicodeScalars {
            if let newScalar = UnicodeScalar(base + scalar.value) {
                scalarView.append(newScalar)
            }
        }
        return String(scalarView)
    }
}

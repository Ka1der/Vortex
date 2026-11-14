import Foundation
import Darwin

/// Errors occurring during sing-box configuration generation
public enum ConfigBuilderError: LocalizedError, Sendable {
    case invalidNodeAddress(String)
    case invalidNodePort(Int)
    case serializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidNodeAddress(let addr):
            return "Некорректный адрес сервера: \(addr)"
        case .invalidNodePort(let port):
            return "Некорректный порт сервера: \(port)"
        case .serializationFailed(let reason):
            return "Ошибка сериализации конфигурации sing-box: \(reason)"
        }
    }
}

/// Generates valid, production-ready sing-box JSON configuration
/// Incorporates strict anti-loop protection, DNS split-routing, and mode-based rule dispatch
public enum ConfigBuilder {

    // MARK: - Public API

    /// Builds a formatted sing-box JSON string
    public static func buildConfig(
        node: ServerNode,
        mode: GlobalRoutingMode,
        rules: [RoutingRule] = [],
        mtu: Int = 1280,
        remoteDns: String = "https://1.1.1.1/dns-query",
        directDns: String = "77.88.8.8"
    ) throws -> String {
        let data = try buildConfigData(
            node: node,
            mode: mode,
            rules: rules,
            mtu: mtu,
            remoteDns: remoteDns,
            directDns: directDns
        )
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw ConfigBuilderError.serializationFailed("Не удалось преобразовать JSON-данные в строку UTF-8")
        }
        return jsonString
    }

    /// Builds a pretty-printed sing-box JSON Data buffer
    public static func buildConfigData(
        node: ServerNode,
        mode: GlobalRoutingMode,
        rules: [RoutingRule] = [],
        mtu: Int = 1280,
        remoteDns: String = "https://1.1.1.1/dns-query",
        directDns: String = "77.88.8.8"
    ) throws -> Data {
        let dict = buildConfigDictionary(
            node: node,
            mode: mode,
            rules: rules,
            mtu: mtu,
            remoteDns: remoteDns,
            directDns: directDns
        )

        do {
            return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw ConfigBuilderError.serializationFailed(error.localizedDescription)
        }
    }

    /// Assembles the complete root dictionary for sing-box configuration
    public static func buildConfigDictionary(
        node: ServerNode,
        mode: GlobalRoutingMode,
        rules: [RoutingRule] = [],
        mtu: Int = 1280,
        remoteDns: String = "https://1.1.1.1/dns-query",
        directDns: String = "77.88.8.8"
    ) -> [String: Any] {
        var config: [String: Any] = [:]

        // 1. Log block
        config["log"] = [
            "level": "warn",
            "timestamp": true
        ]

        // 2. DNS block
        config["dns"] = buildDNSBlock(
            node: node,
            remoteDns: remoteDns,
            directDns: directDns
        )

        // 3. Inbounds (Virtual TUN + Local Mixed SOCKS5/HTTP Proxy)
        var inbounds: [[String: Any]] = [
            [
                "type": "mixed",
                "tag": "mixed-in",
                "listen": "127.0.0.1",
                "listen_port": 10808,
                "sniff": true,
                "sniff_override_destination": true
            ]
        ]
        #if !os(macOS)
        inbounds.append(buildTunInbound(mtu: mtu))
        #endif
        config["inbounds"] = inbounds

        // 4. Outbounds (Proxy, Direct, Block, DNS)
        config["outbounds"] = buildOutbounds(node: node)

        // 5. Routing engine with Anti-Loop protection
        config["route"] = buildRouteBlock(
            node: node,
            mode: mode,
            rules: rules
        )

        return config
    }

    // MARK: - DNS Configuration

    private static func buildDNSBlock(
        node: ServerNode,
        remoteDns: String,
        directDns: String
    ) -> [String: Any] {
        let dnsServers: [[String: Any]] = [
            [
                "tag": "dns-remote",
                "address": remoteDns,
                "address_resolver": "dns-direct",
                "strategy": "prefer_ipv4",
                "detour": "proxy-out"
            ],
            [
                "tag": "dns-direct",
                "address": directDns,
                "strategy": "prefer_ipv4",
                "detour": "direct-out"
            ],
            [
                "tag": "dns-block",
                "address": "rcode://refused"
            ]
        ]

        var dnsRules: [[String: Any]] = []

        // Direct server hostname resolution (Anti-Loop for DNS)
        let serverAddr = node.address
        if !isIPAddress(serverAddr) && !serverAddr.isEmpty {
            dnsRules.append([
                "domain": [serverAddr],
                "server": "dns-direct"
            ])
        }

        // VK Signaling and relay domains for VKCall
        if case .vkCall = node.configuration {
            dnsRules.append([
                "domain_suffix": ["vk.com", "mycdn.me", "userapi.com", "vk-portal.net", "vkuser.net"],
                "server": "dns-direct"
            ])
        }

        // Standard direct domains (.ru, .рф, punycode)
        dnsRules.append([
            "domain_suffix": ["ru", "рф", "xn--p1ai"],
            "server": "dns-direct"
        ])

        return [
            "servers": dnsServers,
            "rules": dnsRules,
            "final": "dns-remote",
            "strategy": "prefer_ipv4",
            "independent_cache": true
        ]
    }

    // MARK: - TUN Inbound

    private static func buildTunInbound(mtu: Int) -> [String: Any] {
        return [
            "type": "tun",
            "tag": "tun-in",
            "interface_name": "utun",
            "inet4_address": "172.19.0.1/30",
            "mtu": mtu,
            "auto_route": true,
            "strict_route": true,
            "stack": "system",
            "sniff": true,
            "sniff_override_destination": false
        ]
    }

    // MARK: - Outbounds

    private static func buildOutbounds(node: ServerNode) -> [[String: Any]] {
        var outbounds: [[String: Any]] = []

        // Active Proxy Outbound
        let proxyOutbound = buildActiveProxyOutbound(node: node)
        outbounds.append(proxyOutbound)

        // Direct Outbound
        outbounds.append([
            "type": "direct",
            "tag": "direct-out"
        ])

        // Block Outbound
        outbounds.append([
            "type": "block",
            "tag": "block-out"
        ])

        // DNS Detour Outbound
        outbounds.append([
            "type": "dns",
            "tag": "dns-out"
        ])

        return outbounds
    }

    private static func buildActiveProxyOutbound(node: ServerNode) -> [String: Any] {
        switch node.configuration {
        case .vless(let cfg):
            var outbound: [String: Any] = [
                "type": "vless",
                "tag": "proxy-out",
                "server": cfg.address,
                "server_port": cfg.port,
                "uuid": cfg.uuid,
                "packet_encoding": "xudp"
            ]

            if let flow = cfg.flow, !flow.isEmpty {
                outbound["flow"] = flow
            }

            // TLS / Reality
            if cfg.security == "reality" {
                var realityDict: [String: Any] = ["enabled": true]
                if let pbk = cfg.publicKey, !pbk.isEmpty {
                    realityDict["public_key"] = normalizeRealityPublicKey(pbk)
                }
                if let sid = cfg.shortId, !sid.isEmpty {
                    realityDict["short_id"] = sid
                }

                let fp = (cfg.fingerprint?.isEmpty == false) ? cfg.fingerprint! : "chrome"
                let tlsDict: [String: Any] = [
                    "enabled": true,
                    "server_name": cfg.sni ?? cfg.address,
                    "reality": realityDict,
                    "utls": [
                        "enabled": true,
                        "fingerprint": fp
                    ]
                ]
                outbound["tls"] = tlsDict

            } else if cfg.security == "tls" {
                var tlsDict: [String: Any] = [
                    "enabled": true,
                    "server_name": cfg.sni ?? cfg.address
                ]
                if let fp = cfg.fingerprint, !fp.isEmpty {
                    tlsDict["utls"] = [
                        "enabled": true,
                        "fingerprint": fp
                    ]
                }
                outbound["tls"] = tlsDict
            }

            // Transport: WebSocket or gRPC
            if cfg.network == "ws" {
                var wsDict: [String: Any] = [
                    "type": "ws",
                    "path": cfg.wsPath ?? "/"
                ]
                if let headers = cfg.wsHeaders, !headers.isEmpty {
                    wsDict["headers"] = headers
                }
                outbound["transport"] = wsDict
            } else if cfg.network == "grpc" {
                outbound["transport"] = [
                    "type": "grpc",
                    "service_name": cfg.grpcServiceName ?? ""
                ]
            }

            return outbound

        case .proprietary(let cfg):
            var customOutbound: [String: Any] = [
                "type": "custom",
                "tag": "proxy-out",
                "server": cfg.address,
                "server_port": cfg.port,
                "custom_type": "vortex_proto",
                "secret_key": cfg.secretKey,
                "obfuscation_mode": cfg.obfuscationMode
            ]
            if !cfg.extraParams.isEmpty {
                customOutbound["extra"] = cfg.extraParams
            }
            return customOutbound

        case .vkCall(let cfg):
            var customOutbound: [String: Any] = [
                "type": "custom",
                "tag": "proxy-out",
                "server": cfg.relayAddress,
                "server_port": cfg.relayPort,
                "custom_type": "vk_call_tunnel",
                "call_join_link": cfg.callJoinLink
            ]
            if let creds = cfg.turnCredentials {
                customOutbound["turn_username"] = creds.username
                customOutbound["turn_password"] = creds.password
            }
            if let secret = cfg.secretKey {
                customOutbound["secret_key"] = secret
            }
            return customOutbound
        }
    }

    // MARK: - Routing Block & Anti-Loop

    private static func buildRouteBlock(
        node: ServerNode,
        mode: GlobalRoutingMode,
        rules: [RoutingRule]
    ) -> [String: Any] {
        var routeRules: [[String: Any]] = []

        // 1. Intercept standard DNS requests
        routeRules.append([
            "protocol": ["dns"],
            "outbound": "dns-out"
        ])
        routeRules.append([
            "port": [53],
            "outbound": "dns-out"
        ])

        // 2. ANTI-LOOP PROTECTION (Placed at the very top of routing rules)
        let antiLoopRules = generateAntiLoopRules(for: node)
        routeRules.append(contentsOf: antiLoopRules)

        // 3. Private network addresses always direct (LAN / localhost)
        routeRules.append([
            "ip_is_private": true,
            "outbound": "direct-out"
        ])
        routeRules.append([
            "ip_cidr": [
                "10.0.0.0/8",
                "172.16.0.0/12",
                "192.168.0.0/16",
                "127.0.0.0/8",
                "fc00::/7",
                "fe80::/10"
            ],
            "outbound": "direct-out"
        ])

        #if os(macOS)
        let autoDetect = false
        #else
        let autoDetect = true
        #endif

        // 4. Mode-specific dispatch
        switch mode {
        case .direct:
            // Entire traffic routes directly
            routeRules.append([
                "outbound": "direct-out"
            ])
            return [
                "auto_detect_interface": autoDetect,
                "final": "direct-out",
                "rules": routeRules
            ]

        case .block:
            // Entire traffic drops
            routeRules.append([
                "outbound": "block-out"
            ])
            return [
                "auto_detect_interface": autoDetect,
                "final": "block-out",
                "rules": routeRules
            ]

        case .proxy:
            // Global proxy: all non-anti-loop traffic routes via VPN outbound
            return [
                "auto_detect_interface": autoDetect,
                "final": "proxy-out",
                "rules": routeRules
            ]

        case .config:
            // Rule-based routing: evaluate user-configured domain/IP/Geo rules
            for rule in rules where rule.isEnabled {
                let targetOutbound = rule.action.outboundTag
                switch rule.type {
                case .domain:
                    routeRules.append([
                        "domain": [rule.value],
                        "outbound": targetOutbound
                    ])
                case .domainSuffix:
                    routeRules.append([
                        "domain_suffix": [rule.value],
                        "outbound": targetOutbound
                    ])
                case .domainKeyword:
                    routeRules.append([
                        "domain_keyword": [rule.value],
                        "outbound": targetOutbound
                    ])
                case .ipCidr:
                    routeRules.append([
                        "ip_cidr": [rule.value],
                        "outbound": targetOutbound
                    ])
                case .geoip:
                    routeRules.append([
                        "geoip": [rule.value],
                        "outbound": targetOutbound
                    ])
                case .geosite:
                    routeRules.append([
                        "geosite": [rule.value],
                        "outbound": targetOutbound
                    ])
                }
            }

            return [
                "auto_detect_interface": autoDetect,
                "final": "proxy-out",
                "rules": routeRules
            ]
        }
    }

    /// Critical anti-loop rules guaranteeing VPN server packets and signaling never loop into the TUN interface
    private static func generateAntiLoopRules(for node: ServerNode) -> [[String: Any]] {
        var rules: [[String: Any]] = []

        let serverAddr = node.address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !serverAddr.isEmpty {
            if isIPv4(serverAddr) {
                rules.append([
                    "ip_cidr": ["\(serverAddr)/32"],
                    "outbound": "direct-out"
                ])
            } else if isIPv6(serverAddr) {
                rules.append([
                    "ip_cidr": ["\(serverAddr)/128"],
                    "outbound": "direct-out"
                ])
            } else {
                rules.append([
                    "domain": [serverAddr],
                    "outbound": "direct-out"
                ])
            }
        }

        // If node has SNI different from address, bypass SNI domain too
        if case .vless(let cfg) = node.configuration,
           let sni = cfg.sni?.trimmingCharacters(in: .whitespacesAndNewlines),
           !sni.isEmpty,
           sni != serverAddr {
            rules.append([
                "domain": [sni],
                "outbound": "direct-out"
            ])
        }

        // VK Call signaling and media relay infrastructure bypass
        if case .vkCall = node.configuration {
            rules.append([
                "domain_suffix": [
                    "vk.com",
                    "mycdn.me",
                    "userapi.com",
                    "vk-portal.net",
                    "vkuser.net"
                ],
                "outbound": "direct-out"
            ])
        }

        return rules
    }

    // MARK: - IP Address Verification

    private static func isIPAddress(_ string: String) -> Bool {
        return isIPv4(string) || isIPv6(string)
    }

    private static func isIPv4(_ string: String) -> Bool {
        var sin = sockaddr_in()
        return string.withCString { cstr in
            inet_pton(AF_INET, cstr, &sin.sin_addr) == 1
        }
    }

    private static func isIPv6(_ string: String) -> Bool {
        var sin6 = sockaddr_in6()
        return string.withCString { cstr in
            inet_pton(AF_INET6, cstr, &sin6.sin6_addr) == 1
        }
    }

    /// Normalizes Reality X25519 public key to standard 32-byte RawURLEncoding (43 chars) expected by sing-box
    public static func normalizeRealityPublicKey(_ rawKey: String) -> String {
        var key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        key = key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let rem = key.count % 4
        if rem > 0 { key.append(String(repeating: "=", count: 4 - rem)) }
        if let data = Data(base64Encoded: key) {
            let keyBytes = data.prefix(32)
            if keyBytes.count == 32 {
                var b64url = keyBytes.base64EncodedString()
                    .replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_")
                while b64url.hasSuffix("=") { b64url.removeLast() }
                return b64url
            }
        }
        return rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

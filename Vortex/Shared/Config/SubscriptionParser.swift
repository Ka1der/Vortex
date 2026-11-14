import Foundation

/// Errors that can occur during subscription or node URI parsing
public enum SubscriptionParseError: LocalizedError, Sendable {
    case invalidURL(String)
    case unsupportedScheme(String)
    case missingHost(String)
    case missingUUID(String)
    case decodingFailed(String)
    case emptySubscription
    case networkError(String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let raw):
            return "Некорректный формат ссылки: \(raw)"
        case .unsupportedScheme(let scheme):
            return "Неподдерживаемый протокол/схема: \(scheme)"
        case .missingHost(let raw):
            return "В ссылке отсутствует хост/адрес сервера: \(raw)"
        case .missingUUID(let raw):
            return "В ссылке отсутствует UUID пользователя: \(raw)"
        case .decodingFailed(let detail):
            return "Ошибка декодирования данных подписки: \(detail)"
        case .emptySubscription:
            return "В подписке не найдено ни одного валидного сервера"
        case .networkError(let message):
            return "Сетевая ошибка при загрузке подписки: \(message)"
        case .invalidResponse:
            return "Некорректный ответ удаленного сервера подписки"
        }
    }
}

/// High-performance parser for VLESS, Vortex Proprietary, VK Call and Base64 subscriptions
public enum SubscriptionParser {

    // MARK: - Single Node Parsing

    /// Parses a single configuration link (`vless://`, `vortex://`, or `vkcall://`)
    /// Handles all known real-world QR formats, URL encoding, Base64 wrappers, and query parameters.
    public static func parseNode(from rawLink: String, subscriptionId: UUID? = nil) throws -> ServerNode {
        var text = rawLink.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{200B}\u{FEFF}\u{0000}"))

        guard !text.isEmpty else {
            throw SubscriptionParseError.invalidURL(rawLink)
        }

        // 1. Remove surrounding quotes if present
        if (text.hasPrefix("\"") && text.hasSuffix("\"")) || (text.hasPrefix("'") && text.hasSuffix("'")) {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Decode percent-encoding if the URL scheme itself is encoded (e.g. vless%3A%2F%2F)
        if text.lowercased().hasPrefix("vless%3a") || text.contains("%3A%2F%2F") || text.contains("%3a%2f%2f") {
            if let decoded = text.removingPercentEncoding {
                text = decoded
            }
        }

        // 3. If raw string is an entire Base64-encoded string without "://":
        if !text.contains("://") && !text.hasPrefix("vless:") && !text.hasPrefix("vortex:") && !text.hasPrefix("vkcall:") {
            if let decoded = decodeBase64Flexible(text) {
                let trimmedDecoded = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedDecoded.contains("://") || trimmedDecoded.hasPrefix("vless:") || trimmedDecoded.hasPrefix("{") {
                    text = trimmedDecoded
                }
            }
        }

        // 4. Check if raw string is JSON directly (e.g. Shadowrocket JSON export, v2ray config JSON)
        if text.hasPrefix("{") && text.hasSuffix("}") {
            return try parseNodeFromJSON(rawText: text, subscriptionId: subscriptionId)
        }

        // 5. Separate URL base and fragment (#Remark) safely before parsing
        let parts = text.components(separatedBy: "#")
        let basePart = parts[0]
        let rawRemark = parts.count > 1 ? parts.dropFirst().joined(separator: "#") : ""
        let remark = rawRemark.removingPercentEncoding ?? rawRemark

        // 6. Extract scheme flexibly (supporting :// and :)
        let scheme: String
        let afterSchemeRaw: String
        if let schemeEndRange = basePart.range(of: "://") {
            scheme = String(basePart[..<schemeEndRange.lowerBound]).lowercased()
            afterSchemeRaw = String(basePart[schemeEndRange.upperBound...])
        } else if let colonRange = basePart.range(of: ":") {
            scheme = String(basePart[..<colonRange.lowerBound]).lowercased()
            afterSchemeRaw = String(basePart[colonRange.upperBound...])
        } else {
            throw SubscriptionParseError.unsupportedScheme(rawLink)
        }

        switch scheme {
        case "vless":
            return try parseVLESS(afterSchemeRaw: afterSchemeRaw, rawRemark: remark, subscriptionId: subscriptionId)
        case "vortex":
            return try parseVortex(afterSchemeRaw: afterSchemeRaw, rawRemark: remark, subscriptionId: subscriptionId)
        case "vkcall":
            return try parseVKCall(afterSchemeRaw: afterSchemeRaw, rawRemark: remark, subscriptionId: subscriptionId)
        default:
            throw SubscriptionParseError.unsupportedScheme(scheme)
        }
    }

    // MARK: - JSON Node Parser (Shadowrocket / v2ray / sing-box)

    private static func parseNodeFromJSON(rawText: String, subscriptionId: UUID?) throws -> ServerNode {
        guard let data = rawText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubscriptionParseError.decodingFailed("Некорректный JSON")
        }

        let type = ((json["type"] as? String) ?? "VLESS").uppercased()
        guard type == "VLESS" else {
            throw SubscriptionParseError.unsupportedScheme(type)
        }

        // UUID / Password: in Shadowrocket JSON, the UUID is stored in "password"
        let uuid = (json["password"] as? String) ?? (json["id"] as? String) ?? (json["uuid"] as? String) ?? ""
        guard !uuid.isEmpty else {
            throw SubscriptionParseError.missingUUID(rawText)
        }

        // Host
        let host = (json["host"] as? String) ?? (json["add"] as? String) ?? (json["address"] as? String) ?? ""
        guard !host.isEmpty else {
            throw SubscriptionParseError.missingHost(rawText)
        }

        // Port
        let port: Int
        if let pInt = json["port"] as? Int {
            port = pInt
        } else if let pStr = json["port"] as? String, let pParsed = Int(pStr) {
            port = pParsed
        } else {
            port = 443
        }

        // Title / Name
        let name = (json["title"] as? String) ?? (json["remarks"] as? String) ?? (json["ps"] as? String) ?? "\(host):\(port)"

        // Reality / TLS
        let publicKey = (json["publicKey"] as? String) ?? (json["pbk"] as? String)
        let shortId = (json["shortId"] as? String) ?? (json["sid"] as? String)
        let peer = (json["peer"] as? String) ?? (json["sni"] as? String) ?? (json["servername"] as? String)
        let fp = (json["fingerprint"] as? String) ?? (json["fp"] as? String) ?? "chrome"

        let security: String
        if let pbk = publicKey, !pbk.isEmpty {
            security = "reality"
        } else if json["tls"] as? Bool == true || (json["tls"] as? String) == "1" || (json["security"] as? String)?.lowercased() == "tls" {
            security = "tls"
        } else {
            security = (json["security"] as? String)?.lowercased() ?? "none"
        }

        // XTLS / Flow: in Shadowrocket xtls: 2 means xtls-rprx-vision
        let xtls = json["xtls"]
        let flow: String?
        if let xtlsInt = xtls as? Int, xtlsInt == 2 {
            flow = "xtls-rprx-vision"
        } else if let xtlsStr = xtls as? String, xtlsStr == "2" || xtlsStr.lowercased() == "vision" {
            flow = "xtls-rprx-vision"
        } else if let flowStr = json["flow"] as? String, !flowStr.isEmpty {
            flow = flowStr
        } else {
            flow = nil
        }

        let network = ((json["network"] as? String) ?? (json["net"] as? String) ?? (json["obfs"] as? String) ?? "tcp").lowercased()

        let config = VLESSConfig(
            uuid: uuid,
            address: host,
            port: port,
            flow: flow,
            security: security,
            sni: peer,
            publicKey: publicKey,
            shortId: shortId,
            fingerprint: fp,
            network: network == "none" ? "tcp" : network,
            wsPath: json["path"] as? String,
            wsHeaders: peer.map { ["Host": $0] }
        )

        return ServerNode(
            name: name,
            configuration: .vless(config),
            subscriptionId: subscriptionId
        )
    }

    // MARK: - VLESS Parser

    /// Parses VLESS links across all real-world formats:
    /// - Standard: <uuid>@<host>:<port>?<query>
    /// - URL-encoded: <uuid>%40<host>:<port>?<query>
    /// - Query UUID: <host>:<port>?uuid=<uuid> or ?id=<uuid>
    /// - Base64 authority: <base64> containing uuid@host:port or JSON
    /// - JSON directly: {"id": "...", "add": "...", "port": ...}
    /// - UUID with password or braces: <uuid>:<pass>@... or {<uuid>}@...
    private static func parseVLESS(afterSchemeRaw: String, rawRemark: String, subscriptionId: UUID?) throws -> ServerNode {
        var content = afterSchemeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        while content.hasPrefix("/") {
            content.removeFirst()
        }

        // 1. Separate authority part from query parameters BEFORE decoding
        let hostPortAndQuery = content.components(separatedBy: "?")
        var authorityPart = hostPortAndQuery[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let queryStr = hostPortAndQuery.count > 1 ? hostPortAndQuery.dropFirst().joined(separator: "?") : ""

        // 2. Decode Base64 authority if no '@' is present (Shadowrocket format: none:uuid@host:port in Base64)
        if !authorityPart.contains("@") {
            if let decoded = decodeBase64Flexible(authorityPart) {
                let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.contains("@") || trimmed.hasPrefix("{") {
                    authorityPart = trimmed
                }
            }
        }

        // 3. Check if authorityPart is JSON (e.g. from v2ray JSON export)
        if authorityPart.hasPrefix("{") {
            if let data = authorityPart.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let uuid = (json["id"] as? String) ?? (json["uuid"] as? String) ?? ""
                guard !uuid.isEmpty else {
                    throw SubscriptionParseError.missingUUID(afterSchemeRaw)
                }
                let host = (json["add"] as? String) ?? (json["host"] as? String) ?? ""
                let portStr = String(describing: json["port"] ?? 443)
                let port = Int(portStr) ?? 443
                let flow = json["flow"] as? String
                let security = ((json["tls"] as? String) ?? (json["security"] as? String) ?? "none").lowercased()
                let sni = (json["sni"] as? String) ?? (json["peer"] as? String) ?? (json["host"] as? String)
                let pbk = (json["pbk"] as? String) ?? (json["publicKey"] as? String)
                let sid = (json["sid"] as? String) ?? (json["shortId"] as? String)
                let fp = (json["fp"] as? String) ?? "chrome"
                let net = ((json["net"] as? String) ?? (json["type"] as? String) ?? "tcp").lowercased()
                let path = json["path"] as? String
                let ps = (json["ps"] as? String) ?? (json["remarks"] as? String) ?? rawRemark
                let nodeName = ps.isEmpty ? "\(host):\(port)" : ps

                let cfg = VLESSConfig(
                    uuid: uuid,
                    address: host,
                    port: port,
                    flow: flow,
                    security: security,
                    sni: sni,
                    publicKey: pbk,
                    shortId: sid,
                    fingerprint: fp,
                    network: net,
                    wsPath: path,
                    wsHeaders: sni.map { ["Host": $0] }
                )
                return ServerNode(name: nodeName, configuration: .vless(cfg), subscriptionId: subscriptionId)
            }
        }

        // 4. Replace percent-encoded @ (%40)
        if !authorityPart.contains("@") && authorityPart.contains("%40") {
            authorityPart = authorityPart.replacingOccurrences(of: "%40", with: "@")
        }

        var uuid = ""
        var hostPortStr = ""

        if let atIndex = authorityPart.firstIndex(of: "@") {
            let rawUser = String(authorityPart[..<atIndex]).trimmingCharacters(in: .whitespaces)
            // Handle Shadowrocket / Xray format: "none:UUID" or "UUID:password" or plain "UUID"
            if rawUser.contains(":") {
                let parts = rawUser.components(separatedBy: ":")
                if parts.count >= 2 {
                    if parts[0].lowercased() == "none" || parts[0].lowercased() == "zero" {
                        uuid = parts[1]
                    } else if UUID(uuidString: parts[0]) != nil {
                        uuid = parts[0]
                    } else if UUID(uuidString: parts[1]) != nil {
                        uuid = parts[1]
                    } else {
                        uuid = parts[0]
                    }
                } else {
                    uuid = parts[0]
                }
            } else {
                uuid = rawUser
            }
            uuid = uuid.trimmingCharacters(in: CharacterSet(charactersIn: "{}()[] \t"))
            hostPortStr = String(authorityPart[authorityPart.index(after: atIndex)...])
        } else {
            // No '@' found: check query parameters ?uuid= or ?id=
            hostPortStr = authorityPart
            let qParams = parseQueryParams(queryStr)
            if let qUUID = qParams["uuid"] ?? qParams["id"], !qUUID.isEmpty {
                uuid = qUUID.trimmingCharacters(in: CharacterSet(charactersIn: "{}()[] \t"))
            }
        }

        guard !uuid.isEmpty else {
            throw SubscriptionParseError.missingUUID(authorityPart)
        }

        let (host, port) = try parseHostAndPort(hostPortStr)
        let queryParams = parseQueryParams(queryStr)

        // Shadowrocket & sing-box query mappings:
        // xtls=2 -> xtls-rprx-vision, xtls=1 -> xtls-rprx-direct
        let xtlsParam = queryParams["xtls"]?.lowercased()
        let flow: String?
        if xtlsParam == "2" || xtlsParam == "vision" {
            flow = "xtls-rprx-vision"
        } else if xtlsParam == "1" || xtlsParam == "direct" {
            flow = "xtls-rprx-direct"
        } else {
            flow = queryParams["flow"]
        }

        // SNI mapping: peer (Shadowrocket), sni, servername
        let sni = queryParams["peer"] ?? queryParams["sni"] ?? queryParams["servername"]

        // Reality parameters
        let publicKey = queryParams["pbk"] ?? queryParams["publickey"]
        let shortId = queryParams["sid"] ?? queryParams["shortid"]
        let fingerprint = queryParams["fp"] ?? "chrome"

        // Security mapping: if pbk is present -> reality; else if tls=1 or security=tls -> tls
        let security: String
        if let pbk = publicKey, !pbk.isEmpty {
            security = "reality"
        } else if queryParams["tls"] == "1" || queryParams["security"]?.lowercased() == "tls" {
            security = "tls"
        } else {
            security = (queryParams["security"] ?? "none").lowercased()
        }

        let network = (queryParams["type"] ?? queryParams["obfs"] ?? queryParams["network"] ?? "tcp").lowercased()
        let wsPath = queryParams["path"]?.removingPercentEncoding ?? queryParams["path"]
        let grpcServiceName = queryParams["servicename"] ?? queryParams["service_name"]

        var wsHeaders: [String: String]? = nil
        if let wsHost = queryParams["host"] ?? sni {
            wsHeaders = ["Host": wsHost]
        }

        let config = VLESSConfig(
            uuid: uuid,
            address: host,
            port: port,
            flow: flow,
            security: security,
            sni: sni,
            publicKey: publicKey,
            shortId: shortId,
            fingerprint: fingerprint,
            network: network,
            wsPath: wsPath,
            wsHeaders: wsHeaders,
            grpcServiceName: grpcServiceName
        )

        // Remark: prefer queryParams["remarks"] (Shadowrocket) or rawRemark (#...) or host:port
        let remarkFromQuery = queryParams["remarks"]?.removingPercentEncoding ?? queryParams["remarks"]
        let finalRemark: String
        if !rawRemark.isEmpty {
            finalRemark = rawRemark
        } else if let rQuery = remarkFromQuery, !rQuery.isEmpty {
            finalRemark = rQuery
        } else {
            finalRemark = "\(host):\(port)"
        }

        return ServerNode(
            name: finalRemark,
            configuration: .vless(config),
            subscriptionId: subscriptionId
        )
    }

    // MARK: - Vortex Proprietary Parser

    /// Parses `vortex://<secret>@<host>:<port>?mode=<mode>&<extraParams>#<Remark>`
    private static func parseVortex(afterSchemeRaw: String, rawRemark: String, subscriptionId: UUID?) throws -> ServerNode {
        var content = afterSchemeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        while content.hasPrefix("/") { content.removeFirst() }
        if !content.contains("@") && content.contains("%40") {
            content = content.replacingOccurrences(of: "%40", with: "@")
        }

        guard let atIndex = content.firstIndex(of: "@") else {
            throw SubscriptionParseError.missingUUID("Отсутствует секретный ключ в vortex://")
        }

        let secret = String(content[..<atIndex]).trimmingCharacters(in: .whitespaces)
        let remaining = String(content[content.index(after: atIndex)...])

        let hostPortAndQuery = remaining.components(separatedBy: "?")
        let hostPortStr = hostPortAndQuery[0]
        let queryStr = hostPortAndQuery.count > 1 ? hostPortAndQuery.dropFirst().joined(separator: "?") : ""

        let (host, port) = try parseHostAndPort(hostPortStr)
        var queryParams = parseQueryParams(queryStr)

        let mode = queryParams.removeValue(forKey: "mode") ?? "udp-mask"

        let config = ProprietaryConfig(
            address: host,
            port: port,
            secretKey: secret,
            obfuscationMode: mode,
            extraParams: queryParams
        )

        let nodeName = rawRemark.isEmpty ? "Vortex \(host):\(port)" : rawRemark

        return ServerNode(
            name: nodeName,
            configuration: .proprietary(config),
            subscriptionId: subscriptionId
        )
    }

    // MARK: - VK Call Tunnel Parser

    /// Parses `vkcall://<call_id>@<relay_host>:<port>?key=<secret>&vk_link=<encoded_url>#<Remark>`
    private static func parseVKCall(afterSchemeRaw: String, rawRemark: String, subscriptionId: UUID?) throws -> ServerNode {
        var content = afterSchemeRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        while content.hasPrefix("/") { content.removeFirst() }
        if !content.contains("@") && content.contains("%40") {
            content = content.replacingOccurrences(of: "%40", with: "@")
        }

        guard let atIndex = content.firstIndex(of: "@") else {
            throw SubscriptionParseError.missingUUID("Отсутствует идентификатор звонка в vkcall://")
        }

        let callId = String(content[..<atIndex]).trimmingCharacters(in: .whitespaces)
        let remaining = String(content[content.index(after: atIndex)...])

        let hostPortAndQuery = remaining.components(separatedBy: "?")
        let hostPortStr = hostPortAndQuery[0]
        let queryStr = hostPortAndQuery.count > 1 ? hostPortAndQuery.dropFirst().joined(separator: "?") : ""

        let (relayHost, relayPort) = try parseHostAndPort(hostPortStr)
        let queryParams = parseQueryParams(queryStr)

        let secretKey = queryParams["key"] ?? queryParams["secret"]
        let rawVkLink = queryParams["vk_link"] ?? queryParams["call_link"]
        let callJoinLink = rawVkLink?.removingPercentEncoding ?? "https://vk.com/call/join/\(callId)"

        var turnCreds: TurnCredentials? = nil
        if let username = queryParams["turn_user"], let password = queryParams["turn_pass"] {
            turnCreds = TurnCredentials(username: username, password: password)
        }

        let config = VKCallConfig(
            callJoinLink: callJoinLink,
            relayAddress: relayHost,
            relayPort: relayPort,
            turnCredentials: turnCreds,
            secretKey: secretKey
        )

        let nodeName = rawRemark.isEmpty ? "VK Call Relay \(relayHost):\(relayPort)" : rawRemark

        return ServerNode(
            name: nodeName,
            configuration: .vkCall(config),
            subscriptionId: subscriptionId
        )
    }

    // MARK: - Subscription Content Parser (Multi-Node & Base64)

    /// Parses raw subscription response body (which can be Base64-encoded or plain text multi-line)
    public static func parseSubscriptionContent(_ rawContent: String, subscriptionId: UUID? = nil) throws -> [ServerNode] {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SubscriptionParseError.emptySubscription
        }

        // Try decoding as Base64 first
        var decodedText: String? = nil
        if let base64Decoded = decodeBase64Flexible(trimmed) {
            // Check if the decoded payload actually contains valid protocol schemes
            if base64Decoded.contains("://") {
                decodedText = base64Decoded
            }
        }

        // If Base64 decoding did not yield protocols, fallback to interpreting the content as plain text
        let contentToParse = decodedText ?? trimmed

        let lines = contentToParse.components(separatedBy: CharacterSet.newlines)
        var parsedNodes: [ServerNode] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            // Skip commented out lines
            if line.hasPrefix("#") || line.hasPrefix("//") { continue }

            do {
                let node = try parseNode(from: line, subscriptionId: subscriptionId)
                parsedNodes.append(node)
            } catch {
                // Silently skip non-node lines or log if needed
                continue
            }
        }

        guard !parsedNodes.isEmpty else {
            throw SubscriptionParseError.emptySubscription
        }

        return parsedNodes
    }

    // MARK: - Flexible Base64 Decoding

    /// Decodes Base64 or URL-Safe Base64, automatically adding missing padding
    public static func decodeBase64Flexible(_ input: String) -> String? {
        var base64 = input
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Re-add padding '=' if needed
        let rem = base64.count % 4
        if rem > 0 {
            base64.append(String(repeating: "=", count: 4 - rem))
        }

        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else {
            return nil
        }

        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii)
    }

    // MARK: - Helper Utilities

    private static func parseHostAndPort(_ hostPortStr: String) throws -> (host: String, port: Int) {
        let trimmed = hostPortStr.trimmingCharacters(in: .whitespaces)

        // Check for IPv6 bracket notation [2001:db8::1]:443
        if trimmed.hasPrefix("[") {
            guard let closeBracket = trimmed.firstIndex(of: "]") else {
                throw SubscriptionParseError.invalidURL("Некорректный IPv6 адрес: \(hostPortStr)")
            }
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
            let afterBracket = String(trimmed[trimmed.index(after: closeBracket)...])
            if afterBracket.hasPrefix(":") {
                let portStr = String(afterBracket.dropFirst())
                let port = Int(portStr) ?? 443
                return (host, port)
            } else {
                return (host, 443)
            }
        }

        // Standard host:port
        let parts = trimmed.components(separatedBy: ":")
        if parts.count == 2 {
            let host = parts[0]
            guard !host.isEmpty else {
                throw SubscriptionParseError.missingHost(hostPortStr)
            }
            let port = Int(parts[1]) ?? 443
            return (host, port)
        } else if parts.count == 1 {
            let host = parts[0]
            guard !host.isEmpty else {
                throw SubscriptionParseError.missingHost(hostPortStr)
            }
            return (host, 443)
        } else {
            throw SubscriptionParseError.invalidURL("Неверный формат хоста и порта: \(hostPortStr)")
        }
    }

    private static func parseQueryParams(_ queryStr: String) -> [String: String] {
        var params: [String: String] = [:]
        guard !queryStr.isEmpty else { return params }

        let pairs = queryStr.components(separatedBy: "&")
        for pair in pairs {
            let kv = pair.components(separatedBy: "=")
            guard !kv.isEmpty else { continue }
            let key = kv[0].lowercased().trimmingCharacters(in: .whitespaces)
            let val = kv.count > 1 ? kv[1].removingPercentEncoding ?? kv[1] : ""
            if !key.isEmpty {
                params[key] = val
            }
        }
        return params
    }
}

// MARK: - Subscription Remote Fetcher

/// Asynchronous network fetcher for remote subscriptions
public actor SubscriptionFetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: config)
    }

    /// Fetches a subscription from URL, parses `Subscription-Userinfo` header and returns nodes
    public func fetch(from url: URL, subscriptionId: UUID = UUID()) async throws -> (userInfo: SubscriptionUserInfo?, nodes: [ServerNode]) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Use realistic User-Agent so subscription providers do not reject the client
        request.setValue("Vortex/1.0 (iOS; Shadowrocket-Compatible)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/plain, application/octet-stream, */*", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SubscriptionParseError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SubscriptionParseError.networkError("HTTP status code: \(httpResponse.statusCode)")
        }

        // Parse Subscription-Userinfo header (case-insensitive lookup)
        var userInfo: SubscriptionUserInfo? = nil
        for (key, val) in httpResponse.allHeaderFields {
            if let keyStr = key as? String,
               keyStr.caseInsensitiveCompare("Subscription-Userinfo") == .orderedSame,
               let valStr = val as? String {
                userInfo = SubscriptionUserInfo(headerValue: valStr)
                break
            }
        }

        // Decode content string
        guard let contentString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw SubscriptionParseError.decodingFailed("Не удалось преобразовать байты ответа в текст")
        }

        let nodes = try SubscriptionParser.parseSubscriptionContent(contentString, subscriptionId: subscriptionId)

        return (userInfo, nodes)
    }
}

import Foundation

/// Parsed metadata from `Subscription-Userinfo` HTTP response header
public struct SubscriptionUserInfo: Codable, Hashable, Sendable {
    public var upload: Int64
    public var download: Int64
    public var total: Int64
    public var expire: Int64?

    public init(upload: Int64, download: Int64, total: Int64, expire: Int64? = nil) {
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }

    /// Parses a standard `Subscription-Userinfo` header value:
    /// e.g. `upload=533512396; download=30472392704; total=107374182400; expire=1735689600`
    public init?(headerValue: String) {
        var upload: Int64 = 0
        var download: Int64 = 0
        var total: Int64 = 0
        var expire: Int64? = nil
        var foundAny = false

        let pairs = headerValue.components(separatedBy: ";")
        for rawPair in pairs {
            let pair = rawPair.trimmingCharacters(in: .whitespacesAndNewlines)
            let kv = pair.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let valStr = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)

            if let val = Int64(valStr) {
                switch key {
                case "upload":
                    upload = val
                    foundAny = true
                case "download":
                    download = val
                    foundAny = true
                case "total":
                    total = val
                    foundAny = true
                case "expire":
                    expire = (val > 0) ? val : nil
                    foundAny = true
                default:
                    break
                }
            }
        }

        guard foundAny else { return nil }
        self.upload = upload
        self.download = download
        self.total = total
        self.expire = expire
    }
}

/// Remote Subscription Group containing servers and quota metadata
public struct SubscriptionGroup: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var uploadBytes: Int64
    public var downloadBytes: Int64
    public var totalBytes: Int64
    public var expireTimestamp: Int64?
    public var lastUpdated: Date?
    public var nodes: [ServerNode]

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL,
        uploadBytes: Int64 = 0,
        downloadBytes: Int64 = 0,
        totalBytes: Int64 = 0,
        expireTimestamp: Int64? = nil,
        lastUpdated: Date? = nil,
        nodes: [ServerNode] = []
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.uploadBytes = uploadBytes
        self.downloadBytes = downloadBytes
        self.totalBytes = totalBytes
        self.expireTimestamp = expireTimestamp
        self.lastUpdated = lastUpdated
        self.nodes = nodes
    }

    // MARK: - Quota & Traffic Calculations

    public var usedBytes: Int64 {
        return uploadBytes + downloadBytes
    }

    public var remainingBytes: Int64? {
        guard totalBytes > 0 else { return nil }
        let rem = totalBytes - usedBytes
        return rem >= 0 ? rem : 0
    }

    /// Formatted traffic line matching Shadowrocket style:
    /// e.g. "↑:508.8M, ↓:28.38G, TOT:0.00K, EXPIRE:∞" or with formatted expire date
    public var trafficSummary: String {
        let upStr = Self.formatBytes(uploadBytes)
        let downStr = Self.formatBytes(downloadBytes)
        let totalStr = (totalBytes > 0) ? Self.formatBytes(totalBytes) : "0.00K"

        let expireStr: String
        if let expire = expireTimestamp, expire > 0 {
            let expireDate = Date(timeIntervalSince1970: TimeInterval(expire))
            let formatter = DateFormatter()
            formatter.dateFormat = "dd.MM.yyyy"
            expireStr = formatter.string(from: expireDate)
        } else {
            expireStr = "∞"
        }

        return "↑:\(upStr), ↓:\(downStr), TOT:\(totalStr), EXPIRE:\(expireStr)"
    }

    /// Update quota info from SubscriptionUserInfo
    public mutating func updateUserInfo(_ info: SubscriptionUserInfo) {
        self.uploadBytes = info.upload
        self.downloadBytes = info.download
        self.totalBytes = info.total
        self.expireTimestamp = info.expire
    }

    /// Helper to format raw byte values into compact units (B, K, M, G, T)
    public static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0.00B" }

        let doubleBytes = Double(bytes)
        let kb: Double = 1024
        let mb: Double = kb * 1024
        let gb: Double = mb * 1024
        let tb: Double = gb * 1024

        if doubleBytes >= tb {
            return String(format: "%.2fT", doubleBytes / tb)
        } else if doubleBytes >= gb {
            return String(format: "%.2fG", doubleBytes / gb)
        } else if doubleBytes >= mb {
            if doubleBytes >= mb * 100 {
                return String(format: "%.1fM", doubleBytes / mb)
            } else {
                return String(format: "%.2fM", doubleBytes / mb)
            }
        } else if doubleBytes >= kb {
            return String(format: "%.2fK", doubleBytes / kb)
        } else {
            return "\(bytes)B"
        }
    }
}

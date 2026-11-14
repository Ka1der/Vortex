import Foundation

/// Coordinates loading, validation, and remote updating of binary Sing-box Rule Sets (.srs)
public enum RuleSetManager {

    public struct RuleSetInfo: Sendable {
        public let tag: String
        public let filename: String
        public let targetURL: URL
        public let remoteURL: URL

        public var exists: Bool {
            FileManager.default.fileExists(atPath: targetURL.path)
        }
    }

    public static let standardRuleSets: [RuleSetInfo] = [
        RuleSetInfo(
            tag: "geoip-ru",
            filename: "geoip-ru.srs",
            targetURL: AppGroup.geoipRuURL,
            remoteURL: URL(string: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs")!
        ),
        RuleSetInfo(
            tag: "geosite-ru",
            filename: "geosite-category-ru.srs",
            targetURL: AppGroup.geositeRuURL,
            remoteURL: URL(string: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs")!
        ),
        RuleSetInfo(
            tag: "geosite-ads",
            filename: "geosite-category-ads-all.srs",
            targetURL: AppGroup.geositeAdsURL,
            remoteURL: URL(string: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs")!
        )
    ]

    /// Ensures all standard rule-set (.srs) files are present in the App Group rules directory.
    /// If not present, copies from Bundle resources or downloads.
    public static func setupRuleSets() {
        let fileManager = FileManager.default

        // Ensure directory exists
        _ = AppGroup.rulesDirectoryURL

        for info in standardRuleSets {
            if !info.exists {
                // Try copying from main app bundle or resource subdirectories
                if let bundleURL = Bundle.main.url(forResource: (info.filename as NSString).deletingPathExtension, withExtension: "srs") {
                    try? fileManager.copyItem(at: bundleURL, to: info.targetURL)
                } else if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(info.filename), fileManager.fileExists(atPath: resourceURL.path) {
                    try? fileManager.copyItem(at: resourceURL, to: info.targetURL)
                } else if let nestedURL = Bundle.main.resourceURL?.appendingPathComponent("RuleSets/\(info.filename)"), fileManager.fileExists(atPath: nestedURL.path) {
                    try? fileManager.copyItem(at: nestedURL, to: info.targetURL)
                } else if let sharedURL = Bundle.main.resourceURL?.appendingPathComponent("Shared/Resources/RuleSets/\(info.filename)"), fileManager.fileExists(atPath: sharedURL.path) {
                    try? fileManager.copyItem(at: sharedURL, to: info.targetURL)
                }
            }
        }
    }

    /// Checks if a specific rule-set tag has an existing valid .srs binary file on disk
    public static func isRuleSetAvailable(tag: String) -> Bool {
        if let info = standardRuleSets.first(where: { $0.tag == tag }) {
            return info.exists
        }
        let customFile = AppGroup.rulesDirectoryURL.appendingPathComponent("\(tag).srs")
        return FileManager.default.fileExists(atPath: customFile.path)
    }

    /// Returns the absolute path for a rule-set if it exists on disk, or nil if missing
    public static func path(for tag: String) -> String? {
        if let info = standardRuleSets.first(where: { $0.tag == tag }), info.exists {
            return info.targetURL.path
        }
        let customFile = AppGroup.rulesDirectoryURL.appendingPathComponent("\(tag).srs")
        if FileManager.default.fileExists(atPath: customFile.path) {
            return customFile.path
        }
        return nil
    }

    /// Asynchronously downloads and refreshes all standard rule-set binaries from remote repository
    public static func updateRuleSets() async throws {
        let session = URLSession.shared
        let fileManager = FileManager.default

        for info in standardRuleSets {
            let (tempURL, response) = try await session.download(from: info.remoteURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                continue
            }

            // Verify binary signature (first 3 bytes must be "SRS")
            let handle = try FileHandle(forReadingFrom: tempURL)
            let header = handle.readData(ofLength: 3)
            try? handle.close()

            guard header == Data([0x53, 0x52, 0x53]) else {
                continue // Corrupted or invalid .srs file, skip overwrite
            }

            // Atomic move into destination
            if fileManager.fileExists(atPath: info.targetURL.path) {
                _ = try? fileManager.removeItem(at: info.targetURL)
            }
            try fileManager.moveItem(at: tempURL, to: info.targetURL)
        }
    }
}

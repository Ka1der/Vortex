import Foundation
import Observation

/// Service managing binary Sing-box Rule Sets (.srs) inside the App Group container.
/// Supports bundled initialization, atomic updates with fallback mirrors, SRS binary validation,
/// and scheduled/background auto-refresh.
@Observable
@MainActor
public final class RuleSetManager {

    public static let shared = RuleSetManager()

    /// Descriptor for a standard Rule Set
    public struct RuleSetItem: Sendable {
        public let tag: String
        public let filename: String
        public let targetURL: URL
        public let primaryURL: URL
        public let mirrorURLs: [URL]

        public var exists: Bool {
            FileManager.default.fileExists(atPath: targetURL.path)
        }
    }

    /// Default list of production rule sets used by Vortex
    nonisolated public static let standardRuleSets: [RuleSetItem] = [
        RuleSetItem(
            tag: "geoip-ru",
            filename: "geoip-ru.srs",
            targetURL: AppGroup.geoipRuURL,
            primaryURL: URL(string: "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs")!,
            mirrorURLs: [
                URL(string: "https://fastly.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-ru.srs")!,
                URL(string: "https://mirror.ghproxy.com/https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs")!
            ]
        ),
        RuleSetItem(
            tag: "geosite-ru",
            filename: "geosite-category-ru.srs",
            targetURL: AppGroup.geositeRuURL,
            primaryURL: URL(string: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs")!,
            mirrorURLs: [
                URL(string: "https://fastly.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-category-ru.srs")!,
                URL(string: "https://mirror.ghproxy.com/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs")!
            ]
        ),
        RuleSetItem(
            tag: "geosite-ads",
            filename: "geosite-category-ads-all.srs",
            targetURL: AppGroup.geositeAdsURL,
            primaryURL: URL(string: "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs")!,
            mirrorURLs: [
                URL(string: "https://fastly.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-category-ads-all.srs")!,
                URL(string: "https://mirror.ghproxy.com/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs")!
            ]
        )
    ]

    /// Default update interval: 7 days in seconds (604,800 sec)
    public static let defaultUpdateInterval: TimeInterval = 7 * 24 * 3600

    // MARK: - Observable UI State

    public private(set) var isUpdating: Bool = false
    public private(set) var lastUpdateDate: Date?
    public private(set) var lastErrorMessage: String?
    public private(set) var fileSizes: [String: Int64] = [:]

    /// Callback invoked when rule-sets have been updated and a reload of active tunnel is requested
    public var onRuleSetsReloadRequested: (() async -> Void)?

    /// Whether automatic background rule-set updates are enabled
    public var autoUpdateRuleSets: Bool {
        didSet {
            AppGroup.userDefaults.set(autoUpdateRuleSets, forKey: AppGroup.Keys.autoUpdateRuleSets)
        }
    }

    /// Interval between automatic updates in seconds
    public var updateInterval: TimeInterval {
        didSet {
            AppGroup.userDefaults.set(updateInterval, forKey: AppGroup.Keys.ruleSetUpdateInterval)
        }
    }

    // MARK: - Lifecycle

    public init() {
        let defaults = AppGroup.userDefaults
        let autoUpdate = defaults.object(forKey: AppGroup.Keys.autoUpdateRuleSets) as? Bool ?? true
        let interval = defaults.double(forKey: AppGroup.Keys.ruleSetUpdateInterval)
        self.autoUpdateRuleSets = autoUpdate
        self.updateInterval = interval > 0 ? interval : Self.defaultUpdateInterval

        if let timestamp = defaults.object(forKey: AppGroup.Keys.lastRuleSetUpdateDate) as? Date {
            self.lastUpdateDate = timestamp
        } else if let timeDouble = defaults.object(forKey: AppGroup.Keys.lastRuleSetUpdateDate) as? Double, timeDouble > 0 {
            self.lastUpdateDate = Date(timeIntervalSince1970: timeDouble)
        }

        if let storedSizes = defaults.dictionary(forKey: AppGroup.Keys.ruleSetFileSizes) as? [String: Int64] {
            self.fileSizes = storedSizes
        } else {
            self.refreshFileSizes()
        }
    }

    // MARK: - 1. App Group Initialization (Bundled Rules)

    /// Ensures bundled .srs files are copied into <AppGroup>/RuleSets/ if not present
    public func ensureBundledRulesCopied() {
        let fileManager = FileManager.default
        _ = AppGroup.rulesDirectoryURL

        // Migration check from legacy rules/ directory
        let legacyRulesDir = AppGroup.containerURL.appendingPathComponent("rules", isDirectory: true)

        for item in Self.standardRuleSets {
            if !item.exists || !Self.validateSRSFile(at: item.targetURL) {
                let legacyFile = legacyRulesDir.appendingPathComponent(item.filename)
                if fileManager.fileExists(atPath: legacyFile.path) && Self.validateSRSFile(at: legacyFile) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: legacyFile, to: item.targetURL)
                } else if let bundleURL = Bundle.main.url(forResource: (item.filename as NSString).deletingPathExtension, withExtension: "srs"),
                          Self.validateSRSFile(at: bundleURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: bundleURL, to: item.targetURL)
                } else if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(item.filename),
                          fileManager.fileExists(atPath: resourceURL.path),
                          Self.validateSRSFile(at: resourceURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: resourceURL, to: item.targetURL)
                } else if let nestedURL = Bundle.main.resourceURL?.appendingPathComponent("RuleSets/\(item.filename)"),
                          fileManager.fileExists(atPath: nestedURL.path),
                          Self.validateSRSFile(at: nestedURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: nestedURL, to: item.targetURL)
                } else if let sharedURL = Bundle.main.resourceURL?.appendingPathComponent("Shared/Resources/RuleSets/\(item.filename)"),
                          fileManager.fileExists(atPath: sharedURL.path),
                          Self.validateSRSFile(at: sharedURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: sharedURL, to: item.targetURL)
                }
            }
        }

        refreshFileSizes()
    }

    /// Backwards compatible static seeding helper for background threads or tunnel start
    nonisolated public static func setupRuleSets() {
        let fileManager = FileManager.default
        _ = AppGroup.rulesDirectoryURL

        let legacyRulesDir = AppGroup.containerURL.appendingPathComponent("rules", isDirectory: true)

        for item in standardRuleSets {
            if !item.exists || !validateSRSFile(at: item.targetURL) {
                let legacyFile = legacyRulesDir.appendingPathComponent(item.filename)
                if fileManager.fileExists(atPath: legacyFile.path) && validateSRSFile(at: legacyFile) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: legacyFile, to: item.targetURL)
                } else if let bundleURL = Bundle.main.url(forResource: (item.filename as NSString).deletingPathExtension, withExtension: "srs"),
                          validateSRSFile(at: bundleURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: bundleURL, to: item.targetURL)
                } else if let resourceURL = Bundle.main.resourceURL?.appendingPathComponent(item.filename),
                          fileManager.fileExists(atPath: resourceURL.path),
                          validateSRSFile(at: resourceURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: resourceURL, to: item.targetURL)
                } else if let nestedURL = Bundle.main.resourceURL?.appendingPathComponent("RuleSets/\(item.filename)"),
                          fileManager.fileExists(atPath: nestedURL.path),
                          validateSRSFile(at: nestedURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: nestedURL, to: item.targetURL)
                } else if let sharedURL = Bundle.main.resourceURL?.appendingPathComponent("Shared/Resources/RuleSets/\(item.filename)"),
                          fileManager.fileExists(atPath: sharedURL.path),
                          validateSRSFile(at: sharedURL) {
                    _ = try? fileManager.removeItem(at: item.targetURL)
                    try? fileManager.copyItem(at: sharedURL, to: item.targetURL)
                }
            }
        }
    }

    // MARK: - 2. Compatibility Validation

    /// Validates that a file exceeds 512 bytes and starts with the "SRS" magic binary signature [0x53, 0x52, 0x53]
    nonisolated public static func validateSRSFile(at fileURL: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? Int64,
              size > 512 else {
            return false
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { try? handle.close() }

        let magic = handle.readData(ofLength: 3)
        return magic == Data([0x53, 0x52, 0x53]) // ASCII "SRS"
    }

    /// Instance validation wrapper
    public func validateSRSFile(at fileURL: URL) -> Bool {
        return Self.validateSRSFile(at: fileURL)
    }

    // MARK: - 3. Manual Update

    /// Downloads the latest .srs binary rule-sets with fallback mirrors, validates integrity, and atomically swaps files
    @discardableResult
    public func updateAllRuleSets(force: Bool = false) async -> Bool {
        guard !isUpdating else { return false }
        isUpdating = true
        lastErrorMessage = nil
        defer { isUpdating = false }

        var anyUpdated = false
        var allSucceeded = true

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)

        for item in Self.standardRuleSets {
            var downloadSuccess = false
            let candidateURLs = [item.primaryURL] + item.mirrorURLs

            for url in candidateURLs {
                do {
                    let (tempDownloadedURL, response) = try await session.download(from: url)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        try? FileManager.default.removeItem(at: tempDownloadedURL)
                        continue
                    }

                    if Self.validateSRSFile(at: tempDownloadedURL) {
                        let destURL = item.targetURL
                        let tempDestURL = destURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".tmp")

                        try FileManager.default.moveItem(at: tempDownloadedURL, to: tempDestURL)
                        if FileManager.default.fileExists(atPath: destURL.path) {
                            _ = try? FileManager.default.removeItem(at: destURL)
                        }
                        try FileManager.default.moveItem(at: tempDestURL, to: destURL)

                        downloadSuccess = true
                        anyUpdated = true
                        break
                    } else {
                        try? FileManager.default.removeItem(at: tempDownloadedURL)
                    }
                } catch {
                    continue
                }
            }

            if !downloadSuccess {
                allSucceeded = false
            }
        }

        refreshFileSizes()

        if anyUpdated || allSucceeded {
            let now = Date()
            self.lastUpdateDate = now
            AppGroup.userDefaults.set(now, forKey: AppGroup.Keys.lastRuleSetUpdateDate)
            AppGroup.userDefaults.set(self.fileSizes, forKey: AppGroup.Keys.ruleSetFileSizes)

            // If tunnel reload callback is registered, notify it
            if let onRuleSetsReloadRequested {
                await onRuleSetsReloadRequested()
            }
            return true
        } else {
            self.lastErrorMessage = "Не удалось обновить базы правил: серверы недоступны"
            return false
        }
    }

    // MARK: - 4. Automatic Background Update

    /// Checks elapsed time since last update and performs background refresh if elapsed time exceeds interval
    public func checkAndAutoUpdateIfNeeded() async {
        guard autoUpdateRuleSets else { return }

        let last = lastUpdateDate ?? .distantPast
        let elapsed = Date().timeIntervalSince(last)

        if elapsed >= updateInterval {
            _ = await updateAllRuleSets(force: false)
        }
    }

    // MARK: - Helpers

    /// Checks if a specific rule-set tag has an existing valid .srs binary file on disk
    nonisolated public static func isRuleSetAvailable(tag: String) -> Bool {
        if let item = standardRuleSets.first(where: { $0.tag == tag }) {
            return item.exists && validateSRSFile(at: item.targetURL)
        }
        let customFile = AppGroup.rulesDirectoryURL.appendingPathComponent("\(tag).srs")
        return FileManager.default.fileExists(atPath: customFile.path) && validateSRSFile(at: customFile)
    }

    /// Returns the absolute path for a rule-set if it exists on disk, or nil if missing
    nonisolated public static func path(for tag: String) -> String? {
        if let item = standardRuleSets.first(where: { $0.tag == tag }), item.exists && validateSRSFile(at: item.targetURL) {
            return item.targetURL.path
        }
        let customFile = AppGroup.rulesDirectoryURL.appendingPathComponent("\(tag).srs")
        if FileManager.default.fileExists(atPath: customFile.path) && validateSRSFile(at: customFile) {
            return customFile.path
        }
        return nil
    }

    /// Refreshes local cached file sizes from disk
    public func refreshFileSizes() {
        var sizes: [String: Int64] = [:]
        for item in Self.standardRuleSets {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: item.targetURL.path),
               let size = attrs[.size] as? Int64 {
                sizes[item.tag] = size
            }
        }
        self.fileSizes = sizes
    }
}

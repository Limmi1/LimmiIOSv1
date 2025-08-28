//
//  DAMSharedTypes.swift
//  DAM (DeviceActivity Extension)
//
//  Purpose: Minimal shared types for DeviceActivityMonitor extension communication
//  Dependencies: Foundation only (no Firebase dependencies)
//  Related: SharedActiveRuleData.swift (main app), ShieldHeartbeatMonitor.swift
//

import Foundation
import ManagedSettings
import FamilyControls

/// Lightweight version of BlockedTokenInfo for extension use.
///
/// This structure contains only the essential information needed by the
/// DeviceActivityMonitor extension to apply blocking. It avoids Firebase
/// dependencies and complex validation logic.
struct DAMBlockedTokenInfo: Codable {
    /// Firebase document ID for reference.
    let tokenId: String
    
    /// Type of token: "application", "webDomain", or "activityCategory".
    let tokenType: String
    
    /// Base64 encoded Screen Time token data.
    let tokenData: String
    
    /// App bundle identifier (for applications only).
    let bundleIdentifier: String?
    
    /// Display name for debugging.
    let displayName: String
    
    // MARK: - Screen Time Token Decoding
    
    /// Decodes the token data as an ApplicationToken.
    func decodedApplicationToken() -> ApplicationToken? {
        guard tokenType == "application",
              let data = Data(base64Encoded: tokenData) else { return nil }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(ApplicationToken.self, from: data)
    }
    
    /// Decodes the token data as a WebDomainToken.
    func decodedWebDomainToken() -> WebDomainToken? {
        guard tokenType == "webDomain",
              let data = Data(base64Encoded: tokenData) else { return nil }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(WebDomainToken.self, from: data)
    }
    
    /// Decodes the token data as an ActivityCategoryToken.
    func decodedActivityCategoryToken() -> ActivityCategoryToken? {
        guard tokenType == "activityCategory",
              let data = Data(base64Encoded: tokenData) else { return nil }
        
        let decoder = JSONDecoder()
        return try? decoder.decode(ActivityCategoryToken.self, from: data)
    }
}

/// Minimal shared data structure for DeviceActivityMonitor extension communication.
///
/// This structure contains only the essential data needed by the extension
/// to apply rule-based blocking. It avoids complex dependencies and focuses
/// on performance and reliability within extension constraints.
struct DAMSharedActiveRuleData: Codable {
    /// Essential token information from active rules.
    let activeRuleTokens: [DAMBlockedTokenInfo]
    
    /// Timestamp when this data was last updated.
    let lastUpdated: Date
    
    /// Schema version for future compatibility.
    let schemaVersion: Int
    
    /// Current schema version.
    static let currentSchemaVersion = 1
    
    // MARK: - Initialization
    
    init(
        activeRuleTokens: [DAMBlockedTokenInfo],
        lastUpdated: Date = Date(),
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.activeRuleTokens = activeRuleTokens
        self.lastUpdated = lastUpdated
        self.schemaVersion = schemaVersion
    }
    
    // MARK: - Computed Properties
    
    /// Returns tokens filtered by type.
    var applicationTokens: [DAMBlockedTokenInfo] {
        activeRuleTokens.filter { $0.tokenType == "application" }
    }
    
    /// Returns web domain tokens.
    var webDomainTokens: [DAMBlockedTokenInfo] {
        activeRuleTokens.filter { $0.tokenType == "webDomain" }
    }
    
    /// Returns activity category tokens.
    var activityCategoryTokens: [DAMBlockedTokenInfo] {
        activeRuleTokens.filter { $0.tokenType == "activityCategory" }
    }
    
    /// Total number of tokens.
    var totalTokenCount: Int {
        activeRuleTokens.count
    }
    
    /// Whether there are any tokens to block.
    var hasTokens: Bool {
        !activeRuleTokens.isEmpty
    }
    
    /// Age of this data in seconds.
    var ageInSeconds: TimeInterval {
        Date().timeIntervalSince(lastUpdated)
    }
    
    // MARK: - Validation
    
    /// Basic validation for extension use.
    func isValid() -> Bool {
        schemaVersion > 0 && lastUpdated.timeIntervalSince1970 > 0
    }
    
    /// Checks if data is fresh enough for use.
    func isFresh(maxAgeSeconds: TimeInterval = 3600) -> Bool {
        ageInSeconds <= maxAgeSeconds
    }
    
    /// Concise description for logging.
    var shortDescription: String {
        "\(totalTokenCount) tokens from active rules (age: \(String(format: "%.0f", ageInSeconds))s)"
    }
}

/// Minimal shared data manager for DeviceActivityMonitor extension.
///
/// This class provides essential data communication functionality without
/// complex dependencies. It focuses on reliability and performance within
/// extension constraints.
final class DAMSharedDataManager {
    
    // MARK: - Configuration
    
    private static let appGroupIdentifier = "group.com.ah.limmi.shareddata"
    private static let activeRuleDataFileName = "activeRuleTokens.json"
    
    // MARK: - Properties
    
    private static let fileManager = FileManager.default
    private static let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
    
    private static let sharedContainerURL: URL? = {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }()
    
    private static let activeRuleDataFileURL: URL? = {
        sharedContainerURL?.appendingPathComponent(activeRuleDataFileName)
    }()
    
    // MARK: - Public API
    
    /// Saves active rule data to shared storage.
    ///
    /// Uses JSON file storage with UserDefaults fallback for reliability.
    ///
    /// - Parameter data: DAMSharedActiveRuleData to save
    /// - Returns: True if successfully saved
    @discardableResult
    static func saveActiveRuleData(_ data: DAMSharedActiveRuleData) -> Bool {
        // Primary storage: JSON file
        if saveToFile(data) {
            return true
        }
        
        // Fallback storage: UserDefaults
        return saveToUserDefaults(data)
    }
    
    /// Loads active rule data from shared storage.
    /// 
    /// This method attempts to load from JSON file first, then falls back
    /// to UserDefaults. It handles decoding errors gracefully.
    ///
    /// - Returns: DAMSharedActiveRuleData if available and valid, nil otherwise
    static func loadActiveRuleData() -> DAMSharedActiveRuleData? {
        // Try loading from file first
        if let data = loadFromFile() {
            return data
        }
        
        // Fallback to UserDefaults
        return loadFromUserDefaults()
    }
    
    // MARK: - Private Implementation
    
    private static func saveToFile(_ data: DAMSharedActiveRuleData) -> Bool {
        guard let fileURL = activeRuleDataFileURL else {
            return false
        }
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            try jsonData.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
    
    private static func saveToUserDefaults(_ data: DAMSharedActiveRuleData) -> Bool {
        guard let defaults = sharedDefaults else {
            return false
        }
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            defaults.set(jsonData, forKey: "activeRuleData")
            return defaults.synchronize()
        } catch {
            return false
        }
    }
    
    private static func loadFromFile() -> DAMSharedActiveRuleData? {
        guard let fileURL = activeRuleDataFileURL,
              fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let data = try JSONDecoder().decode(DAMSharedActiveRuleData.self, from: jsonData)
            return data.isValid() ? data : nil
        } catch {
            return nil
        }
    }
    
    private static func loadFromUserDefaults() -> DAMSharedActiveRuleData? {
        guard let defaults = sharedDefaults,
              let jsonData = defaults.data(forKey: "activeRuleData") else {
            return nil
        }
        
        do {
            let data = try JSONDecoder().decode(DAMSharedActiveRuleData.self, from: jsonData)
            return data.isValid() ? data : nil
        } catch {
            return nil
        }
    }
}

/// Core blocking utility specifically designed for DeviceActivityMonitor extension.
///
/// This utility provides essential ManagedSettings blocking functionality
/// optimized for extension constraints. It avoids complex dependencies
/// and focuses on performance and reliability.
final class DAMCoreBlockingUtility {
    
    // MARK: - Properties
    
    private let store: ManagedSettingsStore
    private let storeName: String
    
    // MARK: - Initialization
    
    init(storeName: String = "Default") {
        self.storeName = storeName
        if storeName == "Default" {
            self.store = ManagedSettingsStore()
        } else {
            self.store = ManagedSettingsStore(named: ManagedSettingsStore.Name(storeName))
        }
    }
    
    // MARK: - Blocking Operations
    
    /// Applies blocking for the specified Screen Time tokens.
    ///
    /// - Parameters:
    ///   - apps: Set of ApplicationToken objects to block (nil to leave unchanged)
    ///   - webDomains: Set of WebDomainToken objects to block (nil to leave unchanged)
    ///   - categories: Set of ActivityCategoryToken objects to block (nil to leave unchanged)
    func applyBlocking(
        apps: Set<ApplicationToken>? = nil,
        webDomains: Set<WebDomainToken>? = nil,
        categories: Set<ActivityCategoryToken>? = nil
    ) {
        // Apply application blocking (nil means leave unchanged, empty set means clear all)
        if let apps = apps {
            store.shield.applications = apps.isEmpty ? nil : apps
        }
        
        // Apply web domain blocking (nil means leave unchanged, empty set means clear all)
        if let webDomains = webDomains {
            store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        }
        
        // Apply activity category blocking (nil means leave unchanged, empty set means clear all)
        if let categories = categories {
            if !categories.isEmpty {
                store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(categories)
                store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.specific(categories)
            } else {
                store.shield.applicationCategories = nil
                store.shield.webDomainCategories = nil
            }
        }
    }
    
    /// Applies complete blocking state, ensuring all restrictions are set explicitly.
    ///
    /// Unlike the selective applyBlocking method, this method always sets all three
    /// restriction types, ensuring a complete and consistent blocking state.
    ///
    /// - Parameters:
    ///   - applications: Application tokens to block (empty set clears blocking)
    ///   - webDomains: Web domain tokens to block (empty set clears blocking)
    ///   - activityCategories: Activity category tokens to block (empty set clears blocking)
    func setCompleteBlockingState(
        applications: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        activityCategories: Set<ActivityCategoryToken>
    ) {
        // Always set all three types to ensure consistent state
        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        
        if !activityCategories.isEmpty {
            store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(activityCategories)
            store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.specific(activityCategories)
        } else {
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        }
    }
    
    /// Applies blocking based on DAM token information.
    ///
    /// Converts DAM token info to Screen Time tokens and applies complete blocking state.
    /// This ensures all blocking types are set consistently.
    func applyBlocking(tokens: [DAMBlockedTokenInfo]) {
        var applicationTokens: Set<ApplicationToken> = []
        var webDomainTokens: Set<WebDomainToken> = []
        var activityCategoryTokens: Set<ActivityCategoryToken> = []
        
        for token in tokens {
            switch token.tokenType {
            case "application":
                if let appToken = token.decodedApplicationToken() {
                    applicationTokens.insert(appToken)
                }
            case "webDomain":
                if let webToken = token.decodedWebDomainToken() {
                    webDomainTokens.insert(webToken)
                }
            case "activityCategory":
                if let categoryToken = token.decodedActivityCategoryToken() {
                    activityCategoryTokens.insert(categoryToken)
                }
            default:
                break
            }
        }
        
        setCompleteBlockingState(
            applications: applicationTokens,
            webDomains: webDomainTokens,
            activityCategories: activityCategoryTokens
        )
    }
    
    /// Applies blocking from shared active rule data.
    func applyActiveRuleBlocking(from sharedData: DAMSharedActiveRuleData) {
        guard sharedData.isValid() && sharedData.hasTokens else {
            clearAllBlocking()
            return
        }
        
        applyBlocking(tokens: sharedData.activeRuleTokens)
    }
    
    /// Clears all blocking restrictions.
    func clearAllBlocking() {
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
    }
    
    /// Returns description for debugging.
    var currentStateDescription: String {
        "DAMCoreBlockingUtility(store: \(storeName))"
    }
}

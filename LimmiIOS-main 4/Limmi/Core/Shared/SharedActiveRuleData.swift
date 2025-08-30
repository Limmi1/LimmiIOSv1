//
//  SharedActiveRuleData.swift
//  Limmi
//
//  Purpose: Data structure for communicating active rule tokens between main app and DeviceActivityMonitor extension
//  Dependencies: Foundation, existing BlockedTokenInfo
//  Related: SharedDataManager.swift, ShieldHeartbeatMonitor.swift
//

import Foundation

/// Data structure for sharing active rule tokens between main app and DeviceActivityMonitor extension.
///
/// This structure contains all tokens from currently active rules, regardless of whether
/// they are currently being blocked by the main app. The DeviceActivityMonitor extension
/// uses this data to provide "safety net" blocking when the main app is unavailable.
///
/// ## Key Concepts
/// - **Active Rule Tokens**: ALL tokens referenced in rules that are currently active
/// - **Currently Blocked Tokens**: Subset of active tokens actually blocked based on current context
/// - **Extension Behavior**: Blocks ALL active rule tokens for comprehensive coverage
///
/// ## Data Flow
/// 1. Main app determines which rules are active (based on Firebase data)
/// 2. Extracts all tokens from those active rules
/// 3. Saves to App Group container via SharedDataManager
/// 4. Extension loads and applies broad blocking for all tokens
///
/// - Since: 1.0
struct SharedActiveRuleData: Codable {
    
    /// All blocked token information from currently active rules.
    /// Includes applications, web domains, and activity categories.
    let activeRuleTokens: [BlockedTokenInfo]
    
    /// Timestamp when this data was last updated.
    /// Used for cache validation and debugging.
    let lastUpdated: Date
    
    /// Schema version for future data format evolution.
    /// Allows for backward compatibility handling.
    let schemaVersion: Int
    
    /// Current schema version constant.
    static let currentSchemaVersion = 1
    
    // MARK: - Initialization
    
    /// Creates a new SharedActiveRuleData instance.
    ///
    /// - Parameters:
    ///   - activeRuleTokens: Array of BlockedTokenInfo from active rules
    ///   - lastUpdated: Timestamp of last update (defaults to current time)
    ///   - schemaVersion: Data format version (defaults to current version)
    init(
        activeRuleTokens: [BlockedTokenInfo],
        lastUpdated: Date = Date(),
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.activeRuleTokens = activeRuleTokens
        self.lastUpdated = lastUpdated
        self.schemaVersion = schemaVersion
    }
    
    // MARK: - Computed Properties
    
    /// Returns tokens filtered by type for easier processing.
    var applicationTokens: [BlockedTokenInfo] {
        activeRuleTokens.filter { $0.tokenType == "application" }
    }
    
    /// Returns web domain tokens from active rules.
    var webDomainTokens: [BlockedTokenInfo] {
        activeRuleTokens.filter { $0.tokenType == "webDomain" }
    }
    
    /// Returns activity category tokens from active rules.
    var activityCategoryTokens: [BlockedTokenInfo] {
        activeRuleTokens.filter { $0.tokenType == "activityCategory" }
    }
    
    /// Returns the total number of tokens from active rules.
    var totalTokenCount: Int {
        activeRuleTokens.count
    }
    
    /// Indicates whether there are any tokens to potentially block.
    var hasTokens: Bool {
        !activeRuleTokens.isEmpty
    }
    
    /// Returns age of this data in seconds.
    var ageInSeconds: TimeInterval {
        Date().timeIntervalSince(lastUpdated)
    }
    
    // MARK: - Validation
    
    /// Validates the data structure and its contents.
    ///
    /// Checks for:
    /// - Non-empty token array
    /// - Valid schema version
    /// - Reasonable last updated timestamp
    /// - Valid token data within each BlockedTokenInfo
    ///
    /// - Returns: True if data appears valid and usable
    func isValid() -> Bool {
        // Check basic structure
        guard schemaVersion > 0,
              lastUpdated.timeIntervalSince1970 > 0,
              !activeRuleTokens.isEmpty else {
            return false
        }
        
        // Check that tokens themselves are valid
        return activeRuleTokens.allSatisfy { $0.isValid() }
    }
    
    /// Checks if this data is reasonably fresh for extension use.
    ///
    /// Extensions should prefer recent data to avoid applying outdated blocking rules.
    /// Data older than this threshold may indicate the main app hasn't been running.
    ///
    /// - Parameter maxAgeSeconds: Maximum acceptable age in seconds (default: 1 hour)
    /// - Returns: True if data is fresh enough for reliable use
    func isFresh(maxAgeSeconds: TimeInterval = 3600) -> Bool {
        ageInSeconds <= maxAgeSeconds
    }
    
    // MARK: - Debugging
    
    /// Returns a detailed description for debugging purposes.
    var debugDescription: String {
        let appCount = applicationTokens.count
        let webCount = webDomainTokens.count
        let categoryCount = activityCategoryTokens.count
        
        return """
        SharedActiveRuleData:
        - Total tokens: \(totalTokenCount)
        - Applications: \(appCount)
        - Web domains: \(webCount)
        - Activity categories: \(categoryCount)
        - Last updated: \(lastUpdated)
        - Age: \(String(format: "%.1f", ageInSeconds))s
        - Schema version: \(schemaVersion)
        - Is valid: \(isValid())
        - Is fresh: \(isFresh())
        """
    }
    
    /// Returns a concise summary for logging.
    var shortDescription: String {
        "\(totalTokenCount) tokens from active rules (age: \(String(format: "%.0f", ageInSeconds))s)"
    }
}

// MARK: - Equatable

extension SharedActiveRuleData: Equatable {
    /// Compares two SharedActiveRuleData instances for equality.
    ///
    /// Two instances are considered equal if they contain the same tokens
    /// (order independent) and have the same schema version.
    /// LastUpdated timestamp is ignored for equality comparison.
    static func == (lhs: SharedActiveRuleData, rhs: SharedActiveRuleData) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion &&
        lhs.activeRuleTokens.count == rhs.activeRuleTokens.count &&
        Set(lhs.activeRuleTokens.compactMap { $0.id }) == Set(rhs.activeRuleTokens.compactMap { $0.id })
    }
}

// MARK: - Convenience Factory Methods

extension SharedActiveRuleData {
    /// Creates an empty SharedActiveRuleData instance.
    ///
    /// Useful for initializing or clearing shared state.
    static func empty() -> SharedActiveRuleData {
        SharedActiveRuleData(activeRuleTokens: [])
    }
    
    /// Creates SharedActiveRuleData from a collection of rules.
    ///
    /// Extracts all blocked token IDs from the provided rules and looks them up
    /// in the token store to create the complete BlockedTokenInfo array.
    ///
    /// - Parameters:
    ///   - rules: Array of active Rule objects
    ///   - tokenStore: Dictionary mapping token IDs to BlockedTokenInfo
    /// - Returns: SharedActiveRuleData containing all tokens from active rules
    static func from(
        activeRules rules: [Rule],
        tokenStore: [String: BlockedTokenInfo]
    ) -> SharedActiveRuleData {
        let allTokenIds = rules.flatMap { $0.blockedTokenIds }
        let tokens = allTokenIds.compactMap { tokenStore[$0] }
        
        return SharedActiveRuleData(activeRuleTokens: tokens)
    }
}
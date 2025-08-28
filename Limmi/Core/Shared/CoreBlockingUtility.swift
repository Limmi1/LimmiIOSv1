//
//  CoreBlockingUtility.swift
//  Limmi
//
//  Purpose: Lightweight, reusable core blocking functionality using ManagedSettings
//  Dependencies: ManagedSettings, FamilyControls, Foundation
//  Related: ScreenTimeBlocker.swift, ShieldHeartbeatMonitor.swift
//

import Foundation
import ManagedSettings
import FamilyControls
import os

/// Lightweight utility for core Screen Time blocking operations.
///
/// This class extracts the essential ManagedSettings blocking logic from ScreenTimeBlocker
/// to provide a shared implementation that can be used in both the main app and extensions.
/// It removes complex dependencies like @MainActor, Combine publishers, and Firebase integration
/// to make it suitable for extension environments.
///
/// ## Key Features
/// - Thread-safe operations (no @MainActor requirement)
/// - Minimal memory footprint for extension use
/// - Direct ManagedSettings API integration
/// - Named store support for avoiding conflicts
/// - Fast, synchronous operations
///
/// ## Store Separation
/// Different contexts should use different store names to prevent conflicts:
/// - Main app: "MainApp" or default store
/// - DeviceActivityMonitor heartbeat: "HeartbeatShield"
/// - DeviceActivityMonitor rules: "RuleBasedShield"
///
/// - Since: 1.0
final class CoreBlockingUtility {
    
    // MARK: - Properties
    
    /// ManagedSettings store for applying blocking restrictions.
    private let store: ManagedSettingsStore
    
    /// Store name for debugging and identification.
    private let storeName: String
    
    /// Logger for debugging blocking operations.
    private let logger: Logger
    
    // MARK: - Initialization
    
    /// Creates a new CoreBlockingUtility with the specified store name.
    ///
    /// - Parameter storeName: Unique identifier for this blocking context.
    ///                       Use different names to prevent conflicts between different blocking systems.
    init(storeName: String) {
        self.storeName = storeName
        self.store = ManagedSettingsStore(named: ManagedSettingsStore.Name(storeName))
        self.logger = Logger(subsystem: "com.limmi.core", category: "CoreBlockingUtility-\(storeName)")
        
        logger.debug("CoreBlockingUtility initialized with store: \(storeName)")
    }
    
    /// Creates a new CoreBlockingUtility using the default ManagedSettings store.
    ///
    /// Use this initializer for the main app context where you want to use
    /// the system's default store.
    convenience init() {
        self.init(storeName: "Default")
        
        logger.debug("CoreBlockingUtility initialized with default store")
    }
    
    // MARK: - Core Blocking Operations
    
    /// Applies blocking restrictions for the specified token types.
    ///
    /// This method mirrors the core blocking logic from ScreenTimeBlocker but
    /// removes the complex state management and dependency requirements.
    ///
    /// - Parameters:
    ///   - apps: Set of ApplicationToken objects to block (nil to leave unchanged)
    ///   - webDomains: Set of WebDomainToken objects to block (nil to leave unchanged)
    ///   - categories: Set of ActivityCategoryToken objects to block (nil to leave unchanged)
    func applyBlocking(
        apps: Set<ApplicationToken>? = [],
        webDomains: Set<WebDomainToken>? = [],
        categories: Set<ActivityCategoryToken>? = []
    ) {
        logger.debug("Applying blocking - apps: \(apps?.count ?? -1), web: \(webDomains?.count ?? -1), categories: \(categories?.count ?? -1)")
        
        // Apply application blocking (nil means leave unchanged, empty set means clear all)
        if let apps = apps {
            store.shield.applications = apps.isEmpty ? nil : apps
            //logger.debug("Applied application blocking to \(apps.count) apps")
        }
        
        // Apply web domain blocking (nil means leave unchanged, empty set means clear all)
        if let webDomains = webDomains {
            store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
            //logger.debug("Applied web domain blocking to \(webDomains.count) domains")
        }
        
        // Apply activity category blocking (nil means leave unchanged, empty set means clear all)
        if let categories = categories {
            if !categories.isEmpty {
                store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.specific(categories)
                store.shield.webDomainCategories = ShieldSettings.ActivityCategoryPolicy.specific(categories)
                //logger.debug("Applied activity category blocking to \(categories.count) categories")
            } else {
                store.shield.applicationCategories = nil
                store.shield.webDomainCategories = nil
                //logger.debug("Cleared activity category blocking")
            }
        }
        
        //logger.debug("Blocking application completed successfully")
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
        logger.debug("Setting complete blocking state - apps: \(applications.count), web: \(webDomains.count), categories: \(activityCategories.count)")
        
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
        
        logger.debug("Complete blocking state applied successfully")
    }
    
    /// Applies blocking for all specified Screen Time tokens.
    ///
    /// Convenience method that applies blocking for applications, web domains,
    /// and activity categories in a single call. This ensures all blocking
    /// types are set consistently.
    ///
    /// - Parameters:
    ///   - applications: Application tokens to block
    ///   - webDomains: Web domain tokens to block  
    ///   - activityCategories: Activity category tokens to block
    func applyBlocking(
        applications: Set<ApplicationToken>,
        webDomains: Set<WebDomainToken>,
        activityCategories: Set<ActivityCategoryToken>
    ) {
        setCompleteBlockingState(
            applications: applications,
            webDomains: webDomains,
            activityCategories: activityCategories
        )
    }
    
    /// Applies blocking based on BlockedTokenInfo objects.
    ///
    /// Converts BlockedTokenInfo objects to their corresponding Screen Time tokens
    /// and applies blocking. Invalid tokens are ignored with warnings.
    ///
    /// - Parameter tokens: Array of BlockedTokenInfo to block
    func applyBlocking(tokens: [BlockedTokenInfo]) {
        logger.debug("Converting \(tokens.count) BlockedTokenInfo objects to Screen Time tokens")
        
        var applicationTokens: Set<ApplicationToken> = []
        var webDomainTokens: Set<WebDomainToken> = []
        var activityCategoryTokens: Set<ActivityCategoryToken> = []
        
        for token in tokens {
            switch token.tokenType {
            case "application":
                if let appToken = token.decodedApplicationToken() {
                    applicationTokens.insert(appToken)
                } else {
                    logger.warning("Failed to decode application token: \(token.displayName)")
                }
                
            case "webDomain":
                if let webToken = token.decodedWebDomainToken() {
                    webDomainTokens.insert(webToken)
                } else {
                    logger.warning("Failed to decode web domain token: \(token.displayName)")
                }
                
            case "activityCategory":
                if let categoryToken = token.decodedActivityCategoryToken() {
                    activityCategoryTokens.insert(categoryToken)
                } else {
                    logger.warning("Failed to decode activity category token: \(token.displayName)")
                }
                
            default:
                logger.warning("Unknown token type: \(token.tokenType) for token: \(token.displayName)")
            }
        }
        
        logger.debug("Converted tokens - apps: \(applicationTokens.count), web: \(webDomainTokens.count), categories: \(activityCategoryTokens.count)")
        
        // Apply the blocking
        applyBlocking(
            applications: applicationTokens,
            webDomains: webDomainTokens,
            activityCategories: activityCategoryTokens
        )
    }
    
    /// Removes all blocking restrictions managed by this utility.
    ///
    /// Clears all application, web domain, and activity category restrictions
    /// from this utility's ManagedSettings store.
    func clearAllBlocking() {
        logger.debug("Clearing all blocking restrictions")
        
        store.shield.applications = nil
        store.shield.webDomains = nil
        store.shield.applicationCategories = nil
        store.shield.webDomainCategories = nil
        
        logger.debug("All blocking restrictions cleared")
    }
    
    /// Removes blocking for specific applications.
    ///
    /// - Parameter applications: Application tokens to unblock
    func removeApplicationBlocking(_ applications: Set<ApplicationToken>) {
        logger.debug("Removing application blocking for \(applications.count) apps")
        
        // Note: ManagedSettings doesn't support partial removal, so this would require
        // maintaining current state and setting the difference. For now, we log the limitation.
        logger.warning("Partial application unblocking not implemented - use clearAllBlocking() and reapply desired restrictions")
    }
    
    // MARK: - State Inspection
    
    /// Returns basic information about the current blocking state.
    ///
    /// Note: ManagedSettings doesn't provide direct query capabilities,
    /// so this returns store identification information rather than actual restrictions.
    var currentStateDescription: String {
        "CoreBlockingUtility(store: \(storeName))"
    }
    
    // MARK: - Debugging
    
    /// Returns detailed debug information about this blocking utility.
    func getDebugInfo() -> String {
        return """
        CoreBlockingUtility Debug Info:
        - Store name: \(storeName)
        - Subsystem: com.limmi.core
        - Category: CoreBlockingUtility-\(storeName)
        """
    }
}

// MARK: - Convenience Extensions

extension CoreBlockingUtility {
    /// Factory method for creating main app blocking utility.
    static func forMainApp() -> CoreBlockingUtility {
        CoreBlockingUtility(storeName: "MainApp")
    }
    
    /// Factory method for creating DeviceActivityMonitor heartbeat blocking utility.
    static func forHeartbeatShield() -> CoreBlockingUtility {
        CoreBlockingUtility(storeName: "HeartbeatShield")
    }
    
    /// Factory method for creating DeviceActivityMonitor rule-based blocking utility.
    static func forRuleBasedShield() -> CoreBlockingUtility {
        CoreBlockingUtility(storeName: "RuleBasedShield")
    }
}

// MARK: - Error Handling

/// Errors that can occur during core blocking operations.
enum CoreBlockingError: LocalizedError {
    case invalidToken(String)
    case blockingFailed(String)
    case storeNotAvailable
    
    var errorDescription: String? {
        switch self {
        case .invalidToken(let tokenName):
            return "Invalid or corrupted token: \(tokenName)"
        case .blockingFailed(let reason):
            return "Blocking operation failed: \(reason)"
        case .storeNotAvailable:
            return "ManagedSettings store is not available"
        }
    }
}

// MARK: - Shared Extensions

extension CoreBlockingUtility {
    /// Convenience method for applying blocking from SharedActiveRuleData.
    ///
    /// This method is specifically designed for DeviceActivityMonitor extension use
    /// where it needs to apply broad blocking based on shared active rule data.
    ///
    /// - Parameter sharedData: Active rule data from main app
    func applyActiveRuleBlocking(from sharedData: SharedActiveRuleData) {
        logger.debug("Applying active rule blocking from shared data: \(sharedData.shortDescription)")
        
        guard sharedData.isValid() else {
            logger.warning("Shared active rule data is invalid, skipping blocking")
            return
        }
        
        guard sharedData.hasTokens else {
            logger.debug("No tokens in shared data, clearing blocking")
            clearAllBlocking()
            return
        }
        
        // Apply blocking for all active rule tokens
        applyBlocking(tokens: sharedData.activeRuleTokens)
        
        logger.debug("Successfully applied active rule blocking")
    }
}

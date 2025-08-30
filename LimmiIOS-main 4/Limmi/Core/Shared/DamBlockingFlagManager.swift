//
//  DamBlockingFlagManager.swift
//  Limmi
//
//  Purpose: Manages DAM blocking status flag using shared file in App Group container
//  Dependencies: Foundation only (lightweight for all targets)
//  Targets: Main app, DAM extension, Shield extension
//

import Foundation
import os

/// Manages a simple flag indicating when DAM extension is responsible for app blocking.
///
/// This flag is used to coordinate between the main app and DAM extension:
/// - DAM extension sets the flag when it takes over blocking responsibilities
/// - Main app clears the flag when it launches/becomes active
/// - All targets can check the flag status
///
/// ## Thread Safety
/// All operations are thread-safe using NSFileCoordinator for file access.
///
/// ## Implementation
/// Uses file presence/absence for maximum simplicity and reliability.
/// No complex data structures or JSON parsing required.
///
/// ## Usage
/// ```swift
/// // DAM extension sets flag when taking over
/// DamBlockingFlagManager.setFlag()
///
/// // Main app clears flag on launch/foreground
/// DamBlockingFlagManager.clearFlag()
///
/// // Any target can check status
/// let damIsBlocking = DamBlockingFlagManager.isFlagSet()
/// ```
struct DamBlockingFlagManager {
    
    // MARK: - Configuration
    
    /// App Group identifier shared between all targets
    private static let appGroupIdentifier = "group.com.ah.limmi.shareddata"
    
    /// Name of the flag file in App Group container
    private static let flagFileName = "dam_blocking_active.flag"
    
    
    // MARK: - Private Properties
    
    /// File manager instance for file operations
    private static let fileManager = FileManager.default
    
    /// Unified logger for both file and system logging
    private static let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "DamBlockingFlag")
    )
    
    /// Computed URL for the flag file in App Group container
    private static var flagFileURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(flagFileName)
    }
    
    // MARK: - Public API
    
    /// Sets the DAM blocking flag to indicate DAM extension is handling app blocking.
    ///
    /// Creates the flag file in App Group container with timestamp content.
    /// This should be called by the DAM extension when it takes over blocking responsibilities.
    ///
    /// - Returns: True if flag was set successfully
    @discardableResult
    static func setFlag() -> Bool {
        logger.debug("Setting DAM blocking flag")
        
        guard let flagURL = flagFileURL else {
            logger.error("App Group container URL is nil")
            return false
        }
        
        do {
            let timestamp = Date().timeIntervalSince1970
            try "\(timestamp)\n".write(to: flagURL, atomically: true, encoding: .utf8)
            logger.debug("DAM blocking flag set successfully")
            return true
        } catch {
            logger.error("Failed to set DAM blocking flag: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Clears the DAM blocking flag to indicate main app has resumed blocking control.
    ///
    /// Removes the flag file from App Group container.
    /// This should be called by the main app when it launches or becomes active.
    ///
    /// - Returns: True if flag was cleared successfully (or was already cleared)
    @discardableResult
    static func clearFlag() -> Bool {
        logger.debug("Clearing DAM blocking flag")
        
        guard let flagURL = flagFileURL else {
            logger.error("App Group container URL is nil")
            return false
        }
        
        do {
            if fileManager.fileExists(atPath: flagURL.path) {
                try fileManager.removeItem(at: flagURL)
                logger.debug("DAM blocking flag cleared successfully")
            } else {
                logger.debug("DAM blocking flag already cleared")
            }
            return true
        } catch {
            logger.error("Failed to clear DAM blocking flag: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Checks if the DAM blocking flag is currently set.
    ///
    /// Checks for flag file existence in App Group container.
    /// This can be called by any target to determine if DAM extension is handling blocking.
    ///
    /// - Returns: True if DAM extension is responsible for blocking
    static func isFlagSet() -> Bool {
        guard let flagURL = flagFileURL else {
            logger.error("App Group container URL is nil")
            return false
        }
        
        let flagExists = fileManager.fileExists(atPath: flagURL.path)
        logger.debug("DAM blocking flag is \(flagExists ? "set" : "not set")")
        return flagExists
    }
    
    /// Gets the timestamp when the flag was last set (if available).
    ///
    /// Useful for debugging and monitoring how long DAM has been handling blocking.
    ///
    /// - Returns: Date when flag was set, or nil if flag is not set or timestamp unavailable
    static func getFlagTimestamp() -> Date? {
        guard let flagURL = flagFileURL else {
            return nil
        }
        
        do {
            guard fileManager.fileExists(atPath: flagURL.path) else {
                return nil
            }
            
            let content = try String(contentsOf: flagURL, encoding: .utf8)
            let timestampString = content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let timestampInterval = Double(timestampString) {
                return Date(timeIntervalSince1970: timestampInterval)
            }
        } catch {
            logger.error("Failed to read flag timestamp: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Utility Methods
    
    /// Validates that the App Group container is accessible.
    ///
    /// Useful for debugging setup issues across different targets.
    ///
    /// - Returns: True if App Group container is accessible
    static func validateAppGroupAccess() -> Bool {
        guard let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            logger.error("App Group container URL is nil - check entitlements configuration")
            return false
        }
        
        logger.debug("App Group container path: \(containerURL.path)")
        
        // Test write access
        let testFile = containerURL.appendingPathComponent("dam_flag_access_test.tmp")
        
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            logger.debug("App Group container is accessible for DAM flag operations")
            return true
        } catch {
            logger.error("App Group container access test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Gets debug information about the flag system.
    ///
    /// Useful for troubleshooting and monitoring.
    ///
    /// - Returns: Dictionary with debug information
    static func getDebugInfo() -> [String: Any] {
        let containerURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        let containerPath = containerURL?.path ?? "N/A"
        let flagFilePath = flagFileURL?.path ?? "N/A"
        
        let flagExists = isFlagSet()
        let timestamp = getFlagTimestamp()
        
        return [
            "appGroupIdentifier": appGroupIdentifier,
            "containerPath": containerPath,
            "flagFileName": flagFileName,
            "flagFilePath": flagFilePath,
            "flagExists": flagExists,
            "flagTimestamp": timestamp?.description ?? "N/A",
            "appGroupAccessible": validateAppGroupAccess()
        ]
    }
}
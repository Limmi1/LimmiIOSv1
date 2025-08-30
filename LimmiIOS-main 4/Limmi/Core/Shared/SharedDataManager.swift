//
//  SharedDataManager.swift
//  Limmi
//
//  Purpose: Manages reading/writing of shared data between main app and DeviceActivityMonitor extension
//  Dependencies: Foundation, App Group container access
//  Related: SharedActiveRuleData.swift, ShieldHeartbeatMonitor.swift
//

import Foundation
import os

/// Manages shared data communication between the main app and DeviceActivityMonitor extension.
///
/// This class handles the serialization, storage, and retrieval of active rule data
/// using the App Group container. It provides thread-safe operations and robust
/// error handling for inter-process communication.
///
/// ## App Group Configuration
/// Both the main app and DeviceActivityMonitor extension must be configured with
/// the same App Group identifier in their entitlements files.
///
/// ## Data Storage
/// - Uses JSON serialization for human-readable debugging
/// - Atomic writes to prevent data corruption
/// - Proper file permissions for App Group access
///
/// ## Thread Safety
/// All methods are thread-safe and can be called from any queue.
///
/// - Since: 1.0
final class SharedDataManager {
    
    // MARK: - Configuration
    
    /// App Group identifier shared between main app and extensions.
    /// Must match the identifier configured in entitlements files.
    private static let appGroupIdentifier = "group.com.ah.limmi.shareddata"
    
    /// File name for storing active rule data in the shared container.
    private static let activeRuleDataFileName = "activeRuleTokens.json"
    
    /// UserDefaults suite for shared preferences (alternative storage).
    private static let sharedUserDefaultsKey = "activeRuleData"
    
    // MARK: - Properties
    
    /// Logger for debugging shared data operations.
    private static let logger = Logger(
        subsystem: "com.limmi.shared", 
        category: "SharedDataManager"
    )
    
    /// File manager for container access.
    private static let fileManager = FileManager.default
    
    /// Shared UserDefaults suite for App Group.
    private static let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier)
    
    /// Lazy-computed path to the shared container directory.
    private static let sharedContainerURL: URL? = {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }()
    
    /// Lazy-computed path to the active rule data file.
    private static let activeRuleDataFileURL: URL? = {
        sharedContainerURL?.appendingPathComponent(activeRuleDataFileName)
    }()
    
    // MARK: - Public API
    
    /// Saves active rule data to the shared App Group container.
    ///
    /// Uses JSON serialization and atomic writes to ensure data integrity.
    /// If file-based storage fails, falls back to UserDefaults as a backup.
    ///
    /// - Parameter data: SharedActiveRuleData to save
    /// - Returns: True if successfully saved, false otherwise
    @discardableResult
    static func saveActiveRuleData(_ data: SharedActiveRuleData) -> Bool {
        logger.debug("Attempting to save active rule data with \(data.totalTokenCount) tokens")
        
        // Primary storage: JSON file in App Group container
        if saveToFile(data) {
            logger.debug("Successfully saved active rule data to file")
            return true
        }
        
        // Fallback storage: UserDefaults
        logger.warning("File storage failed, attempting UserDefaults fallback")
        if saveToUserDefaults(data) {
            logger.debug("Successfully saved active rule data to UserDefaults")
            return true
        }
        
        logger.error("Failed to save active rule data to both file and UserDefaults")
        return false
    }
    
    /// Loads active rule data from the shared App Group container.
    ///
    /// Attempts to load from JSON file first, then falls back to UserDefaults.
    /// Validates loaded data before returning.
    ///
    /// - Returns: SharedActiveRuleData if successfully loaded and valid, nil otherwise
    static func loadActiveRuleData() -> SharedActiveRuleData? {
        logger.debug("Attempting to load active rule data")
        
        // Primary storage: JSON file in App Group container
        if let data = loadFromFile() {
            logger.debug("Successfully loaded active rule data from file: \(data.shortDescription)")
            return data
        }
        
        // Fallback storage: UserDefaults
        logger.debug("File loading failed, attempting UserDefaults fallback")
        if let data = loadFromUserDefaults() {
            logger.debug("Successfully loaded active rule data from UserDefaults: \(data.shortDescription)")
            return data
        }
        
        logger.debug("No active rule data found in shared storage")
        return nil
    }
    
    /// Clears all stored active rule data.
    ///
    /// Removes data from both file storage and UserDefaults to ensure
    /// clean state. Useful for testing or resetting shared state.
    ///
    /// - Returns: True if successfully cleared from all storage locations
    @discardableResult
    static func clearActiveRuleData() -> Bool {
        logger.debug("Clearing all active rule data")
        
        let fileCleared = clearFile()
        let defaultsCleared = clearUserDefaults()
        
        let success = fileCleared && defaultsCleared
        logger.debug("Active rule data clearing: file=\(fileCleared), defaults=\(defaultsCleared)")
        
        return success
    }
    
    /// Validates that the App Group container is accessible.
    ///
    /// Useful for debugging shared data issues and ensuring proper
    /// App Group configuration.
    ///
    /// - Returns: True if container is accessible and writable
    static func validateAppGroupAccess() -> Bool {
        guard let containerURL = sharedContainerURL else {
            logger.error("App Group container URL is nil - check entitlements configuration")
            return false
        }
        
        logger.debug("App Group container path: \(containerURL.path)")
        
        // Test write access
        let testFile = containerURL.appendingPathComponent("access_test.tmp")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            logger.debug("App Group container is accessible and writable")
            return true
        } catch {
            logger.error("App Group container access test failed: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - File Storage Implementation
    
    /// Saves data to JSON file in App Group container.
    private static func saveToFile(_ data: SharedActiveRuleData) -> Bool {
        guard let fileURL = activeRuleDataFileURL else {
            logger.error("Active rule data file URL is nil")
            return false
        }
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            try jsonData.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.error("Failed to save active rule data to file: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Loads data from JSON file in App Group container.
    private static func loadFromFile() -> SharedActiveRuleData? {
        guard let fileURL = activeRuleDataFileURL else {
            logger.debug("Active rule data file URL is nil")
            return nil
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.debug("Active rule data file does not exist")
            return nil
        }
        
        do {
            let jsonData = try Data(contentsOf: fileURL)
            let data = try JSONDecoder().decode(SharedActiveRuleData.self, from: jsonData)
            
            // Validate loaded data
            guard data.isValid() else {
                logger.warning("Loaded active rule data is invalid, ignoring")
                return nil
            }
            
            return data
        } catch {
            logger.error("Failed to load active rule data from file: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Clears JSON file storage.
    private static func clearFile() -> Bool {
        guard let fileURL = activeRuleDataFileURL else {
            return true // Nothing to clear
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return true // Already cleared
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            return true
        } catch {
            logger.error("Failed to clear active rule data file: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - UserDefaults Storage Implementation
    
    /// Saves data to shared UserDefaults as fallback.
    private static func saveToUserDefaults(_ data: SharedActiveRuleData) -> Bool {
        guard let defaults = sharedDefaults else {
            logger.error("Shared UserDefaults is nil")
            return false
        }
        
        do {
            let jsonData = try JSONEncoder().encode(data)
            defaults.set(jsonData, forKey: sharedUserDefaultsKey)
            return defaults.synchronize()
        } catch {
            logger.error("Failed to save active rule data to UserDefaults: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Loads data from shared UserDefaults.
    private static func loadFromUserDefaults() -> SharedActiveRuleData? {
        guard let defaults = sharedDefaults else {
            logger.debug("Shared UserDefaults is nil")
            return nil
        }
        
        guard let jsonData = defaults.data(forKey: sharedUserDefaultsKey) else {
            logger.debug("No active rule data found in UserDefaults")
            return nil
        }
        
        do {
            let data = try JSONDecoder().decode(SharedActiveRuleData.self, from: jsonData)
            
            // Validate loaded data
            guard data.isValid() else {
                logger.warning("Active rule data from UserDefaults is invalid, ignoring")
                return nil
            }
            
            return data
        } catch {
            logger.error("Failed to decode active rule data from UserDefaults: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Clears UserDefaults storage.
    private static func clearUserDefaults() -> Bool {
        guard let defaults = sharedDefaults else {
            return true // Nothing to clear
        }
        
        defaults.removeObject(forKey: sharedUserDefaultsKey)
        return defaults.synchronize()
    }
}

// MARK: - Debugging Extensions

extension SharedDataManager {
    /// Returns detailed status information for debugging.
    static func getDebugStatus() -> String {
        let containerPath = sharedContainerURL?.path ?? "N/A"
        let filePath = activeRuleDataFileURL?.path ?? "N/A"
        let hasValidAccess = validateAppGroupAccess()
        let currentData = loadActiveRuleData()
        
        return """
        SharedDataManager Debug Status:
        - App Group ID: \(appGroupIdentifier)
        - Container path: \(containerPath)
        - Data file path: \(filePath)
        - Has valid access: \(hasValidAccess)
        - Current data: \(currentData?.shortDescription ?? "none")
        - Shared UserDefaults available: \(sharedDefaults != nil)
        """
    }
}

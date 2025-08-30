//
//  AppTerminationFlagManager.swift
//  Limmi
//
//  Purpose: Manages app termination flag in shared storage for heartbeat monitoring
//  Dependencies: Foundation
//  Related: AppDelegate.swift, ShieldHeartbeatMonitor.swift
//

import Foundation
import os

/// Manages a shared flag that tracks app termination state.
///
/// This utility helps distinguish between normal app termination and force-quit scenarios
/// by maintaining a flag in the app group that gets set on `applicationWillTerminate`
/// and cleared on app launch.
///
/// ## Usage Pattern
/// 1. Clear termination flag on app launch
/// 2. Set termination flag on `applicationWillTerminate`
/// 3. DAM extension checks flag to determine if app was force-quit
///
/// ## Detection Logic
/// - Flag absent/false = Normal termination or first launch
/// - Flag true = App was force-quit (termination handler never called)
///
/// - Since: 1.0
final class AppTerminationFlagManager {
    
    // MARK: - Constants
    
    /// App group identifier for shared storage
    private static let appGroupIdentifier = "group.com.ah.limmi.shareddata"
    
    /// Key for storing the termination flag
    private static let terminationFlagKey = "appWillTerminateFlag"
    
    /// Key for storing termination timestamp
    private static let terminationTimestampKey = "appTerminationTimestamp"
    
    /// File name for file-based storage
    private static let fileName = "appTerminationFlag.json"
    
    // MARK: - Properties
    
    /// Shared instance for convenient access
    static let shared = AppTerminationFlagManager()
    
    /// Logger for debugging termination flag operations
    private let logger = Logger(subsystem: "com.limmi.core", category: "AppTerminationFlagManager")
    
    // MARK: - Initialization
    
    private init() {
        logger.debug("AppTerminationFlagManager initialized")
    }
    
    // MARK: - Public Methods
    
    /// Clears the termination flag on app launch.
    ///
    /// This should be called during app initialization to indicate that the app
    /// is starting normally and can handle termination events properly.
    func clearTerminationFlag() {
        logger.debug("Clearing app termination flag")
        
        let success = saveTerminationState(isTerminating: false, timestamp: Date())
        
        if success {
            logger.debug("Successfully cleared termination flag")
        } else {
            logger.error("Failed to clear termination flag")
        }
    }
    
    /// Sets the termination flag when `applicationWillTerminate` is called.
    ///
    /// This indicates that the app is about to terminate normally through
    /// the iOS app lifecycle. If this flag is not set and the app stops
    /// running, it indicates a force-quit scenario.
    func setTerminationFlag() {
        logger.debug("Setting app termination flag")
        
        let success = saveTerminationState(isTerminating: true, timestamp: Date())
        
        if success {
            logger.debug("Successfully set termination flag")
        } else {
            logger.error("Failed to set termination flag")
        }
    }
    
    /// Checks if the app was force-quit by examining the termination flag.
    ///
    /// - Returns: AppTerminationStatus indicating the app's termination state
    func getTerminationStatus() -> AppTerminationStatus {
        guard let terminationData = loadTerminationState() else {
            logger.debug("No termination data found - likely first launch")
            return .firstLaunch
        }
        
        let wasTerminating = terminationData["isTerminating"] as? Bool ?? false
        let timestamp = Date(timeIntervalSince1970: terminationData["timestamp"] as? TimeInterval ?? 0)
        
        if wasTerminating {
            logger.debug("App was force-quit - termination flag was set but never cleared")
            return .forceQuit(lastSeen: timestamp)
        } else {
            logger.debug("App terminated normally - termination flag was properly managed")
            return .normalTermination(lastSeen: timestamp)
        }
    }
    
    /// Gets the last known app activity timestamp.
    ///
    /// - Returns: Date of last termination flag update, or nil if not available
    func getLastActivityTimestamp() -> Date? {
        guard let terminationData = loadTerminationState(),
              let timestamp = terminationData["timestamp"] as? TimeInterval else {
            return nil
        }
        
        return Date(timeIntervalSince1970: timestamp)
    }
    
    // MARK: - Private Methods
    
    /// Saves the termination state to shared storage.
    ///
    /// Uses both file-based and UserDefaults storage for redundancy.
    ///
    /// - Parameters:
    ///   - isTerminating: Whether the app is currently terminating
    ///   - timestamp: Timestamp of the state change
    /// - Returns: True if successfully saved
    private func saveTerminationState(isTerminating: Bool, timestamp: Date) -> Bool {
        let terminationData: [String: Any] = [
            "isTerminating": isTerminating,
            "timestamp": timestamp.timeIntervalSince1970,
            "schemaVersion": 1
        ]
        
        var success = false
        
        // Try to save to App Group container file (primary method)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(Self.fileName)
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: terminationData, options: [])
                try jsonData.write(to: fileURL, options: .atomic)
                logger.debug("Saved termination state to App Group file")
                success = true
            } catch {
                logger.error("Failed to save termination state to file: \(error.localizedDescription)")
            }
        }
        
        // Fallback: Save to UserDefaults (for redundancy)
        if let sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: terminationData, options: [])
                sharedDefaults.set(jsonData, forKey: "terminationFlagData")
                
                // Also save individual keys for easier access
                sharedDefaults.set(isTerminating, forKey: Self.terminationFlagKey)
                sharedDefaults.set(timestamp.timeIntervalSince1970, forKey: Self.terminationTimestampKey)
                
                let syncSuccess = sharedDefaults.synchronize()
                logger.debug("Saved termination state to UserDefaults: \(syncSuccess)")
                success = success || syncSuccess
            } catch {
                logger.error("Failed to save termination state to UserDefaults: \(error.localizedDescription)")
            }
        }
        
        return success
    }
    
    /// Loads the termination state from shared storage.
    ///
    /// Tries file-based storage first, then falls back to UserDefaults.
    ///
    /// - Returns: Dictionary containing termination state data, or nil if not found
    private func loadTerminationState() -> [String: Any]? {
        // Try to load from App Group container file (primary method)
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(Self.fileName)
            
            do {
                let jsonData = try Data(contentsOf: fileURL)
                let terminationData = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                logger.debug("Loaded termination state from App Group file")
                return terminationData
            } catch {
                logger.debug("Failed to load termination state from file: \(error.localizedDescription)")
            }
        }
        
        // Fallback: Load from UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) {
            // Try structured data first
            if let jsonData = sharedDefaults.data(forKey: "terminationFlagData") {
                do {
                    let terminationData = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
                    logger.debug("Loaded termination state from UserDefaults (structured)")
                    return terminationData
                } catch {
                    logger.debug("Failed to parse structured termination data: \(error.localizedDescription)")
                }
            }
            
            // Fallback to individual keys
            let isTerminating = sharedDefaults.bool(forKey: Self.terminationFlagKey)
            let timestamp = sharedDefaults.double(forKey: Self.terminationTimestampKey)
            
            if timestamp > 0 {
                logger.debug("Loaded termination state from UserDefaults (individual keys)")
                return [
                    "isTerminating": isTerminating,
                    "timestamp": timestamp,
                    "schemaVersion": 1
                ]
            }
        }
        
        logger.debug("No termination state found in shared storage")
        return nil
    }
}

// MARK: - Supporting Types

/// Represents the app's termination status based on the termination flag.
enum AppTerminationStatus: Equatable {
    /// First app launch, no previous termination data
    case firstLaunch
    
    /// App terminated normally (termination flag was properly cleared)
    case normalTermination(lastSeen: Date)
    
    /// App was force-quit (termination flag was set but never cleared)
    case forceQuit(lastSeen: Date)
    
    /// Human-readable description of the termination status
    var description: String {
        switch self {
        case .firstLaunch:
            return "First launch"
        case .normalTermination(let lastSeen):
            return "Normal termination (last seen: \(lastSeen))"
        case .forceQuit(let lastSeen):
            return "Force quit detected (last seen: \(lastSeen))"
        }
    }
    
    /// Whether the app was force-quit
    var wasForceQuit: Bool {
        switch self {
        case .forceQuit:
            return true
        default:
            return false
        }
    }
    
    /// The last known app activity timestamp, if available
    var lastSeenTimestamp: Date? {
        switch self {
        case .normalTermination(let lastSeen), .forceQuit(let lastSeen):
            return lastSeen
        case .firstLaunch:
            return nil
        }
    }
}
//
//  HeartbeatManager.swift
//  Limmi
//
//  Purpose: Manages app liveness signals for force-quit detection and automatic shield activation
//  Dependencies: Foundation, UnifiedLogger
//  Related: ShieldHeartbeatMonitor.swift, BlockingEngine.swift, LimmiApp.swift
//

import Foundation
import os

/// Manages heartbeat signals to detect app force-quit and coordinate with shield extension.
///
/// This class implements a dual-signal system for detecting when the main Limmi app
/// has been force-quit or killed, enabling the shield extension to automatically
/// re-enable Screen Time blocking to prevent bypassing app restrictions.
///
/// ## Heartbeat System
/// - **Presence File**: `alive.flag` exists only while app is in foreground
/// - **Timestamp**: `lastHeartbeat` updated every 10s and on significant events
/// - **Detection**: Shield extension monitors both signals for staleness
///
/// ## Integration Points
/// - App lifecycle events (foreground/background transitions)
/// - BlockingEngine callbacks (beacon events, rule evaluations)
/// - System events (location updates, push notifications)
///
/// ## Performance
/// - Minimal I/O operations (file touch vs write)
/// - UserDefaults for persistent timestamp storage
/// - Timer-based updates only in foreground
///
/// - Since: 1.0
final class HeartbeatManager: HeartbeatProtocol {
    
    // MARK: - Configuration
    
    /// Interval for foreground heartbeat updates (10 seconds)
    static let foregroundUpdateInterval: TimeInterval = 10.0
    
    /// Maximum age before heartbeat is considered stale (120 seconds)
    static let stalenessThreshold: TimeInterval = 90.0
    
    /// Minimum interval between heartbeat updates (5 seconds) to prevent excessive updates
    static let updateThrottleInterval: TimeInterval = 5.0
    
    /// App Group identifier for shared container access
    private static let appGroupIdentifier = "group.com.ah.limmi.shareddata"
    
    /// UserDefaults key for heartbeat timestamp
    private static let heartbeatKey = "lastHeartbeat"
    
    /// Presence file name in shared container
    private static let aliveFileName = "alive.flag"
    
    // MARK: - Properties
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "HeartbeatManager")
    )
    
    private let fileManager = FileManager.default
    private let sharedDefaults: UserDefaults
    private let appGroupContainer: URL
    private let aliveFilePath: URL
    
    private var foregroundTimer: Timer?
    private var isInForeground = false
    private var lastHeartbeatUpdateTime: TimeInterval = 0
    
    // MARK: - Initialization
    
    /// Initializes the heartbeat manager with shared container access.
    /// 
    /// - Throws: HeartbeatError if App Group container is not accessible
    init() throws {
        guard let sharedDefaults = UserDefaults(suiteName: Self.appGroupIdentifier) else {
            throw HeartbeatError.appGroupNotAccessible
        }
        
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier) else {
            throw HeartbeatError.appGroupNotAccessible
        }
        
        self.sharedDefaults = sharedDefaults
        self.appGroupContainer = container
        self.aliveFilePath = container.appendingPathComponent(Self.aliveFileName)
        
        logger.debug("HeartbeatManager initialized with container: \(container.path)")
    }
    
    // MARK: - Public Methods
    
    /// Starts foreground heartbeat monitoring.
    /// 
    /// Creates the presence file and begins regular heartbeat updates.
    /// Should be called when the app enters the foreground.
    func startForegroundHeartbeat() {
        guard !isInForeground else {
            logger.debug("Foreground heartbeat already active")
            return
        }
        
        isInForeground = true
        createPresenceFile()
        updateHeartbeat()
        startForegroundTimer()
        
        logger.debug("Started foreground heartbeat monitoring")
    }
    
    /// Stops foreground heartbeat monitoring.
    /// 
    /// Removes the presence file and stops regular updates.
    /// Should be called when the app enters the background.
    func stopForegroundHeartbeat() {
        guard isInForeground else {
            logger.debug("Foreground heartbeat already inactive")
            return
        }
        
        isInForeground = false
        removePresenceFile()
        stopForegroundTimer()
        
        // Final heartbeat update before going to background
        updateHeartbeat()
        
        logger.debug("Stopped foreground heartbeat monitoring")
    }
    
    /// Updates the heartbeat timestamp immediately.
    /// 
    /// Can be called from any context (foreground, background, callbacks).
    /// Use this to signal app activity during beacon events, rule evaluations, etc.
    /// Throttles updates to maximum every 5 seconds to prevent excessive writes.
    func updateHeartbeat() {
        let currentTime = Date().timeIntervalSince1970
        
        // Check if enough time has passed since last update (throttling)
        let timeSinceLastUpdate = currentTime - lastHeartbeatUpdateTime
        if timeSinceLastUpdate < Self.updateThrottleInterval {
            // Throttled - skip this update
            return
        }
        
        // Update timestamp and record when we did it
        lastHeartbeatUpdateTime = currentTime
        sharedDefaults.set(currentTime, forKey: Self.heartbeatKey)
        
        // Touch presence file if in foreground
        if isInForeground {
            touchPresenceFile()
        }
        
        logger.debug("Updated heartbeat: \(currentTime)")
    }
    
    /// Performs cleanup and stops all heartbeat activities.
    /// 
    /// Should be called during app termination or deinitialization.
    func cleanup() {
        stopForegroundHeartbeat()
        logger.debug("HeartbeatManager cleanup completed")
    }
    
    // MARK: - Status Methods
    
    /// Returns the current heartbeat timestamp.
    /// 
    /// - Returns: Timestamp of last heartbeat, or nil if never set
    func getCurrentHeartbeat() -> TimeInterval? {
        let timestamp = sharedDefaults.double(forKey: Self.heartbeatKey)
        return timestamp > 0 ? timestamp : nil
    }
    
    /// Returns the age of the current heartbeat in seconds.
    /// 
    /// - Returns: Age in seconds, or nil if no heartbeat exists
    func getHeartbeatAge() -> TimeInterval? {
        guard let timestamp = getCurrentHeartbeat() else { return nil }
        return Date().timeIntervalSince1970 - timestamp
    }
    
    /// Checks if the heartbeat is considered stale.
    /// 
    /// - Returns: True if heartbeat age exceeds staleness threshold
    func isHeartbeatStale() -> Bool {
        guard let age = getHeartbeatAge() else { return true }
        return age > Self.stalenessThreshold
    }
    
    /// Checks if the presence file exists.
    /// 
    /// - Returns: True if alive.flag file exists
    func isPresenceFileActive() -> Bool {
        return fileManager.fileExists(atPath: aliveFilePath.path)
    }
    
    // MARK: - Private Methods - File Operations
    
    /// Creates the presence file to indicate foreground activity.
    private func createPresenceFile() {
        do {
            // Create zero-length file
            try Data().write(to: aliveFilePath)
            logger.debug("Created presence file: \(aliveFilePath.path)")
        } catch {
            logger.error("Failed to create presence file: \(error.localizedDescription)")
        }
    }
    
    /// Updates the modification time of the presence file.
    private func touchPresenceFile() {
        guard fileManager.fileExists(atPath: aliveFilePath.path) else {
            // File doesn't exist, create it
            createPresenceFile()
            return
        }
        
        do {
            let now = Date()
            try fileManager.setAttributes([.modificationDate: now], ofItemAtPath: aliveFilePath.path)
        } catch {
            logger.error("Failed to touch presence file: \(error.localizedDescription)")
        }
    }
    
    /// Removes the presence file when entering background.
    private func removePresenceFile() {
        guard fileManager.fileExists(atPath: aliveFilePath.path) else {
            logger.debug("Presence file already removed")
            return
        }
        
        do {
            try fileManager.removeItem(at: aliveFilePath)
            logger.debug("Removed presence file: \(aliveFilePath.path)")
        } catch {
            logger.error("Failed to remove presence file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods - Timer Management
    
    /// Starts the foreground timer for regular heartbeat updates.
    private func startForegroundTimer() {
        stopForegroundTimer() // Ensure no duplicate timers
        
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: Self.foregroundUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateHeartbeat()
        }
        
        logger.debug("Started foreground timer with interval: \(Self.foregroundUpdateInterval)s")
    }
    
    /// Stops the foreground timer.
    private func stopForegroundTimer() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        logger.debug("Stopped foreground timer")
    }
    
    deinit {
        cleanup()
    }
}

// MARK: - Error Types

/// Errors that can occur during heartbeat operations.
enum HeartbeatError: LocalizedError {
    case appGroupNotAccessible
    case presenceFileError(String)
    case heartbeatUpdateFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .appGroupNotAccessible:
            return "App Group container is not accessible"
        case .presenceFileError(let message):
            return "Presence file error: \(message)"
        case .heartbeatUpdateFailed(let message):
            return "Heartbeat update failed: \(message)"
        }
    }
}

// MARK: - Debugging Extensions

extension HeartbeatManager {
    /// Returns detailed status information for debugging.
    func getDebugStatus() -> HeartbeatDebugStatus {
        return HeartbeatDebugStatus(
            isInForeground: isInForeground,
            currentHeartbeat: getCurrentHeartbeat(),
            heartbeatAge: getHeartbeatAge(),
            isStale: isHeartbeatStale(),
            presenceFileExists: isPresenceFileActive(),
            containerPath: appGroupContainer.path,
            stalenessThreshold: Self.stalenessThreshold
        )
    }
}

/// Debug status information for heartbeat system.
struct HeartbeatDebugStatus {
    let isInForeground: Bool
    let currentHeartbeat: TimeInterval?
    let heartbeatAge: TimeInterval?
    let isStale: Bool
    let presenceFileExists: Bool
    let containerPath: String
    let stalenessThreshold: TimeInterval
    
    var description: String {
        return """
        Heartbeat Debug Status:
        - In foreground: \(isInForeground)
        - Current heartbeat: \(currentHeartbeat?.description ?? "none")
        - Heartbeat age: \(heartbeatAge?.description ?? "none")s
        - Is stale: \(isStale)
        - Presence file exists: \(presenceFileExists)
        - Container path: \(containerPath)
        - Staleness threshold: \(stalenessThreshold)s
        """
    }
}

//
//  HeartbeatProtocol.swift
//  Limmi
//
//  Purpose: Protocol abstraction for heartbeat management with test and production implementations
//  Dependencies: Foundation
//  Related: HeartbeatManager.swift, EventProcessor.swift, BlockingEngine.swift
//

import Foundation

/// Protocol abstraction for managing app liveness signals.
///
/// This protocol provides a clean abstraction for heartbeat operations,
/// enabling dependency injection, testability, and flexibility in heartbeat strategies.
/// Supports both file-based presence signals and timestamp-based staleness detection.
///
/// ## Implementation Strategy
/// - **Production**: HeartbeatManager using App Group container and UserDefaults
/// - **Testing**: TestHeartbeatManager with controllable state
/// - **Future**: Could support additional backends (remote monitoring, analytics)
///
/// ## Lifecycle Management
/// Implementations handle foreground/background transitions and provide
/// immediate activity signals for critical app events.
///
/// ## Thread Safety
/// Implementations should be thread-safe and handle concurrent access
/// from multiple subsystems (lifecycle, event processing, UI updates).
///
/// - Since: 1.0
protocol HeartbeatProtocol {
    /// Starts foreground heartbeat monitoring.
    /// 
    /// Creates presence signals and begins regular heartbeat updates.
    /// Should be called when the app enters the foreground.
    func startForegroundHeartbeat()
    
    /// Stops foreground heartbeat monitoring.
    /// 
    /// Removes presence signals and stops regular updates.
    /// Should be called when the app enters the background.
    func stopForegroundHeartbeat()
    
    /// Updates the heartbeat timestamp immediately.
    /// 
    /// Can be called from any context (foreground, background, callbacks).
    /// Use this to signal app activity during events, rule evaluations, etc.
    func updateHeartbeat()
    
    /// Performs cleanup and stops all heartbeat activities.
    /// 
    /// Should be called during app termination or deinitialization.
    func cleanup()
    
    /// Returns the current heartbeat timestamp.
    /// 
    /// - Returns: Timestamp of last heartbeat, or nil if never set
    func getCurrentHeartbeat() -> TimeInterval?
    
    /// Returns the age of the current heartbeat in seconds.
    /// 
    /// - Returns: Age in seconds, or nil if no heartbeat exists
    func getHeartbeatAge() -> TimeInterval?
    
    /// Checks if the heartbeat is considered stale.
    /// 
    /// - Returns: True if heartbeat age exceeds staleness threshold
    func isHeartbeatStale() -> Bool
    
    /// Checks if the presence file exists.
    /// 
    /// - Returns: True if presence signal is active
    func isPresenceFileActive() -> Bool
}

/// Default implementation providing common functionality
extension HeartbeatProtocol {
    /// Convenience method to check if heartbeat is healthy
    var isHealthy: Bool {
        return !isHeartbeatStale() && isPresenceFileActive()
    }
    
    /// Convenience method to get heartbeat status summary
    var statusSummary: String {
        let age = getHeartbeatAge() ?? -1
        let stale = isHeartbeatStale()
        let present = isPresenceFileActive()
        return "Age: \(String(format: "%.1f", age))s, Stale: \(stale), Present: \(present)"
    }
}

/// Test implementation of HeartbeatProtocol
final class TestHeartbeatManager: HeartbeatProtocol {
    
    // MARK: - Properties
    
    private var isForegroundActive = false
    private var lastHeartbeatTimestamp: TimeInterval?
    private var presenceFileExists = false
    
    /// Configurable staleness threshold for testing
    var stalenessThreshold: TimeInterval = 60.0
    
    /// Controllable time source for testing
    var currentTime: () -> TimeInterval = { Date().timeIntervalSince1970 }
    
    // MARK: - HeartbeatProtocol Implementation
    
    func startForegroundHeartbeat() {
        isForegroundActive = true
        presenceFileExists = true
        updateHeartbeat()
    }
    
    func stopForegroundHeartbeat() {
        isForegroundActive = false
        presenceFileExists = false
        updateHeartbeat()
    }
    
    func updateHeartbeat() {
        lastHeartbeatTimestamp = currentTime()
    }
    
    func cleanup() {
        isForegroundActive = false
        presenceFileExists = false
        lastHeartbeatTimestamp = nil
    }
    
    func getCurrentHeartbeat() -> TimeInterval? {
        return lastHeartbeatTimestamp
    }
    
    func getHeartbeatAge() -> TimeInterval? {
        guard let timestamp = lastHeartbeatTimestamp else { return nil }
        return currentTime() - timestamp
    }
    
    func isHeartbeatStale() -> Bool {
        guard let age = getHeartbeatAge() else { return true }
        return age > stalenessThreshold
    }
    
    func isPresenceFileActive() -> Bool {
        return presenceFileExists
    }
    
    // MARK: - Test Helper Methods
    
    /// Simulates time advancement for testing staleness
    func advanceTime(by seconds: TimeInterval) {
        let baseTime = currentTime()
        currentTime = { baseTime + seconds }
    }
    
    /// Forces heartbeat into stale state for testing
    func forceStaleHeartbeat() {
        if let current = lastHeartbeatTimestamp {
            lastHeartbeatTimestamp = current - (stalenessThreshold + 1)
        }
    }
    
    /// Simulates app crash (presence file remains but heartbeat stops)
    func simulateAppCrash() {
        // Presence file remains but heartbeat stops updating
        presenceFileExists = true
        // Don't update timestamp to simulate freeze
    }
}

/// No-op implementation for scenarios where heartbeat is disabled
final class NoOpHeartbeatManager: HeartbeatProtocol {
    func startForegroundHeartbeat() {}
    func stopForegroundHeartbeat() {}
    func updateHeartbeat() {}
    func cleanup() {}
    func getCurrentHeartbeat() -> TimeInterval? { return nil }
    func getHeartbeatAge() -> TimeInterval? { return nil }
    func isHeartbeatStale() -> Bool { return false }
    func isPresenceFileActive() -> Bool { return false }
}

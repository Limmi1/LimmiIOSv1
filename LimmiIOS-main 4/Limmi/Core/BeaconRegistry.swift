//
//  BeaconRegistry.swift
//  Limmi
//
//  Purpose: Centralized beacon status management for BlockingEngine
//  Dependencies: Foundation, Combine, BeaconStatus, BeaconID, BeaconDevice
//  Related: BlockingEngine.swift, BeaconMonitor.swift, EventProcessor.swift
//

import Foundation
import Combine
import os

/// Centralized registry for managing beacon status within the BlockingEngine
///
/// The BeaconRegistry maintains comprehensive state for all tracked beacons, providing
/// sophisticated rule processing capabilities through real-time status updates and
/// historical analysis. It serves as the single source of truth for beacon information
/// within the blocking engine.
///
/// ## Key Features
/// - **Centralized Status**: Single source of truth for all beacon state
/// - **Real-time Updates**: Processes beacon events and updates status immediately
/// - **Rule Integration**: Provides beacon status for rule evaluation
/// - **Performance Optimized**: Efficient lookup and update operations
/// - **Observable**: SwiftUI-compatible reactive updates
///
/// ## Usage
/// ```swift
/// let registry = BeaconRegistry()
/// registry.registerBeacon(beaconID: id, device: device)
/// registry.processEvent(.beaconDetected(id, rssi: -65))
/// 
/// if registry.isBeaconInRange(id) {
///     // Process beacon-based rules
/// }
/// ```
@MainActor
class BeaconRegistry: ObservableObject {
    
    // MARK: - Published Properties
    
    /// All currently tracked beacon statuses
    @Published private(set) var beaconStatuses: [BeaconID: BeaconStatus] = [:]
    
    /// Beacon IDs that are currently in range (computed from statuses)
    @Published private(set) var beaconsInRange: Set<BeaconID> = []
    
    /// Beacon IDs that are currently in near range (stricter criteria)
    @Published private(set) var beaconsInNearRange: Set<BeaconID> = []
    
    // MARK: - Private Properties
    
    /// Performance monitoring and debugging
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BeaconRegistry")
    )
    
    /// Cleanup timer for removing stale beacon statuses
    //private var cleanupTimer: Timer?
    
    /// Maximum time to retain beacon status after last detection (in seconds)
    //private let maxStaleTime: TimeInterval = 300 // 5 minutes
    
    /// Minimum time between cleanup operations (in seconds)
    //private let cleanupInterval: TimeInterval = 60 // 1 minute
    
    // MARK: - Initialization
    
    init() {
        logger.debug("BeaconRegistry initialized")
        //startCleanupTimer()
    }
    
    deinit {
        //cleanupTimer?.invalidate()
    }
    
    // MARK: - Beacon Registration
    
    /// Register a beacon for tracking
    /// - Parameters:
    ///   - beaconID: Unique identifier for the beacon
    ///   - device: Associated device information from Firebase
    func registerBeacon(beaconID: BeaconID, device: BeaconDevice) {
        if beaconStatuses[beaconID] == nil {
            beaconStatuses[beaconID] = BeaconStatus(beaconID: beaconID, device: device)
            logger.debug("Registered new beacon: \(beaconID.shortDescription)")
        } else {
            // Update device information if it has changed
            beaconStatuses[beaconID]?.device = device
            logger.debug("Updated existing beacon: \(beaconID.shortDescription)")
        }
    }
    
    /// Register multiple beacons from a device list
    /// - Parameter devices: Array of beacon devices to register
    func registerBeacons(from devices: [BeaconDevice]) {
        for device in devices {
            guard let uuid = UUID(uuidString: device.uuid) else {
                logger.error("Invalid UUID for device: \(device.name)")
                continue
            }
            
            let beaconID = BeaconID(
                uuid: uuid,
                major: UInt16(device.major),
                minor: UInt16(device.minor)
            )
            
            registerBeacon(beaconID: beaconID, device: device)
        }
        
        logger.debug("Registered \(devices.count) beacons from device list")
    }
    
    /// Unregister a beacon (removes from tracking)
    /// - Parameter beaconID: Beacon to unregister
    func unregisterBeacon(_ beaconID: BeaconID) {
        beaconStatuses.removeValue(forKey: beaconID)
        beaconsInRange.remove(beaconID)
        beaconsInNearRange.remove(beaconID)
        logger.debug("Unregistered beacon: \(beaconID.shortDescription)")
    }
    
    // MARK: - Event Processing
    
    /// Process a beacon event and update relevant beacon status
    /// - Parameter event: The beacon event to process
    func processEvent(_ event: BeaconEvent) {
        if let beaconID = event.beaconID {
            // Handle beacon-specific events
            processBeaconSpecificEvent(event, beaconID: beaconID)
        } else {
            // Handle system-level events (e.g., ranging heartbeat)
            processSystemEvent(event)
        }
    }
    
    /// Process events that are specific to a particular beacon
    private func processBeaconSpecificEvent(_ event: BeaconEvent, beaconID: BeaconID) {
        // Ensure beacon is registered
        guard var status = beaconStatuses[beaconID] else {
            logger.error("Received event for unregistered beacon: \(beaconID.shortDescription)")
            return
        }
        
        // Update beacon status
        status.updateFromEvent(event)
        beaconStatuses[beaconID] = status
        
        // Update range sets
        updateRangeSets()
        
        //logger.debug("Processed event for beacon \(beaconID.shortDescription): \(event)")
    }
    
    /// Process system-level events that don't relate to specific beacons
    private func processSystemEvent(_ event: BeaconEvent) {
        switch event {
        case .noBeacon(let constraint):
            //logger.debug("Processed no beacon event for constraint: \(constraint)")
            // No beacon event indicates monitoring is active but no beacons detected
            // This is useful for triggering rule evaluation even when no beacons are present
            break
        case .missingBeacon:
            //logger.debug("Processed missing beacon event: \(event)")
            // Missing beacon event indicates beacon with invalid RSSI was detected
            break
        case .monitoringStarted, .monitoringStopped, .authorizationChanged, .error:
            //logger.debug("Processed system event: \(event)")
            break
        default:
            logger.error("Received unexpected system event without beacon ID: \(event)")
        }
    }
    
    /// Process multiple events efficiently
    /// - Parameter events: Array of beacon events to process
    func processEvents(_ events: [BeaconEvent]) {
        var anyUpdates = false
        
        for event in events {
            guard let beaconID = event.beaconID,
                  var status = beaconStatuses[beaconID] else {
                continue
            }
            
            status.updateFromEvent(event)
            beaconStatuses[beaconID] = status
            anyUpdates = true
        }
        
        if anyUpdates {
            updateRangeSets()
            logger.debug("Processed batch of \(events.count) beacon events")
        }
    }
    
    // MARK: - Status Queries
    
    /// Get status for a specific beacon
    /// - Parameter beaconID: Beacon to query
    /// - Returns: Beacon status or nil if not tracked
    func status(for beaconID: BeaconID) -> BeaconStatus? {
        return beaconStatuses[beaconID]
    }
    
    /// Check if a beacon is currently in range
    /// - Parameter beaconID: Beacon to check
    /// - Returns: True if beacon is in range
    func isBeaconInRange(_ beaconID: BeaconID) -> Bool {
        return beaconStatuses[beaconID]?.isInRange ?? false
    }
    
    /// Check if a beacon is in near range (stricter criteria)
    /// - Parameter beaconID: Beacon to check
    /// - Returns: True if beacon is in near range
    func isBeaconInNearRange(_ beaconID: BeaconID) -> Bool {
        return beaconStatuses[beaconID]?.isNearRange ?? false
    }
    
    /// Get all beacons that are currently in range
    /// - Returns: Array of beacon statuses for in-range beacons
    func beaconsCurrentlyInRange() -> [BeaconStatus] {
        return beaconStatuses.values.filter { $0.isInRange }
    }
    
    /// Get all beacons that are currently in near range
    /// - Returns: Array of beacon statuses for near-range beacons
    func beaconsCurrentlyInNearRange() -> [BeaconStatus] {
        return beaconStatuses.values.filter { $0.isNearRange }
    }
    
    /// Get beacon statuses for specific beacon IDs
    /// - Parameter beaconIDs: Array of beacon IDs to query
    /// - Returns: Array of beacon statuses (excludes untracked beacons)
    func statuses(for beaconIDs: [BeaconID]) -> [BeaconStatus] {
        return beaconIDs.compactMap { beaconStatuses[$0] }
    }
    
    // MARK: - Rule Integration Support
    
    /// Get beacon condition status for rule evaluation
    /// - Parameter beaconIDs: Beacon IDs used in rule conditions
    /// - Returns: Dictionary mapping beacon IDs to their in-range status
    func beaconConditions(for beaconIDs: [BeaconID]) -> [BeaconID: Bool] {
        var conditions: [BeaconID: Bool] = [:]
        for beaconID in beaconIDs {
            conditions[beaconID] = isBeaconInRange(beaconID)
        }
        return conditions
    }
    
    /// Check if any beacons in a list are in range
    /// - Parameter beaconIDs: Beacon IDs to check
    /// - Returns: True if any beacon is in range
    func anyBeaconInRange(from beaconIDs: [BeaconID]) -> Bool {
        return beaconIDs.contains { isBeaconInRange($0) }
    }
    
    /// Check if all beacons in a list are in range
    /// - Parameter beaconIDs: Beacon IDs to check
    /// - Returns: True if all beacons are in range
    func allBeaconsInRange(from beaconIDs: [BeaconID]) -> Bool {
        guard !beaconIDs.isEmpty else { return false }
        return beaconIDs.allSatisfy { isBeaconInRange($0) }
    }
    
    /// Get count of beacons in range from a list
    /// - Parameter beaconIDs: Beacon IDs to check
    /// - Returns: Number of beacons currently in range
    func beaconInRangeCount(from beaconIDs: [BeaconID]) -> Int {
        return beaconIDs.count { isBeaconInRange($0) }
    }
    
    // MARK: - Advanced Analysis
    
    /// Get beacon presence analysis for recent time window
    /// - Parameters:
    ///   - beaconID: Beacon to analyze
    ///   - timeWindow: Time window in seconds
    /// - Returns: Presence ratio (0.0 to 1.0) or nil if beacon not tracked
    func presenceRatio(for beaconID: BeaconID, in timeWindow: TimeInterval) -> Double? {
        return beaconStatuses[beaconID]?.presenceRatio(in: timeWindow)
    }
    
    /// Get beacons that have been stable in range for minimum duration
    /// - Parameter minimumDuration: Required stable duration in seconds
    /// - Returns: Array of beacon statuses meeting criteria
    func beaconsStableInRange(for minimumDuration: TimeInterval) -> [BeaconStatus] {
        return beaconStatuses.values.filter { 
            $0.hasBeenStableInRange(for: minimumDuration)
        }
    }
    
    /// Get overall beacon detection statistics
    /// - Returns: Summary statistics for all tracked beacons
    func detectionStatistics() -> BeaconDetectionStatistics {
        let statuses = Array(beaconStatuses.values)
        
        return BeaconDetectionStatistics(
            totalBeacons: statuses.count,
            beaconsInRange: beaconsInRange.count,
            beaconsInNearRange: beaconsInNearRange.count,
            averageReliability: statuses.isEmpty ? 0.0 : statuses.map(\.reliability).reduce(0, +) / Double(statuses.count),
            totalDetections: statuses.map(\.totalDetections).reduce(0, +)
        )
    }
    
    // MARK: - Internal Management
    
    /// Update the published range sets based on current beacon statuses
    private func updateRangeSets() {
        let newInRange = Set(beaconStatuses.compactMap { (id, status) in
            status.isInRange ? id : nil
        })
        
        let newInNearRange = Set(beaconStatuses.compactMap { (id, status) in
            status.isNearRange ? id : nil
        })
        
        // Only update if changed to minimize UI updates
        if beaconsInRange != newInRange {
            beaconsInRange = newInRange
        }
        
        if beaconsInNearRange != newInNearRange {
            beaconsInNearRange = newInNearRange
        }
    }
    
    /// Start periodic cleanup of stale beacon statuses
    /*private func startCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: cleanupInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupStaleBeacons()
            }
        }
    }*/
    
    /// Remove beacon statuses that haven't been updated recently
    /*private func cleanupStaleBeacons() {
        let now = Date()
        var removedCount = 0
        
        for (beaconID, status) in beaconStatuses {
            if now.timeIntervalSince(status.lastSeen) > maxStaleTime {
                beaconStatuses.removeValue(forKey: beaconID)
                beaconsInRange.remove(beaconID)
                beaconsInNearRange.remove(beaconID)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            logger.debug("Cleaned up \(removedCount) stale beacon statuses")
        }
    }*/
    
    // MARK: - Debug Support
    
    /// Get debug information for all tracked beacons
    /// - Returns: String representation of all beacon statuses
    func debugDescription() -> String {
        let sortedStatuses = beaconStatuses.values.sorted { $0.device.name < $1.device.name }
        
        var description = "BeaconRegistry Debug Information:\n"
        description += "Total Beacons: \(beaconStatuses.count)\n"
        description += "In Range: \(beaconsInRange.count)\n"
        description += "In Near Range: \(beaconsInNearRange.count)\n\n"
        
        for status in sortedStatuses {
            description += "\(status.description)\n"
        }
        
        return description
    }
}

// MARK: - Supporting Types

/// Summary statistics for beacon detection performance
struct BeaconDetectionStatistics {
    let totalBeacons: Int
    let beaconsInRange: Int
    let beaconsInNearRange: Int
    let averageReliability: Double
    let totalDetections: Int
    
    var description: String {
        return """
        Beacon Detection Statistics:
        - Total Beacons: \(totalBeacons)
        - In Range: \(beaconsInRange)
        - In Near Range: \(beaconsInNearRange)
        - Average Reliability: \(String(format: "%.1f%%", averageReliability * 100))
        - Total Detections: \(totalDetections)
        """
    }
}

// MARK: - BeaconEvent Extension
// Note: BeaconEvent extensions are defined in BeaconEvent.swift

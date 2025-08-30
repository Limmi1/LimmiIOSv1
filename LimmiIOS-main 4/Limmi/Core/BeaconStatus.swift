//
//  BeaconStatus.swift
//  Limmi
//
//  Purpose: Enhanced beacon status tracking for sophisticated rule processing
//  Dependencies: Foundation, BeaconID, BeaconDevice, BeaconEvent
//  Related: BlockingEngine.swift, BeaconMonitor.swift, EventProcessor.swift
//

import Foundation
import os

/// Comprehensive status tracking for individual beacons within the BlockingEngine
///
/// This structure maintains rich state information for each tracked beacon, enabling
/// sophisticated rule processing strategies based on beacon proximity, signal quality,
/// and presence history. The status is updated in real-time as beacon events are processed.
///
/// ## Key Features
/// - **Real-time Status**: Current proximity and signal strength tracking
/// - **History Management**: Sliding window of recent beacon events
/// - **Signal Quality**: RSSI averaging and quality assessment
/// - **State Transitions**: Tracks beacon state changes for rule evaluation
/// - **Performance Metrics**: Detection reliability and timing statistics
///
/// ## Usage
/// ```swift
/// var status = BeaconStatus(beaconID: beaconID, device: device)
/// status.updateFromEvent(.beaconDetected(beaconID, rssi: -65))
/// 
/// if status.isInRange {
///     // Process beacon-based rules
/// }
/// ```
struct BeaconStatus {
    // MARK: - Core Identity
    
    /// Unique identifier for this beacon
    let beaconID: BeaconID
    
    /// Associated device information from Firebase
    var device: BeaconDevice
    
    // MARK: - Current State
    
    /// Current proximity classification based on signal strength
    private(set) var proximity: BeaconProximity = .unknown
    
    /// Most recent RSSI value (-30 to -100, or nil if not detected)
    private(set) var currentRSSI: Int?
    
    /// Current region monitoring state (independent of RSSI detection)
    private(set) var isInRegion: Bool = false
    
    /// Computed property for range status based on multiple factors
    var isInRange: Bool {
        switch proximity {
        case .immediate, .near:
            return true
        case .far:
            // Consider "far" as in-range if signal is strong enough
            return (currentRSSI ?? -100) > -85
        case .unknown:
            return false
        }
    }
    
    /// Alternative computed range status with stricter criteria
    var isNearRange: Bool {
        proximity == .immediate || proximity == .near
    }
    
    // MARK: - Temporal Information
    
    /// Timestamp when beacon was first detected
    let firstSeen: Date
    
    /// Timestamp of most recent beacon event
    private(set) var lastSeen: Date
    
    /// Timestamp when beacon was last considered "in range"
    private(set) var lastInRange: Date?
    
    /// Timestamp when beacon region was last entered
    private(set) var lastRegionEntry: Date?
    
    /// Timestamp when beacon region was last exited
    private(set) var lastRegionExit: Date?
    
    /// Duration since beacon was last detected
    var timeSinceLastSeen: TimeInterval {
        Date().timeIntervalSince(lastSeen)
    }
    
    /// Duration of current presence session (nil if not currently present)
    var currentPresenceDuration: TimeInterval? {
        guard isInRange, let lastInRange = lastInRange else { return nil }
        return Date().timeIntervalSince(lastInRange)
    }
    
    /// Duration of current region presence session (nil if not in region)
    var currentRegionPresenceDuration: TimeInterval? {
        guard isInRegion, let lastRegionEntry = lastRegionEntry else { return nil }
        return Date().timeIntervalSince(lastRegionEntry)
    }
    
    // MARK: - Signal Quality Metrics
    
    /// Exponential moving average of RSSI values for signal smoothing
    private var rssiEMA: Double?
    
    /// Smoothing factor for RSSI averaging (0.2 = 20% new value, 80% historical)
    private let rssiSmoothingFactor: Double = 0.2
    
    /// Average RSSI over recent detections
    var averageRSSI: Double? {
        return rssiEMA
    }
    
    /// Signal quality assessment based on RSSI stability and strength
    var signalQuality: SignalQuality {
        guard let rssi = currentRSSI, let avgRSSI = rssiEMA else {
            return .poor
        }
        
        let signalStrength = avgRSSI
        let signalStability = abs(Double(rssi) - avgRSSI)
        
        // Determine quality based on both signal strength and stability
        if signalStrength >= -60 && signalStability <= 5 {
            return .excellent
        } else if signalStrength >= -70 && signalStability <= 8 {
            return .good
        } else if signalStrength >= -80 && signalStability <= 12 {
            return .fair
        } else {
            return .poor
        }
    }
    
    // MARK: - Detection Statistics
    
    /// Number of consecutive detections in current session
    private(set) var consecutiveDetections: Int = 0
    
    /// Total number of detections since tracking began
    private(set) var totalDetections: Int = 0
    
    /// Number of times beacon has entered range
    private(set) var rangeEntryCount: Int = 0
    
    /// Detection reliability score (0.0 to 1.0)
    var reliability: Double {
        let expectedDetections = max(1, Int(Date().timeIntervalSince(firstSeen) / 2.0)) // Expect detection every 2 seconds
        return min(1.0, Double(totalDetections) / Double(expectedDetections))
    }
    
    // MARK: - Event History
    
    /// Sliding window of recent beacon events for pattern analysis
    private var eventHistory: [BeaconEventRecord] = []
    
    /// Maximum number of events to retain in history
    private let maxHistorySize: Int = 50
    
    /// Recent event history for analysis (read-only)
    var recentEvents: [BeaconEventRecord] {
        return eventHistory
    }
    
    // MARK: - Initialization
    
    /// Initialize beacon status tracking for a new beacon
    /// - Parameters:
    ///   - beaconID: Unique identifier for the beacon
    ///   - device: Associated device information from Firebase
    init(beaconID: BeaconID, device: BeaconDevice) {
        self.beaconID = beaconID
        self.device = device
        self.firstSeen = Date()
        self.lastSeen = Date()
    }
    
    // MARK: - State Updates
    
    /// Update beacon status from a beacon event
    /// - Parameter event: The beacon event to process
    mutating func updateFromEvent(_ event: BeaconEvent) {
        let now = Date()
        lastSeen = now
        
        // Record event in history
        addEventToHistory(BeaconEventRecord(event: event, timestamp: now))
        
        // Process event based on type
        switch event {
        case .beaconDetected(_, let rssi):
            updateFromDetection(rssi: rssi, timestamp: now)
            
        case .regionEntered(_):
            updateFromRegionEntry(timestamp: now)
            
        case .regionExited(_):
            updateFromRegionExit(timestamp: now)
            
        case .beaconLost(_):
            updateFromBeaconLost(timestamp: now)
            
        case .proximityChanged(_, let newProximity):
            updateFromProximityChange(newProximity, timestamp: now)
            
        default:
            // Handle other event types if needed
            break
        }
    }
    
    /// Update status from a direct detection event with RSSI
    private mutating func updateFromDetection(rssi: Int, timestamp: Date) {
        currentRSSI = rssi
        totalDetections += 1
        consecutiveDetections += 1
        
        // Update RSSI moving average
        if let existingEMA = rssiEMA {
            rssiEMA = existingEMA * (1 - rssiSmoothingFactor) + Double(rssi) * rssiSmoothingFactor
        } else {
            rssiEMA = Double(rssi)
        }
        
        // Update proximity based on RSSI
        let newProximity = BeaconProximity(from: rssi)
        updateProximityIfChanged(newProximity, timestamp: timestamp)
    }
    
    /// Update status from region entry event
    private mutating func updateFromRegionEntry(timestamp: Date) {
        rangeEntryCount += 1
        isInRegion = true
        lastRegionEntry = timestamp
        if !isInRange {
            lastInRange = timestamp
        }
        updateProximityIfChanged(.near, timestamp: timestamp)
    }
    
    /// Update status from region exit event
    private mutating func updateFromRegionExit(timestamp: Date) {
        consecutiveDetections = 0
        isInRegion = false
        lastRegionExit = timestamp
        currentRSSI = nil
        updateProximityIfChanged(.unknown, timestamp: timestamp)
    }
    
    /// Update status when beacon is lost
    private mutating func updateFromBeaconLost(timestamp: Date) {
        consecutiveDetections = 0
        currentRSSI = nil
        updateProximityIfChanged(.unknown, timestamp: timestamp)
    }
    
    /// Update status from explicit proximity change
    private mutating func updateFromProximityChange(_ newProximity: BeaconProximity, timestamp: Date) {
        updateProximityIfChanged(newProximity, timestamp: timestamp)
    }
    
    /// Update proximity if it has changed, tracking range transitions
    private mutating func updateProximityIfChanged(_ newProximity: BeaconProximity, timestamp: Date) {
        let wasInRange = isInRange
        proximity = newProximity
        let nowInRange = isInRange
        
        // Track range entry transitions
        if !wasInRange && nowInRange {
            lastInRange = timestamp
        }
    }
    
    /// Add event to sliding window history
    private mutating func addEventToHistory(_ record: BeaconEventRecord) {
        eventHistory.append(record)
        
        // Maintain sliding window size
        if eventHistory.count > maxHistorySize {
            eventHistory.removeFirst(eventHistory.count - maxHistorySize)
        }
    }
    
    // MARK: - Analysis Methods
    
    /// Check if beacon has been stable in range for a minimum duration
    /// - Parameter minimumDuration: Required stable duration in seconds
    /// - Returns: True if beacon has been consistently in range
    func hasBeenStableInRange(for minimumDuration: TimeInterval) -> Bool {
        guard let currentDuration = currentPresenceDuration else { return false }
        return currentDuration >= minimumDuration
    }
    
    /// Check if beacon has been stable in region for a minimum duration
    /// - Parameter minimumDuration: Required stable duration in seconds
    /// - Returns: True if beacon region has been consistently entered
    func hasBeenStableInRegion(for minimumDuration: TimeInterval) -> Bool {
        guard let currentDuration = currentRegionPresenceDuration else { return false }
        return currentDuration >= minimumDuration
    }
    
    /// Get beacon presence pattern over recent history
    /// - Parameter timeWindow: Time window to analyze (in seconds)
    /// - Returns: Percentage of time beacon was in range (0.0 to 1.0)
    func presenceRatio(in timeWindow: TimeInterval) -> Double {
        let cutoffTime = Date().addingTimeInterval(-timeWindow)
        let relevantEvents = eventHistory.filter { $0.timestamp >= cutoffTime }
        
        guard !relevantEvents.isEmpty else { return 0.0 }
        
        var inRangeTime: TimeInterval = 0
        var currentlyInRange = false
        var lastTransitionTime = cutoffTime
        
        for event in relevantEvents {
            // Calculate time in current state
            let stateDuration = event.timestamp.timeIntervalSince(lastTransitionTime)
            if currentlyInRange {
                inRangeTime += stateDuration
            }
            
            // Update state based on event
            switch event.event {
            case .beaconDetected(_, let rssi):
                currentlyInRange = rssi > -99
            case .regionEntered(_):
                currentlyInRange = true
            case .regionExited(_), .beaconLost(_):
                currentlyInRange = false
            default:
                break
            }
            
            lastTransitionTime = event.timestamp
        }
        
        // Account for time from last event to now
        let finalDuration = Date().timeIntervalSince(lastTransitionTime)
        if currentlyInRange {
            inRangeTime += finalDuration
        }
        
        return inRangeTime / timeWindow
    }
}

// MARK: - Supporting Types

/// Signal quality assessment for beacon detection
enum SignalQuality: String, CaseIterable, Comparable {
    case poor = "poor"
    case fair = "fair"
    case good = "good"  
    case excellent = "excellent"
    
    var description: String {
        switch self {
        case .excellent:
            return "Excellent (Strong, Stable)"
        case .good:
            return "Good (Strong)"
        case .fair:
            return "Fair (Moderate)"
        case .poor:
            return "Poor (Weak/Unstable)"
        }
    }
    
    /// Ordinal value for comparison (higher = better quality)
    var ordinalValue: Int {
        switch self {
        case .poor: return 0
        case .fair: return 1
        case .good: return 2
        case .excellent: return 3
        }
    }
    
    static func < (lhs: SignalQuality, rhs: SignalQuality) -> Bool {
        return lhs.ordinalValue < rhs.ordinalValue
    }
}

/// Record of a beacon event with timestamp for history tracking
struct BeaconEventRecord {
    let event: BeaconEvent
    let timestamp: Date
    
    /// Human-readable description of the event
    var description: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return "\(formatter.string(from: timestamp)): \(event)"
    }
}

// MARK: - BeaconProximity Extension
// Note: BeaconProximity already has init(from rssi: Int) in BeaconEvent.swift

// MARK: - Debug Support

extension BeaconStatus: CustomStringConvertible {
    var description: String {
        let inRangeStatus = isInRange ? "✓" : "✗"
        let rssiText = currentRSSI.map { "\($0)dBm" } ?? "N/A"
        let avgRssiText = averageRSSI.map { String(format: "%.1f", $0) } ?? "N/A"
        
        let regionStatus = isInRegion ? "✓" : "✗"
        
        return """
        BeaconStatus(
          ID: \(beaconID.shortDescription)
          Device: \(device.name)
          InRange: \(inRangeStatus) (\(proximity))
          InRegion: \(regionStatus)
          RSSI: \(rssiText) (avg: \(avgRssiText))
          Quality: \(signalQuality.rawValue)
          Detections: \(consecutiveDetections)/\(totalDetections)
          LastSeen: \(String(format: "%.1f", timeSinceLastSeen))s ago
        )
        """
    }
}


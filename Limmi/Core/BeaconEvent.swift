//
//  BeaconEvent.swift
//  Limmi
//
//  Purpose: Beacon monitoring event system with proximity detection and error handling
//  Dependencies: Foundation, CoreLocation
//  Related: BeaconID.swift, BeaconMonitorProtocol.swift, BeaconSignalProcessor.swift
//

import Foundation
import CoreLocation

/// Comprehensive event system for beacon monitoring operations.
///
/// This enum represents all possible events that can occur during beacon monitoring,
/// providing a type-safe way to handle beacon detection, proximity changes, and errors.
/// Events are published by beacon monitors and consumed by the blocking engine.
///
/// ## Event Categories
/// - **Detection Events**: beaconDetected, regionEntered
/// - **Loss Events**: beaconLost, regionExited  
/// - **State Changes**: proximityChanged, authorizationChanged
/// - **Lifecycle Events**: monitoringStarted, monitoringStopped
/// - **Error Events**: error with detailed error information
///
/// ## Usage Pattern
/// ```swift
/// beaconMonitor.eventPublisher
///     .sink { event in
///         switch event {
///         case .beaconDetected(let id, let rssi):
///             // Handle beacon detection
///         case .regionEntered(let id):
///             // Handle region entry
///         // ... other cases
///         }
///     }
/// ```
///
/// - Since: 1.0
enum BeaconEvent {
    /// Beacon detected via RSSI ranging with signal strength.
    /// Fired continuously during active ranging when beacon is in range.
    case beaconDetected(BeaconID, rssi: Int)
    
    /// Beacon signal lost during ranging operations.
    /// Indicates beacon is no longer detectable via RSSI ranging.
    case beaconLost(BeaconID)
    
    /// Device entered a beacon region (background-capable).
    /// Triggered by CoreLocation region monitoring, works in background.
    case regionEntered(BeaconID)
    
    /// Device exited a beacon region (background-capable).
    /// Triggered by CoreLocation region monitoring, works in background.
    case regionExited(BeaconID)
    
    /// Beacon proximity level changed based on signal processing.
    /// Result of RSSI analysis determining immediate/near/far/unknown proximity.
    case proximityChanged(BeaconID, proximity: BeaconProximity)
    
    /// Beacon monitoring started successfully for specified beacons.
    /// Indicates monitoring system is active and listening for events.
    case monitoringStarted(Set<BeaconID>)
    
    /// Beacon monitoring stopped (manually or due to error).
    /// All beacon detection will cease until monitoring restarts.
    case monitoringStopped
    
    /// Error occurred during beacon monitoring operations.
    /// Contains detailed error information for debugging and user feedback.
    case error(BeaconMonitoringError)
    
    /// Location authorization status changed.
    /// Critical for beacon monitoring which requires location permissions.
    case authorizationChanged(CLAuthorizationStatus)
    
    /// No beacons detected during ranging operation.
    /// Indicates ranging is active but no beacons are in range for the given constraint.
    /// This is normal behavior when beacons are not present or out of range.
    case noBeacon(CLBeaconIdentityConstraint)
    
    /// Beacon detected with invalid RSSI (0).
    /// Indicates beacon is present but signal strength is unreliable or corrupted.
    /// This may occur due to interference, beacon malfunction, or edge cases.
    case missingBeacon(BeaconID)
}

/// Beacon proximity classification based on RSSI signal strength.
///
/// Provides human-readable proximity levels derived from RSSI measurements.
/// These levels help translate technical signal strength into meaningful
/// distance categories for business logic and user interfaces.
///
/// ## RSSI Ranges
/// - **Immediate**: -30 to 0 dBm (very close, typically < 1 meter)
/// - **Near**: -60 to -30 dBm (close, typically 1-3 meters)
/// - **Far**: -90 to -60 dBm (distant, typically 3+ meters)
/// - **Unknown**: Below -90 dBm or invalid readings
///
/// ## Usage
/// ```swift
/// let proximity = BeaconProximity(from: rssi)
/// if proximity == .immediate || proximity == .near {
///     // User is close to beacon
/// }
/// ```
///
/// - Since: 1.0
enum BeaconProximity: String, CaseIterable {
    /// Very close proximity (< -30 dBm), typically within 1 meter.
    case immediate = "immediate"
    
    /// Close proximity (-30 to -60 dBm), typically 1-3 meters.
    case near = "near"
    
    /// Distant proximity (-60 to -90 dBm), typically 3+ meters.
    case far = "far"
    
    /// Unknown proximity (< -90 dBm or invalid), unreliable signal.
    case unknown = "unknown"
    
    /// Creates proximity classification from RSSI signal strength.
    /// 
    /// Converts raw RSSI measurements into meaningful proximity categories
    /// using empirically-determined thresholds for iBeacon signals.
    /// 
    /// - Parameter rssi: Signal strength in dBm (negative values)
    init(from rssi: Int) {
        switch rssi {
        case -80...0:
            self = .immediate
        case -85..<(-80):
            self = .near
        case -99..<(-85):
            self = .far
        default:
            self = .unknown
        }
    }
    
    /// Human-readable display name for UI presentation.
    /// - Returns: Capitalized string suitable for user interfaces
    var displayName: String {
        switch self {
        case .immediate: return "Immediate"
        case .near: return "Near"
        case .far: return "Far"
        case .unknown: return "Unknown"
        }
    }
}

/// Comprehensive error types for beacon monitoring operations.
///
/// Provides detailed error information for all failure modes in beacon monitoring,
/// enabling proper error handling and user feedback throughout the app.
///
/// ## Error Categories
/// - **Permission Errors**: locationPermissionDenied
/// - **Hardware Errors**: bluetoothUnavailable, regionMonitoringUnavailable
/// - **Configuration Errors**: invalidBeaconConfiguration
/// - **Runtime Errors**: rangeError, monitoringFailed with detailed messages
///
/// All errors provide localized descriptions suitable for user presentation.
///
/// - Since: 1.0
enum BeaconMonitoringError: Error, LocalizedError {
    /// Location permission denied by user.
    /// Required for all beacon monitoring operations.
    case locationPermissionDenied
    
    /// Bluetooth hardware unavailable or disabled.
    /// Beacon detection requires active Bluetooth.
    case bluetoothUnavailable
    
    /// Invalid beacon configuration provided.
    /// Indicates malformed UUID or invalid major/minor values.
    case invalidBeaconConfiguration
    
    /// Error during RSSI ranging operations.
    /// Contains specific error message from CoreLocation.
    case rangeError(String)
    
    /// Region monitoring not available on device.
    /// Some older devices don't support region monitoring.
    case regionMonitoringUnavailable
    
    /// General monitoring failure with detailed message.
    /// Catch-all for unexpected monitoring errors.
    case monitoringFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .locationPermissionDenied:
            return "Location permission denied for beacon monitoring"
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable"
        case .invalidBeaconConfiguration:
            return "Invalid beacon configuration"
        case .rangeError(let message):
            return "Beacon ranging error: \(message)"
        case .regionMonitoringUnavailable:
            return "Region monitoring is unavailable"
        case .monitoringFailed(let message):
            return "Monitoring failed: \(message)"
        }
    }
}

/// Configuration parameters for beacon monitoring behavior.
///
/// Allows customization of beacon monitoring strategies and thresholds
/// to optimize for different use cases (battery life vs. accuracy).
///
/// ## Configuration Options
/// - **Detection Methods**: RSSI ranging vs. region monitoring
/// - **Signal Processing**: Enable/disable noise filtering
/// - **Thresholds**: Proximity and timeout values
///
/// The default configuration provides balanced performance for most use cases.
///
/// - Since: 1.0
struct BeaconMonitoringConfig {
    /// Enable region monitoring for background-capable entry/exit detection.
    /// Works reliably in background and provides beacon detection through region events.
    /// Note: RSSI ranging is automatically handled by region monitoring.
    let useRegionMonitoring: Bool
    
    /// Enable signal processing for noise reduction and proximity calculation.
    /// Improves accuracy but adds computational overhead.
    let signalProcessingEnabled: Bool
    
    /// RSSI threshold for considering a beacon "near" (in dBm).
    /// Typical values: -70 dBm for close proximity detection.
    let proximityThreshold: Int
    
    /// Timeout before considering a beacon lost (in seconds).
    /// Prevents false negatives during temporary signal interruptions.
    let lostBeaconTimeout: TimeInterval
    
    /// Default configuration optimized for reliable beacon detection.
    /// 
    /// Uses dual-manager approach: region monitoring for entry/exit and
    /// RSSI ranging for precise signal strength when inside regions.
    static let `default` = BeaconMonitoringConfig(
        useRegionMonitoring: true,
        signalProcessingEnabled: true,
        proximityThreshold: -70,
        lostBeaconTimeout: 3.0
    )
}

/// Processed beacon detection result with computed proximity and metadata.
///
/// Represents a complete beacon detection event with all relevant information
/// extracted and computed from raw CoreLocation data. Includes automatic
/// proximity classification and timestamp information.
///
/// ## Data Flow
/// CLBeacon (CoreLocation) → BeaconDetectionResult → Business Logic
///
/// This abstraction allows business logic to work with processed beacon data
/// without depending on CoreLocation types directly.
///
/// - Since: 1.0
struct BeaconDetectionResult {
    /// Unique identifier for the detected beacon.
    let beaconID: BeaconID
    
    /// Signal strength in dBm (negative values, closer to 0 = stronger).
    let rssi: Int
    
    /// Computed proximity classification based on RSSI.
    let proximity: BeaconProximity
    
    /// When this detection occurred.
    let timestamp: Date
    
    /// Optional accuracy estimate from CoreLocation (in meters).
    let accuracy: Double?
    
    /// Creates a detection result with automatic proximity calculation.
    /// 
    /// - Parameters:
    ///   - beaconID: Identifier for the detected beacon
    ///   - rssi: Signal strength in dBm
    ///   - timestamp: Detection time (defaults to now)
    ///   - accuracy: Optional accuracy estimate in meters
    init(beaconID: BeaconID, rssi: Int, timestamp: Date = Date(), accuracy: Double? = nil) {
        self.beaconID = beaconID
        self.rssi = rssi
        self.proximity = BeaconProximity(from: rssi)
        self.timestamp = timestamp
        self.accuracy = accuracy
    }
    
    /// Creates a detection result from CoreLocation CLBeacon data.
    /// 
    /// Converts raw CoreLocation beacon detection into processed business object.
    /// Automatically extracts all relevant information and computes proximity.
    /// 
    /// - Parameter clBeacon: CLBeacon from CoreLocation ranging callback
    init(from clBeacon: CLBeacon) {
        let beaconID = BeaconID(from: clBeacon)
        self.init(
            beaconID: beaconID,
            rssi: clBeacon.rssi,
            timestamp: clBeacon.timestamp,
            accuracy: clBeacon.accuracy
        )
    }
}

// MARK: - BeaconEvent Convenience Methods

/// Convenience methods for working with beacon events.
///
/// These extensions provide easy access to common event properties and
/// classification methods for event filtering and processing.
extension BeaconEvent {
    /// Extracts the beacon ID from beacon-specific events.
    /// 
    /// Returns the associated BeaconID for events that relate to a specific beacon,
    /// or nil for system-wide events like monitoring lifecycle changes.
    /// 
    /// - Returns: BeaconID if event is beacon-specific, nil otherwise
    var beaconID: BeaconID? {
        switch self {
        case .beaconDetected(let id, _),
             .beaconLost(let id),
             .regionEntered(let id),
             .regionExited(let id),
             .proximityChanged(let id, _),
             .missingBeacon(let id):
            return id
        case .noBeacon:
            return nil // No beacon events are not beacon-specific
        default:
            return nil
        }
    }
    
    /// Indicates if this event represents beacon detection.
    /// 
    /// True for events that indicate a beacon becoming available:
    /// - beaconDetected (RSSI ranging)
    /// - regionEntered (region monitoring)
    /// 
    /// - Returns: True if beacon was detected
    var isDetection: Bool {
        switch self {
        case .beaconDetected, .regionEntered:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if this event represents beacon loss.
    /// 
    /// True for events that indicate a beacon becoming unavailable:
    /// - beaconLost (RSSI ranging stopped detecting)
    /// - regionExited (left beacon region)
    /// 
    /// - Returns: True if beacon was lost
    var isLoss: Bool {
        switch self {
        case .beaconLost, .regionExited:
            return true
        default:
            return false
        }
    }
    
    /// Indicates if this event represents an error condition.
    /// 
    /// True only for error events that require special handling or user notification.
    /// 
    /// - Returns: True if event contains error information
    var isError: Bool {
        switch self {
        case .error:
            return true
        default:
            return false
        }
    }
}

// MARK: - Equatable Conformance

extension BeaconEvent: Equatable {
    static func == (lhs: BeaconEvent, rhs: BeaconEvent) -> Bool {
        switch (lhs, rhs) {
        case (.beaconDetected(let lhsID, let lhsRSSI), .beaconDetected(let rhsID, let rhsRSSI)):
            return lhsID == rhsID && lhsRSSI == rhsRSSI
        case (.beaconLost(let lhsID), .beaconLost(let rhsID)):
            return lhsID == rhsID
        case (.regionEntered(let lhsID), .regionEntered(let rhsID)):
            return lhsID == rhsID
        case (.regionExited(let lhsID), .regionExited(let rhsID)):
            return lhsID == rhsID
        case (.proximityChanged(let lhsID, let lhsProximity), .proximityChanged(let rhsID, let rhsProximity)):
            return lhsID == rhsID && lhsProximity == rhsProximity
        case (.monitoringStarted(let lhsBeacons), .monitoringStarted(let rhsBeacons)):
            return lhsBeacons == rhsBeacons
        case (.monitoringStopped, .monitoringStopped):
            return true
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.authorizationChanged(let lhsStatus), .authorizationChanged(let rhsStatus)):
            return lhsStatus == rhsStatus
        case (.noBeacon(let lhsConstraint), .noBeacon(let rhsConstraint)):
            return lhsConstraint == rhsConstraint
        case (.missingBeacon(let lhsBeaconID), .missingBeacon(let rhsBeaconID)):
            return lhsBeaconID == rhsBeaconID
        default:
            return false
        }
    }
}

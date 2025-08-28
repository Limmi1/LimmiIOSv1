//
//  BeaconID.swift
//  Limmi
//
//  Purpose: Type-safe beacon identification with flexible matching and CoreLocation integration
//  Dependencies: Foundation, CoreLocation
//  Related: BeaconDevice.swift, BeaconMonitor.swift, CLBeacon integration
//

import Foundation

/// Domain-specific value type for beacon identification with flexible matching capabilities.
///
/// This struct provides type-safe beacon identification supporting three matching modes:
/// - **UUID only**: Matches any beacon with this UUID (major and minor are nil)
/// - **UUID + major**: Matches any beacon with this UUID and major value (minor is nil)
/// - **UUID + major + minor**: Exact beacon match with all three components
///
/// ## Usage Examples
/// ```swift
/// // Match any beacon with this UUID
/// let anyBeacon = BeaconID(uuid: myUUID)
/// 
/// // Match specific major, any minor
/// let familyBeacon = BeaconID(uuid: myUUID, major: 1)
/// 
/// // Exact beacon match
/// let exactBeacon = BeaconID(uuid: myUUID, major: 1, minor: 5)
/// ```
///
/// ## CoreLocation Integration
/// BeaconID seamlessly converts to CoreLocation types:
/// - CLBeaconIdentityConstraint for ranging
/// - CLBeaconRegion for region monitoring
/// - Creation from CLBeacon objects
///
/// ## Performance Notes
/// - Implements Hashable for efficient Set and Dictionary operations
/// - Codable for Firebase and Core Data serialization
/// - Value semantics prevent accidental mutation
/// - Optimized matching algorithm with fail-fast evaluation
///
/// - Since: 1.0
struct BeaconID: Hashable, Codable {
    // MARK: - Properties
    
    /// Beacon UUID (universally unique identifier).
    /// This is the primary identifier that must always be present.
    let uuid: UUID
    
    /// Beacon major value (optional for flexible matching).
    /// When nil, matches any major value during beacon detection.
    let major: UInt16?
    
    /// Beacon minor value (optional for flexible matching).
    /// When nil, matches any minor value during beacon detection.
    let minor: UInt16?
    
    // MARK: - Initialization
    
    /// Creates a BeaconID with UUID only for broad matching.
    /// 
    /// This initializer creates a "wildcard" beacon ID that will match any beacon
    /// with the specified UUID, regardless of major or minor values.
    /// 
    /// - Parameter uuid: The beacon UUID to match
    init(uuid: UUID) {
        self.uuid = uuid
        self.major = nil
        self.minor = nil
    }
    
    /// Creates a BeaconID with UUID and major for family-level matching.
    /// 
    /// This initializer creates a beacon ID that matches beacons with the specified
    /// UUID and major value, but ignores the minor value for flexible matching.
    /// 
    /// - Parameters:
    ///   - uuid: The beacon UUID to match
    ///   - major: The major value to match
    init(uuid: UUID, major: UInt16) {
        self.uuid = uuid
        self.major = major
        self.minor = nil
    }
    
    /// Creates a BeaconID with full specification for exact or flexible matching.
    /// 
    /// This is the most flexible initializer that allows creating any type of beacon ID:
    /// - Both major and minor nil: matches any beacon with UUID
    /// - Major specified, minor nil: matches UUID and major
    /// - Both specified: exact beacon match
    /// 
    /// - Parameters:
    ///   - uuid: The beacon UUID to match
    ///   - major: Optional major value (nil for wildcard)
    ///   - minor: Optional minor value (nil for wildcard)
    init(uuid: UUID, major: UInt16?, minor: UInt16?) {
        self.uuid = uuid
        self.major = major
        self.minor = minor
    }
    
    /// Creates a BeaconID from a Firebase BeaconDevice model.
    /// 
    /// Converts a Firebase data model to a value type for use in business logic.
    /// This enables type-safe beacon handling throughout the application.
    /// 
    /// - Parameter device: BeaconDevice from Firebase containing UUID and values
    /// - Important: Crashes if device.uuid is not a valid UUID string
    init(from device: BeaconDevice) {
        guard let deviceUUID = UUID(uuidString: device.uuid) else {
            fatalError("Invalid UUID string in BeaconDevice: \(device.uuid)")
        }
        
        self.uuid = deviceUUID
        self.major = UInt16(device.major)
        self.minor = UInt16(device.minor)
    }
    
    /// Creates a BeaconID from string components with validation.
    /// 
    /// Attempts to parse a UUID string and optional major/minor values into a BeaconID.
    /// Returns nil if the UUID string is invalid, providing safe parsing.
    /// 
    /// - Parameters:
    ///   - uuidString: String representation of the UUID
    ///   - major: Optional major value as Int
    ///   - minor: Optional minor value as Int
    /// - Returns: BeaconID if UUID is valid, nil otherwise
    init?(uuidString: String, major: Int? = nil, minor: Int? = nil) {
        guard let uuid = UUID(uuidString: uuidString) else {
            return nil
        }
        
        self.uuid = uuid
        self.major = major.map { UInt16($0) }
        self.minor = minor.map { UInt16($0) }
    }
    
    // MARK: - Computed Properties
    
    /// Human-readable string representation for debugging and logging.
    /// 
    /// Formats the beacon ID in a hierarchical notation:
    /// - UUID only: "550e8400-e29b-41d4-a716-446655440000"
    /// - UUID + major: "550e8400-e29b-41d4-a716-446655440000:1"
    /// - Full specification: "550e8400-e29b-41d4-a716-446655440000:1:5"
    var description: String {
        var result = uuid.uuidString
        if let major = major {
            result += ":\(major)"
            if let minor = minor {
                result += ":\(minor)"
            }
        }
        return result
    }
    
    // MARK: - Matching Logic
    
    /// Checks if this BeaconID matches another considering wildcard semantics.
    /// 
    /// Implements flexible matching where nil values act as wildcards:
    /// - UUID must always match exactly
    /// - If either BeaconID has nil major, major comparison is skipped
    /// - If either BeaconID has nil minor, minor comparison is skipped
    /// 
    /// This enables rule-based matching where a monitoring rule can specify
    /// broad criteria (UUID only) or narrow criteria (exact beacon).
    /// 
    /// ## Examples
    /// ```swift
    /// let broad = BeaconID(uuid: uuid)  // matches any major/minor
    /// let specific = BeaconID(uuid: uuid, major: 1, minor: 5)
    /// broad.matches(specific)  // true
    /// specific.matches(broad)  // true
    /// ```
    /// 
    /// - Parameter other: BeaconID to compare against
    /// - Returns: True if the beacons match according to wildcard rules
    func matches(_ other: BeaconID) -> Bool {
        // UUID must always match
        guard uuid == other.uuid else { return false }
        
        // If this has no major, it matches any major
        guard let thisMajor = major else { return true }
        guard let otherMajor = other.major else { return true }
        guard thisMajor == otherMajor else { return false }
        
        // If this has no minor, it matches any minor
        guard let thisMinor = minor else { return true }
        guard let otherMinor = other.minor else { return true }
        
        return thisMinor == otherMinor
    }
}

// MARK: - CoreLocation Integration

import CoreLocation

/// CoreLocation integration for seamless beacon monitoring.
///
/// These extensions provide automatic conversion between BeaconID value types
/// and CoreLocation's beacon monitoring types. This abstraction allows business
/// logic to work with type-safe BeaconID objects while the monitoring layer
/// uses CoreLocation's required types.
extension BeaconID {
    /// Creates a CLBeaconIdentityConstraint for beacon ranging.
    /// 
    /// Converts this BeaconID to a CoreLocation constraint for use with
    /// `startRangingBeacons(satisfying:)`. The constraint type depends on
    /// which components are specified:
    /// - UUID only: Ranges all beacons with this UUID
    /// - UUID + major: Ranges beacons with this UUID and major
    /// - UUID + major + minor: Ranges only the exact beacon
    /// 
    /// - Returns: CLBeaconIdentityConstraint configured for this beacon
    var clBeaconConstraint: CLBeaconIdentityConstraint {
        if let major = major, let minor = minor {
            return CLBeaconIdentityConstraint(
                uuid: uuid,
                major: CLBeaconMajorValue(major),
                minor: CLBeaconMinorValue(minor)
            )
        } else if let major = major {
            return CLBeaconIdentityConstraint(
                uuid: uuid,
                major: CLBeaconMajorValue(major)
            )
        } else {
            return CLBeaconIdentityConstraint(uuid: uuid)
        }
    }
    
    /// Creates a CLBeaconRegion for background region monitoring.
    /// 
    /// Converts this BeaconID to a CoreLocation region for use with
    /// `startMonitoring(for:)`. Region monitoring works reliably in background
    /// and provides entry/exit events without continuous ranging.
    /// 
    /// The region identifier uses the beacon description for uniqueness and debugging.
    /// 
    /// - Returns: CLBeaconRegion configured for this beacon with unique identifier
    var clBeaconRegion: CLBeaconRegion {
        let identifier = "BeaconRegion_\(description)"
        
        if let major = major, let minor = minor {
            return CLBeaconRegion(
                uuid: uuid,
                major: CLBeaconMajorValue(major),
                minor: CLBeaconMinorValue(minor),
                identifier: identifier
            )
        } else if let major = major {
            return CLBeaconRegion(
                uuid: uuid,
                major: CLBeaconMajorValue(major),
                identifier: identifier
            )
        } else {
            return CLBeaconRegion(
                uuid: uuid,
                identifier: identifier
            )
        }
    }
    
    /// Creates a BeaconID from a detected CLBeacon.
    /// 
    /// Converts a CoreLocation beacon detection result back to a BeaconID value type.
    /// This enables type-safe handling of detected beacons throughout the application.
    /// 
    /// - Parameter clBeacon: CLBeacon object from ranging delegate callback
    init(from clBeacon: CLBeacon) {
        self.uuid = clBeacon.uuid
        self.major = UInt16(clBeacon.major.intValue)
        self.minor = UInt16(clBeacon.minor.intValue)
    }

    /// Initializes a BeaconID from a CLBeaconIdentityConstraint.
    init(from constraint: CLBeaconIdentityConstraint) {
        self.uuid = constraint.uuid
        self.major = constraint.major
        self.minor = constraint.minor
    }
    /// Initializes a BeaconID from a CLBeaconRegion.
    init(from region: CLBeaconRegion) {
        self.uuid = region.uuid
        self.major = region.major.map { UInt16(truncating: $0) }
        self.minor = region.minor.map { UInt16(truncating: $0) }
    }
}

// MARK: - Collection Extensions

/// Convenience methods for working with collections of BeaconIDs.
///
/// These extensions provide batch conversion operations for efficiently
/// setting up beacon monitoring with multiple targets.
extension Collection where Element == BeaconID {
    /// Converts all BeaconIDs to CLBeaconIdentityConstraints for ranging.
    /// 
    /// Efficiently converts a collection of BeaconIDs to CoreLocation constraints
    /// for batch setup of beacon ranging operations.
    /// 
    /// - Returns: Array of constraints ready for `startRangingBeacons(satisfying:)`
    var clBeaconConstraints: [CLBeaconIdentityConstraint] {
        return map { $0.clBeaconConstraint }
    }
    
    /// Converts all BeaconIDs to CLBeaconRegions for monitoring.
    /// 
    /// Efficiently converts a collection of BeaconIDs to CoreLocation regions
    /// for batch setup of region monitoring operations.
    /// 
    /// - Returns: Array of regions ready for `startMonitoring(for:)`
    var clBeaconRegions: [CLBeaconRegion] {
        return map { $0.clBeaconRegion }
    }
}

// MARK: - Debug Support

extension BeaconID {
    /// Short description for debugging and logging
    var shortDescription: String {
        let shortUUID = String(uuid.uuidString.prefix(8))
        if let major = major, let minor = minor {
            return "\(shortUUID):\(major):\(minor)"
        } else if let major = major {
            return "\(shortUUID):\(major):*"
        } else {
            return "\(shortUUID):*:*"
        }
    }
}

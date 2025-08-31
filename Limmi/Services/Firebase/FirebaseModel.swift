//
//  Model.swift
//  Limmi
//
//  Created by ALP on 14.05.2025.
//

import SwiftUI
import Foundation
import FirebaseFirestore
import CoreLocation
import ManagedSettings

// MARK: - Main Rule Model
struct Rule: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var isActive: Bool
    var dateCreated: Date
    var dateModified: Date
    
    // Core components
    var timeRules: [TimeRule]              // Many time rules
    var gpsLocation: GPSLocation           // One GPS location
    var fineLocationRules: [FineLocationRule]  // Many BLE beacon rules
    var blockedTokenIds: [String]          // Reference to BlockedTokenInfo IDs
    var isBlockingEnabled: Bool            // Whether this rule blocks or allows apps
    
    init(name: String, isBlockingEnabled: Bool = true) {
        self.name = name
        self.isActive = true
        self.dateCreated = Date()
        self.dateModified = Date()
        self.timeRules = []
        self.gpsLocation = GPSLocation()
        self.fineLocationRules = []
        self.blockedTokenIds = []
        self.isBlockingEnabled = isBlockingEnabled
    }
    
    /// Checks if this rule is equivalent to another rule, ignoring timestamps and IDs
    /// Used to prevent unnecessary updates when only metadata has changed
    func isEquivalent(to other: Rule) -> Bool {
        return name == other.name &&
               isActive == other.isActive &&
               isBlockingEnabled == other.isBlockingEnabled &&
               timeRules.isEquivalent(to: other.timeRules) &&
               gpsLocation.isEquivalent(to: other.gpsLocation) &&
               fineLocationRules.isEquivalent(to: other.fineLocationRules) &&
               blockedTokenIds == other.blockedTokenIds
    }
}

// MARK: - Time Rules
struct TimeRule: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var startTime: Date                    // Daily start time
    var endTime: Date                      // Daily end time
    var recurrencePattern: RecurrencePattern
    var customInterval: Int?               // For custom patterns
    var daysOfWeek: [Int]?                // [1-7] for weekly
    var daysOfMonth: [Int]?               // [1-31] for monthly
    var startDate: Date                    // Rule activation date
    var endDate: Date?                     // Optional expiration
    var isActive: Bool
    
    init(name: String, startTime: Date, endTime: Date, recurrencePattern: RecurrencePattern) {
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.recurrencePattern = recurrencePattern
        self.startDate = Date()
        self.isActive = true
    }
    
    /// Checks if this time rule is equivalent to another, ignoring ID and creation/modification dates
    func isEquivalent(to other: TimeRule) -> Bool {
        return name == other.name &&
               startTime == other.startTime &&
               endTime == other.endTime &&
               recurrencePattern == other.recurrencePattern &&
               customInterval == other.customInterval &&
               daysOfWeek == other.daysOfWeek &&
               daysOfMonth == other.daysOfMonth &&
               startDate == other.startDate &&
               endDate == other.endDate &&
               isActive == other.isActive
    }
}

enum RecurrencePattern: String, Codable, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom"
        }
    }
}

// MARK: - GPS Location
struct GPSLocation: Codable {
    var latitude: Double
    var longitude: Double
    var radius: Double                     // Radius in meters
    var isActive: Bool
    
    init() {
        self.latitude = 0.0
        self.longitude = 0.0
        self.radius = 100.0                // Default 100m radius
        self.isActive = false
    }
    
    init(latitude: Double, longitude: Double, radius: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isActive = true
    }
    
    /// Checks if this GPS location is equivalent to another
    func isEquivalent(to other: GPSLocation) -> Bool {
        return latitude == other.latitude &&
               longitude == other.longitude &&
               radius == other.radius &&
               isActive == other.isActive
    }
}

// MARK: - Fine Location (BLE Beacon) Rules
struct FineLocationRule: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String
    var beaconId: String                   // Reference to BeaconDevice ID
    var behaviorType: FineLocationBehavior
    var isActive: Bool
    var dateCreated: Date
    
    init(name: String, beaconId: String, behaviorType: FineLocationBehavior) {
        self.name = name
        self.beaconId = beaconId
        self.behaviorType = behaviorType
        self.isActive = true
        self.dateCreated = Date()
    }
    
    /// Checks if this fine location rule is equivalent to another, ignoring ID and creation date
    func isEquivalent(to other: FineLocationRule) -> Bool {
        return name == other.name &&
               beaconId == other.beaconId &&
               behaviorType == other.behaviorType &&
               isActive == other.isActive
    }
}

enum FineLocationBehavior: String, Codable, CaseIterable {
    case allowedIn = "allowed_in"          // Allow when near beacon
    case blockedIn = "blocked_in"          // Block when near beacon
    
    var displayName: String {
        switch self {
        case .allowedIn: return "Allowed Near Beacon"
        case .blockedIn: return "Blocked Near Beacon"
        }
    }
}

// MARK: - Simplified Beacon Device
struct BeaconDevice: Identifiable, Codable, Equatable {
    @DocumentID var documentID: String?
    var name: String
    var uuid: String
    var major: Int
    var minor: Int
    var isActive: Bool
    var dateCreated: Date
    
    var id: String { "\(uuid)-\(major)-\(minor)" }
    
    init(name: String, uuid: String, major: Int, minor: Int) {
        self.name = name
        self.uuid = uuid
        self.major = major
        self.minor = minor
        self.isActive = true
        self.dateCreated = Date()
    }
    
    static func == (lhs: BeaconDevice, rhs: BeaconDevice) -> Bool {
        return lhs.uuid == rhs.uuid && lhs.major == rhs.major && lhs.minor == rhs.minor
    }
    
    /// Checks if this beacon device is equivalent to another, ignoring creation date
    func isEquivalent(to other: BeaconDevice) -> Bool {
        return name == other.name &&
               uuid == other.uuid &&
               major == other.major &&
               minor == other.minor &&
               isActive == other.isActive
    }
}

// MARK: - Enhanced BlockedTokenInfo
struct BlockedTokenInfo: Identifiable, Codable {
    @DocumentID var id: String?
    var name: String                       // Deprecated: Use displayName instead
    var displayName: String                // Localized display name or domain
    var tokenType: String                  // "application", "webDomain", "activityCategory"
    var bundleId: String?                  // Deprecated: Use bundleIdentifier instead  
    var bundleIdentifier: String?          // App bundle identifier (applications only)
    var tokenData: Data
    var dateAdded: Date
    var isActive: Bool
    
    // Legacy initializer for backward compatibility
    init(name: String, tokenType: String, tokenData: Data, bundleId: String? = nil) {
        self.name = name
        self.displayName = name  // Fallback to name for legacy data
        self.tokenType = tokenType
        self.tokenData = tokenData
        self.bundleId = bundleId
        self.bundleIdentifier = bundleId  // Fallback for legacy data
        self.dateAdded = Date()
        self.isActive = true
    }
    
    // Enhanced initializer with new metadata
    init(displayName: String, tokenType: String, tokenData: Data, bundleIdentifier: String? = nil) {
        self.name = displayName  // Keep legacy field populated
        self.displayName = displayName
        self.tokenType = tokenType
        self.tokenData = tokenData
        self.bundleId = bundleIdentifier  // Keep legacy field populated
        self.bundleIdentifier = bundleIdentifier
        self.dateAdded = Date()
        self.isActive = true
    }
    
    /// Checks if this blocked token info is equivalent to another, ignoring ID and date added
    func isEquivalent(to other: BlockedTokenInfo) -> Bool {
        return displayName == other.displayName &&
               tokenType == other.tokenType &&
               bundleIdentifier == other.bundleIdentifier &&
               tokenData == other.tokenData &&
               isActive == other.isActive
    }
}

extension BlockedTokenInfo {
    func decodedApplicationToken() -> ApplicationToken? {
        guard tokenType == "application" else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ApplicationToken.self, from: tokenData)
    }
    
    func decodedWebDomainToken() -> WebDomainToken? {
        guard tokenType == "webDomain" else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(WebDomainToken.self, from: tokenData)
    }
    
    func decodedActivityCategoryToken() -> ActivityCategoryToken? {
        guard tokenType == "activityCategory" else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ActivityCategoryToken.self, from: tokenData)
    }
    
    // MARK: - Static Factory Methods
    
    // MARK: - Legacy Create Methods (for backward compatibility)
    
    static func create(name: String, applicationToken: ApplicationToken, bundleId: String? = nil) -> BlockedTokenInfo? {
        let encoder = JSONEncoder()
        guard let tokenData = try? encoder.encode(applicationToken) else { return nil }
        return BlockedTokenInfo(name: name, tokenType: "application", tokenData: tokenData, bundleId: bundleId)
    }
    
    static func create(name: String, webDomainToken: WebDomainToken) -> BlockedTokenInfo? {
        let encoder = JSONEncoder()
        guard let tokenData = try? encoder.encode(webDomainToken) else { return nil }
        return BlockedTokenInfo(name: name, tokenType: "webDomain", tokenData: tokenData)
    }
    
    static func create(name: String, activityCategoryToken: ActivityCategoryToken) -> BlockedTokenInfo? {
        let encoder = JSONEncoder()
        guard let tokenData = try? encoder.encode(activityCategoryToken) else { return nil }
        return BlockedTokenInfo(name: name, tokenType: "activityCategory", tokenData: tokenData)
    }
    
    static func create(name: String, tokenData: Data, tokenType: String, bundleId: String? = nil) -> BlockedTokenInfo {
        return BlockedTokenInfo(name: name, tokenType: tokenType, tokenData: tokenData, bundleId: bundleId)
    }
    
    // MARK: - Enhanced Create Methods (with metadata extraction)
    
    static func createWithMetadata(applicationToken: ApplicationToken, displayName: String, bundleIdentifier: String) -> BlockedTokenInfo? {
        let encoder = JSONEncoder()
        guard let tokenData = try? encoder.encode(applicationToken) else { return nil }
        return BlockedTokenInfo(displayName: displayName, tokenType: "application", tokenData: tokenData, bundleIdentifier: bundleIdentifier)
    }
    
    static func createWithMetadata(webDomainToken: WebDomainToken, domain: String) -> BlockedTokenInfo? {
        let encoder = JSONEncoder()
        guard let tokenData = try? encoder.encode(webDomainToken) else { return nil }
        return BlockedTokenInfo(displayName: domain, tokenType: "webDomain", tokenData: tokenData, bundleIdentifier: nil)
    }
    
    static func createWithMetadata(activityCategoryToken: ActivityCategoryToken, displayName: String) -> BlockedTokenInfo? {
        let encoder = JSONEncoder()
        guard let tokenData = try? encoder.encode(activityCategoryToken) else { return nil }
        return BlockedTokenInfo(displayName: displayName, tokenType: "activityCategory", tokenData: tokenData, bundleIdentifier: nil)
    }
    
    // MARK: - Validation Methods
    
    func isValid() -> Bool {
        guard !name.isEmpty && !tokenData.isEmpty else { return false }
        
        switch tokenType {
        case "application":
            return decodedApplicationToken() != nil
        case "webDomain":
            return decodedWebDomainToken() != nil
        case "activityCategory":
            return decodedActivityCategoryToken() != nil
        default:
            return false
        }
    }
    
    func hasValidToken() -> Bool {
        return isValid()
    }
    
    // MARK: - Comparison Methods
    
    func isSameToken(as other: BlockedTokenInfo) -> Bool {
        guard tokenType == other.tokenType else { return false }
        
        if tokenType == "application" {
            if let thisBundleId = bundleId, let otherBundleId = other.bundleId {
                return thisBundleId == otherBundleId
            }
        }
        return tokenData == other.tokenData
    }
    
    func matches(applicationToken: ApplicationToken) -> Bool {
        guard tokenType == "application", let decodedToken = decodedApplicationToken() else { return false }
        return decodedToken == applicationToken
    }
    
    func matches(webDomainToken: WebDomainToken) -> Bool {
        guard tokenType == "webDomain", let decodedToken = decodedWebDomainToken() else { return false }
        return decodedToken == webDomainToken
    }
    
    func matches(activityCategoryToken: ActivityCategoryToken) -> Bool {
        guard tokenType == "activityCategory", let decodedToken = decodedActivityCategoryToken() else { return false }
        return decodedToken == activityCategoryToken
    }
    
    func matches(bundleId: String) -> Bool {
        return tokenType == "application" && self.bundleId == bundleId
    }
    
    // MARK: - Update Methods
    
    mutating func updateName(_ newName: String) {
        self.name = newName
    }
    
    mutating func updateApplicationToken(_ newToken: ApplicationToken) -> Bool {
        guard tokenType == "application" else { return false }
        guard let newTokenData = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: false) else { return false }
        self.tokenData = newTokenData
        return true
    }
    
    mutating func updateWebDomainToken(_ newToken: WebDomainToken) -> Bool {
        guard tokenType == "webDomain" else { return false }
        guard let newTokenData = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: false) else { return false }
        self.tokenData = newTokenData
        return true
    }
    
    mutating func updateActivityCategoryToken(_ newToken: ActivityCategoryToken) -> Bool {
        guard tokenType == "activityCategory" else { return false }
        guard let newTokenData = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: false) else { return false }
        self.tokenData = newTokenData
        return true
    }
    
    mutating func updateBundleId(_ newBundleId: String?) {
        guard tokenType == "application" else { return }
        self.bundleId = newBundleId
    }
    
    mutating func setActive(_ active: Bool) {
        self.isActive = active
    }
    
    mutating func toggle() {
        self.isActive.toggle()
    }
    
    // MARK: - Utility Methods
    
    
    func shortDescription() -> String {
        let status = isActive ? "Active" : "Inactive"
        let typeLabel = tokenType.capitalized
        return "\(displayName) (\(typeLabel)) - \(status)"
    }
    
    func debugDescription() -> String {
        return """
        BlockedTokenInfo:
        - ID: \(id ?? "nil")
        - Name: \(name)
        - Token Type: \(tokenType)
        - Bundle ID: \(bundleId ?? "nil")
        - Token Data Size: \(tokenData.count) bytes
        - Date Added: \(dateAdded)
        - Is Active: \(isActive)
        - Valid Token: \(hasValidToken())
        """
    }
    
    // MARK: - Sorting & Filtering Support
    
    static func sortedByName(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        return tokens.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    static func sortedByDateAdded(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        return tokens.sorted { $0.dateAdded < $1.dateAdded }
    }
    
    static func sortedByType(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        return tokens.sorted { $0.tokenType.localizedCaseInsensitiveCompare($1.tokenType) == .orderedAscending }
    }
    
    static func activeTokens(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        return tokens.filter { $0.isActive }
    }
    
    static func inactiveTokens(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        return tokens.filter { !$0.isActive }
    }
    
    static func validTokens(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        return tokens.filter { $0.isValid() }
    }
    
    static func filterByType(_ tokens: [BlockedTokenInfo], type: String) -> [BlockedTokenInfo] {
        return tokens.filter { $0.tokenType == type }
    }
    
    // MARK: - Collection Operations
    
    static func removeDuplicates(_ tokens: [BlockedTokenInfo]) -> [BlockedTokenInfo] {
        var uniqueTokens: [BlockedTokenInfo] = []
        var seenTokens: Set<Data> = []
        var seenBundleIds: Set<String> = []
        
        for token in tokens {
            var isDuplicate = false
            
            if seenTokens.contains(token.tokenData) {
                isDuplicate = true
            }
            
            if let bundleId = token.bundleId, seenBundleIds.contains(bundleId) {
                isDuplicate = true
            }
            
            if !isDuplicate {
                uniqueTokens.append(token)
                seenTokens.insert(token.tokenData)
                if let bundleId = token.bundleId {
                    seenBundleIds.insert(bundleId)
                }
            }
        }
        
        return uniqueTokens
    }
    
    static func findToken(in tokens: [BlockedTokenInfo], byName name: String) -> BlockedTokenInfo? {
        return tokens.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }
    
    static func findToken(in tokens: [BlockedTokenInfo], byBundleId bundleId: String) -> BlockedTokenInfo? {
        return tokens.first { $0.bundleId == bundleId }
    }
    
    static func findToken(in tokens: [BlockedTokenInfo], byApplicationToken token: ApplicationToken) -> BlockedTokenInfo? {
        return tokens.first { $0.matches(applicationToken: token) }
    }
    
    static func findToken(in tokens: [BlockedTokenInfo], byWebDomainToken token: WebDomainToken) -> BlockedTokenInfo? {
        return tokens.first { $0.matches(webDomainToken: token) }
    }
    
    static func findToken(in tokens: [BlockedTokenInfo], byActivityCategoryToken token: ActivityCategoryToken) -> BlockedTokenInfo? {
        return tokens.first { $0.matches(activityCategoryToken: token) }
    }
}

// MARK: - Business Logic Extensions

// MARK: - Rule Extensions
extension Rule {
    /// Creates a rule from individual components
    static func createFromComponents(
        name: String,
        beaconId: String,
        gpsLocation: GPSLocation,
        blockedTokenIds: [String],
        isBlockingEnabled: Bool
    ) -> Rule {
        var rule = Rule(name: name, isBlockingEnabled: isBlockingEnabled)
        rule.gpsLocation = gpsLocation
        rule.blockedTokenIds = blockedTokenIds
        
        // Create fine location rule for the beacon
        let fineLocationRule = FineLocationRule(
            name: "Beacon Rule for \(name)",
            beaconId: beaconId,
            behaviorType: isBlockingEnabled ? .blockedIn : .allowedIn
        )
        rule.fineLocationRules = [fineLocationRule]
        
        return rule
    }
    
    /// Returns all beacon IDs referenced by this rule
    var referencedBeaconIds: [String] {
        return fineLocationRules.map { $0.beaconId }
    }
    
    /// Returns true if this rule references the specified beacon
    func referencesBeacon(id: String) -> Bool {
        return fineLocationRules.contains { $0.beaconId == id }
    }
    
    /// Returns true if this rule references the specified token
    func referencesToken(id: String) -> Bool {
        return blockedTokenIds.contains(id)
    }
    
    /// Returns true if this rule has any active components
    var hasActiveComponents: Bool {
        return gpsLocation.isActive || 
               fineLocationRules.contains { $0.isActive } ||
               timeRules.contains { $0.isActive }
    }
    
    /// Updates the rule's modification date
    mutating func touch() {
        dateModified = Date()
    }
}

// MARK: - FineLocationRule Extensions
extension FineLocationRule {
    /// Note: init method is already defined in the struct above
    
    /// Returns true if this rule allows apps when near the beacon
    var allowsWhenNear: Bool {
        return behaviorType == .allowedIn
    }
    
    /// Returns true if this rule blocks apps when near the beacon
    var blocksWhenNear: Bool {
        return behaviorType == .blockedIn
    }
}

// MARK: - GPSLocation Extensions
extension GPSLocation {
    /// Note: init method is already defined in the struct above
    
    /// Returns a CLLocation representation
    var clLocation: CLLocation {
        return CLLocation(latitude: latitude, longitude: longitude)
    }
    
    /// Returns true if the location has valid coordinates
    var hasValidCoordinates: Bool {
        return latitude != 0.0 || longitude != 0.0
    }
    
    /// Returns the distance from another GPS location in meters
    func distance(to other: GPSLocation) -> Double {
        let location1 = CLLocation(latitude: latitude, longitude: longitude)
        let location2 = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return location1.distance(from: location2)
    }
    
    /// Returns true if another location is within this location's radius
    func contains(_ other: GPSLocation) -> Bool {
        return distance(to: other) <= radius
    }
}

// MARK: - BeaconDevice Extensions
extension BeaconDevice {
    /// Note: init method is already defined in the struct above
    
    /// Returns a CLBeaconRegion for monitoring
    var clBeaconRegion: CLBeaconRegion? {
        guard let uuid = UUID(uuidString: uuid) else { return nil }
        return CLBeaconRegion(uuid: uuid, major: CLBeaconMajorValue(major), minor: CLBeaconMinorValue(minor), identifier: name)
    }
    
    /// Returns true if this beacon matches the given parameters
    func matches(uuid: String, major: Int? = nil, minor: Int? = nil) -> Bool {
        guard self.uuid.lowercased() == uuid.lowercased() else { return false }
        
        if let major = major, self.major != major { return false }
        if let minor = minor, self.minor != minor { return false }
        
        return true
    }
    
    /// Returns a display string for the beacon
    var displayString: String {
        return "\(name) (UUID: \(uuid.prefix(8))..., Major: \(major), Minor: \(minor))"
    }
}

// MARK: - BlockedTokenInfo Convenience Extensions
extension BlockedTokenInfo {
    /// Creates a BlockedTokenInfo from an ApplicationToken
    init(from applicationToken: ApplicationToken, name: String) {
        let encoder = JSONEncoder()
        let tokenData = (try? encoder.encode(applicationToken)) ?? Data()
        self.init(name: name, tokenType: "application", tokenData: tokenData)
    }
    
    /// Creates a BlockedTokenInfo from a WebDomainToken
    init(from webDomainToken: WebDomainToken, name: String) {
        let encoder = JSONEncoder()
        let tokenData = (try? encoder.encode(webDomainToken)) ?? Data()
        self.init(name: name, tokenType: "webDomain", tokenData: tokenData)
    }
    
    /// Creates a BlockedTokenInfo from an ActivityCategoryToken
    init(from activityCategoryToken: ActivityCategoryToken, name: String) {
        let encoder = JSONEncoder()
        let tokenData = (try? encoder.encode(activityCategoryToken)) ?? Data()
        self.init(name: name, tokenType: "activityCategory", tokenData: tokenData)
    }
    
    /// Returns a display string for the token
    var displayString: String {
        switch tokenType {
        case "application":
            if let bundleId = bundleId {
                return "\(name) (\(bundleId))"
            }
            return name
        case "webDomain":
            return "\(name) (Website)"
        case "activityCategory":
            return "\(name) (Category)"
        default:
            return name
        }
    }
}

// MARK: - Array Extensions for Equivalence Checking

extension Array where Element == TimeRule {
    /// Checks if this array of TimeRules is equivalent to another array
    func isEquivalent(to other: [TimeRule]) -> Bool {
        guard count == other.count else { return false }
        
        // Sort both arrays by a stable criteria (name, then start time) for comparison
        let sortedSelf = sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.startTime < rhs.startTime
            }
            return lhs.name < rhs.name
        }
        
        let sortedOther = other.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.startTime < rhs.startTime
            }
            return lhs.name < rhs.name
        }
        
        return zip(sortedSelf, sortedOther).allSatisfy { $0.isEquivalent(to: $1) }
    }
}

extension Array where Element == FineLocationRule {
    /// Checks if this array of FineLocationRules is equivalent to another array
    func isEquivalent(to other: [FineLocationRule]) -> Bool {
        guard count == other.count else { return false }
        
        // Sort both arrays by a stable criteria (beacon ID, then name) for comparison
        let sortedSelf = sorted { lhs, rhs in
            if lhs.beaconId == rhs.beaconId {
                return lhs.name < rhs.name
            }
            return lhs.beaconId < rhs.beaconId
        }
        
        let sortedOther = other.sorted { lhs, rhs in
            if lhs.beaconId == rhs.beaconId {
                return lhs.name < rhs.name
            }
            return lhs.beaconId < rhs.beaconId
        }
        
        return zip(sortedSelf, sortedOther).allSatisfy { $0.isEquivalent(to: $1) }
    }
}

extension Array where Element == BeaconDevice {
    /// Checks if this array of BeaconDevices is equivalent to another array
    func isEquivalent(to other: [BeaconDevice]) -> Bool {
        guard count == other.count else { return false }
        
        // Sort both arrays by ID for comparison
        let sortedSelf = sorted { $0.id < $1.id }
        let sortedOther = other.sorted { $0.id < $1.id }
        
        return zip(sortedSelf, sortedOther).allSatisfy { $0.isEquivalent(to: $1) }
    }
}

extension Array where Element == BlockedTokenInfo {
    /// Checks if this array of BlockedTokenInfo is equivalent to another array
    func isEquivalent(to other: [BlockedTokenInfo]) -> Bool {
        guard count == other.count else { return false }
        
        // Sort both arrays by name for comparison
        let sortedSelf = sorted { $0.name < $1.name }
        let sortedOther = other.sorted { $0.name < $1.name }
        
        return zip(sortedSelf, sortedOther).allSatisfy { $0.isEquivalent(to: $1) }
    }
}

extension Array where Element == Rule {
    /// Checks if this array of Rules is equivalent to another array
    func isEquivalent(to other: [Rule]) -> Bool {
        guard count == other.count else { return false }
        
        // Sort both arrays by name for comparison
        let sortedSelf = sorted { $0.name < $1.name }
        let sortedOther = other.sorted { $0.name < $1.name }
        
        return zip(sortedSelf, sortedOther).allSatisfy { $0.isEquivalent(to: $1) }
    }
}

// Clean rule-based data model - no legacy support

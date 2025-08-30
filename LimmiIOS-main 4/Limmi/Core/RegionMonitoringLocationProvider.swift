//
//  RegionMonitoringLocationProvider.swift
//  Limmi
//
//  Purpose: Battery-efficient location provider using CoreLocation region monitoring
//  Dependencies: Foundation, CoreLocation, Combine
//  Related: LocationProvider.swift, BlockingEngine.swift, GPS location rules
//

import Foundation
import CoreLocation
import Combine
import os.log

/// Region monitoring implementation of LocationProvider using CoreLocation geofencing.
///
/// This implementation uses CoreLocation's region monitoring capabilities instead of
/// continuous location updates, providing significant battery life improvements for
/// geofencing scenarios.
///
/// ## Key Advantages
/// - **Battery Efficiency**: Only triggers when entering/exiting defined regions
/// - **Background Operation**: Works reliably in background without constant GPS
/// - **System Integration**: Leverages iOS's efficient region monitoring
/// - **Precision**: Triggers based on actual boundary crossings, not distance filtering
///
/// ## Region Management
/// - Automatically creates circular regions around GPS rule locations
/// - Monitors up to 20 regions simultaneously (iOS limit)
/// - Handles region registration/deregistration dynamically
/// - Provides entry/exit events for immediate rule evaluation
///
/// ## Location Updates
/// - Requests location only when entering/exiting regions
/// - Provides accurate location at boundary crossing moments
/// - Falls back to standard location updates when no regions are active
///
/// ## Background Behavior
/// - Region monitoring works in background with "Always" authorization
/// - System handles monitoring even when app is terminated
/// - Launches app in background for region events
///
/// ## Thread Safety
/// - Must be accessed from main thread due to CLLocationManagerDelegate
/// - Region events are published on main thread for UI integration
///
/// - Since: 1.0
final class RegionMonitoringLocationProvider: NSObject, LocationProvider {
    
    // MARK: - Properties
    
    private let locationManager = CLLocationManager()
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    private let regionEventSubject = PassthroughSubject<RegionEvent, Never>()
    private let logger: UnifiedLogger
    
    /// Set of regions currently being monitored
    private var monitoredRegions: Set<CLCircularRegion> = []
    
    /// Cache of the last known location
    private var _currentLocation: CLLocation?
    
    /// Maximum number of regions that can be monitored simultaneously
    private let maxRegions = 20
    
    // MARK: - LocationProvider Implementation
    
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    var currentLocation: CLLocation? {
        _currentLocation ?? locationManager.location
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    /// Publisher for region entry/exit events
    var regionEventPublisher: AnyPublisher<RegionEvent, Never> {
        regionEventSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    override init() {
        logger = UnifiedLogger(
            fileLogger: .shared,
            osLogger: Logger(subsystem: "com.limmi.app", category: "RegionMonitoringLocationProvider")
        )
        super.init()
        locationManager.delegate = self
        logger.debug("RegionMonitoringLocationProvider: Delegate successfully assigned to \(self)")
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 3.0
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = false // More discreet for region monitoring
    }
    
    // Helper function to format region details for logging
    private func formatRegionDetails(_ regions: Set<CLRegion>) -> String {
        return regions.map { region in
            let delegate = locationManager.delegate != nil ? "ok" : "no"
            if let beaconRegion = region as? CLBeaconRegion {
                return "\(region.identifier) [Beacon, delegate:\(delegate), entry:\(beaconRegion.notifyOnEntry), exit:\(beaconRegion.notifyOnExit)]"
            } else if let circularRegion = region as? CLCircularRegion {
                return "\(region.identifier) [GPS, delegate:\(delegate), entry:\(circularRegion.notifyOnEntry), exit:\(circularRegion.notifyOnExit)]"
            } else {
                return "\(region.identifier) [Unknown, delegate:\(delegate)]"
            }
        }.joined(separator: ", ")
    }
    
    // MARK: - LocationProvider Implementation
    
    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
    
    func startLocationUpdates() { // ¤V¤ Is this really needed if we are a reactive only flow? Rules are updated -> The monitoring is updated, no batch start.
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        
        // Start region monitoring if regions are configured
        /*if !monitoredRegions.isEmpty {
            startRegionMonitoring()
        } else {
            logger.info("RegionMonitoringLocationProvider: No region to monitor, falling back to standard location updates")
            // Fall back to standard location updates if no regions
            locationManager.startUpdatingLocation()
        }*/
    }
    
    func stopLocationUpdates() {
        
        locationManager.stopUpdatingLocation()
        stopRegionMonitoring()
    }
    
    // MARK: - Region Management
    
    /// Adds a circular region for monitoring
    /// - Parameters:
    ///   - center: Geographic center of the region
    ///   - radius: Radius in meters (minimum 1m, maximum 400m for best performance)
    ///   - identifier: Unique identifier for the region
    func addRegion(center: CLLocationCoordinate2D, radius: CLLocationDistance, identifier: String) {
        guard monitoredRegions.count < maxRegions else {
            logger.error("RegionMonitoringLocationProvider: Cannot add region - maximum limit reached")
            return
        }
        
        let region = CLCircularRegion(
            center: center,
            radius: min(max(radius, 1.0), 400.0), // Clamp radius to valid range
            identifier: identifier
        )
        
        region.notifyOnEntry = true
        region.notifyOnExit = true
        
        monitoredRegions.insert(region)
        
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            logger.debug("RegionMonitoringLocationProvider: Starting monitoring for region \(region.identifier)")
            locationManager.startMonitoring(for: region)
        }
    }
    
    /// Removes a monitored region
    /// - Parameter identifier: Unique identifier of the region to remove
    func removeRegion(identifier: String) {
        if let region = monitoredRegions.first(where: { $0.identifier == identifier }) {
            logger.debug("RegionMonitoringLocationProvider: Stopping monitoring for region \(region.identifier)")
            monitoredRegions.remove(region)
            locationManager.stopMonitoring(for: region)
        }
    }
    
    /// Removes all monitored regions
    func removeAllRegions() {
        // Get GPS regions that are actually registered with CLLocationManager (handles app crash recovery)
        let allSystemRegions = locationManager.monitoredRegions
        let systemGPSRegions = allSystemRegions.compactMap { $0 as? CLCircularRegion }
        
        // Remove all GPS regions from CLLocationManager (including orphaned ones from crashes)
        for gpsRegion in systemGPSRegions {
            logger.debug("RegionMonitoringLocationProvider: Stopping monitoring for GPS region \(gpsRegion.identifier)")
            locationManager.stopMonitoring(for: gpsRegion)
        }
        
        // Clear internal tracking
        monitoredRegions.removeAll()
        
        let allSystemRegionsAfter = locationManager.monitoredRegions
        logger.debug("RegionMonitoringLocationProvider: All system regions after cleanup: \(formatRegionDetails(allSystemRegionsAfter))")
    }
    
    /// Updates regions based on GPS rules
    /// - Parameter gpsRules: Array of GPS location rules to monitor
    func updateRegions(from gpsRules: [GPSLocationRule]) {
        // Remove existing regions
        removeAllRegions() // ¤V¤ Should I check if the rule really changed before? But I also want to make sure I have the right delegate set (but is that really something?)
        
        // Add new regions from rules
        for rule in gpsRules {
            addRegion(
                center: CLLocationCoordinate2D(
                    latitude: rule.latitude,
                    longitude: rule.longitude
                ),
                radius: rule.radius,
                identifier: rule.identifier
            )
        }
    }
    
    /// Requests the current state of a monitored region
    /// - Parameter identifier: Region identifier to check
    func requestRegionState(identifier: String) {
        if let region = monitoredRegions.first(where: { $0.identifier == identifier }) {
            locationManager.requestState(for: region)
        }
    }
    
    // MARK: - Private Methods
    
    private func startRegionMonitoring() {
        logger.debug("RegionMonitoringLocationProvider: Current monitored regions before batch start: \(formatRegionDetails(locationManager.monitoredRegions))")
        for region in monitoredRegions {
            logger.debug("RegionMonitoringLocationProvider: Starting monitoring (batch) for region \(region.identifier)")
            locationManager.startMonitoring(for: region)
        }
        logger.debug("RegionMonitoringLocationProvider: Current monitored regions after batch start: \(formatRegionDetails(locationManager.monitoredRegions))")
    }
    
    private func stopRegionMonitoring() {
        logger.debug("RegionMonitoringLocationProvider: stopRegionMonitoring called")
        
        // Get GPS regions that are actually registered with CLLocationManager
        let allSystemRegions = locationManager.monitoredRegions
        let systemGPSRegions = allSystemRegions.compactMap { $0 as? CLCircularRegion }
        
        logger.debug("RegionMonitoringLocationProvider: All system regions before batch stop: \(formatRegionDetails(allSystemRegions))")
        logger.debug("RegionMonitoringLocationProvider: System GPS regions to stop: \(systemGPSRegions.map { $0.identifier })")
        logger.debug("RegionMonitoringLocationProvider: Internal GPS regions tracked: \(monitoredRegions.map { $0.identifier })")

        // Stop all GPS regions from CLLocationManager (including orphaned ones)
        for gpsRegion in systemGPSRegions {
            logger.debug("RegionMonitoringLocationProvider: Stopping monitoring (batch) for GPS region \(gpsRegion.identifier)")
            locationManager.stopMonitoring(for: gpsRegion)
        }
        
        let allSystemRegionsAfter = locationManager.monitoredRegions
        logger.debug("RegionMonitoringLocationProvider: All system regions after batch stop: \(formatRegionDetails(allSystemRegionsAfter))")
    }
    
    private func updateCurrentLocation(_ location: CLLocation) {
        _currentLocation = location
        locationSubject.send(location)
    }
}

// MARK: - CLLocationManagerDelegate

extension RegionMonitoringLocationProvider: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        logger.debug("RegionMonitoringLocationProvider: didUpdateLocations")
        guard let location = locations.last else { return }
        updateCurrentLocation(location)	
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("RegionMonitoringLocationProvider error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startLocationUpdates()
        case .denied, .restricted:
            stopLocationUpdates()
        default:
            break
        }
    }
    
    // MARK: - Region Monitoring Delegate Methods
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        logger.debug("RegionMonitoringLocationProvider: didEnterRegion \(region) - delegate: \(self), manager: \(manager)")
        
        guard let circularRegion = region as? CLCircularRegion else { return }
        
        // Request current location for accurate position
        manager.requestLocation()
        
        // Emit region event
        regionEventSubject.send(.entered(circularRegion))
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        logger.debug("RegionMonitoringLocationProvider: didExitRegion \(region) - delegate: \(self), manager: \(manager)")
        
        guard let circularRegion = region as? CLCircularRegion else { return }
        
        // Request current location for accurate position
        manager.requestLocation()
        
        // Emit region event
        regionEventSubject.send(.exited(circularRegion))
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        
        // filter out CLBeaconRegion events which are handled elsewhere
        guard let circularRegion = region as? CLCircularRegion else { return }
        
        logger.debug("RegionMonitoringLocationProvider: didDetermineState \(state.rawValue) for \(region) - delegate: \(self), manager: \(manager)")
        
        // Request current location for accurate position
        manager.requestLocation()
        
        switch state {
        case .inside:
            regionEventSubject.send(.inside(circularRegion))
        case .outside:
            regionEventSubject.send(.outside(circularRegion))
        case .unknown:
            regionEventSubject.send(.unknown(circularRegion))
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        if let region = region as? CLCircularRegion {
            regionEventSubject.send(.monitoringFailed(region, error))
        }
        logger.error("Region monitoring failed: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }
        regionEventSubject.send(.monitoringStarted(circularRegion))
        
        // Request the initial state of the region
        manager.requestState(for: region)
    }
}

// MARK: - Supporting Types

/// GPS location rule for region monitoring
struct GPSLocationRule {
    let identifier: String
    let latitude: Double
    let longitude: Double
    let radius: Double
    let isActive: Bool
    
    init(identifier: String, latitude: Double, longitude: Double, radius: Double, isActive: Bool = true) {
        self.identifier = identifier
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        self.isActive = isActive
    }
}

/// Region monitoring events
enum RegionEvent {
    case entered(CLCircularRegion)
    case exited(CLCircularRegion)
    case inside(CLCircularRegion)
    case outside(CLCircularRegion)
    case unknown(CLCircularRegion)
    case monitoringStarted(CLCircularRegion)
    case monitoringFailed(CLCircularRegion, Error)
    
    var region: CLCircularRegion {
        switch self {
        case .entered(let region), .exited(let region), .inside(let region), 
             .outside(let region), .unknown(let region), .monitoringStarted(let region):
            return region
        case .monitoringFailed(let region, _):
            return region
        }
    }
    
    var isInsideRegion: Bool {
        switch self {
        case .entered, .inside:
            return true
        case .exited, .outside:
            return false
        case .unknown, .monitoringStarted, .monitoringFailed:
            return false
        }
    }
}

// MARK: - Extensions

extension RegionMonitoringLocationProvider {
    /// Convenience method to check if currently inside any monitored region
    func isInsideAnyRegion() -> Bool {
        return locationManager.monitoredRegions.contains { region in
            // This would require checking state, but that's async
            // Better to track state internally or use region events
            return false
        }
    }
    
    /// Returns identifiers of all currently monitored regions
    var monitoredRegionIdentifiers: [String] {
        return monitoredRegions.map { $0.identifier }
    }
    
    /// Checks if a specific region is being monitored
    func isMonitoring(identifier: String) -> Bool {
        return monitoredRegions.contains { $0.identifier == identifier }
    }
    
    /// Updates regions from Rule objects (convenience method for BlockingEngine integration)
    func updateRegions(from rules: [Rule]) {
        let gpsRules = rules.compactMap { rule -> GPSLocationRule? in
            guard rule.isActive && rule.gpsLocation.isActive else { return nil }
            
            return GPSLocationRule(
                identifier: rule.id ?? UUID().uuidString,
                latitude: rule.gpsLocation.latitude,
                longitude: rule.gpsLocation.longitude,
                radius: rule.gpsLocation.radius,
                isActive: rule.isActive
            )
        }
        
        logger.debug("RegionMonitoringLocationProvider: Updating regions to \(gpsRules.count) GPS rules")
        updateRegions(from: gpsRules)
    }
    
}

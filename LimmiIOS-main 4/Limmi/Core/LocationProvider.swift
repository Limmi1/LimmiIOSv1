//
//  LocationProvider.swift
//  Limmi
//
//  Purpose: Location services abstraction for GPS-based rule evaluation
//  Dependencies: Foundation, CoreLocation, Combine
//  Related: BlockingEngine.swift, GPS location rules, CoreLocationProvider implementation
//

import Foundation
import CoreLocation
import Combine

/// Protocol abstraction for location services in the blocking system.
///
/// This protocol provides a clean interface for location operations, enabling:
/// - Dependency injection for testability
/// - Flexibility to switch between location providers
/// - Clean separation between business logic and CoreLocation APIs
///
/// ## Usage in Blocking Engine
/// Location data is used for GPS-based rule evaluation:
/// - Rule specifies GPS coordinates and radius
/// - Current location is compared against rule boundaries
/// - Location changes trigger rule re-evaluation
///
/// ## Implementation Strategy
/// - **Production**: CoreLocationProvider using actual GPS hardware
/// - **Testing**: MockLocationProvider with controllable location data
/// - **Future**: Could support additional providers (network location, etc.)
///
/// ## Performance Considerations
/// - Uses distance filtering to minimize unnecessary updates
/// - Balances accuracy needs with battery life
/// - Integrates with app background execution limitations
///
/// - Since: 1.0
protocol LocationProvider {
    /// Publisher that emits location updates for reactive rule evaluation.
    /// 
    /// Emits CLLocation objects whenever the device location changes significantly.
    /// Used by blocking engine to trigger GPS-based rule evaluation.
    var locationPublisher: AnyPublisher<CLLocation, Never> { get }
    
    /// Most recent location reading, if available.
    /// 
    /// May be nil if location services haven't provided a reading yet
    /// or if location access is denied.
    var currentLocation: CLLocation? { get }
    
    /// Current CoreLocation authorization status.
    /// 
    /// GPS-based rules require .authorizedWhenInUse or .authorizedAlways.
    var authorizationStatus: CLAuthorizationStatus { get }
    
    /// Requests location authorization using progressive escalation.
    /// 
    /// Implements the standard iOS pattern: first requests "When In Use",
    /// then escalates to "Always" for background operation.
    func requestAuthorization()
    
    /// Starts continuous location monitoring.
    /// 
    /// Begins publishing location updates via locationPublisher.
    /// Requires appropriate authorization to succeed.
    func startLocationUpdates()
    
    /// Stops location monitoring to conserve battery.
    /// 
    /// Ceases location updates and publisher emissions.
    func stopLocationUpdates()
    
    /// Updates monitored regions based on active rules.
    /// 
    /// For providers that support region monitoring (like RegionMonitoringLocationProvider),
    /// this updates the set of GPS regions being monitored. For basic providers, this is a no-op.
    func updateRegions(from rules: [Rule])
}

/// Production implementation of LocationProvider using CoreLocation framework.
///
/// This class wraps CoreLocation's CLLocationManager to provide location services
/// for GPS-based rule evaluation. Configured for balanced accuracy and battery life.
///
/// ## Configuration
/// - **Accuracy**: kCLLocationAccuracyNearestTenMeters (good balance)
/// - **Distance Filter**: 10 meters (reduces update frequency)
/// - **Authorization**: Progressive escalation (When In Use → Always)
///
/// ## Background Behavior
/// - Location updates work in background with "Always" authorization
/// - Updates may be throttled by iOS to conserve battery
/// - Distance filtering prevents excessive rule evaluation
///
/// ## Thread Safety
/// - Must be accessed from main thread due to CLLocationManagerDelegate
/// - Location updates are published on main thread for UI integration
///
/// - Since: 1.0
final class CoreLocationProvider: NSObject, LocationProvider, ObservableObject {
    
    // MARK: - Properties
    
    private let locationManager = CLLocationManager()
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    var currentLocation: CLLocation? {
        locationManager.location
    }
    
    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        locationManager.distanceFilter = 10.0
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
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
    
    func startLocationUpdates() {
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            return
        }
        locationManager.startUpdatingLocation()
    }
    
    func stopLocationUpdates() {
        locationManager.stopUpdatingLocation()
    }
    
    func updateRegions(from rules: [Rule]) {
        // CoreLocationProvider doesn't support region monitoring - no-op
        // GPS rules will be evaluated against current location instead
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationProvider: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationSubject.send(location)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Handle location errors - could emit error events in future
        print("Location error: \(error.localizedDescription)")
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
}

/// Test implementation of LocationProvider with controllable location
final class TestLocationProvider: LocationProvider {
    
    // MARK: - Properties
    
    private let locationSubject = PassthroughSubject<CLLocation, Never>()
    
    var locationPublisher: AnyPublisher<CLLocation, Never> {
        locationSubject.eraseToAnyPublisher()
    }
    
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    
    // MARK: - Test Controls
    
    func setLocation(_ location: CLLocation) {
        currentLocation = location
        locationSubject.send(location)
    }
    
    func setAuthorizationStatus(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
    }
    
    // MARK: - LocationProvider Implementation
    
    func requestAuthorization() {
        // Test implementation - no-op
    }
    
    func startLocationUpdates() {
        // Test implementation - no-op
    }
    
    func stopLocationUpdates() {
        // Test implementation - no-op
    }
    
    func updateRegions(from rules: [Rule]) {
        // Test implementation - no-op
        // Could be extended to track which regions would be monitored for testing
    }
}

// MARK: - Convenience Extensions

extension LocationProvider {
    /// Checks if location services are available and authorized
    var isLocationAvailable: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    /// Returns the distance between current location and a target location
    func distance(to target: CLLocation) -> CLLocationDistance? {
        guard let current = currentLocation else { return nil }
        return current.distance(from: target)
    }
}

// MARK: - Location Event Types

/// Events that can be emitted by location providers
enum LocationEvent {
    case locationUpdated(CLLocation)
    case authorizationChanged(CLAuthorizationStatus)
    case error(Error)
}

/// Extended LocationProvider protocol for event-driven architecture
protocol LocationEventProvider: LocationProvider {
    var eventPublisher: AnyPublisher<LocationEvent, Never> { get }
}

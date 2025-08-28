//
//  BeaconMonitorProtocol.swift
//  Limmi
//
//  Purpose: Protocol abstraction for beacon monitoring with test and production implementations
//  Dependencies: Foundation, CoreLocation, Combine, BeaconSignalProcessor
//  Related: BeaconEvent.swift, BeaconID.swift, BeaconMonitor.swift (legacy)
//

import Foundation
import CoreLocation
import Combine
import os

/// Protocol abstraction for beacon monitoring services.
///
/// This protocol provides a clean abstraction for beacon monitoring operations,
/// enabling dependency injection, testability, and flexibility in monitoring strategies.
/// Uses dual-manager architecture for reliable beacon detection.
///
/// ## Implementation Strategy
/// - **Production**: CoreLocationBeaconMonitor using separate managers for region and RSSI monitoring
/// - **Testing**: TestBeaconMonitor with event simulation capabilities
/// - **Future**: Could support additional backends (external SDKs, mock data)
///
/// ## Dual-Manager Architecture
/// The implementation uses separate CLLocationManager instances because:
/// - Combining region monitoring and RSSI ranging in one manager causes conflicts
/// - Region monitoring provides reliable entry/exit events
/// - RSSI ranging provides precise signal strength when inside regions
/// - Better reliability and performance separation
///
/// ## Event-Driven Architecture
/// All monitoring results are delivered via Combine publishers, enabling reactive
/// programming patterns and loose coupling between monitoring and business logic.
///
/// ## Thread Safety
/// Implementations should be thread-safe and handle CoreLocation's delegation
/// requirements appropriately (typically MainActor for UI integration).
///
/// - Since: 1.0
protocol BeaconMonitorProtocol {
    /// Updates the set of beacons to monitor.
    /// 
    /// Replaces the current monitoring targets with the provided set.
    /// If monitoring is active, stops current operations and starts monitoring new targets.
    /// 
    /// - Parameter beacons: Set of BeaconID objects to monitor
    func setMonitoredBeacons(_ beacons: Set<BeaconID>)
    
    /// Starts beacon monitoring for the configured beacon set.
    /// 
    /// Initiates region monitoring and RSSI ranging as needed.
    /// Requires location authorization to succeed.
    func startMonitoring()
    
    /// Stops all beacon monitoring operations.
    /// 
    /// Cancels region monitoring, RSSI ranging, and cleanup timers.
    /// Uses locationManager's internal lists to ensure complete cleanup.
    /// Does not change the monitored beacon set.
    func stopMonitoring()
    
    /// Publisher that emits beacon monitoring events.
    /// 
    /// Publishes all beacon events including detection, loss, region changes,
    /// errors, and authorization status changes. Never fails, errors are
    /// delivered as .error events.
    var eventPublisher: AnyPublisher<BeaconEvent, Never> { get }
    
    /// Configuration parameters for monitoring behavior.
    /// 
    /// Allows customization of region monitoring, signal processing,
    /// and timeout values. Changes take effect on next monitoring start.
    var configuration: BeaconMonitoringConfig { get set }
    
    /// Set of beacons currently configured for monitoring.
    /// 
    /// May differ from actively monitored beacons if monitoring is stopped.
    var monitoredBeacons: Set<BeaconID> { get }
    
    /// Current CoreLocation authorization status.
    /// 
    /// Monitoring requires .authorizedWhenInUse or .authorizedAlways.
    var authorizationStatus: CLAuthorizationStatus { get }
    
    /// Requests location authorization for beacon monitoring.
    /// 
    /// Implements progressive authorization: first requests "When In Use",
    /// then escalates to "Always" for background monitoring.
    func requestAuthorization()
}

/// Default implementation providing common functionality
extension BeaconMonitorProtocol {
    /// Checks if location services are available
    var isLocationAvailable: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }
    
    /// Convenience method to monitor a single beacon
    func setMonitoredBeacon(_ beacon: BeaconID) {
        setMonitoredBeacons([beacon])
    }
    
    /// Convenience method to add a beacon to monitoring
    func addMonitoredBeacon(_ beacon: BeaconID) {
        var beacons = monitoredBeacons
        beacons.insert(beacon)
        setMonitoredBeacons(beacons)
    }
    
    /// Convenience method to remove a beacon from monitoring
    func removeMonitoredBeacon(_ beacon: BeaconID) {
        var beacons = monitoredBeacons
        beacons.remove(beacon)
        setMonitoredBeacons(beacons)
    }
}

/// Test implementation of BeaconMonitorProtocol
final class TestBeaconMonitor: BeaconMonitorProtocol {
    
    // MARK: - Properties
    
    private let eventSubject = PassthroughSubject<BeaconEvent, Never>()
    
    var eventPublisher: AnyPublisher<BeaconEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    var configuration = BeaconMonitoringConfig.default
    var monitoredBeacons: Set<BeaconID> = []
    var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    
    private var isMonitoring = false
    
    // MARK: - BeaconMonitorProtocol Implementation
    
    func setMonitoredBeacons(_ beacons: Set<BeaconID>) {
        monitoredBeacons = beacons
        if isMonitoring {
            eventSubject.send(.monitoringStarted(beacons))
        }
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        eventSubject.send(.monitoringStarted(monitoredBeacons))
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        eventSubject.send(.monitoringStopped)
    }
    
    func requestAuthorization() {
        // Test implementation - no-op
    }
    
    // MARK: - Test Helper Methods
    
    func simulateBeaconDetected(_ beaconID: BeaconID, rssi: Int) {
        eventSubject.send(.beaconDetected(beaconID, rssi: rssi))
        eventSubject.send(.proximityChanged(beaconID, proximity: BeaconProximity(from: rssi)))
    }
    
    func simulateBeaconLost(_ beaconID: BeaconID) {
        eventSubject.send(.beaconLost(beaconID))
    }
    
    func simulateRegionEntered(_ beaconID: BeaconID) {
        eventSubject.send(.regionEntered(beaconID))
    }
    
    func simulateRegionExited(_ beaconID: BeaconID) {
        eventSubject.send(.regionExited(beaconID))
    }
    
    func simulateError(_ error: BeaconMonitoringError) {
        eventSubject.send(.error(error))
    }
    
    func simulateAuthorizationChanged(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        eventSubject.send(.authorizationChanged(status))
    }
    
    func simulateNoBeacon(_ constraint: CLBeaconIdentityConstraint) {
        eventSubject.send(.noBeacon(constraint))
    }
    
    func simulateMissingBeacon(_ beaconID: BeaconID) {
        eventSubject.send(.missingBeacon(beaconID))
    }
}

// MARK: - Internal Managers

/// Protocol for region monitoring event delegation
protocol RegionMonitoringDelegate: AnyObject {
    func regionManager(_ manager: RegionMonitoringManager, didReceiveEvent event: BeaconEvent)
}

/// Internal manager for region monitoring (entry/exit detection)
final class RegionMonitoringManager: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    weak var delegate: RegionMonitoringDelegate? {
        didSet {
            logger.debug("RegionMonitoringDelegate set: \(delegate != nil)")
        }
    }
    private let logger: UnifiedLogger
    
    init(logger: UnifiedLogger) {
        self.logger = logger
        super.init()
        logger.debug("RegionMonitoringManager: Creating delegate assignment for CLLocationManager")
        locationManager.delegate = self
        logger.debug("RegionMonitoringManager: Delegate successfully assigned to \(self)")
        logger.debug("RegionMonitoringManager initialized: \(self)")
        assert(Thread.isMainThread, "CLLocationManagerDelegate must be called on the main thread")
    }
    
    deinit {
        logger.debug("RegionMonitoringManager deinit: \(self)")
    }
    
    // Helper function to format region details for logging
    private func formatRegionDetails(_ regions: Set<CLRegion>) -> String {
        return regions.map { region in
            let delegate = locationManager.delegate != nil ? "Y" : "N"
            if let beaconRegion = region as? CLBeaconRegion {
                return "\(region.identifier) [Beacon, delegate:\(delegate), entry:\(beaconRegion.notifyOnEntry), exit:\(beaconRegion.notifyOnExit)]"
            } else if let circularRegion = region as? CLCircularRegion {
                return "\(region.identifier) [GPS, delegate:\(delegate), entry:\(circularRegion.notifyOnEntry), exit:\(circularRegion.notifyOnExit)]"
            } else {
                return "\(region.identifier) [Unknown, delegate:\(delegate)]"
            }
        }.joined(separator: ", ")
    }
    
    func startMonitoring(for beaconIDs: Set<BeaconID>) {
        logger.debug("RegionMonitoringManager: Starting monitoring for \(beaconIDs.count) beacons")
        
        // Only stop beacon regions that this manager is responsible for
        let currentBeaconRegions = locationManager.monitoredRegions.compactMap { $0 as? CLBeaconRegion }
        logger.debug("RegionMonitoringManager: Current beacon regions before stop: \(currentBeaconRegions.map { $0.identifier })")
        
        for beaconRegion in currentBeaconRegions {
            locationManager.stopMonitoring(for: beaconRegion)
            logger.debug("RegionMonitoringManager: Stopped monitoring beacon region \(beaconRegion.identifier)")
        }
        
        // Start new monitoring
        for beaconID in beaconIDs {
            let region = beaconID.clBeaconRegion
            locationManager.startMonitoring(for: region)
            locationManager.requestState(for: region)
            logger.debug("RegionMonitoringManager: Started monitoring \(beaconID)")
        }
        
        let allRegionsAfter = locationManager.monitoredRegions
        logger.debug("RegionMonitoringManager: All monitored regions after start: \(formatRegionDetails(allRegionsAfter))")
    }
    
    func stopMonitoring() {
        logger.debug("RegionMonitoringManager: Stopping all beacon monitoring")
        
        // Only stop beacon regions that this manager is responsible for
        let currentBeaconRegions = locationManager.monitoredRegions.compactMap { $0 as? CLBeaconRegion }
        let allRegionsBefore = locationManager.monitoredRegions.map { $0.identifier }
        logger.debug("RegionMonitoringManager: All monitored regions before stop: \(allRegionsBefore)")
        logger.debug("RegionMonitoringManager: Beacon regions to stop: \(currentBeaconRegions.map { $0.identifier })")
        
        for beaconRegion in currentBeaconRegions {
            locationManager.stopMonitoring(for: beaconRegion)
            logger.debug("RegionMonitoringManager: Stopped monitoring beacon region \(beaconRegion.identifier)")
        }
        
        let allRegionsAfter = locationManager.monitoredRegions
        logger.debug("RegionMonitoringManager: All monitored regions after stop: \(formatRegionDetails(allRegionsAfter))")
    }
    
    /// Updates the set of monitored beacons, ensuring all regions have the correct delegate.
    /// This method re-registers all beacon regions to handle cases where regions exist but have stale delegates (e.g., after app restart).
    func updateMonitoredBeacons(_ beaconIDs: Set<BeaconID>) {
        
        // Get all beacon regions currently registered with CLLocationManager
        let currentBeaconRegions = locationManager.monitoredRegions.compactMap { $0 as? CLBeaconRegion }
        let allRegionsBefore = locationManager.monitoredRegions
        
        logger.debug("RegionMonitoringManager: All monitored regions before update: \(formatRegionDetails(allRegionsBefore))")
        logger.debug("RegionMonitoringManager: Desired beacons: \(beaconIDs.map { $0.description })")

        for beaconRegion in currentBeaconRegions {
            locationManager.stopMonitoring(for: beaconRegion)
            logger.debug("RegionMonitoringManager: Stopped monitoring beacon region \(beaconRegion.identifier)")
        }
        
        for beaconID in beaconIDs {
            let region = beaconID.clBeaconRegion
            self.locationManager.startMonitoring(for: region)
            self.locationManager.requestState(for: region)
            self.logger.debug("RegionMonitoringManager: Started monitoring beacon \(beaconID) and requested initial state")
        }
        
        let allRegionsAfterDelay = self.locationManager.monitoredRegions
        self.logger.debug("RegionMonitoringManager: All monitored regions: \(self.formatRegionDetails(allRegionsAfterDelay))")
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        logger.debug("RegionMonitoringManager: didEnterRegion \(region)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            let beaconID = BeaconID(from: beaconRegion)
            delegate?.regionManager(self, didReceiveEvent: .regionEntered(beaconID))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        logger.debug("RegionMonitoringManager: didExitRegion \(region)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            let beaconID = BeaconID(from: beaconRegion)
            delegate?.regionManager(self, didReceiveEvent: .regionExited(beaconID))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        logger.debug("RegionMonitoringManager: didDetermineState \(state.rawValue) for \(region)")
        
        if let beaconRegion = region as? CLBeaconRegion {
            let beaconID = BeaconID(from: beaconRegion)
            switch state {
            case .inside:
                delegate?.regionManager(self, didReceiveEvent: .regionEntered(beaconID))
            case .outside:
                delegate?.regionManager(self, didReceiveEvent: .regionExited(beaconID))
            case .unknown:
                logger.debug("RegionMonitoringManager: Unknown state for \(beaconID)")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("RegionMonitoringManager: didFailWithError \(error.localizedDescription)")
        delegate?.regionManager(self, didReceiveEvent: .error(.rangeError(error.localizedDescription)))
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        logger.debug("RegionMonitoringManager: didChangeAuthorization \(status.rawValue)")
        delegate?.regionManager(self, didReceiveEvent: .authorizationChanged(status))
    }
}

/// Protocol for RSSI ranging event delegation
protocol RSSIRangingDelegate: AnyObject {
    func rssiManager(_ manager: RSSIRangingManager, didReceiveEvent event: BeaconEvent)
}

/// Internal manager for RSSI ranging (precise signal strength)
final class RSSIRangingManager: NSObject, CLLocationManagerDelegate {
    let locationManager = CLLocationManager()
    weak var delegate: RSSIRangingDelegate?
    private let logger: UnifiedLogger
    private var beaconLostTimers: [BeaconID: Timer] = [:]
    private let lostBeaconTimeout: TimeInterval
    
    init(logger: UnifiedLogger, lostBeaconTimeout: TimeInterval = 3.0) {
        self.logger = logger
        self.lostBeaconTimeout = lostBeaconTimeout
        super.init()
        logger.debug("RSSIRangingManager: Creating delegate assignment for CLLocationManager")
        locationManager.delegate = self
        logger.debug("RSSIRangingManager: Delegate successfully assigned to \(self)")
        logger.debug("RSSIRangingManager initialized: \(self)")
        assert(Thread.isMainThread, "CLLocationManagerDelegate must be called on the main thread")
    }
    
    deinit {
        logger.debug("RSSIRangingManager deinit: \(self)")
        stopRanging()
    }
    
    func startRanging(for beaconIDs: Set<BeaconID>) {
        logger.debug("RSSIRangingManager: Starting ranging for \(beaconIDs.count) beacons")
        
        // Stop current ranging
        stopRanging()
        
        // Start new ranging
        for beaconID in beaconIDs {
            let constraint = beaconID.clBeaconConstraint
            locationManager.startRangingBeacons(satisfying: constraint)
            logger.debug("RSSIRangingManager: Started ranging \(beaconID)")
        }
    }
    
    func stopRanging() {
        logger.debug("RSSIRangingManager: Stopping all ranging")
        for constraint in locationManager.rangedBeaconConstraints {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
        
        // Cancel all timers
        beaconLostTimers.values.forEach { $0.invalidate() }
        beaconLostTimers.removeAll()
    }
    
    /// Updates the set of ranged beacons without interrupting ranging for beacons that should remain ranged.
    func updateRangedBeacons(_ beaconIDs: Set<BeaconID>) {
        logger.debug("RSSIRangingManager: Updating ranged beacons to \(beaconIDs.count) beacons")
        let currentConstraints = locationManager.rangedBeaconConstraints
        let currentBeaconIDs: Set<BeaconID> = Set(currentConstraints.compactMap { BeaconID(from: $0) })
        // Beacons to stop ranging
        let toRemove = currentBeaconIDs.subtracting(beaconIDs)
        // Beacons to start ranging
        let toAdd = beaconIDs.subtracting(currentBeaconIDs)
        // Stop ranging removed beacons
        for beaconID in toRemove {
            let constraint = beaconID.clBeaconConstraint
            locationManager.stopRangingBeacons(satisfying: constraint)
            logger.debug("RSSIRangingManager: Stopped ranging \(beaconID)")
        }
        // Start ranging new beacons
        for beaconID in toAdd {
            let constraint = beaconID.clBeaconConstraint
            locationManager.startRangingBeacons(satisfying: constraint)
            logger.debug("RSSIRangingManager: Started ranging \(beaconID)")
        }
    }
    
    private func startBeaconLostTimer(for beaconID: BeaconID) {
        // Cancel existing timer
        beaconLostTimers[beaconID]?.invalidate()
        
        // Start new timer
        let timer = Timer.scheduledTimer(withTimeInterval: lostBeaconTimeout, repeats: false) { [weak self] _ in
            self?.handleBeaconLost(beaconID)
        }
        beaconLostTimers[beaconID] = timer
    }
    
    private func cancelBeaconLostTimer(for beaconID: BeaconID) {
        beaconLostTimers[beaconID]?.invalidate()
        beaconLostTimers.removeValue(forKey: beaconID)
    }
    
    private func handleBeaconLost(_ beaconID: BeaconID) {
        beaconLostTimers.removeValue(forKey: beaconID)
        delegate?.rssiManager(self, didReceiveEvent: .beaconLost(beaconID))
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        //logger.debug("RSSIRangingManager: didRange \(beacons.count) beacons")
        
        if beacons.isEmpty {
            // No beacons detected - emit noBeacon event
            delegate?.rssiManager(self, didReceiveEvent: .noBeacon(beaconConstraint))
            logger.debug("RSSIRangingManager: No beacons detected for constraint \(beaconConstraint)")
        } else {
            // Process detected beacons
            for clBeacon in beacons {
                let beaconID = BeaconID(from: clBeacon)
                logger.debug("RSSIRangingManager: Detected \(beaconID) with RSSI \(clBeacon.rssi)")
                
                // Cancel lost timer
                cancelBeaconLostTimer(for: beaconID)
                
                // Check for invalid RSSI (0)
                if clBeacon.rssi == 0 {
                    // Emit missing beacon event for invalid RSSI
                    delegate?.rssiManager(self, didReceiveEvent: .missingBeacon(beaconID))
                    //logger.debug("RSSIRangingManager: Missing beacon detected (RSSI=0) for \(beaconID)")
                } else {
                    // Emit normal detection event
                    delegate?.rssiManager(self, didReceiveEvent: .beaconDetected(beaconID, rssi: clBeacon.rssi))
                }
                
                // Start lost timer
                startBeaconLostTimer(for: beaconID)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        logger.error("RSSIRangingManager: didFailWithError \(error.localizedDescription)")
        delegate?.rssiManager(self, didReceiveEvent: .error(.rangeError(error.localizedDescription)))
    }
}

/// CoreLocation-based implementation of BeaconMonitorProtocol that ranges all beacons
final class AlwaysRangingBeaconMonitor: NSObject, BeaconMonitorProtocol, RegionMonitoringDelegate, RSSIRangingDelegate {
    
    // MARK: - Properties
    
    private let eventSubject = PassthroughSubject<BeaconEvent, Never>()
    private var signalProcessor: BeaconSignalProcessor?
    
    private let beaconLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "AlwaysRangingBeaconMonitor")
    )
    
    // Internal managers
    private let regionManager: RegionMonitoringManager
    private let rssiManager: RSSIRangingManager
    
    // State tracking
    private var beaconsInsideRegion: Set<BeaconID> = []
    private var isMonitoring = false
    
    var eventPublisher: AnyPublisher<BeaconEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    var configuration = BeaconMonitoringConfig.default {
        didSet {
            if configuration.signalProcessingEnabled {
                signalProcessor = BeaconSignalProcessor()
            } else {
                signalProcessor = nil
            }
        }
    }
    
    var monitoredBeacons: Set<BeaconID> = []
    
    var authorizationStatus: CLAuthorizationStatus {
        regionManager.locationManager.authorizationStatus
    }
    
    // MARK: - Initialization
    
    override init() {
        // Create managers with delegation
        assert(Thread.isMainThread, "RSSIRangingManager & RegionMonitoringManager init must be called on the main thread")
        
        rssiManager = RSSIRangingManager(
            logger: UnifiedLogger(
                fileLogger: .shared,
                osLogger: Logger(subsystem: "com.limmi.app", category: "RSSIRangingManager")
            ),
            lostBeaconTimeout: 3.0
        )
        
        regionManager = RegionMonitoringManager(
            logger: UnifiedLogger(
                fileLogger: .shared,
                osLogger: Logger(subsystem: "com.limmi.app", category: "RegionMonitoringManager")
            )
        )
        
        super.init()
        
        // Set up delegation with detailed logging
        beaconLogger.debug("🔧 Setting RegionMonitoringManager delegate")
        regionManager.delegate = self
        beaconLogger.debug("🔧 Setting RSSIRangingManager delegate") 
        rssiManager.delegate = self
        beaconLogger.debug("🔧 Both delegates set successfully")
        
        beaconLogger.debug("AlwaysRangingBeaconMonitor init: \(self)")
        
        if configuration.signalProcessingEnabled {
            signalProcessor = BeaconSignalProcessor()
        }
    }
    
    deinit {
        beaconLogger.debug("AlwaysRangingBeaconMonitor deinit: \(self)")
    }
    
    // MARK: - RegionMonitoringDelegate
    
    func regionManager(_ manager: RegionMonitoringManager, didReceiveEvent event: BeaconEvent) {
        handleRegionEvent(event)
    }
    
    // MARK: - RSSIRangingDelegate
    
    func rssiManager(_ manager: RSSIRangingManager, didReceiveEvent event: BeaconEvent) {
        handleRSSIEvent(event)
    }
    
    // MARK: - BeaconMonitorProtocol Implementation
    
    func setMonitoredBeacons(_ beacons: Set<BeaconID>) {
        monitoredBeacons = beacons
        
        // Only update monitoring if we're currently monitoring
        guard isMonitoring else { return }
        
        beaconLogger.debug("Updating monitored beacons: \(beacons.count) beacons")

        // Always range ALL monitored beacons (not just those inside regions)
        rssiManager.updateRangedBeacons(beacons)
        // Always update region monitoring
        regionManager.updateMonitoredBeacons(beacons)
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        beaconLogger.debug("startMonitoring: Starting always-ranging monitoring")
        isMonitoring = true
        
        // Start ranging ALL monitored beacons immediately
        rssiManager.startRanging(for: monitoredBeacons)
        
        // Start region monitoring
        regionManager.startMonitoring(for: monitoredBeacons)
        
        eventSubject.send(.monitoringStarted(monitoredBeacons))
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        beaconLogger.debug("stopMonitoring: Stopping always-ranging monitoring")
        
        // Stop both managers
        regionManager.stopMonitoring()
        rssiManager.stopRanging()
        
        // Clear state
        beaconsInsideRegion.removeAll()
        
        eventSubject.send(.monitoringStopped)
    }
    
    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            regionManager.locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            regionManager.locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
    
    // MARK: - Private Methods
    
    /// Handles events from the region monitoring manager
    private func handleRegionEvent(_ event: BeaconEvent) {
        switch event {
        case .regionEntered(let beaconID):
            beaconsInsideRegion.insert(beaconID)
            // Forward the event
            eventSubject.send(event)
            
        case .regionExited(let beaconID):
            beaconsInsideRegion.remove(beaconID)
            // Forward the event
            eventSubject.send(event)
            
        default:
            // Forward other events (errors, authorization changes)
            eventSubject.send(event)
        }
    }
    
    /// Handles events from the RSSI ranging manager
    private func handleRSSIEvent(_ event: BeaconEvent) {
        switch event {
        case .beaconDetected(_, let rssi):
            // Process with signal processor if enabled
            if configuration.signalProcessingEnabled,
               let processor = signalProcessor {
                _ = processor.process(rssi: rssi)
            }
            
            // Forward the event
            eventSubject.send(event)
            
        case .noBeacon(let constraint):
            // Forward the event
            eventSubject.send(event)
            
        case .missingBeacon(let beaconID):
            // Forward the event
            eventSubject.send(event)
            
        default:
            // Forward other events (lost beacons, errors)
            eventSubject.send(event)
        }
    }
}

/// CoreLocation-based implementation of BeaconMonitorProtocol
final class CoreLocationBeaconMonitor: NSObject, BeaconMonitorProtocol, RegionMonitoringDelegate, RSSIRangingDelegate {
    
    // MARK: - Properties
    
    private let eventSubject = PassthroughSubject<BeaconEvent, Never>()
    private var signalProcessor: BeaconSignalProcessor?
    
    private let beaconLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "CoreLocationBeaconMonitor")
    )
    
    // Internal managers
    private let regionManager: RegionMonitoringManager
    private let rssiManager: RSSIRangingManager
    
    // State tracking
    private var beaconsInsideRegion: Set<BeaconID> = []
    private var isMonitoring = false
    
    var eventPublisher: AnyPublisher<BeaconEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }
    
    var configuration = BeaconMonitoringConfig.default {
        didSet {
            if configuration.signalProcessingEnabled {
                signalProcessor = BeaconSignalProcessor()
            } else {
                signalProcessor = nil
            }
        }
    }
    
    var monitoredBeacons: Set<BeaconID> = []
    
    var authorizationStatus: CLAuthorizationStatus {
        regionManager.locationManager.authorizationStatus
    }
    
    // MARK: - Initialization
    
    override init() {
        // Create managers with delegation
        regionManager = RegionMonitoringManager(
            logger: UnifiedLogger(
                fileLogger: .shared,
                osLogger: Logger(subsystem: "com.limmi.app", category: "RegionMonitoringManager")
            )
        )
        
        rssiManager = RSSIRangingManager(
            logger: UnifiedLogger(
                fileLogger: .shared,
                osLogger: Logger(subsystem: "com.limmi.app", category: "RSSIRangingManager")
            ),
            lostBeaconTimeout: 3.0
        )
        
        super.init()
        
        // Set up delegation with detailed logging
        beaconLogger.debug("🔧 Setting RegionMonitoringManager delegate")
        regionManager.delegate = self
        beaconLogger.debug("🔧 Setting RSSIRangingManager delegate") 
        rssiManager.delegate = self
        beaconLogger.debug("🔧 Both delegates set successfully")
        
        beaconLogger.debug("CoreLocationBeaconMonitor init: \(self)")
        
        if configuration.signalProcessingEnabled {
            signalProcessor = BeaconSignalProcessor()
        }
    }
    
    deinit {
        beaconLogger.debug("CoreLocationBeaconMonitor deinit: \(self)")
    }
    
    // MARK: - RegionMonitoringDelegate
    
    func regionManager(_ manager: RegionMonitoringManager, didReceiveEvent event: BeaconEvent) {
        handleRegionEvent(event)
    }
    
    // MARK: - RSSIRangingDelegate
    
    func rssiManager(_ manager: RSSIRangingManager, didReceiveEvent event: BeaconEvent) {
        handleRSSIEvent(event)
    }
    
    // MARK: - BeaconMonitorProtocol Implementation
    
    func setMonitoredBeacons(_ beacons: Set<BeaconID>) {
        monitoredBeacons = beacons
        
        // Only update monitoring if we're currently monitoring
        guard isMonitoring else { return }
        
        beaconLogger.debug("Updating monitored beacons: \(beacons.count) beacons")
        
        // Always update region monitoring
        if configuration.useRegionMonitoring {
            // Use the new updateMonitoredBeacons method instead of startMonitoring
            regionManager.updateMonitoredBeacons(beacons)
        }
        
        //rssiManager.updateRangedBeacons(beacons)
        
        // Update RSSI ranging for beacons currently inside regions
        updateRSSIRanging()
    }
    
    func startMonitoring() {
        guard !isMonitoring else { return }
        beaconLogger.debug("startMonitoring: Starting dual-manager monitoring")
        isMonitoring = true
        
        // Start region monitoring
        if configuration.useRegionMonitoring {
            regionManager.startMonitoring(for: monitoredBeacons)
        }
        
        // RSSI ranging will be started when we enter regions
        eventSubject.send(.monitoringStarted(monitoredBeacons))
    }
    
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        
        beaconLogger.debug("stopMonitoring: Stopping dual-manager monitoring")
        
        // Stop both managers
        regionManager.stopMonitoring()
        rssiManager.stopRanging()
        
        // Clear state
        beaconsInsideRegion.removeAll()
        
        eventSubject.send(.monitoringStopped)
    }
    
    func requestAuthorization() {
        switch authorizationStatus {
        case .notDetermined:
            regionManager.locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            regionManager.locationManager.requestAlwaysAuthorization()
        default:
            break
        }
    }
    
    // MARK: - Private Methods
    
    /// Handles events from the region monitoring manager
    private func handleRegionEvent(_ event: BeaconEvent) {
        switch event {
        case .regionEntered(let beaconID):
            beaconsInsideRegion.insert(beaconID)
            updateRSSIRanging()
            // Forward the event
            eventSubject.send(event)
            
        case .regionExited(let beaconID):
            
            beaconsInsideRegion.remove(beaconID)
            updateRSSIRanging()
            // Forward the event
            eventSubject.send(event)
            
        default:
            // Forward other events (errors, authorization changes)
            eventSubject.send(event)
        }
    }
    
    /// Handles events from the RSSI ranging manager
    private func handleRSSIEvent(_ event: BeaconEvent) {
        switch event {
        case .beaconDetected(_, let rssi):
            // Process with signal processor if enabled
            if configuration.signalProcessingEnabled,
               let processor = signalProcessor {
                _ = processor.process(rssi: rssi)
            }
            
            // Forward the event
            eventSubject.send(event)
            
        case .noBeacon(let constraint):
            // Log no beacon detection
            //beaconLogger.debug("No beacons detected for constraint: \(constraint)")
            // Forward the event
            eventSubject.send(event)
            
        case .missingBeacon(let beaconID):
            // Log missing beacon (RSSI=0)
            //beaconLogger.debug("Missing beacon detected (RSSI=0): \(beaconID)")
            // Forward the event
            eventSubject.send(event)
            
        default:
            // Forward other events (lost beacons, errors)
            eventSubject.send(event)
        }
    }
    
    /// Updates RSSI ranging based on current region state
    private func updateRSSIRanging() {
        guard isMonitoring else { return }
        
        let beaconsToRange = beaconsInsideRegion.intersection(monitoredBeacons)
        
        if beaconsToRange.isEmpty {
            //beaconLogger.debug("No beacons inside regions - stopping RSSI ranging")
            rssiManager.stopRanging()
        } else {
            //beaconLogger.debug("Starting RSSI ranging for \(beaconsToRange.count) beacons inside regions")
            rssiManager.updateRangedBeacons(beaconsToRange)
        }
    }
}

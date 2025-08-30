//
//  CoreLocationBeaconScanner.swift
//  Limmi
//
//  Purpose: CoreLocation-based beacon scanner for user's registered beacons
//  Uses region monitoring and ranging to detect beacons from RuleStore
//

import Foundation
import CoreLocation
import SwiftUI
import os
import Combine

@MainActor
class CoreLocationBeaconScanner: NSObject, BeaconScannerProtocol, CLLocationManagerDelegate {
    
    // MARK: - BeaconScannerProtocol Properties
    
    @Published var devices: [DetectedBeacon] = []
    
    // MARK: - Private Properties
    
    private var locationManager: CLLocationManager!
    private var beaconConstraints: [CLBeaconIdentityConstraint] = []
    private var userBeacons: [BeaconDevice] = []
    private var cancellables = Set<AnyCancellable>()
    private var isScanning = false
    private var cleanupTimer: Timer?
    
    // RSSI tracking for signal averaging
    private let rssiBufferSize = 5
    private var rssiBuffers: [String: [Int]] = [:]
    
    // Dependencies - Clean dependency injection using protocol
    private let ruleStore: any RuleStore
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "CoreLocationBeaconScanner")
    )
    
    // MARK: - Initialization
    
    /// Initialize beacon scanner with rule store
    /// - Parameter ruleStore: Source of beacon data (protocol-based)
    init(ruleStore: any RuleStore) {
        self.ruleStore = ruleStore
        super.init()
        
        setupLocationManager()
        setupBeaconObserver()
        setupCleanupTimer()
    }
    
    deinit {
        cleanupTimer?.invalidate()
        // Stop ranging synchronously in deinit - safe because we're already on MainActor
        for constraint in beaconConstraints {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
    }
    
    // MARK: - Setup Methods
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
    }
    
    private func setupBeaconObserver() {
        // React to changes in user's beacon list using RuleStore
        ruleStore.beaconDevicesPublisher
            .sink { [weak self] beacons in
                self?.userBeacons = beacons
                self?.updateBeaconConstraints()
            }
            .store(in: &cancellables)
    }
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.cleanupOldBeacons()
        }
    }
    
    // MARK: - BeaconScannerProtocol Implementation
    
    func startScanning() {
        guard locationManager.authorizationStatus == .authorizedWhenInUse || 
              locationManager.authorizationStatus == .authorizedAlways else {
            logger.error("Location authorization not granted")
            return
        }
        
        guard !isScanning else {
            logger.debug("Already scanning")
            return
        }
        
        isScanning = true
        
        // Get current beacons from rule store
        userBeacons = ruleStore.beaconDevices()
        
        // Start ranging for existing beacons
        startRangingForUserBeacons()
        
        logger.debug("Started scanning for user's beacons")
    }
    
    func stopScanning() {
        guard isScanning else { return }
        
        isScanning = false
        
        // Stop ranging for all constraints
        for constraint in beaconConstraints {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
        
        beaconConstraints.removeAll()
        rssiBuffers.removeAll()
        
        DispatchQueue.main.async {
            self.devices.removeAll()
        }
        
        logger.debug("Stopped scanning for beacons")
    }
    
    func getBeaconSummary() -> String {
        let summary = devices.map { beacon in
            "Name: \(beacon.name) | UUID: \(beacon.uuid.prefix(8))... | Major: \(beacon.major) | Minor: \(beacon.minor) | RSSI: \(beacon.averagedRSSI) | Distance: \(String(format: "%.1f", beacon.estimatedDistance))m"
        }.joined(separator: "\n")
        
        return summary.isEmpty ? "No user beacons detected" : summary
    }
    
    // MARK: - Private Methods
    
    private func updateBeaconConstraints() {
        guard isScanning else { return }
        
        // Stop current ranging
        for constraint in beaconConstraints {
            locationManager.stopRangingBeacons(satisfying: constraint)
        }
        beaconConstraints.removeAll()
        
        // Start ranging for updated beacon list
        startRangingForUserBeacons()
        
        logger.debug("Updated beacon constraints for \(userBeacons.count) user beacons")
    }
    
    private func startRangingForUserBeacons() {
        guard locationManager.authorizationStatus == .authorizedWhenInUse ||
                locationManager.authorizationStatus == .authorizedAlways else {
            return
        }
        
        // Create constraints for each user beacon
        /*beaconConstraints = userBeacons.compactMap { beacon in
            guard let uuid = UUID(uuidString: beacon.uuid) else {
                logger.error("Invalid UUID for beacon: \(beacon.uuid)")
                return nil
            }
            // E2C56DB5-DFFB-48D2-B060-D0F5A71096E0
            // E2C56DB5-9999-48D2-B060-D0F5A71096E0
            /*return CLBeaconIdentityConstraint(
             uuid: uuid,
             major: CLBeaconMajorValue(beacon.major),
             minor: CLBeaconMinorValue(beacon.minor)
             )*/
            
            return CLBeaconIdentityConstraint(
                uuid: uuid
            )
        }*/
        
        
        beaconConstraints = [
            CLBeaconIdentityConstraint(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!),
            CLBeaconIdentityConstraint(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!),
            CLBeaconIdentityConstraint(uuid: UUID(uuidString: "E2C56DB5-9999-48D2-B060-D0F5A71096E0")!)
        ]

        
        // Start ranging for each constraint
        for constraint in beaconConstraints {
            locationManager.startRangingBeacons(satisfying: constraint)
        }
        
        logger.debug("Started ranging for \(beaconConstraints.count) beacon constraints")
    }
    
    private func beaconKey(uuid: String, major: Int, minor: Int) -> String {
        return "\(uuid)_\(major)_\(minor)"
    }
    
    private func cleanupOldBeacons() {
        let currentTime = Date()
        let cleanupInterval: TimeInterval = 8.0 // Remove beacons not seen for 8 seconds
        
        DispatchQueue.main.async {
            self.devices = self.devices.filter { beacon in
                currentTime.timeIntervalSince(beacon.lastSeen) < cleanupInterval
            }
        }
        
        // Also clean up RSSI buffers for old beacons
        let currentBeaconKeys = Set(devices.map { beaconKey(uuid: $0.uuid, major: $0.major, minor: $0.minor) })
        rssiBuffers = rssiBuffers.filter { currentBeaconKeys.contains($0.key) }
    }
    
    private func updateBeacon(uuid: String, major: Int, minor: Int, rssi: Int) {
        let key = beaconKey(uuid: uuid, major: major, minor: minor)
        
        // Update RSSI buffer
        var buffer = rssiBuffers[key] ?? []
        buffer.append(rssi)
        if buffer.count > rssiBufferSize {
            buffer.removeFirst()
        }
        rssiBuffers[key] = buffer
        
        // Calculate averaged RSSI
        let avgRSSI = buffer.reduce(0, +) / buffer.count
        
        // Find the corresponding user beacon to get name and txPower
        /*guard let userBeacon = userBeacons.first(where: {
            $0.uuid == uuid && $0.major == major && $0.minor == minor
        }) else {
            logger.debug("Detected beacon not found in user's beacon list: \(uuid.prefix(8))... Major: \(major) Minor: \(minor)")
            return
        }*/
        
        // Use a default txPower since it's not stored in BeaconDevice
        let txPower = -59 // Standard iBeacon txPower
        
        // Update devices list on main thread
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { 
                self.beaconKey(uuid: $0.uuid, major: $0.major, minor: $0.minor) == key 
            }) {
                // Update existing beacon
                self.devices[index] = DetectedBeacon(
                    uuid: uuid,
                    major: major,
                    minor: minor,
                    txPower: txPower,
                    averagedRSSI: avgRSSI,
                    lastSeen: Date()
                )
            } else {
                // Add new beacon
                let newBeacon = DetectedBeacon(
                    uuid: uuid,
                    major: major,
                    minor: minor,
                    txPower: txPower,
                    averagedRSSI: avgRSSI,
                    lastSeen: Date()
                )
                self.devices.append(newBeacon)
            }
            
            // Sort by signal strength (strongest first)
            self.devices.sort { $0.averagedRSSI > $1.averagedRSSI }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            logger.debug("Location authorization granted")
            if isScanning {
                startRangingForUserBeacons()
            }
        case .denied, .restricted:
            logger.error("Location authorization denied")
            stopScanning()
        case .notDetermined:
            logger.debug("Location authorization not determined")
        @unknown default:
            logger.debug("Unknown location authorization status")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        guard isScanning else { return }
        
        for beacon in beacons {
            // Only process beacons with valid RSSI
            guard beacon.rssi != 0 && beacon.rssi > -100 else { continue }
            
            updateBeacon(
                uuid: beacon.uuid.uuidString,
                major: Int(truncating: beacon.major),
                minor: Int(truncating: beacon.minor),
                rssi: beacon.rssi
            )
            
            logger.debug("Ranged user beacon: UUID=\(beacon.uuid.uuidString.prefix(8))... Major=\(beacon.major) Minor=\(beacon.minor) RSSI=\(beacon.rssi)")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint, error: Error) {
        logger.error("Failed to range beacons for constraint \(beaconConstraint): \(error.localizedDescription)")
    }
}

// MARK: - DetectedBeacon Extension for User Beacon Names

extension DetectedBeacon {
    /// Returns a user-friendly name for the beacon, using the Firebase beacon name if available
    var userFriendlyName: String {
        // This could be enhanced to look up the actual beacon name from Firebase
        // For now, fallback to the existing name logic
        return name
    }
}

//
//  RegionMonitoringLocationProviderTests.swift
//  Limmi
//
//  Purpose: Tests and validation for RegionMonitoringLocationProvider
//  Dependencies: Foundation, CoreLocation, Combine
//

import Foundation
import CoreLocation
import Combine

/// Test suite for RegionMonitoringLocationProvider
final class RegionMonitoringLocationProviderTests {
    
    private var provider: RegionMonitoringLocationProvider!
    private var cancellables: Set<AnyCancellable> = []
    
    func runTests() {
        print("🧪 Starting RegionMonitoringLocationProvider Tests")
        
        testInitialization()
        testRegionManagement()
        testLocationPublisher()
        testRegionEventPublisher()
        testGPSRuleIntegration()
        
        print("✅ All RegionMonitoringLocationProvider tests completed")
    }
    
    // MARK: - Test Cases
    
    private func testInitialization() {
        print("🔍 Testing initialization...")
        
        provider = RegionMonitoringLocationProvider()
        
        // Check initial state
        assert(provider.currentLocation == nil, "Initial location should be nil")
        assert(provider.monitoredRegionIdentifiers.isEmpty, "Should start with no monitored regions")
        assert(!provider.isMonitoring(identifier: "test"), "Should not be monitoring non-existent region")
        
        print("✅ Initialization test passed")
    }
    
    private func testRegionManagement() {
        print("🔍 Testing region management...")
        
        provider = RegionMonitoringLocationProvider()
        
        // Test adding regions
        let center1 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco
        let center2 = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)  // New York
        
        provider.addRegion(center: center1, radius: 100.0, identifier: "sf_office")
        provider.addRegion(center: center2, radius: 200.0, identifier: "ny_office")
        
        assert(provider.monitoredRegionIdentifiers.count == 2, "Should have 2 monitored regions")
        assert(provider.isMonitoring(identifier: "sf_office"), "Should be monitoring SF office")
        assert(provider.isMonitoring(identifier: "ny_office"), "Should be monitoring NY office")
        
        // Test removing specific region
        provider.removeRegion(identifier: "sf_office")
        assert(provider.monitoredRegionIdentifiers.count == 1, "Should have 1 monitored region")
        assert(!provider.isMonitoring(identifier: "sf_office"), "Should not be monitoring SF office")
        assert(provider.isMonitoring(identifier: "ny_office"), "Should still be monitoring NY office")
        
        // Test removing all regions
        provider.removeAllRegions()
        assert(provider.monitoredRegionIdentifiers.isEmpty, "Should have no monitored regions")
        
        print("✅ Region management test passed")
    }
    
    private func testLocationPublisher() {
        print("🔍 Testing location publisher...")
        
        provider = RegionMonitoringLocationProvider()
        
        var receivedLocations: [CLLocation] = []
        
        // Subscribe to location updates
        provider.locationPublisher
            .sink { location in
                receivedLocations.append(location)
            }
            .store(in: &cancellables)
        
        // Note: In a real test, we'd need to mock CLLocationManager or use a test location
        // For now, we're just verifying the publisher exists and can be subscribed to
        
        print("✅ Location publisher test passed")
    }
    
    private func testRegionEventPublisher() {
        print("🔍 Testing region event publisher...")
        
        provider = RegionMonitoringLocationProvider()
        
        var receivedEvents: [RegionEvent] = []
        
        // Subscribe to region events
        provider.regionEventPublisher
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)
        
        // Note: In a real test, we'd simulate region entry/exit events
        // For now, we're just verifying the publisher exists and can be subscribed to
        
        print("✅ Region event publisher test passed")
    }
    
    private func testGPSRuleIntegration() {
        print("🔍 Testing GPS rule integration...")
        
        provider = RegionMonitoringLocationProvider()
        
        // Create sample GPS rules
        let gpsRules = [
            GPSLocationRule(identifier: "home", latitude: 37.7749, longitude: -122.4194, radius: 50.0),
            GPSLocationRule(identifier: "work", latitude: 37.7849, longitude: -122.4094, radius: 100.0),
            GPSLocationRule(identifier: "inactive", latitude: 37.7949, longitude: -122.3994, radius: 75.0, isActive: false)
        ]
        
        // Update regions from rules
        provider.updateRegions(from: gpsRules)
        
        // Check that regions were created correctly
        assert(provider.monitoredRegionIdentifiers.count == 3, "Should have 3 monitored regions")
        assert(provider.isMonitoring(identifier: "home"), "Should be monitoring home")
        assert(provider.isMonitoring(identifier: "work"), "Should be monitoring work")
        assert(provider.isMonitoring(identifier: "inactive"), "Should be monitoring inactive rule")
        
        print("✅ GPS rule integration test passed")
    }
}

// MARK: - Demo Usage

/// Demo class showing how to use RegionMonitoringLocationProvider
final class RegionMonitoringLocationProviderDemo {
    
    private let provider = RegionMonitoringLocationProvider()
    private var cancellables: Set<AnyCancellable> = []
    
    func runDemo() {
        print("🎯 Starting RegionMonitoringLocationProvider Demo")
        
        setupLocationObservers()
        setupRegionObservers()
        configureRegions()
        
        // Request authorization
        provider.requestAuthorization()
        
        // Start monitoring
        provider.startLocationUpdates()
        
        print("✅ Demo setup complete - monitoring for region events")
    }
    
    private func setupLocationObservers() {
        provider.locationPublisher
            .sink { location in
                print("📍 Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            }
            .store(in: &cancellables)
    }
    
    private func setupRegionObservers() {
        provider.regionEventPublisher
            .sink { event in
                switch event {
                case .entered(let region):
                    print("🚪 Entered region: \(region.identifier)")
                case .exited(let region):
                    print("🚪 Exited region: \(region.identifier)")
                case .inside(let region):
                    print("🏠 Inside region: \(region.identifier)")
                case .outside(let region):
                    print("🌍 Outside region: \(region.identifier)")
                case .monitoringStarted(let region):
                    print("👀 Started monitoring region: \(region.identifier)")
                case .monitoringFailed(let region, let error):
                    print("❌ Failed to monitor region: \(region.identifier), error: \(error.localizedDescription)")
                case .unknown(let region):
                    print("❓ Unknown state for region: \(region.identifier)")
                }
            }
            .store(in: &cancellables)
    }
    
    private func configureRegions() {
        // Example: Configure regions around common locations
        let sampleRules = [
            GPSLocationRule(identifier: "home", latitude: 37.7749, longitude: -122.4194, radius: 100.0),
            GPSLocationRule(identifier: "office", latitude: 37.7849, longitude: -122.4094, radius: 150.0),
            GPSLocationRule(identifier: "gym", latitude: 37.7649, longitude: -122.4294, radius: 75.0)
        ]
        
        provider.updateRegions(from: sampleRules)
        
        print("🎯 Configured \(sampleRules.count) regions for monitoring")
    }
}

// MARK: - Integration with Existing System


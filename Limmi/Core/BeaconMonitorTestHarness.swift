//
//  BeaconMonitorTestHarness.swift
//  Limmi
//
//  Purpose: Test harness for CoreLocationBeaconMonitor with event validation and scenario testing
//  Dependencies: Foundation, CoreLocation, Combine, XCTest
//  Related: BeaconMonitorProtocol.swift, BeaconEvent.swift, BeaconID.swift
//

import Foundation
import CoreLocation
import Combine
import SwiftUI
import os

/// Comprehensive test harness for CoreLocationBeaconMonitor with event validation and scenario testing.
///
/// This test harness provides:
/// - Real-time event monitoring and validation
/// - Predefined test scenarios for common use cases
/// - Event logging and assertion capabilities
/// - UI for interactive testing
/// - Performance and reliability metrics
///
/// ## Usage
/// ```swift
/// let harness = BeaconMonitorTestHarness()
/// harness.runBasicMonitoringTest()
/// harness.runRegionTransitionTest()
/// ```
///
/// The harness operates independently of the main app and can be used for:
/// - Unit testing beacon monitoring logic
/// - Integration testing with real beacons
/// - Performance benchmarking
/// - Debugging beacon detection issues
///
/// - Since: 1.0
final class BeaconMonitorTestHarness: ObservableObject {
    
    // MARK: - Properties
    
    /// The beacon monitor being tested
    private var beaconMonitor: BeaconMonitorProtocol
    
    /// Publisher for test events and results
    @Published var testEvents: [TestEvent] = []
    
    /// Current test status
    @Published var testStatus: TestStatus = .idle
    
    /// Test metrics and statistics
    @Published var testMetrics = TestMetrics()
    
    /// Event subscription
    private var eventCancellable: AnyCancellable?
    
    /// Test timeout timer
    private var testTimer: Timer?
    
    /// Logger for test harness operations
    private let testLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BeaconMonitorTestHarness")
    )
    
    /// Predefined test beacons
    let testBeacons: [BeaconID] = [
        BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1),
        BeaconID(uuid: UUID(uuidString: "426C7565-4368-6172-6D42-6561636F6E73")!, major: 3838, minor: 4949)
    ]
    
    // MARK: - Initialization
    
    /// Creates a test harness with a real CoreLocationBeaconMonitor
    init() {
        self.beaconMonitor = CoreLocationBeaconMonitor()
        setupEventMonitoring()
    }
    
    /// Creates a test harness with a custom beacon monitor (for dependency injection)
    init(beaconMonitor: BeaconMonitorProtocol) {
        self.beaconMonitor = beaconMonitor
        setupEventMonitoring()
    }
    
    // MARK: - Test Scenarios
    
    /// Runs a basic monitoring test: start monitoring, wait for events, stop monitoring
    func runBasicMonitoringTest() {
        startTest("Basic Monitoring Test")
        
        logTestEvent("📋 INSTRUCTIONS: This test validates basic beacon monitoring setup.")
        logTestEvent("🎯 ACTION REQUIRED: No action needed - testing system initialization only.")
        logTestEvent("📊 EXPECTED: Should see 'monitoringStarted' event within 5 seconds.")
        logTestEvent("⏱️ DURATION: 30 seconds")
        
        // Configure with test beacons
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        
        // Start monitoring
        beaconMonitor.startMonitoring()
        
        // Run test for 30 seconds
        scheduleTestCompletion(timeout: 30.0)
        
        // Expected events: monitoringStarted
        expectEvent(.monitoringStarted(Set(testBeacons)), within: 5.0)
    }
    
    /// Runs a region transition test: simulates entering and exiting beacon regions
    func runRegionTransitionTest() {
        startTest("Region Transition Test")
        
        logTestEvent("📋 INSTRUCTIONS: This test requires a physical beacon nearby.")
        logTestEvent("🎯 ACTION REQUIRED:")
        logTestEvent("  1. Start with beacon OUT OF RANGE (>50m away)")
        logTestEvent("  2. At 30s: Move CLOSE to beacon (within 10m)")
        logTestEvent("  3. At 120s: Move AWAY from beacon (>50m)")
        logTestEvent("📊 EXPECTED: regionEntered event at ~30s, regionExited at ~120s")
        logTestEvent("⏱️ DURATION: 3 minutes")
        logTestEvent("🔍 BEACON: E2C56DB5-0001-48D2-B060-D0F5A71096E0:1331:1")
        
        // Configure for dual-manager monitoring (default behavior)
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: false,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        beaconMonitor.configuration = config
        
        beaconMonitor.setMonitoredBeacons(Set([testBeacons[0]]))
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 180.0)
        
        // Expected events: monitoringStarted, potentially regionEntered/regionExited
        expectEvent(.monitoringStarted(Set([testBeacons[0]])), within: 5.0)
        expectEvent(.regionEntered(testBeacons[0]), within: 60.0)
        expectEvent(.regionExited(testBeacons[0]), within: 180.0)
    }
    
    /// Runs a configuration change test: updates monitored beacons while monitoring
    func runConfigurationChangeTest() {
        startTest("Configuration Change Test")
        
        // Start with one beacon
        beaconMonitor.setMonitoredBeacons(Set([testBeacons[0]]))
        beaconMonitor.startMonitoring()
        
        // After 10 seconds, change to different beacons
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            self.beaconMonitor.setMonitoredBeacons(Set([self.testBeacons[1]]))
        }
        
        scheduleTestCompletion(timeout: 30.0)
        
        // Expected events: monitoringStarted with first beacon, then with new beacons
        expectEvent(.monitoringStarted(Set([testBeacons[0]])), within: 5.0)
    }
    
    /// Runs a permission test: checks authorization status handling
    func runPermissionTest() {
        startTest("Permission Test")
        
        // Check initial authorization status
        let status = beaconMonitor.authorizationStatus
        logTestEvent("Initial authorization status: \(status)")
        
        // Request authorization
        beaconMonitor.requestAuthorization()
        
        scheduleTestCompletion(timeout: 20.0)
        
        // Expected events: authorizationChanged
        expectEvent(.authorizationChanged(status), within: 10.0)
    }
    
    /// Runs a stress test: rapid start/stop cycles
    func runStressTest() {
        startTest("Stress Test")
        
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        
        // Perform 10 rapid start/stop cycles
        var cycleCount = 0
        func performCycle() {
            cycleCount += 1
            if cycleCount <= 10 {
                beaconMonitor.startMonitoring()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.beaconMonitor.stopMonitoring()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        performCycle()
                    }
                }
            }
        }
        
        performCycle()
        scheduleTestCompletion(timeout: 60.0)
    }
    
    /// Runs a long-running stability test
    func runStabilityTest() {
        startTest("Stability Test (5 minutes)")
        
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        beaconMonitor.startMonitoring()
        
        // Run for 5 minutes
        scheduleTestCompletion(timeout: 300.0)
        
        expectEvent(.monitoringStarted(Set(testBeacons)), within: 5.0)
    }
    
    // MARK: - Component-Specific Tests
    
    /// Tests RegionMonitoringManager initialization and delegate setup
    func runRegionManagerInitializationTest() {
        startTest("RegionManager Initialization Test")
        
        // Configure for region monitoring only
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: false,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        beaconMonitor.configuration = config
        
        // Test with 2 beacons like in the log
        let testBeacons = [
            BeaconID(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 2),
            BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        ]
        
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 60.0)
        
        // Expected events: monitoring started, region state determination
        expectEvent(.monitoringStarted(Set(testBeacons)), within: 5.0)
        expectEvent(.authorizationChanged(beaconMonitor.authorizationStatus), within: 10.0)
    }
    
    /// Tests region entry and exit scenarios based on log patterns
    func runRegionTransitionCycleTest() {
        startTest("Region Transition Cycle Test")
        
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: false,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        beaconMonitor.configuration = config
        
        // Use single beacon for focused testing
        let beacon = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        beaconMonitor.setMonitoredBeacons([beacon])
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 180.0)
        
        // Expected sequence from log analysis
        expectEvent(.monitoringStarted([beacon]), within: 5.0)
        expectEvent(.regionEntered(beacon), within: 60.0)
        expectEvent(.regionExited(beacon), within: 120.0)
    }
    
    /// Tests RSSIRangingManager RSSI detection patterns
    func runRSSIDetectionTest() {
        startTest("RSSI Detection Pattern Test")
        
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: false,
            signalProcessingEnabled: true,
            proximityThreshold: -70,
            lostBeaconTimeout: 3.0
        )
        beaconMonitor.configuration = config
        
        // Test with beacon that showed RSSI values in log: 0, -84, -89, -74, -87
        let beacon = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        beaconMonitor.setMonitoredBeacons([beacon])
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 120.0)
        
        // Expected events based on log patterns
        expectEvent(.monitoringStarted([beacon]), within: 5.0)
        expectEvent(.beaconDetected(beacon, rssi: 0), within: 30.0)
        expectEvent(.missingBeacon(beacon), within: 40.0) // RSSI=0 triggers missing beacon
        expectEvent(.noBeacon(beacon.clBeaconConstraint), within: 50.0)
    }
    
    /// Tests AlwaysRangingBeaconMonitor dual-manager coordination
    func runAlwaysRangingCoordinationTest() {
        startTest("AlwaysRanging Manager Coordination Test")
        
        // Create AlwaysRangingBeaconMonitor specifically for this test
        let alwaysRangingMonitor = AlwaysRangingBeaconMonitor()
        
        // Configure for both region and RSSI monitoring
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: true,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        alwaysRangingMonitor.configuration = config
        
        // Test with 2 beacons like in log
        let testBeacons = [
            BeaconID(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 2),
            BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        ]
        
        // Replace the monitor for this test
        beaconMonitor = alwaysRangingMonitor
        
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 180.0)
        
        // Expected coordinated events
        expectEvent(.monitoringStarted(Set(testBeacons)), within: 5.0)
        expectEvent(.regionEntered(testBeacons[1]), within: 60.0) // Based on log pattern
        expectEvent(.beaconDetected(testBeacons[1], rssi: -84), within: 90.0)
    }
    
    /// Tests beacon signal strength variation patterns from the log
    func runSignalStrengthVariationTest() {
        startTest("Signal Strength Variation Test")
        
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: true,
            proximityThreshold: -80,
            lostBeaconTimeout: 5.0
        )
        beaconMonitor.configuration = config
        
        // Test beacon that showed varying RSSI in log: 0, -84, -89, -74, -87
        let beacon = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        beaconMonitor.setMonitoredBeacons([beacon])
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 150.0)
        
        // Expected pattern based on log analysis
        expectEvent(.monitoringStarted([beacon]), within: 5.0)
        expectEvent(.regionEntered(beacon), within: 30.0)
        expectEvent(.beaconDetected(beacon, rssi: 0), within: 45.0)
        expectEvent(.beaconDetected(beacon, rssi: -84), within: 60.0)
        expectEvent(.beaconDetected(beacon, rssi: -89), within: 75.0)
    }
    
    /// Tests no beacon detection scenarios from log patterns
    func runNoBeaconDetectionTest() {
        startTest("No Beacon Detection Test")
        
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: false,
            signalProcessingEnabled: false,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: 2.0
        )
        beaconMonitor.configuration = config
        
        // Test with beacons that showed "No beacons detected" in log
        let testBeacons = [
            BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1),
            BeaconID(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 2)
        ]
        
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        beaconMonitor.startMonitoring()
        
        scheduleTestCompletion(timeout: 90.0)
        
        // Expected no beacon events
        expectEvent(.monitoringStarted(Set(testBeacons)), within: 5.0)
        expectEvent(.noBeacon(testBeacons[0].clBeaconConstraint), within: 30.0)
        expectEvent(.noBeacon(testBeacons[1].clBeaconConstraint), within: 45.0)
    }
    
    /// Tests manager delegate assignment and lifecycle
    func runManagerDelegateTest() {
        startTest("Manager Delegate Assignment Test")
        
        // Test delegate setup patterns from log
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: true,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        beaconMonitor.configuration = config
        
        let beacon = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        beaconMonitor.setMonitoredBeacons([beacon])
        
        // Multiple start/stop cycles to test delegate reliability
        beaconMonitor.startMonitoring()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            self.beaconMonitor.stopMonitoring()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.beaconMonitor.startMonitoring()
            }
        }
        
        scheduleTestCompletion(timeout: 60.0)
        
        // Expected delegate events
        expectEvent(.monitoringStarted([beacon]), within: 5.0)
        expectEvent(.monitoringStopped, within: 15.0)
        expectEvent(.monitoringStarted([beacon]), within: 20.0)
    }
    
    /// Tests background/foreground transition scenarios from log
    func runBackgroundTransitionTest() {
        startTest("Background Transition Test")
        
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: true,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: 3.0
        )
        beaconMonitor.configuration = config
        
        let beacon = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        beaconMonitor.setMonitoredBeacons([beacon])
        beaconMonitor.startMonitoring()
        
        // Simulate app lifecycle events
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
            // Simulate background transition - monitoring should continue
            self.logTestEvent("Simulating background transition")
        }
        
        scheduleTestCompletion(timeout: 120.0)
        
        expectEvent(.monitoringStarted([beacon]), within: 5.0)
        expectEvent(.regionEntered(beacon), within: 60.0)
    }
    
    /// Step-by-step region entry/exit test with user movement guidance
    /// Tests RegionMonitoringManager with real CoreLocation delegate behavior and actual region events
    func runRegionMultipleEntryExitTest() {
        let beacon1 = BeaconID(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 2)
        let beacon2 = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        
        let steps = [
            TestStep(
                stepNumber: 1,
                description: "Initialize RegionMonitoringManager with 0 beacons",
                requiresUserAction: false,
                actionDescription: nil,
                expectedEvents: [.monitoringStarted(Set<BeaconID>())],
                timeout: 5.0
            ),
            TestStep(
                stepNumber: 2,
                description: "Update to monitor 2 beacons",
                requiresUserAction: false,
                actionDescription: nil,
                expectedEvents: [.monitoringStarted(Set([beacon1, beacon2]))],
                timeout: 5.0
            ),
            TestStep(
                stepNumber: 3,
                description: "Position yourself far from both beacons",
                requiresUserAction: true,
                actionDescription: "Move to a location MORE than 100 meters away from both beacons. Ensure you are completely outside both beacon regions before proceeding.",
                expectedEvents: [],
                timeout: 30.0
            ),
            TestStep(
                stepNumber: 4,
                description: "Walk toward beacon 1 to trigger region entry",
                requiresUserAction: true,
                actionDescription: "Walk toward beacon 1 (E2C56DB5-DFFB-48D2-B060-D0F5A71096E0) until you are within 50 meters. This should trigger a region entry event.",
                expectedEvents: [.regionEntered(beacon1)],
                timeout: 90.0
            ),
            TestStep(
                stepNumber: 5,
                description: "Move away from beacon 1 to trigger region exit",
                requiresUserAction: true,
                actionDescription: "Walk away from beacon 1 until you are more than 100 meters away. This should trigger a region exit event.",
                expectedEvents: [.regionExited(beacon1)],
                timeout: 90.0
            ),
            TestStep(
                stepNumber: 6,
                description: "Walk toward beacon 2 to trigger region entry",
                requiresUserAction: true,
                actionDescription: "Now walk toward beacon 2 (E2C56DB5-0001-48D2-B060-D0F5A71096E0) until you are within 50 meters. This should trigger a region entry event for the second beacon.",
                expectedEvents: [.regionEntered(beacon2)],
                timeout: 90.0
            ),
            TestStep(
                stepNumber: 7,
                description: "Test rapid entry/exit by moving between beacon regions",
                requiresUserAction: true,
                actionDescription: "Walk back toward beacon 1 region while still in beacon 2 region (if possible) to test multiple region states. Then move out of all regions.",
                expectedEvents: [.regionExited(beacon2)],
                timeout: 120.0
            ),
            TestStep(
                stepNumber: 8,
                description: "Reduce monitored beacons to test delegate reassignment",
                requiresUserAction: false,
                actionDescription: nil,
                expectedEvents: [.monitoringStarted([beacon1])],
                timeout: 5.0
            ),
            TestStep(
                stepNumber: 9,
                description: "Final test: walk near remaining beacon for final region event",
                requiresUserAction: true,
                actionDescription: "Walk close to beacon 1 (the only remaining monitored beacon) to trigger one final region entry event and verify the delegate is still functional after reassignment.",
                expectedEvents: [.regionEntered(beacon1)],
                timeout: 90.0
            )
        ]
        
        // Configure for region monitoring with real CoreLocation events
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: false,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        beaconMonitor.configuration = config
        
        // Phase 1: Start monitoring with 0 beacons (like in log)
        beaconMonitor.setMonitoredBeacons(Set<BeaconID>())
        beaconMonitor.startMonitoring()
        
        // Schedule beacon set changes to happen during step execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            // This happens during step 2
            self.beaconMonitor.setMonitoredBeacons(Set([beacon1, beacon2]))
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 600.0) {
            // This happens during step 8 (after user movement tests)
            self.beaconMonitor.setMonitoredBeacons([beacon1])
        }
        
        executeStepByStepTest("Region Entry/Exit with User Movement", steps: steps)
    }
    
    /// Tests delegate assignment reliability during region monitoring updates
    /// Reproduces the exact pattern from logs where delegate gets reassigned
    func runRegionDelegateReassignmentTest() {
        startTest("Region Delegate Reassignment Test")
        
        logTestEvent("📋 INSTRUCTIONS: Tests delegate reassignment during updateMonitoredBeacons.")
        logTestEvent("🎯 ACTION REQUIRED: No action needed - testing internal delegate behavior.")
        logTestEvent("📊 EXPECTED: Watch for delegate cleanup/reassignment log messages.")
        logTestEvent("⏱️ DURATION: 50 seconds")
        logTestEvent("🔍 WATCH FOR: 'Stopping all beacon regions to ensure delegate cleanup'")
        logTestEvent("📱 FOCUS: Validates delegate survives multiple reassignments")
        
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: false,
            proximityThreshold: BeaconMonitoringConfig.default.proximityThreshold,
            lostBeaconTimeout: BeaconMonitoringConfig.default.lostBeaconTimeout
        )
        beaconMonitor.configuration = config
        
        let beacon1 = BeaconID(uuid: UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 2)
        let beacon2 = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
        
        // Phase 1: Start with first beacon
        beaconMonitor.setMonitoredBeacons([beacon1])
        beaconMonitor.startMonitoring()
        logTestEvent("Phase 1: Started with beacon1 - RegionMonitoringManager delegate assigned")
        
        // Phase 2: Trigger updateMonitoredBeacons pattern from logs
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            self.logTestEvent("Phase 2: updateMonitoredBeacons - 'Stopping all beacon regions to ensure delegate cleanup'")
            // This reproduces the exact pattern from logs: updateMonitoredBeacons stops all, then restarts
            self.beaconMonitor.setMonitoredBeacons([beacon1, beacon2])
        }
        
        // Phase 3: Verify delegate is still functional after reassignment
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) {
            self.logTestEvent("Phase 3: Post-reassignment validation - delegate should be functional")
            // No simulation - we're testing the delegate setup, not CoreLocation events
            // Real region events will come from actual beacons if present
        }
        
        // Phase 4: Another delegate reassignment cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
            self.logTestEvent("Phase 4: Second delegate reassignment cycle")
            self.beaconMonitor.setMonitoredBeacons([beacon2]) // Remove beacon1, keep beacon2
        }
        
        // Phase 5: Multiple rapid changes to stress-test delegate
        DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) {
            self.logTestEvent("Phase 5: Rapid delegate reassignment stress test")
            self.beaconMonitor.setMonitoredBeacons([beacon1, beacon2]) // Add back
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.beaconMonitor.setMonitoredBeacons([beacon1]) // Remove beacon2
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                self.beaconMonitor.setMonitoredBeacons([beacon1, beacon2]) // Add back again
            }
        }
        
        // Phase 6: Final stop/start cycle
        DispatchQueue.main.asyncAfter(deadline: .now() + 35.0) {
            self.logTestEvent("Phase 6: Stop/start cycle to test complete delegate lifecycle")
            self.beaconMonitor.stopMonitoring()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.beaconMonitor.startMonitoring()
            }
        }
        
        scheduleTestCompletion(timeout: 50.0)
        
        // Expected events - focus on monitoring state changes, not CoreLocation events
        expectEvent(.monitoringStarted([beacon1]), within: 3.0)
        expectEvent(.monitoringStarted([beacon1, beacon2]), within: 12.0) // After first reassignment
        expectEvent(.monitoringStarted([beacon2]), within: 25.0) // After second reassignment
        expectEvent(.monitoringStarted([beacon1, beacon2]), within: 30.0) // After rapid changes
        expectEvent(.monitoringStopped, within: 38.0) // Stop cycle
        expectEvent(.monitoringStarted([beacon1, beacon2]), within: 42.0) // Restart
        
        logTestEvent("Note: Testing RegionMonitoringManager delegate reliability. Actual region events depend on physical beacons.")
        logTestEvent("Watch for: 'RegionMonitoringManager: Stopping all beacon regions to ensure delegate cleanup'")
        logTestEvent("Watch for: 'RegionMonitoringManager: Started monitoring beacon ... and requested initial state'")
    }
    
    // Step-by-step test execution properties
    @Published var currentTestStep: Int = 0
    @Published var testSteps: [TestStep] = []
    @Published var waitingForUserAcknowledgment: Bool = false
    @Published var currentStepDescription: String = ""
    
    /// Represents a test step that may require user action
    struct TestStep {
        let stepNumber: Int
        let description: String
        let requiresUserAction: Bool
        let actionDescription: String?
        let expectedEvents: [BeaconEvent]
        let timeout: TimeInterval
        var completed: Bool = false
        var startTime: Date?
    }
    
    /// Executes a test with step-by-step user guidance
    private func executeStepByStepTest(_ testName: String, steps: [TestStep]) {
        startTest(testName)
        self.testSteps = steps
        self.currentTestStep = 0
        executeNextStep()
    }
    
    /// Executes the next step in the current test
    private func executeNextStep() {
        guard currentTestStep < testSteps.count else {
            completeTest()
            return
        }
        
        let step = testSteps[currentTestStep]
        currentStepDescription = step.description
        logTestEvent("📍 Step \(step.stepNumber): \(step.description)")
        
        if step.requiresUserAction {
            waitingForUserAcknowledgment = true
            if let actionDescription = step.actionDescription {
                logTestEvent("🎯 ACTION REQUIRED: \(actionDescription)")
                logTestEvent("⏳ Waiting for user to complete action...")
                logTestEvent("✅ Press 'Acknowledge Step' when ready to continue")
            }
        } else {
            // Auto-execute step without user action
            testSteps[currentTestStep].startTime = Date()
            
            // Schedule step timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + step.timeout) {
                self.completeCurrentStep()
            }
        }
    }
    
    /// User acknowledges they completed the current step
    func acknowledgeCurrentStep() {
        guard waitingForUserAcknowledgment else { return }
        
        waitingForUserAcknowledgment = false
        testSteps[currentTestStep].startTime = Date()
        
        logTestEvent("☑️ Step \(testSteps[currentTestStep].stepNumber) acknowledged by user")
        
        // Start monitoring for expected events with timeout
        let step = testSteps[currentTestStep]
        DispatchQueue.main.asyncAfter(deadline: .now() + step.timeout) {
            self.completeCurrentStep()
        }
    }
    
    /// Completes the current step and moves to the next
    private func completeCurrentStep() {
        testSteps[currentTestStep].completed = true
        logTestEvent("✅ Step \(testSteps[currentTestStep].stepNumber) completed")
        
        currentTestStep += 1
        executeNextStep()
    }
    
    /// Enhanced Region Monitoring Test with step-by-step guidance
    func runStepByStepRegionTest() {
        let steps = [
            TestStep(
                stepNumber: 1,
                description: "Initialize region monitoring setup",
                requiresUserAction: false,
                actionDescription: nil,
                expectedEvents: [.monitoringStarted(Set([testBeacons[0]]))],
                timeout: 5.0
            ),
            TestStep(
                stepNumber: 2,
                description: "Position yourself far from the beacon",
                requiresUserAction: true,
                actionDescription: "Move to a location MORE than 100 meters away from the beacon. This ensures you start outside the beacon region.",
                expectedEvents: [],
                timeout: 30.0
            ),
            TestStep(
                stepNumber: 3,
                description: "Walk toward the beacon to trigger region entry",
                requiresUserAction: true,
                actionDescription: "Walk toward the beacon until you are within 50 meters. This should trigger a region entry event.",
                expectedEvents: [.regionEntered(testBeacons[0])],
                timeout: 60.0
            ),
            TestStep(
                stepNumber: 4,
                description: "Get close to the beacon for RSSI detection",
                requiresUserAction: true,
                actionDescription: "Move very close to the beacon (within 5 meters) to trigger RSSI ranging and see signal strength.",
                expectedEvents: [.beaconDetected(testBeacons[0], rssi: -50)],
                timeout: 30.0
            ),
            TestStep(
                stepNumber: 5,
                description: "Move away to trigger region exit",
                requiresUserAction: true,
                actionDescription: "Walk away from the beacon until you are more than 100 meters away to trigger region exit.",
                expectedEvents: [.regionExited(testBeacons[0])],
                timeout: 90.0
            )
        ]
        
        // Configure beacon monitoring for region testing
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: true,
            signalProcessingEnabled: true,
            proximityThreshold: -70,
            lostBeaconTimeout: 3.0
        )
        beaconMonitor.configuration = config
        beaconMonitor.setMonitoredBeacons(Set([testBeacons[0]]))
        beaconMonitor.startMonitoring()
        
        executeStepByStepTest("Step-by-Step Region Test", steps: steps)
    }
    
    /// Enhanced RSSI Test with step-by-step guidance
    func runStepByStepRSSITest() {
        let steps = [
            TestStep(
                stepNumber: 1,
                description: "Initialize RSSI ranging setup",
                requiresUserAction: false,
                actionDescription: nil,
                expectedEvents: [.monitoringStarted(Set([testBeacons[0]]))],
                timeout: 5.0
            ),
            TestStep(
                stepNumber: 2,
                description: "Ensure beacon is broadcasting",
                requiresUserAction: true,
                actionDescription: "Verify your beacon is powered on and broadcasting. Check that the beacon LED is blinking if it has one.",
                expectedEvents: [],
                timeout: 10.0
            ),
            TestStep(
                stepNumber: 3,
                description: "Position yourself close to the beacon",
                requiresUserAction: true,
                actionDescription: "Move within 3 meters of the beacon. You should see strong RSSI readings (closer to 0 dBm).",
                expectedEvents: [.beaconDetected(testBeacons[0], rssi: -30)],
                timeout: 30.0
            ),
            TestStep(
                stepNumber: 4,
                description: "Move to medium distance",
                requiresUserAction: true,
                actionDescription: "Move to about 10 meters from the beacon. RSSI should decrease (more negative values).",
                expectedEvents: [.proximityChanged(testBeacons[0], proximity: .near)],
                timeout: 20.0
            ),
            TestStep(
                stepNumber: 5,
                description: "Move to far distance",
                requiresUserAction: true,
                actionDescription: "Move to about 30+ meters from the beacon. RSSI should show far proximity.",
                expectedEvents: [.proximityChanged(testBeacons[0], proximity: .far)],
                timeout: 30.0
            ),
            TestStep(
                stepNumber: 6,
                description: "Move out of range",
                requiresUserAction: true,
                actionDescription: "Move very far away (50+ meters) or block the signal. The beacon should be lost after timeout.",
                expectedEvents: [.beaconLost(testBeacons[0])],
                timeout: 60.0
            )
        ]
        
        // Configure for RSSI-only testing
        let config = BeaconMonitoringConfig(
            useRegionMonitoring: false,
            signalProcessingEnabled: true,
            proximityThreshold: -80,
            lostBeaconTimeout: 5.0
        )
        beaconMonitor.configuration = config
        beaconMonitor.setMonitoredBeacons(Set([testBeacons[0]]))
        beaconMonitor.startMonitoring()
        
        executeStepByStepTest("Step-by-Step RSSI Test", steps: steps)
    }
    
    /// Helper function to create instructions banner
    func instructionsBanner(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Manual Control
    
    /// Manually starts monitoring with test beacons
    func startMonitoring() {
        beaconMonitor.setMonitoredBeacons(Set(testBeacons))
        beaconMonitor.startMonitoring()
        logTestEvent("Manual monitoring started")
    }
    
    /// Manually stops monitoring
    func stopMonitoring() {
        beaconMonitor.stopMonitoring()
        logTestEvent("Manual monitoring stopped")
    }
    
    /// Manually requests authorization
    func requestAuthorization() {
        beaconMonitor.requestAuthorization()
        logTestEvent("Authorization requested")
    }
    
    /// Clears all test events and metrics
    func clearEvents() {
        testEvents.removeAll()
        testMetrics = TestMetrics()
    }
    
    /// Simulates beacon behavior for controlled testing
    func simulateBeaconSequence() {
        startTest("Beacon Simulation Sequence")
        
        if let testMonitor = beaconMonitor as? TestBeaconMonitor {
            let beacon = BeaconID(uuid: UUID(uuidString: "E2C56DB5-0001-48D2-B060-D0F5A71096E0")!, major: 1331, minor: 1)
            
            testMonitor.setMonitoredBeacons([beacon])
            testMonitor.startMonitoring()
            
            // Simulate sequence from log analysis
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                testMonitor.simulateRegionEntered(beacon)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                testMonitor.simulateBeaconDetected(beacon, rssi: 0)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                testMonitor.simulateBeaconDetected(beacon, rssi: -84)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) {
                testMonitor.simulateBeaconDetected(beacon, rssi: -89)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 16.0) {
                testMonitor.simulateBeaconDetected(beacon, rssi: -74)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
                testMonitor.simulateBeaconDetected(beacon, rssi: -87)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 25.0) {
                testMonitor.simulateBeaconLost(beacon)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) {
                testMonitor.simulateRegionExited(beacon)
            }
            
            scheduleTestCompletion(timeout: 40.0)
            
            // Expected events based on simulation
            expectEvent(.monitoringStarted([beacon]), within: 1.0)
            expectEvent(.regionEntered(beacon), within: 3.0)
            expectEvent(.beaconDetected(beacon, rssi: 0), within: 6.0)
            expectEvent(.beaconDetected(beacon, rssi: -84), within: 9.0)
            expectEvent(.beaconLost(beacon), within: 26.0)
            expectEvent(.regionExited(beacon), within: 31.0)
        } else {
            logTestEvent("Simulation requires TestBeaconMonitor")
        }
    }
    
    /// Creates a TestBeaconMonitor for controlled simulation
    func switchToTestMonitor() {
        beaconMonitor = TestBeaconMonitor()
        setupEventMonitoring()
        logTestEvent("Switched to TestBeaconMonitor for simulation")
    }
    
    /// Switches back to real CoreLocationBeaconMonitor
    func switchToRealMonitor() {
        beaconMonitor = CoreLocationBeaconMonitor()
        setupEventMonitoring()
        logTestEvent("Switched to CoreLocationBeaconMonitor for real testing")
    }
    
    // MARK: - Private Methods
    
    private func setupEventMonitoring() {
        eventCancellable = beaconMonitor.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleBeaconEvent(event)
            }
    }
    
    private func handleBeaconEvent(_ event: BeaconEvent) {
        let testEvent = TestEvent(
            timestamp: Date(),
            beaconEvent: event,
            testDescription: "Beacon event received"
        )
        
        testEvents.append(testEvent)
        testMetrics.totalEvents += 1
        
        // Update metrics based on event type
        switch event {
        case .beaconDetected:
            testMetrics.detectionEvents += 1
        case .beaconLost:
            testMetrics.lossEvents += 1
        case .regionEntered:
            testMetrics.regionEntryEvents += 1
        case .regionExited:
            testMetrics.regionExitEvents += 1
        case .error:
            testMetrics.errorEvents += 1
        case .noBeacon:
            testMetrics.noBeaconEvents += 1
        case .missingBeacon:
            testMetrics.missingBeaconEvents += 1
        default:
            break
        }
        
        // Check expected events
        checkExpectedEvents(event)
        
        // Log event
        testLogger.info("Beacon event: \(String(describing: event))")
    }
    
    private func startTest(_ testName: String) {
        testStatus = .running(testName)
        testMetrics = TestMetrics()
        testMetrics.testStartTime = Date()
        
        logTestEvent("Starting test: \(testName)")
        testLogger.info("Starting test: \(testName)")
    }
    
    private func completeTest() {
        testTimer?.invalidate()
        testTimer = nil
        
        testMetrics.testEndTime = Date()
        
        let testName = switch testStatus {
        case .running(let name): name
        default: "Unknown"
        }
        
        testStatus = .completed(testName)
        logTestEvent("Test completed: \(testName)")
        testLogger.info("Test completed: \(testName)")
        
        // Stop monitoring
        beaconMonitor.stopMonitoring()
    }
    
    private func scheduleTestCompletion(timeout: TimeInterval) {
        testTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.completeTest()
        }
    }
    
    private func expectEvent(_ expectedEvent: BeaconEvent, within timeout: TimeInterval) {
        let expectation = EventExpectation(event: expectedEvent, timeout: timeout)
        testMetrics.expectedEvents.append(expectation)
        
        // Set up timeout for this expectation
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
            if !expectation.fulfilled {
                expectation.timedOut = true
                self.logTestEvent("Expected event timed out: \(expectedEvent)")
            }
        }
    }
    
    private func checkExpectedEvents(_ event: BeaconEvent) {
        for expectation in testMetrics.expectedEvents {
            if !expectation.fulfilled && expectation.event == event {
                expectation.fulfilled = true
                expectation.actualTime = Date()
                logTestEvent("Expected event fulfilled: \(event)")
            }
        }
    }
    
    private func logTestEvent(_ message: String) {
        let testEvent = TestEvent(
            timestamp: Date(),
            beaconEvent: nil,
            testDescription: message
        )
        testEvents.append(testEvent)
    }
}

// MARK: - Supporting Types

/// Represents a test event with timestamp and context
struct TestEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let beaconEvent: BeaconEvent?
    let testDescription: String
    
    var displayDescription: String {
        if let event = beaconEvent {
            return "\(testDescription): \(event)"
        } else {
            return testDescription
        }
    }
}

/// Current status of the test harness
enum TestStatus {
    case idle
    case running(String)
    case completed(String)
    case failed(String, Error)
    
    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .running(let name):
            return "Running: \(name)"
        case .completed(let name):
            return "Completed: \(name)"
        case .failed(let name, let error):
            return "Failed: \(name) - \(error.localizedDescription)"
        }
    }
}

/// Test metrics and statistics
struct TestMetrics {
    var testStartTime: Date?
    var testEndTime: Date?
    var totalEvents: Int = 0
    var detectionEvents: Int = 0
    var lossEvents: Int = 0
    var regionEntryEvents: Int = 0
    var regionExitEvents: Int = 0
    var errorEvents: Int = 0
    var noBeaconEvents: Int = 0
    var missingBeaconEvents: Int = 0
    var expectedEvents: [EventExpectation] = []
    
    var testDuration: TimeInterval? {
        guard let start = testStartTime, let end = testEndTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var eventsPerSecond: Double? {
        guard let duration = testDuration, duration > 0 else { return nil }
        return Double(totalEvents) / duration
    }
    
    var fulfilledExpectations: Int {
        expectedEvents.filter { $0.fulfilled }.count
    }
    
    var timedOutExpectations: Int {
        expectedEvents.filter { $0.timedOut }.count
    }
}

/// Represents an expected event with timeout and fulfillment tracking
class EventExpectation: ObservableObject {
    let event: BeaconEvent
    let timeout: TimeInterval
    let createdAt: Date
    
    @Published var fulfilled: Bool = false
    @Published var timedOut: Bool = false
    var actualTime: Date?
    
    init(event: BeaconEvent, timeout: TimeInterval) {
        self.event = event
        self.timeout = timeout
        self.createdAt = Date()
    }
    
    var responseTime: TimeInterval? {
        guard let actualTime = actualTime else { return nil }
        return actualTime.timeIntervalSince(createdAt)
    }
}

// MARK: - Test Harness UI

/// SwiftUI view for the beacon monitor test harness
struct BeaconMonitorTestHarnessView: View {
    @StateObject private var harness: BeaconMonitorTestHarness
    @State private var selectedTab = 0
    @State private var autoScroll = true
    
    init(beaconMonitor: BeaconMonitorProtocol? = nil) {
        if let monitor = beaconMonitor {
            self._harness = StateObject(wrappedValue: BeaconMonitorTestHarness(beaconMonitor: monitor))
        } else {
            self._harness = StateObject(wrappedValue: BeaconMonitorTestHarness())
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Status Section - Always visible
                statusSection
                
                // Tab Selection
                Picker("Test Category", selection: $selectedTab) {
                    Text("Quick").tag(0)
                    Text("Basic").tag(1)
                    Text("Components").tag(2)
                    Text("Events").tag(3)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Tab Content
                TabView(selection: $selectedTab) {
                    quickActionsTab.tag(0)
                    basicTestsTab.tag(1)
                    componentTestsTab.tag(2)
                    eventsTab.tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Instructions banner
                if selectedTab == 1 || selectedTab == 2 {
                    harness.instructionsBanner(
                        "Test Instructions",
                        "These tests require physical beacons. Follow the step-by-step instructions shown in each test."
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("Beacon Test Harness")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Status:")
                    .font(.headline)
                Text(harness.testStatus.description)
                    .font(.subheadline)
                    .foregroundColor(statusColor)
                Spacer()
                if let duration = harness.testMetrics.testDuration {
                    Text("\(String(format: "%.1f", duration))s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Compact metrics
            HStack {
                Text("Events: \(harness.testMetrics.totalEvents)")
                Text("Errors: \(harness.testMetrics.errorEvents)")
                Text("Expected: \(harness.testMetrics.fulfilledExpectations)/\(harness.testMetrics.expectedEvents.count)")
                Spacer()
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }
    
    private var quickActionsTab: some View {
        VStack(spacing: 20) {
            // Step-by-step tests
            if harness.waitingForUserAcknowledgment {
                stepByStepSection
            } else {
                // Basic Controls
                VStack(spacing: 15) {
                    Text("Monitor Control")
                        .font(.headline)
                    
                    HStack(spacing: 15) {
                        Button("Start") { harness.startMonitoring() }
                            .buttonStyle(BorderedProminentButtonStyle())
                            .frame(maxWidth: .infinity)
                        
                        Button("Stop") { harness.stopMonitoring() }
                            .buttonStyle(BorderedButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                    
                    HStack(spacing: 15) {
                        Button("Request Auth") { harness.requestAuthorization() }
                            .buttonStyle(BorderedButtonStyle())
                            .frame(maxWidth: .infinity)
                        
                        Button("Clear Events") { harness.clearEvents() }
                            .buttonStyle(BorderedButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                }
                
                Divider()
                
                // Step-by-step guided tests
                VStack(spacing: 15) {
                    Text("Guided Tests")
                        .font(.headline)
                    
                    Button("Step-by-Step Region Test") { harness.runStepByStepRegionTest() }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .frame(maxWidth: .infinity)
                    
                    Button("Step-by-Step RSSI Test") { harness.runStepByStepRSSITest() }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .frame(maxWidth: .infinity)
                    
                    Button("Region Entry/Exit Test") { harness.runRegionMultipleEntryExitTest() }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                // Monitor Type
                VStack(spacing: 15) {
                    Text("Monitor Type")
                        .font(.headline)
                    
                    HStack(spacing: 15) {
                        Button("Real Monitor") { harness.switchToRealMonitor() }
                            .buttonStyle(BorderedButtonStyle())
                            .frame(maxWidth: .infinity)
                        
                        Button("Test Monitor") { harness.switchToTestMonitor() }
                            .buttonStyle(BorderedButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                    
                    Button("Run Simulation") { harness.simulateBeaconSequence() }
                        .buttonStyle(BorderedProminentButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }
            
            Spacer()
        }
        .padding()
    }
    
    private var stepByStepSection: some View {
        VStack(spacing: 20) {
            // Current step info
            VStack(alignment: .leading, spacing: 10) {
                Text("Step \(harness.currentTestStep + 1) of \(harness.testSteps.count)")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(harness.currentStepDescription)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let step = harness.testSteps[safe: harness.currentTestStep],
                   let actionDescription = step.actionDescription {
                    Text("ACTION: \(actionDescription)")
                        .font(.callout)
                        .foregroundColor(.orange)
                        .padding(10)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Acknowledge button
            Button("Acknowledge Step Completed") {
                harness.acknowledgeCurrentStep()
            }
            .buttonStyle(BorderedProminentButtonStyle())
            .frame(maxWidth: .infinity)
            .disabled(!harness.waitingForUserAcknowledgment)
            
            // Progress indicator
            ProgressView(value: Double(harness.currentTestStep), total: Double(harness.testSteps.count))
                .progressViewStyle(LinearProgressViewStyle())
            
            Spacer()
        }
        .padding()
    }
    
    private var basicTestsTab: some View {
        ScrollView {
            VStack(spacing: 15) {
                Text("Standard Test Scenarios")
                    .font(.headline)
                    .padding(.top)
                
                // Current step indicator if in step-by-step mode
                if !harness.testSteps.isEmpty {
                    VStack {
                        Text("Current Test Progress")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        ProgressView(value: Double(harness.currentTestStep), total: Double(harness.testSteps.count))
                            .progressViewStyle(LinearProgressViewStyle())
                        
                        Text("Step \(harness.currentTestStep + 1) of \(harness.testSteps.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    TestButton("Basic Test", action: harness.runBasicMonitoringTest)
                    TestButton("Region Test", action: harness.runRegionTransitionTest)
                    TestButton("Config Test", action: harness.runConfigurationChangeTest)
                    TestButton("Permission", action: harness.runPermissionTest)
                    TestButton("Stress Test", action: harness.runStressTest)
                    TestButton("Stability Test", action: harness.runStabilityTest)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var componentTestsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Region Manager Tests
                VStack(spacing: 12) {
                    Text("Region Manager")
                        .font(.headline)
                        .padding(.top)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        TestButton("Region Init", action: harness.runRegionManagerInitializationTest, style: .compact)
                        TestButton("Region Cycle", action: harness.runRegionTransitionCycleTest, style: .compact)
                        TestButton("Multi Entry/Exit", action: harness.runRegionMultipleEntryExitTest, style: .compact)
                        TestButton("Delegate Test", action: harness.runRegionDelegateReassignmentTest, style: .compact)
                    }
                }
                
                Divider()
                
                // RSSI Manager Tests
                VStack(spacing: 12) {
                    Text("RSSI Manager")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        TestButton("RSSI Detection", action: harness.runRSSIDetectionTest, style: .compact)
                        TestButton("Signal Variation", action: harness.runSignalStrengthVariationTest, style: .compact)
                        TestButton("No Beacon", action: harness.runNoBeaconDetectionTest, style: .compact)
                        TestButton("Always Ranging", action: harness.runAlwaysRangingCoordinationTest, style: .compact)
                    }
                }
                
                Divider()
                
                // Other Tests
                VStack(spacing: 12) {
                    Text("System Tests")
                        .font(.headline)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        TestButton("Delegate Test", action: harness.runManagerDelegateTest, style: .compact)
                        TestButton("Background", action: harness.runBackgroundTransitionTest, style: .compact)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var eventsTab: some View {
        VStack(spacing: 0) {
            // Events header
            HStack {
                Text("Events (\(harness.testEvents.count))")
                    .font(.headline)
                
                Spacer()
                
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.top)
            
            // Events list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(harness.testEvents) { event in
                            eventRow(event)
                                .id(event.id)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: harness.testEvents.count) {
                    if autoScroll && !harness.testEvents.isEmpty {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(harness.testEvents.last?.id)
                        }
                    }
                }
            }
        }
    }
    
    private var statusColor: Color {
        switch harness.testStatus {
        case .idle:
            return .primary
        case .running:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private func eventRow(_ event: TestEvent) -> some View {
        HStack {
            Text(DateFormatter.timeFormatter.string(from: event.timestamp))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            
            Text(event.displayDescription)
                .font(.caption)
                .lineLimit(3)
            
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

// MARK: - TestButton Helper

struct TestButton: View {
    let title: String
    let action: () -> Void
    let style: Style
    
    enum Style {
        case normal
        case compact
    }
    
    init(_ title: String, action: @escaping () -> Void, style: Style = .normal) {
        self.title = title
        self.action = action
        self.style = style
    }
    
    var body: some View {
        Group {
            if style == .normal {
                Button(title, action: action)
                    .buttonStyle(BorderedProminentButtonStyle())
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            } else {
                Button(title, action: action)
                    .buttonStyle(BorderedButtonStyle())
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
        }
    }
}

// MARK: - Extensions

private extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

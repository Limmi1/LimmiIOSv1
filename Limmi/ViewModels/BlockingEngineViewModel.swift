//
//  BlockingEngineViewModel.swift
//  Limmi
//
//  Purpose: SwiftUI-optimized ViewModel that bridges BlockingEngine to reactive UI
//  Provides clean separation between domain logic and presentation logic
//

import Foundation
import SwiftUI
import Combine
import CoreLocation
import os
import FirebaseFirestore

/// SwiftUI-optimized ViewModel that exposes BlockingEngine functionality in a reactive, view-friendly way
/// 
/// This ViewModel serves as a clean abstraction layer between the BlockingEngine
/// and SwiftUI views, providing only the data and operations that views actually need
/// while maintaining protocol-based architecture for testability and flexibility.
///
/// ## Key Benefits:
/// - **Focused API**: Only exposes what views need, not entire BlockingEngine interface
/// - **SwiftUI Native**: Built specifically for @EnvironmentObject usage
/// - **Reactive**: All data automatically updates UI through @Published properties
/// - **Testable**: Easy to unit test with mock BlockingEngine implementations
/// - **Proper Separation**: Views don't directly access business logic layer
@MainActor
class BlockingEngineViewModel: ObservableObject {
    
    // MARK: - Published Properties for Views
    
    /// Indicates whether the blocking engine is currently active and monitoring
    @Published var isActive: Bool = false
    
    /// Current state of app blocking including active restrictions and authorization status
    @Published var currentBlockingState: BlockingState = BlockingState()
    
    /// Current user location from the location provider
    @Published var currentLocation: CLLocation?
    
    /// Array of beacon IDs that are currently near the user
    @Published var nearBeacons: [BeaconID] = []
    
    /// Performance metrics for monitoring system health and debugging
    @Published var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    
    /// Trigger for UI updates when blocking conditions change
    @Published var blockingConditionsChanged: Date = Date()
    
    // MARK: - Private Properties
    
    /// The underlying BlockingEngine implementation
    private let blockingEngine: BlockingEngine
    
    /// Combine cancellables for reactive subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Timer for time-based rule evaluation - only active when time-based rules exist
    private var timeBasedTimer: Timer?
    
    /// Tracks if we have time-based rules to avoid unnecessary timer operations
    private var hasTimeBasedRules: Bool = false
    
    /// Debouncer for rapid state changes
    private let debouncer = PassthroughSubject<Void, Never>()
    
    /// Logger for debugging and monitoring
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BlockingEngineViewModel")
    )
    
    // MARK: - Initialization
    
    /// Initialize with a BlockingEngine instance
    /// - Parameter blockingEngine: The BlockingEngine to wrap
    init(blockingEngine: BlockingEngine) {
        self.blockingEngine = blockingEngine
        setupReactiveBindings()
    }
    
    // MARK: - Setup Methods
    
    /// Setup reactive bindings from BlockingEngine to Published properties
    private func setupReactiveBindings() {
        // Bind engine state
        blockingEngine.$isActive
            .receive(on: DispatchQueue.main)
            .assign(to: \.isActive, on: self)
            .store(in: &cancellables)
        
        // Bind blocking state
        blockingEngine.$currentBlockingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.currentBlockingState = newState
                self?.triggerDebounced()
            }
            .store(in: &cancellables)
        
        // Bind location
        blockingEngine.$currentLocation
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newLocation in
                self?.currentLocation = newLocation
                self?.triggerDebounced()
            }
            .store(in: &cancellables)
        
        // Bind near beacons
        blockingEngine.$nearBeacons
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newBeacons in
                self?.nearBeacons = newBeacons
                self?.triggerDebounced()
            }
            .store(in: &cancellables)
        
        // Bind performance metrics
        blockingEngine.$performanceMetrics
            .receive(on: DispatchQueue.main)
            .assign(to: \.performanceMetrics, on: self)
            .store(in: &cancellables)
        
        // Monitor rule changes to update timer state
        blockingEngine.activeRulesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rules in
                self?.updateTimeBasedRuleTracking(rules)
            }
            .store(in: &cancellables)
        
        // Setup debounced state updates
        debouncer
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.blockingConditionsChanged = Date()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods for Views
    
    /// Checks if a rule is currently blocking any apps based on current conditions
    /// - Parameter rule: The rule to evaluate
    /// - Returns: True if the rule is currently blocking apps
    func isRuleCurrentlyBlocking(_ rule: Rule) -> Bool {
        return blockingEngine.isRuleCurrentlyBlocking(rule)
    }
    
    /// Gets the current status of all conditions in a rule
    /// - Parameter rule: The rule to evaluate conditions for
    /// - Returns: RuleConditionStatus with detailed condition states
    func getRuleConditionStatus(_ rule: Rule) -> RuleConditionStatus {
        return blockingEngine.getRuleConditionStatus(rule)
    }
    
    /// Forces immediate rule evaluation regardless of throttling intervals
    func forceEvaluation() {
        logger.debug("Force evaluation requested from UI")
        blockingEngine.forceEvaluation()
    }
    
    /// Refresh rules from data source
    func refreshRules() {
        logger.debug("Refresh rules requested from UI")
        blockingEngine.refreshRules()
    }
    
    /// Start the blocking engine
    func start() {
        logger.debug("Start requested from UI")
        blockingEngine.start()
    }
    
    /// Start the blocking engine after waiting for Firebase data
    func startWhenReady() async throws {
        logger.debug("Start when ready requested from UI")
        try await blockingEngine.startWhenReady()
    }
    
    /// Stop the blocking engine
    func stop() {
        logger.debug("Stop requested from UI")
        blockingEngine.stop()
    }
    
    // MARK: - Computed Properties for Views
    
    /// Returns whether the engine is currently monitoring and active
    var isMonitoring: Bool {
        return isActive
    }
    
    /// Returns the count of currently detected beacons
    var nearBeaconCount: Int {
        return nearBeacons.count
    }
    
    /// Returns whether location services are available
    var hasLocation: Bool {
        return currentLocation != nil
    }
    
    /// Returns the current location coordinate for display
    var currentCoordinate: CLLocationCoordinate2D? {
        return currentLocation?.coordinate
    }
    
    // MARK: - Private Methods
    
    /// Triggers debounced state updates
    private func triggerDebounced() {
        debouncer.send()
    }
    
    /// Updates timer state based on whether time-based rules exist
    private func updateTimeBasedRuleTracking(_ rules: [Rule]) {
        let newHasTimeBasedRules = rules.contains { rule in
            rule.isActive && !rule.timeRules.isEmpty
        }
        
        // Only update timer if state changed
        if newHasTimeBasedRules != hasTimeBasedRules {
            hasTimeBasedRules = newHasTimeBasedRules
            updateTimeBasedTimer()
            logger.debug("Time-based rules status changed: \(hasTimeBasedRules ? "enabled" : "disabled")")
        }
    }
    
    /// Starts or stops the time-based timer based on rule requirements
    private func updateTimeBasedTimer() {
        // Stop existing timer
        timeBasedTimer?.invalidate()
        timeBasedTimer = nil
        
        // Start new timer only if time-based rules exist
        if hasTimeBasedRules {
            logger.debug("Starting time-based timer for time-sensitive rules")
            timeBasedTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
                self?.logger.debug("Time-based timer triggered evaluation")
                self?.triggerDebounced()
            }
        } else {
            logger.debug("No time-based rules found, timer disabled")
        }
    }
    
    /// Cleanup resources when view model is deallocated
    deinit {
        timeBasedTimer?.invalidate()
        logger.debug("BlockingEngineViewModel deallocated, timer cleaned up")
    }
}

// MARK: - Preview Support

#if DEBUG
extension BlockingEngineViewModel {
    /// Creates a mock view model for SwiftUI previews
    static func mock() -> BlockingEngineViewModel {
        // For now, just create the minimum to avoid preview crash
        // In a real app, you would implement proper mocking
        fatalError("Preview mock not implemented - use real dependencies or implement proper mocking")
    }
}
#endif
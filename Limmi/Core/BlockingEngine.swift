//
//  BlockingEngine.swift
//  Limmi
//
//  Purpose: Central orchestrator for the blocking system coordinating rules, beacons, and app restrictions
//  Dependencies: CoreLocation, ManagedSettings, Combine, UnifiedLogger
//  Related: Blocker.swift, RuleStore.swift, BeaconMonitorProtocol.swift, LocationProvider.swift
//

import Foundation
import CoreLocation
import ManagedSettings
import Combine
import os
import FamilyControls


/// Central orchestrator for the blocking system that coordinates all components.
///
/// This class implements the core blocking logic by integrating multiple subsystems:
/// - Location monitoring (GPS and beacon proximity)
/// - Rule evaluation (time-based, location-based, beacon-based)
/// - App blocking enforcement via Screen Time API
/// - Performance monitoring and event processing
///
/// ## Architecture
/// The blocking engine follows a reactive architecture where:
/// 1. Rules are loaded from Firebase and cached locally
/// 2. Location and beacon events trigger rule evaluation
/// 3. Rule evaluation determines which apps should be blocked
/// 4. Blocking decisions are applied via the Blocker protocol
///
/// ## Initialization Sequence
/// 1. Wait for Firebase data to load (rules, apps, beacons)
/// 2. Create all dependencies with loaded data
/// 3. Start location and beacon monitoring
/// 4. Begin reactive rule evaluation
///
/// ## Performance
/// - Event processing is queued to prevent UI blocking
/// - Rule evaluation is throttled to avoid excessive computation
/// - Performance metrics are collected when enabled
///
/// - Important: Must run on MainActor due to Published properties and UI integration
/// - Since: 1.0
@MainActor
final class BlockingEngine: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Indicates whether the blocking engine is currently active and monitoring.
    @Published var isActive: Bool = false
    
    /// Current state of app blocking including active restrictions and authorization status.
    /// Updated automatically when blocking decisions change. UI components observe this for reactive updates.
    @Published var currentBlockingState: BlockingState = BlockingState()
    
    /// Comprehensive beacon status registry for sophisticated rule processing.
    /// Maintains detailed state information for all tracked beacons including proximity,
    /// signal quality, and presence history.
    @Published var beaconRegistry: BeaconRegistry = BeaconRegistry()
    
    /// Array of beacon IDs that are currently near the user (legacy compatibility).
    /// This property is now computed from the beacon registry for backward compatibility.
    @Published var nearBeacons: [BeaconID] = []
    
    /// Current user location from the location provider.
    /// Used for GPS-based rule evaluation and logging.
    @Published var currentLocation: CLLocation?
    
    /// Performance metrics for monitoring system health and debugging.
    /// Includes counters for events, rule evaluations, and timing data.
    @Published var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    
    // MARK: - Dependencies
    
    /// Provides location updates and manages location permissions.
    private let locationProvider: LocationProvider
    
    /// Monitors beacon proximity and publishes beacon events.
    private let beaconMonitor: BeaconMonitorProtocol
    
    /// Exposes the beacon monitor for testing and debugging purposes
    var testBeaconMonitor: BeaconMonitorProtocol {
        beaconMonitor
    }
    
    /// Time provider for rule evaluation (abstracted for testability).
    private let clock: Clock
    
    /// Manages rules, blocked apps, and beacon devices from Firebase.
    private let ruleStore: any RuleStore
    
    /// Handles app blocking via Screen Time API.
    private let blocker: Blocker

    /// Strategy for rule processing (pluggable and updatable)
    private var ruleProcessingStrategy: RuleProcessingStrategy
    
    /// Time limit checker that takes precedence over Firebase rules
    private let timeLimitChecker = TimeLimitChecker()
    
    // MARK: - Private Properties
    
    /// Stores Combine subscriptions for reactive data flow.
    private var cancellables = Set<AnyCancellable>()
    
    /// Cached active rules for change detection to prevent unnecessary processing
    private var activeRules: [Rule] = []
    
    /// Cached blocked tokens for change detection to prevent unnecessary processing
    private var blockedTokens: [BlockedTokenInfo] = []
    
    /// Processes events asynchronously to prevent blocking the main thread.
    private let eventProcessor: EventProcessor
    
    /// Monitors performance metrics when enabled in configuration.
    private let performanceMonitor: PerformanceMonitor
    
    /// Manages heartbeat signals for force-quit detection.
    /// Optional since heartbeat may not be available in all configurations.
    private let heartbeatManager: (any HeartbeatProtocol)?
    
    /// Manages DeviceActivity threshold monitoring for heartbeat-based blocking.
    /// Optional since DeviceActivity monitoring may not be available in all configurations.
    private let deviceActivityService: DeviceActivityHeartbeatService?
    
    /// Unified logger for both file and system logging.
    /// Critical for debugging background behavior when debugger is not attached.
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BlockingEngine")
    )
    
    /// Cache of the most recent rule evaluation results.
    /// Maps rule IDs to their current blocking status to ensure consistency
    /// between evaluateBlockingRules and isRuleCurrentlyBlocking.
    private var currentRuleResults: [String: Bool] = [:]
    
    /// Cache of the most recent detailed rule evaluation results.
    /// Maps rule IDs to their detailed condition status for UI display.
    private var currentDetailedResults: [String: DetailedRuleEvaluationResult] = [:]
    
    // MARK: - Configuration
    
    /// Configuration options for the blocking engine.
    ///
    /// Allows customization of performance monitoring, logging levels,
    /// and processing thresholds for different deployment scenarios.
    struct Configuration {
        /// Enable performance metrics collection (may impact performance).
        let enablePerformanceMonitoring: Bool
        
        /// Enable detailed debug logging (increases log volume).
        let enableDetailedLogging: Bool
        
        /// Maximum number of events in processing queue.
        let eventProcessingQueueSize: Int
        
        /// Minimum interval between rule evaluations (throttling).
        let blockingEvaluationInterval: TimeInterval
        
        /// Minimum distance change to trigger location-based rule evaluation.
        let locationUpdateThreshold: Double
        
        /// Default production configuration with conservative settings.
        static let `default` = Configuration(
            enablePerformanceMonitoring: false,
            enableDetailedLogging: false,
            eventProcessingQueueSize: 100,
            blockingEvaluationInterval: 1.0,
            locationUpdateThreshold: 0.0
        )
    }
    
    private let configuration: Configuration
    
    // MARK: - Initialization
    
    init(
        locationProvider: LocationProvider,
        beaconMonitor: any BeaconMonitorProtocol,
        clock: Clock,
        ruleStore: any RuleStore,
        blocker: Blocker,
        configuration: Configuration = .default,
        heartbeatManager: (any HeartbeatProtocol)? = nil,
        deviceActivityService: DeviceActivityHeartbeatService? = nil,
        ruleProcessingStrategy: RuleProcessingStrategy = RuleProcessingStrategyType.defaultStrategy.createStrategy()
    ) {
        self.locationProvider = locationProvider
        self.beaconMonitor = beaconMonitor
        self.clock = clock
        self.ruleStore = ruleStore
        self.blocker = blocker
        self.configuration = configuration
        self.heartbeatManager = heartbeatManager
        self.deviceActivityService = deviceActivityService
        self.ruleProcessingStrategy = ruleProcessingStrategy
        
        self.eventProcessor = EventProcessor(
            queueSize: configuration.eventProcessingQueueSize,
            processingInterval: configuration.blockingEvaluationInterval
        )
        
        self.performanceMonitor = PerformanceMonitor(
            enabled: configuration.enablePerformanceMonitoring
        )
        
        setupSubscriptions()
        // initializeMonitoring()
    }
    
    // MARK: - Public Methods
    
    func start() {
        logger.debug("Starting BlockingEngine")
        performanceMonitor.startOperation(.engineStart)
        
        isActive = true
        
        // Start all services
        locationProvider.requestAuthorization()
        beaconMonitor.requestAuthorization()
        blocker.requestAuthorization()
        
        locationProvider.startLocationUpdates()
        beaconMonitor.startMonitoring()
        
        // Initial rule evaluation
        updateMonitoredBeacons()
        updateMonitoredRegions()
        
        performanceMonitor.endOperation(.engineStart)
        logger.debug("BlockingEngine started successfully")
    }
    
    /// Starts the blocking engine after waiting for all Firebase data to load.
    ///
    /// This method implements the recommended initialization sequence:
    /// 1. Waits for Firebase data (rules, apps, beacons) to fully load
    /// 2. Requests necessary permissions (location, Screen Time)
    /// 3. Starts monitoring services with complete rule context
    /// 4. Performs initial rule evaluation with loaded data
    ///
    /// Use this method instead of `start()` when you need to ensure all
    /// data is available before beginning monitoring operations.
    ///
    /// - Throws: FirebaseError if data loading fails, or authorization errors
    func startWhenReady() async throws {
        logger.debug("Starting BlockingEngine - waiting for data to load")
        performanceMonitor.startOperation(.engineStart)
        
        // Wait for Firebase data to load if RuleStore supports it
        if let firebaseRuleStore = ruleStore as? FirebaseRuleStore {
            try await firebaseRuleStore.waitForInitialDataLoad()
            logger.debug("Firebase data loaded successfully")
        }
        
        isActive = true
        
        // Start all services
        locationProvider.requestAuthorization()
        beaconMonitor.requestAuthorization()
        blocker.requestAuthorization()
        
        locationProvider.startLocationUpdates()
        beaconMonitor.startMonitoring()
        
        // Initial rule evaluation with loaded data
        // updateMonitoredBeacons()
        // updateMonitoredRegions()
        
        performanceMonitor.endOperation(.engineStart)
        logger.debug("BlockingEngine started successfully with loaded data")
    }
    
    func stop() {
        logger.debug("Stopping BlockingEngine")
        
        isActive = false
        
        // Stop all services
        beaconMonitor.stopMonitoring()
        locationProvider.stopLocationUpdates()
        
        // Clear state
        nearBeacons.removeAll()
        currentLocation = nil
        
        logger.debug("BlockingEngine stopped")
    }
    
    /// Forces immediate rule evaluation regardless of throttling intervals.
    ///
    /// This method bypasses normal throttling and immediately evaluates all active rules
    /// against current context (location, beacons, time). Useful for:
    /// - Manual testing and debugging
    /// - Responding to significant state changes
    /// - UI-triggered rule evaluation
    ///
    /// - Note: Should be used sparingly as it can impact performance
    func forceEvaluation() {
        logger.debug("Force evaluation requested")
        performanceMonitor.startOperation(.ruleEvaluation)
        
        evaluateBlockingRules()
        
        performanceMonitor.endOperation(.ruleEvaluation)
    }
    
    /// Refreshes time limits and forces rule evaluation
    /// This should be called when time limits are added, modified, or deleted
    func refreshTimeLimits() {
        logger.debug("Refreshing time limits")
        timeLimitChecker.refreshTimeLimits()
        forceEvaluation()
    }
    
    func refreshRules() {
        logger.debug("Refreshing rules")
        ruleStore.refreshRules()
        
        // removing the unecessary refresh, those should be done using the subscription on rules events. (rules refresh is async, upadting now risk using old rules or a temp state of rules)
        //updateMonitoredBeacons()
        //updateMonitoredRegions()
    }
    
    // MARK: - Rule Management API (for UI)
    
    /// Adds a new blocking rule to the rule store.
    ///
    /// Creates a new rule and persists it to Firebase. The rule will automatically
    /// be included in future blocking evaluations once successfully saved.
    ///
    /// - Parameters:
    ///   - rule: The rule to add
    ///   - completion: Callback with the saved rule or error
    func addRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void) {
        logger.debug("Adding rule: \(rule.name)")
        ruleStore.addRule(rule, completion: completion)
    }
    
    func updateRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void) {
        logger.debug("Updating rule: \(rule.name)")
        ruleStore.updateRule(rule, completion: completion)
    }
    
    func deleteRule(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.debug("Deleting rule: \(id)")
        ruleStore.deleteRule(id: id, completion: completion)
    }
    
    func getActiveRules() -> [Rule] {
        return ruleStore.activeRules()
    }
    
    func getAllRules() -> [Rule] {
        return ruleStore.allRules()
    }
    
    // MARK: - Blocked Tokens Management API (for UI)
    
    func saveBlockedToken(_ token: BlockedTokenInfo, completion: @escaping (Result<BlockedTokenInfo, Error>) -> Void) {
        logger.debug("Saving blocked token: \(token.name)")
        ruleStore.saveBlockedToken(token, completion: completion)
    }
    
    func deleteBlockedToken(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.debug("Deleting blocked token: \(id)")
        ruleStore.deleteBlockedToken(id: id, completion: completion)
    }
    
    func getBlockedTokens() -> [BlockedTokenInfo] {
        return ruleStore.blockedTokens()
    }
    
    /// Publisher for blocked tokens for reactive UI updates
    var blockedTokensPublisher: AnyPublisher<[BlockedTokenInfo], Never> {
        return ruleStore.blockedTokensPublisher
    }
    
    /// Publisher for active rules for reactive UI updates
    var activeRulesPublisher: AnyPublisher<[Rule], Never> {
        return ruleStore.activeRulesPublisher
    }
    
    /// Checks if a rule is currently blocking any apps based on the most recent rule evaluation.
    /// This uses the cached results from evaluateBlockingRules to ensure consistency with
    /// the actual blocking decisions applied by the system.
    /// - Parameter rule: The rule to check
    /// - Returns: True if the rule is currently blocking apps according to the last evaluation
    func isRuleCurrentlyBlocking(_ rule: Rule) -> Bool {
        guard rule.isActive else { return false }
        guard !rule.blockedTokenIds.isEmpty else { return false }
        guard let ruleId = rule.id else { return false }
        
        // Use cached results from the most recent evaluateBlockingRules call
        // This ensures consistency with the actual blocking applied by the system
        return currentRuleResults[ruleId] ?? false
    }
    
    /// Evaluates the current status of each condition in a rule using cached evaluation results
    /// - Parameter rule: The rule to evaluate conditions for
    /// - Returns: RuleConditionStatus with detailed condition states
    func getRuleConditionStatus(_ rule: Rule) -> RuleConditionStatus {
        guard let ruleId = rule.id else {
            // Fallback for rules without IDs
            return RuleConditionStatus(
                isRuleActive: rule.isActive,
                hasBlockedApps: !rule.blockedTokenIds.isEmpty,
                gpsConditionStatus: .unknown,
                timeConditionStatus: .unknown,
                beaconConditionStatuses: [],
                overallBlockingStatus: false
            )
        }
        
        // Try to use cached detailed evaluation results
        if let detailedResult = currentDetailedResults[ruleId] {
            return convertDetailedResultToConditionStatus(detailedResult)
        }
        
        // Fallback: no cached results available (rule evaluation hasn't run yet)
        return RuleConditionStatus(
            isRuleActive: rule.isActive,
            hasBlockedApps: !rule.blockedTokenIds.isEmpty,
            gpsConditionStatus: rule.gpsLocation.isActive ? .unknown : .notApplicable,
            timeConditionStatus: rule.timeRules.isEmpty ? .notApplicable : .unknown,
            beaconConditionStatuses: rule.fineLocationRules.map { fineRule in
                BeaconConditionStatus(
                    beaconId: fineRule.beaconId,
                    behaviorType: fineRule.behaviorType,
                    isActive: fineRule.isActive,
                    status: fineRule.isActive ? .unknown : .notApplicable
                )
            },
            overallBlockingStatus: false
        )
    }
    
    /// Converts DetailedRuleEvaluationResult to RuleConditionStatus for UI consumption
    private func convertDetailedResultToConditionStatus(_ detailedResult: DetailedRuleEvaluationResult) -> RuleConditionStatus {
        // Convert GPS result
        let gpsStatus: ConditionStatus
        if let gpsResult = detailedResult.gpsResult {
            if gpsResult.isActive {
                gpsStatus = gpsResult.isUserInside ? .satisfied : .notSatisfied
            } else {
                gpsStatus = .notApplicable
            }
        } else {
            gpsStatus = .notApplicable
        }
        
        // Convert time results - overall time condition is satisfied if any time rule is satisfied
        let timeStatus: ConditionStatus
        if detailedResult.timeResults.isEmpty {
            timeStatus = .notApplicable
        } else {
            let hasActiveTimeRule = detailedResult.timeResults.contains { $0.isActive }
            if !hasActiveTimeRule {
                timeStatus = .notApplicable
            } else {
                let anyTimeRuleSatisfied = detailedResult.timeResults.contains { $0.isActive && $0.isCurrentTimeInRange }
                timeStatus = anyTimeRuleSatisfied ? .satisfied : .notSatisfied
            }
        }
        
        // Convert beacon results
        let beaconStatuses = detailedResult.beaconResults.map { beaconResult in
            let status: ConditionStatus
            if beaconResult.isActive {
                status = beaconResult.isUserNearBeacon ? .satisfied : .notSatisfied
            } else {
                status = .notApplicable
            }
            
            return BeaconConditionStatus(
                beaconId: beaconResult.beaconId,
                behaviorType: beaconResult.behaviorType,
                isActive: beaconResult.isActive,
                status: status
            )
        }
        
        return RuleConditionStatus(
            isRuleActive: detailedResult.isRuleActive,
            hasBlockedApps: true, // If we have detailed results, the rule must have blocked apps
            gpsConditionStatus: gpsStatus,
            timeConditionStatus: timeStatus,
            beaconConditionStatuses: beaconStatuses,
            overallBlockingStatus: detailedResult.overallShouldBlock
        )
    }
    
    /// Refresh blocked tokens from data source
    func refreshBlockedTokens() {
        logger.debug("Refreshing blocked tokens")
        ruleStore.refreshBlockedTokens()
    }
    
    /// Updates the rule processing strategy used for rule evaluation
    /// - Parameter newStrategy: The new strategy to use
    func updateRuleProcessingStrategy(_ newStrategy: RuleProcessingStrategy) {
        let oldStrategyType = String(describing: type(of: ruleProcessingStrategy))
        let newStrategyType = String(describing: type(of: newStrategy))
        
        // Skip update if strategy type hasn't changed (avoid duplicate updates)
        guard oldStrategyType != newStrategyType else {
            logger.debug("Strategy type unchanged (\(oldStrategyType)), skipping update")
            return
        }
        
        logger.debug("Updating rule processing strategy: \(oldStrategyType) → \(newStrategyType)")
        ruleProcessingStrategy = newStrategy
        
        // Force immediate rule evaluation with new strategy
        forceEvaluation()
    }
    
    // MARK: - Private Methods - Setup
    
    private func setupSubscriptions() {
        // Subscribe to rule changes
        ruleStore.activeRulesPublisher
            .sink { [weak self] rules in
                // Only process if rules have actually changed
                if !rules.isEquivalent(to: self?.activeRules ?? []) {
                    self?.logger.debug("BlockingEngine: Active rules changed, processing update")
                    self?.activeRules = rules
                    self?.handleRulesChanged(rules)
                } else {
                    self?.logger.debug("BlockingEngine: Active rules unchanged, skipping processing")
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to blocked tokens changes and update app-token mapping
        ruleStore.blockedTokensPublisher
            .sink { [weak self] blockedTokens in
                // Only process if blocked tokens have actually changed
                if !blockedTokens.isEquivalent(to: self?.blockedTokens ?? []) {
                    self?.logger.debug("BlockingEngine: Blocked tokens changed, updating app-token mapping")
                    self?.blockedTokens = blockedTokens
                    var mapping: [String: BlockedToken] = [:]
                    var tokens: Set<ApplicationToken> = []
                    
                    for tokenInfo in blockedTokens {
                        if let id = tokenInfo.id {
                            var blockedToken: BlockedToken?
                            
                            // Create BlockedToken based on type
                            switch tokenInfo.tokenType {
                            case "application":
                                if let appToken = tokenInfo.decodedApplicationToken() {
                                    blockedToken = BlockedToken(applicationToken: appToken, name: tokenInfo.displayName)
                                    tokens.insert(appToken)
                                }
                            case "webDomain":
                                if let webToken = tokenInfo.decodedWebDomainToken() {
                                    blockedToken = BlockedToken(webDomainToken: webToken, name: tokenInfo.displayName)
                                }
                            case "activityCategory":
                                if let categoryToken = tokenInfo.decodedActivityCategoryToken() {
                                    blockedToken = BlockedToken(activityCategoryToken: categoryToken, name: tokenInfo.displayName)
                                }
                            default:
                                break
                            }
                            
                            if let token = blockedToken {
                                mapping[id] = token
                            }
                        }
                    }
                    
                    self?.blocker.setTokenMapping(mapping)
                    
                    // Update DeviceActivity threshold monitoring with new blocked tokens
                    // Use Firebase-based tokens directly
                    self?.deviceActivityService?.startWithBlockedTokens(blockedTokens)
                } else {
                    self?.logger.debug("BlockingEngine: Blocked tokens unchanged, skipping mapping update")
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to beacon events
        beaconMonitor.eventPublisher
            .sink { [weak self] event in
                self?.handleBeaconEvent(event)
            }
            .store(in: &cancellables)
        
        // Subscribe to location updates
        locationProvider.locationPublisher
            .sink { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
        
        // Subscribe to blocking state changes
        blocker.blockingStatePublisher
            .sink { [weak self] state in
                self?.handleBlockingStateChanged(state)
            }
            .store(in: &cancellables)
        
        // Subscribe to processed events
        eventProcessor.processedEventPublisher
            .sink { [weak self] event in
                self?.handleProcessedEvent(event)
            }
            .store(in: &cancellables)
        
        // Subscribe to time limit changes
        timeLimitChecker.$timeLimitBlockedApps
            .sink { [weak self] _ in
                self?.logger.debug("Time limit blocked apps changed, forcing evaluation")
                self?.forceEvaluation()
            }
            .store(in: &cancellables)
    }
    
    private func initializeMonitoring() {
        // Set up initial beacon monitoring from rules
        updateMonitoredBeacons()
        updateMonitoredRegions()
        
        // Request initial location
        if locationProvider.isLocationAvailable {
            locationProvider.startLocationUpdates()
        }
    }
    
    // MARK: - Private Methods - Event Handlers
    
    private func handleRulesChanged(_ activeRules: [Rule]) {
        logger.debug("Rules changed: \(activeRules.count) active rules")
        performanceMonitor.incrementCounter(.ruleChanges)
        
        // Update heartbeat on rules changes
        heartbeatManager?.updateHeartbeat()
        
        // Sync active rule tokens to shared storage for DeviceActivityMonitor extension
        syncActiveRuleTokensToSharedStorage(rules: activeRules)
        
        updateMonitoredBeacons(from: activeRules)
        updateMonitoredRegions(from: activeRules)
        evaluateBlockingRules()
    }
    
    private func handleBeaconEvent(_ event: BeaconEvent) {
        //logger.debug("Beacon event: \(event)")
        performanceMonitor.incrementCounter(.beaconEvents)
        
        // Update heartbeat on beacon activity
        heartbeatManager?.updateHeartbeat()
        
        // Process event through beacon registry for enhanced tracking
        beaconRegistry.processEvent(event)
        
        // Update legacy nearBeacons array for backward compatibility
        updateNearBeaconsFromRegistry()
        
        // Queue event for processing
        eventProcessor.enqueue(event)
    }
    
    private func handleLocationUpdate(_ location: CLLocation) {
        logger.debug("Location update: \(location.coordinate)")
        performanceMonitor.incrementCounter(.locationUpdates)
        
        // Update heartbeat on location activity
        heartbeatManager?.updateHeartbeat()
        
        // Check if location change is significant
        if let currentLoc = currentLocation {
            let distance = location.distance(from: currentLoc)
            if distance < configuration.locationUpdateThreshold {
                return // Skip insignificant location changes
            }
        }
        
        currentLocation = location
        
        // Queue location event for processing
        let locationEvent = EventProcessor.ProcessedEvent.locationChanged(location)
        eventProcessor.enqueue(locationEvent)
    }
    
    private func handleBlockingStateChanged(_ state: BlockingState) {
        //logger.debug("Blocking state changed: \(state.blockedAppIds.count) apps blocked")
        currentBlockingState = state
        performanceMonitor.incrementCounter(.blockingStateChanges)
        
        // Update heartbeat on blocking state changes
        heartbeatManager?.updateHeartbeat()
    }
    
    private func handleProcessedEvent(_ event: EventProcessor.ProcessedEvent) {
        //logger.debug("Processed event: \(event)")
        
        // Update heartbeat on processed events
        heartbeatManager?.updateHeartbeat()
        
        switch event {
        case .beaconProximityChanged, .locationChanged, .ruleEvaluationRequested:
            evaluateBlockingRules()
        case .beaconDetected, .beaconLost:
            evaluateBlockingRules()
            break
        case .performanceThresholdExceeded(let metric):
            logger.debug("Performance threshold exceeded for metric: \(metric)")
            // Could trigger performance-based rule adjustments here
            break
        }
    }
    
    // MARK: - Private Methods - Core Logic
    
    private func updateMonitoredBeacons(from activeRules: [Rule]? = nil) {
        let rules = activeRules ?? ruleStore.activeRules()
        let newBeaconIds = extractBeaconIds(from: rules)
        let currentBeaconIds = beaconMonitor.monitoredBeacons
        
        // Only update if beacon set actually changed
        guard newBeaconIds != currentBeaconIds else {
            logger.debug("Beacon set unchanged (\(newBeaconIds.count) beacons), skipping monitoring update")
            return
        }
        
        logger.debug("Updating monitored beacons: \(currentBeaconIds.count) → \(newBeaconIds.count) beacons")
        beaconMonitor.setMonitoredBeacons(newBeaconIds)
        
        // Register beacons with the registry for enhanced tracking
        let beaconDevices = ruleStore.beaconDevices()
        beaconRegistry.registerBeacons(from: beaconDevices)
    }
    
    private func updateMonitoredRegions(from activeRules: [Rule]? = nil) {
        let rules = activeRules ?? ruleStore.activeRules()
        let gpsRules = rules.filter { $0.gpsLocation.isActive }
        
        logger.debug("Updating monitored GPS regions: \(gpsRules.count) GPS rules")
        locationProvider.updateRegions(from: rules)
    }
    
    private func extractBeaconIds(from rules: [Rule]) -> Set<BeaconID> {
        // Get beacon document IDs from rules
        let beaconDocumentIds = rules.flatMap { rule in
            rule.fineLocationRules.map { $0.beaconId }
        }
        
        // Look up beacon devices by document IDs
        let beaconDevices = ruleStore.beaconDevices(ids: beaconDocumentIds)
        
        // Convert beacon devices to BeaconID objects
        let beaconIds = beaconDevices.compactMap { device -> BeaconID? in
            guard device.isActive else { return nil }
            return BeaconID(from: device)
        }
        
        logger.debug("Extracted \(beaconIds.count) active beacons from \(beaconDocumentIds.count) beacon references")
        
        return Set(beaconIds)
    }
    
    /// Maps detected BeaconID objects back to their Firebase document IDs.
    ///
    /// This method bridges the gap between the low-level beacon detection system
    /// (which works with BeaconID value objects) and the rule evaluation system
    /// (which references beacon devices by Firebase document ID).
    ///
    /// - Returns: Array of Firebase document IDs for currently detected beacons
    private func getNearBeaconDocumentIds() -> [String] {
        let allBeaconDevices = ruleStore.beaconDevices()
        
        return nearBeacons.compactMap { detectedBeaconID in
            // Find the beacon device that matches this detected beacon
            return allBeaconDevices.first { device in
                guard device.isActive else { return false }
                let deviceBeaconID = BeaconID(from: device)
                return deviceBeaconID.matches(detectedBeaconID)
            }?.id
        }
    }
    
    /// Updates the legacy nearBeacons array from the beacon registry for backward compatibility
    private func updateNearBeaconsFromRegistry() {
        nearBeacons = Array(beaconRegistry.beaconsInRange)
    }
    
    /// Evaluates all active rules against current context and applies blocking decisions.
    ///
    /// This is the core method of the blocking engine that:
    /// 1. Gathers current context (location, time, nearby beacons)
    /// 2. Evaluates each active rule against this context
    /// 3. Determines which apps should be blocked based on rule results
    /// 4. Applies blocking decisions via the blocker
    ///
    /// ## Rule Evaluation Logic
    /// For each app and rule combination:
    /// - Check if rule is active and applies to this app
    /// - Evaluate GPS location requirements (if any)
    /// - Evaluate time-based requirements
    /// - Evaluate beacon proximity requirements
    /// - Block app only if ALL conditions are met
    ///
    /// ## Performance
    /// - Typically completes in <50ms for 10 rules
    /// - Performance is monitored when metrics are enabled
    /// - Results are cached until context changes
    private func evaluateBlockingRules() {
        performanceMonitor.startOperation(.ruleEvaluation)
        
        // Update heartbeat on rule evaluation
        heartbeatManager?.updateHeartbeat()
        
        guard let location = currentLocation else {
            logger.debug("No location available for rule evaluation")
            performanceMonitor.endOperation(.ruleEvaluation)
            return
        }
        
        let currentTime = clock.now()
        let rules = ruleStore.activeRules()
        let nearBeaconDocumentIds = getNearBeaconDocumentIds()
                
        // Get all app IDs that could be blocked
        let allBlockedAppIds = Set(rules.flatMap { $0.blockedTokenIds })
        
        // Evaluate rules using the rule processing strategy
        let evaluationResult = ruleProcessingStrategy.evaluateBlockingRules(
            rules: rules,
            location: location,
            beaconRegistry: beaconRegistry,
            currentTime: currentTime
        )
        
        // Cache rule evaluation results for consistency with isRuleCurrentlyBlocking
        currentRuleResults = evaluationResult.ruleBlockingStatus
        currentDetailedResults = evaluationResult.detailedResults
        
        // Apply blocking decisions with time limit precedence
        // Time limits take precedence over Firebase rules
        let timeLimitBlockedApps = timeLimitChecker.getTimeLimitBlockedApps()
        
        blocker.applyRuleBasedBlocking(
            for: Array(allBlockedAppIds),
            using: { appId in 
                // Time limits take precedence - if app is blocked by time limit, block it regardless of Firebase rules
                if timeLimitChecker.shouldBlockApp(appId) {
                    return true
                }
                // Otherwise, use Firebase rule evaluation result
                return evaluationResult.blockedAppIds.contains(appId)
            }
        )
        
        performanceMonitor.endOperation(.ruleEvaluation)
        performanceMonitor.incrementCounter(.ruleEvaluations)
        
        let beaconRegionStatus = beaconRegistry.beaconStatuses.values.compactMap { status in
            "\(status.device.name):\(status.isInRegion ? "in" : "out")"
        }.joined(separator: ",")
        
        let evaluationId = UUID().uuidString.suffix(8)
        let timeLimitBlockedCount = timeLimitBlockedApps.count
        let firebaseBlockedCount = evaluationResult.blockedAppIds.count
        let totalBlockedCount = timeLimitBlockedCount + firebaseBlockedCount
        
        logger.debug("[\(evaluationId)] Evaluating \(rules.count) rules at location \(location.coordinate) with beacons[\(beaconRegionStatus)]: \(totalBlockedCount) apps blocked (Time Limits: \(timeLimitBlockedCount), Firebase: \(firebaseBlockedCount))")
    }
    
    /// Determines if a specific app should be blocked based on a rule and current context.
    ///
    /// Implements the rule evaluation logic for a single app-rule combination.
    /// All active conditions in the rule must be satisfied for blocking to occur.
    ///
    /// ## Evaluation Order (fail-fast for performance)
    /// 1. Rule active status
    /// 2. App inclusion in rule's blocked apps
    /// 3. GPS location requirements (if enabled)
    /// 4. Time-based requirements
    /// 5. Beacon proximity requirements
    ///
    /// - Parameters:
    ///   - appId: Firebase document ID of the app to evaluate
    ///   - rule: The rule to evaluate against
    ///   - userLocation: Current user location
    ///   - nearBeaconDocumentIds: Firebase IDs of nearby beacon devices
    ///   - currentTime: Current time for time-based rule evaluation
    /// - Returns: True if the app should be blocked according to this rule
    private func shouldBlockApp(
        appId: String,
        rule: Rule,
        userLocation: CLLocation,
        nearBeaconDocumentIds: [String],
        currentTime: Date
    ) -> Bool {
        // 1. Check if rule is active
        guard rule.isActive else { return false }
        
        // 2. Check if app is in this rule's blocked apps
        guard rule.blockedTokenIds.contains(appId) else { return false }
        
        // 3. Check GPS location (only if GPS rule is active)
        if rule.gpsLocation.isActive {
            let gpsLocation = CLLocation(
                latitude: rule.gpsLocation.latitude,
                longitude: rule.gpsLocation.longitude
            )
            let inGPSZone = gpsLocation.distance(from: userLocation) <= rule.gpsLocation.radius
            guard inGPSZone else { return false }
        }
        
        // 4. Check time rules
        let timeBasedBlock = shouldBlockBasedOnTimeRules(rule.timeRules, currentTime: currentTime)
        guard timeBasedBlock else { return false }
        
        // 5. Check fine location rules (BLE beacons)
        for fineRule in rule.fineLocationRules {
            guard fineRule.isActive else { continue }
            
            let nearThisBeacon = nearBeaconDocumentIds.contains(fineRule.beaconId)
            
            switch fineRule.behaviorType {
            case .allowedIn:
                if nearThisBeacon {
                    return false  // Near beacon = allow
                }
            case .blockedIn:
                if nearThisBeacon {
                    return true   // Near beacon = block
                } else {
                    return false // Otherwise = allow
                }
            }
        }
        
        // Default: if all active conditions are met, block the app
        return true
    }
    
    /// Evaluates time-based blocking rules against current time.
    ///
    /// Checks if the current time falls within any active time rule windows.
    /// Supports multiple recurrence patterns: daily, weekly, monthly, and custom intervals.
    ///
    /// ## Logic
    /// - If no time rules exist, blocking is always allowed (time-agnostic)
    /// - If any time rule matches current time, blocking is allowed
    /// - Rules can have expiration dates and custom recurrence patterns
    ///
    /// - Parameters:
    ///   - timeRules: Array of time-based rules to evaluate
    ///   - currentTime: Current time to check against rules
    /// - Returns: True if time-based blocking should be active
    private func shouldBlockBasedOnTimeRules(_ timeRules: [TimeRule], currentTime: Date) -> Bool {
        // If no time rules are defined, time-based blocking is always active
        guard !timeRules.isEmpty else { return true }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute, .weekday, .day], from: currentTime)
        
        for rule in timeRules {
            guard rule.isActive else { continue }
            
            // Check if rule has expired
            if let endDate = rule.endDate, currentTime > endDate {
                continue
            }
            
            // Check if rule has started
            if currentTime < rule.startDate {
                continue
            }
            
            // Check time range
            let ruleStartComponents = calendar.dateComponents([.hour, .minute], from: rule.startTime)
            let ruleEndComponents = calendar.dateComponents([.hour, .minute], from: rule.endTime)
            
            let currentMinutes = (currentComponents.hour ?? 0) * 60 + (currentComponents.minute ?? 0)
            let ruleStartMinutes = (ruleStartComponents.hour ?? 0) * 60 + (ruleStartComponents.minute ?? 0)
            let ruleEndMinutes = (ruleEndComponents.hour ?? 0) * 60 + (ruleEndComponents.minute ?? 0)
            
            let inTimeRange = (ruleStartMinutes <= currentMinutes && currentMinutes <= ruleEndMinutes)
            
            if !inTimeRange {
                continue
            }
            
            // Check recurrence pattern
            switch rule.recurrencePattern {
            case .daily:
                return true
            case .weekly:
                if let daysOfWeek = rule.daysOfWeek,
                   let currentWeekday = currentComponents.weekday,
                   daysOfWeek.contains(currentWeekday) {
                    return true
                }
            case .monthly:
                if let daysOfMonth = rule.daysOfMonth,
                   let currentDay = currentComponents.day,
                   daysOfMonth.contains(currentDay) {
                    return true
                }
            case .custom:
                if let customInterval = rule.customInterval {
                    let daysSinceStart = calendar.dateComponents([.day], from: rule.startDate, to: currentTime).day ?? 0
                    if daysSinceStart % customInterval == 0 {
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    // MARK: - Shared Data Synchronization
    
    /// Syncs active rule tokens to shared storage for DeviceActivityMonitor extension.
    ///
    /// This method extracts all blocked token IDs from active rules and saves them
    /// to the App Group container so the DeviceActivityMonitor extension can apply
    /// broad "safety net" blocking when the main app is unavailable.
    ///
    /// - Parameter rules: Array of currently active rules
    private func syncActiveRuleTokensToSharedStorage(rules: [Rule]) {
        logger.debug("Syncing \(rules.count) active rules to shared storage")
        
        // Extract all token IDs from active rules
        let allTokenIds = rules.flatMap { $0.blockedTokenIds }
        let uniqueTokenIds = Array(Set(allTokenIds))
        
        logger.debug("Found \(uniqueTokenIds.count) unique tokens from active rules")
        
        // Get blocked tokens from rule store using specific IDs
        let blockedTokenInfos = ruleStore.getBlockedTokens(byIds: uniqueTokenIds)
        
        logger.debug("Successfully mapped \(blockedTokenInfos.count)/\(uniqueTokenIds.count) tokens")
        
        // Convert to DAM-compatible format for saving to shared storage
        let damCompatibleTokens = blockedTokenInfos.map { tokenInfo in
            [
                "tokenId": tokenInfo.id ?? "",
                "tokenType": tokenInfo.tokenType,
                "tokenData": tokenInfo.tokenData.base64EncodedString(),
                "bundleIdentifier": tokenInfo.bundleIdentifier ?? "",
                "displayName": tokenInfo.displayName
            ]
        }
        
        let damCompatibleData: [String: Any] = [
            "activeRuleTokens": damCompatibleTokens,
            "lastUpdated": Date().timeIntervalSince1970,
            "schemaVersion": 1
        ]
        
        // Save to shared storage using simple JSON approach
        let success = saveDamCompatibleData(damCompatibleData)
        
        if success {
            logger.debug("Successfully synced active rule tokens to shared storage")
        } else {
            logger.error("Failed to sync active rule tokens to shared storage")
        }
        
        // Log summary for debugging
        let appCount = blockedTokenInfos.filter { $0.tokenType == "application" }.count
        let webCount = blockedTokenInfos.filter { $0.tokenType == "webDomain" }.count
        let categoryCount = blockedTokenInfos.filter { $0.tokenType == "activityCategory" }.count
        
        logger.debug("Synced tokens breakdown - apps: \(appCount), web: \(webCount), categories: \(categoryCount)")
    }
    
    /// Saves DAM-compatible data to shared storage without requiring DAM types in main app.
    ///
    /// This method uses simple JSON serialization to avoid complex type dependencies
    /// between the main app and DAM extension targets.
    ///
    /// - Parameter data: Dictionary containing DAM-compatible data
    /// - Returns: True if successfully saved
    private func saveDamCompatibleData(_ data: [String: Any]) -> Bool {
        let appGroupIdentifier = "group.com.ah.limmi.shareddata"
        let fileName = "activeRuleTokens.json"
        
        // Try to save to App Group container file
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(fileName)
            
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                try jsonData.write(to: fileURL, options: .atomic)
                logger.debug("Saved DAM-compatible data to App Group file")
                return true
            } catch {
                logger.error("Failed to save DAM-compatible data to file: \(error.localizedDescription)")
            }
        }
        
        // Fallback: Save to UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data, options: [])
                sharedDefaults.set(jsonData, forKey: "activeRuleData")
                let success = sharedDefaults.synchronize()
                logger.debug("Saved DAM-compatible data to UserDefaults: \(success)")
                return success
            } catch {
                logger.error("Failed to save DAM-compatible data to UserDefaults: \(error.localizedDescription)")
            }
        }
        
        return false
    }
}

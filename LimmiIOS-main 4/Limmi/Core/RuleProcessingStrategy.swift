//
//  RuleProcessingStrategy.swift
//  Limmi
//
//  Purpose: Pluggable rule processing strategies for sophisticated beacon-based app blocking
//  Dependencies: Foundation, CoreLocation, BeaconRegistry, BeaconStatus
//  Related: BlockingEngine.swift, BeaconRegistry.swift, Rule.swift
//

import Foundation
import CoreLocation

/// Result of rule evaluation containing both rule-level and app-level blocking decisions
struct RuleEvaluationResult {
    /// Map of rule ID to whether that rule is currently active/blocking
    let ruleBlockingStatus: [String: Bool]
    
    /// Set of app IDs that should be blocked based on all active rules
    let blockedAppIds: Set<String>
    
    /// Detailed information about why each rule is or isn't blocking (for debugging)
    let ruleEvaluationDetails: [String: String]
    
    /// Detailed evaluation results for each rule (for UI display)
    let detailedResults: [String: DetailedRuleEvaluationResult]
}

/// Protocol for pluggable rule processing strategies
protocol RuleProcessingStrategy {
    /// Evaluates which app IDs should be blocked given the current context and rules
    /// - Parameters:
    ///   - rules: Active rules to evaluate
    ///   - location: Current user location
    ///   - beaconRegistry: Registry containing comprehensive beacon status information
    ///   - currentTime: Current time for time-based rules
    /// - Returns: RuleEvaluationResult with both rule-level and app-level blocking decisions
    @MainActor
    mutating func evaluateBlockingRules(
        rules: [Rule],
        location: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> RuleEvaluationResult
}

/// Default rule processing strategy with enhanced beacon tracking support
///
/// This implementation provides sophisticated rule evaluation using the comprehensive
/// beacon status information from BeaconRegistry. It supports:
/// - Signal quality-based decisions
/// - Beacon stability requirements
/// - Presence pattern analysis
/// - Multiple proximity criteria
struct DefaultRuleProcessingStrategy: RuleProcessingStrategy {
    
    /// Configuration for enhanced beacon-based rule processing
    struct BeaconProcessingConfig {
        /// Minimum duration a beacon must be stable before triggering rules
        let minimumStabilityDuration: TimeInterval
        
        /// Minimum signal quality required for reliable beacon-based decisions
        let minimumSignalQuality: SignalQuality
        
        /// Use strict near-range criteria instead of general in-range
        let useStrictProximity: Bool
        
        /// Minimum presence ratio (0.0-1.0) in recent time window for reliable detection
        let minimumPresenceRatio: Double
        
        /// Time window for presence ratio analysis (seconds)
        let presenceAnalysisWindow: TimeInterval
        
        /// Hysteresis configuration to prevent rapid blocking/unblocking transitions
        let hysteresisConfig: HysteresisConfig
        
        /// Configuration for blocking state transition hysteresis
        /// 
        /// BEHAVIOR: In range = UNBLOCKED, Out of range = BLOCKED
        struct HysteresisConfig {
            /// Stricter proximity criteria to STAY unblocked (in range) - prevents going out of range too easily
            let blockingProximityThreshold: ProximityThreshold
            
            /// Looser proximity criteria to GET unblocked (in range) - makes it easier to get back in range
            let unblockingProximityThreshold: ProximityThreshold
            
            /// Minimum duration in new proximity state before allowing state transition
            let transitionStabilityDuration: TimeInterval
            
            static let `default` = HysteresisConfig(
                blockingProximityThreshold: .immediate,      // Must be near or immediate to stay unblocked
                unblockingProximityThreshold: .far,     // Only need far to get back to unblocked
                transitionStabilityDuration: 2.0        // 2 seconds in new state
            )
            
            static let conservative = HysteresisConfig(
                blockingProximityThreshold: .immediate, // Must be immediate to stay unblocked
                unblockingProximityThreshold: .near,    // Need near to get back to unblocked
                transitionStabilityDuration: 3.0        // 3 seconds in new state
            )
            
            static let responsive = HysteresisConfig(
                blockingProximityThreshold: .far,       // Even far proximity keeps you unblocked
                unblockingProximityThreshold: .far,     // Far proximity gets you back to unblocked
                transitionStabilityDuration: 1.0        // 1 second in new state
            )
        }
        
        /// Proximity threshold levels for hysteresis
        enum ProximityThreshold {
            case immediate  // Only immediate proximity (-50 to 0 dBm)
            case near       // Near or immediate proximity (-88 to 0 dBm)
            case far        // Far, near, or immediate proximity (-99 to 0 dBm)
            case unknown    // Any proximity including unknown/lost signal
            
            /// Checks if the given proximity meets this threshold
            func isMet(by proximity: BeaconProximity) -> Bool {
                switch self {
                case .immediate:
                    return proximity == .immediate
                case .near:
                    return proximity == .immediate || proximity == .near
                case .far:
                    return proximity == .immediate || proximity == .near || proximity == .far
                case .unknown:
                    return true // Any proximity including unknown
                }
            }
        }
        
        /// Default configuration for balanced accuracy and responsiveness
        static let `default` = BeaconProcessingConfig(
            minimumStabilityDuration: 0.0,      // No stability requirement
            minimumSignalQuality: .poor,        // Accept any signal
            useStrictProximity: true,           // Use strict proximity
            minimumPresenceRatio: 0.5,          // 50% presence
            presenceAnalysisWindow: 5.0,        // 4 second analysis
            hysteresisConfig: .default          // Default hysteresis
        )
        
        /// Conservative configuration for high accuracy
        static let conservative = BeaconProcessingConfig(
            minimumStabilityDuration: 0.0,      // No stability requirement
            minimumSignalQuality: .poor,        // Accept any signal
            useStrictProximity: true,           // Use strict proximity
            minimumPresenceRatio: 0.5,          // 50% presence
            presenceAnalysisWindow: 5.0,        // 4 second analysis
            hysteresisConfig: .conservative     // Conservative hysteresis
        )
        
        /// Responsive configuration for quick reactions
        static let responsive = BeaconProcessingConfig(
            minimumStabilityDuration: 0.0,      // No stability requirement
            minimumSignalQuality: .poor,        // Accept any signal
            useStrictProximity: true,           // Use strict proximity
            minimumPresenceRatio: 0.5,          // 50% presence
            presenceAnalysisWindow: 5.0,        // 4 second analysis
            hysteresisConfig: .responsive       // Responsive hysteresis
        )
    }
    
    private let config: BeaconProcessingConfig
    
    /// Tracks blocking state for hysteresis implementation
    private var blockingStateTracker: [String: BlockingStateInfo] = [:]
    
    /// Information about current blocking state for hysteresis
    private struct BlockingStateInfo {
        let isCurrentlyBlocked: Bool
        let lastStateChangeTime: Date
        let lastProximityState: BeaconProximity?
        let proximityStateChangeTime: Date?
        
        init(isBlocked: Bool) {
            self.isCurrentlyBlocked = isBlocked
            self.lastStateChangeTime = Date()
            self.lastProximityState = nil
            self.proximityStateChangeTime = nil
        }
        
        init(isCurrentlyBlocked: Bool, lastStateChangeTime: Date, lastProximityState: BeaconProximity?, proximityStateChangeTime: Date?) {
            self.isCurrentlyBlocked = isCurrentlyBlocked
            self.lastStateChangeTime = lastStateChangeTime
            self.lastProximityState = lastProximityState
            self.proximityStateChangeTime = proximityStateChangeTime
        }
        
        func updatingProximity(_ proximity: BeaconProximity) -> BlockingStateInfo {
            let now = Date()
            let proximityChanged = lastProximityState != proximity
            return BlockingStateInfo(
                isCurrentlyBlocked: isCurrentlyBlocked,
                lastStateChangeTime: lastStateChangeTime,
                lastProximityState: proximity,
                proximityStateChangeTime: proximityChanged ? now : proximityStateChangeTime
            )
        }
        
        func updatingBlockingState(_ isBlocked: Bool) -> BlockingStateInfo {
            return BlockingStateInfo(
                isCurrentlyBlocked: isBlocked,
                lastStateChangeTime: Date(),
                lastProximityState: lastProximityState,
                proximityStateChangeTime: proximityStateChangeTime
            )
        }
        
        /// Checks if proximity state has been stable for the required duration
        func hasStableProximity(for duration: TimeInterval) -> Bool {
            guard let stateChangeTime = proximityStateChangeTime else { return false }
            return Date().timeIntervalSince(stateChangeTime) >= duration
        }
    }
    
    init(config: BeaconProcessingConfig = .responsive) {
        self.config = config
    }
    
    @MainActor
    mutating func evaluateBlockingRules(
        rules: [Rule],
        location: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> RuleEvaluationResult {
        guard let location = location else { 
            return RuleEvaluationResult(
                ruleBlockingStatus: [:],
                blockedAppIds: [],
                ruleEvaluationDetails: [:],
                detailedResults: [:]
            )
        }
        
        var ruleBlockingStatus: [String: Bool] = [:]
        var ruleEvaluationDetails: [String: String] = [:]
        var detailedResults: [String: DetailedRuleEvaluationResult] = [:]
        var blockedAppIds: Set<String> = []
        
        // Evaluate each rule individually to determine its blocking status
        for rule in rules {
            guard let ruleId = rule.id else { continue }
            
            // Generate detailed evaluation for this rule
            let detailedResult = evaluateRuleInDetail(
                rule: rule,
                userLocation: location,
                beaconRegistry: beaconRegistry,
                currentTime: currentTime
            )
            
            let ruleIsBlocking = detailedResult.overallShouldBlock
            
            ruleBlockingStatus[ruleId] = ruleIsBlocking
            ruleEvaluationDetails[ruleId] = "Rule evaluated with beacon registry"
            detailedResults[ruleId] = detailedResult
            
            // If rule is blocking, add its apps to the blocked set
            if ruleIsBlocking {
                blockedAppIds.formUnion(rule.blockedTokenIds)
            }
        }
        
        return RuleEvaluationResult(
            ruleBlockingStatus: ruleBlockingStatus,
            blockedAppIds: blockedAppIds,
            ruleEvaluationDetails: ruleEvaluationDetails,
            detailedResults: detailedResults
        )
    }

    /// Determines if a rule should be blocking based on current conditions
    @MainActor
    private func shouldRuleBlock(
        rule: Rule,
        userLocation: CLLocation,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> Bool {
        guard rule.isActive else { return false }
        guard !rule.blockedTokenIds.isEmpty else { return false }
        
        return shouldBlockApp(
            appId: rule.blockedTokenIds.first!, // Any app from the rule for evaluation
            rule: rule,
            userLocation: userLocation,
            beaconRegistry: beaconRegistry,
            currentTime: currentTime
        )
    }
    
    /// Generates detailed evaluation results for a rule, capturing the status of each condition
    @MainActor
    private mutating func evaluateRuleInDetail(
        rule: Rule,
        userLocation: CLLocation,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> DetailedRuleEvaluationResult {
        guard let ruleId = rule.id else {
            return DetailedRuleEvaluationResult(
                ruleId: "unknown",
                ruleName: rule.name,
                isRuleActive: false,
                overallShouldBlock: false,
                gpsResult: nil,
                timeResults: [],
                beaconResults: []
            )
        }
        
        // Check if rule is active and has blocked apps
        let hasBlockedApps = !rule.blockedTokenIds.isEmpty
        let shouldContinueEvaluation = rule.isActive && hasBlockedApps
        
        // Evaluate GPS condition
        let gpsResult: GPSEvaluationResult?
        if rule.gpsLocation.isActive {
            let gpsLocation = CLLocation(
                latitude: rule.gpsLocation.latitude,
                longitude: rule.gpsLocation.longitude
            )
            let distance = gpsLocation.distance(from: userLocation)
            let isUserInside = distance <= rule.gpsLocation.radius
            
            gpsResult = GPSEvaluationResult(
                isActive: true,
                isUserInside: isUserInside,
                userDistance: distance
            )
        } else {
            gpsResult = GPSEvaluationResult(
                isActive: false,
                isUserInside: false,
                userDistance: nil
            )
        }
        
        // Evaluate time conditions
        let timeResults = rule.timeRules.map { timeRule in
            let isTimeInRange = isCurrentTimeInTimeRule(timeRule, currentTime: currentTime)
            return TimeEvaluationResult(
                timeRuleId: timeRule.id ?? "unknown",
                timeRuleName: timeRule.name,
                isActive: timeRule.isActive,
                isCurrentTimeInRange: isTimeInRange
            )
        }
        
        // Evaluate beacon conditions
        var beaconResults: [BeaconEvaluationResult] = []
        for fineRule in rule.fineLocationRules {
            let beaconResult: BeaconEvaluationResult
            if let beaconDevice = findBeaconDevice(for: fineRule.beaconId, beaconRegistry: beaconRegistry) {
                let beaconID = BeaconID(from: beaconDevice)
                let isReliable = isBeaconReliableForRule(beaconID: beaconID, beaconRegistry: beaconRegistry)
                
                // Get beacon status for detailed info
                let beaconStatus = beaconRegistry.status(for: beaconID)
                
                beaconResult = BeaconEvaluationResult(
                    fineLocationRuleId: fineRule.id ?? "unknown",
                    beaconId: fineRule.beaconId,
                    beaconName: beaconDevice.name,
                    behaviorType: fineRule.behaviorType,
                    isActive: fineRule.isActive,
                    isUserNearBeacon: isReliable,
                    rssiValue: beaconStatus?.currentRSSI.map(Double.init),
                    distance: nil // BeaconStatus doesn't provide distance estimation
                )
            } else {
                beaconResult = BeaconEvaluationResult(
                    fineLocationRuleId: fineRule.id ?? "unknown",
                    beaconId: fineRule.beaconId,
                    beaconName: fineRule.name,
                    behaviorType: fineRule.behaviorType,
                    isActive: fineRule.isActive,
                    isUserNearBeacon: false,
                    rssiValue: nil,
                    distance: nil
                )
            }
            
            beaconResults.append(beaconResult)
        }
        
        // Determine overall blocking status
        let overallShouldBlock: Bool
        if shouldContinueEvaluation {
            // GPS condition must pass if active
            let gpsConditionMet = gpsResult?.isActive != true || gpsResult?.isUserInside == true
            
            // At least one time rule must pass if any are active
            let timeConditionMet = timeResults.isEmpty || 
                                   timeResults.contains { $0.isActive && $0.isCurrentTimeInRange }
            
            // Beacon logic is complex - use existing logic
            let beaconConditionMet = evaluateBeaconConditionsForBlocking(
                rule: rule,
                beaconRegistry: beaconRegistry
            )
            
            overallShouldBlock = gpsConditionMet && timeConditionMet && beaconConditionMet
        } else {
            overallShouldBlock = false
        }
        
        return DetailedRuleEvaluationResult(
            ruleId: ruleId,
            ruleName: rule.name,
            isRuleActive: rule.isActive,
            overallShouldBlock: overallShouldBlock,
            gpsResult: gpsResult,
            timeResults: timeResults,
            beaconResults: beaconResults
        )
    }
    
    /// Evaluates a single time rule against the current time
    @MainActor
    private func isCurrentTimeInTimeRule(_ timeRule: TimeRule, currentTime: Date) -> Bool {
        guard timeRule.isActive else { return false }
        
        // Check if rule has expired
        if let endDate = timeRule.endDate, currentTime > endDate {
            return false
        }
        
        // Check if rule has started
        if currentTime < timeRule.startDate {
            return false
        }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: currentTime)
        let ruleStartComponents = calendar.dateComponents([.hour, .minute], from: timeRule.startTime)
        let ruleEndComponents = calendar.dateComponents([.hour, .minute], from: timeRule.endTime)
        
        let currentMinutes = (currentComponents.hour ?? 0) * 60 + (currentComponents.minute ?? 0)
        let ruleStartMinutes = (ruleStartComponents.hour ?? 0) * 60 + (ruleStartComponents.minute ?? 0)
        let ruleEndMinutes = (ruleEndComponents.hour ?? 0) * 60 + (ruleEndComponents.minute ?? 0)
        
        return ruleStartMinutes <= currentMinutes && currentMinutes <= ruleEndMinutes
    }
    
    /// Evaluates beacon conditions for blocking (simplified version for detailed evaluation)
    @MainActor
    private mutating func evaluateBeaconConditionsForBlocking(
        rule: Rule,
        beaconRegistry: BeaconRegistry
    ) -> Bool {
        guard let ruleId = rule.id else { return false }
        
        // If no beacon rules, beacon condition is met
        let activeBeaconRules = rule.fineLocationRules.filter { $0.isActive }
        guard !activeBeaconRules.isEmpty else { return true }
        
        // Get or initialize current state tracking for this rule
        let currentState = blockingStateTracker[ruleId]
        let currentlyBlocked = currentState?.isCurrentlyBlocked ?? false
        
        // Evaluate beacon conditions with hysteresis logic
        for fineRule in activeBeaconRules {
            guard let beaconDevice = findBeaconDevice(for: fineRule.beaconId, beaconRegistry: beaconRegistry) else {
                continue
            }
            
            let beaconID = BeaconID(from: beaconDevice)
            let beaconStatus = beaconRegistry.status(for: beaconID)
            let currentProximity = beaconStatus?.proximity ?? .unknown
            
            // Update proximity tracking for hysteresis
            if let currentState = currentState {
                blockingStateTracker[ruleId] = currentState.updatingProximity(currentProximity)
            } else {
                blockingStateTracker[ruleId] = BlockingStateInfo(isBlocked: false).updatingProximity(currentProximity)
            }
            
            // Apply hysteresis logic based on current blocking state and behavior type
            let shouldBlockBasedOnProximity = evaluateBeaconWithHysteresis(
                fineRule: fineRule,
                beaconID: beaconID,
                beaconRegistry: beaconRegistry,
                currentProximity: currentProximity,
                currentlyBlocked: currentlyBlocked,
                ruleId: ruleId
            )
            
            switch fineRule.behaviorType {
            case .allowedIn:
                // allowedIn: In range = UNBLOCKED, Out of range = BLOCKED
                // shouldBlockBasedOnProximity = true means out of range, so we BLOCK
                if shouldBlockBasedOnProximity {
                    return true  // Out of range = block apps
                } else {
                    return false // In range = allow apps (don't block)
                }
            case .blockedIn:
                // blockedIn: In range = BLOCKED, Out of range = UNBLOCKED  
                // shouldBlockBasedOnProximity = true means out of range, so we UNBLOCK
                if shouldBlockBasedOnProximity {
                    return false // Out of range = allow apps (don't block)
                } else {
                    return true  // In range = block apps
                }
            }
        }
        
        // Default: if all active conditions are met, block the app
        return true
    }
    
    /// Evaluates beacon condition with hysteresis to prevent rapid state changes
    /// 
    /// Returns true if the rule should block apps, false if apps should be allowed.
    /// This method tracks proximity state internally to prevent rapid transitions.
    @MainActor
    private mutating func evaluateBeaconWithHysteresis(
        fineRule: FineLocationRule,
        beaconID: BeaconID,
        beaconRegistry: BeaconRegistry,
        currentProximity: BeaconProximity,
        currentlyBlocked: Bool,
        ruleId: String
    ) -> Bool {
        let hysteresisConfig = config.hysteresisConfig
        let currentState = blockingStateTracker[ruleId]
        
        // Check if proximity has been stable for the required duration
        let hasStableProximity = currentState?.hasStableProximity(for: hysteresisConfig.transitionStabilityDuration) ?? false
        
        // If proximity hasn't been stable long enough, maintain current state
        guard hasStableProximity else {
            return currentlyBlocked
        }
        
        // Check if beacon is reliable for basic evaluation
        let isBeaconReliable = isBeaconReliableForRule(beaconID: beaconID, beaconRegistry: beaconRegistry)
        
        // Apply different thresholds based on current internal blocking state (hysteresis)
        if currentlyBlocked {
            // Apps are currently being blocked - check if we should allow them
            // Use unblocking threshold (more permissive to stop blocking)
            let meetsUnblockingThreshold = hysteresisConfig.unblockingProximityThreshold.isMet(by: currentProximity)
            
            if meetsUnblockingThreshold && isBeaconReliable {
                // Close enough and reliable - stop blocking apps
                blockingStateTracker[ruleId] = currentState?.updatingBlockingState(false)
                return false // Don't block (allow apps)
            } else {
                // Still too far or unreliable - keep blocking apps
                return true // Block (restrict apps)
            }
        } else {
            // Apps are currently allowed - check if we should block them
            // Use blocking threshold (more restrictive to start blocking)
            let meetsBlockingThreshold = hysteresisConfig.blockingProximityThreshold.isMet(by: currentProximity)
            
            if !meetsBlockingThreshold || !isBeaconReliable {
                // Too far or unreliable - start blocking apps
                blockingStateTracker[ruleId] = currentState?.updatingBlockingState(true)
                return true // Block (restrict apps)
            } else {
                // Still close enough and reliable - keep allowing apps
                return false // Don't block (allow apps)
            }
        }
    }
    
    /// Enhanced rule evaluation with sophisticated beacon status analysis
    @MainActor
    private func shouldBlockApp(
        appId: String,
        rule: Rule,
        userLocation: CLLocation,
        beaconRegistry: BeaconRegistry,
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
        // 5. Check fine location rules (BLE beacons) with enhanced beacon analysis
        for fineRule in rule.fineLocationRules {
            guard fineRule.isActive else { continue }
            
            // Find the beacon device for this rule
            guard let beaconDevice = findBeaconDevice(for: fineRule.beaconId, beaconRegistry: beaconRegistry) else {
                continue // Skip if beacon device not found
            }
            
            let beaconID = BeaconID(from: beaconDevice)
            let isBeaconReliable = isBeaconReliableForRule(beaconID: beaconID, beaconRegistry: beaconRegistry)
            
            switch fineRule.behaviorType {
            case .allowedIn:
                if isBeaconReliable {
                    return false  // Near reliable beacon = allow
                }
            case .blockedIn:
                if isBeaconReliable {
                    return true   // Near reliable beacon = block
                } else {
                    return false // Not reliably near = allow
                }
            }
        }
        // Default: if all active conditions are met, block the app
        return true
    }
    
    /// Finds the beacon device for a given beacon rule ID
    @MainActor
    private func findBeaconDevice(for beaconRuleId: String, beaconRegistry: BeaconRegistry) -> BeaconDevice? {
        // The beaconRuleId corresponds to a Firebase document ID
        // We need to find the beacon device that matches this ID
        for (_, status) in beaconRegistry.beaconStatuses {
            if status.device.id == beaconRuleId {
                return status.device
            }
        }
        return nil
    }
    
    /// Determines if a beacon is reliable enough for rule evaluation based on configuration
    @MainActor
    private func isBeaconReliableForRule(beaconID: BeaconID, beaconRegistry: BeaconRegistry) -> Bool {
        guard let beaconStatus = beaconRegistry.status(for: beaconID) else {
            return false // No status = not reliable
        }
        
        // Check basic range status (strict vs general proximity)
        let inRequiredRange = config.useStrictProximity ? 
            beaconStatus.isNearRange : beaconStatus.isInRange
        guard inRequiredRange else {
            return false // Not in required proximity range
        }
        
        // Check signal quality requirement
        if beaconStatus.signalQuality < config.minimumSignalQuality {
            return false // Signal quality too low
        }
        
        // Check stability requirement
        if !beaconStatus.hasBeenStableInRange(for: config.minimumStabilityDuration) {
            return false // Not stable long enough
        }
        
        // Check presence ratio in recent time window
        let presenceRatio = beaconStatus.presenceRatio(in: config.presenceAnalysisWindow)
        if presenceRatio < config.minimumPresenceRatio {
            return false // Not consistently present
        }
        
        return true // All reliability criteria met
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
}

/// Region-based rule processing strategy focusing exclusively on regionEntered/regionExited events
///
/// This implementation ignores RSSI signal strength and proximity calculations, relying
/// solely on CoreLocation's region monitoring events for rule evaluation. This provides:
/// - Background operation compatibility
/// - Battery efficiency
/// - Binary in/out zone detection
/// - Reliable cross-platform behavior
///
/// Best suited for scenarios where:
/// - Background operation is critical
/// - Binary zone presence is sufficient
/// - Battery life is prioritized over granular proximity
/// - RSSI signal quality is unreliable
struct RegionBasedRuleProcessingStrategy: RuleProcessingStrategy {
    
    /// Configuration for region-based rule processing
    struct RegionProcessingConfig {
        /// Minimum duration a beacon region must be stable before triggering rules
        let minimumRegionStabilityDuration: TimeInterval
        
        /// Require both entry and exit events to be processed for reliable state
        let requireEntryExitHistory: Bool
        
        /// Minimum time between region entry/exit to avoid rapid toggling
        let minimumRegionTransitionInterval: TimeInterval
        
        /// Default configuration for reliable region-based processing
        static let `default` = RegionProcessingConfig(
            minimumRegionStabilityDuration: 5.0,    // 5 seconds stable in region
            requireEntryExitHistory: true,          // Need both entry and exit events
            minimumRegionTransitionInterval: 2.0    // 2 seconds between transitions
        )
        
        /// Strict configuration for high accuracy requirements
        static let strict = RegionProcessingConfig(
            minimumRegionStabilityDuration: 15.0,   // 15 seconds stable
            requireEntryExitHistory: true,          // Require full history
            minimumRegionTransitionInterval: 5.0    // 5 seconds between transitions
        )
        
        /// Responsive configuration for quick reactions
        static let responsive = RegionProcessingConfig(
            minimumRegionStabilityDuration: 0.0,    // 1 second stable
            requireEntryExitHistory: false,         // Accept immediate entry
            minimumRegionTransitionInterval: 0.5    // 0.5 seconds between transitions
        )
    }
    
    private let config: RegionProcessingConfig
    
    init(config: RegionProcessingConfig = .responsive) {
        self.config = config
    }
    
    @MainActor
    mutating func evaluateBlockingRules(
        rules: [Rule],
        location: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> RuleEvaluationResult {
        var ruleBlockingStatus: [String: Bool] = [:]
        var ruleEvaluationDetails: [String: String] = [:]
        var detailedResults: [String: DetailedRuleEvaluationResult] = [:]
        var blockedAppIds: Set<String> = []
        
        // Evaluate each rule individually to determine its blocking status
        for rule in rules {
            guard let ruleId = rule.id else { continue }
            
            // Generate detailed evaluation for this rule using region-based logic
            let detailedResult = evaluateRuleInDetailRegionBased(
                rule: rule,
                userLocation: location,
                beaconRegistry: beaconRegistry,
                currentTime: currentTime
            )
            
            let ruleIsBlocking = detailedResult.overallShouldBlock
            
            ruleBlockingStatus[ruleId] = ruleIsBlocking
            ruleEvaluationDetails[ruleId] = "Rule evaluated with region-based strategy"
            detailedResults[ruleId] = detailedResult
            
            // If rule is blocking, add its apps to the blocked set
            if ruleIsBlocking {
                blockedAppIds.formUnion(rule.blockedTokenIds)
            }
        }
        
        return RuleEvaluationResult(
            ruleBlockingStatus: ruleBlockingStatus,
            blockedAppIds: blockedAppIds,
            ruleEvaluationDetails: ruleEvaluationDetails,
            detailedResults: detailedResults
        )
    }
    
    /// Generates detailed evaluation results for a rule using region-based strategy
    @MainActor
    private func evaluateRuleInDetailRegionBased(
        rule: Rule,
        userLocation: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> DetailedRuleEvaluationResult {
        guard let ruleId = rule.id else {
            return DetailedRuleEvaluationResult(
                ruleId: "unknown",
                ruleName: rule.name,
                isRuleActive: false,
                overallShouldBlock: false,
                gpsResult: nil,
                timeResults: [],
                beaconResults: []
            )
        }
        
        // Check if rule is active and has blocked apps
        let hasBlockedApps = !rule.blockedTokenIds.isEmpty
        let shouldContinueEvaluation = rule.isActive && hasBlockedApps
        
        // Evaluate GPS condition
        let gpsResult: GPSEvaluationResult?
        if rule.gpsLocation.isActive {
            if let location = userLocation {
                let gpsLocation = CLLocation(
                    latitude: rule.gpsLocation.latitude,
                    longitude: rule.gpsLocation.longitude
                )
                let distance = gpsLocation.distance(from: userLocation!)
                let isUserInside = distance <= rule.gpsLocation.radius
                
                gpsResult = GPSEvaluationResult(
                    isActive: true,
                    isUserInside: isUserInside,
                    userDistance: distance
                )
            } else {
                gpsResult = GPSEvaluationResult(
                    isActive: true,
                    isUserInside: false,
                    userDistance: nil
                )
            }
        } else {
            gpsResult = GPSEvaluationResult(
                isActive: false,
                isUserInside: false,
                userDistance: nil
            )
        }
        
        // Evaluate time conditions (same logic as DefaultRuleProcessingStrategy)
        let timeResults = rule.timeRules.map { timeRule in
            let isTimeInRange = isCurrentTimeInTimeRuleRegionBased(timeRule, currentTime: currentTime)
            return TimeEvaluationResult(
                timeRuleId: timeRule.id ?? "unknown",
                timeRuleName: timeRule.name,
                isActive: timeRule.isActive,
                isCurrentTimeInRange: isTimeInRange
            )
        }
        
        // Evaluate beacon conditions using region-based logic
        var beaconResults: [BeaconEvaluationResult] = []
        for fineRule in rule.fineLocationRules {
            let beaconResult: BeaconEvaluationResult
            
            if let beaconDevice = findBeaconDeviceRegionBased(for: fineRule.beaconId, beaconRegistry: beaconRegistry) {
                let beaconID = BeaconID(from: beaconDevice)
                let isInRegion = beaconRegistry.beaconStatuses[beaconID]?.isInRegion ?? false
                let beaconStatus = beaconRegistry.status(for: beaconID)
                
                beaconResult = BeaconEvaluationResult(
                    fineLocationRuleId: fineRule.id ?? "unknown",
                    beaconId: fineRule.beaconId,
                    beaconName: beaconDevice.name,
                    behaviorType: fineRule.behaviorType,
                    isActive: fineRule.isActive,
                    isUserNearBeacon: isInRegion,
                    rssiValue: beaconStatus?.currentRSSI.map(Double.init),
                    distance: nil // Region-based strategy doesn't use distance estimation
                )
            } else {
                beaconResult = BeaconEvaluationResult(
                    fineLocationRuleId: fineRule.id ?? "unknown",
                    beaconId: fineRule.beaconId,
                    beaconName: fineRule.name,
                    behaviorType: fineRule.behaviorType,
                    isActive: fineRule.isActive,
                    isUserNearBeacon: false,
                    rssiValue: nil,
                    distance: nil
                )
            }
            
            beaconResults.append(beaconResult)
        }
        
        // Determine overall blocking status using region-based logic
        let overallShouldBlock: Bool
        if shouldContinueEvaluation {
            // GPS condition must pass if active
            let gpsConditionMet = gpsResult?.isActive != true || gpsResult?.isUserInside == true
            
            // At least one time rule must pass if any are active
            let timeConditionMet = timeResults.isEmpty || 
                                   timeResults.contains { $0.isActive && $0.isCurrentTimeInRange }
            
            // Beacon logic - region-based approach
            let beaconConditionMet = evaluateBeaconConditionsForBlockingRegionBased(
                rule: rule,
                beaconRegistry: beaconRegistry
            )
            
            overallShouldBlock = gpsConditionMet && timeConditionMet && beaconConditionMet
        } else {
            overallShouldBlock = false
        }
        
        return DetailedRuleEvaluationResult(
            ruleId: ruleId,
            ruleName: rule.name,
            isRuleActive: rule.isActive,
            overallShouldBlock: overallShouldBlock,
            gpsResult: gpsResult,
            timeResults: timeResults,
            beaconResults: beaconResults
        )
    }
    
    /// Helper method: Check if current time is in range for a time rule (region-based version)
    @MainActor
    private func isCurrentTimeInTimeRuleRegionBased(_ timeRule: TimeRule, currentTime: Date) -> Bool {
        guard timeRule.isActive else { return false }
        
        // Check if rule has expired
        if let endDate = timeRule.endDate, currentTime > endDate {
            return false
        }
        
        // Check if rule has started
        if currentTime < timeRule.startDate {
            return false
        }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: currentTime)
        let ruleStartComponents = calendar.dateComponents([.hour, .minute], from: timeRule.startTime)
        let ruleEndComponents = calendar.dateComponents([.hour, .minute], from: timeRule.endTime)
        
        let currentMinutes = (currentComponents.hour ?? 0) * 60 + (currentComponents.minute ?? 0)
        let ruleStartMinutes = (ruleStartComponents.hour ?? 0) * 60 + (ruleStartComponents.minute ?? 0)
        let ruleEndMinutes = (ruleEndComponents.hour ?? 0) * 60 + (ruleEndComponents.minute ?? 0)
        
        return ruleStartMinutes <= currentMinutes && currentMinutes <= ruleEndMinutes
    }
    
    /// Helper method: Find beacon device for region-based strategy (reuses main findBeaconDevice)
    @MainActor
    private func findBeaconDeviceRegionBased(for beaconRuleId: String, beaconRegistry: BeaconRegistry) -> BeaconDevice? {
        return findBeaconDevice(for: beaconRuleId, beaconRegistry: beaconRegistry)
    }
    
    /// Helper method: Evaluate beacon conditions for blocking using region-based logic
    @MainActor
    private func evaluateBeaconConditionsForBlockingRegionBased(
        rule: Rule,
        beaconRegistry: BeaconRegistry
    ) -> Bool {
        // If no beacon rules, beacon condition is met
        let activeBeaconRules = rule.fineLocationRules.filter { $0.isActive }
        guard !activeBeaconRules.isEmpty else { return true }
        
        // Use region-based logic instead of RSSI reliability
        for fineRule in activeBeaconRules {
            guard let beaconDevice = findBeaconDevice(for: fineRule.beaconId, beaconRegistry: beaconRegistry) else {
                continue
            }
            
            let beaconID = BeaconID(from: beaconDevice)
            let isInRegion = beaconRegistry.beaconStatuses[beaconID]?.isInRegion ?? false
            
            switch fineRule.behaviorType {
            case .allowedIn:
                if isInRegion {
                    return false  // In region = allow (don't block)
                }
            case .blockedIn:
                if isInRegion {
                    return true   // In region = block
                } else {
                    return false // Not in region = allow (don't block)
                }
            }
        }
        
        // Default: if all active conditions are met, block the app
        return true
    }
    
    /// Determines if a rule should be blocking based on region-based conditions
    @MainActor
    private func shouldRuleBlockRegionBased(
        rule: Rule,
        userLocation: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> Bool {
        guard rule.isActive else { return false }
        guard !rule.blockedTokenIds.isEmpty else { return false }
        
        return shouldBlockAppRegionBased(
            appId: rule.blockedTokenIds.first!, // Any app from the rule for evaluation
            rule: rule,
            userLocation: userLocation,
            beaconRegistry: beaconRegistry,
            currentTime: currentTime
        )
    }
    
    // VP - Dep
    /// Region-based rule evaluation focusing on region entry/exit events only
    @MainActor
    private func shouldBlockAppRegionBased(
        appId: String,
        rule: Rule,
        userLocation: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> Bool {
        // 1. Check if rule is active
        guard rule.isActive else { return false }
        
        // 2. Check if app is in this rule's blocked apps
        guard rule.blockedTokenIds.contains(appId) else { return false }
        
        // 3. Check GPS location (only if GPS rule is active)
        if rule.gpsLocation.isActive {
            guard let location = userLocation else { return false }
            let gpsLocation = CLLocation(
                latitude: rule.gpsLocation.latitude,
                longitude: rule.gpsLocation.longitude
            )
            let inGPSZone = gpsLocation.distance(from: location) <= rule.gpsLocation.radius
            guard inGPSZone else { return false }
        }
        
        // 4. Check time rules
        let timeBasedBlock = shouldBlockBasedOnTimeRules(rule.timeRules, currentTime: currentTime)
        guard timeBasedBlock else { return false }
        
        // 5. Check fine location rules using ONLY region monitoring state
        for fineRule in rule.fineLocationRules {
            guard fineRule.isActive else { continue }
            
            // Find the beacon device for this rule
            guard let beaconDevice = findBeaconDevice(for: fineRule.beaconId, beaconRegistry: beaconRegistry) else {
                continue // Skip if beacon device not found
            }
            
            let beaconID = BeaconID(from: beaconDevice)
            let isInRegionReliably = isBeaconRegionReliable(beaconID: beaconID, beaconRegistry: beaconRegistry)
            
            switch fineRule.behaviorType {
            case .allowedIn:
                if isInRegionReliably {
                    return false  // In region = allow app usage
                }
            case .blockedIn:
                if isInRegionReliably {
                    return true   // In region = block app usage
                } else {
                    return false // Not in region = allow app usage
                }
            }
        }
        
        // Default: if all active conditions are met, block the app
        return true
    }
    
    
    @MainActor
    private func shouldRuleBlock(
        rule: Rule,
        userLocation: CLLocation?,
        beaconRegistry: BeaconRegistry,
        currentTime: Date
    ) -> Bool {
        // 1. Check if rule is active
        guard rule.isActive else { return false }
        
        // Do I have to only evaluate rules with tokens?
        //guard !rule.blockedTokenIds.isEmpty else { return false }
        
        // 3. Check GPS location (only if GPS rule is active)
        if rule.gpsLocation.isActive {
            guard let location = userLocation else { return false }
            let gpsLocation = CLLocation(
                latitude: rule.gpsLocation.latitude,
                longitude: rule.gpsLocation.longitude
            )
            let inGPSZone = gpsLocation.distance(from: location) <= rule.gpsLocation.radius
            guard inGPSZone else { return false }
        }
        
        // 4. Check time rules
        let timeBasedBlock = shouldBlockBasedOnTimeRules(rule.timeRules, currentTime: currentTime)
        guard timeBasedBlock else { return false }
        
        // 5. Check fine location rules using ONLY region monitoring state
        for fineRule in rule.fineLocationRules {
            guard fineRule.isActive else { continue }
            
            // Find the beacon device for this rule
            guard let beaconDevice = findBeaconDevice(for: fineRule.beaconId, beaconRegistry: beaconRegistry) else {
                continue // Skip if beacon device not found
            }
            
            let beaconID = BeaconID(from: beaconDevice)
            let isInRegionReliably = isBeaconRegionReliable(beaconID: beaconID, beaconRegistry: beaconRegistry)
            
            switch fineRule.behaviorType {
            case .allowedIn:
                if isInRegionReliably {
                    return false  // In region = allow app usage
                }
            case .blockedIn:
                if isInRegionReliably {
                    return true   // In region = block app usage
                } else {
                    return false // Not in region = allow app usage
                }
            }
        }
        
        // Default: if all active conditions are met, block the app
        return true
    }
    
    /// Finds the beacon device for a given beacon rule ID
    @MainActor
    private func findBeaconDevice(for beaconRuleId: String, beaconRegistry: BeaconRegistry) -> BeaconDevice? {
        // The beaconRuleId corresponds to a Firebase document ID
        // We need to find the beacon device that matches this ID
        for (_, status) in beaconRegistry.beaconStatuses {
            if status.device.id == beaconRuleId {
                return status.device
            }
        }
        return nil
    }
    
    /// Determines if a beacon region state is reliable for rule evaluation
    @MainActor
    private func isBeaconRegionReliable(beaconID: BeaconID, beaconRegistry: BeaconRegistry) -> Bool {
        guard let beaconStatus = beaconRegistry.status(for: beaconID) else {
            return false // No status = not reliable
        }
        
        // Check if beacon is currently in region
        guard beaconStatus.isInRegion else {
            return false // Not in region
        }
        
        // Check stability requirement - must be in region for minimum duration
        if !beaconStatus.hasBeenStableInRegion(for: config.minimumRegionStabilityDuration) {
            return false // Not stable long enough in region
        }
        
        // Check for rapid toggling if history is required
        if config.requireEntryExitHistory {
            // Ensure we have both entry and exit timestamps to validate state transitions
            guard beaconStatus.lastRegionEntry != nil else {
                return false // No entry timestamp recorded
            }
            
            // If there was a recent exit, ensure enough time has passed since last transition
            if let lastExit = beaconStatus.lastRegionExit,
               let lastEntry = beaconStatus.lastRegionEntry,
               lastEntry > lastExit { // Entry is more recent than exit (currently in region)
                let timeSinceEntry = Date().timeIntervalSince(lastEntry)
                if timeSinceEntry < config.minimumRegionTransitionInterval {
                    return false // Too soon after entry
                }
            }
        }
        
        return true // All region-based reliability criteria met
    }
    
    /// Evaluates time-based blocking rules against current time.
    /// Identical to DefaultRuleProcessingStrategy implementation.
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
}

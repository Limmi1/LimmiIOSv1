//
//  RuleConditionStatus.swift
//  Limmi
//
//  Purpose: Models for representing the current status of rule conditions for UI display
//  Dependencies: Foundation
//  Related: BlockingEngine.swift, Rule.swift
//

import Foundation
import SwiftUI

/// Represents the current evaluation status of a condition
enum ConditionStatus {
    /// The condition is currently satisfied (e.g., user is in GPS zone)
    case satisfied
    /// The condition is not currently satisfied (e.g., user is outside GPS zone)
    case notSatisfied
    /// The condition is not applicable (e.g., GPS condition is disabled)
    case notApplicable
    /// The condition status cannot be determined (e.g., no location available)
    case unknown
}

/// Represents the current status of a beacon-based condition
struct BeaconConditionStatus {
    /// The Firebase document ID of the beacon
    let beaconId: String
    /// Whether this is an allowedIn or blockedIn rule
    let behaviorType: FineLocationBehavior
    /// Whether this beacon rule is currently active
    let isActive: Bool
    /// Current status of the beacon condition
    let status: ConditionStatus
}

/// Comprehensive status information for all conditions in a rule
struct RuleConditionStatus {
    /// Whether the rule itself is active
    let isRuleActive: Bool
    /// Whether the rule has any blocked apps configured
    let hasBlockedApps: Bool
    /// Current status of the GPS location condition
    let gpsConditionStatus: ConditionStatus
    /// Current status of the time-based conditions
    let timeConditionStatus: ConditionStatus
    /// Current status of all beacon-based conditions
    let beaconConditionStatuses: [BeaconConditionStatus]
    /// Whether the rule is currently blocking apps based on all conditions
    let overallBlockingStatus: Bool
}

// MARK: - UI Helper Extensions

extension ConditionStatus {
    /// User-friendly text description of the condition status
    var displayText: String {
        switch self {
        case .satisfied:
            return "Active"
        case .notSatisfied:
            return "Not Active"
        case .notApplicable:
            return "Disabled"
        case .unknown:
            return "Unknown"
        }
    }
    
    /// Color to use for displaying this condition status
    var displayColor: String {
        switch self {
        case .satisfied:
            return "green"
        case .notSatisfied:
            return "orange"
        case .notApplicable:
            return "secondary"
        case .unknown:
            return "gray"
        }
    }
    
    /// SwiftUI Color for displaying this condition status
    var swiftUIColor: Color {
        switch self {
        case .satisfied:
            return .green
        case .notSatisfied:
            return .orange
        case .notApplicable:
            return .secondary
        case .unknown:
            return .gray
        }
    }
    
    /// SF Symbol icon name for this condition status
    var iconName: String {
        switch self {
        case .satisfied:
            return "checkmark.circle.fill"
        case .notSatisfied:
            return "xmark.circle.fill"
        case .notApplicable:
            return "minus.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}

extension BeaconConditionStatus {
    /// User-friendly description of what this beacon condition means
    var conditionDescription: String {
        switch behaviorType {
        case .allowedIn:
            return "Apps allowed when near this beacon"
        case .blockedIn:
            return "Apps blocked when near this beacon"
        }
    }
    
    /// Detailed status description including beacon behavior
    var detailedStatus: String {
        guard isActive else { return "Disabled" }
        
        switch (status, behaviorType) {
        case (.satisfied, .allowedIn):
            return "Near beacon - Apps allowed"
        case (.notSatisfied, .allowedIn):
            return "Away from beacon - Apps may be blocked"
        case (.satisfied, .blockedIn):
            return "Near beacon - Apps blocked"
        case (.notSatisfied, .blockedIn):
            return "Away from beacon - Apps allowed"
        case (.notApplicable, _):
            return "Disabled"
        case (.unknown, _):
            return "Unknown beacon status"
        }
    }
}

// MARK: - Detailed Rule Evaluation Results

/// Detailed evaluation result for a single GPS location condition
struct GPSEvaluationResult {
    let isActive: Bool
    let isUserInside: Bool
    let userDistance: Double?
}

/// Detailed evaluation result for a single time rule condition
struct TimeEvaluationResult {
    let timeRuleId: String
    let timeRuleName: String
    let isActive: Bool
    let isCurrentTimeInRange: Bool
}

/// Detailed evaluation result for a single beacon condition
struct BeaconEvaluationResult {
    let fineLocationRuleId: String
    let beaconId: String
    let beaconName: String?
    let behaviorType: FineLocationBehavior
    let isActive: Bool
    let isUserNearBeacon: Bool
    let rssiValue: Double?
    let distance: Double?
}

/// Comprehensive evaluation result for all conditions in a single rule
struct DetailedRuleEvaluationResult {
    let ruleId: String
    let ruleName: String
    let isRuleActive: Bool
    let overallShouldBlock: Bool
    
    // Individual condition results
    let gpsResult: GPSEvaluationResult?
    let timeResults: [TimeEvaluationResult]
    let beaconResults: [BeaconEvaluationResult]
}
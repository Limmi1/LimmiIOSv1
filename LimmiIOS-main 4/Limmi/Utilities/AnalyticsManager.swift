//
//  AnalyticsManager.swift
//  Limmi
//
//  Purpose: Firebase Analytics helper for screen tracking and custom events
//  Dependencies: FirebaseAnalytics, Foundation
//  Related: LimmiApp.swift, AppDelegate.swift
//

import Foundation
import FirebaseAnalytics

/// Centralized analytics manager for Firebase Analytics screen and event tracking.
///
/// This class provides convenient methods for:
/// - Screen view tracking for all app screens
/// - Custom event logging with parameters
/// - User property setting
/// - Consistent event naming conventions
///
/// ## Usage
/// ```swift
/// // Track screen view
/// AnalyticsManager.shared.logScreenView(screenName: "HomePage", screenClass: "HomePageView")
/// 
/// // Track custom events
/// AnalyticsManager.shared.logEvent("rule_created", parameters: [
///     "rule_type": "beacon_based",
///     "app_count": 3
/// ])
/// ```
///
/// - Since: 1.0
final class AnalyticsManager {
    
    // MARK: - Singleton
    
    static let shared = AnalyticsManager()
    
    private init() {}
    
    // MARK: - Screen Tracking
    
    /// Logs a screen view event to Firebase Analytics.
    ///
    /// This method automatically tracks when users navigate to different screens,
    /// providing insights into user flow and screen popularity.
    ///
    /// - Parameters:
    ///   - screenName: The name of the screen (e.g., "HomePage", "RuleCreation")
    ///   - screenClass: The SwiftUI view class name (e.g., "HomePageView")
    ///   - additionalParameters: Optional custom parameters for the screen view
    func logScreenView(
        screenName: String,
        screenClass: String? = nil,
        additionalParameters: [String: Any]? = nil
    ) {
        var parameters: [String: Any] = [
            AnalyticsParameterScreenName: screenName
        ]
        
        if let screenClass = screenClass {
            parameters[AnalyticsParameterScreenClass] = screenClass
        }
        
        // Add any additional parameters
        additionalParameters?.forEach { key, value in
            parameters[key] = value
        }
        
        Analytics.logEvent(AnalyticsEventScreenView, parameters: parameters)
        
        #if DEBUG
        print("🔥 Firebase Analytics: Screen view logged - \(screenName)")
        print("📊 Parameters: \(parameters)")
        #endif
    }
    
    // MARK: - Custom Events
    
    /// Logs a custom event with optional parameters.
    ///
    /// Use this method to track user actions, feature usage, and important
    /// app interactions for analytics insights.
    ///
    /// - Parameters:
    ///   - eventName: The name of the event (use snake_case convention)
    ///   - parameters: Optional parameters to provide context about the event
    func logEvent(_ eventName: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(eventName, parameters: parameters)
        
        #if DEBUG
        print("🔥 Firebase Analytics: Event logged - \(eventName)")
        if let params = parameters {
            print("📊 Parameters: \(params)")
        }
        #endif
    }
    
    /// Forces Firebase Analytics to send all buffered events immediately.
    /// Useful for debugging and testing to ensure events are sent right away.
    func flushEvents() {
        #if DEBUG
        print("🔄 Firebase Analytics: Flushing events to server...")
        #endif
        // Note: Analytics.setSessionTimeoutDuration(1) can help with faster session processing
    }
    
    // MARK: - User Properties
    
    /// Sets a user property for analytics segmentation.
    ///
    /// User properties help segment users in Firebase Analytics reports
    /// and can be used for audience creation in other Firebase products.
    ///
    /// - Parameters:
    ///   - value: The property value (max 36 characters)
    ///   - name: The property name (max 24 characters)
    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
        
        #if DEBUG
        print("📊 Analytics: User property set - \(name): \(value ?? "nil")")
        #endif
    }
    
    /// Sets the user ID for analytics tracking.
    /// This enables User Snapshots and better user journey tracking.
    ///
    /// - Parameter userId: The user identifier (typically from authentication)
    func setUserId(_ userId: String?) {
        Analytics.setUserID(userId)
        
        #if DEBUG
        print("👤 Analytics: User ID set - \(userId ?? "nil")")
        print("🔍 This enables User Snapshots in Firebase Console")
        #endif
    }
    
    /// Forces Firebase to send all cached events immediately.
    /// Useful for debug mode to see events in real-time.
    func enableDebugMode() {
        #if DEBUG
        Analytics.setAnalyticsCollectionEnabled(true)
        print("🔥 Firebase Analytics: Debug mode enabled")
        print("📱 Device should now appear in Firebase DebugView")
        print("⏰ Wait 30-60 seconds and refresh DebugView")
        #endif
    }
    
    // MARK: - Rule-Related Events
    
    /// Logs rule creation events with detailed parameters.
    ///
    /// - Parameters:
    ///   - ruleType: Type of rule created ("beacon_based", "location_based", etc.)
    ///   - appCount: Number of apps in the rule
    ///   - hasSchedule: Whether the rule has time-based scheduling
    func logRuleCreated(ruleType: String, appCount: Int, hasSchedule: Bool) {
        logEvent("rule_created", parameters: [
            "rule_type": ruleType,
            "app_count": appCount,
            "has_schedule": hasSchedule
        ])
    }
    
    /// Logs rule modification events.
    ///
    /// - Parameter ruleId: The ID of the modified rule
    func logRuleModified(ruleId: String) {
        logEvent("rule_modified", parameters: [
            "rule_id": ruleId
        ])
    }
    
    /// Logs rule deletion events.
    ///
    /// - Parameter ruleId: The ID of the deleted rule
    func logRuleDeleted(ruleId: String) {
        logEvent("rule_deleted", parameters: [
            "rule_id": ruleId
        ])
    }
    
    // MARK: - Blocking Events
    
    /// Logs when app blocking is triggered.
    ///
    /// - Parameters:
    ///   - trigger: What triggered the blocking ("beacon_proximity", "schedule", etc.)
    ///   - appCount: Number of apps blocked
    func logAppBlocked(trigger: String, appCount: Int) {
        logEvent("app_blocked", parameters: [
            "trigger": trigger,
            "app_count": appCount
        ])
    }
    
    /// Logs when app blocking is lifted.
    ///
    /// - Parameters:
    ///   - trigger: What caused blocking to be lifted
    ///   - duration: How long blocking was active (in seconds)
    func logAppUnblocked(trigger: String, duration: TimeInterval) {
        logEvent("app_unblocked", parameters: [
            "trigger": trigger,
            "duration_seconds": Int(duration)
        ])
    }
    
    // MARK: - Beacon Events
    
    /// Logs beacon-related events.
    ///
    /// - Parameters:
    ///   - action: The beacon action ("detected", "lost", "configured")
    ///   - beaconId: The beacon identifier
    ///   - distance: The distance to the beacon (optional)
    func logBeaconEvent(action: String, beaconId: String, distance: Double? = nil) {
        var parameters: [String: Any] = [
            "action": action,
            "beacon_id": beaconId
        ]
        
        if let distance = distance {
            parameters["distance_meters"] = distance
        }
        
        logEvent("beacon_event", parameters: parameters)
    }
}

// MARK: - SwiftUI Extension

import SwiftUI

/// SwiftUI view modifier for automatic screen tracking.
///
/// This modifier automatically logs screen views when a view appears,
/// making it easy to add analytics to existing views.
///
/// ## Usage
/// ```swift
/// struct MyView: View {
///     var body: some View {
///         VStack {
///             // View content
///         }
///         .trackScreen("MyScreen", screenClass: "MyView")
///     }
/// }
/// ```
struct ScreenTrackingModifier: ViewModifier {
    let screenName: String
    let screenClass: String?
    let additionalParameters: [String: Any]?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                AnalyticsManager.shared.logScreenView(
                    screenName: screenName,
                    screenClass: screenClass,
                    additionalParameters: additionalParameters
                )
            }
    }
}

extension View {
    /// Automatically tracks screen views when this view appears.
    ///
    /// - Parameters:
    ///   - screenName: The name of the screen for analytics
    ///   - screenClass: Optional SwiftUI view class name
    ///   - additionalParameters: Optional additional parameters
    /// - Returns: A view with screen tracking enabled
    func trackScreen(
        _ screenName: String,
        screenClass: String? = nil,
        additionalParameters: [String: Any]? = nil
    ) -> some View {
        modifier(ScreenTrackingModifier(
            screenName: screenName,
            screenClass: screenClass,
            additionalParameters: additionalParameters
        ))
    }
}
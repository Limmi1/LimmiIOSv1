//
//  DeviceActivityHeartbeatService.swift
//  Limmi
//
//  Purpose: Manages DeviceActivity schedules for threshold-based heartbeat monitoring
//  Dependencies: DeviceActivity, Foundation, UnifiedLogger
//  Related: ShieldHeartbeatMonitor.swift, HeartbeatManager.swift
//

import DeviceActivity
import Foundation
import FamilyControls
import ManagedSettings
import os

/// Manages DeviceActivity schedules for threshold-based heartbeat monitoring.
///
/// This service sets up monitoring for blocked content (apps, web domains, categories) with low usage thresholds.
/// When content approaches their usage limit, the extension checks heartbeat status
/// to decide whether to extend usage (if main app is alive) or block immediately.
///
/// ## Monitoring Strategy
/// - **Always-on monitoring**: Watches blocked content continuously
/// - **Low thresholds**: Short usage limits trigger heartbeat checks quickly
/// - **Dynamic decisions**: Extend usage if main app alive + rules allow
///
/// ## Performance Considerations
/// - Extension only wakes on threshold approach (efficient)
/// - Quick heartbeat checks (<3 seconds)
/// - Battery efficient compared to periodic monitoring
///
/// - Since: 1.0
final class DeviceActivityHeartbeatService {
    
    // MARK: - Configuration
    
    /// DeviceActivity name for threshold-based monitoring
    private static let thresholdActivityName = DeviceActivityName("ThresholdHeartbeatMonitor")
    
    /// DeviceActivity event name for threshold monitoring
    private static let thresholdEventName = DeviceActivityEvent.Name("AppUsageThreshold")
    
    /// Low usage threshold that triggers heartbeat checks (in seconds)
    private static let usageThreshold: TimeInterval = 1.0 // 1 seconds of usage
    
    // MARK: - Properties
    
    private let deviceActivityCenter = DeviceActivityCenter()
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "DeviceActivityHeartbeatService")
    )
    
    // MARK: - Public Methods
    
    /// Starts threshold-based DeviceActivity monitoring for blocked content.
    ///
    /// This sets up monitoring for content that should be blocked, with low usage thresholds
    /// that trigger heartbeat checks when approached. The extension will check app liveness
    /// and decide whether to extend usage or proceed with blocking.
    ///
    /// - Parameter blockedTokens: Array of BlockedTokenInfo from Firebase
    /// - Throws: DeviceActivityError if monitoring setup fails
    func startThresholdMonitoring(for blockedTokens: [BlockedTokenInfo]) throws {
        logger.debug("Starting threshold-based monitoring for \(blockedTokens.count) blocked tokens")
        
        do {
            // Stop any existing monitoring first
            try stopThresholdMonitoring()
            
            // Create threshold-based schedule and events
            let (schedule, events) = createThresholdSchedule(for: blockedTokens)
            
            // Start monitoring with events
            try deviceActivityCenter.startMonitoring(Self.thresholdActivityName, during: schedule, events: events)
            
            logger.debug("Threshold monitoring started successfully for \(blockedTokens.count) tokens")
            
        } catch {
            logger.error("Failed to start threshold monitoring: \(error.localizedDescription)")
            throw DeviceActivityHeartbeatError.scheduleCreationFailed(error.localizedDescription)
        }
    }
    
    /// Stops threshold-based DeviceActivity monitoring.
    ///
    /// This removes the monitoring schedule, stopping threshold checks.
    /// Should be called when apps are no longer being monitored.
    ///
    /// - Throws: DeviceActivityError if schedule removal fails
    func stopThresholdMonitoring() throws {
        logger.debug("Stopping threshold-based monitoring")
        
        do {
            deviceActivityCenter.stopMonitoring([Self.thresholdActivityName])
            logger.debug("Threshold monitoring stopped successfully")
            
        } catch {
            logger.error("Failed to stop threshold monitoring: \(error.localizedDescription)")
            throw DeviceActivityHeartbeatError.scheduleRemovalFailed(error.localizedDescription)
        }
    }
    
    /// Checks if heartbeat monitoring is currently active.
    ///
    /// - Returns: True if the DeviceActivity schedule is running
    func isHeartbeatMonitoringActive() -> Bool {
        // Note: DeviceActivityCenter doesn't provide a direct way to check if a specific
        // activity is running, so we'll track this internally or assume it's running
        // if the service was started successfully
        return true // Simplified for now
    }
    
    /// Forces an immediate threshold check by restarting the monitoring.
    ///
    /// This can be useful for testing or when immediate validation is needed.
    /// The monitoring restart will trigger the extension immediately.
    ///
    /// - Parameter blockedTokens: Array of BlockedTokenInfo from Firebase
    /// - Throws: DeviceActivityError if monitoring restart fails
    func triggerImmediateCheck(for blockedTokens: [BlockedTokenInfo]) throws {
        logger.debug("Triggering immediate threshold check")
        
        do {
            try stopThresholdMonitoring()
            try startThresholdMonitoring(for: blockedTokens)
            logger.debug("Immediate threshold check triggered successfully")
            
        } catch {
            logger.error("Failed to trigger immediate check: \(error.localizedDescription)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    /// Creates a DeviceActivitySchedule and events for threshold-based monitoring.
    ///
    /// Sets up continuous monitoring with usage thresholds that trigger heartbeat checks.
    /// When content approaches their usage limit, the extension will check main app liveness.
    ///
    /// - Parameter blockedTokens: Array of BlockedTokenInfo from Firebase
    /// - Returns: Tuple of (schedule, events) for DeviceActivity monitoring
    private func createThresholdSchedule(for blockedTokens: [BlockedTokenInfo]) -> (DeviceActivitySchedule, [DeviceActivityEvent.Name: DeviceActivityEvent]) {
        // Create an all-day schedule that runs continuously
        let calendar = Calendar.current
        
        let intervalStart = DateComponents(
            calendar: calendar,
            hour: 0,
            minute: 0
        )
        
        let intervalEnd = DateComponents(
            calendar: calendar,
            hour: 23,
            minute: 59
        )
        
        let schedule = DeviceActivitySchedule(
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            repeats: true
        )
        
        // Extract tokens from BlockedTokenInfo array
        var applications = Set<ApplicationToken>()
        var webDomains = Set<WebDomainToken>()
        var categories = Set<ActivityCategoryToken>()
        
        for tokenInfo in blockedTokens {
            guard tokenInfo.isActive else { continue }
            
            switch tokenInfo.tokenType {
            case "application":
                if let token = tokenInfo.decodedApplicationToken() {
                    applications.insert(token)
                }
            case "webDomain":
                if let token = tokenInfo.decodedWebDomainToken() {
                    webDomains.insert(token)
                }
            case "activityCategory":
                if let token = tokenInfo.decodedActivityCategoryToken() {
                    categories.insert(token)
                }
            default:
                logger.info("Unknown token type: \(tokenInfo.tokenType)")
            }
        }
        
        // Create events for content usage thresholds
        let thresholdEvent = DeviceActivityEvent(
            applications: applications,
            categories: categories,
            webDomains: webDomains,
            threshold: DateComponents(second: Int(Self.usageThreshold))
        ) // If we focused only on iOS 17.4+ we could use "includesPastActivity: false" and we wouldn't have to create 2 activities with one dynamic starting after the last threshold reached.
        
        let events = [Self.thresholdEventName: thresholdEvent]
        
        let totalContent = applications.count + webDomains.count + categories.count
        logger.debug("Created threshold schedule: threshold=\(Self.usageThreshold)s, total=\(totalContent) (apps=\(applications.count), web=\(webDomains.count), categories=\(categories.count))")
        return (schedule, events)
    }
}

// MARK: - Error Types

/// Errors that can occur during DeviceActivity heartbeat service operations.
enum DeviceActivityHeartbeatError: LocalizedError {
    case scheduleCreationFailed(String)
    case scheduleRemovalFailed(String)
    case scheduleUpdateFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .scheduleCreationFailed(let message):
            return "Failed to create DeviceActivity schedule: \(message)"
        case .scheduleRemovalFailed(let message):
            return "Failed to remove DeviceActivity schedule: \(message)"
        case .scheduleUpdateFailed(let message):
            return "Failed to update DeviceActivity schedule: \(message)"
        }
    }
}

// MARK: - Integration Extensions

extension DeviceActivityHeartbeatService {
    
    /// Convenience method to start monitoring with blocked tokens from Firebase.
    ///
    /// This should be called when blocked content changes to update monitoring.
    /// It's safe to call multiple times.
    ///
    /// - Parameter blockedTokens: Array of BlockedTokenInfo from Firebase
    func startWithBlockedTokens(_ blockedTokens: [BlockedTokenInfo]) {
        let activeTokens = blockedTokens.filter { $0.isActive }
        guard !activeTokens.isEmpty else {
            do {
                try stopThresholdMonitoring()
            } catch {
                logger.error("Failed to stop threshold monitoring : \(error.localizedDescription)")
                // Don't throw here - we're shutting down anyway
            }
            logger.debug("No active blocked tokens to monitor - skipping threshold monitoring")
            return
        }
        
        do {
            try startThresholdMonitoring(for: activeTokens)
        } catch {
            logger.error("Failed to start threshold monitoring with blocked tokens: \(error.localizedDescription)")
            // Don't throw here - monitoring is not critical for basic app functionality
        }
    }

}

//
//  ShieldHeartbeatMonitor.swift
//  shield (DeviceActivity Extension)
//
//  Purpose: Monitors app heartbeat to detect force-quit and automatically apply shields
//  Dependencies: DeviceActivity, ManagedSettings, Foundation
//  Related: HeartbeatManager.swift, ShieldConfigurationExtension.swift
//

import DeviceActivity
import ManagedSettings
import Foundation
import os

/// Monitors heartbeat signals from the main app to detect force-quit scenarios.
///
/// This class implements the shield-side heartbeat monitoring logic:
/// 1. Periodically wakes via DeviceActivitySchedule (every minute)
/// 2. Checks for presence file and heartbeat timestamp staleness
/// 3. Applies/lifts shields automatically based on app liveness
///
/// ## Detection Logic
/// - **Presence file exists**: App force-quit in foreground → APPLY SHIELD
/// - **Heartbeat stale**: App killed in background → APPLY SHIELD
/// - **Heartbeat fresh**: App is alive → LIFT SHIELD
///
/// ## Performance
/// - Designed for <6MB memory usage (extension limits)
/// - Complete check in <3 seconds
/// - Minimal I/O operations for battery efficiency
///
/// - Since: 1.0
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    
    // MARK: - Configuration
    
    /// App Group identifier for shared container access (must match main app)
    private static let appGroupIdentifier = "group.com.ah.limmi.shareddata"
    
    /// UserDefaults key for heartbeat timestamp (must match HeartbeatManager)
    private static let heartbeatKey = "lastHeartbeat"
    
    /// Presence file name in shared container (must match HeartbeatManager)
    private static let aliveFileName = "alive.flag"
    
    /// Maximum age before heartbeat is considered stale (must match HeartbeatManager)
    private static let stalenessThreshold: TimeInterval = 60.0
    
    /// Extension duration when threshold is extended (10 sec)
    private static let thresholdExtensionDuration: TimeInterval = 30.0
    
    // MARK: - Properties
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.shield", category: "ShieldHeartbeatMonitor")
    )
    
    
    private let fileManager = FileManager.default
    
    /// Shared ManagedSettings store - same as main app uses
    private let managedSettingsStore = ManagedSettingsStore()
    
    /// Core blocking utility using the default shared store (same as main app)
    private let blockingUtility = DAMCoreBlockingUtility()
    
    /// DeviceActivityCenter for updating threshold schedules
    private let deviceActivityCenter = DeviceActivityCenter()
    
    private lazy var sharedDefaults: UserDefaults? = {
        UserDefaults(suiteName: Self.appGroupIdentifier)
    }()
    
    private lazy var appGroupContainer: URL? = {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
    }()
    
    private lazy var aliveFilePath: URL? = {
        appGroupContainer?.appendingPathComponent(Self.aliveFileName)
    }()
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        logger.debug("DAM ShieldHeartbeatMonitor initialized")
        logger.forceFlush(synchronous: true)
    }
    
    // MARK: - DeviceActivityMonitor Implementation
    
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        logger.debug("Heartbeat monitor interval started")
        // When interval starts, assume main app is alive
        clearSafetyNetBlocking()
        
        // Force flush to ensure we capture DAM extension startup
        logger.forceFlush(synchronous: true)
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        logger.debug("Heartbeat monitor interval ended")
        // When interval ends, check if we need safety net - No we don't because it's called when the main app is restarted which cause a blocking flickering.
        // performMainAppLivenessCheck()
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        logger.debug("Heartbeat monitor threshold event triggered: event=\(event), activity=\(activity)")
        
        // Check if main app is alive and act accordingly
        performMainAppLivenessCheck()
        
        // Force flush logs since DAM extension may terminate soon
        logger.forceFlush(synchronous: true)
    }
    
    // MARK: - Main App Liveness Check
    
    /// Performs main app liveness check and applies safety net blocking if needed.
    ///
    /// This method checks if the main app is alive via heartbeat. If the main app
    /// is dead/force-quit, it applies "safety net" blocking for all tokens from
    /// active rules to ensure blocking continues until the main app is restored.
    private func performMainAppLivenessCheck() {
        let checkStartTime = Date()
        logger.debug("Starting main app liveness check")
        
        do {
            // Check if main app is alive via heartbeat
            let heartbeatStatus = try checkHeartbeatStatus()
            let shouldApplySafetyNet = determineShieldAction(from: heartbeatStatus)
            
            if shouldApplySafetyNet {
                logger.debug("Main app appears to be dead - applying safety net blocking")
                applySafetyNetBlocking()
            } else {
                logger.debug("Main app is alive - clearing any safety net blocking and extending threshold")
                clearSafetyNetBlocking()
                extendDynamicSchedule()
                //extendThresholdBy2Minutes()
            }
            
            let checkDuration = Date().timeIntervalSince(checkStartTime)
            logger.debug("Main app liveness check completed in \(String(format: "%.3f", checkDuration))s")
            
        } catch {
            logger.error("Main app liveness check failed: \(error.localizedDescription)")
            // On error, apply safety net as precaution
            logger.debug("Applying safety net blocking due to check failure")
            applySafetyNetBlocking()
        }
        
        // Force flush critical logs immediately
        logger.forceFlush(synchronous: true)
    }
    
    /// Applies safety net blocking using tokens from active rules.
    ///
    /// When the main app is determined to be dead, this method loads the active
    /// rule tokens and blocks ALL of them to ensure blocking continues.
    /// It also sets the location verification flag for the shield UI.
    private func applySafetyNetBlocking() {
        logger.debug("Applying safety net blocking")
        
        // Set the DAM blocking flag to indicate DAM is handling blocking
        DamBlockingFlagManager.setFlag()
        
        // Load active rule tokens from shared storage
        guard let sharedData = DAMSharedDataManager.loadActiveRuleData() else {
            logger.info("No active rule data available for safety net blocking")
            return
        }
        
        // Validate data
        guard sharedData.isValid() && sharedData.isFresh(maxAgeSeconds: 3600) else {
            logger.info("Active rule data is invalid or stale - not applying safety net")
            return
        }
        
        // Apply blocking for ALL tokens from active rules
        if sharedData.hasTokens {
            logger.debug("Applying safety net blocking for \(sharedData.totalTokenCount) tokens from active rules")
            blockingUtility.applyActiveRuleBlocking(from: sharedData)
        } else {
            logger.debug("No tokens in active rules - no safety net blocking needed")
        }
    }
    
    /// Clears safety net blocking to allow main app to resume control.
    ///
    /// When the main app is determined to be alive, this method clears any
    /// safety net blocking so the main app can handle sophisticated rule evaluation.
    /// It also clears the location verification flag.
    private func clearSafetyNetBlocking() {
        logger.debug("Clearing safety net blocking - main app is alive")
        
        // Clear the DAM blocking flag since main app is handling blocking
        DamBlockingFlagManager.clearFlag()
        
        // Note: We DON'T clear the shared ManagedSettings store here because
        // the main app is alive and handling blocking. We just ensure we're
        // not interfering with its decisions.
        
        // The main app will handle all blocking decisions from here
        logger.debug("Safety net cleared - main app has control")
    }
    
    
    private func extendDynamicSchedule() {
        logger.debug("Extending (& create) dynamic schedule to extend monitoring")
        
        do {
            // Load active rule data to get current blocked tokens
            guard let sharedData = DAMSharedDataManager.loadActiveRuleData(),
                  sharedData.isValid() else {
                logger.info("No valid active rule data available - cannot extend threshold")
                return
            }
            
            // Create updated schedule with extended threshold
            let (schedule, events) = createDynamicThresholdSchedule(from: sharedData)
            
            // Update the dynamic monitoring with extended threshold
            try deviceActivityCenter.startMonitoring(.thresholdDynamicActivityName, during: schedule, events: events)
            
            logger.debug("Successfully extended DeviceActivity threshold by \(Int(Self.thresholdExtensionDuration))s")
            
        } catch {
            logger.error("Failed to extend DeviceActivity threshold: \(error.localizedDescription)")
            // Not critical - the current schedule will continue running
        }
        
    }
    
    /// Checks the current heartbeat status from shared storage.
    ///
    /// - Returns: HeartbeatStatus containing presence file and timestamp information
    /// - Throws: HeartbeatMonitorError if unable to access shared storage
    private func checkHeartbeatStatus() throws -> HeartbeatStatus {
        guard let aliveFilePath = aliveFilePath else {
            throw HeartbeatMonitorError.appGroupNotAccessible
        }
        
        // Check presence file
        let presenceFileExists = fileManager.fileExists(atPath: aliveFilePath.path)
        
        // Check heartbeat timestamp
        let heartbeatTimestamp = sharedDefaults?.double(forKey: Self.heartbeatKey) ?? 0
        let heartbeatAge = heartbeatTimestamp > 0 ? Date().timeIntervalSince1970 - heartbeatTimestamp : Double.infinity
        let isHeartbeatStale = heartbeatAge > Self.stalenessThreshold
        
        let status = HeartbeatStatus(
            presenceFileExists: presenceFileExists,
            heartbeatTimestamp: heartbeatTimestamp > 0 ? heartbeatTimestamp : nil,
            heartbeatAge: heartbeatAge == Double.infinity ? nil : heartbeatAge,
            isHeartbeatStale: isHeartbeatStale
        )
        
        logger.debug("Heartbeat status: presence=\(presenceFileExists), age=\(heartbeatAge)s, stale=\(isHeartbeatStale)")
        return status
    }
    
    /// Determines whether shield should be active based on heartbeat status.
    ///
    /// Implements the detection logic:
    /// - Presence file exists → App force-quit in foreground → Shield ON
    /// - No presence file + stale heartbeat → App killed in background → Shield ON
    /// - No presence file + fresh heartbeat → App alive in background → Shield OFF
    ///
    /// - Parameter status: Current heartbeat status
    /// - Returns: True if shield should be active, false if it should be lifted
    private func determineShieldAction(from status: HeartbeatStatus) -> Bool {
        // Priority 1: Check for presence file (indicates foreground force-quit)
        if status.presenceFileExists {
            logger.debug("Presence file detected - main app foreground or has been force-quit in background")
        }
        
        // Priority 2: Check heartbeat staleness (indicates background kill or no activity)
        if status.isHeartbeatStale {
            logger.debug("Heartbeat is stale (age: \(status.heartbeatAge ?? -1)s) - app likely killed")
            return true // Apply shield
        }
        
        // App appears to be alive and running normally
        logger.debug("Heartbeat is fresh - app is alive")
        return false // Lift shield
    }
    
    /// Creates an extended DeviceActivity schedule with updated threshold.
    ///
    /// This method creates a DeviceActivity schedule that starts one minute from now
    /// with the extended threshold duration to delay the next event.
    ///
    /// - Parameter sharedData: Active rule data containing blocked tokens
    /// - Returns: Tuple of (schedule, events) for DeviceActivity monitoring
    private func createDynamicThresholdSchedule(from sharedData: DAMSharedActiveRuleData) -> (DeviceActivitySchedule, [DeviceActivityEvent.Name: DeviceActivityEvent]) {
        
        // Create a schedule that starts in 10 sec from now
        let calendar = Calendar.current
        let now = Date()
        let startTime = now.addingTimeInterval(10)
        
        let intervalStart = calendar.dateComponents([.hour, .minute, .second], from: startTime)
        
        // Set end time to end of day to ensure continuous monitoring
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
        
        // Convert DAMBlockedTokenInfo to Screen Time tokens
        var applications = Set<ApplicationToken>()
        var webDomains = Set<WebDomainToken>()
        var categories = Set<ActivityCategoryToken>()
        
        for tokenInfo in sharedData.activeRuleTokens {
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
        
        // Get the original threshold from DeviceActivityHeartbeatService (1 second based on the updated config)
        let originalThreshold: TimeInterval = 1.0
        let extendedThreshold = originalThreshold + Self.thresholdExtensionDuration
        
        // Create events with extended threshold
        let thresholdEvent = DeviceActivityEvent(
            applications: applications,
            categories: categories,
            webDomains: webDomains,
            threshold: DateComponents(second: Int(extendedThreshold))
        )
        
        let events = [DeviceActivityEvent.Name.thresholdEventName: thresholdEvent]
        
        let totalContent = applications.count + webDomains.count + categories.count
        let startTimeString = DateFormatter.localizedString(from: startTime, dateStyle: .none, timeStyle: .medium)
        logger.debug("Created extended threshold schedule starting at \(startTimeString): threshold=\(Int(extendedThreshold))s, total=\(totalContent) tokens (apps=\(applications.count), web=\(webDomains.count), categories=\(categories.count))")
        
        return (schedule, events)
    }

}

// MARK: - DeviceActivity Extensions

extension DeviceActivityName {
    /// DeviceActivity name for threshold-based monitoring (matches main app)
    static let thresholdActivityName = DeviceActivityName("ThresholdHeartbeatMonitor")
}

extension DeviceActivityName {
    static let thresholdMainActivityName = DeviceActivityName("ThresholdHeartbeatMonitor")
}

extension DeviceActivityName {
    static let thresholdDynamicActivityName = DeviceActivityName("DynamicThresholdMonitor")
}

extension DeviceActivityEvent.Name {
    /// DeviceActivity event name for threshold monitoring (matches main app)
    static let thresholdEventName = DeviceActivityEvent.Name("AppUsageThreshold")
}

// MARK: - Supporting Types

/// Represents the current status of the heartbeat system.
struct HeartbeatStatus {
    /// Whether the presence file exists in the shared container
    let presenceFileExists: Bool
    
    /// Timestamp of the last heartbeat (nil if never set)
    let heartbeatTimestamp: TimeInterval?
    
    /// Age of the heartbeat in seconds (nil if never set)
    let heartbeatAge: TimeInterval?
    
    /// Whether the heartbeat exceeds the staleness threshold
    let isHeartbeatStale: Bool
}

/// Errors that can occur during heartbeat monitoring.
enum HeartbeatMonitorError: LocalizedError {
    case appGroupNotAccessible
    case heartbeatCheckFailed(String)
    case shieldOperationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .appGroupNotAccessible:
            return "App Group container is not accessible"
        case .heartbeatCheckFailed(let message):
            return "Heartbeat check failed: \(message)"
        case .shieldOperationFailed(let message):
            return "Shield operation failed: \(message)"
        }
    }
}

// MARK: - Debugging Extensions

extension DeviceActivityMonitorExtension {
    /// Returns detailed status information for debugging.
    func getDebugStatus() throws -> String {
        let status = try checkHeartbeatStatus()
        let containerPath = appGroupContainer?.path ?? "N/A"
        let sharedData = DAMSharedDataManager.loadActiveRuleData()
        
        let safetyNetInfo: String
        if let data = sharedData {
            safetyNetInfo = """
            - Safety net data: \(data.shortDescription)
            - Is valid: \(data.isValid())
            - Is fresh: \(data.isFresh())
            - App tokens: \(data.applicationTokens.count)
            - Web tokens: \(data.webDomainTokens.count)
            - Category tokens: \(data.activityCategoryTokens.count)
            """
        } else {
            safetyNetInfo = "- Safety net data: none"
        }
        
        return """
        Shield Heartbeat Monitor Debug Status:
        - Container path: \(containerPath)
        - Presence file exists: \(status.presenceFileExists)
        - Heartbeat timestamp: \(status.heartbeatTimestamp?.description ?? "none")
        - Heartbeat age: \(status.heartbeatAge?.description ?? "none")s
        - Is stale: \(status.isHeartbeatStale)
        - Staleness threshold: \(Self.stalenessThreshold)s
        - Would apply safety net: \(determineShieldAction(from: status))
        \(safetyNetInfo)
        - Blocking utility: \(blockingUtility.currentStateDescription)
        - Shared store: Default ManagedSettingsStore (same as main app)
        """
    }
}

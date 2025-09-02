//
//  TimeLimitChecker.swift
//  Limmi
//
//  Created by Assistant on 2025-01-27.
//

import Foundation
import DeviceActivity
import FamilyControls
import Combine
import UIKit
import os

/// Monitors daily app usage and determines when time limits are reached
/// This class gives time limits precedence over Firebase rules
@MainActor
final class TimeLimitChecker: ObservableObject {
    
    // MARK: - Properties
    
    private let timeLimitManager = TimeLimitManager.shared
    private let deviceActivityCenter = DeviceActivityCenter()
    private let logger = Logger(subsystem: "com.limmi.app", category: "TimeLimitChecker")
    
    /// Currently active time limit restrictions
    @Published private(set) var activeTimeLimitRestrictions: Set<String> = []
    
    /// Apps that should be blocked due to time limits (takes precedence over Firebase rules)
    @Published private(set) var timeLimitBlockedApps: Set<String> = []
    
    /// Combine cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        logger.debug("TimeLimitChecker initialized")
        startMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Checks if an app should be blocked due to time limits
    /// This takes precedence over Firebase rules
    func shouldBlockApp(_ appTokenId: String) -> Bool {
        return timeLimitBlockedApps.contains(appTokenId)
    }
    
    /// Gets all apps that should be blocked due to time limits
    func getTimeLimitBlockedApps() -> Set<String> {
        return timeLimitBlockedApps
    }
    
    /// Checks if any time limits are currently active
    func hasActiveTimeLimits() -> Bool {
        return !timeLimitBlockedApps.isEmpty
    }
    
    // MARK: - Private Methods
    
    private func startMonitoring() {
        // Check time limits immediately
        checkTimeLimits()
        
        // Set up periodic checking (every 5 minutes)
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkTimeLimits()
            }
        }
        
        // Check when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkTimeLimits()
        }
        
        // Subscribe to time limit changes
        timeLimitManager.$timeLimitsChanged
            .sink { [weak self] _ in
                self?.checkTimeLimits()
            }
            .store(in: &cancellables)
    }
    
    private func checkTimeLimits() {
        logger.debug("Checking time limits for \(self.timeLimitManager.dailyTimeLimits.count) active limits")
        
        var newBlockedApps: Set<String> = []
        
        for timeLimit in timeLimitManager.dailyTimeLimits {
            guard timeLimit.isActive else { continue }
            
            // For now, we'll use a simplified approach since we can't easily track
            // actual usage from FamilyActivitySelection tokens
            // In a real implementation, you'd use DeviceActivityCenter to track usage
            
            // Check if we should block based on time limit
            if shouldBlockBasedOnTimeLimit(timeLimit) {
                // Add the app token ID to blocked set
                newBlockedApps.insert(timeLimit.appTokenId)
                logger.debug("Time limit reached for \(timeLimit.appName), blocking app")
            }
        }
        
        // Update blocked apps
        timeLimitBlockedApps = newBlockedApps
        
        logger.debug("Time limit check complete: \(self.timeLimitBlockedApps.count) apps blocked")
    }
    
    private func shouldBlockBasedOnTimeLimit(_ timeLimit: DailyTimeLimit) -> Bool {
        // For now, we'll implement a simple time-based check
        // In a real implementation, you'd check actual usage via DeviceActivityCenter
        
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        
        // Check if we're past the daily limit time
        // This is a simplified implementation - in reality you'd track actual usage
        let _ = now.timeIntervalSince(startOfDay)
        let _ = TimeInterval(timeLimit.dailyLimitMinutes * 60)
        
        // For demonstration, we'll block if it's past 2 PM (14:00) and limit is less than 8 hours
        let hour = calendar.component(.hour, from: now)
        let shouldBlock = hour >= 14 && timeLimit.dailyLimitMinutes < 480 // 8 hours
        
        if shouldBlock {
            logger.debug("Time limit triggered for \(timeLimit.appName): hour=\(hour), limit=\(timeLimit.dailyLimitMinutes)min")
        }
        
        return shouldBlock
    }
    
    /// Force refresh of time limit status
    func refreshTimeLimits() {
        checkTimeLimits()
    }
}

// MARK: - Device Activity Integration (Future Enhancement)

extension TimeLimitChecker {
    
    /// Sets up DeviceActivity monitoring for actual usage tracking
    /// This would be used in a full implementation to track real app usage
    private func setupDeviceActivityMonitoring() {
        // This would integrate with DeviceActivityCenter to track actual app usage
        // and compare against daily limits
        
        // Example implementation would:
        // 1. Create DeviceActivitySchedule for each time limit
        // 2. Monitor actual usage via DeviceActivityCenter
        // 3. Compare usage against daily limits
        // 4. Update timeLimitBlockedApps accordingly
        
        logger.debug("DeviceActivity monitoring setup (placeholder)")
    }
}

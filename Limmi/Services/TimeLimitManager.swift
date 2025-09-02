//
//  TimeLimitManager.swift
//  Limmi
//
//  Created by Assistant on 2025-01-27.
//

import Foundation
import SwiftUI

/// Manages local persistence of daily time limits using UserDefaults
class TimeLimitManager: ObservableObject {
    static let shared = TimeLimitManager()
    
    @Published var dailyTimeLimits: [DailyTimeLimit] = []
    
    /// Publisher for notifying when time limits change
    @Published var timeLimitsChanged = false
    
    private let userDefaults = UserDefaults.standard
    private let timeLimitsKey = "dailyTimeLimits"
    
    private init() {
        loadTimeLimits()
    }
    
    /// Loads time limits from UserDefaults
    private func loadTimeLimits() {
        guard let data = userDefaults.data(forKey: timeLimitsKey),
              let decodedLimits = try? JSONDecoder().decode([DailyTimeLimit].self, from: data) else {
            dailyTimeLimits = []
            return
        }
        dailyTimeLimits = decodedLimits
    }
    
    /// Saves time limits to UserDefaults
    private func saveTimeLimits() {
        guard let data = try? JSONEncoder().encode(dailyTimeLimits) else {
            print("Failed to encode time limits")
            return
        }
        userDefaults.set(data, forKey: timeLimitsKey)
    }
    
    /// Adds a new time limit
    func addTimeLimit(_ timeLimit: DailyTimeLimit) {
        dailyTimeLimits.append(timeLimit)
        saveTimeLimits()
        notifyTimeLimitsChanged()
    }
    
    /// Updates an existing time limit
    func updateTimeLimit(_ timeLimit: DailyTimeLimit) {
        if let index = dailyTimeLimits.firstIndex(where: { $0.id == timeLimit.id }) {
            dailyTimeLimits[index] = timeLimit
            saveTimeLimits()
            notifyTimeLimitsChanged()
        }
    }
    
    /// Deletes a time limit
    func deleteTimeLimit(id: UUID) {
        dailyTimeLimits.removeAll { $0.id == id }
        saveTimeLimits()
        notifyTimeLimitsChanged()
    }
    
    /// Gets all active time limits
    func getActiveTimeLimits() -> [DailyTimeLimit] {
        return dailyTimeLimits.filter { $0.isActive }
    }
    
    /// Notifies that time limits have changed
    private func notifyTimeLimitsChanged() {
        timeLimitsChanged.toggle() // Toggle to trigger publisher
    }
}

// MARK: - Daily Time Limit Model
struct DailyTimeLimit: Identifiable, Codable {
    var id = UUID()
    var appName: String
    var appTokenId: String
    var dailyLimitMinutes: Int
    var resetTime: Date
    var isActive: Bool
    var warningThresholdMinutes: Int
    var gracePeriodMinutes: Int
    
    init(appName: String, appTokenId: String, dailyLimitMinutes: Int, resetTime: Date = Calendar.current.startOfDay(for: Date()), isActive: Bool = true, warningThresholdMinutes: Int = 0, gracePeriodMinutes: Int = 5) {
        self.appName = appName
        self.appTokenId = appTokenId
        self.dailyLimitMinutes = dailyLimitMinutes
        self.resetTime = resetTime
        self.isActive = isActive
        self.warningThresholdMinutes = warningThresholdMinutes
        self.gracePeriodMinutes = gracePeriodMinutes
    }
}

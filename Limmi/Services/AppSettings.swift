//
//  AppSettings.swift
//  Limmi
//
//  Purpose: Centralized app settings and user preferences management
//  Dependencies: Foundation, Combine
//  Related: RuleProcessingStrategyType.swift, ConfigurationView.swift
//

import Foundation
import Combine

/// Centralized settings manager for app-wide user preferences
///
/// This class provides a reactive interface for managing user settings with
/// automatic persistence to UserDefaults. All settings are published via
/// Combine for reactive UI updates.
///
/// ## Key Features
/// - **Reactive**: All settings are @Published for SwiftUI integration
/// - **Persistent**: Automatically saves to UserDefaults
/// - **Type-Safe**: Uses enums and structured types for settings
/// - **Observable**: Conforms to ObservableObject for SwiftUI
///
/// ## Usage
/// ```swift
/// @StateObject private var settings = AppSettings.shared
/// 
/// // Read setting
/// let strategy = settings.ruleProcessingStrategy
/// 
/// // Update setting (automatically persists)
/// settings.ruleProcessingStrategy = .region
/// ```
final class AppSettings: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AppSettings()
    
    // MARK: - Published Settings
    
    /// Currently selected rule processing strategy
    @Published var ruleProcessingStrategy: RuleProcessingStrategyType {
        didSet {
            UserDefaults.standard.set(ruleProcessingStrategy.rawValue, forKey: Keys.ruleProcessingStrategy)
        }
    }
    
    /// Enable detailed logging for debugging
    @Published var enableDetailedLogging: Bool {
        didSet {
            UserDefaults.standard.set(enableDetailedLogging, forKey: Keys.enableDetailedLogging)
        }
    }
    
    /// Enable performance monitoring
    @Published var enablePerformanceMonitoring: Bool {
        didSet {
            UserDefaults.standard.set(enablePerformanceMonitoring, forKey: Keys.enablePerformanceMonitoring)
        }
    }
    
    // MARK: - Private Keys
    
    private enum Keys {
        static let ruleProcessingStrategy = "ruleProcessingStrategy"
        static let strategyConfigurationLevel = "strategyConfigurationLevel"
        static let enableDetailedLogging = "enableDetailedLogging"
        static let enablePerformanceMonitoring = "enablePerformanceMonitoring"
    }
    
    // MARK: - Initialization
    
    private init() {
        // Load rule processing strategy
        if let strategyRawValue = UserDefaults.standard.string(forKey: Keys.ruleProcessingStrategy),
           let strategy = RuleProcessingStrategyType(rawValue: strategyRawValue) {
            self.ruleProcessingStrategy = strategy
        } else {
            self.ruleProcessingStrategy = .region
        }
        
        // Load other settings
        self.enableDetailedLogging = UserDefaults.standard.bool(forKey: Keys.enableDetailedLogging)
        self.enablePerformanceMonitoring = UserDefaults.standard.bool(forKey: Keys.enablePerformanceMonitoring)
    }
    
    // MARK: - Computed Properties
    
    /// Creates the currently configured rule processing strategy
    var currentStrategy: RuleProcessingStrategy {
        return ruleProcessingStrategy.createStrategy()
    }
    
    /// Returns BlockingEngine configuration based on current settings
    var blockingEngineConfiguration: BlockingEngine.Configuration {
        return BlockingEngine.Configuration(
            enablePerformanceMonitoring: enablePerformanceMonitoring,
            enableDetailedLogging: enableDetailedLogging,
            eventProcessingQueueSize: 100,
            blockingEvaluationInterval: 1.0,
            locationUpdateThreshold: 0.0
        )
    }
    
    // MARK: - Reset Methods
    
    /// Resets all settings to their default values
    func resetToDefaults() {
        ruleProcessingStrategy = .region
        enableDetailedLogging = false
        enablePerformanceMonitoring = false
    }
    
    /// Resets only the rule processing settings
    func resetRuleProcessingSettings() {
        ruleProcessingStrategy = .region
    }
}

// MARK: - Publisher Extensions

extension AppSettings {
    /// Publisher for rule processing strategy changes
    var ruleProcessingStrategyPublisher: AnyPublisher<RuleProcessingStrategyType, Never> {
        $ruleProcessingStrategy.eraseToAnyPublisher()
    }
    
    /// Publisher that emits when the current strategy configuration changes
    var currentStrategyPublisher: AnyPublisher<RuleProcessingStrategy, Never> {
        $ruleProcessingStrategy
            .map { strategyType in
                strategyType.createStrategy()
            }
            .eraseToAnyPublisher()
    }
}

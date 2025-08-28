//
//  BlockingEngineConfiguration.swift
//  Limmi
//
//  Created by Claude Code on 09.07.2025.
//

import Foundation
import CoreLocation

/// Advanced configuration options for the BlockingEngine
struct BlockingEngineConfiguration {
    
    // MARK: - Core Configuration
    
    /// Whether the engine is enabled
    let isEnabled: Bool
    
    /// Performance monitoring settings
    let performanceConfiguration: PerformanceConfiguration
    
    /// Event processing settings
    let eventProcessingConfiguration: EventProcessingConfiguration
    
    /// Beacon monitoring settings
    let beaconConfiguration: BeaconConfiguration
    
    /// Location monitoring settings
    let locationConfiguration: LocationConfiguration
    
    /// Rule evaluation settings
    let ruleEvaluationConfiguration: RuleEvaluationConfiguration
    
    /// Logging settings
    let loggingConfiguration: LoggingConfiguration
    
    // MARK: - Default Configuration
    
    static let `default` = BlockingEngineConfiguration(
        isEnabled: true,
        performanceConfiguration: .default,
        eventProcessingConfiguration: .default,
        beaconConfiguration: .default,
        locationConfiguration: .default,
        ruleEvaluationConfiguration: .default,
        loggingConfiguration: .default
    )
    
    // MARK: - Development Configuration
    
    static let development = BlockingEngineConfiguration(
        isEnabled: true,
        performanceConfiguration: .development,
        eventProcessingConfiguration: .development,
        beaconConfiguration: .development,
        locationConfiguration: .development,
        ruleEvaluationConfiguration: .development,
        loggingConfiguration: .development
    )
    
    // MARK: - Production Configuration
    
    static let production = BlockingEngineConfiguration(
        isEnabled: true,
        performanceConfiguration: .production,
        eventProcessingConfiguration: .production,
        beaconConfiguration: .production,
        locationConfiguration: .production,
        ruleEvaluationConfiguration: .production,
        loggingConfiguration: .production
    )
    
    // MARK: - Testing Configuration
    
    static let testing = BlockingEngineConfiguration(
        isEnabled: true,
        performanceConfiguration: .testing,
        eventProcessingConfiguration: .testing,
        beaconConfiguration: .testing,
        locationConfiguration: .testing,
        ruleEvaluationConfiguration: .testing,
        loggingConfiguration: .testing
    )
}

// MARK: - Performance Configuration

struct PerformanceConfiguration {
    let isEnabled: Bool
    let metricsUpdateInterval: TimeInterval
    let enableCPUMonitoring: Bool
    let enableMemoryMonitoring: Bool
    let maxStoredSamples: Int
    let performanceThresholds: [PerformanceMonitor.Metric: Double]
    let alertThresholds: [PerformanceMonitor.Metric: Double]
    
    static let `default` = PerformanceConfiguration(
        isEnabled: true,
        metricsUpdateInterval: 5.0,
        enableCPUMonitoring: true,
        enableMemoryMonitoring: true,
        maxStoredSamples: 100,
        performanceThresholds: [
            .averageRuleEvaluationTime: 0.1,
            .memoryUsage: 50.0,
            .eventProcessingLatency: 0.05
        ],
        alertThresholds: [
            .averageRuleEvaluationTime: 0.2,
            .memoryUsage: 75.0,
            .eventProcessingLatency: 0.1
        ]
    )
    
    static let development = PerformanceConfiguration(
        isEnabled: true,
        metricsUpdateInterval: 1.0,
        enableCPUMonitoring: true,
        enableMemoryMonitoring: true,
        maxStoredSamples: 50,
        performanceThresholds: [
            .averageRuleEvaluationTime: 0.05,
            .memoryUsage: 25.0,
            .eventProcessingLatency: 0.02
        ],
        alertThresholds: [
            .averageRuleEvaluationTime: 0.1,
            .memoryUsage: 50.0,
            .eventProcessingLatency: 0.05
        ]
    )
    
    static let production = PerformanceConfiguration(
        isEnabled: true,
        metricsUpdateInterval: 10.0,
        enableCPUMonitoring: false,
        enableMemoryMonitoring: true,
        maxStoredSamples: 200,
        performanceThresholds: [
            .averageRuleEvaluationTime: 0.2,
            .memoryUsage: 100.0,
            .eventProcessingLatency: 0.1
        ],
        alertThresholds: [
            .averageRuleEvaluationTime: 0.5,
            .memoryUsage: 150.0,
            .eventProcessingLatency: 0.2
        ]
    )
    
    static let testing = PerformanceConfiguration(
        isEnabled: false,
        metricsUpdateInterval: 0.1,
        enableCPUMonitoring: false,
        enableMemoryMonitoring: false,
        maxStoredSamples: 10,
        performanceThresholds: [:],
        alertThresholds: [:]
    )
}

// MARK: - Event Processing Configuration

struct EventProcessingConfiguration {
    let queueSize: Int
    let processingInterval: TimeInterval
    let enableDeduplication: Bool
    let enableBatching: Bool
    let maxBatchSize: Int
    let priorityProcessing: Bool
    let enableEventFiltering: Bool
    
    static let `default` = EventProcessingConfiguration(
        queueSize: 100,
        processingInterval: 0.5,
        enableDeduplication: true,
        enableBatching: true,
        maxBatchSize: 10,
        priorityProcessing: true,
        enableEventFiltering: false
    )
    
    static let development = EventProcessingConfiguration(
        queueSize: 50,
        processingInterval: 0.1,
        enableDeduplication: true,
        enableBatching: true,
        maxBatchSize: 5,
        priorityProcessing: true,
        enableEventFiltering: true
    )
    
    static let production = EventProcessingConfiguration(
        queueSize: 200,
        processingInterval: 1.0,
        enableDeduplication: true,
        enableBatching: true,
        maxBatchSize: 20,
        priorityProcessing: true,
        enableEventFiltering: false
    )
    
    static let testing = EventProcessingConfiguration(
        queueSize: 10,
        processingInterval: 0.01,
        enableDeduplication: false,
        enableBatching: false,
        maxBatchSize: 1,
        priorityProcessing: false,
        enableEventFiltering: false
    )
}

// MARK: - Beacon Configuration

struct BeaconConfiguration {
    let useRSSI: Bool
    let useRegionMonitoring: Bool
    let signalProcessingEnabled: Bool
    let proximityThreshold: Int
    let lostBeaconTimeout: TimeInterval
    let rssiSmoothingFactor: Double
    let minimumRSSI: Int
    let maximumRSSI: Int
    let scanInterval: TimeInterval
    
    static let `default` = BeaconConfiguration(
        useRSSI: true,
        useRegionMonitoring: true,
        signalProcessingEnabled: true,
        proximityThreshold: -70,
        lostBeaconTimeout: 3.0,
        rssiSmoothingFactor: 0.3,
        minimumRSSI: -100,
        maximumRSSI: -20,
        scanInterval: 1.0
    )
    
    static let development = BeaconConfiguration(
        useRSSI: true,
        useRegionMonitoring: true,
        signalProcessingEnabled: true,
        proximityThreshold: -60,
        lostBeaconTimeout: 1.0,
        rssiSmoothingFactor: 0.5,
        minimumRSSI: -90,
        maximumRSSI: -20,
        scanInterval: 0.5
    )
    
    static let production = BeaconConfiguration(
        useRSSI: true,
        useRegionMonitoring: true,
        signalProcessingEnabled: true,
        proximityThreshold: -75,
        lostBeaconTimeout: 5.0,
        rssiSmoothingFactor: 0.2,
        minimumRSSI: -100,
        maximumRSSI: -20,
        scanInterval: 2.0
    )
    
    static let testing = BeaconConfiguration(
        useRSSI: false,
        useRegionMonitoring: false,
        signalProcessingEnabled: false,
        proximityThreshold: -50,
        lostBeaconTimeout: 0.1,
        rssiSmoothingFactor: 1.0,
        minimumRSSI: -100,
        maximumRSSI: -20,
        scanInterval: 0.1
    )
}

// MARK: - Location Configuration

struct LocationConfiguration {
    let desiredAccuracy: CLLocationAccuracy
    let distanceFilter: Double
    let updateInterval: TimeInterval
    let significantLocationChanges: Bool
    let backgroundLocationUpdates: Bool
    let locationUpdateThreshold: Double
    let timeoutInterval: TimeInterval
    
    static let `default` = LocationConfiguration(
        desiredAccuracy: kCLLocationAccuracyNearestTenMeters,
        distanceFilter: 10.0,
        updateInterval: 5.0,
        significantLocationChanges: true,
        backgroundLocationUpdates: false,
        locationUpdateThreshold: 10.0,
        timeoutInterval: 30.0
    )
    
    static let development = LocationConfiguration(
        desiredAccuracy: kCLLocationAccuracyBest,
        distanceFilter: 1.0,
        updateInterval: 1.0,
        significantLocationChanges: false,
        backgroundLocationUpdates: false,
        locationUpdateThreshold: 1.0,
        timeoutInterval: 10.0
    )
    
    static let production = LocationConfiguration(
        desiredAccuracy: kCLLocationAccuracyHundredMeters,
        distanceFilter: 50.0,
        updateInterval: 10.0,
        significantLocationChanges: true,
        backgroundLocationUpdates: true,
        locationUpdateThreshold: 50.0,
        timeoutInterval: 60.0
    )
    
    static let testing = LocationConfiguration(
        desiredAccuracy: kCLLocationAccuracyKilometer,
        distanceFilter: 0.0,
        updateInterval: 0.1,
        significantLocationChanges: false,
        backgroundLocationUpdates: false,
        locationUpdateThreshold: 0.0,
        timeoutInterval: 1.0
    )
}

// MARK: - Rule Evaluation Configuration

struct RuleEvaluationConfiguration {
    let evaluationInterval: TimeInterval
    let enableCaching: Bool
    let cacheTimeout: TimeInterval
    let maxCachedRules: Int
    let enableParallelEvaluation: Bool
    let evaluationTimeout: TimeInterval
    let enableOptimization: Bool
    
    static let `default` = RuleEvaluationConfiguration(
        evaluationInterval: 1.0,
        enableCaching: true,
        cacheTimeout: 30.0,
        maxCachedRules: 100,
        enableParallelEvaluation: true,
        evaluationTimeout: 5.0,
        enableOptimization: true
    )
    
    static let development = RuleEvaluationConfiguration(
        evaluationInterval: 0.5,
        enableCaching: false,
        cacheTimeout: 5.0,
        maxCachedRules: 10,
        enableParallelEvaluation: false,
        evaluationTimeout: 1.0,
        enableOptimization: false
    )
    
    static let production = RuleEvaluationConfiguration(
        evaluationInterval: 2.0,
        enableCaching: true,
        cacheTimeout: 60.0,
        maxCachedRules: 500,
        enableParallelEvaluation: true,
        evaluationTimeout: 10.0,
        enableOptimization: true
    )
    
    static let testing = RuleEvaluationConfiguration(
        evaluationInterval: 0.1,
        enableCaching: false,
        cacheTimeout: 1.0,
        maxCachedRules: 5,
        enableParallelEvaluation: false,
        evaluationTimeout: 0.5,
        enableOptimization: false
    )
}

// MARK: - Logging Configuration

struct LoggingConfiguration {
    let enableFileLogging: Bool
    let enableOSLogging: Bool
    let enableDetailedLogging: Bool
    let enableDebugLogging: Bool
    let logLevel: LogLevel
    let maxLogFileSize: Int
    let maxLogFiles: Int
    let enablePerformanceLogging: Bool
    
    enum LogLevel: String, CaseIterable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
        case critical = "critical"
    }
    
    static let `default` = LoggingConfiguration(
        enableFileLogging: true,
        enableOSLogging: true,
        enableDetailedLogging: false,
        enableDebugLogging: false,
        logLevel: .debug,
        maxLogFileSize: 10 * 1024 * 1024, // 10MB
        maxLogFiles: 5,
        enablePerformanceLogging: false
    )
    
    static let development = LoggingConfiguration(
        enableFileLogging: true,
        enableOSLogging: true,
        enableDetailedLogging: true,
        enableDebugLogging: true,
        logLevel: .debug,
        maxLogFileSize: 5 * 1024 * 1024, // 5MB
        maxLogFiles: 3,
        enablePerformanceLogging: true
    )
    
    static let production = LoggingConfiguration(
        enableFileLogging: true,
        enableOSLogging: false,
        enableDetailedLogging: false,
        enableDebugLogging: false,
        logLevel: .warning,
        maxLogFileSize: 50 * 1024 * 1024, // 50MB
        maxLogFiles: 10,
        enablePerformanceLogging: false
    )
    
    static let testing = LoggingConfiguration(
        enableFileLogging: false,
        enableOSLogging: false,
        enableDetailedLogging: false,
        enableDebugLogging: false,
        logLevel: .error,
        maxLogFileSize: 1024 * 1024, // 1MB
        maxLogFiles: 1,
        enablePerformanceLogging: false
    )
}

// MARK: - Configuration Extensions

extension BlockingEngineConfiguration {
    
    /// Create a custom configuration by merging with defaults
    static func custom(
        isEnabled: Bool? = nil,
        performanceConfiguration: PerformanceConfiguration? = nil,
        eventProcessingConfiguration: EventProcessingConfiguration? = nil,
        beaconConfiguration: BeaconConfiguration? = nil,
        locationConfiguration: LocationConfiguration? = nil,
        ruleEvaluationConfiguration: RuleEvaluationConfiguration? = nil,
        loggingConfiguration: LoggingConfiguration? = nil
    ) -> BlockingEngineConfiguration {
        return BlockingEngineConfiguration(
            isEnabled: isEnabled ?? `default`.isEnabled,
            performanceConfiguration: performanceConfiguration ?? `default`.performanceConfiguration,
            eventProcessingConfiguration: eventProcessingConfiguration ?? `default`.eventProcessingConfiguration,
            beaconConfiguration: beaconConfiguration ?? `default`.beaconConfiguration,
            locationConfiguration: locationConfiguration ?? `default`.locationConfiguration,
            ruleEvaluationConfiguration: ruleEvaluationConfiguration ?? `default`.ruleEvaluationConfiguration,
            loggingConfiguration: loggingConfiguration ?? `default`.loggingConfiguration
        )
    }
    
    /// Validate configuration settings
    func validate() throws {
        // Validate performance configuration
        if performanceConfiguration.metricsUpdateInterval <= 0 {
            throw ConfigurationError.invalidMetricsUpdateInterval
        }
        
        // Validate event processing configuration
        if eventProcessingConfiguration.queueSize <= 0 {
            throw ConfigurationError.invalidQueueSize
        }
        
        if eventProcessingConfiguration.processingInterval <= 0 {
            throw ConfigurationError.invalidProcessingInterval
        }
        
        // Validate beacon configuration
        if beaconConfiguration.lostBeaconTimeout <= 0 {
            throw ConfigurationError.invalidLostBeaconTimeout
        }
        
        if beaconConfiguration.proximityThreshold >= 0 {
            throw ConfigurationError.invalidProximityThreshold
        }
        
        // Validate location configuration
        if locationConfiguration.updateInterval <= 0 {
            throw ConfigurationError.invalidUpdateInterval
        }
        
        // Validate rule evaluation configuration
        if ruleEvaluationConfiguration.evaluationInterval <= 0 {
            throw ConfigurationError.invalidEvaluationInterval
        }
    }
}

// MARK: - Configuration Errors

enum ConfigurationError: Error, LocalizedError {
    case invalidMetricsUpdateInterval
    case invalidQueueSize
    case invalidProcessingInterval
    case invalidLostBeaconTimeout
    case invalidProximityThreshold
    case invalidUpdateInterval
    case invalidEvaluationInterval
    
    var errorDescription: String? {
        switch self {
        case .invalidMetricsUpdateInterval:
            return "Metrics update interval must be greater than 0"
        case .invalidQueueSize:
            return "Queue size must be greater than 0"
        case .invalidProcessingInterval:
            return "Processing interval must be greater than 0"
        case .invalidLostBeaconTimeout:
            return "Lost beacon timeout must be greater than 0"
        case .invalidProximityThreshold:
            return "Proximity threshold must be negative (RSSI value)"
        case .invalidUpdateInterval:
            return "Update interval must be greater than 0"
        case .invalidEvaluationInterval:
            return "Evaluation interval must be greater than 0"
        }
    }
}

// MARK: - Configuration Utilities

extension BlockingEngineConfiguration {
    
    /// Export configuration to JSON
    func exportToJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        
        let configData: [String: Any] = [
            "isEnabled": isEnabled,
            "performance": [
                "isEnabled": performanceConfiguration.isEnabled,
                "metricsUpdateInterval": performanceConfiguration.metricsUpdateInterval,
                "enableCPUMonitoring": performanceConfiguration.enableCPUMonitoring,
                "enableMemoryMonitoring": performanceConfiguration.enableMemoryMonitoring,
                "maxStoredSamples": performanceConfiguration.maxStoredSamples
            ],
            "eventProcessing": [
                "queueSize": eventProcessingConfiguration.queueSize,
                "processingInterval": eventProcessingConfiguration.processingInterval,
                "enableDeduplication": eventProcessingConfiguration.enableDeduplication,
                "enableBatching": eventProcessingConfiguration.enableBatching,
                "maxBatchSize": eventProcessingConfiguration.maxBatchSize
            ],
            "beacon": [
                "useRSSI": beaconConfiguration.useRSSI,
                "useRegionMonitoring": beaconConfiguration.useRegionMonitoring,
                "signalProcessingEnabled": beaconConfiguration.signalProcessingEnabled,
                "proximityThreshold": beaconConfiguration.proximityThreshold,
                "lostBeaconTimeout": beaconConfiguration.lostBeaconTimeout
            ],
            "location": [
                "desiredAccuracy": locationConfiguration.desiredAccuracy,
                "distanceFilter": locationConfiguration.distanceFilter,
                "updateInterval": locationConfiguration.updateInterval,
                "significantLocationChanges": locationConfiguration.significantLocationChanges,
                "backgroundLocationUpdates": locationConfiguration.backgroundLocationUpdates
            ],
            "ruleEvaluation": [
                "evaluationInterval": ruleEvaluationConfiguration.evaluationInterval,
                "enableCaching": ruleEvaluationConfiguration.enableCaching,
                "cacheTimeout": ruleEvaluationConfiguration.cacheTimeout,
                "maxCachedRules": ruleEvaluationConfiguration.maxCachedRules,
                "enableParallelEvaluation": ruleEvaluationConfiguration.enableParallelEvaluation
            ],
            "logging": [
                "enableFileLogging": loggingConfiguration.enableFileLogging,
                "enableOSLogging": loggingConfiguration.enableOSLogging,
                "enableDetailedLogging": loggingConfiguration.enableDetailedLogging,
                "enableDebugLogging": loggingConfiguration.enableDebugLogging,
                "logLevel": loggingConfiguration.logLevel.rawValue,
                "maxLogFileSize": loggingConfiguration.maxLogFileSize,
                "maxLogFiles": loggingConfiguration.maxLogFiles
            ]
        ]
        
        return try? JSONSerialization.data(withJSONObject: configData, options: .prettyPrinted)
    }
    
    /// Get configuration summary
    func summary() -> String {
        return """
        Blocking Engine Configuration Summary:
        - Engine Enabled: \(isEnabled)
        - Performance Monitoring: \(performanceConfiguration.isEnabled)
        - Event Queue Size: \(eventProcessingConfiguration.queueSize)
        - Beacon RSSI Enabled: \(beaconConfiguration.useRSSI)
        - Region Monitoring: \(beaconConfiguration.useRegionMonitoring)
        - Location Accuracy: \(locationConfiguration.desiredAccuracy)
        - Rule Evaluation Interval: \(ruleEvaluationConfiguration.evaluationInterval)s
        - Log Level: \(loggingConfiguration.logLevel.rawValue)
        """
    }
}

//
//  PerformanceMonitor.swift
//  Limmi
//
//  Created by Claude Code on 09.07.2025.
//

import Foundation
import os
import Combine

/// Performance monitoring for the blocking engine
/// Tracks operations, counters, and system metrics
final class PerformanceMonitor {
    
    // MARK: - Types
    
    /// Operations that can be monitored
    enum Operation: String, CaseIterable {
        case engineStart = "engine_start"
        case engineStop = "engine_stop"
        case ruleEvaluation = "rule_evaluation"
        case beaconProcessing = "beacon_processing"
        case locationUpdate = "location_update"
        case eventProcessing = "event_processing"
        case blockingDecision = "blocking_decision"
    }
    
    /// Counters that can be tracked
    enum Counter: String, CaseIterable {
        case ruleEvaluations = "rule_evaluations"
        case beaconEvents = "beacon_events"
        case locationUpdates = "location_updates"
        case blockingStateChanges = "blocking_state_changes"
        case ruleChanges = "rule_changes"
        case errorsEncountered = "errors_encountered"
        case performanceWarnings = "performance_warnings"
    }
    
    /// Metrics that can be measured
    enum Metric: String, CaseIterable {
        case averageRuleEvaluationTime = "avg_rule_eval_time"
        case memoryUsage = "memory_usage"
        case cpuUsage = "cpu_usage"
        case eventProcessingLatency = "event_processing_latency"
        case beaconDetectionRate = "beacon_detection_rate"
        case locationUpdateRate = "location_update_rate"
    }
    
    // MARK: - Properties
    
    private let isEnabled: Bool
    private var operationStartTimes: [Operation: Date] = [:]
    private var counters: [Counter: Int] = [:]
    private var metrics: [Metric: Double] = [:]
    private var operationTimes: [Operation: [TimeInterval]] = [:]
    
    private let metricsSubject = PassthroughSubject<PerformanceMetrics, Never>()
    private let alertSubject = PassthroughSubject<PerformanceAlert, Never>()
    
    private let queue = DispatchQueue(label: "com.limmi.performance-monitor", qos: .utility)
    private var metricsTimer: Timer?
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "PerformanceMonitor")
    )
    
    // MARK: - Configuration
    
    struct Configuration {
        let metricsUpdateInterval: TimeInterval
        let enableCPUMonitoring: Bool
        let enableMemoryMonitoring: Bool
        let performanceThresholds: [Metric: Double]
        let maxStoredSamples: Int
        
        static let `default` = Configuration(
            metricsUpdateInterval: 5.0,
            enableCPUMonitoring: true,
            enableMemoryMonitoring: true,
            performanceThresholds: [
                .averageRuleEvaluationTime: 0.1,
                .memoryUsage: 50.0,
                .eventProcessingLatency: 0.05
            ],
            maxStoredSamples: 100
        )
    }
    
    private let configuration: Configuration
    
    // MARK: - Publishers
    
    var metricsPublisher: AnyPublisher<PerformanceMetrics, Never> {
        metricsSubject.eraseToAnyPublisher()
    }
    
    var alertPublisher: AnyPublisher<PerformanceAlert, Never> {
        alertSubject.eraseToAnyPublisher()
    }
    
    // MARK: - Initialization
    
    init(enabled: Bool = true, configuration: Configuration = .default) {
        self.isEnabled = enabled
        self.configuration = configuration
        
        if enabled {
            startMetricsTimer()
            initializeCounters()
        }
    }
    
    deinit {
        metricsTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Start timing an operation
    func startOperation(_ operation: Operation) {
        guard isEnabled else { return }
        
        queue.async { [weak self] in
            self?.operationStartTimes[operation] = Date()
        }
    }
    
    /// End timing an operation
    func endOperation(_ operation: Operation) {
        guard isEnabled else { return }
        
        queue.async { [weak self] in
            guard let self = self,
                  let startTime = self.operationStartTimes[operation] else { return }
            
            let duration = Date().timeIntervalSince(startTime)
            self.operationStartTimes.removeValue(forKey: operation)
            
            // Store operation time
            if self.operationTimes[operation] == nil {
                self.operationTimes[operation] = []
            }
            self.operationTimes[operation]?.append(duration)
            
            // Keep only recent samples
            if let times = self.operationTimes[operation],
               times.count > self.configuration.maxStoredSamples {
                self.operationTimes[operation] = Array(times.suffix(self.configuration.maxStoredSamples))
            }
            
            // Update metrics
            self.updateOperationMetrics(operation)
            
            // Check thresholds
            self.checkPerformanceThresholds(operation, duration: duration)
            
            self.logger.debug("Operation \(operation.rawValue) completed in \(duration)s")
        }
    }
    
    /// Increment a counter
    func incrementCounter(_ counter: Counter) {
        guard isEnabled else { return }
        
        queue.async { [weak self] in
            self?.counters[counter, default: 0] += 1
        }
    }
    
    /// Set a metric value
    func setMetric(_ metric: Metric, value: Double) {
        guard isEnabled else { return }
        
        queue.async { [weak self] in
            self?.metrics[metric] = value
        }
    }
    
    /// Get current performance metrics
    func getCurrentMetrics() -> PerformanceMetrics {
        guard isEnabled else { return PerformanceMetrics() }
        
        return queue.sync {
            return PerformanceMetrics(
                operationTimes: operationTimes,
                counters: counters,
                metrics: metrics,
                timestamp: Date()
            )
        }
    }
    
    /// Reset all performance data
    func reset() {
        guard isEnabled else { return }
        
        queue.async { [weak self] in
            self?.operationStartTimes.removeAll()
            self?.counters.removeAll()
            self?.metrics.removeAll()
            self?.operationTimes.removeAll()
            self?.initializeCounters()
        }
    }
    
    // MARK: - Private Methods
    
    private func initializeCounters() {
        for counter in Counter.allCases {
            counters[counter] = 0
        }
    }
    
    private func startMetricsTimer() {
        metricsTimer = Timer.scheduledTimer(withTimeInterval: configuration.metricsUpdateInterval, repeats: true) { [weak self] _ in
            self?.updateSystemMetrics()
            self?.publishMetrics()
        }
    }
    
    private func updateSystemMetrics() {
        if configuration.enableMemoryMonitoring {
            setMetric(.memoryUsage, value: getMemoryUsage())
        }
        
        if configuration.enableCPUMonitoring {
            setMetric(.cpuUsage, value: getCPUUsage())
        }
    }
    
    private func updateOperationMetrics(_ operation: Operation) {
        guard let times = operationTimes[operation], !times.isEmpty else { return }
        
        let averageTime = times.reduce(0, +) / Double(times.count)
        
        switch operation {
        case .ruleEvaluation:
            metrics[.averageRuleEvaluationTime] = averageTime
        case .eventProcessing:
            metrics[.eventProcessingLatency] = averageTime
        default:
            break
        }
    }
    
    private func checkPerformanceThresholds(_ operation: Operation, duration: TimeInterval) {
        for (metric, threshold) in configuration.performanceThresholds {
            guard let currentValue = metrics[metric] else { continue }
            
            if currentValue > threshold {
                let alert = PerformanceAlert(
                    metric: metric,
                    threshold: threshold,
                    actualValue: currentValue,
                    timestamp: Date()
                )
                
                alertSubject.send(alert)
                incrementCounter(.performanceWarnings)
                
                logger.debug("Performance threshold exceeded: \(metric.rawValue) = \(currentValue) > \(threshold)")
            }
        }
    }
    
    private func publishMetrics() {
        let metrics = getCurrentMetrics()
        metricsSubject.send(metrics)
    }
    
    private func getMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.resident_size) / 1024 / 1024 // MB
        }
        
        return 0.0
    }
    
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.policy) // This is a simplified approximation
        }
        
        return 0.0
    }
}

// MARK: - Supporting Types

/// Performance metrics snapshot
struct PerformanceMetrics {
    let operationTimes: [PerformanceMonitor.Operation: [TimeInterval]]
    let counters: [PerformanceMonitor.Counter: Int]
    let metrics: [PerformanceMonitor.Metric: Double]
    let timestamp: Date
    
    init(
        operationTimes: [PerformanceMonitor.Operation: [TimeInterval]] = [:],
        counters: [PerformanceMonitor.Counter: Int] = [:],
        metrics: [PerformanceMonitor.Metric: Double] = [:],
        timestamp: Date = Date()
    ) {
        self.operationTimes = operationTimes
        self.counters = counters
        self.metrics = metrics
        self.timestamp = timestamp
    }
    
    /// Get average time for an operation
    func averageTime(for operation: PerformanceMonitor.Operation) -> TimeInterval? {
        guard let times = operationTimes[operation], !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }
    
    /// Get counter value
    func count(for counter: PerformanceMonitor.Counter) -> Int {
        return counters[counter] ?? 0
    }
    
    /// Get metric value
    func value(for metric: PerformanceMonitor.Metric) -> Double? {
        return metrics[metric]
    }
}

/// Performance alert
struct PerformanceAlert {
    let metric: PerformanceMonitor.Metric
    let threshold: Double
    let actualValue: Double
    let timestamp: Date
    
    var severity: Severity {
        let ratio = actualValue / threshold
        switch ratio {
        case 0..<1.2:
            return .info
        case 1.2..<2.0:
            return .warning
        default:
            return .critical
        }
    }
    
    enum Severity {
        case info
        case debug
        case warning
        case critical
    }
}

// MARK: - Extensions

extension PerformanceMonitor {
    
    /// Get performance summary
    func getPerformanceSummary() -> String {
        let metrics = getCurrentMetrics()
        
        var summary = "Performance Summary:\n"
        
        // Operation times
        for (operation, times) in metrics.operationTimes {
            if !times.isEmpty {
                let avgTime = times.reduce(0, +) / Double(times.count)
                summary += "  \(operation.rawValue): \(String(format: "%.3f", avgTime))s avg\n"
            }
        }
        
        // Counters
        for (counter, count) in metrics.counters {
            summary += "  \(counter.rawValue): \(count)\n"
        }
        
        // Metrics
        for (metric, value) in metrics.metrics {
            summary += "  \(metric.rawValue): \(String(format: "%.2f", value))\n"
        }
        
        return summary
    }
    
    /// Export metrics to JSON
    func exportMetrics() -> Data? {
        let metrics = getCurrentMetrics()
        
        let exportData: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: metrics.timestamp),
            "counters": metrics.counters.mapKeys { $0.rawValue },
            "metrics": metrics.metrics.mapKeys { $0.rawValue },
            "operation_averages": metrics.operationTimes.compactMapValues { times in
                times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
            }.mapKeys { $0.rawValue }
        ]
        
        do {
            return try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
        } catch {
            return nil
        }
    }
}

// MARK: - Helper Extensions

extension Dictionary {
    func mapKeys<T>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        return try Dictionary<T, Value>(uniqueKeysWithValues: map { (try transform($0.key), $0.value) })
    }
}

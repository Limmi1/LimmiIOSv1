//
//  AppDelegate.swift
//  Limmi
//
//  Purpose: UIKit app delegate for Firebase configuration and lifecycle monitoring
//  Dependencies: Firebase Core, UnifiedLogger
//  Related: LimmiApp.swift, FileLogger.swift
//

import SwiftUI
import FirebaseCore
import FirebaseAnalytics
import os
import Foundation
import UIKit
import Darwin.Mach

/// App delegate responsible for Firebase initialization and system event monitoring.
///
/// This class handles critical app lifecycle events and system notifications that are
/// essential for beacon monitoring and app blocking functionality. It provides centralized
/// logging for debugging background behavior and performance monitoring.
///
/// ## Key Responsibilities
/// - Firebase SDK initialization and configuration
/// - App lifecycle event logging for debugging
/// - Memory and thermal state monitoring
/// - Background execution time tracking
///
/// ## Background Behavior
/// The logging here is crucial for understanding app behavior when the debugger
/// is not attached, particularly for CoreLocation ranging limitations.
///
/// - Important: Must remain as NSObject subclass for UIKit integration
/// - Note: Observers are properly cleaned up in deinit to prevent memory leaks
class AppDelegate: NSObject, UIApplicationDelegate {
    // MARK: - Properties
    
    private let appLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "AppDelegate")
    )
    
    private var observers: [NSObjectProtocol] = []
    
    // MARK: - Launch Tracking
    
    private static let processStartTime = Date()
    private var lastActiveTime: Date?
    private var backgroundStartTime: Date?
    private var foregroundTransitionCount = 0
    private var launchType: LaunchType = .unknown
    
    /// Tracks whether app launch is cold (first launch) or warm (return from background)
    private enum LaunchType {
        case cold       // First launch after process start
        case warm       // Return from background
        case unknown    // Unable to determine
    }
    
    // MARK: - UIApplicationDelegate
    
    /// Configures Firebase and sets up system monitoring on app launch.
    /// 
    /// - Parameters:
    ///   - application: The app instance
    ///   - launchOptions: Launch configuration options
    /// - Returns: True if initialization succeeded, false otherwise
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let launchStartTime = Date()
        
        // Clear termination flag to indicate normal app launch
        AppTerminationFlagManager.shared.clearTerminationFlag()
        
        // Determine launch type
        launchType = foregroundTransitionCount == 0 ? .cold : .warm
        
        do {
            FirebaseApp.configure()
            
            #if DEBUG
            // Enable debug mode for Firebase Analytics
            Analytics.setAnalyticsCollectionEnabled(true)
            
            // Set debug flag that Firebase is looking for
            UserDefaults.standard.set(true, forKey: "FIRDebugEnabled")
            UserDefaults.standard.set(true, forKey: "FIRAnalyticsDebugEnabled")
            
            AnalyticsManager.shared.enableDebugMode()
            print("🔥 Firebase Debug Arguments Set")
            print("📱 Device should appear in DebugView within 60 seconds")
            #endif
            
            Analytics.logEvent(AnalyticsEventAppOpen, parameters: nil)
            registerLoggingObservers()
            
            let launchDuration = Date().timeIntervalSince(launchStartTime)
            let totalLaunchTime = Date().timeIntervalSince(Self.processStartTime)
            
            logAppLaunch(
                launchType: launchType,
                launchDuration: launchDuration,
                totalLaunchTime: totalLaunchTime,
                launchOptions: launchOptions
            )
            
            return true
        } catch {
            appLogger.error("Failed to configure Firebase: \(error)")
            return false
        }
    }

    /// Logs transition to inactive state.
    /// Called when app is about to become inactive (e.g., phone call, notification center).
    func applicationWillResignActive(_ application: UIApplication) {
        appLogger.debug("applicationWillResignActive")
    }

    /// Logs background transition with remaining background execution time.
    /// Critical for understanding beacon monitoring limitations in background.
    func applicationDidEnterBackground(_ application: UIApplication) {
        backgroundStartTime = Date()
        let memoryUsage = getMemoryUsage()
        let activeDuration = lastActiveTime.map { Date().timeIntervalSince($0) } ?? 0
        
        appLogger.debug("""
        applicationDidEnterBackground:
        - Background time remaining: \(application.backgroundTimeRemaining == UIApplication.shared.backgroundTimeRemaining ? "unlimited" : "\(String(format: "%.1f", application.backgroundTimeRemaining))s")
        - Memory usage: \(memoryUsage)MB
        - Active duration: \(String(format: "%.1f", activeDuration))s
        - Transition count: \(foregroundTransitionCount)
        """)
    }

    /// Logs foreground transition.
    /// Useful for tracking when beacon ranging can resume full accuracy.
    func applicationWillEnterForeground(_ application: UIApplication) {
        foregroundTransitionCount += 1
        let backgroundDuration = backgroundStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let memoryUsage = getMemoryUsage()
        
        appLogger.debug("""
        applicationWillEnterForeground:
        - Background duration: \(String(format: "%.1f", backgroundDuration))s
        - Memory usage: \(memoryUsage)MB
        - Transition count: \(foregroundTransitionCount)
        """)
    }

    /// Logs active state transition.
    /// Indicates when app is fully interactive and all services are available.
    func applicationDidBecomeActive(_ application: UIApplication) {
        lastActiveTime = Date()
        let memoryUsage = getMemoryUsage()
        
        appLogger.debug("""
        applicationDidBecomeActive:
        - Memory usage: \(memoryUsage)MB
        - Thermal state: \(ProcessInfo.processInfo.thermalState.rawValue)
        """)
    }

    /// Logs app termination and sets termination flag.
    /// Final lifecycle event before app process ends.
    func applicationWillTerminate(_ application: UIApplication) {
        let totalRuntime = Date().timeIntervalSince(Self.processStartTime)
        let memoryUsage = getMemoryUsage()
        
        // Set termination flag to indicate normal termination
        AppTerminationFlagManager.shared.setTerminationFlag()
        
        appLogger.debug("""
        applicationWillTerminate:
        - Total runtime: \(String(format: "%.1f", totalRuntime))s
        - Memory usage: \(memoryUsage)MB
        - Foreground transitions: \(foregroundTransitionCount)
        - Termination flag set: true
        """)
    }

    // MARK: - Private Methods
    
    /// Registers system notification observers for performance monitoring.
    /// 
    /// Sets up observers for memory warnings and thermal state changes to help
    /// diagnose performance issues that could affect beacon monitoring accuracy.
    private func registerLoggingObservers() {
        let nc = NotificationCenter.default

        let memoryObserver = nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                           object: nil, queue: .main) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        observers.append(memoryObserver)

        let thermalObserver = nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.handleThermalStateChange()
        }
        observers.append(thermalObserver)
    }
    
    deinit {
        // Clean up notification observers to prevent memory leaks
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Handles system memory warning notifications.
    /// Logs memory pressure events that could affect app performance.
    private func handleMemoryWarning() {
        appLogger.debug("Notification: didReceiveMemoryWarning")
    }

    /// Handles thermal state change notifications.
    /// Logs thermal throttling that could impact beacon monitoring performance.
    private func handleThermalStateChange() {
        let state = ProcessInfo.processInfo.thermalState
        appLogger.debug("Thermal state changed: \(state.rawValue)")
    }
    
    /// Logs detailed app launch information with performance metrics.
    private func logAppLaunch(
        launchType: LaunchType,
        launchDuration: TimeInterval,
        totalLaunchTime: TimeInterval,
        launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) {
        let memoryUsage = getMemoryUsage()
        let processInfo = ProcessInfo.processInfo
        let bundle = Bundle.main
        
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildNumber = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        
        let launchReason = launchOptions?.keys.map { $0.rawValue }.joined(separator: ", ") ?? "Normal launch"
        
        appLogger.debug("""
        App Launch (\(launchType)):
        - Launch duration: \(String(format: "%.3f", launchDuration))s
        - Total launch time: \(String(format: "%.3f", totalLaunchTime))s
        - App version: \(appVersion) (\(buildNumber))
        - Launch reason: \(launchReason)
        - Memory usage: \(memoryUsage)MB
        - Process ID: \(processInfo.processIdentifier)
        - OS version: \(processInfo.operatingSystemVersionString)
        - Device: \(UIDevice.current.model) (\(UIDevice.current.systemVersion))
        - Thermal state: \(processInfo.thermalState.rawValue)
        """)
    }
    
    /// Gets current memory usage in megabytes.
    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Int(info.resident_size) / 1024 / 1024
        } else {
            return 0
        }
    }
    
    /// Handles SwiftUI scene phase changes by mapping to UIKit lifecycle methods.
    /// 
    /// Bridges SwiftUI's scene phase system with UIKit's app delegate methods
    /// to ensure consistent lifecycle logging across both frameworks.
    /// 
    /// - Parameter phase: The new scene phase
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            applicationDidBecomeActive(UIApplication.shared)
        case .inactive:
            applicationWillResignActive(UIApplication.shared)
        case .background:
            applicationDidEnterBackground(UIApplication.shared)
        @unknown default:
            break
        }
    }
} 

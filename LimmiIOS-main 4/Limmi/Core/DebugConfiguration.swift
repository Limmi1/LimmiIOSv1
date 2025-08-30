//
//  DebugConfiguration.swift
//  Limmi
//
//  Purpose: Debug-only configuration flags for development and testing
//  Dependencies: Foundation
//  Related: BeaconMonitorTestHarness.swift, LimmiApp.swift
//

import Foundation

/// Debug configuration flags for development and testing.
///
/// This class provides compile-time debug flags that can be set to modify
/// app behavior during development. All flags are ignored in release builds.
///
/// ## Usage
/// Set flags in the app delegate or early in the app lifecycle:
/// ```swift
/// #if DEBUG
/// DebugConfiguration.shared.launchTestHarnessFirst = true
/// #endif
/// ```
///
/// ## Available Flags
/// - `launchTestHarnessFirst`: Launch beacon monitor test harness before main app
/// - `skipMainAppLaunch`: Prevent main app from launching automatically
/// - `enableVerboseLogging`: Enable detailed debug logging
///
/// - Since: 1.0
#if DEBUG
final class DebugConfiguration: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = DebugConfiguration()
    
    private init() {}
    
    // MARK: - Test Harness Flags
    
    /// Launch the beacon monitor test harness before the main app.
    /// When true, the app will show the test harness UI first and provide
    /// a button to launch the main app after testing is complete.
    @Published var launchTestHarnessFirst: Bool = false
    
    /// Skip automatic main app launch.
    /// When true, the main app will not initialize its core services
    /// automatically, allowing for isolated testing.
    @Published var skipMainAppLaunch: Bool = false
    
    /// Enable verbose debug logging.
    /// When true, all components will log detailed debug information.
    @Published var enableVerboseLogging: Bool = false
    
    // MARK: - Beacon Testing Flags
    
    /// Use test beacon UUIDs instead of production ones.
    /// When true, the app will use predefined test beacon identifiers.
    @Published var useTestBeacons: Bool = false
    
    /// Simulate beacon events for testing.
    /// When true, the app will generate fake beacon events for UI testing.
    @Published var simulateBeaconEvents: Bool = false
    
    // MARK: - Firebase Testing Flags
    
    /// Use Firebase emulator for testing.
    /// When true, the app will connect to local Firebase emulator.
    @Published var useFirebaseEmulator: Bool = false
    
    /// Skip Firebase authentication.
    /// When true, the app will bypass authentication for testing.
    @Published var skipFirebaseAuth: Bool = false
    
    // MARK: - Convenience Methods
    
    /// Reset all flags to their default values.
    func resetToDefaults() {
        launchTestHarnessFirst = false
        skipMainAppLaunch = false
        enableVerboseLogging = false
        useTestBeacons = false
        simulateBeaconEvents = false
        useFirebaseEmulator = false
        skipFirebaseAuth = false
    }
    
    /// Configure for isolated beacon testing.
    /// Sets flags to optimize for beacon monitor testing.
    func configureForBeaconTesting() {
        launchTestHarnessFirst = true
        skipMainAppLaunch = true
        enableVerboseLogging = true
        useTestBeacons = true
    }
    
    /// Configure for UI testing.
    /// Sets flags to optimize for UI and integration testing.
    func configureForUITesting() {
        skipFirebaseAuth = true
        simulateBeaconEvents = true
        enableVerboseLogging = true
    }
    
    // MARK: - Environment Variable Support
    
    /// Load configuration from environment variables.
    /// Allows setting debug flags via Xcode scheme environment variables.
    func loadFromEnvironment() {
        if let value = ProcessInfo.processInfo.environment["LIMMI_LAUNCH_TEST_HARNESS_FIRST"] {
            launchTestHarnessFirst = value.lowercased() == "true"
        }
        
        if let value = ProcessInfo.processInfo.environment["LIMMI_SKIP_MAIN_APP_LAUNCH"] {
            skipMainAppLaunch = value.lowercased() == "true"
        }
        
        if let value = ProcessInfo.processInfo.environment["LIMMI_VERBOSE_LOGGING"] {
            enableVerboseLogging = value.lowercased() == "true"
        }
        
        if let value = ProcessInfo.processInfo.environment["LIMMI_USE_TEST_BEACONS"] {
            useTestBeacons = value.lowercased() == "true"
        }
        
        if let value = ProcessInfo.processInfo.environment["LIMMI_SIMULATE_BEACON_EVENTS"] {
            simulateBeaconEvents = value.lowercased() == "true"
        }
        
        if let value = ProcessInfo.processInfo.environment["LIMMI_USE_FIREBASE_EMULATOR"] {
            useFirebaseEmulator = value.lowercased() == "true"
        }
        
        if let value = ProcessInfo.processInfo.environment["LIMMI_SKIP_FIREBASE_AUTH"] {
            skipFirebaseAuth = value.lowercased() == "true"
        }
    }
}

#else
// Release builds: Provide no-op implementation
final class DebugConfiguration: ObservableObject {
    static let shared = DebugConfiguration()
    private init() {}
    
    let launchTestHarnessFirst: Bool = false
    let skipMainAppLaunch: Bool = false
    let enableVerboseLogging: Bool = false
    let useTestBeacons: Bool = false
    let simulateBeaconEvents: Bool = false
    let useFirebaseEmulator: Bool = false
    let skipFirebaseAuth: Bool = false
    
    func resetToDefaults() {}
    func configureForBeaconTesting() {}
    func configureForUITesting() {}
    func loadFromEnvironment() {}
}
#endif

// MARK: - Convenience Extensions

extension DebugConfiguration {
    /// Quick check if any testing flags are enabled.
    var isTestingMode: Bool {
        launchTestHarnessFirst || skipMainAppLaunch || useTestBeacons || simulateBeaconEvents
    }
    
    /// Quick check if beacon testing is enabled.
    var isBeaconTestingMode: Bool {
        launchTestHarnessFirst || useTestBeacons || simulateBeaconEvents
    }
    
    /// Quick check if Firebase testing is enabled.
    var isFirebaseTestingMode: Bool {
        useFirebaseEmulator || skipFirebaseAuth
    }
}

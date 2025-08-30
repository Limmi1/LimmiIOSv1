//
//  LimmiApp.swift
//  Limmi
//
//  Purpose: Main app entry point and dependency injection container
//  Dependencies: SwiftUI, FamilyControls, Firebase, Core business logic
//  Related: AppDelegate.swift, AuthViewModel.swift, BlockingEngine.swift
//

import SwiftUI
import FamilyControls
import DeviceActivity
import ManagedSettings
import FirebaseAuth
import FirebaseFirestore
import os
import Darwin.Mach

/// Main application entry point that coordinates app lifecycle and dependency injection.
///
/// This struct handles the complete app initialization flow including Firebase data loading,
/// business object creation, and UI state management. It implements a progressive loading
/// pattern to ensure all data is available before presenting the main interface.
///
/// ## Architecture Notes
/// - Uses dependency injection for testability
/// - Implements async initialization to prevent blocking UI
/// - Separates authenticated and unauthenticated states
///
/// ## Performance
/// - Lazy loads blocking engine only after Firebase data is ready
/// - Background initialization prevents UI blocking during startup
///
/// - Since: 1.0
@main
struct LimmiApp: App {
    // MARK: - Properties
    
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var authViewModel = AuthViewModel()
    @StateObject var appSettings = AppSettings.shared
    
    // MARK: - Lifecycle Logging
    
    private let lifecycleLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "AppLifecycle")
    )
    
    private static let appLaunchTime = Date()
    
    // MARK: - Heartbeat Management
    
    private let heartbeatManager: HeartbeatManager?
    private let deviceActivityHeartbeatService = DeviceActivityHeartbeatService()
    
    // MARK: - Initialization
    
    init() {
        // Initialize heartbeat manager
        do {
            heartbeatManager = try HeartbeatManager()
        } catch {
            print("Failed to initialize HeartbeatManager: \(error)")
            heartbeatManager = nil
        }
        
        configureAppearance()
        logAppLaunch()
        
        // Clear DAM blocking flag on app startup
        DamBlockingFlagManager.clearFlag()
        lifecycleLogger.debug("Cleared DAM blocking flag on app startup")
        
        // Load debug configuration from environment variables
        #if DEBUG
        DebugConfiguration.shared.loadFromEnvironment()
        #endif
    }
    
    // MARK: - Scene Configuration
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authViewModel)
                .environmentObject(appSettings)
                .environmentObject(HeartbeatEnvironment(manager: heartbeatManager, deviceActivityService: deviceActivityHeartbeatService))
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            logScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    // MARK: - Private Methods
    
    /// Configures global app appearance settings.
    /// 
    /// Sets up tab bar styling with custom colors to match app design system.
    /// Called during app initialization to ensure consistent theming.
    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(AppColor.shared.darkNavyBlue)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
    
    /// Logs app launch information including performance metrics and device context.
    private func logAppLaunch() {
        let launchDuration = Date().timeIntervalSince(Self.appLaunchTime)
        let processInfo = ProcessInfo.processInfo
        let memoryUsage = getMemoryUsage()
        
        lifecycleLogger.debug("""
        App Launch Completed:
        - Launch duration: \(String(format: "%.3f", launchDuration))s
        - Process ID: \(processInfo.processIdentifier)
        - OS Version: \(processInfo.operatingSystemVersionString)
        - Device model: \(UIDevice.current.model)
        - Memory usage: \(memoryUsage)MB
        - Thermal state: \(processInfo.thermalState.rawValue)
        """)
    }
    
    /// Logs scene phase transitions with timing and context information.
    private func logScenePhaseChange(from oldPhase: ScenePhase?, to newPhase: ScenePhase) {
        let phaseDescription = { (phase: ScenePhase?) -> String in
            switch phase {
            case .active: return "active"
            case .inactive: return "inactive"
            case .background: return "background"
            case .none: return "none"
            @unknown default: return "unknown"
            }
        }
        
        let memoryUsage = getMemoryUsage()
        let backgroundTimeRemaining = UIApplication.shared.backgroundTimeRemaining
        
        lifecycleLogger.debug("""
        Scene Phase Change:
        - From: \(phaseDescription(oldPhase))
        - To: \(phaseDescription(newPhase))
        - Memory usage: \(memoryUsage)MB
        - Background time remaining: \(backgroundTimeRemaining == UIApplication.shared.backgroundTimeRemaining ? "unlimited" : "\(String(format: "%.1f", backgroundTimeRemaining))s")
        """)
        
        // Handle heartbeat lifecycle
        handleHeartbeatPhaseChange(newPhase)
        
        // Notify AppDelegate to maintain consistency
        delegate.handleScenePhaseChange(newPhase)
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
    
    /// Handles heartbeat manager phase changes based on scene state.
    private func handleHeartbeatPhaseChange(_ newPhase: ScenePhase) {
        guard let heartbeatManager = heartbeatManager else {
            lifecycleLogger.error("HeartbeatManager not available for phase change")
            return
        }
        
        switch newPhase {
        case .active:
            heartbeatManager.startForegroundHeartbeat()
            lifecycleLogger.debug("Started foreground heartbeat")
            
            // Clear DAM blocking flag when main app becomes active
            DamBlockingFlagManager.clearFlag()
            lifecycleLogger.debug("Cleared DAM blocking flag - main app is active")
        case .inactive, .background:
            heartbeatManager.stopForegroundHeartbeat()
            lifecycleLogger.debug("Stopped foreground heartbeat")
        @unknown default:
            break
        }
    }
}

/// Environment object for passing heartbeat manager through SwiftUI hierarchy.
class HeartbeatEnvironment: ObservableObject {
    let manager: HeartbeatProtocol?
    let deviceActivityService: DeviceActivityHeartbeatService
    
    init(manager: HeartbeatProtocol?, deviceActivityService: DeviceActivityHeartbeatService) {
        self.manager = manager
        self.deviceActivityService = deviceActivityService
    }
}

/// Add AppSession container class
@MainActor
class AppSession: ObservableObject {
    let ruleStore: FirebaseRuleStore
    let ruleStoreViewModel: RuleStoreViewModel
    let blockingEngine: BlockingEngine
    // Add other session-scoped objects as needed

    init(user: User, heartbeatEnvironment: HeartbeatEnvironment, appSettings: AppSettings) {
        self.ruleStore = FirebaseRuleStore(firestore: Firestore.firestore(), userId: user.uid)
        self.ruleStoreViewModel = RuleStoreViewModel(ruleStore: ruleStore)
        self.blockingEngine = BlockingEngine(
            locationProvider: RegionMonitoringLocationProvider(),
            beaconMonitor: AlwaysRangingBeaconMonitor(),
            clock: SystemClock(),
            ruleStore: ruleStore,
            blocker: ScreenTimeBlocker(),
            configuration: appSettings.blockingEngineConfiguration,
            heartbeatManager: heartbeatEnvironment.manager,
            deviceActivityService: heartbeatEnvironment.deviceActivityService,
            ruleProcessingStrategy: appSettings.currentStrategy
        )
    }
}

/// Root view that handles authentication state routing and debug testing.
///
/// Displays either the login interface, test harness, or main authenticated app
/// based on current authentication status and debug configuration. This separation
/// ensures clean state management and proper lifecycle handling.
struct RootView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appSettings: AppSettings
    @EnvironmentObject var heartbeatEnvironment: HeartbeatEnvironment
    #if DEBUG
    @ObservedObject private var debugConfig = DebugConfiguration.shared
    #endif

    @ViewBuilder
    var body: some View {
        #if DEBUG
        if debugConfig.launchTestHarnessFirst {
            TestHarnessRootView()
        } else if let user = authViewModel.user {
            AuthenticatedHomeView(user: user)
        } else {
            LoginView()
        }
        #else
        if let user = authViewModel.user {
            AuthenticatedHomeView(user: user)
        } else {
            LoginView()
        }
        #endif
    }
}

#if DEBUG
/// Debug-only root view that shows the test harness with option to launch main app.
struct TestHarnessRootView: View {
    @State private var showMainApp = false
    
    var body: some View {
        if showMainApp {
            RootView()
                .onAppear {
                    // Reset debug flag so we don't loop back to test harness
                    DebugConfiguration.shared.launchTestHarnessFirst = false
                }
        } else {
            BeaconMonitorTestHarnessView()
                .overlay(
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                showMainApp = true
                            }) {
                                HStack {
                                    Image(systemName: "app.badge.fill")
                                    Text("Launch Main App")
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .padding()
                        }
                    }
                )
        }
    }
}
#endif

/// Main authenticated app container with async service initialization.
///
/// This view manages the complex initialization sequence required for the blocking engine:
/// 1. Load Firebase data (rules, apps, beacons)
/// 2. Create business objects with loaded data
/// 3. Start blocking engine with full context
/// 4. Present main interface
///
/// ## Error Handling
/// - Displays loading states with progress indicators
/// - Shows detailed error messages with retry options
/// - Gracefully handles network failures and data inconsistencies
///
/// ## Performance Notes
/// - Uses async/await to prevent UI blocking during initialization
/// - Implements progressive loading to show status updates
/// - Lazy initialization ensures minimal memory usage before data is ready
struct AuthenticatedHomeView: View {
    // MARK: - Properties
    
    let user: User
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var heartbeatEnvironment: HeartbeatEnvironment
    @State var session: AppSession? = nil
    @State private var initializationError: Error?
    @State private var isInitializing = true
    @State private var screenTimeAuthStatus: AuthorizationStatus = .notDetermined
    
    // MARK: - Service Initialization Logging
    
    private let serviceLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "ServiceInit")
    )
    
    // MARK: - Initialization
    
    init(user: User) {
        self.user = user
    }
    
    var body: some View {
        Group {
            if let session = session {
                if isInitializing {
                    LoadingView(
                        isLoadingRules: session.ruleStore.isLoadingRules,
                        isLoadingApps: session.ruleStore.isLoadingTokens,
                        isLoadingBeacons: session.ruleStore.isLoadingBeacons,
                        screenTimeAuthStatus: screenTimeAuthStatus,
                        error: session.ruleStore.loadingError,
                        onRetry: {
                            session.ruleStore.retryLoading()
                        }
                    )
                } else if let error = initializationError {
                    ErrorView(
                        error: error,
                        onRetry: {
                            Task { await initializeServices() }
                        }
                    )
                } else {
                    HomePageView()
                        .environmentObject(session.ruleStoreViewModel)
                        .environmentObject(BlockingEngineViewModel(blockingEngine: session.blockingEngine))
                }
            } else {
                // Show loading while session is being created
                LoadingView(
                    isLoadingRules: true,
                    isLoadingApps: true,
                    isLoadingBeacons: true,
                    screenTimeAuthStatus: .notDetermined,
                    error: nil,
                    onRetry: {}
                )
            }
        }
        .onAppear {
            if session == nil {
                session = AppSession(user: user, heartbeatEnvironment: heartbeatEnvironment, appSettings: appSettings)
            }
        }
        .task {
            if session != nil {
                await initializeServices()
            }
        }
        .onReceive(appSettings.currentStrategyPublisher) { newStrategy in
            session?.blockingEngine.updateRuleProcessingStrategy(newStrategy)
        }
        .onDisappear() {
            serviceLogger.debug("I have been killed !")
        }
    }
    
    // MARK: - Private Methods
    
    /// Initializes all business services with proper dependency injection.
    ///
    /// This method implements the complete service initialization sequence:
    /// 1. Waits for Firebase data to fully load
    /// 2. Creates blocking engine with all dependencies
    /// 3. Initializes app blocker with engine reference
    /// 4. Starts blocking engine with loaded rule context
    ///
    /// - Important: Must be called on MainActor due to SwiftUI state updates
    /// - Note: Uses async/await to prevent blocking the main thread
    @MainActor
    private func initializeServices() async {
        let initStartTime = Date()
        isInitializing = true
        initializationError = nil
        
        serviceLogger.debug("Service initialization started for user: \(user.uid)")
        
        do {
            // Wait for Firebase data to load
            let firebaseLoadStart = Date()
            try await session?.ruleStore.waitForInitialDataLoad()
            let firebaseLoadDuration = Date().timeIntervalSince(firebaseLoadStart)
            serviceLogger.debug("Firebase data loaded in \(String(format: "%.3f", firebaseLoadDuration))s")
            
            // Request Screen Time authorization early in the initialization process
            let authStart = Date()
            let screenTimeBlocker = ScreenTimeBlocker()
            screenTimeAuthStatus = screenTimeBlocker.authorizationStatus
            screenTimeBlocker.requestAuthorization()
            // Wait a moment for async authorization to complete
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            screenTimeAuthStatus = screenTimeBlocker.authorizationStatus
            let authDuration = Date().timeIntervalSince(authStart)
            serviceLogger.debug("Screen Time authorization requested in \(String(format: "%.3f", authDuration))s, status: \(screenTimeBlocker.authorizationStatus)")
            
            // Create business objects with loaded data
            let objectCreationStart = Date()
            // let blockingEngineInstance = BlockingEngine(
            //     locationProvider: RegionMonitoringLocationProvider(),
            //     beaconMonitor: CoreLocationBeaconMonitor(),
            //     clock: SystemClock(),
            //     ruleStore: ruleStore,
            //     blocker: screenTimeBlocker,
            //     configuration: appSettings.blockingEngineConfiguration,
            //     heartbeatManager: heartbeatEnvironment.manager,
            //     deviceActivityService: heartbeatEnvironment.deviceActivityService,
            //     ruleProcessingStrategy: appSettings.currentStrategy
            // )
            
            // AppBlocker is no longer needed for UI - functionality moved to ViewModels
            let objectCreationDuration = Date().timeIntervalSince(objectCreationStart)
            serviceLogger.debug("Business objects created in \(String(format: "%.3f", objectCreationDuration))s")
            
            // Start BlockingEngine with loaded data
            let engineStartTime = Date()
            try await session?.blockingEngine.startWhenReady()
            let engineStartDuration = Date().timeIntervalSince(engineStartTime)
            serviceLogger.debug("BlockingEngine started in \(String(format: "%.3f", engineStartDuration))s")
            
            // Set initialized objects
            // blockingEngine = blockingEngineInstance
            isInitializing = false
            
            let totalDuration = Date().timeIntervalSince(initStartTime)
            serviceLogger.debug("Service initialization completed in \(String(format: "%.3f", totalDuration))s")
            
        } catch {
            let errorDuration = Date().timeIntervalSince(initStartTime)
            serviceLogger.error("Service initialization failed after \(String(format: "%.3f", errorDuration))s: \(error.localizedDescription)")
            initializationError = error
            isInitializing = false
        }
    }
}

// MARK: - Loading Views

struct LoadingView: View {
    let isLoadingRules: Bool
    let isLoadingApps: Bool
    let isLoadingBeacons: Bool
    let screenTimeAuthStatus: AuthorizationStatus
    let error: Error?
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.2.and.child.holdinghands")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Loading Limmi")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let error = error {
                    VStack(spacing: 8) {
                        Text("Failed to load data")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        
                        Button("Retry") {
                            onRetry()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 8) {
                        HStack {
                            if isLoadingRules {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading rules...")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Rules loaded")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack {
                            if isLoadingApps {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading blocked apps...")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Apps loaded")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack {
                            if isLoadingBeacons {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading beacon devices...")
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Beacons loaded")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack {
                            switch screenTimeAuthStatus {
                            case .notDetermined:
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Requesting Screen Time access...")
                            case .approved:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Screen Time authorized")
                            case .denied:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("Screen Time access denied")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

struct ErrorView: View {
    let error: Error?
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.red)
            
            VStack(spacing: 12) {
                Text("Initialization Failed")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let error = error {
                    Text(error.localizedDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                Button("Try Again") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

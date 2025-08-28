import SwiftUI
import FamilyControls
import os
import Combine
import FirebaseFirestore

struct HomePageView: View {
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    @EnvironmentObject var blockingEngineViewModel: BlockingEngineViewModel
    
    @State private var selectedTab: Int = 0
    @State private var logTapCount: Int = 0
    @State private var showLogSheet: Bool = false

    private let homeLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "HomePageView")
    )
    
    var body: some View {
        HomePageViewContent(
            selectedTab: $selectedTab,
            logTapCount: $logTapCount,
            showLogSheet: $showLogSheet
        )
        .environmentObject(ruleStoreViewModel)
        .environmentObject(blockingEngineViewModel)
        .trackScreen("HomePage", screenClass: "HomePageView")
        .onDisappear {
            blockingEngineViewModel.stop()
        }
    }
}

extension Notification.Name {
    static let didModifyRules = Notification.Name("didModifyRules")
}

struct HomePageViewContent: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    @EnvironmentObject var blockingEngineViewModel: BlockingEngineViewModel
    @Binding var selectedTab: Int
    @Binding var logTapCount: Int
    @Binding var showLogSheet: Bool
    @State private var showingBugReport = false
    @State private var showingRuleCreation = false
    
    // Explicit initializer for all properties
    init(
        selectedTab: Binding<Int>,
        logTapCount: Binding<Int>,
        showLogSheet: Binding<Bool>
    ) {
        self._selectedTab = selectedTab
        self._logTapCount = logTapCount
        self._showLogSheet = showLogSheet
    }
    
    private var appColor = AppColor.shared
    private let homeLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "HomePageViewContent")
    )
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Limmi")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            HStack(spacing: 12) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(blockingEngineViewModel.isActive ? .green : .gray)
                                        .frame(width: 6, height: 6)
                                    Text(blockingEngineViewModel.isActive ? "Protection Active" : "Protection Inactive")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Create Rule") {
                                    showingRuleCreation = true
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    
                    // Rules Content
                    ScrollView {
                        VStack(spacing: 16) {
                            if $ruleStoreViewModel.activeRules.isEmpty {
                                // Empty State - Only shown when data has actually loaded
                                VStack(spacing: 20) {
                                    Image(systemName: "shield.lefthalf.filled")
                                        .font(.system(size: 64))
                                        .foregroundColor(.blue.opacity(0.6))
                                    
                                    VStack(spacing: 8) {
                                        Text("No Rules Yet")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        
                                        Text("Create your first rule to start blocking apps based on location and time")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }
                                    
                                    // Create Rule Button moved to header
                                }
                                .padding(.horizontal, 32)
                                .padding(.vertical, 40)
                            } else {
                                // Rules List
                                LazyVStack(spacing: 12) {
                                    ForEach(ruleStoreViewModel.activeRules) { rule in
                                        RuleCard(rule: rule)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }
                        }
                        
                        Spacer(minLength: 20)
                    }
                }
                .background(Color(.systemGroupedBackground))
            }
            .tabItem {
                Image(systemName: "shield.lefthalf.filled")
                Text("Rules")
            }
            .tag(0)
            
            NavigationStack {
                ConfigurationView()
            }
            .tabItem {
                Image(systemName: "gearshape.fill")
                Text("Settings")
            }
            .tag(1)
        }
        .sheet(isPresented: $showingRuleCreation,
               onDismiss: { NotificationCenter.default.post(name: .didModifyRules, object: nil) }) {
            RuleCreationFlowView(authViewModel: authViewModel)
                .environmentObject(authViewModel)
                .environmentObject(ruleStoreViewModel)
        }
        .tint(appColor.buttonColor)
        .onAppear {
            // Customize tab bar appearance with better colors and spacing
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.systemBackground
            
            // Add subtle shadow/border
            appearance.shadowColor = UIColor.systemGray4
            
            // Selected tab styling - using buttonColor (dark blue)
            appearance.stackedLayoutAppearance.selected.iconColor = UIColor(appColor.buttonColor)
            appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                .foregroundColor: UIColor(appColor.buttonColor),
                .font: UIFont.systemFont(ofSize: 10, weight: .semibold)
            ]
            
            // Unselected tab styling - softer gray
            appearance.stackedLayoutAppearance.normal.iconColor = UIColor.systemGray2
            appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.systemGray2,
                .font: UIFont.systemFont(ofSize: 10, weight: .regular)
            ]
            
            // Improve spacing and padding
            appearance.stackedLayoutAppearance.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
            appearance.stackedLayoutAppearance.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            
            // Phase 3: Initialize BlockingEngine on app launch
            blockingEngineViewModel.refreshRules()
        }
        .onReceive(NotificationCenter.default.publisher(for: .didModifyRules)) { _ in
            // Phase 3: Refresh rule data via BlockingEngine
            blockingEngineViewModel.refreshRules()
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            // Track tab switching for analytics
            let tabName = newTab == 0 ? "RulesTab" : "SettingsTab"
            AnalyticsManager.shared.logScreenView(
                screenName: tabName,
                screenClass: "HomePageViewContent",
                additionalParameters: ["tab_index": newTab]
            )
        }
    }
}


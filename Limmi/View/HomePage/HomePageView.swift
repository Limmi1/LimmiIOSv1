import SwiftUI
import FamilyControls
import os
import Combine
import FirebaseFirestore

// MARK: - Rule Creation Mode
enum RuleCreationMode {
    case blocked
    case allowed
    
    var title: String {
        switch self {
        case .blocked:
            return "Create Blocked Space"
        case .allowed:
            return "Create Allowed Space"
        }
    }
    
    var isBlockingEnabled: Bool {
        switch self {
        case .blocked:
            return true
        case .allowed:
            return false
        }
    }
}

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
    @State private var ruleCreationMode: RuleCreationMode = .blocked
    
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
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Limmi")
                                    .font(DesignSystem.headingLarge)
                                    .fontWeight(.bold)
                                    .foregroundColor(DesignSystem.pureBlack)
                                
                                Text("Smart App Blocking")
                                    .font(DesignSystem.bodyTextSmall)
                                    .foregroundColor(DesignSystem.secondaryBlue)
                            }
                            
                            Spacer()
                            
                            // Status indicator
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(blockingEngineViewModel.isActive ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                
                                Text(blockingEngineViewModel.isActive ? "Active" : "Inactive")
                                    .font(DesignSystem.captionText)
                                    .foregroundColor(DesignSystem.secondaryBlue)
                            }
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                        .padding(.top, DesignSystem.spacingS)
                    }
                    
                    // New Spaces Section
                    VStack(spacing: DesignSystem.spacingL) {
                        // Section Header
                        HStack {
                            Text("New Spaces")
                                .font(DesignSystem.headingMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.pureBlack)
                            Spacer()
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                        
                        // New Space Buttons
                        HStack(spacing: DesignSystem.spacingM) {
                            // Create Blocked Space Button
                            Button(action: {
                                ruleCreationMode = .blocked
                                showingRuleCreation = true
                            }) {
                                VStack(spacing: DesignSystem.spacingS) {
                                    Image(systemName: "shield.lefthalf.filled")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                    
                                    Text("Create Blocked Space")
                                        .font(DesignSystem.bodyText)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .background(DesignSystem.mutedRed)
                                .cornerRadius(DesignSystem.cornerRadius)
                                .shadow(
                                    color: DesignSystem.cardShadow.color,
                                    radius: DesignSystem.cardShadow.radius,
                                    x: DesignSystem.cardShadow.x,
                                    y: DesignSystem.cardShadow.y
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            // Create Allowed Space Button
                            Button(action: {
                                ruleCreationMode = .allowed
                                showingRuleCreation = true
                            }) {
                                VStack(spacing: DesignSystem.spacingS) {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                    
                                    Text("Create Allowed Space")
                                        .font(DesignSystem.bodyText)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 120)
                                .background(DesignSystem.mutedGreen)
                                .cornerRadius(DesignSystem.cornerRadius)
                                .shadow(
                                    color: DesignSystem.cardShadow.color,
                                    radius: DesignSystem.cardShadow.radius,
                                    x: DesignSystem.cardShadow.x,
                                    y: DesignSystem.cardShadow.y
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                    }
                    .padding(.vertical, DesignSystem.spacingL)
                    .background(DesignSystem.pureWhite.opacity(0.5))
                    
                    // Existing Spaces Section
                    VStack(spacing: DesignSystem.spacingL) {
                        // Section Header
                        HStack {
                            Text("Existing Spaces")
                                .font(DesignSystem.headingMedium)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.pureBlack)
                            Spacer()
                        }
                        .padding(.horizontal, DesignSystem.spacingL)
                        
                        // Rules Content
                        ScrollView {
                            VStack(spacing: DesignSystem.spacingL) {
                                if $ruleStoreViewModel.activeRules.isEmpty {
                                    // Empty State - Only shown when data has actually loaded
                                    VStack(spacing: DesignSystem.spacingXL) {
                                        Image(systemName: "shield.lefthalf.filled")
                                            .font(.system(size: 64))
                                            .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                                        
                                        VStack(spacing: DesignSystem.spacingS) {
                                            Text("No Spaces Yet")
                                                .font(DesignSystem.headingMedium)
                                                .fontWeight(.semibold)
                                                .foregroundColor(DesignSystem.pureBlack)
                                            
                                            Text("Create your first space to start managing apps based on location and time")
                                                .font(DesignSystem.bodyText)
                                                .foregroundColor(DesignSystem.secondaryBlue)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(3)
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.spacingXXL)
                                    .padding(.vertical, DesignSystem.spacingXXL)
                                } else {
                                    // Rules List
                                    LazyVStack(spacing: DesignSystem.spacingM) {
                                        ForEach(ruleStoreViewModel.activeRules) { rule in
                                            RuleCard(rule: rule)
                                        }
                                    }
                                    .padding(.horizontal, DesignSystem.spacingL)
                                }
                            }
                            
                            Spacer(minLength: DesignSystem.spacingXL)
                        }
                    }
                    .padding(.vertical, DesignSystem.spacingL)
                    .background(DesignSystem.backgroundYellow.opacity(0.8))
                }
                .background(DesignSystem.backgroundYellow.opacity(0.8))
                .sheet(isPresented: $showingRuleCreation) {
                    RuleCreationFlowView(ruleCreationMode: ruleCreationMode)
                }
            }
            .tabItem {
                Image(systemName: "shield.lefthalf.filled")
                Text("Spaces")
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


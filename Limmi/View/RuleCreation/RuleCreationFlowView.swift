import SwiftUI
import FamilyControls
import ManagedSettings
import os
import FirebaseFirestore

struct RuleCreationFlowView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    
    @State private var ruleName: String = ""
    @State private var selectedTokens: [BlockedToken] = []
    @State private var currentStep: RuleCreationStep = .name
    @State private var selectedBeacon: BeaconDevice?
    @State private var gpsLocation: GPSLocation = GPSLocation()
    @State private var isCreatingRule = false
    @State private var creationError: String?
    
    // Pre-determined blocking mode from the button clicked
    let ruleCreationMode: RuleCreationMode
    
    private let flowLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "RuleCreationFlow")
    )
    
    init(ruleCreationMode: RuleCreationMode) {
        self.ruleCreationMode = ruleCreationMode
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress Header
                ProgressHeaderView(currentStep: currentStep)
                
                // Step Content
                TabView(selection: $currentStep) {
                    RuleNameStepView(
                        ruleName: $ruleName,
                        onNext: { moveToNextStep() }
                    )
                    .tag(RuleCreationStep.name)
                    
                    UserBeaconSelectionStepView(
                        selectedBeacon: $selectedBeacon,
                        onNext: { moveToNextStep() },
                        onBack: { moveToPreviousStep() }
                    )
                    .tag(RuleCreationStep.beacon)
                    
                    GPSLocationStepView(
                        gpsLocation: $gpsLocation,
                        onNext: { moveToNextStep() },
                        onBack: { moveToPreviousStep() }
                    )
                    .tag(RuleCreationStep.location)
                    
                    AppSelectionStepView(
                        selectedTokens: $selectedTokens,
                        onNext: { createRule() },
                        onBack: { moveToPreviousStep() },
                        isCreating: isCreatingRule,
                        ruleCreationMode: ruleCreationMode
                    )
                    .tag(RuleCreationStep.apps)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .disabled(isCreatingRule)
            }
            .background(DesignSystem.backgroundYellow)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(ruleCreationMode.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep == .name {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.secondaryBlue)
                        .disabled(isCreatingRule)
                    } else {
                        Button(action: {
                            hideKeyboard()
                            moveToPreviousStep()
                        }) {
                            HStack(spacing: DesignSystem.spacingXS) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(DesignSystem.secondaryBlue)
                                Text("Back")
                                    .font(DesignSystem.bodyText)
                                    .fontWeight(.medium)
                                    .foregroundColor(DesignSystem.secondaryBlue)
                            }
                        }
                        .disabled(isCreatingRule)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isCreatingRule {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.primaryYellow))
                    } else if currentStep == .name {
                        Button("Cancel") {
                            dismiss()
                        }
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.secondaryBlue)
                    }
                }
            }
            .alert("Creation Error", isPresented: .constant(creationError != nil)) {
                Button("OK") { creationError = nil }
            } message: {
                Text(creationError ?? "")
            }
        }
        .onAppear {
            ruleStoreViewModel.refreshBeacons()
            ruleStoreViewModel.refreshBlockedTokens()
        }
        .trackScreen("RuleCreation", screenClass: "RuleCreationFlowView")
        .onChange(of: currentStep) { oldStep, newStep in
            // Track step progression for analytics
            AnalyticsManager.shared.logEvent("rule_creation_step", parameters: [
                "step_name": newStep.title,
                "step_index": newStep.rawValue
            ])
        }
    }
    
    private func moveToNextStep() {
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = currentStep.next
        }
    }
    
    private func moveToPreviousStep() {
        hideKeyboard()
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = currentStep.previous
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func createRule() {
        guard !ruleName.isEmpty,
              let beacon = selectedBeacon,
              gpsLocation.isActive,
              !selectedTokens.isEmpty else {
            creationError = "Please complete all steps before creating the rule."
            return
        }
        isCreatingRule = true

        // Use RuleStoreViewModel for orchestration
        ruleStoreViewModel.createComplexRule(
            name: ruleName,
            beacon: beacon,
            gpsLocation: gpsLocation,
            blockedTokens: selectedTokens,
            isBlockingEnabled: ruleCreationMode.isBlockingEnabled
        ) { result in
            DispatchQueue.main.async {
                self.isCreatingRule = false
                switch result {
                case .success(_):
                    self.flowLogger.debug("Rule created successfully: \(self.ruleName)")
                    
                    // Track successful rule creation
                    AnalyticsManager.shared.logRuleCreated(
                        ruleType: "beacon_gps_hybrid",
                        appCount: self.selectedTokens.count,
                        hasSchedule: false
                    )
                    
                    self.dismiss()
                case .failure(let error):
                    self.creationError = "Failed to create rule: \(error.localizedDescription)"
                    self.flowLogger.error("Failed to create rule: \(self.ruleName) - \(error.localizedDescription)")
                    
                    // Track failed rule creation
                    AnalyticsManager.shared.logEvent("rule_creation_failed", parameters: [
                        "rule_name": self.ruleName,
                        "error": error.localizedDescription,
                        "app_count": self.selectedTokens.count
                    ])
                }
            }
        }
    }
}

// MARK: - Step Enumeration

enum RuleCreationStep: Int, CaseIterable {
    case name = 0
    case beacon = 1
    case location = 2
    case apps = 3
    
    var title: String {
        switch self {
        case .name: return "Name Your Rule"
        case .beacon: return "Select Beacon"
        case .location: return "Set GPS Location"
        case .apps: return "Choose Apps"
        }
    }
    
    var subtitle: String {
        switch self {
        case .name: return "Give your rule a memorable name"
        case .beacon: return "Pick a beacon to control access"
        case .location: return "Set GPS boundary for the rule"
        case .apps: return "Select content to block"
        }
    }
    
    var next: RuleCreationStep {
        switch self {
        case .name: return .beacon
        case .beacon: return .location
        case .location: return .apps
        case .apps: return .apps // Last step
        }
    }
    
    var previous: RuleCreationStep {
        switch self {
        case .name: return .name // First step
        case .beacon: return .name
        case .location: return .beacon
        case .apps: return .location
        }
    }
}

// MARK: - Progress Header

struct ProgressHeaderView: View {
    let currentStep: RuleCreationStep
    
    var body: some View {
                    VStack(spacing: DesignSystem.spacingL) {
            // Progress Indicator
            HStack(spacing: DesignSystem.spacingS) {
                ForEach(RuleCreationStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(step == currentStep ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }
            .padding(.top, DesignSystem.spacingS)
            
            // Step Title
            VStack(spacing: DesignSystem.spacingXS) {
                Text(currentStep.title)
                    .font(DesignSystem.headingMedium)
                    .fontWeight(.bold)
                    .foregroundColor(DesignSystem.pureBlack)
                
                Text(currentStep.subtitle)
                    .font(DesignSystem.bodyTextSmall)
                    .foregroundColor(DesignSystem.secondaryBlue)
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .padding(.horizontal, DesignSystem.spacingXL)
        .padding(.bottom, DesignSystem.spacingXL)
        .frame(maxWidth: .infinity)
        .background(DesignSystem.backgroundYellow)
    }
}

#if DEBUG
struct RuleCreationFlowView_Previews: PreviewProvider {
    static var previews: some View {
        let authViewModel = AuthViewModel()
        let firebaseRuleStore = FirebaseRuleStore(
            firestore: Firestore.firestore(),
            userId: "preview-user-id"
        )
        let ruleStoreViewModel = RuleStoreViewModel(ruleStore: firebaseRuleStore)
        RuleCreationFlowView(ruleCreationMode: .blocked)
            .environmentObject(authViewModel)
            .environmentObject(ruleStoreViewModel)
    }
}
#endif

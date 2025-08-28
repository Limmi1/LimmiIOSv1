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
    
    private let flowLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "RuleCreationFlow")
    )
    
    init(authViewModel: AuthViewModel) {
        
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
                        isCreating: isCreatingRule
                    )
                    .tag(RuleCreationStep.apps)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .disabled(isCreatingRule)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if currentStep == .name {
                        Button("Cancel") {
                            dismiss()
                        }
                        .disabled(isCreatingRule)
                    } else {
                        Button(action: {
                            hideKeyboard()
                            moveToPreviousStep()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Back")
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                        .disabled(isCreatingRule)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isCreatingRule {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if currentStep == .name {
                        Button("Cancel") {
                            dismiss()
                        }
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
            // Smart navigation: skip beacon step if no beacon is selected
            if currentStep == .name && selectedBeacon == nil {
                currentStep = .location
            } else if currentStep == .beacon && selectedBeacon == nil {
                currentStep = .location
            } else {
                currentStep = currentStep.next
            }
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
              gpsLocation.isActive,
              !selectedTokens.isEmpty else {
            creationError = "Please complete all steps before creating the rule."
            return
        }
        isCreatingRule = true

        // Use RuleStoreViewModel for orchestration
        ruleStoreViewModel.createComplexRule(
            name: ruleName,
            beacon: selectedBeacon, // Now optional
            gpsLocation: gpsLocation,
            blockedTokens: selectedTokens
        ) { result in
            DispatchQueue.main.async {
                self.isCreatingRule = false
                switch result {
                case .success(_):
                    self.flowLogger.debug("Rule created successfully: \(self.ruleName)")
                    
                    // Track successful rule creation
                    let ruleType = self.selectedBeacon != nil ? "beacon_gps_hybrid" : "gps_only"
                    AnalyticsManager.shared.logRuleCreated(
                        ruleType: ruleType,
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
        case .beacon: return "Pick a beacon to control access (optional)"
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
        VStack(spacing: 16) {
            // Step counter
            HStack {
                Text("Step \(currentStep.rawValue + 1) of \(RuleCreationStep.allCases.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            // Progress Indicator
            HStack(spacing: 8) {
                ForEach(RuleCreationStep.allCases, id: \.rawValue) { step in
                    Circle()
                        .fill(step.rawValue <= currentStep.rawValue ? .blue : .gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(step == currentStep ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }
            .padding(.top, 8)
            
            // Step Title
            VStack(spacing: 4) {
                Text(currentStep.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(currentStep.subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
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
        RuleCreationFlowView(authViewModel: authViewModel)
            .environmentObject(authViewModel)
            .environmentObject(ruleStoreViewModel)
    }
}
#endif

import SwiftUI
import FamilyControls
import MapKit
import CoreLocation
import os

struct RuleEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    @EnvironmentObject var blockingEngineViewModel: BlockingEngineViewModel
    
    @StateObject private var formViewModel: RuleFormViewModel
    @State private var showingDeleteConfirmation = false
    
    private let editLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "RuleEditView")
    )
    
    // Reactive condition status
    private var conditionStatus: RuleConditionStatus {
        // Access blockingConditionsChanged to trigger updates when conditions change
        _ = blockingEngineViewModel.blockingConditionsChanged
        return blockingEngineViewModel.getRuleConditionStatus(formViewModel.rule)
    }
    
    init(rule: Rule, authViewModel: AuthViewModel, ruleStoreViewModel: RuleStoreViewModel) {
        let formVM = RuleFormViewModel(mode: .editing(originalRule: rule), ruleStoreViewModel: ruleStoreViewModel)
        _formViewModel = StateObject(wrappedValue: formVM)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 24) {
                    topSections
                    
                    locationSections
                    
                    contentSection
                    
                    deleteSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(DesignSystem.homepageBackground)
            .navigationTitle(formViewModel.formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(formViewModel.isSaving)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(formViewModel.saveButtonTitle) {
                        saveRule()
                    }
                    .disabled(formViewModel.isSaving || !formViewModel.isValid)
                    .fontWeight(.semibold)
                }
            }
            .overlay {
                if formViewModel.isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .overlay {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.2)
                                Text("Saving Rule...")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(32)
                            .background(Color.black.opacity(0.8))
                            .cornerRadius(16)
                        }
                }
            }
        }
        .alert("Delete Rule", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteRule()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this rule? This action cannot be undone.")
        }
        .alert("Error", isPresented: .constant(formViewModel.errorMessage != nil)) {
            Button("OK") { formViewModel.errorMessage = nil }
        } message: {
            Text(formViewModel.errorMessage ?? "")
        }
    }
    
    private func saveRule() {
        Task {
            let result = await formViewModel.saveRule()
            
            await MainActor.run {
                switch result {
                case .success(_):
                    editLogger.debug("Rule updated successfully: \(formViewModel.rule.name)")
                    dismiss()
                case .failure(let error):
                    editLogger.error("Failed to update rule: \(formViewModel.rule.name) - \(error.localizedDescription)")
                    // Error is handled by formViewModel.errorMessage
                }
            }
        }
    }
    
    private func deleteRule() {
        guard let ruleId = formViewModel.rule.id else {
            formViewModel.errorMessage = "Cannot delete rule: missing ID."
            return
        }
        
        formViewModel.isSaving = true
        
        ruleStoreViewModel.deleteRule(id: ruleId) { result in
            DispatchQueue.main.async {
                formViewModel.isSaving = false
                
                switch result {
                case .success(_):
                    editLogger.debug("Rule deleted successfully: \(formViewModel.rule.name)")
                    dismiss()
                case .failure(let error):
                    formViewModel.errorMessage = "Failed to delete rule: \(error.localizedDescription)"
                    editLogger.error("Failed to delete rule: \(formViewModel.rule.name) - \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Computed Sub-views
    
    private var topSections: some View {
        VStack(spacing: 24) {
            RuleNameSection(ruleName: $formViewModel.rule.name)
            RuleActiveSection(isActive: $formViewModel.rule.isActive)
            RuleConditionStatusSection(conditionStatus: conditionStatus)
        }
    }
    
    private var locationSections: some View {
        VStack(spacing: 24) {
            GPSLocationSection(
                gpsLocation: $formViewModel.rule.gpsLocation,
                conditionStatus: conditionStatus.gpsConditionStatus
            )
            
            BeaconRulesSection(
                fineLocationRules: $formViewModel.rule.fineLocationRules,
                availableBeacons: ruleStoreViewModel.beacons,
                beaconConditionStatuses: conditionStatus.beaconConditionStatuses
            )
        }
    }
    
    private var contentSection: some View {
        VStack(spacing: 24) {
            TimeRulesSection(
                timeRules: $formViewModel.rule.timeRules,
                conditionStatus: conditionStatus.timeConditionStatus
            )
            
            AppTokenSelectionView(
                selectedTokens: $formViewModel.selectedTokens,
                familySelection: $formViewModel.familySelection,
                onSelectionChanged: {
                    formViewModel.updateTokensFromSelection()
                }
            )
        }
    }
    
    private var deleteSection: some View {
        DeleteRuleButton(showingDeleteConfirmation: $showingDeleteConfirmation)
    }
}

// MARK: - Rule Name Section

struct RuleNameSection: View {
    @Binding var ruleName: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rule Name")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField("Enter rule name", text: $ruleName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.body)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignSystem.homepageCardBackground)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.homepageCardBorder, lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
}

// MARK: - Rule Active Section

struct RuleActiveSection: View {
    @Binding var isActive: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rule Status")
                .font(.headline)
                .foregroundColor(.primary)
            
            Toggle("Rule is active", isOn: $isActive)
                .toggleStyle(SwitchToggleStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignSystem.homepageCardBackground)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.homepageCardBorder, lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
}

// MARK: - Rule Condition Status Section

struct RuleConditionStatusSection: View {
    let conditionStatus: RuleConditionStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Current Status")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Overall blocking status
                HStack(spacing: 4) {
                    Image(systemName: conditionStatus.overallBlockingStatus ? "shield.fill" : "shield")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(conditionStatus.overallBlockingStatus ? DesignSystem.homepageRed : DesignSystem.homepageGreen)
                    
                    Text(conditionStatus.overallBlockingStatus ? "Blocking" : "Not Blocking")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(conditionStatus.overallBlockingStatus ? DesignSystem.homepageRed : DesignSystem.homepageGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill((conditionStatus.overallBlockingStatus ? DesignSystem.homepageRed : DesignSystem.homepageGreen).opacity(0.1))
                )
            }
            
            VStack(spacing: 8) {
                // Rule active status
                StatusRow(
                    title: "Rule Active",
                    status: conditionStatus.isRuleActive ? .satisfied : .notSatisfied,
                    icon: "power"
                )
                
                // Has blocked apps
                StatusRow(
                    title: "Apps Configured",
                    status: conditionStatus.hasBlockedApps ? .satisfied : .notSatisfied,
                    icon: "apps.iphone"
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignSystem.homepageCardBackground)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.homepageCardBorder, lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
}

// MARK: - Status Row Component

struct StatusRow: View {
    let title: String
    let status: ConditionStatus
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            HStack(spacing: 4) {
                Image(systemName: status.iconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(status.swiftUIColor)
                
                Text(status.displayText)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(status.swiftUIColor)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(status.swiftUIColor.opacity(0.1))
            )
        }
    }
}

// MARK: - GPS Location Section

struct GPSLocationSection: View {
    @Binding var gpsLocation: GPSLocation
    let conditionStatus: ConditionStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("GPS Location")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // GPS condition status indicator
                HStack(spacing: 4) {
                    Image(systemName: conditionStatus.iconName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(conditionStatus.swiftUIColor)
                    
                    Text(conditionStatus.displayText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(conditionStatus.swiftUIColor)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(conditionStatus.swiftUIColor.opacity(0.1))
                )
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Latitude:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.6f", gpsLocation.latitude))
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text("Longitude:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.6f", gpsLocation.longitude))
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                HStack {
                    Text("Radius:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(gpsLocation.radius))m")
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                Toggle("GPS location is active", isOn: $gpsLocation.isActive)
                    .toggleStyle(SwitchToggleStyle())
                
                // GPS Zone Preview Map
                GPSZoneMapPreview(
                    latitude: gpsLocation.latitude,
                    longitude: gpsLocation.longitude,
                    radius: gpsLocation.radius
                )
                .frame(height: 200)
                .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignSystem.homepageCardBackground)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.homepageCardBorder, lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
}

// MARK: - Beacon Rules Section

struct BeaconRulesSection: View {
    @Binding var fineLocationRules: [FineLocationRule]
    let availableBeacons: [BeaconDevice]
    let beaconConditionStatuses: [BeaconConditionStatus]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Beacon Rules")
                .font(.headline)
                .foregroundColor(.primary)
            
            if fineLocationRules.isEmpty {
                Text("No beacon rules configured")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(fineLocationRules.indices, id: \.self) { index in
                    let beaconStatus = beaconConditionStatuses.first { $0.beaconId == fineLocationRules[index].beaconId }
                    BeaconRuleCard(
                        rule: $fineLocationRules[index],
                        availableBeacons: availableBeacons,
                        conditionStatus: beaconStatus
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignSystem.homepageCardBackground)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.homepageCardBorder, lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
}

// MARK: - Beacon Rule Card

struct BeaconRuleCard: View {
    @Binding var rule: FineLocationRule
    let availableBeacons: [BeaconDevice]
    let conditionStatus: BeaconConditionStatus?
    
    var beaconName: String {
        availableBeacons.first { $0.id == rule.beaconId }?.name ?? "Unknown Beacon"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(beaconName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Beacon condition status
                if let status = conditionStatus {
                    HStack(spacing: 4) {
                        Image(systemName: status.status.iconName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(status.status.swiftUIColor)
                        
                        Text(status.status.displayText)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(status.status.swiftUIColor)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(status.status.swiftUIColor.opacity(0.1))
                    )
                }
                
                Picker("Behavior", selection: $rule.behaviorType) {
                    Text("Allowed In").tag(FineLocationBehavior.allowedIn)
                    Text("Blocked In").tag(FineLocationBehavior.blockedIn)
                }
                .pickerStyle(MenuPickerStyle())
            }
            
            // Show detailed status if available
            if let status = conditionStatus, rule.isActive {
                Text(status.detailedStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
            
            Toggle("Beacon rule is active", isOn: $rule.isActive)
                .toggleStyle(SwitchToggleStyle())
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Time Rules Section

struct TimeRulesSection: View {
    @Binding var timeRules: [TimeRule]
    let conditionStatus: ConditionStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time Rules")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Time condition status indicator
                if !timeRules.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: conditionStatus.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(conditionStatus.swiftUIColor)
                        
                        Text(conditionStatus.displayText)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(conditionStatus.swiftUIColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(conditionStatus.swiftUIColor.opacity(0.1))
                    )
                }
            }
            
            if timeRules.isEmpty {
                Text("No time rules configured")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(timeRules.indices, id: \.self) { index in
                    TimeRuleCard(rule: $timeRules[index])
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(DesignSystem.homepageCardBackground)
        .cornerRadius(DesignSystem.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                .stroke(DesignSystem.homepageCardBorder, lineWidth: 1)
        )
        .shadow(
            color: DesignSystem.subtleShadow.color,
            radius: DesignSystem.subtleShadow.radius,
            x: DesignSystem.subtleShadow.x,
            y: DesignSystem.subtleShadow.y
        )
    }
}

// MARK: - Time Rule Card

struct TimeRuleCard: View {
    @Binding var rule: TimeRule
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(rule.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text(rule.recurrencePattern.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
            
            HStack {
                Text("Start:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(rule.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("End:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(rule.endTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            Toggle("Time rule is active", isOn: $rule.isActive)
                .toggleStyle(SwitchToggleStyle())
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Blocked Apps Section

struct BlockedAppsSection: View {
    @Binding var blockedAppIds: [String]
    @Binding var familySelection: FamilyActivitySelection
    @Binding var showingAppPicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blocked Apps")
                .font(.headline)
                .foregroundColor(.primary)
            
            Button(action: {
                showingAppPicker = true
            }) {
                HStack {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 20))
                        .foregroundColor(.red)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Select Apps to Block")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text(blockedAppIds.isEmpty ? "No apps selected" : "\(blockedAppIds.count) app\(blockedAppIds.count == 1 ? "" : "s") selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Delete Rule Button

struct DeleteRuleButton: View {
    @Binding var showingDeleteConfirmation: Bool
    
    var body: some View {
        Button(action: {
            showingDeleteConfirmation = true
        }) {
            HStack {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                
                Text("Delete Rule")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color.red)
            .cornerRadius(12)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }
}

// MARK: - Rule Edit App Picker Sheet

struct RuleEditAppPickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\(selection.applicationTokens.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                    
                    Spacer()
                }
                .padding(.top, 8)
                
                // Family Activity Picker
                FamilyActivityPicker(selection: $selection)
                
                Divider()
                
                // Accept Button
                Button("Accept") {
                    onAccept()
                    dismiss()
                }
                .disabled(selection.applicationTokens.isEmpty)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(selection.applicationTokens.isEmpty ? .gray : .blue)
                .cornerRadius(12)
                .padding()
            }
            .navigationTitle("Select Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - GPS Zone Map Preview

struct GPSZoneMapPreview: View {
    let latitude: Double
    let longitude: Double
    let radius: Double
    
    @State private var region: MKCoordinateRegion
    
    init(latitude: Double, longitude: Double, radius: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.radius = radius
        
        // Initialize region centered on the GPS location
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        
        // Calculate span based on radius - show area roughly 2.5x the radius
        let spanMultiplier = 2.5
        let latitudeDelta = (radius * spanMultiplier) / 111000 // Approximate meters per degree latitude
        let longitudeDelta = (radius * spanMultiplier) / (111000 * cos(latitude * .pi / 180))
        
        self._region = State(initialValue: MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(
                latitudeDelta: max(latitudeDelta, 0.001), // Minimum zoom level
                longitudeDelta: max(longitudeDelta, 0.001)
            )
        ))
    }
    
    var body: some View {
        ZStack {
            Map(coordinateRegion: .constant(region), annotationItems: [GPSLocationAnnotation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: radius)]) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    ZStack {
                        // Radius circle
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                            .frame(width: radiusToMapPixels(radius: annotation.radius), height: radiusToMapPixels(radius: annotation.radius))
                        
                        // Center point
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .disabled(true) // Disable map interaction
            
            // Overlay with zone info
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Zone Preview")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        Text("\(Int(radius))m radius")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .padding(8)
                }
            }
        }
    }
    
    // Helper function to convert radius to approximate map pixels
    private func radiusToMapPixels(radius: Double) -> CGFloat {
        // This is a rough approximation for visualization
        // In a real implementation, you might want to use map projection calculations
        let basePixelSize: CGFloat = 60 // Base size for 100m radius
        let radiusRatio = radius / 100.0
        return max(basePixelSize * CGFloat(radiusRatio), 20) // Minimum 20 pixels
    }
}

// Helper struct for map annotation
struct GPSLocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let radius: Double
}

#if DEBUG
struct RuleEditView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleRule = Rule(name: "Sample Rule")
        let authViewModel = AuthViewModel()
        // TODO: Implement proper BlockingEngineViewModel mock for preview
        /*
        RuleEditView(rule: sampleRule, authViewModel: authViewModel)
            .environmentObject(authViewModel)
            .environmentObject(RuleStoreViewModel(ruleStore: FirebaseRuleStore()))
            .environmentObject(BlockingEngineViewModel.mock())
        */
        Text("Preview temporarily disabled")
    }
}
#endif

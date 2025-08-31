import SwiftUI
import FamilyControls
import ManagedSettings

struct AppSelectionStepView: View {
    /// The raw BlockedTokens selected by the user
    @Binding var selectedTokens: [BlockedToken]
    let onNext: () -> Void
    let onBack: () -> Void
    let isCreating: Bool
    let ruleCreationMode: RuleCreationMode
    
    @State private var showingAppValidation = false
    @State private var showingAppPicker = false
    @State private var familySelection = FamilyActivitySelection()
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 24) {
                    // Hero Section
                    VStack(spacing: 16) {
                        Image(systemName: "apps.iphone")
                            .font(.system(size: 64))
                            .foregroundStyle(DesignSystem.homepageRed)
                            .scaleEffect(!selectedTokens.isEmpty ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.3), value: selectedTokens.isEmpty)
                        
                        VStack(spacing: 8) {
                            Text(ruleCreationMode.isBlockingEnabled ? "Select apps to block" : "Select apps to allow")
                                .font(DesignSystem.headingMedium)
                                .foregroundColor(DesignSystem.createRuleTextPrimary)
                                .multilineTextAlignment(.center)
                            
                            Text(ruleCreationMode.isBlockingEnabled ? 
                                "Choose which apps, categories, or websites should be blocked when you're not near the beacon" :
                                "Choose which apps, categories, or websites should be allowed when you're near the beacon")
                                .font(DesignSystem.bodyText)
                                .foregroundColor(DesignSystem.createRuleTextSecondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    // App Selection Button
                    Button(action: {
                        showingAppPicker = true
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(DesignSystem.homepageBlue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Select Content")
                                    .font(DesignSystem.headingSmall)
                                    .fontWeight(.semibold)
                                    .foregroundColor(DesignSystem.createRuleTextPrimary)
                                
                                Text(selectedTokens.isEmpty ? "Tap to choose apps, categories, or websites" : "\(selectedTokens.count) item\(selectedTokens.count == 1 ? "" : "s") selected")
                                    .font(DesignSystem.bodyTextSmall)
                                    .foregroundColor(DesignSystem.createRuleTextSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.createRuleTextSecondary)
                        }
                        .padding(20)
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
                    .disabled(isCreating)
                    .padding(.horizontal, 16)
                    
                    // Selected Content Preview
                    if !selectedTokens.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Selected Content")
                                .font(DesignSystem.headingSmall)
                                .fontWeight(.semibold)
                                .foregroundColor(DesignSystem.createRuleTextPrimary)
                                .padding(.horizontal, 16)

                            LazyVStack(spacing: 8) {
                                ForEach(Array(selectedTokens.enumerated()), id: \.offset) { index, token in
                                    TokenPreviewCard(token: token, index: index + 1)
                                }
                            }
                            .padding(.horizontal, 16)
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
                    
                    // Validation Message
                    if showingAppValidation {
                        Label("Please select at least one item to continue", systemImage: "exclamationmark.triangle.fill")
                            .font(DesignSystem.captionText)
                            .foregroundColor(DesignSystem.homepageRed)
                            .transition(.opacity)
                            .padding(.horizontal, 16)
                    }
                    
                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .background(DesignSystem.homepageBackground)
            
            // Create Rule Button
            VStack(spacing: 0) {
                Divider()
                    .background(DesignSystem.homepageCardBorder)
                
                Button(action: validateAndProceed) {
                    HStack(spacing: 12) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        
                        Text(isCreating ? "Creating Rule..." : "Create Rule")
                            .font(DesignSystem.bodyText)
                            .fontWeight(.semibold)
                        
                        if !isCreating {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .fill(selectedTokens.isEmpty || isCreating ? Color.gray.opacity(0.3) : DesignSystem.homepageGreen)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .stroke(selectedTokens.isEmpty || isCreating ? Color.clear : DesignSystem.homepageGreen.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(selectedTokens.isEmpty || isCreating)
                .scaleEffect(selectedTokens.isEmpty || isCreating ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: selectedTokens.isEmpty || isCreating)
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(DesignSystem.homepageCardBackground)
        }
        .background(DesignSystem.homepageBackground)
        .sheet(isPresented: $showingAppPicker) {
            TokenSelectionPickerSheet(
                selection: $familySelection,
                selectedTokens: $selectedTokens
            )
        }
    }
    
    private func validateAndProceed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingAppValidation = selectedTokens.isEmpty
        }

        if !showingAppValidation {
            onNext()
        }
    }
}

// MARK: - Token Selection Picker Sheet

struct TokenSelectionPickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    @Binding var selectedTokens: [BlockedToken]
    @Environment(\.dismiss) private var dismiss
    
    var totalSelectedCount: Int {
        return selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\(totalSelectedCount) selected")
                        .font(DesignSystem.bodyTextSmall)
                        .foregroundColor(DesignSystem.createRuleTextSecondary)
                        .padding(.leading)
                    
                    Spacer()
                }
                .padding(.top, 8)
                
                // Family Activity Picker
                FamilyActivityPicker(selection: $selection)
                
                Divider()
                    .background(DesignSystem.homepageCardBorder)
                
                // Accept Button
                Button("Accept") {
                    convertSelectionToBlockedTokens()
                    dismiss()
                }
                .disabled(totalSelectedCount == 0)
                .font(DesignSystem.headingSmall)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(DesignSystem.homepageBlue)
                .cornerRadius(DesignSystem.cornerRadius)
                .padding()
            }
            .navigationTitle("Select Content")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.homepageBlue)
                }
            }
        }
    }
    
    private func convertSelectionToBlockedTokens() {
        var tokens: [BlockedToken] = []
        
        // Convert application tokens with metadata from selection.applications
        for appToken in selection.applicationTokens {
            // Find the corresponding Application object for this token
            if let app = selection.applications.first(where: { $0.token == appToken }) {
                let displayName = app.localizedDisplayName ?? "Unknown App"
                let bundleId = app.bundleIdentifier
                let token = BlockedToken(applicationToken: appToken, displayName: displayName, bundleIdentifier: bundleId)
                tokens.append(token)
            } else {
                // Fallback if we can't find the corresponding Application object
                let token = BlockedToken(applicationToken: appToken, displayName: "Unknown App", bundleIdentifier: nil)
                tokens.append(token)
            }
        }
        
        // Convert activity category tokens with metadata from selection.categories
        for categoryToken in selection.categoryTokens {
            // Find the corresponding ActivityCategory object for this token
            if let category = selection.categories.first(where: { $0.token == categoryToken }) {
                let displayName = category.localizedDisplayName ?? "Unknown Category"
                let token = BlockedToken(activityCategoryToken: categoryToken, displayName: displayName)
                tokens.append(token)
            } else {
                // Fallback if we can't find the corresponding ActivityCategory object
                let token = BlockedToken(activityCategoryToken: categoryToken, displayName: "Unknown Category")
                tokens.append(token)
            }
        }
        
        // Convert web domain tokens with metadata from selection.webDomains
        for webToken in selection.webDomainTokens {
            // Find the corresponding WebDomain object for this token
            if let webDomain = selection.webDomains.first(where: { $0.token == webToken }) {
                let domain = webDomain.domain ?? "Unknown Domain"
                let token = BlockedToken(webDomainToken: webToken, domain: domain)
                tokens.append(token)
            } else {
                // Fallback if we can't find the corresponding WebDomain object
                let token = BlockedToken(webDomainToken: webToken, domain: "Unknown Domain")
                tokens.append(token)
            }
        }
        
        selectedTokens = tokens
    }
}

// MARK: - Token Preview Card

struct TokenPreviewCard: View {
    let token: BlockedToken
    let index: Int
    
    var tokenIcon: String {
        switch token.type {
        case .application:
            return "app"
        case .webDomain:
            return "globe"
        case .activityCategory:
            return "folder"
        }
    }
    
    var tokenColor: Color {
        switch token.type {
        case .application:
            return DesignSystem.homepageBlue
        case .webDomain:
            return DesignSystem.homepageGreen
        case .activityCategory:
            return .orange
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Token Icon
            Image(systemName: tokenIcon)
                .font(.system(size: 16))
                .foregroundColor(tokenColor)
                .frame(width: 20, height: 20)
            
            // Token Info
            VStack(alignment: .leading, spacing: 2) {
                Text(token.displayName)
                    .font(DesignSystem.bodyTextSmall)
                    .fontWeight(.medium)
                    .foregroundColor(DesignSystem.createRuleTextPrimary)
                
                HStack(spacing: 4) {
                    Text(token.type.rawValue.capitalized)
                        .font(DesignSystem.captionText)
                        .foregroundColor(DesignSystem.createRuleTextSecondary)
                    
                    Text("•")
                        .font(DesignSystem.captionText)
                        .foregroundColor(DesignSystem.createRuleTextSecondary)
                    
                    Text("Selected for blocking")
                        .font(DesignSystem.captionText)
                        .foregroundColor(DesignSystem.createRuleTextSecondary)
                }
            }
            
            Spacer()
            
            // Selection indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.homepageGreen)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Previews
#if DEBUG
struct AppSelectionStepView_Previews: PreviewProvider {
    static var previews: some View {
        AppSelectionStepView(
            selectedTokens: .constant([]),
            onNext: { },
            onBack: { },
            isCreating: false,
            ruleCreationMode: .blocked
        )
    }
}
#endif

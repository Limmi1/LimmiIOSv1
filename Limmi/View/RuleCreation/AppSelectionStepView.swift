import SwiftUI
import FamilyControls
import ManagedSettings

struct AppSelectionStepView: View {
    /// The raw BlockedTokens selected by the user
    @Binding var selectedTokens: [BlockedToken]
    let onNext: () -> Void
    let onBack: () -> Void
    let isCreating: Bool
    
    @State private var showingAppValidation = false
    @State private var showingAppPicker = false
    @State private var familySelection = FamilyActivitySelection()
    
    var body: some View {
        VStack(spacing: 0) {
            
            ScrollView {
                VStack(spacing: 32) {
                    // Hero Section
                    VStack(spacing: 16) {
                        Image(systemName: "apps.iphone")
                            .font(.system(size: 64))
                            .foregroundStyle(.red)
                        .scaleEffect(!selectedTokens.isEmpty ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.3), value: selectedTokens.isEmpty)
                        
                        VStack(spacing: 8) {
                            Text("Select apps to block")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("Choose which apps, categories, or websites should be blocked when you're not near the beacon")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // App Selection Button
                    Button(action: {
                        showingAppPicker = true
                    }) {
                        HStack(spacing: 16) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Select Content")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text(selectedTokens.isEmpty ? "Tap to choose apps, categories, or websites" : "\(selectedTokens.count) item\(selectedTokens.count == 1 ? "" : "s") selected")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(20)
                        .background(Color(.systemBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
                    }
                    .disabled(isCreating)
                    .padding(.horizontal, 24)
                    
                    // Selected Content Preview
                    if !selectedTokens.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Selected Content")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 24)

                            LazyVStack(spacing: 8) {
                                ForEach(Array(selectedTokens.enumerated()), id: \.offset) { index, token in
                                    TokenPreviewCard(token: token, index: index + 1)
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    
                    // Validation Message
                    if showingAppValidation {
                        Label("Please select at least one item to continue", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .transition(.opacity)
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            
            // Create Rule Button
            VStack(spacing: 0) {
                Divider()
                    .background(Color(.systemGray5))
                
                Button(action: validateAndProceed) {
                    HStack(spacing: 12) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        
                        Text(isCreating ? "Creating Rule..." : "Create Rule")
                            .font(.system(size: 16, weight: .semibold))
                        
                        if !isCreating {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                        .fill(selectedTokens.isEmpty || isCreating ? .gray.opacity(0.3) : .green)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                        .stroke(selectedTokens.isEmpty || isCreating ? .clear : .green.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(selectedTokens.isEmpty || isCreating)
                .scaleEffect(selectedTokens.isEmpty || isCreating ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: selectedTokens.isEmpty || isCreating)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
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
                    convertSelectionToBlockedTokens()
                    dismiss()
                }
                .disabled(totalSelectedCount == 0)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.blue)
                .cornerRadius(12)
                .padding()
            }
            .navigationTitle("Select Content")
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
            return "apps.iphone"
        case .webDomain:
            return "globe"
        case .activityCategory:
            return "folder"
        }
    }
    
    var tokenColor: Color {
        switch token.type {
        case .application:
            return .blue
        case .webDomain:
            return .green
        case .activityCategory:
            return .orange
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Token Index
            ZStack {
                Circle()
                    .fill(tokenColor.opacity(0.1))
                    .frame(width: 32, height: 32)
                
                Text("\(index)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tokenColor)
            }
            
            // Token Icon
            Image(systemName: tokenIcon)
                .font(.system(size: 16))
                .foregroundColor(tokenColor)
                .frame(width: 20, height: 20)
            
            // Token Info
            VStack(alignment: .leading, spacing: 2) {
                Text(token.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text("\(token.type.rawValue.capitalized) • Selected for blocking")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Blocked indicator
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.red)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
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
            isCreating: false
        )
    }
}
#endif

import SwiftUI
import FamilyControls

/// Reusable app selection view for both rule creation and editing
/// Handles FamilyActivityPicker and token conversion with metadata
struct AppTokenSelectionView: View {
    @Binding var selectedTokens: [BlockedToken]
    @Binding var familySelection: FamilyActivitySelection
    
    let onSelectionChanged: () -> Void
    
    @State private var showingPicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Selection Summary
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocked Content")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(selectionSummary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Select") {
                    showingPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
            
            // Token Preview List
            if !selectedTokens.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(Array(selectedTokens.enumerated()), id: \.offset) { index, token in
                        TokenPreviewRow(token: token, index: index)
                    }
                }
                .padding(.top, 8)
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
        .sheet(isPresented: $showingPicker) {
            AppPickerSheet(
                selection: $familySelection,
                onAccept: {
                    onSelectionChanged()
                }
            )
        }
    }
    
    private var selectionSummary: String {
        if selectedTokens.isEmpty {
            return "No content selected for blocking"
        }
        
        var parts: [String] = []
        
        let appCount = selectedTokens.filter { $0.type == .application }.count
        if appCount > 0 {
            parts.append("\(appCount) app\(appCount == 1 ? "" : "s")")
        }
        
        let categoryCount = selectedTokens.filter { $0.type == .activityCategory }.count
        if categoryCount > 0 {
            parts.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies")")
        }
        
        let domainCount = selectedTokens.filter { $0.type == .webDomain }.count
        if domainCount > 0 {
            parts.append("\(domainCount) website\(domainCount == 1 ? "" : "s")")
        }
        
        return parts.joined(separator: ", ")
    }
}

// MARK: - Token Preview Row

struct TokenPreviewRow: View {
    let token: BlockedToken
    let index: Int
    
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
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text(token.type.rawValue.capitalized)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let bundleId = token.bundleIdentifier, !bundleId.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Selection indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
    
    private var tokenIcon: String {
        switch token.type {
        case .application:
            return "app"
        case .webDomain:
            return "globe"
        case .activityCategory:
            return "folder"
        }
    }
    
    private var tokenColor: Color {
        switch token.type {
        case .application:
            return .blue
        case .webDomain:
            return .green
        case .activityCategory:
            return .orange
        }
    }
}

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
    @Binding var selection: FamilyActivitySelection
    let onAccept: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(selectionSummary)
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
                .disabled(totalSelectionCount == 0)
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(totalSelectionCount == 0 ? .gray : .blue)
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
    
    private var totalSelectionCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }
    
    private var selectionSummary: String {
        var parts: [String] = []
        
        if selection.applicationTokens.count > 0 {
            parts.append("\(selection.applicationTokens.count) app\(selection.applicationTokens.count == 1 ? "" : "s")")
        }
        
        if selection.categoryTokens.count > 0 {
            parts.append("\(selection.categoryTokens.count) categor\(selection.categoryTokens.count == 1 ? "y" : "ies")")
        }
        
        if selection.webDomainTokens.count > 0 {
            parts.append("\(selection.webDomainTokens.count) website\(selection.webDomainTokens.count == 1 ? "" : "s")")
        }
        
        if parts.isEmpty {
            return "No content selected"
        }
        
        return parts.joined(separator: ", ") + " selected"
    }
}

#if DEBUG
struct AppTokenSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        AppTokenSelectionView(
            selectedTokens: .constant([]),
            familySelection: .constant(FamilyActivitySelection()),
            onSelectionChanged: {}
        )
        .padding()
    }
}
#endif
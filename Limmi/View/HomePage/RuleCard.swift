import SwiftUI

struct RuleCard: View {
    let rule: Rule
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    @EnvironmentObject var blockingEngineViewModel: BlockingEngineViewModel
    @State private var showingEditView = false
    
    private var isCurrentlyBlocking: Bool {
        // Access blockingConditionsChanged to trigger updates when conditions change
        _ = blockingEngineViewModel.blockingConditionsChanged
        return blockingEngineViewModel.isRuleCurrentlyBlocking(rule)
    }
    
    private var spaceTypeIndicator: (text: String, color: Color, icon: String) {
        // Check if rule has any fine location rules to determine space type
        let activeFineRules = rule.fineLocationRules.filter { $0.isActive }
        
        if activeFineRules.isEmpty {
            // No beacon rules - default to blocked space
            return ("Blocked Space", .red, "shield.fill")
        }
        
        // Check if all active fine rules are of the same type
        let hasAllowedIn = activeFineRules.contains { $0.behaviorType == .allowedIn }
        let hasBlockedIn = activeFineRules.contains { $0.behaviorType == .blockedIn }
        
        if hasAllowedIn && !hasBlockedIn {
            // All rules are allowedIn
            return ("Allowed Space", .green, "checkmark.shield.fill")
        } else if hasBlockedIn && !hasAllowedIn {
            // All rules are blockedIn
            return ("Blocked Space", .red, "shield.fill")
        } else {
            // Mixed rules - show as blocked space (more restrictive)
            return ("Mixed Space", .orange, "exclamationmark.shield.fill")
        }
    }
    
    var body: some View {
        Button(action: {
            showingEditView = true
        }) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                // Rule Header with Space Type Indicator and Chevron
                HStack {
                    Text(rule.name)
                        .font(DesignSystem.headingSmall)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.pureBlack)
                    
                    Spacer()
                    
                    // Space Type Indicator
                    HStack(spacing: 4) {
                        Image(systemName: spaceTypeIndicator.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(spaceTypeIndicator.color)
                        
                        Text(spaceTypeIndicator.text)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(spaceTypeIndicator.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(spaceTypeIndicator.color.opacity(0.1))
                    )
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.secondaryBlue)
                }
                
                // Status Chips
                HStack(spacing: DesignSystem.spacingS) {
                    // Blocking Status Indicator (Dominant Badge)
                    if rule.isActive {
                        HStack(spacing: DesignSystem.spacingXS) {
                            Image(systemName: isCurrentlyBlocking ? "shield.fill" : "shield")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isCurrentlyBlocking ? .red : DesignSystem.mutedGreen)
                            
                            Text(isCurrentlyBlocking ? "Blocking" : "Not Blocking")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isCurrentlyBlocking ? .red : DesignSystem.mutedGreen)
                        }
                        .padding(.horizontal, DesignSystem.spacingS)
                        .padding(.vertical, 6)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                                .fill(isCurrentlyBlocking ? .red.opacity(0.1) : DesignSystem.mutedGreen.opacity(0.1))
                        )
                    }
                    
                    // Rule Active Status (Secondary Badge)
                    Text(rule.isActive ? "Active" : "Inactive")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(rule.isActive ? .green : .gray)
                        .padding(.horizontal, DesignSystem.spacingS)
                        .padding(.vertical, 6)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                                .stroke(rule.isActive ? .green : .gray, lineWidth: 1)
                        )
                }
                
                // Compact Meta Info Row
                HStack(spacing: DesignSystem.ruleCardMetaSpacing) {
                    // GPS Info
                    HStack(spacing: DesignSystem.ruleCardMetaSpacing) {
                        Image(systemName: "location")
                            .font(.system(size: DesignSystem.ruleCardMetaIconSize))
                            .foregroundColor(DesignSystem.secondaryBlue)
                        
                        Text("\(Int(rule.gpsLocation.radius))m")
                            .font(.system(size: DesignSystem.ruleCardMetaTextSize, weight: .medium))
                            .foregroundColor(DesignSystem.secondaryBlue)
                    }
                    
                    // Separator
                    Text("•")
                        .font(.system(size: DesignSystem.ruleCardMetaIconSize, weight: .medium))
                        .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                    
                    // Limmi Device Info
                    if !rule.fineLocationRules.isEmpty {
                        HStack(spacing: DesignSystem.ruleCardMetaSpacing) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: DesignSystem.ruleCardMetaIconSize))
                                .foregroundColor(.orange)
                            
                            Text("\(rule.fineLocationRules.count) \(rule.fineLocationRules.count == 1 ? "Limmi Device" : "Limmi Devices")")
                                .font(.system(size: DesignSystem.ruleCardMetaTextSize, weight: .medium))
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                        
                        // Separator
                        Text("•")
                            .font(.system(size: DesignSystem.ruleCardMetaIconSize, weight: .medium))
                            .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                    }
                    
                    // Blocked Apps Info
                    if !rule.blockedTokenIds.isEmpty {
                        HStack(spacing: DesignSystem.ruleCardMetaSpacing) {
                            Image(systemName: "app.badge")
                                .font(.system(size: DesignSystem.ruleCardMetaIconSize))
                                .foregroundColor(.red)
                            
                            Text("\(rule.blockedTokenIds.count) \(rule.blockedTokenIds.count == 1 ? "Blocked App" : "Blocked Apps")")
                                .font(.system(size: DesignSystem.ruleCardMetaTextSize, weight: .medium))
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                    }
                    
                    Spacer()
                }
            }
            .padding(DesignSystem.cardPadding)
            .background(DesignSystem.pureWhite)
            .cornerRadius(DesignSystem.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
            )
            .shadow(
                color: DesignSystem.subtleShadow.color,
                radius: DesignSystem.subtleShadow.radius,
                x: DesignSystem.subtleShadow.x,
                y: DesignSystem.subtleShadow.y
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingEditView,
               onDismiss: { NotificationCenter.default.post(name: .didModifyRules, object: nil) }) {
            RuleEditView(rule: rule, authViewModel: authViewModel, ruleStoreViewModel: ruleStoreViewModel)
                .environmentObject(authViewModel)
                .environmentObject(ruleStoreViewModel)
                .environmentObject(blockingEngineViewModel)
        }
    }
}

/*
#if DEBUG
struct RuleCard_Previews: PreviewProvider {
    static var previews: some View {
        RuleCard(
            rule: Rule(name: "Sample Rule")
        )
        .environmentObject(AuthViewModel())
        .environmentObject(RuleStoreViewModel(ruleStore: FirebaseRuleStore(firestore: nil, userId: "preview-user-id")))
        .environmentObject(BlockingEngineViewModel.mock())
        .padding()
    }
}
#endif
*/
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
    
    var body: some View {
        Button(action: {
            showingEditView = true
        }) {
            VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                // Rule Header with Chevron
                HStack {
                    Text(rule.name)
                        .font(DesignSystem.headingSmall)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.pureBlack)
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.secondaryBlue)
                }
                
                // Status Chips
                HStack(spacing: DesignSystem.spacingS) {
                    // Rule Active Status
                    Text(rule.isActive ? "Active" : "Inactive")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(rule.isActive ? .green : DesignSystem.secondaryBlue)
                        .padding(.horizontal, DesignSystem.spacingS)
                        .padding(.vertical, 6)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                                .fill(rule.isActive ? .green.opacity(0.1) : DesignSystem.secondaryBlue.opacity(0.1))
                        )
                    
                    // Blocking Status Indicator
                    if rule.isActive {
                        HStack(spacing: DesignSystem.spacingXS) {
                            Image(systemName: isCurrentlyBlocking ? "shield.fill" : "shield")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isCurrentlyBlocking ? .red : DesignSystem.secondaryBlue)
                            
                            Text(isCurrentlyBlocking ? "Blocking" : "Not Blocking")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(isCurrentlyBlocking ? .red : DesignSystem.secondaryBlue)
                        }
                        .padding(.horizontal, DesignSystem.spacingS)
                        .padding(.vertical, 6)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                                .fill(isCurrentlyBlocking ? .red.opacity(0.1) : DesignSystem.secondaryBlue.opacity(0.1))
                        )
                    }
                }
                
                // Compact Meta Info Row
                HStack(spacing: DesignSystem.spacingS) {
                    // GPS Info
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.secondaryBlue)
                        
                        Text("\(Int(rule.gpsLocation.radius)) m radius")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignSystem.secondaryBlue)
                    }
                    
                    // Separator
                    Text("•")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                    
                    // Beacon Info
                    if !rule.fineLocationRules.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            
                            Text("\(rule.fineLocationRules.count) \(rule.fineLocationRules.count == 1 ? "Beacon" : "Beacons")")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                        
                        // Separator
                        Text("•")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                    }
                    
                    // Blocked Apps Info
                    if !rule.blockedTokenIds.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            
                            Text("\(rule.blockedTokenIds.count) \(rule.blockedTokenIds.count == 1 ? "Blocked App" : "Blocked Apps")")
                                .font(.system(size: 13, weight: .medium))
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
                    .stroke(DesignSystem.secondaryBlue, lineWidth: DesignSystem.borderWidth)
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
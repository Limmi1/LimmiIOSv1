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
            HStack(alignment: .top, spacing: DesignSystem.spacingM) {
                // Left side - Rule Info
                VStack(alignment: .leading, spacing: DesignSystem.spacingM) {
                    // Rule Header
                    VStack(alignment: .leading, spacing: DesignSystem.spacingXS) {
                        Text(rule.name)
                            .font(DesignSystem.headingSmall)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.pureBlack)
                        
                        HStack(spacing: DesignSystem.spacingS) {
                            // Rule Active Status
                            Text(rule.isActive ? "Active" : "Inactive")
                                .font(DesignSystem.captionText)
                                .fontWeight(.medium)
                                .foregroundColor(rule.isActive ? .green : DesignSystem.secondaryBlue)
                                .padding(.horizontal, DesignSystem.spacingS)
                                .padding(.vertical, DesignSystem.spacingXS)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius / 3)
                                        .fill(rule.isActive ? .green.opacity(0.1) : DesignSystem.secondaryBlue.opacity(0.1))
                                )
                            
                            // Blocking Status Indicator
                            if rule.isActive {
                                HStack(spacing: DesignSystem.spacingXS) {
                                    Image(systemName: isCurrentlyBlocking ? "shield.fill" : "shield")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isCurrentlyBlocking ? .red : DesignSystem.secondaryBlue)
                                    
                                    Text(isCurrentlyBlocking ? "Blocking" : "Not Blocking")
                                        .font(DesignSystem.captionText)
                                        .fontWeight(.medium)
                                        .foregroundColor(isCurrentlyBlocking ? .red : DesignSystem.secondaryBlue)
                                }
                                .padding(.horizontal, DesignSystem.spacingS)
                                .padding(.vertical, DesignSystem.spacingXS)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius / 3)
                                        .fill(isCurrentlyBlocking ? .red.opacity(0.1) : DesignSystem.secondaryBlue.opacity(0.1))
                                )
                            }
                        }
                    }
                    
                    // Rule Info
                    VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                        // Location Info
                        HStack(spacing: DesignSystem.spacingS) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12))
                                .foregroundColor(DesignSystem.secondaryBlue)
                            
                            Text("GPS Zone: \(Int(rule.gpsLocation.radius))m radius")
                                .font(DesignSystem.captionText)
                                .foregroundColor(DesignSystem.secondaryBlue)
                        }
                        
                        // Beacon Info
                        if !rule.fineLocationRules.isEmpty {
                            HStack(spacing: DesignSystem.spacingS) {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                
                                Text("\(rule.fineLocationRules.count) beacon\(rule.fineLocationRules.count == 1 ? "" : "s")")
                                    .font(DesignSystem.captionText)
                                    .foregroundColor(DesignSystem.secondaryBlue)
                            }
                        }
                        
                        // Time Rules Info
                        if !rule.timeRules.isEmpty {
                            HStack(spacing: DesignSystem.spacingS) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.purple)
                                
                                Text("\(rule.timeRules.count) time rule\(rule.timeRules.count == 1 ? "" : "s")")
                                    .font(DesignSystem.captionText)
                                    .foregroundColor(DesignSystem.secondaryBlue)
                            }
                        }
                        
                        // Blocked Content Info
                        if !rule.blockedTokenIds.isEmpty {
                            HStack(spacing: DesignSystem.spacingS) {
                                Image(systemName: "app.badge.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.red)
                                
                                Text("\(rule.blockedTokenIds.count) blocked item\(rule.blockedTokenIds.count == 1 ? "" : "s")")
                                    .font(DesignSystem.captionText)
                                    .foregroundColor(DesignSystem.secondaryBlue)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Right side - Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DesignSystem.secondaryBlue)
            }
            .padding(DesignSystem.cardPadding)
            .background(DesignSystem.pureWhite)
            .cornerRadius(DesignSystem.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue, lineWidth: DesignSystem.borderWidth)
            )
            .shadow(
                color: DesignSystem.cardShadow.color,
                radius: DesignSystem.cardShadow.radius,
                x: DesignSystem.cardShadow.x,
                y: DesignSystem.cardShadow.y
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
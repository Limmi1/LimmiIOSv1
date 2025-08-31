import SwiftUI
import FirebaseFirestore

struct CreateRuleButton: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    @State private var showingRuleCreation = false
    
    var body: some View {
        Button(action: {
            showingRuleCreation = true
        }) {
            HStack(spacing: DesignSystem.spacingM) {
                Image(systemName: "plus")
                    .font(DesignSystem.bodyText)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.pureBlack)
                
                Text("Create New Rule")
                    .font(DesignSystem.bodyText)
                    .fontWeight(.semibold)
                    .foregroundColor(DesignSystem.pureBlack)
            }
            .frame(maxWidth: .infinity)
            .frame(height: DesignSystem.buttonHeight)
            .background(DesignSystem.primaryYellow)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                    .stroke(DesignSystem.secondaryBlue, lineWidth: DesignSystem.borderWidth)
            )
            .cornerRadius(DesignSystem.cornerRadius)
            .shadow(
                color: DesignSystem.cardShadow.color,
                radius: DesignSystem.cardShadow.radius,
                x: DesignSystem.cardShadow.x,
                y: DesignSystem.cardShadow.y
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(showingRuleCreation ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: showingRuleCreation)
        .sheet(isPresented: $showingRuleCreation,
               onDismiss: { NotificationCenter.default.post(name: .didModifyRules, object: nil) }) {
            RuleCreationFlowView(ruleCreationMode: .blocked)
                .environmentObject(authViewModel)
                .environmentObject(ruleStoreViewModel)
        }
    }
}

#Preview {
    let authViewModel = AuthViewModel()
    let firebaseRuleStore = FirebaseRuleStore(
        firestore: Firestore.firestore(),
        userId: "preview-user-id"
    )
    let ruleStoreViewModel = RuleStoreViewModel(ruleStore: firebaseRuleStore)
    return CreateRuleButton()
        .environmentObject(authViewModel)
        .environmentObject(ruleStoreViewModel)
        .padding()
}
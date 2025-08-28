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
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Create New Rule")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .blue.opacity(0.8)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
            .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(showingRuleCreation ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: showingRuleCreation)
        .sheet(isPresented: $showingRuleCreation,
               onDismiss: { NotificationCenter.default.post(name: .didModifyRules, object: nil) }) {
            RuleCreationFlowView(authViewModel: authViewModel)
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
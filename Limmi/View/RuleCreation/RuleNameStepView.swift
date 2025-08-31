import SwiftUI

struct RuleNameStepView: View {
    @Binding var ruleName: String
    let onNext: () -> Void
    
    @State private var showingNameValidation = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: DesignSystem.spacingXXL) {
            // Add top spacing to move input lower
            Spacer()
                .frame(height: 60)
            
            // Input Section
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("Space Name")
                        .font(DesignSystem.headingSmall)
                        .foregroundColor(DesignSystem.pureBlack)
                    
                    TextField("Study Room", text: $ruleName)
                        .textFieldStyle(ModernTextFieldStyle())
                        .focused($isTextFieldFocused)
                        .submitLabel(.continue)
                        .onSubmit {
                            validateAndProceed()
                        }
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Continue") {
                                    validateAndProceed()
                                }
                                .disabled(ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                }
                
                // Validation Message
                if showingNameValidation {
                    Label("Please enter a name for your rule", systemImage: "exclamationmark.triangle.fill")
                        .font(DesignSystem.captionText)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }
            .createRuleCard()
            

        }
        .onAppear {
            // Auto-focus the text field when view appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextFieldFocused = true
            }
        }
        .onTapGesture {
            // Dismiss keyboard when tapping outside
            isTextFieldFocused = false
        }
    }
    
    private func validateAndProceed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingNameValidation = ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        
        if !showingNameValidation {
            onNext()
        }
    }
}

// MARK: - Modern Text Field Style

struct ModernTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(DesignSystem.spacingL)
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
}

#if DEBUG
struct RuleNameStepView_Previews: PreviewProvider {
    static var previews: some View {
        RuleNameStepView(ruleName: .constant("")) { }
    }
}
#endif
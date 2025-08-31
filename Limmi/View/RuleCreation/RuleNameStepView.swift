import SwiftUI

struct RuleNameStepView: View {
    @Binding var ruleName: String
    let onNext: () -> Void
    
    @State private var showingNameValidation = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: DesignSystem.spacingXXL) {
            // Hero Section
            VStack(spacing: DesignSystem.spacingL) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(DesignSystem.primaryYellow)
                    .scaleEffect(ruleName.isEmpty ? 1.0 : 1.1)
                    .animation(.easeInOut(duration: 0.3), value: ruleName.isEmpty)
                
                VStack(spacing: DesignSystem.spacingS) {
                    Text("What should we call this rule?")
                        .font(DesignSystem.headingMedium)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.pureBlack)
                        .multilineTextAlignment(.center)
                    
                    Text("Choose a name that helps you remember what this rule does")
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.secondaryBlue)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, DesignSystem.spacingXXL)
            
            // Input Section
            VStack(alignment: .leading, spacing: DesignSystem.spacingL) {
                VStack(alignment: .leading, spacing: DesignSystem.spacingS) {
                    Text("Rule Name")
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
                            .padding(.horizontal, DesignSystem.spacingXL)
            
            Spacer()
            
            // Continue Button
            Button(action: validateAndProceed) {
                HStack(spacing: DesignSystem.spacingM) {
                    Text("Continue")
                        .font(DesignSystem.bodyText)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.pureBlack)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignSystem.pureBlack)
                }
                .frame(maxWidth: .infinity)
                .frame(height: DesignSystem.buttonHeight)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .fill(ruleName.isEmpty ? DesignSystem.secondaryBlue.opacity(0.3) : DesignSystem.primaryYellow)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                        .stroke(ruleName.isEmpty ? .clear : DesignSystem.secondaryBlue, lineWidth: DesignSystem.borderWidth)
                )
            }
            .disabled(ruleName.isEmpty)
            .scaleEffect(ruleName.isEmpty ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: ruleName.isEmpty)
            .padding(.horizontal, DesignSystem.spacingXL)
            .padding(.bottom, DesignSystem.spacingXXL)
        }
        .background(DesignSystem.backgroundYellow)
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
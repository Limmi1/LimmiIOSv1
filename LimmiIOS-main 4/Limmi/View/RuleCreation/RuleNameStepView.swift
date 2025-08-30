import SwiftUI

struct RuleNameStepView: View {
    @Binding var ruleName: String
    let onNext: () -> Void
    
    @State private var showingNameValidation = false
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 32) {
            // Hero Section
            VStack(spacing: 16) {
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                    .scaleEffect(ruleName.isEmpty ? 1.0 : 1.1)
                    .animation(.easeInOut(duration: 0.3), value: ruleName.isEmpty)
                
                VStack(spacing: 8) {
                    Text("What should we call this rule?")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Choose a name that helps you remember what this rule does")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 32)
            
            // Input Section
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Rule Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
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
                        .font(.caption)
                        .foregroundColor(.red)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Continue Button
            Button(action: validateAndProceed) {
                HStack(spacing: 12) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(ruleName.isEmpty ? .gray.opacity(0.3) : .blue)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(ruleName.isEmpty ? .clear : .blue.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(ruleName.isEmpty)
            .scaleEffect(ruleName.isEmpty ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: ruleName.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
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
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
    }
}

#if DEBUG
struct RuleNameStepView_Previews: PreviewProvider {
    static var previews: some View {
        RuleNameStepView(ruleName: .constant("")) { }
    }
}
#endif
import SwiftUI

struct PasscodePromptView: View {
    @ObservedObject private var lockManager = LockManager.shared
    @State private var passcode: String = ""
    @State private var showError: Bool = false

    let onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter Limmi Passcode")
                .font(DesignSystem.headingSmall)

            SecureField("Passcode", text: $passcode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .padding(.horizontal)
                .limmiInput()

            if showError {
                Text("Incorrect passcode")
                    .foregroundColor(DesignSystem.mutedRed)
                    .font(DesignSystem.captionText)
            }

            Button(action: {
                if lockManager.validatePasscode(passcode) {
                    lockManager.markUnlocked()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    onSuccess()
                    dismiss()
                } else {
                    showError = true
                }
            }) {
                Text("Unlock")
                    .frame(maxWidth: .infinity)
            }
            .limmiButton(DesignSystem.primaryButtonStyle)
            .disabled(passcode.count < 4)
        }
        .padding(DesignSystem.cardPadding)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onChange(of: passcode) { _, newValue in
            // Keep digits only and limit to 12
            let filtered = newValue.filter { $0.isNumber }
            passcode = String(filtered.prefix(12))
        }
    }
}



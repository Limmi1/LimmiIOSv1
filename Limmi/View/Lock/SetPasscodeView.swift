import SwiftUI
import UIKit

struct SetPasscodeView: View {
    @ObservedObject private var lockManager = LockManager.shared
    @State private var passcode: String = ""
    @State private var confirm: String = ""
    @State private var current: String = ""
    @State private var error: String?
    @State private var successMessage: String?
    @State private var showSavedAlert: Bool = false
    @State private var showForceResetAlert: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(header: Text("Set Limmi Passcode")) {
                HStack {
                    Text("Status")
                    Spacer()
                    Text((lockManager.hasPasscode() ? "Set" : "Not set"))
                        .foregroundColor(lockManager.hasPasscode() ? .green : .secondary)
                        .font(.subheadline)
                }
                if lockManager.hasPasscode() {
                    SecureField("Current Limmi passcode", text: $current)
                        .keyboardType(.numberPad)
                }
                SecureField(lockManager.hasPasscode() ? "New Limmi passcode" : "New Limmi passcode", text: $passcode)
                    .keyboardType(.numberPad)
                SecureField("Confirm Limmi passcode", text: $confirm)
                    .keyboardType(.numberPad)
                if let error = error {
                    Text(error).foregroundColor(.red)
                }
                if let successMessage = successMessage {
                    Text(successMessage).foregroundColor(.green)
                }
                Button(lockManager.hasPasscode() ? "Change Passcode" : "Save Limmi Passcode") {
                    guard passcode.count >= 4 else {
                        error = "Passcode must be at least 4 digits"
                        return
                    }
                    guard passcode == confirm else {
                        error = "Passcodes do not match"
                        return
                    }
                    do {
                        if lockManager.hasPasscode() {
                            try lockManager.changePasscode(current: current, new: passcode, confirm: confirm)
                        } else {
                            try lockManager.setPasscode(passcode)
                        }
                        print("🔐 SetPasscodeView: Passcode saved successfully")
                        error = nil
                        successMessage = "Passcode saved successfully!"
                        passcode = ""
                        confirm = ""
                        current = ""
                        // Clear success message after 3 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            successMessage = nil
                        }
                        // Haptic + alert then auto-dismiss
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        showSavedAlert = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            dismiss()
                        }
                    } catch let caughtError {
                        print("🔐 SetPasscodeView: Failed to save passcode: \(caughtError)")
                        self.error = (caughtError as? LockManager.PasscodeError)?.localizedDescription ?? "Failed to save passcode"
                        successMessage = nil
                    }
                }
                .disabled(passcode.count < 4 || passcode != confirm || (lockManager.hasPasscode() && current.count < 4))
            }

            Section(header: Text("Remove Limmi Passcode")) {
                Button(role: .destructive) {
                    do { try lockManager.removePasscode(current: current) } catch let caughtError {
                        self.error = (caughtError as? LockManager.PasscodeError)?.localizedDescription ?? "Failed to remove passcode"
                    }
                } label: {
                    Text("Remove Limmi Passcode")
                }

                // Forgot passcode flow - wipe without current
                Button(role: .destructive) {
                    showForceResetAlert = true
                } label: {
                    Text("Forgot passcode? Reset without current")
                }
            }
        }
        .navigationTitle("App Lock")
        .alert(isPresented: $showSavedAlert) {
            Alert(
                title: Text("Passcode Saved"),
                message: Text("Your Limmi passcode has been saved."),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Reset Passcode?", isPresented: $showForceResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                do {
                    try lockManager.setPasscode(nil)
                    successMessage = "Passcode has been reset."
                    error = nil
                } catch let caughtError {
                    print("🔐 SetPasscodeView: Failed to reset passcode: \(caughtError)")
                    error = "Failed to reset passcode"
                    successMessage = nil
                }
            }
        } message: {
            Text("This will remove your Limmi passcode immediately. You can set a new one after.")
        }

        .onChange(of: passcode) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            passcode = String(filtered.prefix(12))
        }
        .onChange(of: confirm) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            confirm = String(filtered.prefix(12))
        }
        .onChange(of: current) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            current = String(filtered.prefix(12))
        }
    }
}



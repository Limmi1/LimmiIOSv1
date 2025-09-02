import SwiftUI

struct LockScreenView: View {
    @ObservedObject private var lockManager = LockManager.shared
    @StateObject private var appSettings = AppSettings.shared
    @State private var passcodeInput: String = ""
    @State private var showError: Bool = false
    @State private var showPasscodeUI: Bool = false
    @State private var biometricAttempted: Bool = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Spacer()
                Image("yellowbrainblacklinedots copy")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                Text("Unlock Limmi")
                    .font(.title2)
                    .fontWeight(.semibold)

                // Face ID removed; passcode only
                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .onAppear {
            // Present passcode immediately on appear
            showPasscodeUI = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            // On return to active while locked, present passcode sheet again
            if newPhase == .active && lockManager.isLocked {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showPasscodeUI = true
                }
            }
        }
        // Present passcode as a modal sheet to avoid disrupting the lock screen layout
        .sheet(isPresented: $showPasscodeUI) {
            PasscodePromptView {
                showPasscodeUI = false
            }
        }
    }
}



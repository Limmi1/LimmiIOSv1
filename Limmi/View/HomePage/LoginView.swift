import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var mode: AuthMode = .login
    @State private var legalAccepted = false
    @State private var showLegalModal = false
    @State private var legalModalType: LegalModalType = .betaAgreement
    @FocusState private var focusedField: Field?
    
    enum AuthMode: String, CaseIterable, Identifiable {
        case login = "Login"
        case signup = "Sign Up"
        var id: String { rawValue }
    }
    enum Field: Hashable {
        case email, password
    }
    
    enum LegalModalType {
        case betaAgreement
        case privacyNotice
    }

    var body: some View {
        ZStack {
            DesignSystem.subtleYellowBackground.ignoresSafeArea()
            VStack(spacing: DesignSystem.spacingXXL) {
                Spacer()
                // Logo or App Name
                VStack(spacing: DesignSystem.spacingS) {
                    Image("yellowbrainblacklinedots copy 1")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                    Text("Welcome to Limmi")
                        .font(DesignSystem.headingLarge)
                        .foregroundColor(DesignSystem.pureBlack)
                }
                // Mode Picker
                Picker("Mode", selection: $mode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, DesignSystem.spacingXL)
                // Input Fields
                VStack(spacing: DesignSystem.spacingL) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                        .font(DesignSystem.bodyText)
                        .foregroundColor(DesignSystem.pureBlack)
                        .padding(DesignSystem.spacingL)
                        .background(DesignSystem.pureWhite)
                        .cornerRadius(DesignSystem.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                                .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: DesignSystem.borderWidth)
                        )
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                    
                    HStack {
                        if showPassword {
                            TextField("Password", text: $password)
                                .textContentType(.password)
                        } else {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                        }
                    }
                    .font(DesignSystem.bodyText)
                    .foregroundColor(DesignSystem.pureBlack)
                    .padding(DesignSystem.spacingL)
                    .background(DesignSystem.pureWhite)
                    .cornerRadius(DesignSystem.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.cornerRadius)
                            .stroke(DesignSystem.secondaryBlue.opacity(0.3), lineWidth: DesignSystem.borderWidth)
                    )
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                }
                .padding(.horizontal, DesignSystem.spacingXL)
                
                // Legal Agreement Checkbox (Sign Up only)
                if mode == .signup {
                    HStack(spacing: DesignSystem.spacingM) {
                        Button(action: {
                            legalAccepted.toggle()
                        }) {
                            Image(systemName: legalAccepted ? "checkmark.square.fill" : "square")
                                .font(.system(size: 20))
                                .foregroundColor(legalAccepted ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.6))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 0) {
                                Text("I agree to the ")
                                    .font(DesignSystem.bodyTextSmall)
                                    .foregroundColor(DesignSystem.pureBlack)
                                
                                Button("Beta Tester Agreement") {
                                    legalModalType = .betaAgreement
                                    showLegalModal = true
                                }
                                .font(DesignSystem.bodyTextSmall)
                                .foregroundColor(DesignSystem.secondaryBlue)
                                .underline()
                            }
                            
                            HStack(spacing: 0) {
                                Text("and ")
                                    .font(DesignSystem.bodyTextSmall)
                                    .foregroundColor(DesignSystem.pureBlack)
                                
                                Button("Privacy Notice") {
                                    legalModalType = .privacyNotice
                                    showLegalModal = true
                                }
                                .font(DesignSystem.bodyTextSmall)
                                .foregroundColor(DesignSystem.secondaryBlue)
                                .underline()
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.spacingXL)
                }
                
                // Error Message
                if let error = authViewModel.errorMessage {
                    Text(error)
                        .font(DesignSystem.bodyTextSmall)
                        .foregroundColor(DesignSystem.mutedRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignSystem.spacingXL)
                }
                // Forgot Password (Login only)
                if mode == .login {
                    Button("Forgot password?") {
                        // TODO: Implement password reset
                    }
                    .font(DesignSystem.captionText)
                    .foregroundColor(DesignSystem.secondaryBlue)
                }
                // Main Action Button
                Button(action: {
                    hideKeyboard()
                    
                    // Track authentication attempts
                    AnalyticsManager.shared.logEvent("auth_attempt", parameters: [
                        "type": mode.rawValue.lowercased()
                    ])
                    
                    if mode == .login {
                        authViewModel.signIn(email: email, password: password)
                    } else {
                        authViewModel.signUp(email: email, password: password, legalAccepted: legalAccepted)
                    }
                }) {
                    if authViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.pureBlack))
                            .frame(maxWidth: .infinity)
                            .frame(height: DesignSystem.buttonHeight)
                    } else {
                        Text(mode == .login ? "Login" : "Sign Up")
                            .font(DesignSystem.bodyText)
                            .fontWeight(.semibold)
                            .foregroundColor(DesignSystem.pureBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: DesignSystem.buttonHeight)
                            .background(DesignSystem.primaryYellow)
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
                }
                .disabled(authViewModel.isLoading || (mode == .signup && !legalAccepted))
                .padding(.horizontal, DesignSystem.spacingXL)
                Spacer()
            }
        }
        .onTapGesture { hideKeyboard() }
        .trackScreen("Login", screenClass: "LoginView")
        .onChange(of: mode) { oldMode, newMode in
            // Track auth mode changes
            AnalyticsManager.shared.logEvent("auth_mode_changed", parameters: [
                "mode": newMode.rawValue.lowercased()
            ])
        }
                        .sheet(isPresented: $showLegalModal) {
                    LegalModal(
                        title: legalModalType == .betaAgreement ? "Beta Tester Agreement (Private Evaluation)" : "Privacy Notice",
                        content: loadLegalContent(),
                        onAccept: {
                            showLegalModal = false
                        },
                        onCancel: {
                            showLegalModal = false
                        },
                        requiresAcceptance: legalModalType == .betaAgreement,
                        onScrollComplete: nil
                    )
                }
    }

    private func hideKeyboard() {
        focusedField = nil
    }
    
    private func loadLegalContent() -> String {
        let fileName = legalModalType == .betaAgreement ? LegalConstants.betaTesterAgreementPath : "PrivacyNotice"
        let documentName = legalModalType == .betaAgreement ? "Beta Tester Agreement" : "Privacy Notice"
        
        guard let path = Bundle.main.path(forResource: fileName, ofType: "md"),
              let content = try? String(contentsOfFile: path) else {
            return "\(documentName) content could not be loaded."
        }
        return content
    }
}

#Preview {
    LoginView().environmentObject(AuthViewModel())
} 
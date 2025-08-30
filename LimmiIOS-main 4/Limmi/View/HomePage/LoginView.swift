import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var mode: AuthMode = .login
    @FocusState private var focusedField: Field?
    
    enum AuthMode: String, CaseIterable, Identifiable {
        case login = "Login"
        case signup = "Sign Up"
        var id: String { rawValue }
    }
    enum Field: Hashable {
        case email, password
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(spacing: 32) {
                Spacer()
                // Logo or App Name
                VStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.accentColor)
                    Text("Welcome to Limmi")
                        .font(.title)
                        .fontWeight(.bold)
                }
                // Mode Picker
                Picker("Mode", selection: $mode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                // Input Fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
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
                                .foregroundColor(.gray)
                        }
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($focusedField, equals: .password)
                    .submitLabel(.done)
                }
                .padding(.horizontal)
                // Error Message
                if let error = authViewModel.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                // Forgot Password (Login only)
                if mode == .login {
                    Button("Forgot password?") {
                        // TODO: Implement password reset
                    }
                    .font(.footnote)
                    .foregroundColor(.accentColor)
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
                        authViewModel.signUp(email: email, password: password)
                    }
                }) {
                    if authViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text(mode == .login ? "Login" : "Sign Up")
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .disabled(authViewModel.isLoading)
                .padding(.horizontal)
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
    }

    private func hideKeyboard() {
        focusedField = nil
    }
}

#Preview {
    LoginView().environmentObject(AuthViewModel())
} 
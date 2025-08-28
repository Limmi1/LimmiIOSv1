//
//  AuthViewModel.swift
//  Limmi
//
//  Purpose: Firebase authentication state management for user login and session handling
//  Dependencies: Foundation, FirebaseAuth
//  Related: LimmiApp.swift, LoginView.swift, Firebase user session management
//

import Foundation
import FirebaseAuth

/// Firebase authentication view model managing user authentication state.
///
/// This class provides a reactive interface to Firebase Auth for the SwiftUI app,
/// handling user authentication lifecycle and publishing state changes.
///
/// ## Authentication Flow
/// 1. User enters credentials in LoginView
/// 2. AuthViewModel handles Firebase Auth API calls
/// 3. Authentication state changes are published automatically
/// 4. LimmiApp reacts to user state changes for navigation
///
/// ## State Management
/// - **user**: Current authenticated user (nil if signed out)
/// - **isLoading**: Authentication operation in progress
/// - **errorMessage**: User-facing error messages for failed operations
///
/// ## Automatic State Restoration
/// Firebase Auth automatically restores user sessions on app launch,
/// enabling seamless login persistence across app launches.
///
/// - Important: Must be used on MainActor due to @Published properties
/// - Since: 1.0
class AuthViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// Current authenticated Firebase user.
    /// Nil when user is signed out, populated when authentication succeeds.
    @Published var user: User?
    
    /// User-facing error message for authentication failures.
    /// Automatically cleared on successful operations.
    @Published var errorMessage: String?
    
    /// Indicates if an authentication operation is in progress.
    /// Used to show loading states in UI.
    @Published var isLoading: Bool = false

    // MARK: - Initialization
    
    init() {
        // Restore existing session if available
        self.user = Auth.auth().currentUser
        
        // Listen for authentication state changes
        Auth.auth().addStateDidChangeListener { _, user in
            DispatchQueue.main.async {
                self.user = user
                
                // Set analytics user ID for User Snapshots and better tracking
                AnalyticsManager.shared.setUserId(user?.uid)
                
                if user != nil {
                    // Track successful authentication
                    AnalyticsManager.shared.logEvent("user_authenticated")
                }
            }
        }
    }

    // MARK: - Authentication Methods
    
    /// Signs in user with email and password.
    ///
    /// Handles Firebase authentication and updates published state.
    /// Shows loading state during operation and error messages on failure.
    ///
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    func signIn(email: String, password: String) {
        clearError()
        isLoading = true
        
        Auth.auth().signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.user = result?.user
                }
            }
        }
    }

    /// Creates new user account with email and password.
    ///
    /// Registers new user with Firebase Auth and automatically signs them in.
    /// Shows loading state during operation and error messages on failure.
    ///
    /// - Parameters:
    ///   - email: New user's email address
    ///   - password: New user's password
    func signUp(email: String, password: String) {
        clearError()
        isLoading = true
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    self?.errorMessage = error.localizedDescription
                } else {
                    self?.user = result?.user
                }
            }
        }
    }

    /// Signs out the current user.
    ///
    /// Clears user session and returns to unauthenticated state.
    /// Errors are rare but captured for user feedback.
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.user = nil
            
            // Clear analytics user ID on logout
            AnalyticsManager.shared.setUserId(nil)
            
            clearError()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Private Methods
    
    /// Clears any existing error message.
    private func clearError() {
        errorMessage = nil
    }
} 
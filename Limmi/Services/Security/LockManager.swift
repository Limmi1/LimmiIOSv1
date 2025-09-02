//
//  LockManager.swift
//  Limmi
//
//  Manages App Lock (passcode + biometrics) using Keychain and LocalAuthentication.
//

import Foundation
import LocalAuthentication
import Security

final class LockManager: ObservableObject {
    static let shared = LockManager()

    fileprivate enum KeychainKeys {
        static let passcode = "com.limmi.applock.passcode"
        static let service = "com.ah.limmi.app.applock"
    }

    @Published var isLocked: Bool = false
    @Published var isAuthenticating: Bool = false
    private var lastPromptAt: Date?
    private var lastUnlockAt: Date?
    private let relockGraceInterval: TimeInterval = 2.0
    // MARK: - Passcode constraints
    private let minPasscodeLength: Int = 4
    private let maxPasscodeLength: Int = 12

    enum PasscodeError: LocalizedError {
        case noPasscodeSet
        case incorrectCurrent
        case invalidLength
        case mismatch
        case unknown

        var errorDescription: String? {
            switch self {
            case .noPasscodeSet: return "No passcode is currently set."
            case .incorrectCurrent: return "Current passcode is incorrect."
            case .invalidLength: return "Passcode must be 4-12 digits."
            case .mismatch: return "New passcodes do not match."
            case .unknown: return "An unknown error occurred."
            }
        }
    }


    private init() {}

    // Normalize passcode for consistent storage and compare
    private func normalizePasscode(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep digits only to avoid invisible characters from keyboards
        let digitsOnly = trimmed.filter { $0.isNumber }
        return digitsOnly.isEmpty ? nil : digitsOnly
    }

    // MARK: - Public API

    func setPasscode(_ passcode: String?) throws {
        if let normalized = normalizePasscode(passcode), let data = normalized.data(using: .utf8) {
            guard (minPasscodeLength...maxPasscodeLength).contains(normalized.count) else { throw PasscodeError.invalidLength }
            try KeychainHelper.save(key: KeychainKeys.passcode, data: data)
            print("🔐 LockManager: Passcode set successfully")
            isLocked = true
        } else {
            try KeychainHelper.delete(key: KeychainKeys.passcode)
            print("🔐 LockManager: Passcode removed")
            isLocked = false
        }
    }

    /// Change existing passcode by verifying current and confirming new
    func changePasscode(current: String, new: String, confirm: String) throws {
        guard hasPasscode() else { throw PasscodeError.noPasscodeSet }
        guard validatePasscode(current) else { throw PasscodeError.incorrectCurrent }
        guard let normalizedNew = normalizePasscode(new),
              let normalizedConfirm = normalizePasscode(confirm) else { throw PasscodeError.invalidLength }
        guard (minPasscodeLength...maxPasscodeLength).contains(normalizedNew.count) else { throw PasscodeError.invalidLength }
        guard normalizedNew == normalizedConfirm else { throw PasscodeError.mismatch }
        try setPasscode(normalizedNew)
    }

    /// Remove passcode after verifying current value
    func removePasscode(current: String) throws {
        guard hasPasscode() else { throw PasscodeError.noPasscodeSet }
        guard validatePasscode(current) else { throw PasscodeError.incorrectCurrent }
        try setPasscode(nil)
    }

    func hasPasscode() -> Bool {
        return (try? KeychainHelper.load(key: KeychainKeys.passcode)) != nil
    }

    func validatePasscode(_ input: String) -> Bool {
        guard let normalizedInput = normalizePasscode(input),
              let data = try? KeychainHelper.load(key: KeychainKeys.passcode),
              let stored = String(data: data, encoding: .utf8) else {
            print("🔐 LockManager: No passcode found in keychain")
            return false 
        }
        let isValid = stored == normalizedInput
        print("🔐 LockManager: Passcode validation - Input(normalized): '\(normalizedInput)', Stored: '\(stored)', Valid: \(isValid)")
        return isValid
    }

    func lock() {
        // Always enforce lock if a Limmi passcode exists
        guard hasPasscode() else { isLocked = false; return }
        isLocked = true
    }

    func unlockWithBiometrics(reason: String = "Unlock Limmi") async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Limmi Passcode" // Clarify it's Limmi's passcode, not device passcode
        var authError: NSError?
        // Use .deviceOwnerAuthenticationWithBiometrics to require biometrics only (no device passcode fallback)
        let policy: LAPolicy = .deviceOwnerAuthenticationWithBiometrics
        guard context.canEvaluatePolicy(policy, error: &authError) else {
            print("🔒 LockManager: Cannot evaluate biometric policy: \(authError?.localizedDescription ?? "Unknown error")")
            return false
        }
        do {
            try await context.evaluatePolicy(policy, localizedReason: reason)
            await MainActor.run { self.markUnlocked() }
            print("🔓 LockManager: Biometric unlock successful")
            return true
        } catch let error as LAError {
            print("🔒 LockManager: Biometric error: \(error.localizedDescription)")
            switch error.code {
            case .biometryLockout, .biometryNotAvailable, .biometryNotEnrolled:
                return false
            case .systemCancel, .appCancel, .userCancel:
                return false
            case .userFallback:
                // User chose to use passcode instead of biometrics
                print("🔒 LockManager: User chose to use passcode instead of biometrics")
                return false
            default:
                return false
            }
        } catch {
            print("🔒 LockManager: Unexpected error: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func tryBiometricUnlockIfNeeded(useBiometrics: Bool, reason: String = "Unlock Limmi") async -> Bool {
        guard useBiometrics else { return false }
        guard hasPasscode(), isLocked else { return false }
        if isAuthenticating { return false }
        let now = Date()
        if let last = lastPromptAt, now.timeIntervalSince(last) < 1.5 { return false }
        isAuthenticating = true
        lastPromptAt = now
        let success = await unlockWithBiometrics(reason: reason)
        isAuthenticating = false
        if !success {
            // Keep locked; user can enter passcode or retry
        }
        return success
    }

    @MainActor
    func markUnlocked() {
        isLocked = false
        lastUnlockAt = Date()
    }
}

// MARK: - Simple Keychain wrapper

enum KeychainHelper {
    static func save(key: String, data: Data) throws {
        try delete(key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: LockManager.KeychainKeys.service,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load(key: String) throws -> Data? {
        let queryWithService: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: LockManager.KeychainKeys.service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        var status = SecItemCopyMatching(queryWithService as CFDictionary, &item)
        if status == errSecItemNotFound {
            // Backwards-compatibility: try without service if older entry exists
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            status = SecItemCopyMatching(legacyQuery as CFDictionary, &item)
        }
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        return item as? Data
    }

    static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: LockManager.KeychainKeys.service
        ]
        var status = SecItemDelete(query as CFDictionary)
        if status == errSecItemNotFound {
            // Also attempt legacy delete without service attribute
            let legacyQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key
            ]
            status = SecItemDelete(legacyQuery as CFDictionary)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}



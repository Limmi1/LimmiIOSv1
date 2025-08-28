import SwiftUI
import FamilyControls
import Combine
import os

/// Shared view model for rule creation and editing operations
/// Handles app selection, metadata extraction, and rule persistence
@MainActor
final class RuleFormViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var rule: Rule
    @Published var selectedTokens: [BlockedToken] = []
    @Published var familySelection = FamilyActivitySelection()
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let ruleStoreViewModel: RuleStoreViewModel
    private let mode: FormMode
    private var cancellables = Set<AnyCancellable>()
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "RuleFormViewModel")
    )
    
    // MARK: - Types
    
    enum FormMode {
        case creation
        case editing(originalRule: Rule)
        
        var isEditing: Bool {
            if case .editing = self { return true }
            return false
        }
    }
    
    // MARK: - Initialization
    
    init(mode: FormMode, ruleStoreViewModel: RuleStoreViewModel) {
        self.mode = mode
        self.ruleStoreViewModel = ruleStoreViewModel
        
        switch mode {
        case .creation:
            self.rule = Rule(name: "")
        case .editing(let originalRule):
            self.rule = originalRule
        }
        
        // Load existing tokens if editing
        if mode.isEditing {
            loadExistingTokens()
        }
    }
    
    // MARK: - Public Methods
    
    /// Converts current FamilyActivitySelection to BlockedTokens with metadata
    func updateTokensFromSelection() {
        logger.debug("Converting family activity selection to blocked tokens")
        
        var tokens: [BlockedToken] = []
        
        // Convert application tokens with metadata from selection.applications
        for appToken in familySelection.applicationTokens {
            if let app = familySelection.applications.first(where: { $0.token == appToken }) {
                let displayName = app.localizedDisplayName ?? "Unknown App"
                let bundleId = app.bundleIdentifier
                let token = BlockedToken(applicationToken: appToken, displayName: displayName, bundleIdentifier: bundleId)
                tokens.append(token)
            } else {
                let token = BlockedToken(applicationToken: appToken, displayName: "Unknown App", bundleIdentifier: nil)
                tokens.append(token)
            }
        }
        
        // Convert activity category tokens with metadata from selection.categories
        for categoryToken in familySelection.categoryTokens {
            if let category = familySelection.categories.first(where: { $0.token == categoryToken }) {
                let displayName = category.localizedDisplayName ?? "Unknown Category"
                let token = BlockedToken(activityCategoryToken: categoryToken, displayName: displayName)
                tokens.append(token)
            } else {
                let token = BlockedToken(activityCategoryToken: categoryToken, displayName: "Unknown Category")
                tokens.append(token)
            }
        }
        
        // Convert web domain tokens with metadata from selection.webDomains
        for webToken in familySelection.webDomainTokens {
            if let webDomain = familySelection.webDomains.first(where: { $0.token == webToken }) {
                let domain = webDomain.domain ?? "Unknown Domain"
                let token = BlockedToken(webDomainToken: webToken, domain: domain)
                tokens.append(token)
            } else {
                let token = BlockedToken(webDomainToken: webToken, domain: "Unknown Domain")
                tokens.append(token)
            }
        }
        
        selectedTokens = tokens
        logger.debug("Converted to \(tokens.count) blocked tokens")
    }
    
    /// Saves the rule (creates new or updates existing)
    func saveRule() async -> Result<Rule, Error> {
        isSaving = true
        errorMessage = nil
        
        // Update rule with selected tokens - save tokens first, then get their IDs
        let result = await saveTokensAndUpdateRule()
        
        isSaving = false
        return result
    }
    
    /// Validates the current rule state
    var isValid: Bool {
        !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Gets the current form title
    var formTitle: String {
        switch mode {
        case .creation:
            return "Create Rule"
        case .editing:
            return "Edit Rule"
        }
    }
    
    /// Gets the current save button title
    var saveButtonTitle: String {
        switch mode {
        case .creation:
            return "Create Rule"
        case .editing:
            return "Save Changes"
        }
    }
    
    // MARK: - Private Methods
    
    /// Loads existing tokens for editing mode
    private func loadExistingTokens() {
        guard case .editing = mode else { return }
        guard !rule.blockedTokenIds.isEmpty else {
            logger.debug("No blocked tokens to load for rule")
            return
        }
        
        isLoading = true
        logger.debug("Loading \(rule.blockedTokenIds.count) existing blocked tokens")
        
        // Get the blocked tokens from the rule store
        let blockedTokenInfos = ruleStoreViewModel.getBlockedTokens(byIds: rule.blockedTokenIds)
        logger.debug("Found \(blockedTokenInfos.count) blocked token objects")
        
        // Convert BlockedTokenInfos back to FamilyActivitySelection
        familySelection = FamilyActivitySelection.from(blockedTokens: blockedTokenInfos)
        
        // Also create BlockedTokens for local display
        var tokens: [BlockedToken] = []
        for tokenInfo in blockedTokenInfos {
            switch tokenInfo.tokenType {
            case "application":
                if let appToken = tokenInfo.decodedApplicationToken() {
                    let token = BlockedToken(applicationToken: appToken, displayName: tokenInfo.displayName, bundleIdentifier: tokenInfo.bundleIdentifier)
                    tokens.append(token)
                }
            case "webDomain":
                if let webToken = tokenInfo.decodedWebDomainToken() {
                    let token = BlockedToken(webDomainToken: webToken, domain: tokenInfo.displayName)
                    tokens.append(token)
                }
            case "activityCategory":
                if let categoryToken = tokenInfo.decodedActivityCategoryToken() {
                    let token = BlockedToken(activityCategoryToken: categoryToken, displayName: tokenInfo.displayName)
                    tokens.append(token)
                }
            default:
                break
            }
        }
        
        selectedTokens = tokens
        isLoading = false
        
        logger.debug("Loaded selection: \(familySelection.applicationTokens.count) apps, \(familySelection.webDomainTokens.count) domains, \(familySelection.categoryTokens.count) categories")
    }
    
    /// Saves tokens to Firebase and updates rule with their IDs
    private func saveTokensAndUpdateRule() async -> Result<Rule, Error> {
        // First save the blocked tokens if we have any
        var tokenIds: [String] = []
        
        if !selectedTokens.isEmpty {
            logger.debug("Saving \(selectedTokens.count) blocked tokens")
            
            let tokenSaveResult = await withCheckedContinuation { continuation in
                ruleStoreViewModel.saveBlockedTokensAsBlockedTokenInfo(selectedTokens) { result in
                    continuation.resume(returning: result)
                }
            }
            
            switch tokenSaveResult {
            case .success(let savedTokenIds):
                tokenIds = savedTokenIds
                logger.debug("Saved \(tokenIds.count) token IDs")
            case .failure(let error):
                logger.error("Failed to save blocked tokens: \(error.localizedDescription)")
                return .failure(error)
            }
        }
        
        // Update rule with token IDs
        rule.blockedTokenIds = tokenIds
        rule.dateModified = Date()
        
        // Save or update the rule
        let ruleResult = await withCheckedContinuation { continuation in
            switch mode {
            case .creation:
                ruleStoreViewModel.addRule(rule) { result in
                    continuation.resume(returning: result)
                }
            case .editing:
                ruleStoreViewModel.updateRule(rule) { result in
                    continuation.resume(returning: result)
                }
            }
        }
        
        switch ruleResult {
        case .success(let savedRule):
            logger.debug("Successfully saved rule: \(savedRule.name)")
            rule = savedRule
            return .success(savedRule)
        case .failure(let error):
            logger.error("Failed to save rule: \(error.localizedDescription)")
            errorMessage = "Failed to save rule: \(error.localizedDescription)"
            return .failure(error)
        }
    }
}
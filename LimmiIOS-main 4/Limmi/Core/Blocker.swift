//
//  Blocker.swift
//  Limmi
//
//  Purpose: App blocking abstractions and Screen Time API integration
//  Dependencies: FamilyControls, ManagedSettings, Combine
//  Related: BlockingEngine.swift, ScreenTimeBlocker implementation
//

import Foundation
import FamilyControls
import ManagedSettings
import Combine
import os

// 1. Add the AuthorizationStatus enum
public enum AuthorizationStatus {
    case notDetermined
    case denied
    case approved
}

/// Protocol for token blocking services with Screen Time API integration.
///
/// This protocol abstracts token blocking operations to enable:
/// - Testability through mock implementations
/// - Flexibility to switch between blocking strategies
/// - Clean separation between business logic and platform APIs
///
/// ## Implementation Notes
/// - Production implementation uses Screen Time's ManagedSettings API
/// - Test implementation provides in-memory blocking simulation
/// - All methods are safe to call from any thread
///
/// ## Authorization
/// Blocking requires FamilyControls authorization which must be requested
/// before any blocking operations can succeed.
///
/// - Since: 1.0
protocol Blocker {
    /// Blocks a specific token by its Firebase document ID.
    /// - Parameter tokenId: Firebase document ID of the token to block
    func blockToken(tokenId: String)
    
    /// Blocks multiple tokens by their Firebase document IDs.
    /// - Parameter tokenIds: Array of Firebase document IDs to block
    func blockTokens(tokenIds: [String])
    
    /// Blocks tokens using Screen Time tokens directly.
    /// - Parameter tokens: Array of BlockedToken objects for immediate blocking
    func blockTokens(tokens: [BlockedToken])
    
    /// Blocks apps using Screen Time application tokens directly.
    /// - Parameter tokens: Set of ApplicationToken objects for immediate blocking
    func blockApps(tokens: Set<ApplicationToken>)
    
    /// Blocks web domains using Screen Time web domain tokens directly.
    /// - Parameter tokens: Set of WebDomainToken objects for immediate blocking
    func blockWebDomains(tokens: Set<WebDomainToken>)
    
    /// Blocks activity categories using Screen Time activity category tokens directly.
    /// - Parameter tokens: Set of ActivityCategoryToken objects for immediate blocking
    func blockActivityCategories(tokens: Set<ActivityCategoryToken>)
    
    /// Unblocks a specific token by its Firebase document ID.
    /// - Parameter tokenId: Firebase document ID of the token to unblock
    func unblockToken(tokenId: String)
    
    /// Unblocks multiple tokens by their Firebase document IDs.
    /// - Parameter tokenIds: Array of Firebase document IDs to unblock
    func unblockTokens(tokenIds: [String])
    
    /// Removes all blocking restrictions.
    /// Useful for emergency unblock or system reset scenarios.
    func unblockAllTokens()
    
    /// Returns Firebase document IDs of currently blocked tokens.
    /// - Returns: Array of token IDs that are currently blocked
    func blockedTokenIds() -> [String]
    
    /// Returns Screen Time application tokens that are currently blocked.
    /// - Returns: Set of ApplicationToken objects under active restrictions
    func blockedApplicationTokens() -> Set<ApplicationToken>
    
    /// Returns Screen Time web domain tokens that are currently blocked.
    /// - Returns: Set of WebDomainToken objects under active restrictions
    func blockedWebDomainTokens() -> Set<WebDomainToken>
    
    /// Returns Screen Time activity category tokens that are currently blocked.
    /// - Returns: Set of ActivityCategoryToken objects under active restrictions
    func blockedActivityCategoryTokens() -> Set<ActivityCategoryToken>
    
    /// Checks if a specific token is currently blocked.
    /// - Parameter tokenId: Firebase document ID to check
    /// - Returns: True if the token is currently blocked
    func isTokenBlocked(tokenId: String) -> Bool
    
    /// Checks if an application token is currently blocked.
    /// - Parameter token: ApplicationToken to check
    /// - Returns: True if the token is currently blocked
    func isApplicationTokenBlocked(token: ApplicationToken) -> Bool
    
    /// Checks if a web domain token is currently blocked.
    /// - Parameter token: WebDomainToken to check
    /// - Returns: True if the token is currently blocked
    func isWebDomainTokenBlocked(token: WebDomainToken) -> Bool
    
    /// Checks if an activity category token is currently blocked.
    /// - Parameter token: ActivityCategoryToken to check
    /// - Returns: True if the token is currently blocked
    func isActivityCategoryTokenBlocked(token: ActivityCategoryToken) -> Bool
    
    /// Requests FamilyControls authorization for Screen Time access.
    /// Must be called before any blocking operations will succeed.
    /// - Parameter completion: Result callback with success or specific error
    func requestAuthorization()
    
    /// Publisher that emits blocking state changes for reactive UI updates.
    /// Emits whenever blocking restrictions are added, removed, or modified.
    var blockingStatePublisher: AnyPublisher<BlockingState, Never> { get }
    
    /// Sets the mapping between Firebase token IDs and Screen Time tokens.
    /// This mapping is essential for converting between business logic IDs and platform tokens.
    /// - Parameter mapping: Dictionary mapping Firebase IDs to BlockedTokens
    func setTokenMapping(_ mapping: [String: BlockedToken])
    
    /// Current state of token blocking restrictions and authorization.
    var authorizationStatus: AuthorizationStatus { get }
}

/// Current state of token blocking restrictions and authorization.
///
/// This struct provides a snapshot of the blocking system state at a point in time.
/// Used for reactive UI updates and debugging blocked token status.
struct BlockingState {
    /// Firebase document IDs of tokens currently under blocking restrictions.
    let blockedTokenIds: [String]
    
    /// Screen Time application tokens currently under blocking restrictions.
    let blockedApplicationTokens: Set<ApplicationToken>
    
    /// Screen Time web domain tokens currently under blocking restrictions.
    let blockedWebDomainTokens: Set<WebDomainToken>
    
    /// Screen Time activity category tokens currently under blocking restrictions.
    let blockedActivityCategoryTokens: Set<ActivityCategoryToken>
    
    /// Whether FamilyControls authorization has been granted.
    let isAuthorized: Bool
    
    /// Timestamp when this state snapshot was created.
    let lastUpdated: Date
    
    init(
        blockedTokenIds: [String] = [], 
        blockedApplicationTokens: Set<ApplicationToken> = [], 
        blockedWebDomainTokens: Set<WebDomainToken> = [],
        blockedActivityCategoryTokens: Set<ActivityCategoryToken> = [],
        isAuthorized: Bool = false
    ) {
        self.blockedTokenIds = blockedTokenIds
        self.blockedApplicationTokens = blockedApplicationTokens
        self.blockedWebDomainTokens = blockedWebDomainTokens
        self.blockedActivityCategoryTokens = blockedActivityCategoryTokens
        self.isAuthorized = isAuthorized
        self.lastUpdated = Date()
    }
}

/// Errors that can occur during blocking operations
enum BlockingError: Error, LocalizedError {
    case authorizationDenied
    case authorizationFailed(String)
    case appNotFound(String)
    case tokenNotFound
    case blockingFailed(String)
    case unblockingFailed(String)
    case invalidAppId(String)
    
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Screen Time authorization denied"
        case .authorizationFailed(let message):
            return "Authorization failed: \(message)"
        case .appNotFound(let appId):
            return "App not found: \(appId)"
        case .tokenNotFound:
            return "Application token not found"
        case .blockingFailed(let message):
            return "Blocking failed: \(message)"
        case .unblockingFailed(let message):
            return "Unblocking failed: \(message)"
        case .invalidAppId(let appId):
            return "Invalid app ID: \(appId)"
        }
    }
}

/// Production implementation of Blocker using Apple's Screen Time API.
///
/// This class integrates with iOS Screen Time framework to provide token blocking
/// functionality. It manages ManagedSettingsStore for applying restrictions
/// and handles the mapping between Firebase token IDs and Screen Time tokens.
///
/// ## Screen Time Integration
/// - Uses ManagedSettingsStore.shield.applications for blocking apps
/// - Uses ManagedSettingsStore.shield.webDomains for blocking web domains with auto setting
/// - Uses ManagedSettingsStore.shield.activityCategories for blocking activity categories
/// - Requires FamilyControls authorization
/// - Blocking is enforced system-wide across all app launches
///
/// ## Token Management
/// - Maintains mapping between Firebase IDs and BlockedTokens
/// - Tokens are obtained during selection process
/// - Invalid tokens are handled gracefully
///
/// ## State Management
/// - Publishes state changes for reactive UI updates
/// - Maintains current blocked token sets in memory
/// - Synchronizes with ManagedSettingsStore on changes
///
/// - Important: Must run on MainActor due to ManagedSettings requirements
/// - Since: 1.0
@MainActor
final class ScreenTimeBlocker: Blocker {
    
    // MARK: - Properties
    
    /// Core blocking utility for actual ManagedSettings operations using shared store.
    private let coreBlockingUtility = CoreBlockingUtility()
    
    /// Subject for publishing blocking state changes to subscribers.
    private let stateSubject = CurrentValueSubject<BlockingState, Never>(BlockingState())
    
    /// Unified logger for debugging Screen Time integration issues.
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "ScreenTimeBlocker")
    )
    
    var blockingStatePublisher: AnyPublisher<BlockingState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Set of application tokens currently blocked via ManagedSettings.
    private var currentBlockedApplicationTokens: Set<ApplicationToken> = []
    
    /// Set of web domain tokens currently blocked via ManagedSettings.
    private var currentBlockedWebDomainTokens: Set<WebDomainToken> = []
    
    /// Set of activity category tokens currently blocked via ManagedSettings.
    private var currentBlockedActivityCategoryTokens: Set<ActivityCategoryToken> = []
    
    /// Mapping from Firebase token document IDs to Screen Time blocked tokens.
    private var tokenIdToTokenMapping: [String: BlockedToken] = [:]
    
    // 3. Implement authorizationStatus and requestAuthorization in ScreenTimeBlocker
    private var _authorizationStatus: AuthorizationStatus = .notDetermined
    
    var authorizationStatus: AuthorizationStatus {
        _authorizationStatus
    }
    
    // MARK: - Initialization
    
    init() {
        logger.debug("ScreenTimeBlocker initialized")
        updateAuthorizationStatus()
    }
    
    /// Updates the current authorization status from AuthorizationCenter
    private func updateAuthorizationStatus() {
        let currentStatus = AuthorizationCenter.shared.authorizationStatus
        switch currentStatus {
        case .notDetermined:
            _authorizationStatus = .notDetermined
        case .denied:
            _authorizationStatus = .denied
        case .approved:
            _authorizationStatus = .approved
        @unknown default:
            _authorizationStatus = .notDetermined
        }
        logger.debug("Authorization status updated to: \(_authorizationStatus)")
    }
    
    // MARK: - Blocker Implementation
    
    func blockToken(tokenId: String) {
        blockTokens(tokenIds: [tokenId])
    }
    
    /// Blocks multiple tokens by converting Firebase IDs to Screen Time tokens.
    ///
    /// Looks up blocked tokens for the provided token IDs and applies blocking
    /// via the Screen Time API. Tokens without valid mapping are silently ignored.
    ///
    /// - Parameter tokenIds: Firebase document IDs of tokens to block
    func blockTokens(tokenIds: [String]) {
        let blockedTokens = tokenIds.compactMap { tokenIdToTokenMapping[$0] }
        guard !blockedTokens.isEmpty else { return }
        
        blockTokens(tokens: blockedTokens)
    }
    
    /// Applies blocking restrictions using Screen Time tokens.
    ///
    /// Updates the ManagedSettingsStore to block the specified tokens.
    /// The blocking takes effect immediately and persists until explicitly removed.
    ///
    /// - Parameter tokens: Array of BlockedToken objects to block
    func blockTokens(tokens: [BlockedToken]) {
        guard _authorizationStatus == .approved else {
            return
        }
        
        for token in tokens {
            switch token.type {
            case .application:
                if let appToken = token.applicationToken {
                    currentBlockedApplicationTokens.insert(appToken)
                }
            case .webDomain:
                if let webToken = token.webDomainToken {
                    currentBlockedWebDomainTokens.insert(webToken)
                }
            case .activityCategory:
                if let categoryToken = token.activityCategoryToken {
                    currentBlockedActivityCategoryTokens.insert(categoryToken)
                }
            }
        }
        
        // Apply blocking via CoreBlockingUtility
        coreBlockingUtility.applyBlocking(
            apps: currentBlockedApplicationTokens,
            webDomains: currentBlockedWebDomainTokens,
            categories: currentBlockedActivityCategoryTokens
        )
        
        updateStateSubject()
    }
    
    /// Blocks apps using Screen Time application tokens directly.
    /// - Parameter tokens: Set of ApplicationToken objects for immediate blocking
    func blockApps(tokens: Set<ApplicationToken>) {
        guard _authorizationStatus == .approved else {
            return
        }
        
        currentBlockedApplicationTokens.formUnion(tokens)
        coreBlockingUtility.applyBlocking(apps: currentBlockedApplicationTokens)
        updateStateSubject()
    }
    
    /// Blocks web domains using Screen Time web domain tokens directly.
    /// - Parameter tokens: Set of WebDomainToken objects for immediate blocking
    func blockWebDomains(tokens: Set<WebDomainToken>) {
        guard _authorizationStatus == .approved else {
            return
        }
        
        currentBlockedWebDomainTokens.formUnion(tokens)
        coreBlockingUtility.applyBlocking(webDomains: currentBlockedWebDomainTokens)
        updateStateSubject()
    }
    
    /// Blocks activity categories using Screen Time activity category tokens directly.
    /// - Parameter tokens: Set of ActivityCategoryToken objects for immediate blocking
    func blockActivityCategories(tokens: Set<ActivityCategoryToken>) {
        guard _authorizationStatus == .approved else {
            return
        }
        
        currentBlockedActivityCategoryTokens.formUnion(tokens)
        // Note: ActivityCategory blocking is handled through applications and webDomains with auto policy
        updateStateSubject()
    }
    
    func unblockToken(tokenId: String) {
        unblockTokens(tokenIds: [tokenId])
    }
    
    func unblockTokens(tokenIds: [String]) {
        let blockedTokens = tokenIds.compactMap { tokenIdToTokenMapping[$0] }
        guard !blockedTokens.isEmpty else { return }
        
        for token in blockedTokens {
            switch token.type {
            case .application:
                if let appToken = token.applicationToken {
                    currentBlockedApplicationTokens.remove(appToken)
                }
            case .webDomain:
                if let webToken = token.webDomainToken {
                    currentBlockedWebDomainTokens.remove(webToken)
                }
            case .activityCategory:
                if let categoryToken = token.activityCategoryToken {
                    currentBlockedActivityCategoryTokens.remove(categoryToken)
                }
            }
        }
        
        // Apply updated blocking state via CoreBlockingUtility
        coreBlockingUtility.applyBlocking(
            apps: currentBlockedApplicationTokens,
            webDomains: currentBlockedWebDomainTokens,
            categories: currentBlockedActivityCategoryTokens
        )
        
        updateStateSubject()
    }
    
    func unblockAllTokens() {
        currentBlockedApplicationTokens.removeAll()
        currentBlockedWebDomainTokens.removeAll()
        currentBlockedActivityCategoryTokens.removeAll()
        
        coreBlockingUtility.clearAllBlocking()
        
        updateStateSubject()
    }
    
    func blockedTokenIds() -> [String] {
        return Array(tokenIdToTokenMapping.keys).filter { tokenId in
            guard let token = tokenIdToTokenMapping[tokenId] else { return false }
            switch token.type {
            case .application:
                return token.applicationToken.map { currentBlockedApplicationTokens.contains($0) } ?? false
            case .webDomain:
                return token.webDomainToken.map { currentBlockedWebDomainTokens.contains($0) } ?? false
            case .activityCategory:
                return token.activityCategoryToken.map { currentBlockedActivityCategoryTokens.contains($0) } ?? false
            }
        }
    }
    
    func blockedApplicationTokens() -> Set<ApplicationToken> {
        return currentBlockedApplicationTokens
    }
    
    func blockedWebDomainTokens() -> Set<WebDomainToken> {
        return currentBlockedWebDomainTokens
    }
    
    func blockedActivityCategoryTokens() -> Set<ActivityCategoryToken> {
        return currentBlockedActivityCategoryTokens
    }
    
    func isTokenBlocked(tokenId: String) -> Bool {
        guard let token = tokenIdToTokenMapping[tokenId] else { return false }
        switch token.type {
        case .application:
            return token.applicationToken.map { currentBlockedApplicationTokens.contains($0) } ?? false
        case .webDomain:
            return token.webDomainToken.map { currentBlockedWebDomainTokens.contains($0) } ?? false
        case .activityCategory:
            return token.activityCategoryToken.map { currentBlockedActivityCategoryTokens.contains($0) } ?? false
        }
    }
    
    func isApplicationTokenBlocked(token: ApplicationToken) -> Bool {
        return currentBlockedApplicationTokens.contains(token)
    }
    
    func isWebDomainTokenBlocked(token: WebDomainToken) -> Bool {
        return currentBlockedWebDomainTokens.contains(token)
    }
    
    func isActivityCategoryTokenBlocked(token: ActivityCategoryToken) -> Bool {
        return currentBlockedActivityCategoryTokens.contains(token)
    }
    
    /// Requests FamilyControls authorization for Screen Time access.
    ///
    /// This method must be called before any blocking operations will succeed.
    /// Authorization requires user consent and may present system dialogs.
    ///
    /// - Parameter completion: Callback with authorization result
    func requestAuthorization() {
        Task { @MainActor in
            let currentStatus = AuthorizationCenter.shared.authorizationStatus
            
            switch currentStatus {
            case .notDetermined:
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    self._authorizationStatus = .approved
                } catch {
                    self._authorizationStatus = .denied
                }
            case .denied:
                self._authorizationStatus = .denied
            case .approved:
                self._authorizationStatus = .approved
            @unknown default:
                self._authorizationStatus = .notDetermined
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Updates the mapping between Firebase token IDs and Screen Time tokens.
    ///
    /// This mapping is essential for converting between business logic identifiers
    /// and platform-specific tokens. Called when blocked tokens are loaded from Firebase.
    ///
    /// - Parameter mapping: Dictionary mapping Firebase IDs to BlockedTokens
    func setTokenMapping(_ mapping: [String: BlockedToken]) {
        tokenIdToTokenMapping = mapping
        logger.debug("Updated token mapping with \(mapping.count) entries")
    }
    
    /// Updates the published blocking state for reactive UI updates.
    ///
    /// Creates a new BlockingState snapshot and publishes it to subscribers.
    /// Called whenever blocking restrictions change.
    private func updateStateSubject() {
        let state = BlockingState(
            blockedTokenIds: blockedTokenIds(),
            blockedApplicationTokens: currentBlockedApplicationTokens,
            blockedWebDomainTokens: currentBlockedWebDomainTokens,
            blockedActivityCategoryTokens: currentBlockedActivityCategoryTokens,
            isAuthorized: _authorizationStatus == .approved
        )
        stateSubject.send(state)
    }
}

/// Test implementation of Blocker
final class TestBlocker: Blocker {
    
    // MARK: - Properties
    
    private let stateSubject = CurrentValueSubject<BlockingState, Never>(BlockingState())
    private var _blockedTokenIds: Set<String> = []
    private var blockedAppTokens: Set<ApplicationToken> = []
    private var blockedWebTokens: Set<WebDomainToken> = []
    private var blockedCategoryTokens: Set<ActivityCategoryToken> = []
    private var isAuthorized = true
    
    var blockingStatePublisher: AnyPublisher<BlockingState, Never> {
        stateSubject.eraseToAnyPublisher()
    }
    
    // 2. Update Blocker protocol
    var authorizationStatus: AuthorizationStatus {
        isAuthorized ? .approved : .denied
    }
    
    // MARK: - Blocker Implementation
    
    func blockToken(tokenId: String) {
        _blockedTokenIds.insert(tokenId)
        updateState()
    }
    
    func blockTokens(tokenIds: [String]) {
        _blockedTokenIds.formUnion(tokenIds)
        updateState()
    }
    
    func blockTokens(tokens: [BlockedToken]) {
        // Test implementation - just track by ID
        for token in tokens {
            _blockedTokenIds.insert(token.name)
        }
        updateState()
    }
    
    func blockApps(tokens: Set<ApplicationToken>) {
        blockedAppTokens.formUnion(tokens)
        updateState()
    }
    
    func blockWebDomains(tokens: Set<WebDomainToken>) {
        blockedWebTokens.formUnion(tokens)
        updateState()
    }
    
    func blockActivityCategories(tokens: Set<ActivityCategoryToken>) {
        blockedCategoryTokens.formUnion(tokens)
        updateState()
    }
    
    func unblockToken(tokenId: String) {
        _blockedTokenIds.remove(tokenId)
        updateState()
    }
    
    func unblockTokens(tokenIds: [String]) {
        for tokenId in tokenIds {
            _blockedTokenIds.remove(tokenId)
        }
        updateState()
    }
    
    func unblockAllTokens() {
        _blockedTokenIds.removeAll()
        blockedAppTokens.removeAll()
        blockedWebTokens.removeAll()
        blockedCategoryTokens.removeAll()
        updateState()
    }
    
    func blockedTokenIds() -> [String] {
        return Array(_blockedTokenIds)
    }
    
    func blockedApplicationTokens() -> Set<ApplicationToken> {
        return blockedAppTokens
    }
    
    func blockedWebDomainTokens() -> Set<WebDomainToken> {
        return blockedWebTokens
    }
    
    func blockedActivityCategoryTokens() -> Set<ActivityCategoryToken> {
        return blockedCategoryTokens
    }
    
    func isTokenBlocked(tokenId: String) -> Bool {
        return _blockedTokenIds.contains(tokenId)
    }
    
    func isApplicationTokenBlocked(token: ApplicationToken) -> Bool {
        return blockedAppTokens.contains(token)
    }
    
    func isWebDomainTokenBlocked(token: WebDomainToken) -> Bool {
        return blockedWebTokens.contains(token)
    }
    
    func isActivityCategoryTokenBlocked(token: ActivityCategoryToken) -> Bool {
        return blockedCategoryTokens.contains(token)
    }
    
    func requestAuthorization() {
        if isAuthorized {
            // No-op for test
        } else {
            isAuthorized = true
            updateState()
        }
    }
    
    // MARK: - Test Helper Methods
    
    func setAuthorized(_ authorized: Bool) {
        isAuthorized = authorized
        updateState()
    }
    
    func reset() {
        _blockedTokenIds.removeAll()
        blockedAppTokens.removeAll()
        blockedWebTokens.removeAll()
        blockedCategoryTokens.removeAll()
        isAuthorized = true
        updateState()
    }
    
    // MARK: - Private Methods
    
    private func updateState() {
        let state = BlockingState(
            blockedTokenIds: Array(_blockedTokenIds),
            blockedApplicationTokens: blockedAppTokens,
            blockedWebDomainTokens: blockedWebTokens,
            blockedActivityCategoryTokens: blockedCategoryTokens,
            isAuthorized: isAuthorized
        )
        stateSubject.send(state)
    }
    
    func setTokenMapping(_ mapping: [String: BlockedToken]) {
        // No-op for test
    }
}

/// Extension to provide convenience methods
extension Blocker {
    /// Blocks tokens based on rule evaluation
    func applyRuleBasedBlocking(
        for tokenIds: [String],
        using ruleEvaluator: (String) -> Bool
    ) {
        let tokensToBlock = tokenIds.filter(ruleEvaluator)
        let tokensToUnblock = tokenIds.filter { !ruleEvaluator($0) }
        
        if !tokensToBlock.isEmpty {
            blockTokens(tokenIds: tokensToBlock)
        }
        
        if !tokensToUnblock.isEmpty {
            unblockTokens(tokenIds: tokensToUnblock)
        }
    }
    
    /// Toggles blocking state for a token
    func toggleTokenBlocking(tokenId: String) {
        if isTokenBlocked(tokenId: tokenId) {
            unblockToken(tokenId: tokenId)
        } else {
            blockToken(tokenId: tokenId)
        }
    }
}

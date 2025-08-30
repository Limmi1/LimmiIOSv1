//
//  RuleStoreViewModel.swift
//  Limmi
//
//  Purpose: SwiftUI-optimized ViewModel that bridges RuleStore protocol to reactive UI
//  Provides clean separation between domain logic and presentation logic
//

import Foundation
import SwiftUI
import Combine
import FamilyControls
import ManagedSettings
import os

// Import the data models
// These are defined in FirebaseModel.swift
// Rule, FineLocationRule, GPSLocation, BlockedTokenInfo, BeaconDevice, FineLocationBehavior

/// SwiftUI-optimized ViewModel that exposes RuleStore data in a reactive, view-friendly way
/// 
/// This ViewModel serves as a clean abstraction layer between the RuleStore protocol
/// and SwiftUI views, providing only the data and operations that views actually need
/// while maintaining protocol-based architecture for testability and flexibility.
///
/// ## Key Benefits:
/// - **Focused API**: Only exposes what views need, not entire RuleStore interface
/// - **SwiftUI Native**: Built specifically for @EnvironmentObject usage
/// - **Reactive**: All data automatically updates UI through @Published properties
/// - **Testable**: Easy to unit test with mock RuleStore implementations
/// - **Protocol-based**: Depends on RuleStore protocol for flexibility
@MainActor
class RuleStoreViewModel: ObservableObject {
    
    // MARK: - Published Properties for Views
    
    /// Current list of beacon devices for the user
    @Published var beacons: [BeaconDevice] = []
    
    /// Current list of active rules
    @Published var activeRules: [Rule] = []
    
    /// Current list of blocked tokens
    @Published var blockedTokens: [BlockedTokenInfo] = []
    
    /// Loading states for different data types
    @Published var isLoadingBeacons: Bool = false
    @Published var isLoadingRules: Bool = false
    @Published var isLoadingTokens: Bool = false
    
    /// Error state for UI feedback
    @Published var error: Error?
    
    /// Overall loading state
    var isLoading: Bool {
        isLoadingBeacons || isLoadingRules || isLoadingTokens
    }
    
    // MARK: - Private Properties
    
    /// The underlying RuleStore implementation (protocol-based)
    /// Exposed for components that need direct access (like CoreLocationBeaconScanner)
    let ruleStore: any RuleStore
    
    /// Combine cancellables for reactive subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Logger for debugging and monitoring
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "RuleStoreViewModel")
    )
    
    // MARK: - Initialization
    
    /// Initialize with any RuleStore implementation
    /// - Parameter ruleStore: The RuleStore to wrap (protocol-based for flexibility)
    init(ruleStore: any RuleStore) {
        self.ruleStore = ruleStore
        setupReactiveBindings()
        loadInitialData()
    }
    
    // MARK: - Setup Methods
    
    /// Setup reactive bindings from RuleStore to Published properties
    private func setupReactiveBindings() {
        // Bind beacon devices
        ruleStore.beaconDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] beacons in
                // Only update if beacons have actually changed
                if !beacons.isEquivalent(to: self?.beacons ?? []) {
                    self?.logger.debug("ViewModel: Beacon devices changed, updating UI")
                    self?.beacons = beacons
                }
                self?.isLoadingBeacons = false
            }
            .store(in: &cancellables)
        
        // Bind active rules
        ruleStore.activeRulesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rules in
                // Only update if rules have actually changed
                if !rules.isEquivalent(to: self?.activeRules ?? []) {
                    self?.logger.debug("ViewModel: Active rules changed, updating UI")
                    self?.activeRules = rules
                }
                self?.isLoadingRules = false
            }
            .store(in: &cancellables)
        
        // Bind blocked tokens
        ruleStore.blockedTokensPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tokens in
                // Only update if blocked tokens have actually changed
                if !tokens.isEquivalent(to: self?.blockedTokens ?? []) {
                    self?.logger.debug("ViewModel: Blocked tokens changed, updating UI")
                    self?.blockedTokens = tokens
                }
                self?.isLoadingTokens = false
            }
            .store(in: &cancellables)
        
        // Bind loading states if RuleStore is FirebaseRuleStore
        if let firebaseStore = ruleStore as? FirebaseRuleStore {
            firebaseStore.$isLoadingBeacons
                .receive(on: DispatchQueue.main)
                .assign(to: \.isLoadingBeacons, on: self)
                .store(in: &cancellables)
            
            firebaseStore.$isLoadingRules
                .receive(on: DispatchQueue.main)
                .assign(to: \.isLoadingRules, on: self)
                .store(in: &cancellables)
            
            firebaseStore.$isLoadingTokens
                .receive(on: DispatchQueue.main)
                .assign(to: \.isLoadingTokens, on: self)
                .store(in: &cancellables)
            
            firebaseStore.$loadingError
                .receive(on: DispatchQueue.main)
                .assign(to: \.error, on: self)
                .store(in: &cancellables)
        }
    }
    
    /// Load initial data from RuleStore
    private func loadInitialData() {
        refreshAll()
    }
    
    // MARK: - Public Methods for Views
    
    /// Refresh all data from the underlying RuleStore
    func refreshAll() {
        logger.debug("Refreshing all data from RuleStore")
        
        isLoadingBeacons = true
        isLoadingRules = true
        isLoadingTokens = true
        
        ruleStore.refreshBeaconDevices()
        ruleStore.refreshRules()
        ruleStore.refreshBlockedTokens()
    }
    
    /// Refresh only beacon data
    func refreshBeacons() {
        logger.debug("Refreshing beacon data")
        isLoadingBeacons = true
        ruleStore.refreshBeaconDevices()
    }
    
    /// Refresh only rule data
    func refreshRules() {
        logger.debug("Refreshing rule data")
        isLoadingRules = true
        ruleStore.refreshRules()
    }
    
    /// Refresh only blocked tokens data
    func refreshBlockedTokens() {
        logger.debug("Refreshing blocked tokens data")
        isLoadingTokens = true
        ruleStore.refreshBlockedTokens()
    }
    
    /// Get blocked tokens by their Firebase document IDs
    /// - Parameter ids: Array of Firebase document IDs
    /// - Returns: Array of BlockedTokenInfo objects matching the provided IDs
    func getBlockedTokens(byIds ids: [String]) -> [BlockedTokenInfo] {
        return ruleStore.getBlockedTokens(byIds: ids)
    }
    
    /// Get beacon device by ID
    /// - Parameter id: The beacon device ID
    /// - Returns: The beacon device if found, nil otherwise
    func beaconDevice(id: String) -> BeaconDevice? {
        return ruleStore.beaconDevice(id: id)
    }
    
    /// Get multiple beacon devices by IDs
    /// - Parameter ids: Array of beacon device IDs
    /// - Returns: Array of found beacon devices
    func beaconDevices(ids: [String]) -> [BeaconDevice] {
        return ruleStore.beaconDevices(ids: ids)
    }
    
    /// Clear any error state
    func clearError() {
        error = nil
    }
    
    // MARK: - Complex Rule Creation Orchestration
    
    /// Creates a complete rule with all dependencies (beacon, tokens, rule)
    /// This method orchestrates the complex multi-step process:
    /// 1. Saves beacon device if new
    /// 2. Converts and saves all blocked tokens
    /// 3. Creates the rule with all references
    /// - Parameters:
    ///   - name: Rule name
    ///   - beacon: Beacon device (with or without ID)
    ///   - gpsLocation: GPS location settings
    ///   - blockedTokens: Screen Time tokens (apps, web domains, activity categories)
    ///   - completion: Completion handler with created rule or error
    func createComplexRule(
        name: String,
        beacon: BeaconDevice,
        gpsLocation: GPSLocation,
        blockedTokens: [BlockedToken],
        completion: @escaping (Result<Rule, Error>) -> Void
    ) {
        logger.debug("Starting complex rule creation: \(name)")
        
        // Step 1: Save beacon device (if new) or use existing
        saveBeaconForRule(beacon) { [weak self] result in
            switch result {
            case .success(let savedBeacon):
                let beaconId = savedBeacon.id
                
                // Step 2: Convert BlockedTokens to BlockedTokenInfo and save
                self?.saveBlockedTokensAsBlockedTokenInfo(blockedTokens) { [weak self] result in
                    switch result {
                    case .success(let blockedTokenIds):
                        // Step 3: Create the rule with all references
                        self?.createRuleWithComponents(
                            name: name,
                            beaconId: beaconId,
                            gpsLocation: gpsLocation,
                            blockedTokenIds: blockedTokenIds,
                            completion: completion
                        )
                    case .failure(let error):
                        self?.logger.error("Failed to save blocked tokens: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            case .failure(let error):
                self?.logger.error("Failed to save beacon: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Saves a beacon device, handling both new and existing beacons
    private func saveBeaconForRule(_ beacon: BeaconDevice, completion: @escaping (Result<BeaconDevice, Error>) -> Void) {
        if beacon.documentID == nil {
            // New beacon - save it
            ruleStore.saveBeaconDevice(beacon, completion: completion)
        } else {
            // Existing beacon - use as-is
            completion(.success(beacon))
        }
    }
    
    /// Converts BlockedTokens to BlockedTokenInfo objects and saves them
    func saveBlockedTokensAsBlockedTokenInfo(_ tokens: [BlockedToken], completion: @escaping (Result<[String], Error>) -> Void) {
        logger.debug("Converting and saving \(tokens.count) blocked tokens")
        
        var blockedTokenInfos: [BlockedTokenInfo] = []
        
        for token in tokens {
            let tokenInfo: BlockedTokenInfo?
            
            switch token.type {
            case .application:
                if let appToken = token.applicationToken {
                    tokenInfo = BlockedTokenInfo.createWithMetadata(
                        applicationToken: appToken, 
                        displayName: token.displayName, 
                        bundleIdentifier: token.bundleIdentifier ?? ""
                    )
                } else {
                    tokenInfo = nil
                }
            case .webDomain:
                if let webToken = token.webDomainToken {
                    tokenInfo = BlockedTokenInfo.createWithMetadata(
                        webDomainToken: webToken, 
                        domain: token.displayName
                    )
                } else {
                    tokenInfo = nil
                }
            case .activityCategory:
                if let categoryToken = token.activityCategoryToken {
                    tokenInfo = BlockedTokenInfo.createWithMetadata(
                        activityCategoryToken: categoryToken, 
                        displayName: token.displayName
                    )
                } else {
                    tokenInfo = nil
                }
            }
            
            if let tokenInfo = tokenInfo {
                blockedTokenInfos.append(tokenInfo)
            }
        }
        
        // Save all blocked token infos and get their IDs
        ruleStore.saveMultipleBlockedTokens(blockedTokenInfos, completion: completion)
    }
    
    /// Creates the final rule with all component references
    private func createRuleWithComponents(
        name: String,
        beaconId: String,
        gpsLocation: GPSLocation,
        blockedTokenIds: [String],
        completion: @escaping (Result<Rule, Error>) -> Void
    ) {
        logger.debug("Creating rule with components: beacon=\(beaconId), tokens=\(blockedTokenIds.count)")
        
        // Use the business logic extension to create the rule
        let rule = Rule.createFromComponents(
            name: name,
            beaconId: beaconId,
            gpsLocation: gpsLocation,
            blockedTokenIds: blockedTokenIds
        )
        
        // Save the complete rule
        ruleStore.addRule(rule) { [weak self] result in
            switch result {
            case .success(let savedRule):
                self?.logger.debug("Complex rule creation completed successfully: \(name)")
                completion(.success(savedRule))
            case .failure(let error):
                self?.logger.error("Failed to save final rule: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Rule Operations for Views
    
    /// Add a new rule
    /// - Parameter rule: The rule to add
    /// - Parameter completion: Completion handler with result
    func addRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void = { _ in }) {
        logger.debug("Adding rule: \(rule.name)")
        ruleStore.addRule(rule) { result in
            DispatchQueue.main.async {
                completion(result)
                if case .failure(let error) = result {
                    self.error = error
                }
            }
        }
    }
    
    /// Update an existing rule
    /// - Parameter rule: The rule to update
    /// - Parameter completion: Completion handler with result
    func updateRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void = { _ in }) {
        logger.debug("Updating rule: \(rule.name)")
        ruleStore.updateRule(rule) { result in
            DispatchQueue.main.async {
                completion(result)
                if case .failure(let error) = result {
                    self.error = error
                }
            }
        }
    }
    
    /// Delete a rule
    /// - Parameter id: The rule ID to delete
    /// - Parameter completion: Completion handler with result
    func deleteRule(id: String, completion: @escaping (Result<Void, Error>) -> Void = { _ in }) {
        logger.debug("Deleting rule: \(id)")
        ruleStore.deleteRule(id: id) { result in
            DispatchQueue.main.async {
                completion(result)
                if case .failure(let error) = result {
                    self.error = error
                }
            }
        }
    }
}

// MARK: - Computed Properties for Views

extension RuleStoreViewModel {
    /// Returns beacon devices that are referenced in active rules
    var beaconsInUse: [BeaconDevice] {
        let beaconIdsInUse = Set(activeRules.flatMap { $0.fineLocationRules.map(\.beaconId) })
        return beacons.filter { beacon in
            beaconIdsInUse.contains(beacon.id)
        }
    }
    
    /// Returns beacon devices that are not referenced in any active rules
    var availableBeacons: [BeaconDevice] {
        let beaconIdsInUse = Set(activeRules.flatMap { $0.fineLocationRules.map(\.beaconId) })
        return beacons.filter { beacon in
            !beaconIdsInUse.contains(beacon.id)
        }
    }
    
    /// Returns the count of active rules
    var activeRuleCount: Int {
        activeRules.count
    }
    
    /// Returns the count of available beacons
    var beaconCount: Int {
        beacons.count
    }
}

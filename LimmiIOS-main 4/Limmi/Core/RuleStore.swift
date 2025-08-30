//
//  RuleStore.swift
//  Limmi
//
//  Purpose: Rule storage abstraction and Firebase implementation for app blocking rules
//  Dependencies: Foundation, Combine, FirebaseFirestore
//  Related: BlockingEngine.swift, FirebaseModel.swift, Rule data models
//

import Foundation
import Combine
import FirebaseFirestore
import os

/// Protocol for rule storage and retrieval with reactive data access.
///
/// This protocol abstracts rule data operations to enable:
/// - Testability through mock implementations
/// - Flexibility to switch between data sources (Firebase, Core Data, etc.)
/// - Reactive data flow with Combine publishers
/// - Clean separation between business logic and data persistence
///
/// ## Data Model
/// Manages three types of data:
/// - Rules: Token blocking rules with location, time, and beacon conditions
/// - Blocked Tokens: Applications, web domains, and activity categories that can be restricted with Screen Time tokens
/// - Beacon Devices: Physical beacons referenced by rules
///
/// ## Reactive Updates
/// All data changes are published via Combine publishers for reactive UI updates
/// and automatic rule evaluation triggers in the blocking engine.
///
/// - Since: 1.0
protocol RuleStore: ObservableObject {
    /// Returns all rules regardless of active status.
    /// - Returns: Array of all rules in the data store
    func allRules() -> [Rule]
    
    /// Returns only rules that are currently active and should be evaluated.
    /// - Returns: Array of rules where isActive = true
    func activeRules() -> [Rule]
    
    /// Publisher that emits all rules whenever the rule set changes.
    /// Used for UI that displays all rules regardless of status.
    var rulesPublisher: AnyPublisher<[Rule], Never> { get }
    
    /// Publisher that emits active rules whenever active rule set changes.
    /// Used by blocking engine to automatically update monitoring targets.
    var activeRulesPublisher: AnyPublisher<[Rule], Never> { get }
    
    /// Adds a new rule to the data store.
    /// - Parameters:
    ///   - rule: Rule to add (ID will be generated if not provided)
    ///   - completion: Callback with saved rule or error
    func addRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void)
    
    /// Updates an existing rule in the data store.
    /// - Parameters:
    ///   - rule: Rule with updated properties (must have valid ID)
    ///   - completion: Callback with updated rule or error
    func updateRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void)
    
    /// Deletes a rule from the data store.
    /// - Parameters:
    ///   - id: Firebase document ID of rule to delete
    ///   - completion: Callback indicating success or error
    func deleteRule(id: String, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Refreshes rules from the remote data source.
    /// Triggers re-fetch from Firebase and updates local cache.
    func refreshRules()
    
    // MARK: - Blocked Tokens Management
    
    /// Returns all blocked tokens with their Screen Time tokens.
    /// - Returns: Array of tokens that can be blocked with their metadata
    func blockedTokens() -> [BlockedTokenInfo]
    
    /// Publisher that emits blocked tokens whenever the token list changes.
    /// Used by blocking engine to update token mappings automatically.
    var blockedTokensPublisher: AnyPublisher<[BlockedTokenInfo], Never> { get }
    
    /// Adds or updates a blocked token entry.
    /// - Parameters:
    ///   - token: Token info with Screen Time token and metadata
    ///   - completion: Callback with saved token info or error
    func saveBlockedToken(_ token: BlockedTokenInfo, completion: @escaping (Result<BlockedTokenInfo, Error>) -> Void)
    
    /// Deletes a blocked token by ID
    func deleteBlockedToken(id: String, completion: @escaping (Result<Void, Error>) -> Void)
    
    /// Refreshes blocked tokens from the data source
    func refreshBlockedTokens()
    
    /// Gets blocked tokens by their Firebase document IDs
    /// - Parameter ids: Array of Firebase document IDs
    /// - Returns: Array of BlockedTokenInfo objects matching the provided IDs
    func getBlockedTokens(byIds ids: [String]) -> [BlockedTokenInfo]
    
    // MARK: - Beacon Management
    
    /// Returns all beacon devices
    func beaconDevices() -> [BeaconDevice]
    
    /// Returns a publisher of beacon devices for reactive updates
    var beaconDevicesPublisher: AnyPublisher<[BeaconDevice], Never> { get }
    
    /// Returns beacon device by document ID
    func beaconDevice(id: String) -> BeaconDevice?
    
    /// Returns beacon devices for the given document IDs
    func beaconDevices(ids: [String]) -> [BeaconDevice]
    
    /// Refreshes beacon devices from the data source
    func refreshBeaconDevices()
    
    /// Saves a beacon device and returns it with the Firebase-assigned ID
    func saveBeaconDevice(_ beacon: BeaconDevice, completion: @escaping (Result<BeaconDevice, Error>) -> Void)
    
    /// Saves a blocked token and returns its Firebase document ID
    func saveBlockedTokenReturningId(_ token: BlockedTokenInfo, completion: @escaping (Result<String, Error>) -> Void)
    
    /// Saves multiple blocked tokens and returns their Firebase document IDs
    func saveMultipleBlockedTokens(_ tokens: [BlockedTokenInfo], completion: @escaping (Result<[String], Error>) -> Void)
}

/// Firebase-based implementation of RuleStore
final class FirebaseRuleStore: RuleStore, ObservableObject {
    private let firestore: Firestore
    private let userId: String
    @Published private var rules: [Rule] = []
    @Published private var tokens: [BlockedTokenInfo] = []
    @Published private var beacons: [BeaconDevice] = []
    
    // Loading states for async coordination
    @Published var isLoadingRules: Bool = false
    @Published var isLoadingTokens: Bool = false
    @Published var isLoadingBeacons: Bool = false
    @Published var loadingError: Error?
    
    /// Combined loading state - true when any data is still loading
    var isLoading: Bool {
        isLoadingRules || isLoadingTokens || isLoadingBeacons
    }
    
    /// Publisher that emits when initial data loading is complete
    var dataReadyPublisher: AnyPublisher<Bool, Never> {
        Publishers.CombineLatest3($isLoadingRules, $isLoadingTokens, $isLoadingBeacons)
            .map { isLoadingRules, isLoadingTokens, isLoadingBeacons in
                !isLoadingRules && !isLoadingTokens && !isLoadingBeacons
            }
            .eraseToAnyPublisher()
    }
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "FirebaseRuleStore")
    )
    
    init(firestore: Firestore, userId: String) {
        self.firestore = firestore
        self.userId = userId
        logger.debug("FirebaseRuleStore initialized for user: \(userId)")
        loadRules()
        loadBlockedTokens()
        loadBeaconDevices()
    }
    
    func allRules() -> [Rule] {
        return rules
    }
    
    func activeRules() -> [Rule] {
        return rules.filter { $0.isActive }
    }
    
    var rulesPublisher: AnyPublisher<[Rule], Never> {
        $rules.eraseToAnyPublisher()
    }
    
    var activeRulesPublisher: AnyPublisher<[Rule], Never> {
        $rules
            .map { rules in rules.filter { $0.isActive } }
            .eraseToAnyPublisher()
    }
    
    func addRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void) {
        logger.debug("Adding rule: \(rule.name)")
        
        do {
            let dict = try ruleToFirestoreData(rule)
            
            firestore.collection("users").document(userId).collection("rules").addDocument(data: dict) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to add rule: \(error.localizedDescription)")
                    completion(.failure(RuleStoreError.addFailed))
                } else {
                    self?.logger.debug("Rule added successfully")
                    self?.loadRules()
                    completion(.success(rule))
                }
            }
        } catch {
            logger.error("Failed to encode rule: \(error.localizedDescription)")
            completion(.failure(RuleStoreError.addFailed))
        }
    }
    
    func updateRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void) {
        guard let ruleId = rule.id else {
            completion(.failure(RuleStoreError.ruleNotFound))
            return
        }
        
        logger.debug("Updating rule: \(rule.name)")
        
        do {
            let dict = try ruleToFirestoreData(rule)
            
            firestore.collection("users").document(userId).collection("rules").document(ruleId).setData(dict) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to update rule: \(error.localizedDescription)")
                    completion(.failure(RuleStoreError.updateFailed))
                } else {
                    self?.logger.debug("Rule updated successfully")
                    self?.loadRules()
                    completion(.success(rule))
                }
            }
        } catch {
            logger.error("Failed to encode rule: \(error.localizedDescription)")
            completion(.failure(RuleStoreError.updateFailed))
        }
    }
    
    func deleteRule(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.debug("Deleting rule: \(id)")
        
        firestore.collection("users").document(userId).collection("rules").document(id).delete { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to delete rule: \(error.localizedDescription)")
                completion(.failure(RuleStoreError.deleteFailed))
            } else {
                self?.logger.debug("Rule deleted successfully")
                self?.loadRules()
                completion(.success(()))
            }
        }
    }
    
    func refreshRules() {
        logger.debug("Refreshing rules from Firestore")
        loadRules()
    }
    
    // MARK: - Blocked Tokens Implementation
    
    func blockedTokens() -> [BlockedTokenInfo] {
        return tokens
    }
    
    var blockedTokensPublisher: AnyPublisher<[BlockedTokenInfo], Never> {
        $tokens.eraseToAnyPublisher()
    }
    
    func saveBlockedToken(_ token: BlockedTokenInfo, completion: @escaping (Result<BlockedTokenInfo, Error>) -> Void) {
        logger.debug("Saving blocked token: \(token.name)")
        
        do {
            let dict = try blockedTokenToFirestoreData(token)
            
            if let tokenId = token.id {
                // Update existing token
                firestore.collection("users").document(userId).collection("blockedTokens").document(tokenId).setData(dict) { [weak self] error in
                    if let error = error {
                        self?.logger.error("Failed to update blocked token: \(error.localizedDescription)")
                        completion(.failure(RuleStoreError.updateFailed))
                    } else {
                        self?.logger.debug("Blocked token updated successfully")
                        self?.loadBlockedTokens()
                        completion(.success(token))
                    }
                }
            } else {
                // Create new token
                firestore.collection("users").document(userId).collection("blockedTokens").addDocument(data: dict) { [weak self] error in
                    if let error = error {
                        self?.logger.error("Failed to save blocked token: \(error.localizedDescription)")
                        completion(.failure(RuleStoreError.addFailed))
                    } else {
                        self?.logger.debug("Blocked token saved successfully")
                        self?.loadBlockedTokens()
                        completion(.success(token))
                    }
                }
            }
        } catch {
            logger.error("Failed to encode blocked token: \(error.localizedDescription)")
            completion(.failure(RuleStoreError.addFailed))
        }
    }
    
    func deleteBlockedToken(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        logger.debug("Deleting blocked token: \(id)")
        
        firestore.collection("users").document(userId).collection("blockedTokens").document(id).delete { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to delete blocked token: \(error.localizedDescription)")
                completion(.failure(RuleStoreError.deleteFailed))
            } else {
                self?.logger.debug("Blocked token deleted successfully")
                self?.loadBlockedTokens()
                completion(.success(()))
            }
        }
    }
    
    func refreshBlockedTokens() {
        logger.debug("Refreshing blocked tokens from Firestore")
        loadBlockedTokens()
    }
    
    func getBlockedTokens(byIds ids: [String]) -> [BlockedTokenInfo] {
        return tokens.filter { token in
            guard let tokenId = token.id else { return false }
            return ids.contains(tokenId)
        }
    }
    
    // MARK: - Beacon Devices Implementation
    
    func beaconDevices() -> [BeaconDevice] {
        return beacons
    }
    
    var beaconDevicesPublisher: AnyPublisher<[BeaconDevice], Never> {
        $beacons.eraseToAnyPublisher()
    }
    
    func beaconDevice(id: String) -> BeaconDevice? {
        return beacons.first { $0.id == id }
    }
    
    func beaconDevices(ids: [String]) -> [BeaconDevice] {
        return beacons.filter { beacon in
            ids.contains(beacon.id)
        }
    }
    
    func refreshBeaconDevices() {
        logger.debug("Refreshing beacon devices from Firestore")
        loadBeaconDevices()
    }
    
    func saveBeaconDevice(_ beacon: BeaconDevice, completion: @escaping (Result<BeaconDevice, Error>) -> Void) {
        logger.debug("Saving beacon device: \(beacon.name)")
        let beaconId = beacon.id
        // 1. Check local cache first
        if let existing = beacons.first(where: { $0.id == beaconId }) {
            completion(.success(existing))
            return
        }
        // 2. Save to Firestore (upsert)
        do {
            let dict = try beaconDeviceToFirestoreData(beacon)
            let collection = firestore.collection("users").document(userId).collection("beacons")
            collection.document(beaconId).setData(dict) { [weak self] error in
                if let error = error {
                    self?.logger.error("Failed to save beacon device: \(error.localizedDescription)")
                    completion(.failure(RuleStoreError.addFailed))
                } else {
                    self?.logger.debug("Beacon device saved successfully")
                    self?.loadBeaconDevices()
                    completion(.success(beacon))
                }
            }
        } catch {
            logger.error("Failed to encode beacon device: \(error.localizedDescription)")
            completion(.failure(RuleStoreError.addFailed))
        }
    }
    
    func saveBlockedTokenReturningId(_ token: BlockedTokenInfo, completion: @escaping (Result<String, Error>) -> Void) {
        logger.debug("Saving blocked token: \(token.name)")
        
        do {
            let dict = try blockedTokenToFirestoreData(token)
            
            if let tokenId = token.id {
                // Update existing token
                firestore.collection("users").document(userId).collection("blockedTokens").document(tokenId).setData(dict) { [weak self] error in
                    if let error = error {
                        self?.logger.error("Failed to update blocked token: \(error.localizedDescription)")
                        completion(.failure(RuleStoreError.updateFailed))
                    } else {
                        self?.logger.debug("Blocked token updated successfully")
                        self?.loadBlockedTokens()
                        completion(.success(tokenId))
                    }
                }
            } else {
                // Create new token
                let collection = firestore.collection("users").document(userId).collection("blockedTokens")
                var docRef: DocumentReference? = nil
                docRef = collection.addDocument(data: dict) { [weak self] error in
                    if let error = error {
                        self?.logger.error("Failed to save blocked token: \(error.localizedDescription)")
                        completion(.failure(RuleStoreError.addFailed))
                    } else if let docRef = docRef {
                        self?.logger.debug("Blocked token saved successfully")
                        self?.loadBlockedTokens()
                        completion(.success(docRef.documentID))
                    }
                }
            }
        } catch {
            logger.error("Failed to encode blocked token: \(error.localizedDescription)")
            completion(.failure(RuleStoreError.addFailed))
        }
    }
    
    func saveMultipleBlockedTokens(_ tokens: [BlockedTokenInfo], completion: @escaping (Result<[String], Error>) -> Void) {
        logger.debug("Saving multiple blocked tokens: \(tokens.count) tokens")
        
        var savedIds: [String] = []
        let group = DispatchGroup()
        var hasError = false
        
        for token in tokens {
            group.enter()
            saveBlockedTokenReturningId(token) { result in
                switch result {
                case .success(let id):
                    savedIds.append(id)
                case .failure(_):
                    hasError = true
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if hasError {
                completion(.failure(RuleStoreError.addFailed))
            } else {
                completion(.success(savedIds))
            }
        }
    }
    
    /// Retry loading data after a failure
    func retryLoading() {
        logger.debug("Retrying data loading")
        loadingError = nil
        if !isLoadingRules {
            loadRules()
        }
        if !isLoadingTokens {
            loadBlockedTokens()
        }
        if !isLoadingBeacons {
            loadBeaconDevices()
        }
    }
    
    /// Async method to wait for initial data loading to complete
    func waitForInitialDataLoad() async throws {
        guard isLoading else { return } // Already loaded
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var cancellable: AnyCancellable?
            cancellable = dataReadyPublisher
                .first { isReady in isReady }
                .sink { _ in
                    cancellable?.cancel()
                    if let error = self.loadingError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
        }
    }
    
    // MARK: - Private Methods
    
    private func loadRules() {
        logger.debug("Loading rules from Firestore")
        isLoadingRules = true
        loadingError = nil
        
        firestore.collection("users").document(userId).collection("rules").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.logger.error("Failed to load rules: \(error.localizedDescription)")
                    self?.loadingError = error
                    self?.isLoadingRules = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self?.logger.debug("No rules found")
                    self?.rules = []
                    self?.isLoadingRules = false
                    return
                }
                
                var loadedRules: [Rule] = []
                
                for document in documents {
                    do {
                        var rule = try self?.ruleFromFirestoreData(document.data(), documentId: document.documentID) ?? Rule(name: "Error")
                        rule.id = document.documentID  // Ensure ID is set from document
                        loadedRules.append(rule)
                    } catch {
                        self?.logger.error("Failed to decode rule from document \(document.documentID): \(error.localizedDescription)")
                    }
                }
                
                // Only update if rules have actually changed
                if !loadedRules.isEquivalent(to: self?.rules ?? []) {
                    self?.logger.debug("Rules changed, updating to \(loadedRules.count) rules")
                    self?.rules = loadedRules
                } else {
                    self?.logger.debug("Rules unchanged, skipping update (\(loadedRules.count) rules)")
                }
                self?.isLoadingRules = false
            }
        }
    }
    
    private func loadBlockedTokens() {
        logger.debug("Loading blocked tokens from Firestore")
        isLoadingTokens = true
        loadingError = nil
        
        firestore.collection("users").document(userId).collection("blockedTokens").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.logger.error("Failed to load blocked tokens: \(error.localizedDescription)")
                    self?.loadingError = error
                    self?.isLoadingTokens = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self?.logger.debug("No blocked tokens found")
                    self?.tokens = []
                    self?.isLoadingTokens = false
                    return
                }
                
                var loadedTokens: [BlockedTokenInfo] = []
                
                for document in documents {
                    do {
                        var token = try self?.blockedTokenFromFirestoreData(document.data(), documentId: document.documentID) ?? BlockedTokenInfo(name: "Error", tokenType: "application", tokenData: Data())
                        token.id = document.documentID
                        loadedTokens.append(token)
                    } catch {
                        self?.logger.error("Failed to decode blocked token from document \(document.documentID): \(error.localizedDescription)")
                    }
                }
                
                // Only update if blocked tokens have actually changed
                if !loadedTokens.isEquivalent(to: self?.tokens ?? []) {
                    self?.logger.debug("Blocked tokens changed, updating to \(loadedTokens.count) tokens")
                    self?.tokens = loadedTokens
                } else {
                    self?.logger.debug("Blocked tokens unchanged, skipping update (\(loadedTokens.count) tokens)")
                }
                self?.isLoadingTokens = false
            }
        }
    }
    
    private func loadBeaconDevices() {
        logger.debug("Loading beacon devices from Firestore")
        isLoadingBeacons = true
        loadingError = nil
        
        firestore.collection("users").document(userId).collection("beacons").getDocuments { [weak self] snapshot, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.logger.error("Failed to load beacon devices: \(error.localizedDescription)")
                    self?.loadingError = error
                    self?.isLoadingBeacons = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    self?.logger.debug("No beacon devices found")
                    self?.beacons = []
                    self?.isLoadingBeacons = false
                    return
                }
                
                var loadedBeacons: [BeaconDevice] = []
                
                for document in documents {
                    let id = document.documentID
                    let parts = id.split(separator: "-")
                    // UUID is the first 5 parts joined by "-", major is next, minor is last
                    guard parts.count >= 7 else { continue }
                    let uuid = parts[0...4].joined(separator: "-")
                    let major = Int(parts[5]) ?? 0
                    let minor = Int(parts[6]) ?? 0
                    let data = document.data()
                    let name = data["name"] as? String ?? ""
                    let isActive = data["isActive"] as? Bool ?? true
                    let dateCreated: Date = {
                        if let ts = data["dateCreated"] as? Timestamp {
                            return ts.dateValue()
                        } else {
                            return Date()
                        }
                    }()
                    var beacon = BeaconDevice(name: name, uuid: uuid, major: major, minor: minor)
                    beacon.isActive = isActive
                    beacon.dateCreated = dateCreated
                    loadedBeacons.append(beacon)
                }
                
                // Only update if beacon devices have actually changed
                if !loadedBeacons.isEquivalent(to: self?.beacons ?? []) {
                    self?.logger.debug("Beacon devices changed, updating to \(loadedBeacons.count) beacons")
                    self?.beacons = loadedBeacons
                } else {
                    self?.logger.debug("Beacon devices unchanged, skipping update (\(loadedBeacons.count) beacons)")
                }
                self?.isLoadingBeacons = false
            }
        }
    }
    
    // MARK: - Firestore Data Conversion Helpers
    
    private func ruleToFirestoreData(_ rule: Rule) throws -> [String: Any] {
        // Convert Rule to Firestore-compatible dictionary
        var data: [String: Any] = [
            "name": rule.name,
            "isActive": rule.isActive,
            "dateCreated": Timestamp(date: rule.dateCreated),
            "dateModified": Timestamp(date: rule.dateModified),
            "blockedTokenIds": rule.blockedTokenIds
        ]
        
        // Convert GPS location
        data["gpsLocation"] = [
            "latitude": rule.gpsLocation.latitude,
            "longitude": rule.gpsLocation.longitude,
            "radius": rule.gpsLocation.radius,
            "isActive": rule.gpsLocation.isActive
        ]
        
        // Convert time rules
        data["timeRules"] = rule.timeRules.map { timeRule in
            var timeRuleData: [String: Any] = [
                "name": timeRule.name,
                "startTime": Timestamp(date: timeRule.startTime),
                "endTime": Timestamp(date: timeRule.endTime),
                "recurrencePattern": timeRule.recurrencePattern.rawValue,
                "startDate": Timestamp(date: timeRule.startDate),
                "isActive": timeRule.isActive
            ]
            
            if let endDate = timeRule.endDate {
                timeRuleData["endDate"] = Timestamp(date: endDate)
            }
            if let customInterval = timeRule.customInterval {
                timeRuleData["customInterval"] = customInterval
            }
            if let daysOfWeek = timeRule.daysOfWeek {
                timeRuleData["daysOfWeek"] = daysOfWeek
            }
            if let daysOfMonth = timeRule.daysOfMonth {
                timeRuleData["daysOfMonth"] = daysOfMonth
            }
            
            return timeRuleData
        }
        
        // Convert fine location rules
        data["fineLocationRules"] = rule.fineLocationRules.map { fineRule in
            return [
                "name": fineRule.name,
                "beaconId": fineRule.beaconId,
                "behaviorType": fineRule.behaviorType.rawValue,
                "isActive": fineRule.isActive,
                "dateCreated": Timestamp(date: fineRule.dateCreated)
            ]
        }
        
        return data
    }
    
    private func ruleFromFirestoreData(_ data: [String: Any], documentId: String) throws -> Rule {
        guard let name = data["name"] as? String,
              let isActive = data["isActive"] as? Bool else {
            throw RuleStoreError.networkError
        }
        
        var rule = Rule(name: name)
        rule.id = documentId
        rule.isActive = isActive
        
        // Convert dates
        if let dateCreatedTimestamp = data["dateCreated"] as? Timestamp {
            rule.dateCreated = dateCreatedTimestamp.dateValue()
        }
        if let dateModifiedTimestamp = data["dateModified"] as? Timestamp {
            rule.dateModified = dateModifiedTimestamp.dateValue()
        }
        
        // Convert blocked app IDs
        if let blockedTokenIds = data["blockedTokenIds"] as? [String] {
            rule.blockedTokenIds = blockedTokenIds
        }
        
        // Convert GPS location
        if let gpsData = data["gpsLocation"] as? [String: Any],
           let latitude = gpsData["latitude"] as? Double,
           let longitude = gpsData["longitude"] as? Double,
           let radius = gpsData["radius"] as? Double,
           let isGpsActive = gpsData["isActive"] as? Bool {
            rule.gpsLocation = GPSLocation(latitude: latitude, longitude: longitude, radius: radius)
            rule.gpsLocation.isActive = isGpsActive
        }
        
        // Convert time rules
        if let timeRulesData = data["timeRules"] as? [[String: Any]] {
            rule.timeRules = timeRulesData.compactMap { timeRuleData in
                guard let name = timeRuleData["name"] as? String,
                      let startTimeTimestamp = timeRuleData["startTime"] as? Timestamp,
                      let endTimeTimestamp = timeRuleData["endTime"] as? Timestamp,
                      let recurrencePatternRaw = timeRuleData["recurrencePattern"] as? String,
                      let recurrencePattern = RecurrencePattern(rawValue: recurrencePatternRaw),
                      let startDateTimestamp = timeRuleData["startDate"] as? Timestamp,
                      let isTimeRuleActive = timeRuleData["isActive"] as? Bool else {
                    return nil
                }
                
                var timeRule = TimeRule(
                    name: name,
                    startTime: startTimeTimestamp.dateValue(),
                    endTime: endTimeTimestamp.dateValue(),
                    recurrencePattern: recurrencePattern
                )
                
                timeRule.startDate = startDateTimestamp.dateValue()
                timeRule.isActive = isTimeRuleActive
                
                if let endDateTimestamp = timeRuleData["endDate"] as? Timestamp {
                    timeRule.endDate = endDateTimestamp.dateValue()
                }
                if let customInterval = timeRuleData["customInterval"] as? Int {
                    timeRule.customInterval = customInterval
                }
                if let daysOfWeek = timeRuleData["daysOfWeek"] as? [Int] {
                    timeRule.daysOfWeek = daysOfWeek
                }
                if let daysOfMonth = timeRuleData["daysOfMonth"] as? [Int] {
                    timeRule.daysOfMonth = daysOfMonth
                }
                
                return timeRule
            }
        }
        
        // Convert fine location rules
        if let fineRulesData = data["fineLocationRules"] as? [[String: Any]] {
            rule.fineLocationRules = fineRulesData.compactMap { fineRuleData in
                guard let name = fineRuleData["name"] as? String,
                      let beaconId = fineRuleData["beaconId"] as? String,
                      let behaviorTypeRaw = fineRuleData["behaviorType"] as? String,
                      let behaviorType = FineLocationBehavior(rawValue: behaviorTypeRaw),
                      let isFineRuleActive = fineRuleData["isActive"] as? Bool,
                      let dateCreatedTimestamp = fineRuleData["dateCreated"] as? Timestamp else {
                    return nil
                }
                
                var fineRule = FineLocationRule(name: name, beaconId: beaconId, behaviorType: behaviorType)
                fineRule.isActive = isFineRuleActive
                fineRule.dateCreated = dateCreatedTimestamp.dateValue()
                
                return fineRule
            }
        }
        
        return rule
    }
    
    private func blockedTokenToFirestoreData(_ token: BlockedTokenInfo) throws -> [String: Any] {
        var data: [String: Any] = [
            "name": token.name,                    // Keep for backward compatibility
            "displayName": token.displayName,      // New field
            "tokenType": token.tokenType,
            "tokenData": token.tokenData,
            "dateAdded": Timestamp(date: token.dateAdded),
            "isActive": token.isActive
        ]
        
        // Legacy field for backward compatibility
        if let bundleId = token.bundleId {
            data["bundleId"] = bundleId
        }
        
        // New field for enhanced metadata
        if let bundleIdentifier = token.bundleIdentifier {
            data["bundleIdentifier"] = bundleIdentifier
        }
        
        return data
    }
    
    private func blockedTokenFromFirestoreData(_ data: [String: Any], documentId: String) throws -> BlockedTokenInfo {
        guard let tokenType = data["tokenType"] as? String,
              let tokenData = data["tokenData"] as? Data,
              let isActive = data["isActive"] as? Bool else {
            throw RuleStoreError.networkError
        }
        
        // Handle displayName with backward compatibility
        let displayName = data["displayName"] as? String ?? data["name"] as? String ?? "Unknown"
        let legacyName = data["name"] as? String ?? displayName
        
        // Handle bundleIdentifier with backward compatibility  
        let bundleIdentifier = data["bundleIdentifier"] as? String ?? data["bundleId"] as? String
        let legacyBundleId = data["bundleId"] as? String ?? bundleIdentifier
        
        // Create token using enhanced initializer
        var token = BlockedTokenInfo(displayName: displayName, tokenType: tokenType, tokenData: tokenData, bundleIdentifier: bundleIdentifier)
        token.id = documentId
        token.isActive = isActive
        
        // Ensure legacy fields are populated for compatibility
        token.name = legacyName
        token.bundleId = legacyBundleId
        
        if let dateAddedTimestamp = data["dateAdded"] as? Timestamp {
            token.dateAdded = dateAddedTimestamp.dateValue()
        }
        
        return token
    }
    
    private func beaconDeviceFromFirestoreData(_ data: [String: Any], documentId: String) throws -> BeaconDevice {
        guard let name = data["name"] as? String,
              let uuid = data["uuid"] as? String,
              let major = data["major"] as? Int,
              let minor = data["minor"] as? Int,
              let isActive = data["isActive"] as? Bool else {
            throw RuleStoreError.networkError
        }
        
        var beacon = BeaconDevice(name: name, uuid: uuid, major: major, minor: minor)
        //beacon.id = documentId
        beacon.isActive = isActive
        
        if let dateCreatedTimestamp = data["dateCreated"] as? Timestamp {
            beacon.dateCreated = dateCreatedTimestamp.dateValue()
        }
        
        return beacon
    }
    
    private func beaconDeviceToFirestoreData(_ beacon: BeaconDevice) throws -> [String: Any] {
        var data: [String: Any] = [
            "name": beacon.name,
            /*"uuid": beacon.uuid,
            "major": beacon.major,
            "minor": beacon.minor,*/
            "isActive": beacon.isActive,
            "dateCreated": Timestamp(date: beacon.dateCreated)
        ]
        
        return data
    }
}


/// Test implementation of RuleStore with in-memory storage
final class TestRuleStore: RuleStore {
    @Published private var rules: [Rule] = []
    @Published private var tokens: [BlockedTokenInfo] = []
    @Published private var beacons: [BeaconDevice] = []
    
    init(rules: [Rule] = [], tokens: [BlockedTokenInfo] = [], beacons: [BeaconDevice] = []) {
        self.rules = rules
        self.tokens = tokens
        self.beacons = beacons
    }
    
    func allRules() -> [Rule] {
        return rules
    }
    
    func activeRules() -> [Rule] {
        return rules.filter { $0.isActive }
    }
    
    var rulesPublisher: AnyPublisher<[Rule], Never> {
        $rules.eraseToAnyPublisher()
    }
    
    var activeRulesPublisher: AnyPublisher<[Rule], Never> {
        $rules
            .map { rules in rules.filter { $0.isActive } }
            .eraseToAnyPublisher()
    }
    
    func addRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void) {
        var newRule = rule
        newRule.id = UUID().uuidString
        rules.append(newRule)
        completion(.success(newRule))
    }
    
    func updateRule(_ rule: Rule, completion: @escaping (Result<Rule, Error>) -> Void) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            completion(.success(rule))
        } else {
            completion(.failure(RuleStoreError.ruleNotFound))
        }
    }
    
    func deleteRule(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if let index = rules.firstIndex(where: { $0.id == id }) {
            rules.remove(at: index)
            completion(.success(()))
        } else {
            completion(.failure(RuleStoreError.ruleNotFound))
        }
    }
    
    func refreshRules() {
        // No-op for test implementation
    }
    
    // MARK: - Blocked Tokens Implementation
    
    func blockedTokens() -> [BlockedTokenInfo] {
        return tokens
    }
    
    var blockedTokensPublisher: AnyPublisher<[BlockedTokenInfo], Never> {
        $tokens.eraseToAnyPublisher()
    }
    
    func saveBlockedToken(_ token: BlockedTokenInfo, completion: @escaping (Result<BlockedTokenInfo, Error>) -> Void) {
        var newToken = token
        if newToken.id == nil {
            newToken.id = UUID().uuidString
        }
        
        if let index = tokens.firstIndex(where: { $0.id == newToken.id }) {
            tokens[index] = newToken
        } else {
            tokens.append(newToken)
        }
        
        completion(.success(newToken))
    }
    
    func deleteBlockedToken(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        if let index = tokens.firstIndex(where: { $0.id == id }) {
            tokens.remove(at: index)
            completion(.success(()))
        } else {
            completion(.failure(RuleStoreError.ruleNotFound))
        }
    }
    
    func refreshBlockedTokens() {
        // No-op for test implementation
    }
    
    func getBlockedTokens(byIds ids: [String]) -> [BlockedTokenInfo] {
        return tokens.filter { token in
            guard let tokenId = token.id else { return false }
            return ids.contains(tokenId)
        }
    }
    
    // MARK: - Beacon Devices Implementation
    
    func beaconDevices() -> [BeaconDevice] {
        return beacons
    }
    
    var beaconDevicesPublisher: AnyPublisher<[BeaconDevice], Never> {
        $beacons.eraseToAnyPublisher()
    }
    
    func beaconDevice(id: String) -> BeaconDevice? {
        return beacons.first { $0.id == id }
    }
    
    func beaconDevices(ids: [String]) -> [BeaconDevice] {
        return beacons.filter { beacon in
            ids.contains(beacon.id)
        }
    }
    
    func refreshBeaconDevices() {
        // No-op for test implementation
    }
    
    func saveBeaconDevice(_ beacon: BeaconDevice, completion: @escaping (Result<BeaconDevice, Error>) -> Void) {
        var newBeacon = beacon
        
        if let index = beacons.firstIndex(where: { $0.id == newBeacon.id }) {
            beacons[index] = newBeacon
        } else {
            beacons.append(newBeacon)
        }
        
        completion(.success(newBeacon))
    }
    
    func saveBlockedTokenReturningId(_ token: BlockedTokenInfo, completion: @escaping (Result<String, Error>) -> Void) {
        var newToken = token
        if newToken.id == nil {
            newToken.id = UUID().uuidString
        }
        
        if let index = tokens.firstIndex(where: { $0.id == newToken.id }) {
            tokens[index] = newToken
        } else {
            tokens.append(newToken)
        }
        
        completion(.success(newToken.id!))
    }
    
    func saveMultipleBlockedTokens(_ tokens: [BlockedTokenInfo], completion: @escaping (Result<[String], Error>) -> Void) {
        var savedIds: [String] = []
        
        for token in tokens {
            var newToken = token
            if newToken.id == nil {
                newToken.id = UUID().uuidString
            }
            
            if let index = self.tokens.firstIndex(where: { $0.id == newToken.id }) {
                self.tokens[index] = newToken
            } else {
                self.tokens.append(newToken)
            }
            
            savedIds.append(newToken.id!)
        }
        
        completion(.success(savedIds))
    }
    
    // Test helper methods
    func setRules(_ rules: [Rule]) {
        self.rules = rules
    }
    
    func clearRules() {
        rules.removeAll()
    }
    
    func setBlockedTokens(_ tokens: [BlockedTokenInfo]) {
        self.tokens = tokens
    }
    
    func clearBlockedTokens() {
        tokens.removeAll()
    }
    
    func setBeaconDevices(_ beacons: [BeaconDevice]) {
        self.beacons = beacons
    }
    
    func clearBeaconDevices() {
        beacons.removeAll()
    }
}

/// Errors that can occur during rule store operations
enum RuleStoreError: Error, LocalizedError {
    case addFailed
    case updateFailed
    case deleteFailed
    case ruleNotFound
    case networkError
    case duplicateBeacon
    
    var errorDescription: String? {
        switch self {
        case .addFailed:
            return "Failed to add rule"
        case .updateFailed:
            return "Failed to update rule"
        case .deleteFailed:
            return "Failed to delete rule"
        case .ruleNotFound:
            return "Rule not found"
        case .networkError:
            return "Network error occurred"
        case .duplicateBeacon:
            return "Duplicate beacon"
        }
    }
}

/// Extension to provide convenience methods
extension RuleStore {
    /// Returns rules that match a specific beacon ID
    func rulesForBeacon(beaconId: String) -> [Rule] {
        return activeRules().filter { rule in
            rule.fineLocationRules.contains { $0.beaconId == beaconId }
        }
    }
    
    /// Returns rules that contain a specific token ID
    func rulesForToken(tokenId: String) -> [Rule] {
        return activeRules().filter { rule in
            rule.blockedTokenIds.contains(tokenId)
        }
    }
    
    /// Returns beacon IDs from all active rules
    func allBeaconIds() -> Set<String> {
        return Set(activeRules().flatMap { rule in
            rule.fineLocationRules.map { $0.beaconId }
        })
    }
}

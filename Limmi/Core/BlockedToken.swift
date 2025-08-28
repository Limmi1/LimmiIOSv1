import Foundation
import ManagedSettings
import FamilyControls

enum TokenType: String, CaseIterable {
    case application = "application"
    case webDomain = "webDomain"
    case activityCategory = "activityCategory"
}

struct BlockedToken: Identifiable, Equatable {
    let id: Data // The encoded Token data
    let name: String                    // Deprecated: Use displayName instead
    let displayName: String             // Localized display name or domain
    let bundleIdentifier: String?       // App bundle identifier (applications only)
    let type: TokenType
    let applicationToken: ApplicationToken?
    let webDomainToken: WebDomainToken?
    let activityCategoryToken: ActivityCategoryToken?

    // MARK: - Legacy Initializers (for backward compatibility)
    
    init(applicationToken: ApplicationToken, name: String) {
        let encoder = JSONEncoder()
        self.id = (try? encoder.encode(applicationToken)) ?? Data()
        self.name = name
        self.displayName = name  // Fallback for legacy usage
        self.bundleIdentifier = nil
        self.type = .application
        self.applicationToken = applicationToken
        self.webDomainToken = nil
        self.activityCategoryToken = nil
    }
    
    init(webDomainToken: WebDomainToken, name: String) {
        let encoder = JSONEncoder()
        self.id = (try? encoder.encode(webDomainToken)) ?? Data()
        self.name = name
        self.displayName = name  // Fallback for legacy usage
        self.bundleIdentifier = nil
        self.type = .webDomain
        self.applicationToken = nil
        self.webDomainToken = webDomainToken
        self.activityCategoryToken = nil
    }
    
    init(activityCategoryToken: ActivityCategoryToken, name: String) {
        let encoder = JSONEncoder()
        self.id = (try? encoder.encode(activityCategoryToken)) ?? Data()
        self.name = name
        self.displayName = name  // Fallback for legacy usage
        self.bundleIdentifier = nil
        self.type = .activityCategory
        self.applicationToken = nil
        self.webDomainToken = nil
        self.activityCategoryToken = activityCategoryToken
    }
    
    // MARK: - Enhanced Initializers (with provided metadata)
    
    init(applicationToken: ApplicationToken, displayName: String, bundleIdentifier: String?) {
        let encoder = JSONEncoder()
        
        self.id = (try? encoder.encode(applicationToken)) ?? Data()
        self.name = displayName  // Keep legacy field populated
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.type = .application
        self.applicationToken = applicationToken
        self.webDomainToken = nil
        self.activityCategoryToken = nil
    }
    
    init(webDomainToken: WebDomainToken, domain: String) {
        let encoder = JSONEncoder()
        
        self.id = (try? encoder.encode(webDomainToken)) ?? Data()
        self.name = domain  // Keep legacy field populated
        self.displayName = domain
        self.bundleIdentifier = nil
        self.type = .webDomain
        self.applicationToken = nil
        self.webDomainToken = webDomainToken
        self.activityCategoryToken = nil
    }
    
    init(activityCategoryToken: ActivityCategoryToken, displayName: String) {
        let encoder = JSONEncoder()
        
        self.id = (try? encoder.encode(activityCategoryToken)) ?? Data()
        self.name = displayName  // Keep legacy field populated
        self.displayName = displayName
        self.bundleIdentifier = nil
        self.type = .activityCategory
        self.applicationToken = nil
        self.webDomainToken = nil
        self.activityCategoryToken = activityCategoryToken
    }

    static func == (lhs: BlockedToken, rhs: BlockedToken) -> Bool {
        lhs.id == rhs.id && lhs.displayName == rhs.displayName && lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.type == rhs.type
    }
}

// MARK: - FamilyActivitySelection Extensions

extension FamilyActivitySelection {
    /// Creates a FamilyActivitySelection from blocked token information
    /// - Parameter blockedTokens: Array of BlockedTokenInfo objects
    /// - Returns: FamilyActivitySelection with decoded tokens
    static func from(blockedTokens: [BlockedTokenInfo]) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        
        var applicationTokens: Set<ApplicationToken> = []
        var webDomainTokens: Set<WebDomainToken> = []
        var categoryTokens: Set<ActivityCategoryToken> = []
        
        for blockedToken in blockedTokens {
            switch blockedToken.tokenType {
            case "application":
                if let appToken = blockedToken.decodedApplicationToken() {
                    applicationTokens.insert(appToken)
                }
            case "webDomain":
                if let webToken = blockedToken.decodedWebDomainToken() {
                    webDomainTokens.insert(webToken)
                }
            case "activityCategory":
                if let categoryToken = blockedToken.decodedActivityCategoryToken() {
                    categoryTokens.insert(categoryToken)
                }
            default:
                break
            }
        }
        
        selection.applicationTokens = applicationTokens
        selection.webDomainTokens = webDomainTokens
        selection.categoryTokens = categoryTokens
        
        return selection
    }
}
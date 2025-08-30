import Foundation

// MARK: - Bundle Extensions

extension Bundle {
    var appVersion: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }
    
    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }
    
    var appVersionWithBuild: String {
        return "\(appVersion) (\(buildNumber))"
    }
}
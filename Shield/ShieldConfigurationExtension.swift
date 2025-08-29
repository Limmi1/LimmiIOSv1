//
//  ShieldConfigurationExtension.swift
//  Shield
//
//  Created by Attention Holdings on 20/08/2025.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit
import Foundation

// MARK: - UIColor Extension for Hex Colors
extension UIColor {
    /// Initialize UIColor from hex string
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            alpha: Double(a) / 255
        )
    }
}

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    
    // MARK: - Configuration Creation
    
    private func createShieldConfiguration() -> ShieldConfiguration {
        // Check if we should show location verification message
        if shouldShowLocationVerificationMessage() {
            return createLocationVerificationShieldConfiguration()
        } else {
            return createDefaultLimmiShieldConfiguration()
        }
    }
    
    private func createDefaultLimmiShieldConfiguration() -> ShieldConfiguration {
        // Try to get the app icon from main app bundle, fallback to system icon
        let logoImage = getLimmiLogo()
        
        // Use the most vibrant yellow possible with higher alpha for maximum visibility
        let vibrantYellowBackground = UIColor(displayP3Red: 1.0, green: 1.0, blue: 0.0, alpha: 0.25)
        print("🎨 [Shield] Creating default shield with logo: \(logoImage != nil ? "Found" : "Not found")")
        print("🎨 [Shield] Background color: Maximum Vibrant Yellow (alpha: 0.25)")
        print("🎨 [Shield] Button text: OK")
        
        // Create custom shield configuration with Limmi branding
        // Use maximum vibrant yellow background for all shield screens
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial, // Minimal blur to preserve color vibrancy
            backgroundColor: vibrantYellowBackground, // Maximum vibrant yellow background
            icon: logoImage,
            title: ShieldConfiguration.Label(
                text: "Limmi",
                color: .black
            ),
            subtitle: ShieldConfiguration.Label(
                text: "You are being blocked in this space",
                color: .black
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: .white
            ),
            primaryButtonBackgroundColor: .black,
            secondaryButtonLabel: nil
        )
    }
    
    private func createLocationVerificationShieldConfiguration() -> ShieldConfiguration {
        // Get the app icon
        let logoImage = getLimmiLogo()
        
        // Use the most vibrant yellow possible with higher alpha for maximum visibility
        let vibrantYellowBackground = UIColor(displayP3Red: 1.0, green: 1.0, blue: 0.0, alpha: 0.25)
        print("🎨 [Shield] Creating location verification shield with logo: \(logoImage != nil ? "Found" : "Not found")")
        print("🎨 [Shield] Background color: Maximum Vibrant Yellow (alpha: 0.25)")
        print("🎨 [Shield] Button text: OK")
        
        // Create custom shield configuration for location verification
        // Use maximum vibrant yellow background for all shield screens
        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial, // Minimal blur to preserve color vibrancy
            backgroundColor: vibrantYellowBackground, // Maximum vibrant yellow background
            icon: logoImage,
            title: ShieldConfiguration.Label(
                text: "Limmi",
                color: .black
            ),
            subtitle: ShieldConfiguration.Label(
                text: "We need to confirm your location. Open Limmi to update it.",
                color: .black
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: .white
            ),
            primaryButtonBackgroundColor: .black,
            secondaryButtonLabel: nil
            )
    }
    
    // MARK: - Helper Methods
    
    private func shouldShowLocationVerificationMessage() -> Bool {
        // Check if DAM extension is currently handling blocking
        return DamBlockingFlagManager.isFlagSet()
    }
    
    // MARK: - Shared Data Access
    
    /// Minimal version of DAMSharedActiveRuleData for shield use
    private struct ShieldActiveRuleData: Codable {
        let shouldShowLocationVerificationMessage: Bool
        let schemaVersion: Int
        let lastUpdated: Date
        
        func isValid() -> Bool {
            return schemaVersion > 0 && lastUpdated.timeIntervalSince1970 > 0
        }
        
        func isFresh(maxAgeSeconds: TimeInterval = 3600) -> Bool {
            return Date().timeIntervalSince(lastUpdated) <= maxAgeSeconds
        }
    }
    
    private func loadActiveRuleData() -> ShieldActiveRuleData? {
        let appGroupIdentifier = "group.com.ah.limmi.shareddata"
        let activeRuleDataFileName = "activeRuleTokens.json"
        
        // Try loading from file first
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(activeRuleDataFileName)
            
            do {
                let jsonData = try Data(contentsOf: fileURL)
                let data = try JSONDecoder().decode(ShieldActiveRuleData.self, from: jsonData)
                return data.isValid() && data.isFresh() ? data : nil
            } catch {
                // Ignore errors and try fallback
            }
        }
        
        // Fallback to UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
           let jsonData = sharedDefaults.data(forKey: "activeRuleData") {
            do {
                let data = try JSONDecoder().decode(ShieldActiveRuleData.self, from: jsonData)
                return data.isValid() && data.isFresh() ? data : nil
            } catch {
                // Ignore errors
            }
        }
        
        return nil
    }
    
    private func getLimmiLogo() -> UIImage? {
        print("🔍 [Shield] Looking for yellowbrainblacklinedots copy...")
        
        // List all available image names in the bundle for debugging
        let bundle = Bundle(for: ShieldConfigurationExtension.self)
        print("🔍 [Shield] Extension bundle path: \(bundle.bundlePath)")
        if let resourcePath = bundle.resourcePath {
            do {
                let contents = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                print("🔍 [Shield] Bundle contents: \(contents)")
            } catch {
                print("❌ [Shield] Could not read bundle contents: \(error)")
            }
        }
        
        // Try multiple possible image names for the yellow brain logo with dots
        let possibleNames = ["yellowbrainblacklinedots copy", "yellowbrainblacklinedots copy.png", "yellowbrainblacklinedots copy.jpg", "yellowbrainblacklinedots", "yellowbrainblacklinedots.png", "yellowbrainblacklinedots.jpg"]
        
        for imageName in possibleNames {
            print("🔍 [Shield] Trying image name: \(imageName)")
            
            // Try to load from the main app bundle first (most reliable)
            if let brainLogo = UIImage(named: imageName) {
                print("✅ [Shield] Found logo '\(imageName)' with standard approach")
                return brainLogo
            }
            
            // Try to load from extension bundle
            if let brainLogo = UIImage(named: imageName, in: Bundle(for: ShieldConfigurationExtension.self), compatibleWith: nil) {
                print("✅ [Shield] Found logo '\(imageName)' in extension bundle")
                return brainLogo
            }
            
            // Try to load from main app bundle using bundle identifier
            if let mainBundle = Bundle(identifier: "com.ah.limmi"),
               let brainLogo = UIImage(named: imageName, in: mainBundle, compatibleWith: nil) {
                print("✅ [Shield] Found logo '\(imageName)' in main app bundle")
                return brainLogo
            }
        }
        
        print("❌ [Shield] Yellow brain logo not found, trying BlackLimmiBrainLogo as fallback...")
        
        // Fallback to the original BlackLimmiBrainLogo if yellow brain logo not found
        let fallbackNames = ["BlackLimmiBrainLogo", "BlackLimmiBrainLogo.png", "BlackLimmiBrainLogo.jpg"]
        
        for imageName in fallbackNames {
            if let brainLogo = UIImage(named: imageName) {
                print("✅ [Shield] Found fallback logo '\(imageName)'")
                return brainLogo
            }
            
            if let brainLogo = UIImage(named: imageName, in: Bundle(for: ShieldConfigurationExtension.self), compatibleWith: nil) {
                print("✅ [Shield] Found fallback logo '\(imageName)' in extension bundle")
                return brainLogo
            }
            
            if let mainBundle = Bundle(identifier: "com.ah.limmi"),
               let brainLogo = UIImage(named: imageName, in: mainBundle, compatibleWith: nil) {
                print("✅ [Shield] Found fallback logo '\(imageName)' in main app bundle")
                return brainLogo
            }
        }
        
        print("❌ [Shield] No logos found, using system icon fallback")
        
        // Fallback to a system icon that represents the brain/thinking
        if let systemIcon = UIImage(systemName: "brain.head.profile") {
            print("🔄 [Shield] Using brain.head.profile fallback")
            return systemIcon.withTintColor(.black, renderingMode: .alwaysOriginal)
        }
        
        // Alternative brain-related system icon
        if let systemIcon = UIImage(systemName: "lightbulb.fill") {
            print("🔄 [Shield] Using lightbulb.fill fallback")
            return systemIcon.withTintColor(.black, renderingMode: .alwaysOriginal)
        }
        
        // Final fallback
        print("🔄 [Shield] Using app.badge.checkmark final fallback")
        return UIImage(systemName: "app.badge.checkmark")
    }
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        print("🛡️ [Shield] Configuration requested for app: \(application.bundleIdentifier)")
        let config = createShieldConfiguration()
        print("🛡️ [Shield] Returning configuration with button: \(config.primaryButtonLabel?.text ?? "nil")")
        return config
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        print("🛡️ [Shield] Configuration requested for category: \(category)")
        let config = createShieldConfiguration()
        print("🛡️ [Shield] Returning configuration with button: \(config.primaryButtonLabel?.text ?? "nil")")
        return config
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        print("🛡️ [Shield] Configuration requested for web domain: \(webDomain.domain)")
        let config = createShieldConfiguration()
        print("🛡️ [Shield] Returning configuration with button: \(config.primaryButtonLabel?.text ?? "nil")")
        return config
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        print("🛡️ [Shield] Configuration requested for web domain: \(webDomain.domain) in category: \(category)")
        let config = createShieldConfiguration()
        print("🛡️ [Shield] Returning configuration with button: \(config.primaryButtonLabel?.text ?? "nil")")
        return config
    }
}

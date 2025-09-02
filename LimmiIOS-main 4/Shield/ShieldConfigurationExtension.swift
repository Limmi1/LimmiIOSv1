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
        
        // Create custom shield configuration with Limmi branding
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: logoImage,
            title: ShieldConfiguration.Label(
                text: "Limmi",
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "You are being blocked in this space",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: .systemBlue
            ),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: nil
        )
    }
    
    private func createLocationVerificationShieldConfiguration() -> ShieldConfiguration {
        // Get the app icon
        let logoImage = getLimmiLogo()
        
        // Create custom shield configuration for location verification
        
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: logoImage,
            title: ShieldConfiguration.Label(
                text: "Limmi",
                color: .label
            ),
            subtitle: ShieldConfiguration.Label(
                text: "We need to confirm your location. Open Limmi to update it.",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "OK",
                color: .white
            ),
            primaryButtonBackgroundColor: .systemBlue,
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
        // First, try to load from the main app bundle
        if let mainBundle = Bundle.main.url(forResource: "Limmi", withExtension: "app"),
           let appBundle = Bundle(url: mainBundle),
           let appIcon = UIImage(named: "AppIcon", in: appBundle, compatibleWith: nil) {
            return appIcon
        }
        
        // Try to load from extension bundle
        if let appIcon = UIImage(named: "AppIcon", in: Bundle(for: ShieldConfigurationExtension.self), compatibleWith: nil) {
            return appIcon
        }
        
        // Try standard AppIcon approach
        if let appIcon = UIImage(named: "AppIcon") {
            return appIcon
        }
        
        // Fallback to a system icon that represents blocking/restriction
        if let systemIcon = UIImage(systemName: "exclamationmark.shield.fill") {
            return systemIcon.withTintColor(.systemBlue, renderingMode: .alwaysOriginal)
        }
        
        // Final fallback
        return UIImage(systemName: "app.badge.checkmark")
    }
    
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return createShieldConfiguration()
    }
    
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return createShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return createShieldConfiguration()
    }
    
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return createShieldConfiguration()
    }
}

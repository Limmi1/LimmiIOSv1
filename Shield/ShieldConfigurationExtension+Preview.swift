//
//  ShieldConfigurationExtension+Preview.swift
//  Shield
//
//  Created by Attention Holdings on 20/08/2025.
//

import SwiftUI
import ManagedSettings
import ManagedSettingsUI

#if DEBUG
@available(iOS 16.0, *)
struct ShieldConfigurationExtension_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview the default shield configuration
            ShieldPreviewView(
                title: "Limmi",
                subtitle: "This app is currently blocked by your zone settings",
                buttonText: "OK"
            )
            .previewDisplayName("Default Shield")
            
            // Preview the location verification shield configuration
            ShieldPreviewView(
                title: "Limmi",
                subtitle: "We need to confirm your location. Open Limmi to update it.",
                buttonText: "OK"
            )
            .previewDisplayName("Location Verification Shield")
        }
    }
}

@available(iOS 16.0, *)
struct ShieldPreviewView: View {
    let title: String
    let subtitle: String
    let buttonText: String
    
    var body: some View {
        VStack(spacing: 20) {
            // App icon placeholder
            Image(systemName: "app.badge.checkmark")
                .font(.system(size: 60))
                .foregroundColor(.blue)
                .padding()
            
            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            // Subtitle
            Text(subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Primary button
            Button(action: {}) {
                Text(buttonText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding()
    }
}
#endif

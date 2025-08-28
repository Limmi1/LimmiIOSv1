//
//  ShieldConfigurationPreview.swift
//  Shield
//
//  Created by Attention Holdings on 20/08/2025.
//

import SwiftUI
import ManagedSettings
import ManagedSettingsUI

#if DEBUG
@available(iOS 16.0, *)
struct ShieldConfigurationPreview: PreviewProvider {
    static var previews: some View {
        Group {
            // Test the actual ShieldConfigurationExtension
            ShieldConfigurationTestView()
                .previewDisplayName("Shield Configuration Test")
            
            // Show shield configurations in different states
            ShieldConfigurationStatesView()
                .previewDisplayName("Shield States")
        }
    }
}

@available(iOS 16.0, *)
struct ShieldConfigurationTestView: View {
    @State private var selectedApp = "com.example.app"
    @State private var selectedCategory = "Entertainment"
    
    let categories = ["Entertainment", "Social", "Productivity", "Other"]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Shield Configuration Test")
                .font(.title)
                .fontWeight(.bold)
            
            // App selection
            VStack(alignment: .leading) {
                Text("Test Application:")
                TextField("Bundle ID", text: $selectedApp)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Category selection
            VStack(alignment: .leading) {
                Text("Activity Category:")
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            
            // Test shield configuration
            Button("Test Shield Configuration") {
                testShieldConfiguration()
            }
            .buttonStyle(.borderedProminent)
            
            Spacer()
        }
        .padding()
    }
    
    private func testShieldConfiguration() {
        // This would test the actual shield configuration in a real environment
        print("Testing shield configuration for app: \(selectedApp)")
        print("Category: \(selectedCategory)")
    }
}

@available(iOS 16.0, *)
struct ShieldConfigurationStatesView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Shield Configuration States")
                .font(.title)
                .fontWeight(.bold)
            
            // Default shield state
            ShieldStateCard(
                title: "Default Shield",
                description: "App blocked by zone settings",
                icon: "shield.fill",
                color: .blue
            )
            
            // Location verification state
            ShieldStateCard(
                title: "Location Verification",
                description: "Need to confirm location",
                icon: "location.fill",
                color: .orange
            )
            
            // Error state
            ShieldStateCard(
                title: "Error State",
                description: "Fallback system icon",
                icon: "exclamationmark.triangle.fill",
                color: .red
            )
        }
        .padding()
    }
}

@available(iOS 16.0, *)
struct ShieldStateCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}
#endif

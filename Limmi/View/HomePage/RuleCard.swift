import SwiftUI
import MapKit
import CoreLocation

// Simple annotation struct for the map
private struct MapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct RuleCard: View {
    let rule: Rule
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    @EnvironmentObject var blockingEngineViewModel: BlockingEngineViewModel
    @State private var showingEditView = false
    
    private var isCurrentlyBlocking: Bool {
        // Access blockingConditionsChanged to trigger updates when conditions change
        _ = blockingEngineViewModel.blockingConditionsChanged
        return blockingEngineViewModel.isRuleCurrentlyBlocking(rule)
    }
    
    // Computed properties for GPS location map preview
    private var regionForRule: MKCoordinateRegion {
        guard rule.gpsLocation.isActive else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
        let center = CLLocationCoordinate2D(
            latitude: rule.gpsLocation.latitude,
            longitude: rule.gpsLocation.longitude
        )
        
        // Calculate span based on radius to show the full coverage area
        let radiusInDegrees = rule.gpsLocation.radius / 111000.0 // Approximate conversion from meters to degrees
        let span = MKCoordinateSpan(
            latitudeDelta: radiusInDegrees * 2.5, // Show area slightly larger than radius
            longitudeDelta: radiusInDegrees * 2.5
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    private var mapAnnotationsForRule: [MapAnnotation] {
        guard rule.gpsLocation.isActive else { return [] }
        return [MapAnnotation(
            coordinate: CLLocationCoordinate2D(
                latitude: rule.gpsLocation.latitude,
                longitude: rule.gpsLocation.longitude
            )
        )]
    }
    
    private var radiusCircleSizeForRule: CGFloat {
        guard rule.gpsLocation.isActive else { return 0 }
        // Scale the circle size to fit within the 80px map height
        let maxSize: CGFloat = 60 // Leave some margin
        let radiusInDegrees = rule.gpsLocation.radius / 111000.0
        let spanInDegrees = regionForRule.span.latitudeDelta
        let scaleFactor = maxSize / (spanInDegrees * 1000) // Scale factor for visual representation
        return min(maxSize, CGFloat(radiusInDegrees) * scaleFactor)
    }
    
    private var radiusCirclePositionForRule: CGPoint {
        // Center the circle in the 80px map
        return CGPoint(x: 40, y: 40)
    }
    
    var body: some View {
        Button(action: {
            showingEditView = true
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Rule Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(rule.name)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 8) {
                            // Rule Active Status
                            Text(rule.isActive ? "Active" : "Inactive")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(rule.isActive ? .green : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(rule.isActive ? .green.opacity(0.1) : .secondary.opacity(0.1))
                                )
                            
                            // Blocking Status Indicator
                            if rule.isActive {
                                HStack(spacing: 4) {
                                    Image(systemName: isCurrentlyBlocking ? "shield.fill" : "shield")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isCurrentlyBlocking ? .red : .secondary)
                                    
                                    Text(isCurrentlyBlocking ? "Blocking" : "Not Blocking")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(isCurrentlyBlocking ? .red : .secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(isCurrentlyBlocking ? .red.opacity(0.1) : .secondary.opacity(0.1))
                                )
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Rule Info
                VStack(alignment: .leading, spacing: 8) {
                    // Location Info
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        
                        Text("GPS Zone: \(Int(rule.gpsLocation.radius))m radius")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // GPS Location Map Preview
                    if rule.gpsLocation.isActive {
                        VStack(spacing: 4) {
                            ZStack {
                                // Map background placeholder
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray6))
                                    .frame(height: 80)
                                
                                // Map content
                                Map(coordinateRegion: .constant(regionForRule), 
                                     showsUserLocation: false, 
                                     annotationItems: mapAnnotationsForRule) { annotation in
                                    MapPin(coordinate: annotation.coordinate, tint: .blue)
                                }
                                .frame(height: 80)
                                .cornerRadius(8)
                                .overlay(
                                    // Radius circle overlay
                                    Circle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: radiusCircleSizeForRule, height: radiusCircleSizeForRule)
                                        .position(radiusCirclePositionForRule)
                                )
                            }
                            
                            // Location coordinates
                            Text("\(String(format: "%.4f", rule.gpsLocation.latitude)), \(String(format: "%.4f", rule.gpsLocation.longitude))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Beacon Info
                    if !rule.fineLocationRules.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            
                            Text("\(rule.fineLocationRules.count) beacon\(rule.fineLocationRules.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Time Rules Info
                    if !rule.timeRules.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.purple)
                            
                            Text("\(rule.timeRules.count) time rule\(rule.timeRules.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Blocked Content Info
                    if !rule.blockedTokenIds.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "app.badge.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            
                            Text("\(rule.blockedTokenIds.count) blocked item\(rule.blockedTokenIds.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingEditView,
               onDismiss: { NotificationCenter.default.post(name: .didModifyRules, object: nil) }) {
            RuleEditView(rule: rule, authViewModel: authViewModel, ruleStoreViewModel: ruleStoreViewModel)
                .environmentObject(authViewModel)
                .environmentObject(ruleStoreViewModel)
                .environmentObject(blockingEngineViewModel)
        }
    }
}

/*
#Preview {
    RuleCard(
        rule: Rule(name: "Sample Rule")
    )
    .environmentObject(AuthViewModel())
    .environmentObject(RuleStoreViewModel(ruleStore: FirebaseRuleStore()))
    .environmentObject(BlockingEngineViewModel.mock())
    .padding()
}
*/
import SwiftUI
import MapKit
import CoreLocation
import os

struct GPSLocationStepView: View {
    @Binding var gpsLocation: GPSLocation
    let onNext: () -> Void
    let onBack: () -> Void
    
    @StateObject private var locationProvider = CoreLocationProvider()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to SF
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var isLocationLoading = false
    @State private var locationError: String?
    @State private var radiusText: String = "100"
    
    private let logger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "GPSLocationStep")
    )
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    // Location Status and Controls
                    VStack(spacing: 12) {
                        if isLocationLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Getting current location...")
                                    .foregroundColor(.secondary)
                            }
                        } else if let error = locationError {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        } else if gpsLocation.isActive {
                            VStack(spacing: 6) {
                                HStack {
                                    Image(systemName: "location.fill")
                                        .foregroundColor(.green)
                                    Text("GPS Location Set")
                                        .font(.headline)
                                        .foregroundColor(.green)
                                }
                                Text("Lat: \(gpsLocation.latitude, specifier: "%.5f"), Lng: \(gpsLocation.longitude, specifier: "%.5f")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Current Location Button
                        Button(action: setCurrentLocation) {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                Text("Use Current Location")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .padding(.horizontal)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isLocationLoading)
                    }
                    .padding(.horizontal)
                    
                    // Map View - Adaptive height based on screen size
                    VStack(spacing: 10) {
                        Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: mapAnnotations) { annotation in
                            MapPin(coordinate: annotation.coordinate, tint: .blue)
                        }
                        .frame(height: max(200, min(300, geometry.size.height * 0.35)))
                        .cornerRadius(12)
                        .onTapGesture {
                            // Handle tap to set location
                            let coordinate = region.center
                            updateGPSLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                        }
                        
                        // Radius Control
                        VStack(spacing: 6) {
                            Text("Radius: \(Int(gpsLocation.radius))m")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("50m")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Slider(value: Binding(
                                    get: { gpsLocation.radius },
                                    set: { newValue in
                                        gpsLocation.radius = newValue
                                        radiusText = String(Int(newValue))
                                    }
                                ), in: 50...1000, step: 25)
                                
                                Text("1km")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Add some space before buttons, but not too much on small screens
                    Spacer(minLength: geometry.size.height < 600 ? 20 : 40)
                }
                .frame(minHeight: geometry.size.height - 100) // Reserve space for navigation buttons
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Navigation Buttons - Always visible at bottom
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 16) {
                    Button("Back") {
                        onBack()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                    
                    Button("Next") {
                        onNext()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(gpsLocation.isActive ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(!gpsLocation.isActive)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
        }
        .onAppear {
            setupLocation()
        }
    }
    
    private var mapAnnotations: [LocationAnnotation] {
        guard gpsLocation.isActive else { return [] }
        return [LocationAnnotation(coordinate: CLLocationCoordinate2D(latitude: gpsLocation.latitude, longitude: gpsLocation.longitude))]
    }
    
    private func circleSize(for radius: Double) -> CGFloat {
        // Scale the visual radius based on map zoom level
        // This is a simplified calculation - a more sophisticated approach would consider the actual map scale
        return max(20, min(100, CGFloat(radius) / 10))
    }
    
    private func setupLocation() {
        // Initialize radius text
        radiusText = String(Int(gpsLocation.radius))
        
        // Request location permissions
        if locationProvider.authorizationStatus == .notDetermined {
            locationProvider.requestAuthorization()
        }
        
        // Try to get current location if we have permission
        if locationProvider.authorizationStatus == .authorizedWhenInUse || 
           locationProvider.authorizationStatus == .authorizedAlways {
            locationProvider.startLocationUpdates()
        }
    }
    
    private func setCurrentLocation() {
        isLocationLoading = true
        locationError = nil
        
        // Check authorization status
        switch locationProvider.authorizationStatus {
        case .denied, .restricted:
            locationError = "Location access denied. Please enable location services in Settings."
            isLocationLoading = false
            return
        case .notDetermined:
            locationProvider.requestAuthorization()
            isLocationLoading = false
            return
        default:
            break
        }
        
        // Start location updates if not already started
        locationProvider.startLocationUpdates()
        
        // Try to use current location
        if let currentLocation = locationProvider.currentLocation {
            updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                             longitude: currentLocation.coordinate.longitude)
            isLocationLoading = false
        } else {
            // Wait a bit for location to be available
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let currentLocation = self.locationProvider.currentLocation {
                    self.updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                                          longitude: currentLocation.coordinate.longitude)
                } else {
                    self.locationError = "Could not get current location. Please try again or set location on map."
                }
                self.isLocationLoading = false
            }
        }
    }
    
    private func updateGPSLocation(latitude: Double, longitude: Double) {
        gpsLocation = GPSLocation(latitude: latitude, longitude: longitude, radius: gpsLocation.radius)
        
        // Update map region to center on the new location
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        logger.debug("GPS location set: \(latitude), \(longitude), radius: \(gpsLocation.radius)")
    }
}

// Helper struct for map annotations
private struct LocationAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#if DEBUG
struct GPSLocationStepView_Previews: PreviewProvider {
    static var previews: some View {
        GPSLocationStepView(
            gpsLocation: .constant(GPSLocation()),
            onNext: {},
            onBack: {}
        )
    }
}
#endif
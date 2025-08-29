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
                        // Auto-location message
                        if !gpsLocation.isActive && locationProvider.authorizationStatus == .notDetermined {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                                Text("Your current location will be automatically set once you grant location permission")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        
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
                                Text("Location is fixed at your current position")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // Current Location Button
                        Button(action: setCurrentLocation) {
                            HStack {
                                Image(systemName: "location.circle.fill")
                                Text(gpsLocation.isActive ? "Refresh Current Location" : "Set Current Location")
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
                        .overlay(
                            // Radius circle overlay - directly linked to the pin location
                            Group {
                                if gpsLocation.isActive {
                                    Circle()
                                        .stroke(Color.blue, lineWidth: 2)
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: radiusCircleSize, height: radiusCircleSize)
                                        .position(radiusCircleCenterPosition)
                                }
                            }
                        )

                        .frame(height: max(200, min(300, geometry.size.height * 0.35)))
                        .cornerRadius(12)
                        
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
            // Ensure we have a valid map region first
            if region.center.latitude == 0 && region.center.longitude == 0 {
                // Initialize with a default region if none is set
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
            
            setupLocation()
            
            // Also try to get location immediately if we have permission
            if locationProvider.authorizationStatus == .authorizedWhenInUse || 
               locationProvider.authorizationStatus == .authorizedAlways {
                locationProvider.startLocationUpdates()
                
                // Try to get current location immediately
                if let currentLocation = locationProvider.currentLocation {
                    updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                                     longitude: currentLocation.coordinate.longitude)
                }
            }
        }
    }
    
    private var mapAnnotations: [LocationAnnotation] {
        guard gpsLocation.isActive else { return [] }
        // Create a stable annotation to prevent flickering
        let annotation = LocationAnnotation(coordinate: CLLocationCoordinate2D(latitude: gpsLocation.latitude, longitude: gpsLocation.longitude))
        return [annotation]
    }
    
    // Fixed properties for radius circle visualization to prevent flickering
    private var radiusCircleSize: CGFloat {
        // Use a fixed size for the radius circle to prevent flickering
        return 100
    }
    
    private var radiusCircleCenterPosition: CGPoint {
        // Use a fixed center position to prevent flickering
        return CGPoint(x: 187.5, y: 150) // Fixed center position for the map
    }
    
    private func circleSize(for radius: Double) -> CGFloat {
        // Use a fixed size to prevent flickering
        return 100
    }
    
    private func setupLocation() {
        // Initialize radius text
        radiusText = String(Int(gpsLocation.radius))
        
        // Request location permissions
        if locationProvider.authorizationStatus == .notDetermined {
            locationProvider.requestAuthorization()
            // Check again after a short delay to see if authorization was granted
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.checkAndSetLocation()
            }
        } else if locationProvider.authorizationStatus == .authorizedWhenInUse || 
                  locationProvider.authorizationStatus == .authorizedAlways {
            checkAndSetLocation()
        }
        
        // If we already have a GPS location, center the map on it
        if gpsLocation.isActive {
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: gpsLocation.latitude, longitude: gpsLocation.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        } else {
            // If no GPS location yet, try to get current location immediately
            if let currentLocation = locationProvider.currentLocation {
                updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                                 longitude: currentLocation.coordinate.longitude)
            } else {
                // If no current location available yet, set a default region and wait for location
                // This ensures the map has a valid region even before location is available
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to San Francisco
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            }
        }
    }
    
    private func checkAndSetLocation() {
        // Try to get current location if we have permission
        if locationProvider.authorizationStatus == .authorizedWhenInUse || 
           locationProvider.authorizationStatus == .authorizedAlways {
            locationProvider.startLocationUpdates()
            
            // Automatically try to set current location if GPS location is not already active
            if !gpsLocation.isActive {
                // Try to get current location immediately first
                if let currentLocation = locationProvider.currentLocation {
                    updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                                     longitude: currentLocation.coordinate.longitude)
                } else {
                    // Small delay to allow location manager to start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.autoSetCurrentLocation()
                    }
                }
            }
        }
    }
    
    private func autoSetCurrentLocation() {
        // Check if we already have a current location
        if let currentLocation = locationProvider.currentLocation {
            updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                             longitude: currentLocation.coordinate.longitude)
            logger.debug("Auto-set current location: \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
        } else {
            // If no current location yet, wait a bit longer and try again
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let currentLocation = self.locationProvider.currentLocation {
                    self.updateGPSLocation(latitude: currentLocation.coordinate.latitude, 
                                          longitude: currentLocation.coordinate.longitude)
                    self.logger.debug("Auto-set current location (delayed): \(currentLocation.coordinate.latitude), \(currentLocation.coordinate.longitude)")
                }
            }
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
        // This ensures the pin appears at the exact GPS coordinates
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        
        logger.debug("GPS location set: \(latitude), \(longitude), radius: \(gpsLocation.radius)")
        logger.debug("Map region updated to center: \(region.center.latitude), \(region.center.longitude)")
    }
}

// Helper struct for map annotations
private struct LocationAnnotation: Identifiable, Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    
    static func == (lhs: LocationAnnotation, rhs: LocationAnnotation) -> Bool {
        return lhs.coordinate.latitude == rhs.coordinate.latitude && 
               lhs.coordinate.longitude == rhs.coordinate.longitude
    }
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
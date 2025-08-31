import SwiftUI
import CoreLocation

struct BeaconSelectionStepView<Scanner: BeaconScannerProtocol>: View {
    @Binding var selectedBeacon: BeaconDevice?
    let onNext: () -> Void
    let onBack: () -> Void
    let beaconScanner: Scanner
    
    @State private var showingBeaconValidation = false
    @State private var isScanning = false
    
    init(selectedBeacon: Binding<BeaconDevice?>, onNext: @escaping () -> Void, onBack: @escaping () -> Void, beaconScanner: Scanner) {
        self._selectedBeacon = selectedBeacon
        self.onNext = onNext
        self.onBack = onBack
        self.beaconScanner = beaconScanner
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            ScrollView {
                VStack(spacing: 0) {
                    // Page padding: 20pt
                    VStack(spacing: 0) {
                        // Section header → list: 12pt
                        VStack(spacing: 12) {
                            // Beacon list
                            ScanningBeaconsView(
                                isScanning: $isScanning,
                                beaconScanner: beaconScanner,
                                selectedBeacon: $selectedBeacon
                            )
                            
                            // Validation Message
                            if showingBeaconValidation {
                                Label("Please select a beacon to continue", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .transition(.opacity)
                                    .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    Spacer(minLength: 100)
                }
            }
            
            // Continue Button
            VStack(spacing: 0) {
                Divider()
                    .background(Color(.systemGray5))
                
                Button(action: validateAndProceed) {
                    HStack(spacing: 12) {
                        Text("Continue")
                            .font(.system(size: 16, weight: .semibold))
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 16) // 16pt corner radius
                            .fill(selectedBeacon == nil ? DesignSystem.secondaryBlue.opacity(0.3) : DesignSystem.primaryYellow)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(selectedBeacon == nil ? .clear : DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
                    )
                }
                .disabled(selectedBeacon == nil)
                .opacity(selectedBeacon == nil ? 0.6 : 1.0) // Disabled: reduce opacity to ~60%
                .scaleEffect(selectedBeacon == nil ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: selectedBeacon == nil)
                .padding(.horizontal, 20) // Full-width minus 20pt margins
                .padding(.vertical, 16)
            }
            .background(DesignSystem.createRuleCardBackground)
        }
        .background(DesignSystem.subtleYellowBackground)
        .onAppear {
            isScanning = true
            beaconScanner.startScanning()
        }
        .onDisappear {
            if isScanning {
                beaconScanner.stopScanning()
            }
        }
    }
    
    private func validateAndProceed() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showingBeaconValidation = selectedBeacon == nil
        }
        
        if !showingBeaconValidation {
            onNext()
        }
    }
}

// MARK: - Scanning Beacons View

struct ScanningBeaconsView<Scanner: BeaconScannerProtocol>: View {
    @Binding var isScanning: Bool
    @ObservedObject var beaconScanner: Scanner
    @Binding var selectedBeacon: BeaconDevice?
    
    var body: some View {
        VStack(spacing: 20) {
            // Scanning Status
            HStack(spacing: 12) {
                if isScanning {
                    HStack(spacing: 8) {
                        // Animated scanning indicator
                        HStack(spacing: 4) {
                            ForEach(0..<3) { index in
                                Circle()
                                    .fill(DesignSystem.primaryYellow)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(isScanning ? 1.0 : 0.5)
                                    .animation(
                                        Animation.easeInOut(duration: 0.6)
                                            .repeatForever()
                                            .delay(Double(index) * 0.2),
                                        value: isScanning
                                    )
                            }
                        }
                        
                        Text("Discovering nearby beacons")
                            .font(DesignSystem.bodyText)
                            .foregroundColor(DesignSystem.secondaryBlue)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16))
                            .foregroundColor(DesignSystem.secondaryBlue)
                        Text("Scan stopped")
                            .font(DesignSystem.bodyText)
                            .foregroundColor(DesignSystem.secondaryBlue)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            
            // Detected Beacons
            if beaconScanner.devices.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    
                    Text(isScanning ? "Looking for beacons..." : "No beacons found")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    if isScanning {
                        Text("Make sure your beacon is powered on and nearby")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 16) { // Inter-card spacing (16pt)
                    ForEach(beaconScanner.devices) { detectedBeacon in
                        ScannedBeaconCard(
                            detectedBeacon: detectedBeacon,
                            isSelected: selectedBeacon?.uuid == detectedBeacon.uuid &&
                                        selectedBeacon?.major == detectedBeacon.major &&
                                        selectedBeacon?.minor == detectedBeacon.minor,
                            onSelect: {
                                // Convert DetectedBeacon to BeaconDevice for selection
                                selectedBeacon = BeaconDevice(
                                    name: detectedBeacon.name,
                                    uuid: detectedBeacon.uuid,
                                    major: detectedBeacon.major,
                                    minor: detectedBeacon.minor
                                )
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }
}

// MARK: - Scanned Beacon Card

struct ScannedBeaconCard: View {
    let detectedBeacon: DetectedBeacon
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Left: Circular signal badge (48×48)
                ZStack {
                    Circle()
                        .fill(signalColor.opacity(0.08))
                        .frame(width: 48, height: 48)
                    
                    VStack(spacing: 2) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(signalColor)
                        
                        Text("\(detectedBeacon.averagedRSSI)")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(signalColor)
                    }
                }
                
                // Center: Text stack
                VStack(alignment: .leading, spacing: 8) {
                    // Title: SF Pro 17 semibold, single line with tail truncation
                    Text(detectedBeacon.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DesignSystem.pureBlack)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    // Meta: SF Pro 15 regular in a one-line row with middle dots · as separators
                    HStack(spacing: 4) {
                        Text("Major \(detectedBeacon.major)")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(DesignSystem.secondaryBlue)
                        
                        Text("·")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                        
                        Text("Minor \(detectedBeacon.minor)")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(DesignSystem.secondaryBlue)
                        
                        Text("·")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(DesignSystem.secondaryBlue.opacity(0.6))
                        
                        Text(signalQuality)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(signalColor)
                    }
                }
                
                Spacer()
                
                // Right: Radio control (28×28), vertically centered
                ZStack {
                    Circle()
                        .stroke(isSelected ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)
                    
                    if isSelected {
                        Circle()
                            .fill(DesignSystem.primaryYellow)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(16) // Standardize internal padding (16pt)
            .background(DesignSystem.pureWhite)
            .cornerRadius(16) // Use 16pt corner radius
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? DesignSystem.primaryYellow : DesignSystem.secondaryBlue.opacity(0.3), lineWidth: 1)
            )
            .overlay(
                // Selected card: add a 2pt accent stroke (outside the 1pt neutral stroke) for a clear but subtle highlight
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? DesignSystem.primaryYellow : .clear, lineWidth: 2)
                    .padding(1)
            )
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 1) // Soft shadow (y:1, blur:6)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var signalColor: Color {
        if detectedBeacon.averagedRSSI > -50 {
            return .green
        } else if detectedBeacon.averagedRSSI > -70 {
            return .orange
        } else {
            return .red
        }
    }
    
    private var signalQuality: String {
        if detectedBeacon.averagedRSSI > -50 {
            return "Strong"
        } else if detectedBeacon.averagedRSSI > -70 {
            return "Good"
        } else {
            return "Weak"
        }
    }
}

// MARK: - Beacon Selection Card

struct BeaconSelectionCard: View {
    let beacon: BeaconDevice
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Beacon Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? .blue.opacity(0.1) : .gray.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: isSelected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right")
                        .font(.system(size: 20))
                        .foregroundColor(isSelected ? .blue : .gray)
                }
                
                // Beacon Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(beacon.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 12) {
                        Text("UUID: \(beacon.uuid.prefix(8))...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Major: \(beacon.major)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Minor: \(beacon.minor)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? .blue : .gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(.blue)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? .blue.opacity(0.3) : .clear, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.02), radius: 4, x: 0, y: 2)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - SwiftUI Environment-Based Wrapper

/// SwiftUI wrapper that properly uses EnvironmentObject for RuleStore
struct UserBeaconSelectionStepView: View {
    @Binding var selectedBeacon: BeaconDevice?
    let onNext: () -> Void
    let onBack: () -> Void
    
    // Use EnvironmentObject for ViewModel (SwiftUI best practice)
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel
    
    var body: some View {
        InternalBeaconSelectionView(
            selectedBeacon: $selectedBeacon,
            onNext: onNext,
            onBack: onBack,
            ruleStoreViewModel: ruleStoreViewModel
        )
    }
}

/// Internal view that properly manages the scanner lifecycle
private struct InternalBeaconSelectionView: View {
    @Binding var selectedBeacon: BeaconDevice?
    let onNext: () -> Void
    let onBack: () -> Void
    let ruleStoreViewModel: RuleStoreViewModel
    
    // StateObject for owned CoreLocationBeaconScanner
    @StateObject private var scanner: CoreLocationBeaconScanner
    
    init(selectedBeacon: Binding<BeaconDevice?>, onNext: @escaping () -> Void, onBack: @escaping () -> Void, ruleStoreViewModel: RuleStoreViewModel) {
        self._selectedBeacon = selectedBeacon
        self.onNext = onNext
        self.onBack = onBack
        self.ruleStoreViewModel = ruleStoreViewModel
        // Create scanner with the RuleStore from ViewModel
        self._scanner = StateObject(wrappedValue: CoreLocationBeaconScanner(ruleStore: ruleStoreViewModel.ruleStore))
    }
    
    var body: some View {
        BeaconSelectionStepView(
            selectedBeacon: $selectedBeacon,
            onNext: onNext,
            onBack: onBack,
            beaconScanner: scanner
        )
    }
}

// MARK: - Convenience Extensions

extension BeaconSelectionStepView where Scanner == BeaconScanner {
    /// Legacy convenience initializer using BeaconScanner (Bluetooth scanning)
    init(selectedBeacon: Binding<BeaconDevice?>, onNext: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.init(selectedBeacon: selectedBeacon, onNext: onNext, onBack: onBack, beaconScanner: BeaconScanner())
    }
}

#if DEBUG
struct BeaconSelectionStepView_Previews: PreviewProvider {
    static var previews: some View {
        
        BeaconSelectionStepView(
            selectedBeacon: .constant(nil),
            onNext: { },
            onBack: { }
        )
    }
}
#endif

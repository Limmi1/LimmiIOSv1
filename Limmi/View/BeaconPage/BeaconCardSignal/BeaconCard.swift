import SwiftUI
import Firebase
import os
import FirebaseAuth
// Small subview: Device Row
struct DeviceRow: View {
    let device: DetectedBeacon
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .resizable()
                .frame(width: 26, height: 26)
                .foregroundStyle(.purple)
                .padding(8)
                .background(Color.purple.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text("UUID: \(device.uuid)")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text("Major: \(device.major)   Minor: \(device.minor)")
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                Text("Rssi: \(device.averagedRSSI)")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .purple : .gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: .gray.opacity(0.1), radius: 4, x: 0, y: 2)
        .onTapGesture(perform: onTap)
    }
}

// Main View: BeaconCard
struct BeaconCard: View {
    @StateObject var scanner = BeaconScanner()
    @State var goHomePage: Bool = false
    @State private var selectedDevice: DetectedBeacon? = nil
    var ruleName: String
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var ruleStoreViewModel: RuleStoreViewModel

    init(authViewModel: AuthViewModel, ruleName: String) {
        // Using RuleStoreViewModel from environment - no need to create Firebase ViewModels
        self.ruleName = ruleName
    }

    private let beaconCardLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BeaconCard")
    )

    var body: some View {
        VStack(spacing: 16) {
            headerView

            Divider()

            devicesListView

            connectButton
        }
        .padding(.vertical)
        .background(AppColor.shared.beaconCardBack)
        .cornerRadius(20)
        .padding()
        .onAppear { scanner.startScanning() }
        .onDisappear { scanner.stopScanning() }
        .fullScreenCover(isPresented: $goHomePage) {
            RootView()
                .navigationBarBackButtonHidden(true)
        }
    }

    // Header section
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bluetooth Devices")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Select a Limmi beacon device below.")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }

    // Device list or loading view
    private var devicesListView: some View {
        Group {
            if scanner.devices.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("🔍 Scanning for Bluetooth devices...")
                        .foregroundColor(.gray)
                        .font(.footnote)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(scanner.devices) { device in
                            DeviceRow(
                                device: device,
                                isSelected: selectedDevice?.id == device.id,
                                onTap: {
                                    selectedDevice = selectedDevice?.id == device.id ? nil : device
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
                .frame(maxHeight: 250)
            }
        }
    }

    // Connect button
    private var connectButton: some View {
        Button(action: connectToDevice) {
            Text("Connect to Device")
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(AppColor.shared.buttonColor)
.foregroundStyle(AppColor.shared.darkYellow)
                .cornerRadius(12)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // Connect function
    private func connectToDevice() {
        guard let device = selectedDevice else {
            beaconCardLogger.debug("No device selected.")
            return
        }
        
        let newBeacon = BeaconDevice(
            name: device.name,
            uuid: device.uuid,
            major: device.major,
            minor: device.minor
        )
        
        ruleStoreViewModel.ruleStore.saveBeaconDevice(newBeacon) { result in
            switch result {
            case .success(_):
                beaconCardLogger.debug("Beacon device added successfully: \(device.name)")
                beaconCardLogger.debug("Note: To use this beacon in rules, create/edit a rule and add it to fineLocationRules")
                goHomePage = true
            case .failure(let error):
                beaconCardLogger.error("Failed to add beacon device: \(device.name) - \(error.localizedDescription)")
            }
        }
    }
}

// Preview
#Preview {
    let authViewModel = AuthViewModel()
    BeaconCard(authViewModel: authViewModel, ruleName: "testRule")
        .environmentObject(authViewModel)
}

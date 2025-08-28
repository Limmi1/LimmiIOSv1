import Foundation
import CoreBluetooth
import SwiftUI
import os

// MARK: - BeaconScanner Protocol

protocol BeaconScannerProtocol: ObservableObject {
    var devices: [DetectedBeacon] { get }
    
    func startScanning()
    func stopScanning()
    func getBeaconSummary() -> String
}

// Beacon detection model structure (different from Firebase BeaconDevice)
struct DetectedBeacon: Identifiable {
    let id = UUID()
    let uuid: String
    let major: Int
    let minor: Int
    let txPower: Int
    let averagedRSSI: Int
    let lastSeen: Date

    var name: String {
        // Check if it's a known UUID and provide friendly name
        switch uuid {
        case "FDA50693-A4E2-4FB1-AFCF-C6EB07647825":
            return "Estimote \(minor)"
        case "426C7565-4368-6172-6D42-6561636F6E73":
            return "Limmi \(minor)"
        case "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0":
            return "Apple AirLocate \(minor)"
        case "8492E75F-4FD6-469D-B132-043FE94921D8", "F7826DA6-4FA2-4E98-8024-BC5B71E0893E":
            return "Kontakt.io \(minor)"
        case "2F234454-CF6D-4A0F-ADF2-F4911BA9FFA6":
            return "Radius Networks \(minor)"
        case "B9407F30-F5F8-466E-AFF9-25556B57FE6D":
            return "Estimote \(minor)"
        case "A0B13730-3A9A-11E3-AA6E-0800200C9A66":
            return "Gimbal \(minor)"
        case "E4C8A4FC-F68B-470D-959F-29382AF72CE7":
            return "Twocanoes \(minor)"
        default:
            return "iBeacon \(minor)"
        }
    }
    
    // Calculate estimated distance based on RSSI and TX Power
    var estimatedDistance: Double {
        if averagedRSSI == 0 {
            return -1.0
        }
        
        let ratio = Double(txPower - averagedRSSI) / 20.0
        return pow(10, ratio)
    }
}

class BeaconScanner: NSObject, BeaconScannerProtocol, CBCentralManagerDelegate {
    private var centralManager: CBCentralManager!
    private let rssiBufferSize = 5
    private var isScanning = false
    private var cleanupTimer: Timer?
    
    // Beacon ID (uuid+major+minor) -> last RSSI measurements
    private var rssiBuffers: [String: [Int]] = [:]
    
    // Published device list
    @Published var devices: [DetectedBeacon] = []
    
    private let transmitterLogger = UnifiedLogger(
        fileLogger: .shared,
        osLogger: Logger(subsystem: "com.limmi.app", category: "BeaconTransmitter")
    )
    
    // iBeacon constants - iOS filters iBeacons and exposes them via service data
    private let iBeaconServiceUUID = "FFF1"
    private let iBeaconServiceDataUUID = "C5E2"
    private let iBeaconServiceDataLength = 20 // Length of service data payload
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        setupCleanupTimer()
    }
    
    deinit {
        cleanupTimer?.invalidate()
    }
    
    private func setupCleanupTimer() {
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            self?.cleanupOldBeacons()
        }
    }
    
    // MARK: - Public Methods
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            transmitterLogger.error("Bluetooth is not powered on")
            return
        }
        
        guard !isScanning else {
            transmitterLogger.debug("Already scanning")
            return
        }
        
        isScanning = true
        // Scan for all peripherals - we'll filter for iBeacons in the discovery callback
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        transmitterLogger.debug("Started scanning for iBeacons")
    }
    
    func stopScanning() {
        guard isScanning else { return }
        
        isScanning = false
        centralManager.stopScan()
        rssiBuffers.removeAll()
        DispatchQueue.main.async {
            self.devices.removeAll()
        }
        transmitterLogger.debug("Stopped scanning for iBeacons")
    }
    
    /// Get a summary of all discovered beacons
    func getBeaconSummary() -> String {
        let summary = devices.map { beacon in
            "UUID: \(beacon.uuid.prefix(8))... Major: \(beacon.major) Minor: \(beacon.minor) RSSI: \(beacon.averagedRSSI) Distance: \(String(format: "%.1f", beacon.estimatedDistance))m"
        }.joined(separator: "\n")
        
        return summary.isEmpty ? "No beacons detected" : summary
    }
    
    // MARK: - Private Methods
    
    private func beaconKey(uuid: String, major: Int, minor: Int) -> String {
        return "\(uuid)_\(major)_\(minor)"
    }
    
    /// Clean up old beacon entries that haven't been seen recently
    private func cleanupOldBeacons() {
        let currentTime = Date()
        let cleanupInterval: TimeInterval = 10.0 // Remove beacons not seen for 10 seconds
        
        DispatchQueue.main.async {
            self.devices = self.devices.filter { beacon in
                currentTime.timeIntervalSince(beacon.lastSeen) < cleanupInterval
            }
        }
        
        // Also clean up RSSI buffers for old beacons
        let currentBeaconKeys = Set(devices.map { beaconKey(uuid: $0.uuid, major: $0.major, minor: $0.minor) })
        rssiBuffers = rssiBuffers.filter { currentBeaconKeys.contains($0.key) }
    }
    
    /// Parse iBeacon service data from iOS filtered advertisement
    /// iOS splits the UUID: first 2 bytes become service UUID, remaining data contains the rest
    private func parseIBeaconServiceData(_ serviceUUID: CBUUID, data: Data) -> (uuid: String, major: Int, minor: Int, txPower: Int)? {
        
        guard data.count >= 18 else {
            transmitterLogger.debug("Service data too short: \(data.count) bytes, need at least 18")
            return nil
        }
        
        // Reconstruct full UUID from service UUID (first 2 bytes) + remaining data (next 14 bytes)
        let serviceUUIDData = serviceUUID.data
        let remainingUUIDData = data.subdata(in: 0..<14)
        
        // Combine to form the full 16-byte UUID
        var fullUUIDData = Data()
        fullUUIDData.append(serviceUUIDData)
        fullUUIDData.append(remainingUUIDData)
        
        let uuid = UUID(data: fullUUIDData)?.uuidString ?? ""
        
        // Extract Major (2 bytes at offset 14, big endian)
        let major = Int((UInt16(data[14]) << 8) | UInt16(data[15]))
        
        // Extract Minor (2 bytes at offset 16, big endian)  
        let minor = Int((UInt16(data[16]) << 8) | UInt16(data[17]))
        
        // TX Power might be at offset 18 if available, otherwise use default
        let txPower = data.count > 18 ? Int(Int8(bitPattern: data[18])) : -59
        
        transmitterLogger.debug("Successfully parsed iBeacon from service data: ServiceUUID=\(serviceUUID) UUID=\(uuid.prefix(8))... Major=\(major) Minor=\(minor)")
        return (uuid: uuid, major: major, minor: minor, txPower: txPower)
    }
    
    /// Update or add a beacon to the devices list
    private func updateBeacon(uuid: String, major: Int, minor: Int, txPower: Int, rssi: Int) {
        let key = beaconKey(uuid: uuid, major: major, minor: minor)
        
        // Update RSSI buffer
        var buffer = rssiBuffers[key] ?? []
        buffer.append(rssi)
        if buffer.count > rssiBufferSize {
            buffer.removeFirst()
        }
        rssiBuffers[key] = buffer
        
        // Calculate averaged RSSI
        let avgRSSI = buffer.reduce(0, +) / buffer.count
        
        // Update devices list on main thread
        DispatchQueue.main.async {
            if let index = self.devices.firstIndex(where: { 
                self.beaconKey(uuid: $0.uuid, major: $0.major, minor: $0.minor) == key 
            }) {
                // Update existing beacon
                self.devices[index] = DetectedBeacon(
                    uuid: uuid,
                    major: major,
                    minor: minor,
                    txPower: txPower,
                    averagedRSSI: avgRSSI,
                    lastSeen: Date()
                )
            } else {
                // Add new beacon
                let newBeacon = DetectedBeacon(
                    uuid: uuid,
                    major: major,
                    minor: minor,
                    txPower: txPower,
                    averagedRSSI: avgRSSI,
                    lastSeen: Date()
                )
                self.devices.append(newBeacon)
            }
            
            // Sort by signal strength (strongest first)
            self.devices.sort { $0.averagedRSSI > $1.averagedRSSI }
        }
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            transmitterLogger.debug("Bluetooth is powered on")
        case .poweredOff:
            transmitterLogger.debug("Bluetooth is powered off")
            stopScanning()
        case .unsupported:
            transmitterLogger.error("Bluetooth is not supported on this device")
        case .unauthorized:
            transmitterLogger.error("Bluetooth access is unauthorized")
        case .resetting:
            transmitterLogger.debug("Bluetooth is resetting")
        case .unknown:
            transmitterLogger.debug("Bluetooth state is unknown")
        @unknown default:
            transmitterLogger.debug("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Check if this peripheral has manufacturer data
        transmitterLogger.debug("AdvertismentData: \(advertisementData)")
        if RSSI.intValue < -80 {
            return
        }
        
        // Check for iBeacon service advertisement
        // First verify this is an iBeacon by checking for FFF1 service UUID
        guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID],
              serviceUUIDs.contains(CBUUID(string: iBeaconServiceUUID)) else {
            return // Not an iBeacon service
        }
        
        // Get the service data and look for the C5E2 key (first 2 bytes of beacon UUID)
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let (serviceDataUUID, iBeaconData) = serviceData.first else {
            transmitterLogger.debug("No service data found for iBeacon")
            return
        }
        
        
        // Debug: Print the raw service data
        let hexString = iBeaconData.map { String(format: "%02X", $0) }.joined()
        transmitterLogger.debug("Raw iBeacon service data: \(hexString) (length: \(iBeaconData.count))")
        
        // Try to parse as iBeacon service data
        guard let beaconData = parseIBeaconServiceData(serviceDataUUID, data: iBeaconData) else {
            return
        }
        
        // Update beacon with parsed data
        updateBeacon(
            uuid: beaconData.uuid,
            major: beaconData.major,
            minor: beaconData.minor,
            txPower: beaconData.txPower,
            rssi: RSSI.intValue
        )
        
        transmitterLogger.debug("Discovered iBeacon: UUID=\(beaconData.uuid.prefix(8))... Major=\(beaconData.major) Minor=\(beaconData.minor) RSSI=\(RSSI.intValue)")
    }
}

// MARK: - UUID Extension for Data Conversion
extension UUID {
    init?(data: Data) {
        guard data.count == 16 else { return nil }
        
        let uuidBytes = data.withUnsafeBytes { $0.bindMemory(to: UInt8.self) }
        self.init(uuid: (
            uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
            uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
            uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
            uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
        ))
    }
}

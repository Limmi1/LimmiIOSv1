import Foundation

/// Encapsulates signal processing and hysteresis logic for beacon RSSI.
final class BeaconSignalProcessor {
    // MARK: - Types
    enum State {
        case blocked
        case unblocked
    }

    // MARK: - Properties
    private let emaAlpha: Double
    private let blockThreshold: Int
    private let unblockThreshold: Int
    private let requiredConsecutiveCount: Int

    private var emaRssi: Double?
    private var consecutiveBlockCount = 0
    private var consecutiveUnblockCount = 0
    private(set) var state: State = .unblocked

    /// Called when the state changes (block/unblock)
    var onStateChange: ((State, Int) -> Void)?

    // MARK: - Init
    init(
        emaAlpha: Double = 0.15,
        blockThreshold: Int = -65,
        unblockThreshold: Int = -70,
        requiredConsecutiveCount: Int = 5
    ) {
        self.emaAlpha = emaAlpha
        self.blockThreshold = blockThreshold
        self.unblockThreshold = unblockThreshold
        self.requiredConsecutiveCount = requiredConsecutiveCount
    }

    // MARK: - Public Methods
    /// Call this with each new RSSI value. Returns the current state after processing.
    @discardableResult
    func process(rssi: Int) -> State {
        let averagedRssi = addRssiToEma(rssi)
        applyHysteresisLogic(with: averagedRssi)
        return state
    }

    /// Resets the processor (e.g., when beacons are lost or scanning stops)
    func reset() {
        emaRssi = nil
        consecutiveBlockCount = 0
        consecutiveUnblockCount = 0
        state = .unblocked
    }

    // MARK: - Private Methods
    private func addRssiToEma(_ rssi: Int) -> Int {
        if let previousEma = emaRssi {
            emaRssi = emaAlpha * Double(rssi) + (1 - emaAlpha) * previousEma
        } else {
            emaRssi = Double(rssi)
        }
        return Int(emaRssi ?? Double(rssi))
    }

    private func applyHysteresisLogic(with averagedRssi: Int) {
        switch state {
        case .blocked:
            if averagedRssi < unblockThreshold {
                consecutiveUnblockCount += 1
                consecutiveBlockCount = 0
            } else {
                consecutiveUnblockCount = 0
            }
            if consecutiveUnblockCount >= requiredConsecutiveCount {
                state = .unblocked
                consecutiveUnblockCount = 0
                consecutiveBlockCount = 0
                onStateChange?(.unblocked, averagedRssi)
            }
        case .unblocked:
            if averagedRssi > blockThreshold {
                consecutiveBlockCount += 1
                consecutiveUnblockCount = 0
            } else {
                consecutiveBlockCount = 0
            }
            if consecutiveBlockCount >= requiredConsecutiveCount {
                state = .blocked
                consecutiveBlockCount = 0
                consecutiveUnblockCount = 0
                onStateChange?(.blocked, averagedRssi)
            }
        }
    }
} 

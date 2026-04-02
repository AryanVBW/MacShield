import AppKit
import CoreBluetooth
import os.log

private let logger = Logger(subsystem: "com.macshield.app", category: "Watch")

private func watchLog(_ message: String) {
    logger.info("\(message, privacy: .public)")
    NSLog("[MacShield-Watch] %@", message)
    #if DEBUG
    let line = "[\(Date())] \(message)\n"
    let path = "/tmp/macshield-watch.log"
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
    #endif
}

/// Monitors Apple Watch BLE proximity for auto-unlock.
///
/// Uses a hybrid approach:
/// - **Connection** to the paired Watch for reliable RSSI polling.
/// - **Background scanning** with `allowDuplicates` to detect Apple Continuity
///   "Nearby Info" packets, which reveal whether the Watch is on-wrist (unlocked).
/// - **Scan-based RSSI fallback** when connection drops — uses RSSI from discovery
///   callbacks to maintain proximity awareness without an active connection.
///
/// When the paired Watch moves out of range or is taken off wrist,
/// the system triggers a lock. When it returns in range, auto-unlock fires.
final class WatchProximityService: NSObject, ObservableObject {
    static let shared = WatchProximityService()

    /// Callback when the Watch moves out of BLE range.
    var onWatchOutOfRange: (() -> Void)?

    /// Callback when the Watch returns to BLE range.
    var onWatchInRange: (() -> Void)?

    /// Whether the Watch is currently detected in range and unlocked (on wrist).
    @Published private(set) var isWatchInRange = false

    /// Whether the Watch is unlocked (on wrist) based on Continuity Nearby Info.
    /// `nil` means we haven't received lock state data yet (assume unlocked for backward compat).
    @Published private(set) var isWatchUnlocked: Bool?

    /// Whether BLE scanning is active.
    @Published private(set) var isScanning = false

    /// Current Bluetooth authorization status.
    @Published private(set) var bluetoothState: BluetoothState = .unknown

    enum BluetoothState {
        case unknown
        case poweredOn
        case poweredOff
        case unauthorized
        case unsupported
    }

    /// The paired Watch peripheral identifier (persisted).
    @Published var pairedWatchIdentifier: UUID? {
        didSet {
            if let id = pairedWatchIdentifier {
                UserDefaults.standard.set(id.uuidString, forKey: "MacShield.pairedWatchID")
            } else {
                UserDefaults.standard.removeObject(forKey: "MacShield.pairedWatchID")
            }
        }
    }

    /// RSSI threshold: values below this are considered "out of range".
    /// Default: -70 dBm (roughly 2-3 meters).
    var rssiThreshold: Int = -70

    private var centralManager: CBCentralManager?
    private var pairedPeripheral: CBPeripheral?
    private var rssiTimer: Timer?

    /// Periodic health check timer — reconnects if connection was silently lost.
    private var healthCheckTimer: Timer?

    /// Reconnection backoff state.
    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private static let maxReconnectDelay: TimeInterval = 30
    private static let baseReconnectDelay: TimeInterval = 1

    /// Number of consecutive out-of-range RSSI readings before triggering.
    private let outOfRangeCount = 3
    private var consecutiveOutOfRange = 0

    /// Number of consecutive "locked" Nearby Info readings before changing lock state.
    /// Prevents flapping from occasional noisy BLE packets.
    private let lockedReadingsRequired = 5
    private var consecutiveLockedReadings = 0

    /// Timestamp of last RSSI reading (connection or scan-based).
    private var lastRSSITime: Date?

    private override init() {
        super.init()

        // Restore paired Watch ID
        if let stored = UserDefaults.standard.string(forKey: "MacShield.pairedWatchID"),
           let uuid = UUID(uuidString: stored) {
            pairedWatchIdentifier = uuid
        }

        // Restore RSSI threshold from settings
        rssiThreshold = Defaults.shared.appSettings.watchRssiThreshold
    }

    /// Start BLE scanning for the paired Watch.
    func startScanning() {
        guard !isScanning else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
        isScanning = true
        startHealthCheck()
        watchLog("Watch proximity scanning started")
    }

    /// Stop BLE scanning.
    func stopScanning() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempts = 0
        centralManager?.stopScan()
        centralManager = nil
        pairedPeripheral = nil
        isScanning = false
        isWatchInRange = false
        isWatchUnlocked = nil
        consecutiveOutOfRange = 0
        consecutiveLockedReadings = 0
        lastRSSITime = nil
        watchLog("Watch proximity scanning stopped")
    }

    /// Unpair the current Watch.
    func unpair() {
        stopScanning()
        pairedWatchIdentifier = nil
        pairedPeripheral = nil
        watchLog("Watch unpaired")
    }

    // MARK: - Private

    private func startRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.pairedPeripheral?.readRSSI()
        }
        // Use .common mode so polling continues during modal dialogs
        RunLoop.main.add(rssiTimer!, forMode: .common)
    }

    /// Periodic health check: if connection silently dropped, attempt reconnect.
    private func startHealthCheck() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer(timeInterval: 15.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
        RunLoop.main.add(healthCheckTimer!, forMode: .common)
    }

    private func performHealthCheck() {
        guard centralManager?.state == .poweredOn else { return }
        guard pairedWatchIdentifier != nil else { return }

        // If we have a connected peripheral, everything is fine
        if let peripheral = pairedPeripheral, peripheral.state == .connected {
            return
        }

        // Connection lost or never established — attempt reconnect
        // But only if no reconnect is already scheduled (avoid resetting backoff)
        if reconnectTimer == nil {
            watchLog("Health check: no active connection, attempting reconnect")
            attemptReconnect()
        }

        // If no RSSI reading in 20s and we think we're in range, start treating
        // scan-based RSSI as stale and let out-of-range logic kick in
        if isWatchInRange, let last = lastRSSITime, Date().timeIntervalSince(last) > 20 {
            watchLog("Health check: no RSSI for 20s while in-range, incrementing out-of-range")
            consecutiveOutOfRange += 1
            if consecutiveOutOfRange >= outOfRangeCount {
                isWatchInRange = false
                watchLog("Health check: Watch marked OUT OF RANGE (stale RSSI)")
                onWatchOutOfRange?()
            }
        }
    }

    /// Attempt to reconnect to the paired Watch with exponential backoff.
    private func attemptReconnect() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        guard let watchID = pairedWatchIdentifier else { return }

        // Cancel any pending reconnect timer
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        // Try retrievePeripherals first (most reliable after disconnect)
        let peripherals = central.retrievePeripherals(withIdentifiers: [watchID])
        if let peripheral = peripherals.first {
            pairedPeripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
            watchLog("Reconnect attempt #\(reconnectAttempts + 1): connecting to \(watchID.uuidString)")
        } else {
            watchLog("Reconnect: peripheral not found via retrievePeripherals, relying on scan")
            // Clear pairedPeripheral so didDiscover can re-establish it
            pairedPeripheral = nil
        }
    }

    /// Schedule a reconnect with exponential backoff.
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        let delay = min(
            Self.baseReconnectDelay * pow(2.0, Double(reconnectAttempts)),
            Self.maxReconnectDelay
        )
        reconnectAttempts += 1
        watchLog("Scheduling reconnect in \(delay)s (attempt #\(reconnectAttempts))")

        reconnectTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.attemptReconnect()
        }
        RunLoop.main.add(reconnectTimer!, forMode: .common)
    }

    private func handleRSSI(_ rssi: Int) {
        lastRSSITime = Date()

        if rssi < rssiThreshold {
            consecutiveOutOfRange += 1
            if consecutiveOutOfRange >= outOfRangeCount && isWatchInRange {
                isWatchInRange = false
                watchLog("Watch OUT OF RANGE (RSSI: \(rssi), threshold: \(rssiThreshold))")
                onWatchOutOfRange?()
            }
        } else {
            consecutiveOutOfRange = 0
            if !isWatchInRange {
                isWatchInRange = true
                watchLog("Watch IN RANGE (RSSI: \(rssi))")
                onWatchInRange?()
            }
        }
    }

    // MARK: - Nearby Info Parsing

    /// Parse Apple Continuity "Nearby Info" packet from BLE advertisement manufacturer data.
    /// Returns `true` if device is unlocked, `false` if locked, `nil` if not a Nearby Info packet.
    private func parseNearbyInfoLockState(from advertisementData: [String: Any]) -> Bool? {
        guard let mfgData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              mfgData.count >= 6 else { return nil }

        // Check Apple Company ID (0x004C little-endian)
        guard mfgData[0] == 0x4C, mfgData[1] == 0x00 else { return nil }

        // Apple Continuity packets contain multiple TLV (Type-Length-Value) entries after the company ID.
        // We need to iterate through them to find Nearby Info (type 0x10).
        let payload = Array(mfgData.dropFirst(2))
        var offset = 0

        while offset + 1 < payload.count {
            let type = payload[offset]
            let length = Int(payload[offset + 1])
            let dataStart = offset + 2

            if type == 0x10, length >= 3, dataStart + 2 < payload.count {
                // Nearby Info found
                let dataFlags = payload[dataStart + 1]
                let unlocked = (dataFlags & 0x80) != 0
                return unlocked
            }

            offset = dataStart + length
        }

        return nil
    }
}

// MARK: - CBCentralManagerDelegate

extension WatchProximityService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let oldState = bluetoothState
        switch central.state {
        case .poweredOn: bluetoothState = .poweredOn
        case .poweredOff: bluetoothState = .poweredOff
        case .unauthorized: bluetoothState = .unauthorized
        case .unsupported: bluetoothState = .unsupported
        default: bluetoothState = .unknown
        }

        watchLog("Bluetooth state: \(oldState) → \(bluetoothState)")

        // Reactivate app after Bluetooth permission dialog (menu bar app has no Dock icon)
        if oldState != .poweredOn && bluetoothState == .poweredOn {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        guard central.state == .poweredOn else {
            if central.state == .unauthorized {
                watchLog("Bluetooth access not authorized")
            }
            return
        }

        // Reset reconnect backoff on fresh Bluetooth power-on
        reconnectAttempts = 0

        // If we have a paired Watch, try to reconnect
        if let watchID = pairedWatchIdentifier {
            let peripherals = central.retrievePeripherals(withIdentifiers: [watchID])
            if let peripheral = peripherals.first {
                pairedPeripheral = peripheral
                peripheral.delegate = self
                central.connect(peripheral)
                watchLog("Reconnecting to paired Watch: \(watchID.uuidString)")
            } else {
                watchLog("Paired Watch not found via retrievePeripherals, falling through to scan")
            }
        }

        // Always scan with allowDuplicates — picks up Nearby Info from ALL Apple devices
        // (the Watch may broadcast Nearby Info from a different BLE address than the connected one)
        central.scanForPeripherals(withServices: nil, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: true
        ])
        watchLog("Scanning for BLE peripherals (allowDuplicates, Nearby Info detection)...")
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let peripheralName = peripheral.name
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheralName ?? advName

        // --- Nearby Info detection: check lock state from Continuity packets ---
        // Apple Watch rotates BLE addresses for privacy, so Nearby Info may arrive
        // from a different UUID than the paired one.
        // Strategy: Accept "unlocked" from any Apple device (safe — if ANY nearby device
        // reports unlocked, Watch is likely on wrist). Only accept "locked" from the
        // paired Watch UUID to avoid false locks from other devices (iPhone, Mac, etc.).
        if let lockState = parseNearbyInfoLockState(from: advertisementData) {
            let isPairedDevice = peripheral.identifier == pairedWatchIdentifier
            if lockState {
                // Unlocked → accept from any device (safe direction)
                consecutiveLockedReadings = 0
                if isWatchUnlocked != true {
                    watchLog("Watch lock state changed: unlocked=true (from peripheral: \(peripheral.identifier.uuidString), paired: \(isPairedDevice))")
                    isWatchUnlocked = true
                }
            } else if isPairedDevice {
                // Locked → only trust from paired Watch UUID to avoid false locks
                consecutiveLockedReadings += 1
                if consecutiveLockedReadings >= lockedReadingsRequired && isWatchUnlocked != false {
                    watchLog("Watch lock state changed: unlocked=false (after \(consecutiveLockedReadings) readings)")
                    isWatchUnlocked = false
                }
            }
        }

        // --- Scan-based RSSI fallback for paired Watch ---
        // When connection is lost, use RSSI from scan packets to maintain proximity awareness.
        if peripheral.identifier == pairedWatchIdentifier {
            let rssiValue = RSSI.intValue
            // Only use scan RSSI if we don't have an active connection (avoid double-counting)
            if pairedPeripheral == nil || pairedPeripheral?.state != .connected {
                if rssiValue != 127 { // 127 = RSSI unavailable
                    handleRSSI(rssiValue)
                }
            }
        }

        // --- Watch pairing and connection ---
        guard let name, name.localizedCaseInsensitiveContains("watch") else { return }

        // If no Watch is paired, pair with the first one found
        if pairedWatchIdentifier == nil {
            pairedWatchIdentifier = peripheral.identifier
            watchLog("Auto-paired with Watch: \(name) (ID: \(peripheral.identifier.uuidString))")
        }

        guard peripheral.identifier == pairedWatchIdentifier else { return }

        // Only connect if not already connected
        guard pairedPeripheral == nil else { return }

        pairedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
        watchLog("Connecting to Watch: \(name)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        watchLog("Connected to Watch: \(peripheral.identifier.uuidString) (name: \(peripheral.name ?? "nil"))")
        // Reset reconnect backoff on successful connection
        reconnectAttempts = 0
        // Don't set isWatchInRange here — let handleRSSI determine it
        // based on both RSSI threshold AND lock state from Nearby Info.
        startRSSIPolling()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        watchLog("Failed to connect: \(peripheral.identifier.uuidString) error: \(error?.localizedDescription ?? "nil")")
        pairedPeripheral = nil
        // Retry with exponential backoff
        scheduleReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        watchLog("Watch disconnected (error: \(error?.localizedDescription ?? "none"))")
        pairedPeripheral = nil
        rssiTimer?.invalidate()
        rssiTimer = nil

        // Don't immediately mark out of range — scan-based RSSI will continue
        // providing proximity data. Only fire out-of-range if scan RSSI also drops.
        // Keep last known lock state — clearing to nil would default to "unlocked"
        // via (isWatchUnlocked ?? true) in AppDelegate, which is less safe than
        // keeping the last known value.

        // Retry connection with exponential backoff
        reconnectAttempts = 0 // Fresh disconnect, start backoff from 1s
        scheduleReconnect()
    }
}

// MARK: - CBPeripheralDelegate

extension WatchProximityService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else {
            watchLog("RSSI read error: \(error!.localizedDescription)")
            return
        }
        handleRSSI(RSSI.intValue)
    }
}

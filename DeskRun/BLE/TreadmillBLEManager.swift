import Foundation
import CoreBluetooth

class TreadmillBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// The adapter for the currently connected (or connecting) treadmill.
    private var activeAdapter: (any TreadmillAdapter)?

    private let state: TreadmillState
    var onStateUpdate: (() -> Void)?

    /// Discovered devices now include the matched adapter's display name.
    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String, brand: String, rssi: Int)] = []

    init(state: TreadmillState) {
        self.state = state
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            state.connectionStatus = .error
            state.errorMessage = "Bluetooth is not available"
            return
        }
        discoveredDevices = []
        state.connectionStatus = .scanning

        // Scan using service UUIDs from all registered adapters.
        // Pass nil to scan everything if no adapters are registered (dev/debug mode).
        let serviceUUIDs = TreadmillAdapterRegistry.shared.allServiceUUIDs
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

        print("🔍 [BLE] Scanning for treadmills (registered adapters: \(TreadmillAdapterRegistry.shared.registeredAdapterNames.joined(separator: ", ")))")

        // Stop scanning after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if self?.state.connectionStatus == .scanning {
                self?.stopScanning()
            }
        }
    }

    func stopScanning() {
        centralManager.stopScan()
        if state.connectionStatus == .scanning {
            state.connectionStatus = .disconnected
        }
    }

    // MARK: - Connection

    func connect(to peripheral: CBPeripheral) {
        self.peripheral = peripheral
        peripheral.delegate = self
        state.connectionStatus = .connecting
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let peripheral = peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        activeAdapter = nil
        state.connectionStatus = .disconnected
        state.isRunning = false
    }

    // MARK: - Commands (delegated to active adapter)

    func startTreadmill(speed: Double) {
        guard let adapter = activeAdapter else {
            state.errorMessage = "No treadmill adapter active."
            return
        }
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] startTreadmill failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered. Try reconnecting."
            return
        }
        let data = adapter.buildStartCommand(speed: speed)
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending START command, speed=\(speed), bytes=\(data.hexString)")
        peripheral?.writeValue(data, for: char, type: adapter.writeType)
        state.targetSpeed = speed
        state.errorMessage = nil
    }

    func stopTreadmill() {
        guard let adapter = activeAdapter else {
            state.errorMessage = "No treadmill adapter active."
            return
        }
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] stopTreadmill failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }
        let data = adapter.buildStopCommand()
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending STOP command, bytes=\(data.hexString)")
        peripheral?.writeValue(data, for: char, type: adapter.writeType)
        state.targetSpeed = 0
        state.errorMessage = nil
    }

    func pauseTreadmill() {
        guard let adapter = activeAdapter else {
            state.errorMessage = "No treadmill adapter active."
            return
        }
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] pauseTreadmill failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }
        let data = adapter.buildPauseCommand()
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending PAUSE command, bytes=\(data.hexString)")
        peripheral?.writeValue(data, for: char, type: adapter.writeType)
        state.errorMessage = nil
    }

    func setSpeed(_ speed: Double) {
        guard let adapter = activeAdapter else {
            state.errorMessage = "No treadmill adapter active."
            return
        }
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] setSpeed failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }
        let data = adapter.buildSetSpeedCommand(speed: speed)
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending SET SPEED command, speed=\(speed), bytes=\(data.hexString)")
        peripheral?.writeValue(data, for: char, type: adapter.writeType)
        state.targetSpeed = speed
        state.errorMessage = nil
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state != .poweredOn {
            state.connectionStatus = .error
            state.errorMessage = "Bluetooth is not powered on"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"

        // Ask the registry which adapter matches this peripheral
        if let adapter = TreadmillAdapterRegistry.shared.findAdapter(for: peripheral, advertisementData: advertisementData) {
            let brand = type(of: adapter).displayName
            if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices.append((peripheral: peripheral, name: name, brand: brand, rssi: RSSI.intValue))
                print("✅ [BLE] Discovered \(brand) device: \(name) (RSSI: \(RSSI))")
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ [BLE] Connected to \(peripheral.name ?? "unknown")")
        state.connectionStatus = .connected
        state.errorMessage = nil

        // Look up the adapter for this peripheral from our discovered list,
        // or re-match from the registry.
        if activeAdapter == nil {
            // Re-match — we don't have advertisementData here, but we stored the brand.
            // Find the adapter type by matching from the discovered devices list.
            if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
                // Re-create the adapter by asking the registry (with minimal ad data)
                activeAdapter = TreadmillAdapterRegistry.shared.findAdapter(
                    for: peripheral,
                    advertisementData: [CBAdvertisementDataLocalNameKey: device.name]
                )
            }
        }

        guard let adapter = activeAdapter else {
            state.errorMessage = "Connected but no adapter matched — cannot communicate."
            return
        }

        print("🔌 [BLE] Using adapter: \(type(of: adapter).displayName)")
        peripheral.discoverServices([adapter.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state.connectionStatus = .error
        state.errorMessage = error?.localizedDescription ?? "Failed to connect"
        activeAdapter = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state.connectionStatus = .disconnected
        state.isRunning = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
        activeAdapter = nil
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ [BLE] Service discovery error: \(error.localizedDescription)")
            state.errorMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services, let adapter = activeAdapter else {
            print("⚠️ [BLE] No services found on peripheral or no active adapter")
            state.errorMessage = "No BLE services found on treadmill"
            return
        }

        print("🔍 [BLE] Discovered \(services.count) services: \(services.map { $0.uuid.uuidString })")

        var foundTargetService = false
        for service in services {
            if service.uuid == adapter.serviceUUID {
                foundTargetService = true
                print("✅ [BLE] Found target service \(adapter.serviceUUID.uuidString), discovering characteristics...")
                peripheral.discoverCharacteristics(
                    [adapter.writeCharacteristicUUID, adapter.notifyCharacteristicUUID],
                    for: service
                )
            }
        }
        if !foundTargetService {
            print("⚠️ [BLE] Target service \(adapter.serviceUUID.uuidString) NOT found among: \(services.map { $0.uuid.uuidString })")
            state.errorMessage = "Treadmill service (\(adapter.serviceUUID.uuidString)) not found. This may not be a compatible device."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ [BLE] Characteristic discovery error: \(error.localizedDescription)")
            state.errorMessage = "Characteristic discovery failed: \(error.localizedDescription)"
            return
        }
        guard let characteristics = service.characteristics, let adapter = activeAdapter else {
            print("⚠️ [BLE] No characteristics found for service \(service.uuid)")
            return
        }

        print("🔍 [BLE] Discovered \(characteristics.count) characteristics for service \(service.uuid): \(characteristics.map { "\($0.uuid) props=\($0.properties.rawValue)" })")

        for characteristic in characteristics {
            if characteristic.uuid == adapter.writeCharacteristicUUID {
                writeCharacteristic = characteristic
                let props = characteristic.properties
                print("✅ [BLE] Found WRITE characteristic \(characteristic.uuid) — write=\(props.contains(.write)), writeNoResponse=\(props.contains(.writeWithoutResponse))")
            } else if characteristic.uuid == adapter.notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("✅ [BLE] Found NOTIFY characteristic \(characteristic.uuid), subscribed")
            }
        }
        if writeCharacteristic == nil {
            print("⚠️ [BLE] Write characteristic \(adapter.writeCharacteristicUUID) NOT found!")
            state.errorMessage = "Write characteristic (\(adapter.writeCharacteristicUUID)) not found — commands won't work."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ [BLE] Write error for \(characteristic.uuid): \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.state.errorMessage = "BLE write failed: \(error.localizedDescription)"
            }
        } else {
            print("✅ [BLE] Write succeeded for \(characteristic.uuid)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("❌ [BLE] Notification error: \(error.localizedDescription)")
            return
        }
        guard let adapter = activeAdapter,
              characteristic.uuid == adapter.notifyCharacteristicUUID,
              let data = characteristic.value else { return }

        print("📥 [BLE] Notification (\(data.count) bytes): \(data.hexString)")
        let status = adapter.parseNotification(data)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state.currentSpeed = status.speed
            self.state.distance = status.distance
            self.state.steps = status.steps
            self.state.duration = status.duration
            self.state.calories = status.calories
            self.state.isRunning = status.isRunning
            self.onStateUpdate?()
        }
    }
}

// MARK: - Data Hex String Helper

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

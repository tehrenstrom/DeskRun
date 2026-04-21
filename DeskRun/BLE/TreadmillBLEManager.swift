import Foundation
import CoreBluetooth

class TreadmillBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private let state: TreadmillState
    var onStateUpdate: (() -> Void)?

    private let serviceUUID = CBUUID(string: "FBA0")
    private let writeCharUUID = CBUUID(string: "FBA1")
    private let notifyCharUUID = CBUUID(string: "FBA2")

    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String, rssi: Int)] = []

    init(state: TreadmillState) {
        self.state = state
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            state.connectionStatus = .error
            state.errorMessage = "Bluetooth is not available"
            return
        }
        discoveredDevices = []
        state.connectionStatus = .scanning
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])

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
        state.connectionStatus = .disconnected
        state.isRunning = false
    }

    func startTreadmill(speed: Double) {
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] startTreadmill failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered. Try reconnecting."
            return
        }
        let data = PitPatProtocol.buildStartCommand(speed: speed)
        print("📤 [BLE] Sending START command, speed=\(speed), bytes=\(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        peripheral?.writeValue(data, for: char, type: .withoutResponse)
        state.targetSpeed = speed
        state.errorMessage = nil
    }

    func stopTreadmill() {
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] stopTreadmill failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }
        let data = PitPatProtocol.buildStopCommand()
        print("📤 [BLE] Sending STOP command, bytes=\(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        peripheral?.writeValue(data, for: char, type: .withoutResponse)
        state.targetSpeed = 0
        state.errorMessage = nil
    }

    func pauseTreadmill() {
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] pauseTreadmill failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }
        let data = PitPatProtocol.buildPauseCommand()
        print("📤 [BLE] Sending PAUSE command, bytes=\(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        peripheral?.writeValue(data, for: char, type: .withoutResponse)
        state.errorMessage = nil
    }

    func setSpeed(_ speed: Double) {
        guard let char = writeCharacteristic else {
            print("⚠️ [BLE] setSpeed failed: writeCharacteristic is nil!")
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }
        let data = PitPatProtocol.buildStartCommand(speed: speed)
        print("📤 [BLE] Sending SET SPEED command, speed=\(speed), bytes=\(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        peripheral?.writeValue(data, for: char, type: .withoutResponse)
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

        // Only show PitPat devices, but also show all for debugging
        if name.contains("PitPat") || name.contains("DeerRun") {
            if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices.append((peripheral: peripheral, name: name, rssi: RSSI.intValue))
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ [BLE] Connected to \(peripheral.name ?? "unknown")")
        state.connectionStatus = .connected
        state.errorMessage = nil
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state.connectionStatus = .error
        state.errorMessage = error?.localizedDescription ?? "Failed to connect"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state.connectionStatus = .disconnected
        state.isRunning = false
        writeCharacteristic = nil
        notifyCharacteristic = nil
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("❌ [BLE] Service discovery error: \(error.localizedDescription)")
            state.errorMessage = "Service discovery failed: \(error.localizedDescription)"
            return
        }
        guard let services = peripheral.services else {
            print("⚠️ [BLE] No services found on peripheral")
            state.errorMessage = "No BLE services found on treadmill"
            return
        }
        print("🔍 [BLE] Discovered \(services.count) services: \(services.map { $0.uuid.uuidString })")
        var foundTargetService = false
        for service in services {
            if service.uuid == serviceUUID {
                foundTargetService = true
                print("✅ [BLE] Found target service FBA0, discovering characteristics...")
                peripheral.discoverCharacteristics([writeCharUUID, notifyCharUUID], for: service)
            }
        }
        if !foundTargetService {
            print("⚠️ [BLE] Target service FBA0 NOT found among: \(services.map { $0.uuid.uuidString })")
            state.errorMessage = "Treadmill service (FBA0) not found. This may not be a compatible device."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            print("❌ [BLE] Characteristic discovery error: \(error.localizedDescription)")
            state.errorMessage = "Characteristic discovery failed: \(error.localizedDescription)"
            return
        }
        guard let characteristics = service.characteristics else {
            print("⚠️ [BLE] No characteristics found for service \(service.uuid)")
            return
        }
        print("🔍 [BLE] Discovered \(characteristics.count) characteristics for service \(service.uuid): \(characteristics.map { "\($0.uuid) props=\($0.properties.rawValue)" })")
        for characteristic in characteristics {
            if characteristic.uuid == writeCharUUID {
                writeCharacteristic = characteristic
                let props = characteristic.properties
                print("✅ [BLE] Found WRITE characteristic FBA1 — properties: write=\(props.contains(.write)), writeNoResponse=\(props.contains(.writeWithoutResponse))")
            } else if characteristic.uuid == notifyCharUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                print("✅ [BLE] Found NOTIFY characteristic FBA2, subscribed")
            }
        }
        if writeCharacteristic == nil {
            print("⚠️ [BLE] Write characteristic FBA1 NOT found!")
            state.errorMessage = "Write characteristic (FBA1) not found — commands won't work."
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
        guard characteristic.uuid == notifyCharUUID, let data = characteristic.value else { return }
        print("📥 [BLE] Notification (\(data.count) bytes): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        let status = PitPatProtocol.parseNotification(data)

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

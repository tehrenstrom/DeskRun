import Foundation
import CoreBluetooth

class TreadmillBLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    /// The adapter for the currently connected (or connecting) treadmill.
    private var activeAdapter: (any TreadmillAdapter)?

    /// Cache of advertisement data from discovery, keyed by peripheral identifier.
    /// Persisted so that didConnect can re-match using the full original payload
    /// (including manufacturer data, service UUIDs, etc.) instead of synthetic data.
    private var discoveryAdvertisementData: [UUID: [String: Any]] = [:]

    /// Peripherals already emitted to the scan-debug log, so each device is
    /// logged at most once per scan session rather than on every advertisement.
    private var loggedPeripheralIDs: Set<UUID> = []

    private let state: TreadmillState
    var onStateUpdate: (() -> Void)?

    /// Discovered devices now include the matched adapter's display name.
    @Published var discoveredDevices: [(peripheral: CBPeripheral, name: String, brand: String, rssi: Int)] = []

    private enum PitPatUserCommandKind {
        case start
        case setSpeed
        case pause
        case stop
    }

    private enum PitPatCommandAction: String {
        case startMinimum = "start-minimum"
        case setSpeed = "set-speed"
        case pause = "pause"
        case hardStop = "hard-stop"
    }

    private enum PitPatOutboundWriteKind {
        case heartbeat(counter: UInt8?)
        case command(id: UUID, action: PitPatCommandAction, counter: UInt8?)
    }

    private struct PitPatCommandTransaction {
        let id: UUID
        let kind: PitPatUserCommandKind
        let action: PitPatCommandAction
        let requestedTargetSpeed: Double?
        let queuedAt: Date
        let commandCounter: UInt8?
        let beforeStatus: TreadmillStatus
        let fallbackToHardStopOnTimeout: Bool
        var sentAt: Date?
        var notificationCount: Int = 0
        var transportWriteAccepted = false
    }

    private var activePitPatTransaction: PitPatCommandTransaction?
    private var pitPatTimeoutWorkItem: DispatchWorkItem?
    private var queuedPitPatPacket: Data?
    private var pitPatPendingWriteKind: PitPatOutboundWriteKind?
    private var pendingPitPatTargetSpeed: Double?
    private var lastPitPatStatus: TreadmillStatus?
    private let pitPatSpeedTolerance = 0.15

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
        loggedPeripheralIDs = []
        state.connectionStatus = .scanning

        // Scan for all peripherals rather than filtering by service UUID.
        // The registry's matches() method handles brand identification during discovery.
        // This ensures we don't miss devices that advertise differently than expected.
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
        resetPitPatSession()
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
        resetPitPatSession()
    }

    // MARK: - Commands

    func startTreadmill(speed: Double) {
        guard let adapter = activeAdapter else {
            state.commandStatus = .rejected
            state.errorMessage = "No treadmill adapter active."
            return
        }

        if let pitPatAdapter = adapter as? PitPatAdapter {
            handlePitPatStart(speed: speed, adapter: pitPatAdapter)
            return
        }

        guard let char = writeCharacteristic, let peripheral = peripheral else {
            print("⚠️ [BLE] startTreadmill failed: writeCharacteristic is nil!")
            state.commandStatus = .rejected
            state.errorMessage = "Cannot send command — write characteristic not discovered. Try reconnecting."
            return
        }

        let data = adapter.buildStartCommand(speed: speed)
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending START command, speed=\(speed), bytes=\(data.hexString)")
        peripheral.writeValue(data, for: char, type: adapter.writeType)
        state.targetSpeed = speed
        state.errorMessage = nil
    }

    func stopTreadmill() {
        guard let adapter = activeAdapter else {
            state.commandStatus = .rejected
            state.errorMessage = "No treadmill adapter active."
            return
        }

        if let pitPatAdapter = adapter as? PitPatAdapter {
            handlePitPatStop(adapter: pitPatAdapter)
            return
        }

        guard let char = writeCharacteristic, let peripheral = peripheral else {
            print("⚠️ [BLE] stopTreadmill failed: writeCharacteristic is nil!")
            state.commandStatus = .rejected
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }

        let data = adapter.buildStopCommand()
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending STOP command, bytes=\(data.hexString)")
        peripheral.writeValue(data, for: char, type: adapter.writeType)
        state.targetSpeed = 0
        state.errorMessage = nil
    }

    func pauseTreadmill() {
        guard let adapter = activeAdapter else {
            state.commandStatus = .rejected
            state.errorMessage = "No treadmill adapter active."
            return
        }

        if let pitPatAdapter = adapter as? PitPatAdapter {
            handlePitPatPause(adapter: pitPatAdapter)
            return
        }

        guard let char = writeCharacteristic, let peripheral = peripheral else {
            print("⚠️ [BLE] pauseTreadmill failed: writeCharacteristic is nil!")
            state.commandStatus = .rejected
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }

        let data = adapter.buildPauseCommand()
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending PAUSE command, bytes=\(data.hexString)")
        peripheral.writeValue(data, for: char, type: adapter.writeType)
        state.errorMessage = nil
    }

    func setSpeed(_ speed: Double) {
        guard let adapter = activeAdapter else {
            state.commandStatus = .rejected
            state.errorMessage = "No treadmill adapter active."
            return
        }

        if let pitPatAdapter = adapter as? PitPatAdapter {
            handlePitPatSetSpeed(speed, adapter: pitPatAdapter)
            return
        }

        guard let char = writeCharacteristic, let peripheral = peripheral else {
            print("⚠️ [BLE] setSpeed failed: writeCharacteristic is nil!")
            state.commandStatus = .rejected
            state.errorMessage = "Cannot send command — write characteristic not discovered."
            return
        }

        let data = adapter.buildSetSpeedCommand(speed: speed)
        print("📤 [BLE] [\(type(of: adapter).displayName)] Sending SET SPEED command, speed=\(speed), bytes=\(data.hexString)")
        peripheral.writeValue(data, for: char, type: adapter.writeType)
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

        if let adapter = TreadmillAdapterRegistry.shared.findAdapter(for: peripheral, advertisementData: advertisementData) {
            let brand = type(of: adapter).displayName
            discoveryAdvertisementData[peripheral.identifier] = advertisementData
            if !discoveredDevices.contains(where: { $0.peripheral.identifier == peripheral.identifier }) {
                discoveredDevices.append((peripheral: peripheral, name: name, brand: brand, rssi: RSSI.intValue))
                print("✅ [BLE] Discovered \(brand) device: \(name) (RSSI: \(RSSI))")
            }
        } else if !loggedPeripheralIDs.contains(peripheral.identifier) {
            loggedPeripheralIDs.insert(peripheral.identifier)

            let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "<nil>"
            let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?
                .map { $0.uuidString }
                .joined(separator: ",") ?? "<none>"
            let mfgData = (advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data)?.hexString ?? "<none>"

            print("🔎 [BLE scan-debug] unmatched: name=\(peripheral.name ?? "<nil>") localName=\(localName) services=[\(serviceUUIDs)] mfg=\(mfgData) rssi=\(RSSI)")
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("✅ [BLE] Connected to \(peripheral.name ?? "unknown")")
        state.connectionStatus = .connected
        state.errorMessage = nil
        state.commandStatus = .idle
        resetPitPatSession()

        if let cachedAdData = discoveryAdvertisementData[peripheral.identifier] {
            activeAdapter = TreadmillAdapterRegistry.shared.findAdapter(
                for: peripheral,
                advertisementData: cachedAdData
            )
        } else if let device = discoveredDevices.first(where: { $0.peripheral.identifier == peripheral.identifier }) {
            activeAdapter = TreadmillAdapterRegistry.shared.findAdapter(
                for: peripheral,
                advertisementData: [CBAdvertisementDataLocalNameKey: device.name]
            )
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
        resetPitPatSession()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        state.connectionStatus = .disconnected
        state.isRunning = false
        state.commandStatus = .idle
        writeCharacteristic = nil
        notifyCharacteristic = nil
        activeAdapter = nil
        resetPitPatSession()
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
            if let pendingWrite = pitPatPendingWriteKind {
                pitPatPendingWriteKind = nil

                switch pendingWrite {
                case .command(let id, let action, let counter):
                    if let tx = activePitPatTransaction, tx.id == id {
                        logPitPatTransactionOutcome(
                            prefix: "❌ [BLE] [PitPat] ATT write failed for \(action.rawValue), counter=\(counter?.hexByte ?? "--")",
                            transaction: tx,
                            before: tx.beforeStatus,
                            after: lastPitPatStatus ?? tx.beforeStatus
                        )
                        clearPitPatTransactionState()
                        state.commandStatus = .rejected
                        state.errorMessage = "BLE write failed: \(error.localizedDescription)"
                    } else {
                        print("❌ [BLE] [PitPat] ATT write failed for \(action.rawValue), counter=\(counter?.hexByte ?? "--"): \(error.localizedDescription)")
                    }

                case .heartbeat(let counter):
                    print("❌ [BLE] [PitPat] Heartbeat write failed, counter=\(counter?.hexByte ?? "--"): \(error.localizedDescription)")
                }
                return
            }

            print("❌ [BLE] Write error for \(characteristic.uuid): \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.state.errorMessage = "BLE write failed: \(error.localizedDescription)"
            }
            return
        }

        if let pendingWrite = pitPatPendingWriteKind {
            pitPatPendingWriteKind = nil

            switch pendingWrite {
            case .command(let id, let action, let counter):
                if var tx = activePitPatTransaction, tx.id == id {
                    tx.transportWriteAccepted = true
                    activePitPatTransaction = tx
                }
                print("✅ [BLE] [PitPat] ATT write accepted for \(action.rawValue), counter=\(counter?.hexByte ?? "--")")

            case .heartbeat(let counter):
                print("✅ [BLE] [PitPat] Heartbeat write accepted, counter=\(counter?.hexByte ?? "--")")
            }
            return
        }

        print("✅ [BLE] Write succeeded for \(characteristic.uuid)")
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

        if adapter is PitPatAdapter {
            lastPitPatStatus = status
            processPitPatStatus(status)
        }

        if adapter is PitPatAdapter,
           let char = writeCharacteristic {
            if let packet = queuedPitPatPacket,
               var tx = activePitPatTransaction,
               tx.sentAt == nil {
                tx.sentAt = Date()
                activePitPatTransaction = tx
                queuedPitPatPacket = nil
                pitPatPendingWriteKind = .command(id: tx.id, action: tx.action, counter: tx.commandCounter)
                schedulePitPatTimeout(for: tx.id)
                print("📤 [BLE] [PitPat] dispatching action=\(tx.action.rawValue) on notify slot, counter=\(tx.commandCounter?.hexByte ?? "--"), bytes=\(packet.hexString)")
                peripheral.writeValue(packet, for: char, type: adapter.writeType)
            } else if let reply = adapter.onNotificationReceived() {
                pitPatPendingWriteKind = .heartbeat(counter: reply.packetCounter)
                peripheral.writeValue(reply, for: char, type: adapter.writeType)
            }
        } else if let reply = adapter.onNotificationReceived(),
                  let char = writeCharacteristic {
            peripheral.writeValue(reply, for: char, type: adapter.writeType)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.state.currentSpeed = status.speed
            self.state.distance = status.distance
            self.state.duration = status.duration
            self.state.calories = status.calories
            self.state.isRunning = status.isRunning
            self.onStateUpdate?()
        }
    }

    // MARK: - PitPat Command Handling

    private var pitPatAdapter: PitPatAdapter? {
        activeAdapter as? PitPatAdapter
    }

    private var pitPatCommandTimeout: TimeInterval {
        pitPatAdapter?.commandAcceptanceTimeout ?? 2.0
    }

    private var pitPatCommandNotificationLimit: Int {
        pitPatAdapter?.commandAcceptanceNotificationLimit ?? 3
    }

    private func handlePitPatStart(speed: Double, adapter: PitPatAdapter) {
        let requestedSpeed = max(speed, adapter.minimumStartSpeed)
        state.targetSpeed = requestedSpeed

        if let tx = activePitPatTransaction, tx.action == .startMinimum {
            pendingPitPatTargetSpeed = requestedSpeed
            print("🧭 [BLE] [PitPat] Updated pending post-start speed to \(requestedSpeed.formattedSpeed)")
            return
        }

        guard activePitPatTransaction == nil else {
            rejectPitPatCommand("A treadmill command is already pending.")
            return
        }

        pendingPitPatTargetSpeed = requestedSpeed

        if state.isRunning {
            beginPitPatTransaction(
                kind: .setSpeed,
                action: .setSpeed,
                packet: adapter.buildSetSpeedCommand(speed: requestedSpeed),
                requestedTargetSpeed: requestedSpeed
            )
            return
        }

        beginPitPatTransaction(
            kind: .start,
            action: .startMinimum,
            packet: adapter.buildStartCommand(speed: adapter.minimumStartSpeed),
            requestedTargetSpeed: requestedSpeed
        )
    }

    private func handlePitPatSetSpeed(_ speed: Double, adapter: PitPatAdapter) {
        state.targetSpeed = speed

        if let tx = activePitPatTransaction, tx.action == .startMinimum {
            pendingPitPatTargetSpeed = speed
            print("🧭 [BLE] [PitPat] Updated pending post-start speed to \(speed.formattedSpeed)")
            return
        }

        guard activePitPatTransaction == nil else {
            rejectPitPatCommand("A treadmill command is already pending.")
            return
        }

        if !state.isRunning {
            pendingPitPatTargetSpeed = speed
            state.commandStatus = .idle
            state.errorMessage = nil
            print("🧭 [BLE] [PitPat] Stored idle target speed \(speed.formattedSpeed) for the next app-driven start")
            return
        }

        if let lastStatus = lastPitPatStatus, pitPatSpeedMatchesExpectation(lastStatus, requested: speed) {
            state.commandStatus = .accepted
            state.errorMessage = nil
            print("🧭 [BLE] [PitPat] Requested speed already active at \(speed.formattedSpeed); no command sent")
            return
        }

        pendingPitPatTargetSpeed = speed
        beginPitPatTransaction(
            kind: .setSpeed,
            action: .setSpeed,
            packet: adapter.buildSetSpeedCommand(speed: speed),
            requestedTargetSpeed: speed
        )
    }

    private func handlePitPatPause(adapter: PitPatAdapter) {
        guard activePitPatTransaction == nil else {
            rejectPitPatCommand("A treadmill command is already pending.")
            return
        }

        beginPitPatTransaction(
            kind: .pause,
            action: .pause,
            packet: adapter.buildPauseCommand(),
            requestedTargetSpeed: 0
        )
    }

    private func handlePitPatStop(adapter: PitPatAdapter) {
        state.targetSpeed = 0
        pendingPitPatTargetSpeed = nil

        guard activePitPatTransaction == nil else {
            rejectPitPatCommand("A treadmill command is already pending.")
            return
        }

        let isRunning = lastPitPatStatus?.isRunning ?? state.isRunning
        if isRunning {
            beginPitPatTransaction(
                kind: .stop,
                action: .pause,
                packet: adapter.buildPauseCommand(),
                requestedTargetSpeed: 0,
                fallbackToHardStopOnTimeout: true
            )
            return
        }

        beginPitPatTransaction(
            kind: .stop,
            action: .hardStop,
            packet: adapter.buildStopCommand(),
            requestedTargetSpeed: 0
        )
    }

    private func beginPitPatTransaction(
        kind: PitPatUserCommandKind,
        action: PitPatCommandAction,
        packet: Data,
        requestedTargetSpeed: Double?,
        fallbackToHardStopOnTimeout: Bool = false
    ) {
        guard pitPatAdapter != nil,
              peripheral != nil,
              writeCharacteristic != nil else {
            rejectPitPatCommand("Cannot send command — write characteristic not discovered.")
            return
        }
        guard activePitPatTransaction == nil else {
            rejectPitPatCommand("A treadmill command is already pending.")
            return
        }

        let beforeStatus = currentPitPatStatusSnapshot()
        let tx = PitPatCommandTransaction(
            id: UUID(),
            kind: kind,
            action: action,
            requestedTargetSpeed: requestedTargetSpeed,
            queuedAt: Date(),
            commandCounter: packet.packetCounter,
            beforeStatus: beforeStatus,
            fallbackToHardStopOnTimeout: fallbackToHardStopOnTimeout,
            sentAt: nil
        )

        activePitPatTransaction = tx
        queuedPitPatPacket = packet
        state.commandStatus = .pending
        state.errorMessage = nil

        let speedPart = requestedTargetSpeed.map { ", requested=\($0.formattedSpeed)" } ?? ""
        print("🧭 [BLE] [PitPat] queued action=\(action.rawValue), counter=\(tx.commandCounter?.hexByte ?? "--")\(speedPart), mode=\(pitPatUnitSummary(beforeStatus)), before=\(pitPatStatusSummary(beforeStatus)), bytes=\(packet.hexString)")
    }

    private func processPitPatStatus(_ status: TreadmillStatus) {
        print("📊 [BLE] [PitPat] status=\(pitPatStatusSummary(status))")

        guard var tx = activePitPatTransaction else { return }
        guard let sentAt = tx.sentAt else {
            activePitPatTransaction = tx
            return
        }

        tx.notificationCount += 1
        activePitPatTransaction = tx

        if pitPatTransactionAccepted(tx, after: status) {
            logPitPatTransactionOutcome(
                prefix: "✅ [BLE] [PitPat] Command accepted",
                transaction: tx,
                before: tx.beforeStatus,
                after: status
            )
            finishPitPatTransactionSuccess(tx, after: status)
            return
        }

        let age = Date().timeIntervalSince(sentAt)
        if tx.notificationCount >= pitPatCommandNotificationLimit || age >= pitPatCommandTimeout {
            let reason: String
            if tx.notificationCount >= pitPatCommandNotificationLimit {
                reason = "\(tx.notificationCount) status frames"
            } else {
                reason = String(format: "%.1fs", age)
            }
            handlePitPatTransactionTimeout(tx, after: status, reason: reason)
        }
    }

    private func pitPatTransactionAccepted(_ tx: PitPatCommandTransaction, after status: TreadmillStatus) -> Bool {
        switch tx.action {
        case .startMinimum:
            return status.isRunning || status.speed > 0.1

        case .setSpeed:
            guard let requested = tx.requestedTargetSpeed, status.isRunning else {
                return false
            }
            if pitPatSpeedMatchesExpectation(status, requested: requested) {
                return true
            }

            let before = tx.beforeStatus
            let speedMovedCloser = abs(status.speed - requested) + pitPatSpeedTolerance < abs(before.speed - requested)
            let targetMovedCloser: Bool
            if let afterTarget = status.reportedTargetSpeed, let beforeTarget = before.reportedTargetSpeed {
                targetMovedCloser = abs(afterTarget - requested) + pitPatSpeedTolerance < abs(beforeTarget - requested)
            } else {
                targetMovedCloser = false
            }
            return speedMovedCloser || targetMovedCloser

        case .pause, .hardStop:
            return !status.isRunning || status.speed < 0.1
        }
    }

    private func pitPatSpeedMatchesExpectation(_ status: TreadmillStatus, requested: Double) -> Bool {
        if let target = status.reportedTargetSpeed, abs(target - requested) <= pitPatSpeedTolerance {
            return true
        }
        return abs(status.speed - requested) <= max(pitPatSpeedTolerance, 0.2)
    }

    private func finishPitPatTransactionSuccess(_ tx: PitPatCommandTransaction, after status: TreadmillStatus) {
        clearPitPatTransactionState()

        switch tx.action {
        case .startMinimum:
            let desiredSpeed = pendingPitPatTargetSpeed ?? tx.requestedTargetSpeed ?? pitPatAdapter?.minimumStartSpeed ?? status.statusSpeedFallback
            let minimumStartSpeed = pitPatAdapter?.minimumStartSpeed ?? 1.0
            if desiredSpeed > minimumStartSpeed + pitPatSpeedTolerance,
               let adapter = pitPatAdapter {
                print("📤 [BLE] [PitPat] Start accepted, issuing follow-up speed command to \(desiredSpeed.formattedSpeed)")
                beginPitPatTransaction(
                    kind: .setSpeed,
                    action: .setSpeed,
                    packet: adapter.buildSetSpeedCommand(speed: desiredSpeed),
                    requestedTargetSpeed: desiredSpeed
                )
                return
            }
            pendingPitPatTargetSpeed = nil

        case .setSpeed:
            pendingPitPatTargetSpeed = nil

        case .pause, .hardStop:
            pendingPitPatTargetSpeed = nil
        }

        state.commandStatus = .accepted
        state.errorMessage = nil
    }

    private func handlePitPatTransactionTimeout(_ tx: PitPatCommandTransaction, after status: TreadmillStatus?, reason: String) {
        guard activePitPatTransaction?.id == tx.id else { return }

        let afterStatus = status ?? lastPitPatStatus ?? currentPitPatStatusSnapshot()
        logPitPatTransactionOutcome(
            prefix: "⚠️ [BLE] [PitPat] Command timed out after \(reason)",
            transaction: tx,
            before: tx.beforeStatus,
            after: afterStatus
        )

        clearPitPatTransactionState()

        if tx.fallbackToHardStopOnTimeout, afterStatus.isRunning, let adapter = pitPatAdapter {
            print("⚠️ [BLE] [PitPat] Soft stop was not accepted; escalating to hard stop")
            beginPitPatTransaction(
                kind: .stop,
                action: .hardStop,
                packet: adapter.buildStopCommand(),
                requestedTargetSpeed: 0
            )
            return
        }

        state.commandStatus = .timedOut
        state.errorMessage = "PitPat command was written, but treadmill state did not change."
    }

    private func schedulePitPatTimeout(for id: UUID) {
        pitPatTimeoutWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self,
                  let tx = self.activePitPatTransaction,
                  tx.id == id else { return }
            self.handlePitPatTransactionTimeout(tx, after: self.lastPitPatStatus, reason: String(format: "%.1fs wall clock", self.pitPatCommandTimeout))
        }
        pitPatTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + pitPatCommandTimeout, execute: workItem)
    }

    private func clearPitPatTransactionState() {
        pitPatTimeoutWorkItem?.cancel()
        pitPatTimeoutWorkItem = nil
        activePitPatTransaction = nil
        queuedPitPatPacket = nil
        pitPatPendingWriteKind = nil
    }

    private func rejectPitPatCommand(_ message: String) {
        state.commandStatus = .rejected
        state.errorMessage = message
        print("⚠️ [BLE] [PitPat] \(message)")
    }

    private func resetPitPatSession() {
        clearPitPatTransactionState()
        pendingPitPatTargetSpeed = nil
        lastPitPatStatus = nil
        state.commandStatus = .idle
    }

    private func currentPitPatStatusSnapshot() -> TreadmillStatus {
        if let lastPitPatStatus {
            return lastPitPatStatus
        }

        var snapshot = TreadmillStatus()
        snapshot.speed = state.currentSpeed
        snapshot.distance = state.distance
        snapshot.duration = state.duration
        snapshot.calories = state.calories
        snapshot.isRunning = state.isRunning
        return snapshot
    }

    private func pitPatStatusSummary(_ status: TreadmillStatus) -> String {
        let firmware = status.pitPatFirmwareVersion?.hexByte ?? "--"
        let flags = status.pitPatStateFlags?.hexByte ?? "--"
        let current = pitPatSpeedSummary(
            normalized: status.speed,
            raw: status.pitPatRawCurrentSpeed,
            usesImperialUnits: status.pitPatUsesImperialUnits
        )
        let target = status.reportedTargetSpeed.map {
            pitPatSpeedSummary(
                normalized: $0,
                raw: status.pitPatRawTargetSpeed,
                usesImperialUnits: status.pitPatUsesImperialUnits
            )
        } ?? "--"
        return "speed=\(current), target=\(target), running=\(status.isRunning), mode=\(pitPatUnitSummary(status)), firmware=\(firmware), flags=\(flags)"
    }

    private func logPitPatTransactionOutcome(
        prefix: String,
        transaction: PitPatCommandTransaction,
        before: TreadmillStatus,
        after: TreadmillStatus
    ) {
        print("\(prefix), action=\(transaction.action.rawValue), counter=\(transaction.commandCounter?.hexByte ?? "--"), before={\(pitPatStatusSummary(before))}, after={\(pitPatStatusSummary(after))}")
    }

    private func pitPatSpeedSummary(
        normalized: Double,
        raw: UInt16?,
        usesImperialUnits: Bool?
    ) -> String {
        guard let raw else {
            return normalized.formattedSpeed
        }

        let rawSpeedText = String(format: "%.1f", Double(raw) / 1000.0)
        if usesImperialUnits == true {
            return "\(normalized.formattedSpeed) (\(rawSpeedText) mph raw)"
        }

        return "\(normalized.formattedSpeed) (raw \(rawSpeedText) km/h)"
    }

    private func pitPatUnitSummary(_ status: TreadmillStatus) -> String {
        status.pitPatUsesImperialUnits == true ? "imperial" : "metric"
    }
}

// MARK: - Data Helpers

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var packetCounter: UInt8? {
        guard count >= 4,
              self[startIndex] == 0x4D,
              self[startIndex.advanced(by: 1)] == 0x00 else {
            return nil
        }
        return self[startIndex.advanced(by: 2)]
    }
}

private extension UInt8 {
    var hexByte: String {
        String(format: "%02X", self)
    }
}

private extension Double {
    var formattedSpeed: String {
        String(format: "%.1f km/h", self)
    }
}

private extension TreadmillStatus {
    var statusSpeedFallback: Double {
        reportedTargetSpeed ?? speed
    }
}

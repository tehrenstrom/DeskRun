import SwiftUI

struct ConnectionView: View {
    let state: TreadmillState
    @ObservedObject var bleManager: TreadmillBLEManager

    var body: some View {
        VStack(spacing: 20) {
            // Status
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(state.connectionStatus.rawValue)
                    .font(.headline)
            }
            .padding()

            if let error = state.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            // Scan button
            if state.connectionStatus == .disconnected || state.connectionStatus == .error {
                Button("Scan for Treadmill") {
                    bleManager.startScanning()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if state.connectionStatus == .scanning {
                Button("Stop Scanning") {
                    bleManager.stopScanning()
                }
                .buttonStyle(.bordered)
            } else if state.connectionStatus == .connected {
                // Quick controls right here so user doesn't have to navigate
                VStack(spacing: 12) {
                    Divider()
                    Text("Quick Controls")
                        .font(.headline)

                    if state.isRunning {
                        HStack(spacing: 12) {
                            Button("Pause") {
                                bleManager.pauseTreadmill()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)

                            Button("Stop") {
                                bleManager.stopTreadmill()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.large)
                        }
                    } else {
                        Button("Start Walking (3.0 km/h)") {
                            bleManager.startTreadmill(speed: 3.0)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                    }

                    Text("Tip: Use the Dashboard tab for full speed controls")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                }

                Button("Disconnect") {
                    bleManager.disconnect()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            // Discovered devices
            if !bleManager.discoveredDevices.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discovered Devices")
                        .font(.headline)

                    ForEach(bleManager.discoveredDevices, id: \.peripheral.identifier) { device in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.body)
                                Text("\(device.brand) · Signal: \(device.rssi) dBm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Connect") {
                                bleManager.connect(to: device.peripheral)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()

            // Help text
            VStack(spacing: 8) {
                Text("Looking for your DeerRun treadmill?")
                    .font(.headline)
                Text("Make sure your treadmill is powered on and not connected to the PitPat app on your phone.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .padding()
        .navigationTitle("Connection")
    }

    private var statusColor: Color {
        switch state.connectionStatus {
        case .disconnected: return .gray
        case .scanning: return .orange
        case .connecting: return .yellow
        case .connected: return .green
        case .error: return .red
        }
    }
}

import Foundation
import CoreBluetooth

/// Central registry of all known treadmill adapters.
///
/// At app launch, each adapter type is registered here. The BLE manager
/// consults the registry to know which service UUIDs to scan for and
/// to match a discovered peripheral to its adapter.
///
/// Usage:
/// ```swift
/// // In your app startup (e.g. App.init or AppDelegate):
/// TreadmillAdapterRegistry.shared.register(PitPatAdapter.self)
/// TreadmillAdapterRegistry.shared.register(KingSmithAdapter.self)
/// // etc.
/// ```
final class TreadmillAdapterRegistry {

    static let shared = TreadmillAdapterRegistry()

    private var adapterTypes: [any TreadmillAdapter.Type] = []

    private init() {}

    // MARK: - Registration

    /// Register an adapter type. Call once per adapter at app launch.
    func register(_ type: any TreadmillAdapter.Type) {
        // Avoid duplicates
        guard !adapterTypes.contains(where: { $0 == type }) else { return }
        adapterTypes.append(type)
    }

    // MARK: - Queries

    /// All service UUIDs across every registered adapter (used as the scan filter).
    /// Returns `nil` if no adapters are registered — pass nil to CoreBluetooth
    /// to scan for all peripherals (useful during development/debugging).
    var allServiceUUIDs: [CBUUID]? {
        let uuids = adapterTypes.flatMap { $0.serviceUUIDs }
        return uuids.isEmpty ? nil : Array(Set(uuids))
    }

    /// Find the first adapter whose `matches(peripheral:advertisementData:)` returns true.
    /// Returns an instantiated adapter ready for use, or `nil` if no match.
    func findAdapter(for peripheral: CBPeripheral, advertisementData: [String: Any]) -> (any TreadmillAdapter)? {
        for adapterType in adapterTypes {
            if adapterType.matches(peripheral: peripheral, advertisementData: advertisementData) {
                // Instantiate the adapter (all adapters are value types with no required init params)
                return adapterType.init()
            }
        }
        return nil
    }

    /// The display names of all registered adapters, for UI/debug purposes.
    var registeredAdapterNames: [String] {
        adapterTypes.map { $0.displayName }
    }
}

// MARK: - Protocol requirement for parameterless init

/// Adapters must be constructible without arguments so the registry can instantiate them.
extension TreadmillAdapter where Self: Any {
    // Default init is already available for structs with all-default/no stored properties.
}

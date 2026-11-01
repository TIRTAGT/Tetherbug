import CoreBluetooth
import Foundation

/// `tetherbug scan [seconds]`: lists every Bluetooth LE device the Mac can see, unfiltered, and marks
/// the ones advertising the Tetherbug service. For diagnosing an agent that never finds the phone.
final class BLEScanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var seen = Set<UUID>()
    private let seconds: TimeInterval

    init(seconds: TimeInterval) { self.seconds = seconds }

    func run() -> Never {
        central = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in
            print("done: \(seen.count) device(s) seen in \(Int(seconds)) s")
            exit(0)
        }
        RunLoop.main.run()
        exit(0)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = ["unknown", "resetting", "unsupported", "unauthorized", "off", "on"][min(central.state.rawValue, 5)]
        print("bluetooth \(state)")
        guard central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Gatt.service]) {
            print("connected to the system with the Tetherbug service: \(peripheral.name ?? "unnamed") \(peripheral.identifier)")
        }
        print("scanning for \(Int(seconds)) s…")
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard seen.insert(peripheral.identifier).inserted else { return }
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            + (advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] ?? [])
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "unnamed"
        let connectable = (advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber)?.boolValue ?? false
        let mark = services.contains(Gatt.service) ? "  <-- Tetherbug" : ""
        print("\(name) \(peripheral.identifier) \(rssi) dBm connectable=\(connectable) services=\(services.map(\.uuidString))\(mark)")
    }
}

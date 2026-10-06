// 블루투스 모드에서 마우스에 직접 배터리 잔량을 물어본다 (표준 Battery Service 0x180F / Battery Level 0x2A19).
// 맥이 블루투스 메뉴에 보여주는 값과 같은 출처다. IORegistry에는 이 마우스의 배터리 값이 없다.

import Foundation
import CoreBluetooth

final class BLEBattery: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BLEBattery()
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let hidService = CBUUID(string: "1812")
    static let mouseName = "BT5.0 Mouse"

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    var onReading: ((Int?) -> Void)?
    private var lastFound: Bool?

    /// 블루투스 마우스가 연결됐을 때 부른다
    func start() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            attach()
        }
    }

    /// 블루투스 마우스가 끊겼을 때
    func stop() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        peripheral = nil
        characteristic = nil
        onReading?(nil)
    }

    /// 주기적으로 다시 읽기
    func refresh() {
        if let p = peripheral, let c = characteristic, p.state == .connected {
            p.readValue(for: c)
        } else if peripheral == nil {
            attach()
        }
    }

    private func attach() {
        guard let central, central.state == .poweredOn else { return }
        let found = central.retrieveConnectedPeripherals(withServices: [Self.batteryService, Self.hidService])
        // 이 마우스만. 다른 블루투스 기기에는 붙지 않고, 다른 기기 이름도 기록하지 않는다.
        let p = found.first(where: { $0.name == Self.mouseName })
        if lastFound != (p != nil) {   // 상태가 바뀔 때만 기록 (1분마다 쌓이지 않게)
            lastFound = p != nil
            log("BLE: \(Self.mouseName) \(p != nil ? "찾음" : "못 찾음")")
        }
        guard let p else { return }
        peripheral = p
        p.delegate = self
        central.connect(p)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("BLE 상태: \(central.state.rawValue) (5=켜짐, 3=권한 없음)")
        if central.state == .poweredOn { attach() }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("BLE 연결 실패: \(error?.localizedDescription ?? "?")")
        self.peripheral = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        self.peripheral = nil
        characteristic = nil
        onReading?(nil)
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else {
            log("BLE 배터리 서비스 없음: \(peripheral.services?.map(\.uuid.uuidString) ?? [])")
            return
        }
        peripheral.discoverCharacteristics([Self.batteryLevel], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let c = service.characteristics?.first(where: { $0.uuid == Self.batteryLevel }) else { return }
        characteristic = c
        peripheral.readValue(for: c)
        if c.properties.contains(.notify) { peripheral.setNotifyValue(true, for: c) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let v = characteristic.value?.first else { return }
        log("BLE 배터리: \(v)%")
        onReading?(Int(v))
    }
}

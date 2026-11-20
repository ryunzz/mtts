import Foundation
import Testing
@testable import mtts

struct BluetoothInventoryTests {
    /// Shape of `system_profiler SPBluetoothDataType -json` on macOS 26.
    private let fixture = Data(#"""
    {
      "SPBluetoothDataType": [{
        "controller_properties": {"controller_address": "00:00:00:00:00:01"},
        "device_connected": [
          {"Ryan’s Powerbeats Pro": {
            "device_address": "AC:BC:32:11:22:33",
            "device_batteryLevelCase": "40%",
            "device_batteryLevelLeft": "85%",
            "device_batteryLevelRight": "90%",
            "device_firmwareVersion": "8A359",
            "device_minorType": "Headphones",
            "device_productID": "0x201D",
            "device_vendorID": "0x004C"
          }},
          {"Magic Mouse": {
            "device_address": "D0:C0:50:CF:94:1A",
            "device_minorType": "Mouse",
            "device_productID": "0x0323",
            "device_vendorID": "0x004C"
          }}
        ],
        "device_not_connected": [
          {"Old Headset": {"device_address": "11:22:33:44:55:66", "device_minorType": "Headset"}}
        ]
      }]
    }
    """#.utf8)

    @Test func parsesConnectedAndPairedDevices() throws {
        let devices = try BluetoothInventory.parse(fixture)
        #expect(devices.count == 3)
        let beats = try #require(devices.first { $0.name == "Ryan’s Powerbeats Pro" })
        #expect(beats.productID == 0x201D)
        #expect(beats.vendorID == 0x004C)
        #expect(beats.firmware == "8A359")
        #expect(beats.isConnected)
        #expect(beats.isAudio)
        #expect(devices.first { $0.name == "Old Headset" }?.isConnected == false)
    }

    @Test func parsesBatteryLevels() throws {
        let devices = try BluetoothInventory.parse(fixture)
        let beats = try #require(devices.first { $0.name == "Ryan’s Powerbeats Pro" })
        #expect(beats.battery == BluetoothDeviceInfo.Battery(left: 85, right: 90, caseLevel: 40, main: nil))
        #expect(devices.first { $0.name == "Magic Mouse" }?.battery == nil)
    }

    @Test(arguments: [("85%", 85), ("100 %", 100), ("0%", 0), ("101%", nil), ("abc", nil), ("", nil)] as [(String, Int?)])
    func parsesPercentStrings(input: String, expected: Int?) {
        #expect(BluetoothInventory.percent(input) == expected)
    }

    @Test func rejectsUnexpectedJSON() {
        #expect(throws: BluetoothInventory.LoadError.self) {
            try BluetoothInventory.parse(Data(#"{"foo": 1}"#.utf8))
        }
    }

    @Test func matchesOutputByAddressInUID() throws {
        let devices = try BluetoothInventory.parse(fixture)
        let match = BluetoothInventory.match(outputName: "Renamed", outputUID: "AC-BC-32-11-22-33:output", in: devices)
        #expect(match?.productID == 0x201D)
    }

    @Test func matchesOutputByName() throws {
        let devices = try BluetoothInventory.parse(fixture)
        let match = BluetoothInventory.match(outputName: "ryan’s powerbeats pro", outputUID: nil, in: devices)
        #expect(match?.productID == 0x201D)
    }

    @Test func fallsBackToTheOnlyConnectedAudioDevice() throws {
        let devices = try BluetoothInventory.parse(fixture)
        let match = BluetoothInventory.match(outputName: "Unknown", outputUID: "no-address-here", in: devices)
        #expect(match?.name == "Ryan’s Powerbeats Pro")
    }

    @Test func ignoresDisconnectedDevices() throws {
        let devices = try BluetoothInventory.parse(fixture).filter { $0.name != "Ryan’s Powerbeats Pro" }
        #expect(BluetoothInventory.match(outputName: "Old Headset", outputUID: nil, in: devices) == nil)
    }

    @Test(arguments: [("0x201D", UInt16(0x201D)), ("201d", 0x201D), (" 0x004C ", 0x004C)])
    func parsesHexIDs(input: String, expected: UInt16) {
        #expect(BluetoothInventory.hex(input) == expected)
    }

    @Test func invalidHexIsNil() {
        #expect(BluetoothInventory.hex(nil) == nil)
        #expect(BluetoothInventory.hex("") == nil)
        #expect(BluetoothInventory.hex("0xZZZZ") == nil)
    }
}

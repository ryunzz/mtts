import Foundation
import Testing
@testable import mtts

struct IntegrationTests {
    /// Runs the real `system_profiler` lookup the app uses. Every Mac has it; the list may be empty.
    @Test(.timeLimit(.minutes(1)))
    func bluetoothInventoryLoadsOnThisMac() async throws {
        let devices = try await BluetoothInventory.load()
        #expect(devices.allSatisfy { !$0.name.isEmpty })
    }

    @Test func cancelledLookupStopsCleanly() async {
        let task = Task { try await BluetoothInventory.load() }
        task.cancel()
        let result = await task.result
        if case .failure(let error) = result {
            #expect(error is CancellationError)
        }
    }

    @Test func motionCSVRowMatchesHeader() {
        let sample = MotionSample(t: 10.5, accel: (0.1, 0.2, 0.3), rotation: (1, 2, 3), attitude: (0.4, 0.5, 0.6))
        let fields = sample.csvRow(relativeTo: 10).split(separator: ",")
        #expect(fields.count == MotionSample.csvHeader.split(separator: ",").count)
        #expect(fields.first == "0.500000")
        #expect(fields[1] == "0.100000")
    }

    @Test(arguments: HeadphoneModel.catalog)
    func everyModelHasLabels(model: HeadphoneModel) {
        #expect(!model.fitTip.isEmpty)
        #expect(!model.headTrackingLabel.isEmpty)
        #expect(!model.symbol.isEmpty)
    }

    @Test func unrecognizedModelHasGenericLabels() {
        let model = HeadphoneModel.unrecognized(name: "Desk Speaker")
        #expect(model.headTrackingLabel == "Head tracking unknown")
        #expect(model.fitTip.contains("same way"))
        #expect(HeadphoneModel.model(id: "powerbeats-pro-2") == .powerbeatsPro2)
        #expect(HeadphoneModel.model(id: "nope") == nil)
    }
}

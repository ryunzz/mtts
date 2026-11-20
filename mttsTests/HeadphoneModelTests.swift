import Testing
@testable import mtts

struct HeadphoneModelTests {
    @Test func powerbeatsPro2IsIdentifiedByProductID() throws {
        // macOS names both generations "Powerbeats Pro"; only the product ID tells them apart.
        let model = try #require(HeadphoneModel.identify(productID: 0x201D, vendorID: 0x004C, name: "Ryan’s Powerbeats Pro"))
        #expect(model == .powerbeatsPro2)
        #expect(model.headTracking == .supported)
        #expect(model.fit == .earHook)
    }

    @Test func originalPowerbeatsProHasNoHeadTracking() throws {
        let model = try #require(HeadphoneModel.identify(productID: 0x200B, vendorID: 0x004C, name: "Ryan’s Powerbeats Pro"))
        #expect(model == .powerbeatsPro)
        #expect(model.headTracking == .unsupported)
    }

    @Test func unknownProductFallsBackToName() throws {
        let model = try #require(HeadphoneModel.identify(productID: 0x2FFF, vendorID: 0x004C, name: "Studio Monitors"))
        #expect(model.id == "other:studio monitors")
        #expect(model.headTracking == .unknown)
        #expect(model.fit == nil)
    }

    @Test func nameAloneNeverClaimsAModel() throws {
        let model = try #require(HeadphoneModel.identify(productID: nil, vendorID: nil, name: "Powerbeats Pro"))
        #expect(model.headTracking == .unknown)
    }

    @Test func nonAppleVendorIsNotMatchedByProductID() throws {
        let model = try #require(HeadphoneModel.identify(productID: 0x201D, vendorID: 0x0A12, name: "Other Buds"))
        #expect(model.id == "other:other buds")
    }

    @Test func nothingToIdentifyReturnsNil() {
        #expect(HeadphoneModel.identify(productID: nil, vendorID: nil, name: nil) == nil)
        #expect(HeadphoneModel.identify(productID: nil, vendorID: nil, name: "  ") == nil)
    }

    @Test func catalogIDsAndProductIDsAreUnique() {
        let ids = HeadphoneModel.catalog.map(\.id)
        #expect(Set(ids).count == ids.count)
        let pids = HeadphoneModel.catalog.flatMap(\.productIDs)
        #expect(Set(pids).count == pids.count)
    }

    @Test(arguments: [
        (UInt16(0x2027), "airpods-pro-3"), (0x2024, "airpods-pro-2"), (0x201B, "airpods-4"),
        (0x202D, "airpods-max-2"), (0x2012, "beats-fit-pro"), (0x2017, "beats-studio-pro"),
    ])
    func identifiesOtherHeadTrackingModels(productID: UInt16, expectedID: String) throws {
        let model = try #require(HeadphoneModel.identify(productID: productID, vendorID: 0x004C, name: "x"))
        #expect(model.id == expectedID)
        #expect(model.hasHeadTracking)
    }

    @Test func treatAsMenuOnlyOffersHeadTrackingModels() {
        let models = HeadphoneModel.headTrackingModels
        let ids = Set(models.map(\.id))
        let allTrack = models.allSatisfy { $0.hasHeadTracking }
        #expect(allTrack)
        #expect(ids.contains("powerbeats-pro-2"))
        #expect(!ids.contains("powerbeats-pro"))
    }
}

struct HeadphoneIdentificationTests {
    private let output = AudioDevices.OutputDevice(
        id: 42, name: "Ryan’s Powerbeats Pro", uid: "AC-BC-32-11-22-33:output", isBluetooth: true)
    private let powerbeats = BluetoothDeviceInfo(
        name: "Ryan’s Powerbeats Pro", address: "AC:BC:32:11:22:33", productID: 0x201D, vendorID: 0x004C,
        firmware: "8A359", minorType: "Headphones", isConnected: true)

    @Test func confirmedWhenTheBluetoothLookupFindsTheDevice() throws {
        let result = try #require(HeadphoneIdentification.identify(output: output, inventory: [powerbeats]))
        #expect(result.model == .powerbeatsPro2)
        #expect(result.isConfirmed)
        #expect(result.bluetooth?.firmware == "8A359")
    }

    @Test func unconfirmedGuessWhenTheLookupFailed() throws {
        // A failed lookup must not produce a key that would hide the user's takes.
        let result = try #require(HeadphoneIdentification.identify(output: output, inventory: nil))
        #expect(!result.isConfirmed)
        #expect(result.model.headTracking == .unknown)
    }

    @Test func unconfirmedWhenTheDeviceIsNotListedYet() throws {
        let result = try #require(HeadphoneIdentification.identify(output: output, inventory: []))
        #expect(!result.isConfirmed)
    }

    @Test func nonBluetoothOutputsAreNotHeadphones() {
        let speakers = AudioDevices.OutputDevice(id: 1, name: "Mac mini Speakers", uid: "BuiltIn", isBluetooth: false)
        #expect(HeadphoneIdentification.identify(output: speakers, inventory: [powerbeats]) == nil)
    }
}

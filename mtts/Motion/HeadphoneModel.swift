import Foundation

/// What mtts knows about a headphone model: whether it has the head-tracking motion
/// sensor that `CMHeadphoneMotionManager` reads, and how it sits on the head (which changes
/// how jaw movement reaches the sensor).
///
/// Models are identified by Bluetooth product ID, not by name: iOS and macOS call both the
/// 2019 Powerbeats Pro and the 2025 Powerbeats Pro 2 "Powerbeats Pro", and only the second
/// one has head tracking.
struct HeadphoneModel: Hashable, Sendable, Identifiable {
    enum Family: String, Sendable, CaseIterable {
        case beats = "Beats"
        case airPods = "AirPods"
        case other = "Other"
    }

    enum Fit: String, Sendable {
        case earHook = "Ear hook"
        case wingtip = "Wingtip"
        case inEar = "In-ear"
        case onEar = "On-ear"
        case overEar = "Over-ear"
    }

    enum HeadTracking: Sendable {
        case supported
        case unsupported
        case unknown
    }

    /// Stable key stored with each training take, so takes from different headphones never mix.
    let id: String
    let name: String
    let family: Family
    let productIDs: Set<UInt16>
    let fit: Fit?
    let headTracking: HeadTracking
    let symbol: String

    static let appleVendorID: UInt16 = 0x004C

    /// A headphone that isn't in the catalog. Head tracking is unknown until motion streams.
    static func unrecognized(name: String) -> HeadphoneModel {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return HeadphoneModel(
            id: "other:\(key)", name: name, family: .other, productIDs: [], fit: nil,
            headTracking: .unknown, symbol: "headphones")
    }

    /// Looks up a model by Bluetooth product ID; falls back to an unrecognized entry named
    /// after the device. Returns nil when there is nothing to identify.
    static func identify(productID: UInt16?, vendorID: UInt16?, name: String?) -> HeadphoneModel? {
        let isApple = vendorID.map { $0 == appleVendorID } ?? true
        if isApple, let productID, let model = catalog.first(where: { $0.productIDs.contains(productID) }) {
            return model
        }
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return unrecognized(name: name)
    }

    static func model(id: String) -> HeadphoneModel? {
        catalog.first { $0.id == id }
    }

    var hasHeadTracking: Bool { headTracking == .supported }

    var headTrackingLabel: String {
        switch headTracking {
        case .supported: "Head tracking"
        case .unsupported: "No head tracking"
        case .unknown: "Head tracking unknown"
        }
    }

    var fitTip: String {
        switch fit {
        case .earHook:
            "Seat the ear tip, then settle the ear hook the same way each session. Re-seating shifts the signal, so train with the fit you'll demo with."
        case .wingtip, .inEar:
            "Push the ear tips in snugly and keep the same fit between training and decoding."
        case .onEar, .overEar:
            "Ear cups pick up less jaw movement than earbuds. Keep the headband position fixed while you train."
        case nil:
            "Keep the headphones seated the same way between training and decoding."
        }
    }
}

extension HeadphoneModel {
    // Apple Bluetooth product IDs (vendor 0x004C). Powerbeats Pro 2 = 0x201D per AppleDB
    // ("Device1,8221", models A3157 / A3158 / A3160); the rest agree across community tables.
    // A wrong or missing entry only changes labels — motion streams or not regardless.

    static let powerbeatsPro2 = HeadphoneModel(
        id: "powerbeats-pro-2", name: "Powerbeats Pro 2", family: .beats, productIDs: [0x201D],
        fit: .earHook, headTracking: .supported, symbol: "beats.powerbeatspro")
    static let powerbeatsFit = HeadphoneModel(
        id: "powerbeats-fit", name: "Powerbeats Fit", family: .beats, productIDs: [0x202F],
        fit: .wingtip, headTracking: .supported, symbol: "beats.fitpro")
    static let beatsFitPro = HeadphoneModel(
        id: "beats-fit-pro", name: "Beats Fit Pro", family: .beats, productIDs: [0x2012],
        fit: .wingtip, headTracking: .supported, symbol: "beats.fitpro")
    static let beatsStudioPro = HeadphoneModel(
        id: "beats-studio-pro", name: "Beats Studio Pro", family: .beats, productIDs: [0x2017],
        fit: .overEar, headTracking: .supported, symbol: "beats.headphones")
    static let beatsSolo4 = HeadphoneModel(
        id: "beats-solo-4", name: "Beats Solo 4", family: .beats, productIDs: [0x2025],
        fit: .onEar, headTracking: .supported, symbol: "beats.headphones")
    static let powerbeatsPro = HeadphoneModel(
        id: "powerbeats-pro", name: "Powerbeats Pro (2019)", family: .beats, productIDs: [0x200B],
        fit: .earHook, headTracking: .unsupported, symbol: "beats.powerbeatspro")
    static let beatsStudioBuds = HeadphoneModel(
        id: "beats-studio-buds", name: "Beats Studio Buds", family: .beats, productIDs: [0x2011, 0x2016],
        fit: .inEar, headTracking: .unsupported, symbol: "beats.studiobuds")
    static let beatsSoloBuds = HeadphoneModel(
        id: "beats-solo-buds", name: "Beats Solo Buds", family: .beats, productIDs: [0x2026],
        fit: .inEar, headTracking: .unsupported, symbol: "beats.studiobuds")
    static let beatsOlder = HeadphoneModel(
        id: "beats-older", name: "Beats (no head tracking)", family: .beats,
        productIDs: [0x2003, 0x2005, 0x2006, 0x2009, 0x200C, 0x200D, 0x2010],
        fit: nil, headTracking: .unsupported, symbol: "beats.headphones")

    static let airPodsPro3 = HeadphoneModel(
        id: "airpods-pro-3", name: "AirPods Pro 3", family: .airPods, productIDs: [0x2027],
        fit: .inEar, headTracking: .supported, symbol: "airpodspro")
    static let airPodsPro2 = HeadphoneModel(
        id: "airpods-pro-2", name: "AirPods Pro 2", family: .airPods, productIDs: [0x2014, 0x2024],
        fit: .inEar, headTracking: .supported, symbol: "airpodspro")
    static let airPodsPro = HeadphoneModel(
        id: "airpods-pro", name: "AirPods Pro", family: .airPods, productIDs: [0x200E],
        fit: .inEar, headTracking: .supported, symbol: "airpodspro")
    static let airPods4 = HeadphoneModel(
        id: "airpods-4", name: "AirPods 4", family: .airPods,
        productIDs: [0x2019, 0x201B, 0x201C, 0x201E, 0x2020],
        fit: .inEar, headTracking: .supported, symbol: "airpods.gen3")
    static let airPods3 = HeadphoneModel(
        id: "airpods-3", name: "AirPods (3rd generation)", family: .airPods, productIDs: [0x2013],
        fit: .inEar, headTracking: .supported, symbol: "airpods.gen3")
    static let airPodsMax2 = HeadphoneModel(
        id: "airpods-max-2", name: "AirPods Max 2", family: .airPods, productIDs: [0x202D],
        fit: .overEar, headTracking: .supported, symbol: "airpodsmax")
    static let airPodsMax = HeadphoneModel(
        id: "airpods-max", name: "AirPods Max", family: .airPods, productIDs: [0x200A, 0x201F],
        fit: .overEar, headTracking: .supported, symbol: "airpodsmax")
    static let airPodsOlder = HeadphoneModel(
        id: "airpods-older", name: "AirPods (1st or 2nd generation)", family: .airPods,
        productIDs: [0x2002, 0x200F],
        fit: .inEar, headTracking: .unsupported, symbol: "airpods")

    static let catalog: [HeadphoneModel] = [
        .powerbeatsPro2, .powerbeatsFit, .beatsFitPro, .beatsStudioPro, .beatsSolo4,
        .powerbeatsPro, .beatsStudioBuds, .beatsSoloBuds, .beatsOlder,
        .airPodsPro3, .airPodsPro2, .airPodsPro, .airPods4, .airPods3, .airPodsMax2, .airPodsMax,
        .airPodsOlder,
    ]

    /// Models with head tracking, for the manual "Treat as" picker.
    static let headTrackingModels: [HeadphoneModel] = catalog.filter(\.hasHeadTracking)
}

/// The model behind one audio output, plus how much to trust it.
struct HeadphoneIdentification: Hashable, Sendable {
    let model: HeadphoneModel
    let bluetooth: BluetoothDeviceInfo?
    /// The Bluetooth lookup found this exact device, so the model (a catalog hit or a named
    /// unknown device) is safe to key training takes on. False means a name-only guess made
    /// while the lookup failed or the device wasn't listed yet.
    let isConfirmed: Bool

    /// `inventory` is nil when the Bluetooth lookup failed.
    static func identify(output: AudioDevices.OutputDevice, inventory: [BluetoothDeviceInfo]?) -> HeadphoneIdentification? {
        guard output.isBluetooth else { return nil }
        guard let inventory,
              let info = BluetoothInventory.match(outputName: output.name, outputUID: output.uid, in: inventory),
              let model = HeadphoneModel.identify(productID: info.productID, vendorID: info.vendorID, name: info.name)
        else {
            return HeadphoneIdentification(model: .unrecognized(name: output.name), bluetooth: nil, isConfirmed: false)
        }
        return HeadphoneIdentification(model: model, bluetooth: info, isConfirmed: true)
    }
}

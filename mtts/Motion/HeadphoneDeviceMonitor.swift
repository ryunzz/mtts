import CoreAudio
import Foundation
import Observation
import os

/// Tracks the Mac's audio outputs, identifies the headphone model behind each, and lets the
/// user switch outputs or override a model the app can't recognize.
///
/// `CMHeadphoneMotionManager` never says which headphones it streams from; it follows the
/// active audio route — the default output. Choosing headphones here therefore means making
/// them the Mac's sound output.
@MainActor @Observable
final class HeadphoneDeviceMonitor {
    struct Output: Identifiable, Hashable, Sendable {
        let device: AudioDevices.OutputDevice
        let identification: HeadphoneIdentification?
        var id: AudioDeviceID { device.id }
    }

    private(set) var outputs: [Output] = []
    private(set) var currentOutputID: AudioDeviceID?
    /// Paired Bluetooth headphones that aren't connected right now.
    private(set) var pairedHeadphones: [BluetoothDeviceInfo] = []
    private(set) var lookupError: String?
    private(set) var isRefreshing = false
    private var overrides: [String: String]

    var onModelChange: (() -> Void)?

    @ObservationIgnored private var started = false
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var cachedInventory: (key: [String], devices: [BluetoothDeviceInfo])?
    @ObservationIgnored private var forceReload = false
    @ObservationIgnored private var lastNotified: (model: HeadphoneModel?, confirmed: Bool)?
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "device")

    static let overridesKey = "headphoneModelOverrides"
    private static let debounce: Duration = .milliseconds(300)
    private static let retryDelay: Duration = .seconds(1.5)

    init() {
        overrides = UserDefaults.standard.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:]
    }

    // MARK: Current headphones

    var current: Output? {
        outputs.first { $0.id == currentOutputID }
    }

    var output: AudioDevices.OutputDevice? { current?.device }

    var bluetooth: BluetoothDeviceInfo? { current?.identification?.bluetooth }

    /// The detected model, unless the user picked one by hand for this output.
    var model: HeadphoneModel? {
        override ?? current?.identification?.model
    }

    /// Whether `model` is trustworthy enough to key training takes on.
    var isModelConfirmed: Bool {
        override != nil || current?.identification?.isConfirmed == true
    }

    var detectedModel: HeadphoneModel? { current?.identification?.model }

    var override: HeadphoneModel? {
        guard let key = current.map(Self.overrideKey) else { return nil }
        return overrides[key].flatMap(HeadphoneModel.model(id:))
    }

    // MARK: Actions

    func start() {
        guard !started else { return }
        started = true
        let refresh: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        AudioDevices.observeSystem(kAudioHardwarePropertyDefaultOutputDevice, refresh)
        AudioDevices.observeSystem(kAudioHardwarePropertyDevices, refresh)
        refresh()
    }

    /// Coalesces bursts of Core Audio notifications into one lookup.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.debounce)
                try await self?.performRefresh(retryIfUnconfirmed: true)
            } catch {
                // Cancelled by a newer refresh.
            }
        }
    }

    /// Re-reads the Bluetooth list (battery levels change; the cached list doesn't).
    func reloadBluetooth() {
        guard output?.isBluetooth == true, !isRefreshing else { return }
        forceReload = true
        refresh()
    }

    /// Makes the output the Mac's sound output so head motion streams from it.
    func select(_ output: Output) {
        guard output.id != currentOutputID else { return }
        if !AudioDevices.setDefaultOutput(output.id) {
            log.error("Couldn't switch output to \(output.device.name, privacy: .public)")
        }
        refresh()
    }

    /// Treat the current output as `model` (nil returns to automatic detection).
    func setOverride(_ model: HeadphoneModel?) {
        guard let current else { return }
        let key = Self.overrideKey(current)
        overrides[key] = model?.id
        UserDefaults.standard.set(overrides, forKey: Self.overridesKey)
        notifyIfChanged()
    }

    // MARK: Lookup

    private func performRefresh(retryIfUnconfirmed: Bool) async throws {
        let devices = AudioDevices.outputDevices()
        let currentID = AudioDevices.defaultOutput()?.id
        let inventory = try await inventory(for: devices)
        try Task.checkCancellation()

        outputs = devices.map { device in
            Output(device: device, identification: HeadphoneIdentification.identify(output: device, inventory: inventory))
        }
        currentOutputID = currentID
        if let inventory {
            pairedHeadphones = inventory.filter { !$0.isConnected && $0.isAudio }
        }
        notifyIfChanged()

        // Core Audio often lists new headphones a moment before Bluetooth does.
        if retryIfUnconfirmed, let current, current.device.isBluetooth, current.identification?.isConfirmed != true {
            cachedInventory = nil
            try await Task.sleep(for: Self.retryDelay)
            try await performRefresh(retryIfUnconfirmed: false)
        }
    }

    /// The Bluetooth device list, reused while the set of Bluetooth outputs is unchanged.
    /// Returns nil when the lookup failed.
    private func inventory(for devices: [AudioDevices.OutputDevice]) async throws -> [BluetoothDeviceInfo]? {
        let key = devices.filter(\.isBluetooth).map { $0.uid ?? $0.name }.sorted()
        guard !key.isEmpty else {
            lookupError = nil
            return []
        }
        let previous = cachedInventory?.key == key ? cachedInventory?.devices : nil
        if !forceReload, let previous { return previous }
        forceReload = false

        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let devices = try await BluetoothInventory.load()
            cachedInventory = (key, devices)
            lookupError = nil
            return devices
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            log.error("Bluetooth lookup failed: \(error.localizedDescription, privacy: .public)")
            // A failed periodic reload keeps the last good list rather than forgetting the model.
            if let previous { return previous }
            lookupError = error.localizedDescription
            return nil
        }
    }

    private func notifyIfChanged() {
        let state = (model: model, confirmed: isModelConfirmed)
        if let lastNotified, lastNotified.model == state.model, lastNotified.confirmed == state.confirmed { return }
        lastNotified = state
        onModelChange?()
    }

    private static func overrideKey(_ output: Output) -> String {
        output.device.uid ?? output.device.name
    }
}

import Foundation

/// One paired Bluetooth device as reported by `system_profiler SPBluetoothDataType -json`.
struct BluetoothDeviceInfo: Hashable, Sendable {
    var name: String
    var address: String?
    var productID: UInt16?
    var vendorID: UInt16?
    var firmware: String?
    var minorType: String?
    var isConnected: Bool
    var battery: Battery?

    /// Charge levels (percent) as macOS reports them for Apple and Beats headphones.
    struct Battery: Hashable, Sendable {
        var left: Int?
        var right: Int?
        var caseLevel: Int?
        /// Single-battery headphones report one level.
        var main: Int?

        var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && main == nil }
    }

    var isAudio: Bool {
        guard let minorType else { return false }
        return ["headphones", "headset", "loudspeaker"].contains(minorType.lowercased())
    }
}

/// Reads the Bluetooth product ID of the connected headphones. Core Audio only exposes the
/// (user-editable) device name, which can't tell Powerbeats Pro 2 from the 2019 model.
enum BluetoothInventory {
    enum LoadError: LocalizedError {
        case exitStatus(Int32)
        case timedOut
        case unexpectedFormat

        var errorDescription: String? {
            switch self {
            case .exitStatus(let code): "system_profiler exited with status \(code)."
            case .timedOut: "system_profiler took too long to answer."
            case .unexpectedFormat: "Couldn't read the Bluetooth device list."
            }
        }
    }

    /// Runs `system_profiler` off the main thread. Cancelling the calling task, or hitting the
    /// timeout, terminates the child process.
    static func load(timeout: TimeInterval = 10) async throws -> [BluetoothDeviceInfo] {
        let run = ProfilerRun()
        return try await withTaskCancellationHandler {
            try await run.start(timeout: timeout)
        } onCancel: {
            run.cancel()
        }
    }

    static func parse(_ data: Data) throws -> [BluetoothDeviceInfo] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else {
            throw LoadError.unexpectedFormat
        }
        let groups = [("device_connected", true), ("device_not_connected", false)]
        return controllers.flatMap { controller in
            groups.flatMap { key, connected -> [BluetoothDeviceInfo] in
                let entries = controller[key] as? [[String: Any]] ?? []
                return entries.flatMap { entry in
                    entry.compactMap { name, value -> BluetoothDeviceInfo? in
                        guard let fields = value as? [String: Any] else { return nil }
                        return BluetoothDeviceInfo(
                            name: name,
                            address: fields["device_address"] as? String,
                            productID: hex(fields["device_productID"] as? String),
                            vendorID: hex(fields["device_vendorID"] as? String),
                            firmware: fields["device_firmwareVersion"] as? String,
                            minorType: fields["device_minorType"] as? String,
                            isConnected: connected,
                            battery: battery(fields))
                    }
                }
            }
        }
    }

    /// Finds the Bluetooth device behind a Core Audio output. Bluetooth audio device UIDs
    /// embed the MAC address (e.g. `AA-BB-CC-DD-EE-FF:output`), which is the most reliable key.
    static func match(outputName: String, outputUID: String?, in devices: [BluetoothDeviceInfo]) -> BluetoothDeviceInfo? {
        let connected = devices.filter(\.isConnected)
        if let uid = outputUID.map(normalizedAddress),
           let byAddress = connected.first(where: { device in
               guard let address = device.address.map(normalizedAddress), !address.isEmpty else { return false }
               return uid.contains(address)
           }) {
            return byAddress
        }
        if let byName = connected.first(where: { $0.name == outputName })
            ?? connected.first(where: { $0.name.caseInsensitiveCompare(outputName) == .orderedSame }) {
            return byName
        }
        let audio = connected.filter(\.isAudio)
        return audio.count == 1 ? audio[0] : nil
    }

    static func battery(_ fields: [String: Any]) -> BluetoothDeviceInfo.Battery? {
        let level = { (key: String) in percent(fields["device_batteryLevel\(key)"] as? String) }
        let battery = BluetoothDeviceInfo.Battery(
            left: level("Left"), right: level("Right"), caseLevel: level("Case"), main: level("Main"))
        return battery.isEmpty ? nil : battery
    }

    /// "85%" → 85.
    static func percent(_ string: String?) -> Int? {
        guard let digits = string?.trimmingCharacters(in: CharacterSet(charactersIn: "% ")),
              let value = Int(digits), (0...100).contains(value) else { return nil }
        return value
    }

    static func hex(_ string: String?) -> UInt16? {
        guard var digits = string?.trimmingCharacters(in: .whitespaces).lowercased(), !digits.isEmpty else { return nil }
        if digits.hasPrefix("0x") { digits.removeFirst(2) }
        return UInt16(digits, radix: 16)
    }

    static func normalizedAddress(_ string: String) -> String {
        string.uppercased().replacingOccurrences(of: "-", with: ":")
    }
}

/// One `system_profiler` invocation that can be cancelled or timed out from any thread.
private final class ProfilerRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func start(timeout: TimeInterval) async throws -> [BluetoothDeviceInfo] {
        try await Task.detached(priority: .utility) { [self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            let proceed = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                self.process = process
                return true
            }
            guard proceed else { throw CancellationError() }
            try process.run()

            let timer = DispatchWorkItem { [self] in expire() }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
            // Drain before waiting so a full pipe can't block the child.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timer.cancel()

            let (wasCancelled, didTimeOut) = lock.withLock { (cancelled, timedOut) }
            if wasCancelled { throw CancellationError() }
            if didTimeOut { throw BluetoothInventory.LoadError.timedOut }
            guard process.terminationStatus == 0 else {
                throw BluetoothInventory.LoadError.exitStatus(process.terminationStatus)
            }
            return try BluetoothInventory.parse(data)
        }.value
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            terminateLocked()
        }
    }

    private func expire() {
        lock.withLock {
            timedOut = true
            terminateLocked()
        }
    }

    private func terminateLocked() {
        if let process, process.isRunning { process.terminate() }
    }
}

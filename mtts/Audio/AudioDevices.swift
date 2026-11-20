import CoreAudio

/// Minimal Core Audio queries: the capture device picker (Powerbeats vs. built-in mic) and the
/// current output device, which is the headphone `CMHeadphoneMotionManager` streams from.
enum AudioDevices {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
    }

    struct OutputDevice: Identifiable, Hashable, Sendable {
        let id: AudioDeviceID
        let name: String
        let uid: String?
        let isBluetooth: Bool
    }

    static func inputDevices() -> [Device] {
        allDeviceIDs().compactMap { id in
            guard channelCount(id, scope: kAudioDevicePropertyScopeInput) > 0 else { return nil }
            return Device(id: id, name: name(of: id) ?? "Device \(id)")
        }
    }

    /// Every device that can play audio, Bluetooth headphones first.
    static func outputDevices() -> [OutputDevice] {
        allDeviceIDs()
            .filter { channelCount($0, scope: kAudioDevicePropertyScopeOutput) > 0 }
            .map(outputDevice)
            .sorted { lhs, rhs in
                lhs.isBluetooth != rhs.isBluetooth ? lhs.isBluetooth : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    static func defaultInputID() -> AudioDeviceID? {
        systemDevice(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func defaultOutput() -> OutputDevice? {
        systemDevice(kAudioHardwarePropertyDefaultOutputDevice).map(outputDevice)
    }

    /// Makes `id` the Mac's sound output — the same as picking it in Control Center. Head
    /// motion follows the output, so this is how the app switches between headphones.
    @discardableResult
    static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value = id
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        return status == noErr
    }

    private static func outputDevice(_ id: AudioDeviceID) -> OutputDevice {
        let transport = uint32Property(id, kAudioDevicePropertyTransportType)
        return OutputDevice(
            id: id,
            name: name(of: id) ?? "Device \(id)",
            uid: stringProperty(id, kAudioDevicePropertyDeviceUID),
            isBluetooth: transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE)
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func name(of id: AudioDeviceID) -> String? {
        stringProperty(id, kAudioObjectPropertyName)
    }

    /// Calls `handler` on the main queue whenever a system-wide audio property changes
    /// (default output switched, headphones connected or disconnected).
    @discardableResult
    static func observeSystem(_ selector: AudioObjectPropertySelector, _ handler: @escaping @Sendable () -> Void) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { _, _ in handler() }
        return status == noErr
    }

    private static func systemDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        guard let id = uint32Property(AudioObjectID(kAudioObjectSystemObject), selector), id != 0 else { return nil }
        return id
    }

    private static func uint32Property(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

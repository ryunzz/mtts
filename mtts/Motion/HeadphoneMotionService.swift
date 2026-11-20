import CoreMotion
import Observation
import os

/// Streams `CMHeadphoneMotionManager` updates from the connected head-tracking headphones
/// (Powerbeats Pro 2, Beats Fit Pro, AirPods Pro, …). The manager follows the active audio route.
@MainActor @Observable
final class HeadphoneMotionService {
    enum Status: Equatable {
        case unsupported
        case denied
        case waiting
        case streaming
        case error(String)

        var label: String {
            switch self {
            case .unsupported: "Headphone motion unsupported"
            case .denied: "Motion access denied"
            case .waiting: "Waiting for headphones"
            case .streaming: "Streaming"
            case .error(let message): message
            }
        }
    }

    static let historySeconds: TimeInterval = 10
    /// No sample for this long means the stream has stalled, even without a disconnect.
    static let stallTimeout: TimeInterval = 1

    private(set) var status: Status = .waiting
    private(set) var isConnected = false
    private(set) var latest: MotionSample?
    private(set) var history: [MotionSample] = []
    private(set) var sampleCount = 0
    private(set) var stats = StreamStats()
    /// When the current stream's first sample arrived.
    private(set) var streamStartedAt: Date?
    /// The yaw that counts as "facing forward". Set by the first sample of each stream and by
    /// `recenter()`.
    private(set) var yawReference: Double?
    /// Changes whenever a new stream starts (reconnect, stall, or clock restart).
    private(set) var streamID = 0

    var sampleRate: Double { stats.rate }

    var onSample: ((MotionSample) -> Void)?
    var onConnectionChange: ((Bool) -> Void)?

    @ObservationIgnored private let manager = CMHeadphoneMotionManager()
    @ObservationIgnored private let proxy = DelegateProxy()
    @ObservationIgnored private let log = Logger(subsystem: AppInfo.subsystem, category: "motion")
    @ObservationIgnored private var lastArrival: TimeInterval?
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    func start() {
        guard manager.isDeviceMotionAvailable else {
            status = .unsupported
            return
        }
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .denied, .restricted:
            status = .denied
            return
        default:
            break
        }

        proxy.onChange = { [weak self] connected in
            Task { @MainActor in self?.connectionChanged(connected) }
        }
        manager.delegate = proxy
        manager.startConnectionStatusUpdates()
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            MainActor.assumeIsolated {
                self?.handle(motion, error)
            }
        }
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(500))
                } catch {
                    return
                }
                self?.checkStall(at: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        manager.stopConnectionStatusUpdates()
        watchdog?.cancel()
        endStream(keepHeading: false)
        latest = nil
        status = .waiting
    }

    /// Makes the current head direction the forward reference.
    func recenter() {
        guard status == .streaming, let latest else { return }
        yawReference = latest.yaw
    }

    /// Marks the stream as waiting when samples stop arriving without a disconnect.
    func checkStall(at uptime: TimeInterval) {
        guard status == .streaming, let lastArrival, uptime - lastArrival > Self.stallTimeout else { return }
        log.info("Motion stream stalled")
        status = .waiting
    }

    /// Adds one reading. `arrival` is when it reached the app, on the `systemUptime` clock.
    func ingest(_ sample: MotionSample, arrival: TimeInterval) {
        if let previous = history.last?.t {
            if sample.t == previous { return }
            if sample.t < previous {
                // The sensor clock restarted, so this is a new session with a new yaw zero.
                endStream(keepHeading: false)
            } else if sample.t - previous > Self.stallTimeout {
                // Don't draw or interpolate across the gap.
                endStream(keepHeading: true)
            }
        }
        if streamStartedAt == nil {
            streamStartedAt = Date()
            log.info("Motion stream started")
        }
        if yawReference == nil { yawReference = sample.yaw }

        latest = sample
        lastArrival = arrival
        status = .streaming
        isConnected = true
        sampleCount += 1
        stats = stats.recording(t: sample.t, arrival: arrival)

        let cutoff = sample.t - Self.historySeconds
        history = Array(history.drop(while: { $0.t < cutoff })) + [sample]

        onSample?(sample)
    }

    private func connectionChanged(_ connected: Bool) {
        isConnected = connected
        log.info("Headphones \(connected ? "connected" : "disconnected", privacy: .public)")
        onConnectionChange?(connected)
        if !connected {
            status = .waiting
            endStream(keepHeading: false)
            latest = nil
        }
    }

    private func endStream(keepHeading: Bool) {
        history = []
        stats = StreamStats()
        streamStartedAt = nil
        lastArrival = nil
        streamID += 1
        if !keepHeading { yawReference = nil }
    }

    private func handle(_ motion: CMDeviceMotion?, _ error: Error?) {
        if let error {
            let ns = error as NSError
            if ns.domain == CMErrorDomain, ns.code == Int(CMErrorMotionActivityNotAuthorized.rawValue) {
                status = .denied
            } else {
                log.error("Motion error: \(error.localizedDescription, privacy: .public)")
                status = .error(error.localizedDescription)
            }
            return
        }
        guard let motion else { return }
        ingest(MotionSample(motion), arrival: ProcessInfo.processInfo.systemUptime)
    }
}

private final class DelegateProxy: NSObject, CMHeadphoneMotionManagerDelegate {
    var onChange: ((Bool) -> Void)?

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        onChange?(true)
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        onChange?(false)
    }
}

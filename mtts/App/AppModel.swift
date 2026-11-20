import AppKit
import Observation

/// One line of headphone state for the sidebar, banners and toolbar.
enum HeadphoneStatus: Equatable {
    case streaming(rate: Double)
    case waiting
    case noHeadphones
    case unsupported(name: String)
    case denied
    case unavailable(String)

    var title: String {
        switch self {
        case .streaming(let rate): "Streaming · \(Int(rate.rounded())) Hz"
        case .waiting: "Waiting for motion"
        case .noHeadphones: "No headphones"
        case .unsupported: "No head tracking"
        case .denied: "Motion access off"
        case .unavailable(let message): message
        }
    }

    var isStreaming: Bool {
        if case .streaming = self { return true }
        return false
    }
}

struct DecodedWord: Identifiable, Hashable {
    let id = UUID()
    var prediction: Prediction
    var text: String { prediction.best?.label ?? "?" }
}

@MainActor @Observable
final class AppModel {
    enum Screen: String, CaseIterable, Identifiable {
        case live = "Live"
        case train = "Train"
        case decode = "Decode"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .live: "gyroscope"
            case .train: "square.stack.3d.up"
            case .decode: "text.bubble"
            }
        }
    }

    let motion = HeadphoneMotionService()
    let device = HeadphoneDeviceMonitor()
    let audio = AudioService()
    let transcriber = MicTranscriber()
    let capture = CaptureController()
    let recorder = SessionRecorder()

    var screen: Screen = .live {
        didSet {
            syncCaptureMode()
            if screen != .live { frozenMotion = nil }
        }
    }

    // MARK: Live view

    /// A still copy of the live plots, taken by Freeze.
    struct FrozenMotion {
        let frame: LiveFrame
    }

    private(set) var frozenMotion: FrozenMotion?
    @ObservationIgnored private var liveEdge: LiveEdge?

    /// What the live plots should draw at `uptime`: the frozen copy, or the stream.
    func liveFrame(at uptime: TimeInterval) -> LiveFrame {
        if let frozenMotion { return frozenMotion.frame }
        var edge: TimeInterval?
        if motion.status == .streaming, let candidate = motion.stats.displayTime(at: uptime) {
            let advanced = liveEdge?.advanced(to: candidate, stream: motion.streamID)
                ?? LiveEdge(stream: motion.streamID, time: candidate)
            liveEdge = advanced
            edge = advanced.time
        }
        return LiveFrame(samples: motion.history, edge: edge, yawReference: motion.yawReference ?? 0)
    }

    /// The newest reading, for numbers that update at the sensor rate rather than every frame.
    var readoutFrame: LiveFrame {
        if let frozenMotion { return frozenMotion.frame }
        guard motion.status == .streaming, let latest = motion.latest else {
            return LiveFrame(samples: [], edge: nil, yawReference: 0)
        }
        return LiveFrame(samples: [latest], edge: latest.t, yawReference: motion.yawReference ?? latest.yaw)
    }

    var canFreeze: Bool { frozenMotion != nil || motion.status == .streaming }
    var canRecenter: Bool { frozenMotion == nil && motion.status == .streaming }

    func toggleFreeze() {
        if frozenMotion != nil {
            frozenMotion = nil
            return
        }
        let frame = liveFrame(at: ProcessInfo.processInfo.systemUptime)
        guard frame.edge != nil else { return }
        frozenMotion = FrozenMotion(frame: frame)
    }

    // MARK: Headphones

    static let deviceKeyDefaultsKey = "lastHeadphoneModel"

    /// The headphones takes are recorded with and matched against. Sticky: it keeps the last
    /// identified model while the headphones are briefly disconnected.
    private(set) var deviceKey: String? = UserDefaults.standard.string(forKey: AppModel.deviceKeyDefaultsKey)

    var headphoneName: String {
        if let model = device.model { return model.name }
        if let output = device.output, output.isBluetooth { return output.name }
        return "No headphones"
    }

    var headphoneSymbol: String {
        device.model?.symbol ?? "headphones"
    }

    var headphoneStatus: HeadphoneStatus {
        switch motion.status {
        case .streaming: return .streaming(rate: motion.sampleRate)
        case .denied: return .denied
        case .unsupported: return .unavailable("Motion unsupported on this Mac")
        case .error(let message): return .unavailable(message)
        case .waiting: break
        }
        guard let output = device.output, output.isBluetooth else { return .noHeadphones }
        if let model = device.model, model.headTracking == .unsupported { return .unsupported(name: model.name) }
        return .waiting
    }

    /// A connected head-tracking headphone that isn't the current output, to offer a switch.
    var switchSuggestion: HeadphoneDeviceMonitor.Output? {
        device.outputs.first { output in
            output.id != device.currentOutputID && output.identification?.model.hasHeadTracking == true
        }
    }

    /// Every take of a word across all headphones, for the delete confirmation.
    func allTakeCount(for word: String) -> Int {
        dataset.templates.filter { $0.label == word }.count
    }

    // MARK: Training

    private(set) var dataset = TemplateStore.load()
    var selectedWord: String?
    var featureSet: FeatureSet = .all {
        didSet { rebuildClassifier() }
    }
    private(set) var classifier: TemplateClassifier?
    private(set) var evaluation: Evaluation?
    private(set) var isEvaluating = false
    private(set) var lastTemplateID: Template.ID?
    /// Built from the click-gesture takes once there are enough of them.
    private(set) var clickMatcher: ClickGestureMatcher?
    var clickTakeCount: Int { templates(for: Template.clickLabel).count }

    // MARK: Head shortcuts

    /// Turn your head from center to fire a shortcut; face center again to re-arm.
    var gesturesEnabled = UserDefaults.standard.bool(forKey: "gesturesEnabled") {
        didSet {
            UserDefaults.standard.set(gesturesEnabled, forKey: "gesturesEnabled")
            gestureDetector.reset()
            // Shortcuts and the pointer both use head turns; only one at a time.
            if gesturesEnabled && pointerEnabled { pointerEnabled = false }
            if gesturesEnabled && !ShortcutSender.isTrusted { ShortcutSender.requestAccess() }
            refreshAccessibility()
        }
    }
    var gestureAction = GestureAction(rawValue: UserDefaults.standard.string(forKey: "gestureAction") ?? "") ?? .tabs {
        didSet { UserDefaults.standard.set(gestureAction.rawValue, forKey: "gestureAction") }
    }
    var gestureTriggerDegrees: Double = UserDefaults.standard.object(forKey: "gestureTriggerDegrees") as? Double ?? 25 {
        didSet {
            UserDefaults.standard.set(gestureTriggerDegrees, forKey: "gestureTriggerDegrees")
            gestureDetector.triggerAngle = gestureTriggerDegrees * .pi / 180
        }
    }
    var gesturesInverted = UserDefaults.standard.bool(forKey: "gesturesInverted") {
        didSet {
            UserDefaults.standard.set(gesturesInverted, forKey: "gesturesInverted")
            gestureDetector.invert = gesturesInverted
        }
    }
    private(set) var gestureArmed = false
    private(set) var lastGesture: (turn: HeadTurn, at: Date)?
    private(set) var accessibilityTrusted = ShortcutSender.isTrusted
    @ObservationIgnored private var gestureDetector = HeadGestureDetector()

    func refreshAccessibility() {
        accessibilityTrusted = ShortcutSender.isTrusted
    }

    // MARK: Gesture click

    /// Clicks the mouse wherever the cursor is when your trained click gesture is seen.
    /// Not persisted: it takes over the mouse button.
    var clickEnabled = false {
        didSet {
            guard clickEnabled != oldValue else { return }
            clickDetector.reset()
            clickScore = nil
            if clickEnabled && !ShortcutSender.isTrusted { ShortcutSender.requestAccess() }
            refreshAccessibility()
        }
    }
    var clickSensitivity: Double = UserDefaults.standard.object(forKey: "clickSensitivity") as? Double ?? 1.2 {
        didSet {
            UserDefaults.standard.set(clickSensitivity, forKey: "clickSensitivity")
            clickDetector.sensitivity = clickSensitivity
        }
    }
    /// Live match against the click takes: at or below 1 clicks.
    private(set) var clickScore: Double?
    private(set) var lastClick: Date?
    @ObservationIgnored private var clickDetector = ClickGestureDetector()

    /// Watches for the trained click gesture. Runs on Live (so you can test it with the meter)
    /// or while clicking is on; only clicks while it's on.
    private func detectClickGesture(_ sample: MotionSample) {
        guard clickMatcher != nil, clickEnabled || screen == .live, !capture.isCapturing else { return }
        let fired = clickDetector.ingest(sample)
        if clickScore != clickDetector.score { clickScore = clickDetector.score }
        guard let start = fired else { return }
        lastClick = Date()
        // With the head pointer on, click where you were pointing when the gesture began.
        if clickEnabled { ShortcutSender.click(at: pointerEnabled ? headPointer.position(at: start) : nil) }
    }

    // MARK: Head pointer

    /// The cursor follows where your head points. Not persisted: it takes over the mouse.
    var pointerEnabled = false {
        didSet {
            guard pointerEnabled != oldValue else { return }
            if pointerEnabled {
                if gesturesEnabled { gesturesEnabled = false }
                if !ShortcutSender.isTrusted { ShortcutSender.requestAccess() }
                refreshAccessibility()
                centerPointer()
                headPointer.start()
            } else {
                headPointer.stop()
            }
        }
    }
    var pointerReachDegrees: Double = UserDefaults.standard.object(forKey: "pointerReachDegrees") as? Double ?? 20 {
        didSet {
            UserDefaults.standard.set(pointerReachDegrees, forKey: "pointerReachDegrees")
            headPointer.mapping.reachDegrees = pointerReachDegrees
        }
    }
    var pointerSmoothing: Double = UserDefaults.standard.object(forKey: "pointerSmoothing") as? Double ?? 0.18 {
        didSet {
            UserDefaults.standard.set(pointerSmoothing, forKey: "pointerSmoothing")
            headPointer.smoothing = pointerSmoothing
        }
    }
    var pointerInvertX = UserDefaults.standard.bool(forKey: "pointerInvertX") {
        didSet {
            UserDefaults.standard.set(pointerInvertX, forKey: "pointerInvertX")
            headPointer.mapping.invertX = pointerInvertX
        }
    }
    var pointerInvertY = UserDefaults.standard.bool(forKey: "pointerInvertY") {
        didSet {
            UserDefaults.standard.set(pointerInvertY, forKey: "pointerInvertY")
            headPointer.mapping.invertY = pointerInvertY
        }
    }
    @ObservationIgnored private let headPointer = HeadPointer()
    /// The pitch that counts as level for the pointer, captured by `centerPointer()`.
    @ObservationIgnored private var pointerPitchReference = 0.0

    /// Makes where you're looking now the middle of the screen (turn and nod).
    func centerPointer() {
        motion.recenter()
        pointerPitchReference = motion.latest?.pitch ?? 0
    }

    private func steerPointer(_ sample: MotionSample) {
        guard pointerEnabled, let reference = motion.yawReference else { return }
        headPointer.update(pose: HeadPose(sample: sample, yawReference: reference),
                           pitchReference: pointerPitchReference)
    }

    private func detectGesture(_ sample: MotionSample) {
        guard gesturesEnabled, let reference = motion.yawReference else { return }
        // Don't fire shortcuts while recording a word.
        guard !capture.isCapturing else { return }
        let turn = gestureDetector.ingest(HeadPose(sample: sample, yawReference: reference))
        if gestureArmed != gestureDetector.isArmed { gestureArmed = gestureDetector.isArmed }
        guard let turn else { return }
        lastGesture = (turn, Date())
        ShortcutSender.send(gestureAction, for: turn)
    }

    // MARK: Decoding

    var decodeMode: CaptureController.Mode = .hold {
        didSet { syncCaptureMode() }
    }
    var maxDistance: Double = 1.5
    var minConfidence: Double = 0.05
    private(set) var decoded: [DecodedWord] = []
    private(set) var lastSegment: [MotionSample] = []

    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var started = false

    init() {
        selectedWord = dataset.vocabulary.first
        rebuildClassifier()
        gestureDetector.triggerAngle = gestureTriggerDegrees * .pi / 180
        gestureDetector.invert = gesturesInverted
        clickDetector.sensitivity = clickSensitivity
        headPointer.mapping = HeadPointerMapping(reachDegrees: pointerReachDegrees,
                                                 invertX: pointerInvertX, invertY: pointerInvertY)
        headPointer.smoothing = pointerSmoothing
    }

    func start() {
        guard !started else { return }
        started = true
        motion.onSample = { [weak self] sample in self?.ingest(sample) }
        motion.onConnectionChange = { [weak self] connected in
            if !connected { self?.frozenMotion = nil }
            self?.device.refresh()
        }
        capture.onSegment = { [weak self] segment in self?.handleSegment(segment) }
        device.onModelChange = { [weak self] in self?.headphonesChanged() }
        device.start()
        motion.start()
        audio.refreshDevices()
        installKeyMonitor()
    }

    private func ingest(_ sample: MotionSample) {
        capture.ingest(sample)
        recorder.record(sample)
        detectGesture(sample)
        steerPointer(sample)
        detectClickGesture(sample)
    }

    /// Re-keys the take set only for a confirmed model, so a failed or early Bluetooth lookup
    /// can't hide the takes recorded with the real headphones.
    private func headphonesChanged() {
        guard device.isModelConfirmed, let model = device.model, model.id != deviceKey else { return }
        deviceKey = model.id
        UserDefaults.standard.set(model.id, forKey: Self.deviceKeyDefaultsKey)
        rebuildClassifier()
    }

    private func syncCaptureMode() {
        capture.autoEnabled = screen == .decode && decodeMode == .auto
    }

    private func handleSegment(_ segment: [MotionSample]) {
        lastSegment = segment
        switch screen {
        case .train:
            guard let word = selectedWord else { return }
            addTemplate(Template(label: word, samples: segment, device: deviceKey))
            recorder.logEvent(segment, kind: "train", label: word, confidence: nil)
        case .decode:
            guard let classifier else { return }
            let prediction = classifier.predict(segment, maxDistance: maxDistance, minConfidence: minConfidence)
            decoded.append(DecodedWord(prediction: prediction))
            recorder.logEvent(segment, kind: prediction.accepted ? "decode" : "reject",
                              label: prediction.best?.label ?? "", confidence: prediction.confidence)
        case .live:
            recorder.logEvent(segment, kind: "segment", label: recorder.prompt, confidence: nil)
        }
    }

    // MARK: Space bar = hold to capture

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard event.keyCode == 49 else { return event }
            let isDown = event.type == .keyDown
            let isRepeat = isDown && event.isARepeat
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.spaceCapturesMotion else { return false }
                if !isDown {
                    self.capture.end()
                } else if !isRepeat {
                    self.capture.begin()
                }
                return true
            }
            return consumed ? nil : event
        }
    }

    private var spaceCapturesMotion: Bool {
        // Let text fields keep the space bar.
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        switch screen {
        case .train: return selectedWord != nil
        case .decode: return decodeMode == .hold && classifier != nil
        case .live: return recorder.isRecording
        }
    }

    // MARK: Dataset editing

    /// Takes recorded with the current headphones.
    var activeTemplates: [Template] {
        dataset.templates(forDevice: deviceKey)
    }

    /// Takes of vocabulary words, without the click gesture.
    var wordTemplates: [Template] {
        activeTemplates.filter { $0.label != Template.clickLabel }
    }

    func templates(for word: String) -> [Template] {
        activeTemplates.filter { $0.label == word }
    }

    func addWord(_ raw: String) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !word.isEmpty, !dataset.vocabulary.contains(word) else { return }
        dataset.vocabulary.append(word)
        selectedWord = word
        persist()
    }

    func removeWord(_ word: String) {
        dataset.vocabulary.removeAll { $0 == word }
        dataset.templates.removeAll { $0.label == word }
        if selectedWord == word { selectedWord = dataset.vocabulary.first }
        persist()
    }

    func addTemplate(_ template: Template) {
        dataset.templates.append(template)
        lastTemplateID = template.id
        persist()
    }

    func deleteTemplate(_ id: Template.ID) {
        dataset.templates.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        TemplateStore.save(dataset)
        rebuildClassifier()
    }

    private func rebuildClassifier() {
        classifier = TemplateClassifier(templates: wordTemplates, featureSet: featureSet)
        clickMatcher = ClickGestureMatcher(templates: templates(for: Template.clickLabel))
        clickDetector.matcher = clickMatcher
        clickDetector.reset()
        clickScore = nil
        evaluation = nil
    }

    func evaluate() {
        guard !isEvaluating else { return }
        isEvaluating = true
        let templates = wordTemplates
        let featureSet = featureSet
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Evaluation.run(templates: templates, featureSet: featureSet)
            }.value
            self.isEvaluating = false
            guard self.featureSet == featureSet, self.wordTemplates == templates else { return }
            self.evaluation = result
        }
    }

    // MARK: Decode transcript

    var transcript: String {
        decoded.filter(\.prediction.accepted).map(\.text).joined(separator: " ")
    }

    func clearDecoded() {
        decoded.removeAll()
        lastSegment = []
    }

    // MARK: Mic

    func toggleMic() async {
        if audio.isRunning {
            transcriber.stop()
            audio.stop()
        } else {
            await audio.start()
            if audio.isRunning { await transcriber.start(sink: audio.sink) }
        }
    }
}

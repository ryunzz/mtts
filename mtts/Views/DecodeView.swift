import SwiftUI

/// Motion → text: segments are classified against the trained vocabulary and appended to a
/// running transcript, with the microphone transcript alongside for comparison.
struct DecodeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Page {
            HeadphoneBanner()
            if model.classifier == nil {
                Banner(symbol: "square.stack.3d.up", title: "Train first",
                       message: "Record takes for at least two words on the Train screen.", tint: .accentColor) {
                    Button("Go to Train") { model.screen = .train }
                }
            }
            HStack {
                Picker("Segmentation", selection: $model.decodeMode) {
                    ForEach(CaptureController.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                Spacer()
                Button("Clear Transcript", action: model.clearDecoded)
                    .disabled(model.decoded.isEmpty)
            }
            TranscriptCard()
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    if model.decodeMode == .hold {
                        CapturePad(
                            title: "Mouth a word",
                            isCapturing: model.capture.isCapturing,
                            isEnabled: model.classifier != nil && model.motion.status == .streaming,
                            onBegin: model.capture.begin,
                            onEnd: model.capture.end)
                    } else {
                        AutoDetectCard()
                    }
                    TuningCard()
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 16) {
                    LastWordCard()
                    MicReferenceCard()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct TranscriptCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card("Transcript", caption: "Decoded from motion only") {
            Group {
                if model.decoded.isEmpty {
                    Text("Mouth a trained word…")
                        .foregroundStyle(.tertiary)
                } else {
                    decodedText.textSelection(.enabled)
                }
            }
            .font(.system(size: 30, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            Text("Faded words fell below the match thresholds.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var decodedText: Text {
        model.decoded.reduce(Text("")) { text, word in
            let piece = Text(word.text + " ")
            return text + (word.prediction.accepted ? piece : piece.foregroundColor(.secondary.opacity(0.35)))
        }
    }
}

private struct AutoDetectCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var capture = model.capture
        let scaleMax = max((capture.threshold ?? 0.05) * 2, 0.02)
        Card("Auto-detect", caption: "Starts a segment when motion rises above the noise floor") {
            HStack(spacing: 6) {
                StatusDot(color: capture.isCapturing ? .red : (capture.noiseFloor == nil ? .secondary : .green))
                Text(capture.isCapturing ? "Capturing" : (capture.noiseFloor == nil ? "Not calibrated" : "Listening"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } content: {
            LevelMeter(value: capture.energy / scaleMax,
                       marker: capture.threshold.map { $0 / scaleMax },
                       tint: capture.isCapturing ? .red : .accentColor)
            HStack {
                Button(capture.isCalibrating ? "Hold still…" : "Calibrate Noise Floor") {
                    capture.calibrate()
                }
                .disabled(capture.isCalibrating || model.motion.status != .streaming)
                if let floor = capture.noiseFloor {
                    Text(String(format: "Floor %.4f", floor))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Trigger") {
                HStack {
                    Slider(value: $capture.triggerRatio, in: 1.5...10)
                    Text(String(format: "%.1f×", capture.triggerRatio))
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            .font(.callout)
            if capture.noiseFloor == nil {
                Text("Calibrate first: keep still for 2 seconds so the detector learns your resting motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct TuningCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card("Match Thresholds") {
            LabeledContent("Max distance") {
                HStack {
                    Slider(value: $model.maxDistance, in: 0.2...4)
                    Text(String(format: "%.2f", model.maxDistance)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
            LabeledContent("Min confidence") {
                HStack {
                    Slider(value: $model.minConfidence, in: 0...0.5)
                    Text(String(format: "%.2f", model.minConfidence)).monospacedDigit().frame(width: 40, alignment: .trailing)
                }
            }
        }
        .font(.callout)
    }
}

private struct LastWordCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card("Last Word", caption: "DTW distance to each word's closest take") {
            if let prediction = model.decoded.last?.prediction {
                let worst = prediction.ranked.last?.distance ?? 1
                VStack(spacing: 8) {
                    ForEach(prediction.ranked) { candidate in
                        let isBest = candidate == prediction.best
                        HStack(spacing: 10) {
                            Text(candidate.label)
                                .font(.callout.weight(isBest ? .semibold : .regular))
                                .frame(width: 70, alignment: .leading)
                            LevelMeter(value: 1 - candidate.distance / max(worst * 1.2, 1e-6),
                                       tint: isBest ? (prediction.accepted ? .green : .orange) : .secondary.opacity(0.5))
                            Text(String(format: "%.2f", candidate.distance))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                Label(String(format: "Confidence %.2f · %@", prediction.confidence,
                             prediction.accepted ? "accepted" : "rejected"),
                      systemImage: prediction.accepted ? "checkmark.circle" : "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(prediction.accepted ? .green : .secondary)
                SignalPlot(title: "Rotation rate", samples: model.lastSegment,
                           channels: SignalPlot.rotation, minScale: 0.05, height: 56)
            } else {
                Text("The ranking for each mouthed word appears here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MicReferenceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Card("Microphone Reference", caption: "Speech recognition, for comparison") {
            HStack(spacing: 10) {
                Button(model.audio.isRunning ? "Stop" : "Start") {
                    Task { await model.toggleMic() }
                }
                .frame(minWidth: 56)
                LevelMeter(value: Double(model.audio.level), tint: .green)
                Button("Clear", action: model.transcriber.clear)
                    .buttonStyle(.borderless)
            }
            Text(model.transcriber.text.isEmpty ? "Whisper or speak to compare against the motion decoder." : model.transcriber.text)
                .font(.callout)
                .foregroundStyle(model.transcriber.text.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            if model.transcriber.isRunning {
                Text(model.transcriber.isOnDevice ? "On-device recognition" : "Server recognition")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if let error = model.audio.error ?? model.transcriber.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

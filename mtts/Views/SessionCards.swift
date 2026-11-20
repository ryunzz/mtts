import CoreAudio
import SwiftUI

/// Optional reference audio from any input.
struct MicrophoneCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var audio = model.audio
        Card("Microphone", caption: "Optional reference audio") {
            Picker("Input", selection: $audio.selectedDeviceID) {
                Text("System Default").tag(AudioDeviceID?.none)
                ForEach(audio.devices) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            HStack(spacing: 10) {
                Button(audio.isRunning ? "Stop" : "Start") {
                    Task { await model.toggleMic() }
                }
                .frame(minWidth: 56)
                LevelMeter(value: Double(audio.level), tint: .green)
                Button("Refresh Inputs", systemImage: "arrow.clockwise") { audio.refreshDevices() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            if let name = audio.activeDeviceName {
                Text("Listening to \(name)").font(.caption).foregroundStyle(.secondary)
            }
            if let error = audio.error ?? model.transcriber.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("Using your Powerbeats as the input switches them to the headset profile, which lowers playback quality.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fillingHeight()
    }
}

/// Synchronized motion, audio and marks for offline analysis.
struct RecordingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var recorder = model.recorder
        Card("Session Recording", caption: "Motion CSV, audio and marks") {
            if let url = recorder.lastSessionURL, !recorder.isRecording {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .buttonStyle(.link)
            }
        } content: {
            Picker("Condition", selection: $recorder.condition) {
                ForEach(SessionRecorder.Condition.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(recorder.isRecording)

            TextField("What you'll say, e.g. “yes no yes stop”", text: $recorder.prompt)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Button {
                    recorder.isRecording ? recorder.stop() : recorder.start(audio: model.audio)
                } label: {
                    Label(recorder.isRecording ? "Stop" : "Record",
                          systemImage: recorder.isRecording ? "stop.fill" : "record.circle")
                        .frame(minWidth: 70)
                }
                .buttonStyle(.borderedProminent)
                .tint(recorder.isRecording ? .red : .accentColor)

                if recorder.isRecording, let startedAt = recorder.startedAt {
                    Text(startedAt, style: .timer).monospacedDigit()
                    Text("\(recorder.motionCount) samples · \(recorder.eventCount) marks")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)

            Text(model.audio.isRunning
                 ? "Records motion and audio. Hold Space to mark each utterance."
                 : "Records motion only. Start the microphone to add audio. Hold Space to mark each utterance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = recorder.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .fillingHeight()
    }
}

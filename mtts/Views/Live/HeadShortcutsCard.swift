import SwiftUI

/// Turn your head from center to send a shortcut; face center again to re-arm.
struct HeadShortcutsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card("Head Shortcuts",
             caption: "Turn from center to fire once. Face center again to re-arm.") {
            Toggle("On", isOn: $model.gesturesEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        } content: {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Action", selection: $model.gestureAction) {
                        ForEach(GestureAction.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .fixedSize()
                    Text(model.gestureAction.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Text("Turn")
                        Slider(value: $model.gestureTriggerDegrees, in: 10...45, step: 1)
                            .frame(width: 140)
                        Text("\(Int(model.gestureTriggerDegrees))°").monospacedDigit()
                    }
                    .font(.callout)
                    Toggle("Swap left and right", isOn: $model.gesturesInverted)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                }
                Spacer(minLength: 0)
                GestureStatus()
            }
            if model.gesturesEnabled && !model.accessibilityTrusted {
                AccessibilityWarning(action: "send keystrokes to other apps")
            }
        }
        .task(id: model.gesturesEnabled) {
            // Pick up the Accessibility grant once it's switched on in System Settings.
            while model.gesturesEnabled && !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Shown while a gesture feature is on but macOS won't deliver synthetic events yet.
struct AccessibilityWarning: View {
    var action: String

    var body: some View {
        HStack(spacing: 8) {
            Label("mtts needs Accessibility access to \(action).", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Open Settings") { ShortcutSender.openSettings() }
        }
        .font(.callout)
    }
}

/// Armed / fired, with the last turn flashing briefly.
private struct GestureStatus: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let recent = model.lastGesture.flatMap { context.date.timeIntervalSince($0.at) < 1.2 ? $0.turn : nil }
            HStack(spacing: 14) {
                arrow("arrow.left", label: "Previous", lit: recent == .left)
                VStack(spacing: 4) {
                    Image(systemName: model.gestureArmed ? "scope" : "circle.dashed")
                        .font(.title2)
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 110)
                arrow("arrow.right", label: "Next", lit: recent == .right)
            }
        }
    }

    private var statusText: String {
        if !model.gesturesEnabled { return "Off" }
        if model.motion.status != .streaming { return "No motion" }
        return model.gestureArmed ? "Armed" : "Face center"
    }

    private var statusColor: Color {
        guard model.gesturesEnabled, model.motion.status == .streaming else { return .secondary }
        return model.gestureArmed ? .green : .orange
    }

    private func arrow(_ symbol: String, label: String, lit: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(lit ? Color.accentColor : Color.secondary.opacity(0.4))
                .scaleEffect(lit ? 1.25 : 1)
                .animation(.spring(duration: 0.25), value: lit)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

import SwiftUI

/// Point your nose at the center to arm, then turn left or right to send a shortcut.
struct HeadShortcutsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card("Head Shortcuts",
             caption: "Point your nose at the center circle to arm, then turn: left goes left, right goes right. Come back to center before the next one.") {
            Button("Center", systemImage: "scope") { model.motion.recenter() }
                .buttonStyle(.borderless)
                .disabled(!model.canRecenter)
                .help("Make where your nose points now the center")
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
                NoseTarget()
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

/// Where your nose points, with the center circle that arms shortcuts and the left and
/// right zones that fire them. The zone you turned into lights up.
private struct NoseTarget: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            LiveTimeline { frame in
                Canvas { context, size in draw(&context, size, pose: frame.pose) }
            }
            .frame(width: 320, height: 120)
            .background(Color.subtleFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(statusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
        }
        .accessibilityElement()
        .accessibilityLabel("Nose target: \(statusText)")
    }

    /// Degrees across half the width: a bit past the trigger so the zones have room.
    private var halfRange: Double { model.gestureTriggerDegrees * 1.5 }
    private static let pitchHalfRange = 15.0

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, pose: HeadPose?) {
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let degreesToX = size.width / 2 / halfRange
        let trigger = model.gestureTriggerDegrees * degreesToX
        let recent = model.lastGesture.flatMap { Date().timeIntervalSince($0.at) < 1.0 ? $0.turn : nil }
        let (leftLabel, rightLabel) = model.gestureAction.zoneLabels

        // Left and right zones, lit when they just fired.
        for (turn, rect, label) in [(HeadTurn.left, CGRect(x: 0, y: 0, width: mid.x - trigger, height: size.height), leftLabel),
                                    (HeadTurn.right, CGRect(x: mid.x + trigger, y: 0, width: mid.x - trigger, height: size.height), rightLabel)] {
            let lit = recent == turn
            context.fill(Path(roundedRect: rect, cornerRadius: 10),
                         with: .color(lit ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.05)))
            context.draw(Text(label).font(.caption.weight(lit ? .bold : .regular))
                            .foregroundStyle(lit ? Color.accentColor : Color.secondary),
                         at: CGPoint(x: rect.midX, y: size.height - 12))
        }

        // The center circle: point your nose in here to arm.
        let armed = model.gesturesEnabled && model.gestureArmed
        let straight = pose?.isStraight ?? false
        let r = HeadPose.straightToleranceDegrees * degreesToX
        let ring = Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2))
        context.fill(ring, with: .color((straight ? Color.green : Color.primary).opacity(straight ? 0.18 : 0.04)))
        context.stroke(ring, with: .color(straight ? .green : .secondary.opacity(0.6)), lineWidth: straight ? 2 : 1)

        // The nose. Shown the way it will fire, so "Swap left and right" moves it too.
        guard let pose else { return }
        let yaw = (model.gesturesInverted ? -pose.yaw : pose.yaw) * 180 / .pi
        let pitch = pose.pitch * 180 / .pi
        let x = min(max(mid.x - yaw * degreesToX, 6), size.width - 6)
        let y = min(max(mid.y - pitch / Self.pitchHalfRange * (size.height / 2), 6), size.height - 6)
        let color: Color = !model.gesturesEnabled ? .secondary : armed ? .green : .orange
        context.fill(Path(ellipseIn: CGRect(x: x - 6, y: y - 6, width: 12, height: 12)), with: .color(color))
    }

    private var statusText: String {
        if !model.gesturesEnabled { return "Off: turn on to use" }
        if model.motion.status != .streaming { return "No motion" }
        return model.gestureArmed ? "Armed: turn left or right" : "Point your nose at the center"
    }

    private var statusColor: Color {
        guard model.gesturesEnabled, model.motion.status == .streaming else { return .secondary }
        return model.gestureArmed ? .green : .orange
    }
}

private extension GestureAction {
    /// What turning into each zone does, for the zone labels.
    var zoneLabels: (left: String, right: String) {
        switch self {
        case .tabs: ("◀ Tab left", "Tab right ▶")
        case .desktops: ("◀ Desktop left", "Desktop right ▶")
        case .arrows: ("◀ Previous", "Next ▶")
        }
    }
}

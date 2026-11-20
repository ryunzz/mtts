import SwiftUI

/// The cursor follows where your head points. Pair it with Gesture Click to click hands-free.
struct HeadPointerCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card("Head Pointer",
             caption: "The cursor follows your head. Face the middle of the screen and press Center first.") {
            Button("Center", systemImage: "scope") { model.centerPointer() }
                .buttonStyle(.borderless)
                .disabled(!model.canRecenter)
                .help("Make where you're looking now the middle of the screen")
            Toggle("On", isOn: $model.pointerEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.motion.status != .streaming && !model.pointerEnabled)
        } content: {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    slider("Reach", value: $model.pointerReachDegrees, in: 8...40, step: 1,
                           label: "±\(Int(model.pointerReachDegrees))°",
                           help: "How far you turn to reach the screen edge. Lower is faster.")
                    // Shown as "smoothness": the model stores how far the cursor moves per frame.
                    slider("Smooth", value: Binding(get: { 1 - model.pointerSmoothing },
                                                    set: { model.pointerSmoothing = 1 - $0 }),
                           in: 0.5...0.95, step: 0.01,
                           label: "\(Int(((1 - model.pointerSmoothing) - 0.5) / 0.45 * 100))%",
                           help: "Higher is steadier but lags more.")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Swap left and right", isOn: $model.pointerInvertX)
                    Toggle("Swap up and down", isOn: $model.pointerInvertY)
                }
                .toggleStyle(.checkbox)
                .font(.callout)
                Spacer(minLength: 0)
            }
            Text(model.clickMatcher == nil
                 ? "To click hands-free, record a click motion and turn on Gesture Click below."
                 : model.clickEnabled ? "Gesture Click is on: do your click motion to click where you're pointing."
                                      : "Turn on Gesture Click below to click where you're pointing.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.pointerEnabled && !model.accessibilityTrusted {
                AccessibilityWarning(action: "move the cursor")
            }
            if model.pointerEnabled {
                Label("Move the mouse yourself any time: the head pointer steps aside for a moment.",
                      systemImage: "computermouse")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: model.pointerEnabled) {
            while model.pointerEnabled && !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                        label: String, help: String) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 52, alignment: .leading)
            Slider(value: value, in: range, step: step).frame(width: 140)
            Text(label).monospacedDigit().frame(width: 44, alignment: .leading)
        }
        .font(.callout)
        .help(help)
    }
}

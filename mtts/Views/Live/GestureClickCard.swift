import SwiftUI

/// Click the mouse with a motion you trained yourself, wherever the cursor is.
struct GestureClickCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card("Gesture Click",
             caption: "Do your trained click motion to click wherever the cursor is.") {
            Toggle("On", isOn: $model.clickEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(model.clickMatcher == nil && !model.clickEnabled)
        } content: {
            if model.clickMatcher == nil {
                HStack(spacing: 8) {
                    Label("Record at least \(ClickGestureMatcher.minimumTakes) takes of your click motion (\(model.clickTakeCount) so far).",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    Spacer()
                    RecordTakesButton()
                }
                .font(.callout)
            } else {
                HStack(alignment: .center, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Sensitivity")
                            Slider(value: $model.clickSensitivity, in: 0.6...2.5, step: 0.05)
                                .frame(width: 140)
                            Text(String(format: "%.2f×", model.clickSensitivity)).monospacedDigit()
                        }
                        .font(.callout)
                        HStack(spacing: 8) {
                            Text("\(model.clickTakeCount) takes").font(.caption).foregroundStyle(.secondary)
                            RecordTakesButton()
                        }
                    }
                    MatchMeter(score: model.clickScore)
                    Spacer(minLength: 0)
                    ClickFlash()
                }
            }
            if model.clickEnabled && !model.accessibilityTrusted {
                AccessibilityWarning(action: "click in other apps")
            }
        }
        .task(id: model.clickEnabled) {
            while model.clickEnabled && !Task.isCancelled {
                model.refreshAccessibility()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

private struct RecordTakesButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Record Takes…") {
            model.selectedWord = Template.clickLabel
            model.screen = .train
        }
        .buttonStyle(.link)
    }
}

/// How close the live stream is to your click motion. Full bar clicks.
private struct MatchMeter: View {
    var score: Double?

    private var level: Double {
        guard let score, score > 0 else { return 0 }
        return min(1, 1 / score)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Match").font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(level >= 1 ? Color.green : Color.accentColor)
                        .frame(width: proxy.size.width * level)
                }
            }
            .frame(width: 140, height: 6)
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }
}

/// Lights up briefly when the click motion is seen, even with clicking off.
private struct ClickFlash: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let lit = model.lastClick.map { context.date.timeIntervalSince($0) < 1 } ?? false
            VStack(spacing: 4) {
                Image(systemName: "cursorarrow.click.2")
                    .font(.title2)
                    .foregroundStyle(lit ? Color.accentColor : Color.secondary.opacity(0.4))
                    .scaleEffect(lit ? 1.2 : 1)
                    .animation(.spring(duration: 0.25), value: lit)
                Text(model.clickEnabled ? "Click" : "Seen").font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 70)
        }
    }
}

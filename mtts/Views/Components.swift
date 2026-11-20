import SwiftUI

/// Multi-channel line plot of motion samples, drawn with Canvas so it keeps up at sensor rate.
struct SignalPlot: View {
    struct Channel {
        var name: String
        var color: Color
        var value: KeyPath<MotionSample, Double>
    }

    var title: String
    var samples: [MotionSample]
    var channels: [Channel]
    /// Visible time span; defaults to the extent of `samples`.
    var span: ClosedRange<TimeInterval>?
    var minScale: Double = 0.02
    var height: CGFloat = 84
    var showsHeader = true

    static let acceleration = [
        Channel(name: "x", color: .pink, value: \.ax),
        Channel(name: "y", color: .green, value: \.ay),
        Channel(name: "z", color: .blue, value: \.az),
    ]
    static let rotation = [
        Channel(name: "x", color: .pink, value: \.rx),
        Channel(name: "y", color: .green, value: \.ry),
        Channel(name: "z", color: .blue, value: \.rz),
    ]
    static let attitude = [
        Channel(name: "pitch", color: .orange, value: \.pitch),
        Channel(name: "roll", color: .purple, value: \.roll),
        Channel(name: "yaw", color: .teal, value: \.yaw),
    ]

    var body: some View {
        let range = span ?? ((samples.first?.t ?? 0)...(samples.last?.t ?? 1))
        let visible = samples.filter { range.contains($0.t) }
        let scale = max(minScale, channels.flatMap { c in visible.map { abs($0[keyPath: c.value]) } }.max() ?? 0)

        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack(spacing: 12) {
                    Text(title).font(.subheadline.weight(.medium))
                    ForEach(channels, id: \.name) { channel in
                        HStack(spacing: 4) {
                            Circle().fill(channel.color).frame(width: 6, height: 6)
                            Text(channel.name)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("±\(scale, specifier: "%.3f")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Canvas { context, size in
                let mid = size.height / 2
                var grid = Path()
                for fraction in [0.25, 0.5, 0.75] {
                    let y = size.height * fraction
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(.primary.opacity(0.06)), lineWidth: 0.5)

                let width = max(range.upperBound - range.lowerBound, 1e-3)
                for channel in channels {
                    var path = Path()
                    for (i, s) in visible.enumerated() {
                        let point = CGPoint(
                            x: (s.t - range.lowerBound) / width * size.width,
                            y: mid - s[keyPath: channel.value] / scale * (mid - 3))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(path, with: .color(channel.color.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
            .frame(height: height)
            .background(Color.subtleFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct LevelMeter: View {
    var value: Double
    var marker: Double?
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(tint)
                    .frame(width: max(geo.size.width * min(max(value, 0), 1), 0))
                if let marker {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: geo.size.height + 6)
                        .offset(x: geo.size.width * min(max(marker, 0), 1) - 1)
                }
            }
        }
        .frame(height: 6)
        .animation(.linear(duration: 0.08), value: value)
    }
}

/// The press-and-hold target. Space does the same thing from anywhere on the screen.
struct CapturePad: View {
    var title: String
    var isCapturing: Bool
    var isEnabled = true
    var onBegin: () -> Void
    var onEnd: () -> Void

    @State private var pressed = false

    private var tint: Color { isCapturing ? .red : .accentColor }

    // Split into small typed pieces: as one expression the body is slow enough to type-check
    // that some compiler versions give up.
    var body: some View {
        VStack(spacing: 12) {
            badge
            caption
        }
        .frame(maxWidth: .infinity, minHeight: 190)
        .background(padBackground)
        .overlay(padBorder)
        .contentShape(Rectangle())
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeOut(duration: 0.15), value: isCapturing)
        .gesture(pressGesture)
        .accessibilityLabel(isCapturing ? "Recording" : title)
        .accessibilityAddTraits(.isButton)
    }

    private var badge: some View {
        ZStack {
            if isCapturing {
                Pulse()
            }
            Circle()
                .fill(tint.opacity(isCapturing ? 0.14 : 0.10))
            Image(systemName: isCapturing ? "waveform" : "mouth")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.variableColor.iterative, isActive: isCapturing)
        }
        .frame(width: 64, height: 64)
    }

    private var caption: some View {
        VStack(spacing: 12) {
            Text(isCapturing ? "Recording…" : title)
                .font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                Text("Hold")
                KeyCap(label: "Space")
                Text("or press and hold here")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var padShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
    }

    private var padBackground: some View {
        let fill: Color = isCapturing ? Color.red.opacity(0.05) : Color.subtleFill.opacity(0.5)
        return padShape.fill(fill)
    }

    private var padBorder: some View {
        let color: Color = isCapturing ? Color.red.opacity(0.5) : Color.primary.opacity(0.12)
        let style: StrokeStyle = isCapturing
            ? StrokeStyle(lineWidth: 1.5)
            : StrokeStyle(lineWidth: 1, dash: [5, 4])
        return padShape.strokeBorder(color, style: style)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled, !pressed else { return }
                pressed = true
                onBegin()
            }
            .onEnded { _ in
                guard pressed else { return }
                pressed = false
                onEnd()
            }
    }
}

/// An expanding ring behind the capture badge while recording.
private struct Pulse: View {
    var body: some View {
        PhaseAnimator([0.0, 1.0]) { (phase: Double) in
            Circle()
                .stroke(Color.red.opacity(0.4), lineWidth: 2)
                .scaleEffect(1 + 0.4 * phase)
                .opacity(1 - phase)
        } animation: { (phase: Double) -> Animation in
            phase == 1 ? .easeOut(duration: 1.1) : .linear(duration: 0)
        }
    }
}

/// "7 of 10" as a row of segments.
struct TakeProgress: View {
    var count: Int
    var target: Int = Layout.takeTarget

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(0..<target, id: \.self) { index in
                    Capsule()
                        .fill(index < count ? Color.accentColor : Color.primary.opacity(0.1))
                        .frame(width: 14, height: 5)
                }
            }
            Text(count >= target ? "\(count) takes" : "\(count) of \(target) takes")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .animation(.easeOut(duration: 0.2), value: count)
    }
}

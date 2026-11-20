import SwiftUI

/// One plotted channel: a motion field converted into display units.
struct ScopeChannel: Identifiable {
    let name: String
    let color: Color
    let field: KeyPath<MotionSample, Double>
    var factor: Double = 1
    var id: String { name }

    func read(_ sample: MotionSample) -> Double { sample[keyPath: field] * factor }

    static let degreesPerRadian = 180 / Double.pi
    static let milliG = 1000.0

    @MainActor static let gyroscope = [
        ScopeChannel(name: "X", color: .red, field: \.rx, factor: degreesPerRadian),
        ScopeChannel(name: "Y", color: .green, field: \.ry, factor: degreesPerRadian),
        ScopeChannel(name: "Z", color: .blue, field: \.rz, factor: degreesPerRadian),
    ]
    @MainActor static let accelerometer = [
        ScopeChannel(name: "X", color: .red, field: \.ax, factor: milliG),
        ScopeChannel(name: "Y", color: .green, field: \.ay, factor: milliG),
        ScopeChannel(name: "Z", color: .blue, field: \.az, factor: milliG),
    ]
}

/// Re-renders every display frame while motion streams, and hands its content the frame to
/// draw. Paused while idle or frozen, so it costs nothing then.
struct LiveTimeline<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let content: (LiveFrame) -> Content

    init(@ViewBuilder content: @escaping (LiveFrame) -> Content) {
        self.content = content
    }

    var body: some View {
        let paused = model.frozenMotion != nil || model.motion.status != .streaming
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { _ in
            content(model.liveFrame(at: ProcessInfo.processInfo.systemUptime))
        }
    }
}

/// A scrolling oscilloscope. The right edge is "now"; each trace ends in a dot showing the
/// current value, and the scale snaps to 1–2–5 steps.
struct LiveScope: View {
    let frame: LiveFrame
    let channels: [ScopeChannel]
    var span: TimeInterval = 6
    var minimumScale: Double
    var minHeight: CGFloat = 160

    private static let gutter: CGFloat = 40
    private static let inset: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .frame(minHeight: minHeight, maxHeight: .infinity)
        .overlay {
            if frame.edge == nil {
                Text("Waiting for motion").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .background(Color.subtleFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(channels.map(\.name).joined(separator: ", ") + " live plot")
    }

    private struct Mapper {
        let plot: CGRect
        let start: TimeInterval
        let span: TimeInterval
        let scale: Double

        func x(_ t: TimeInterval) -> CGFloat { plot.minX + (t - start) / span * plot.width }
        func y(_ v: Double) -> CGFloat {
            plot.midY - min(max(v / scale, -1.05), 1.05) * plot.height / 2
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let plot = CGRect(x: 0, y: Self.inset, width: max(size.width - Self.gutter, 1),
                          height: max(size.height - Self.inset * 2, 1))
        let edge = frame.edge
        let end = edge ?? 0
        // Half a second either side, so lines run cleanly off both edges.
        let visible = edge == nil ? [] : Trace.window(from: end - span - 0.5, to: end + 0.5, in: frame.samples)
        let map = Mapper(plot: plot, start: end - span, span: span,
                         scale: ScopeScale.niceCeiling(peak(of: visible, through: end), minimum: minimumScale))

        drawGrid(&context, map, scrolling: edge != nil)
        drawScaleLabels(&context, map)
        var traces = context
        traces.clip(to: Path(plot))
        for channel in channels {
            drawTrace(&traces, channel, visible, map)
        }
        if let edge {
            for channel in channels {
                drawLiveDot(&context, channel, map, at: edge)
            }
        }
    }

    /// The largest magnitude on screen, ignoring readings past the live edge.
    private func peak(of samples: ArraySlice<MotionSample>, through end: TimeInterval) -> Double {
        var peak = 0.0
        for sample in samples where sample.t <= end {
            for channel in channels {
                peak = max(peak, abs(channel.read(sample)))
            }
        }
        return peak
    }

    private func drawGrid(_ context: inout GraphicsContext, _ map: Mapper, scrolling: Bool) {
        var lines = Path()
        for fraction in [-1.0, -0.5, 0.5, 1.0] {
            let y = map.y(fraction * map.scale)
            lines.move(to: CGPoint(x: map.plot.minX, y: y))
            lines.addLine(to: CGPoint(x: map.plot.maxX, y: y))
        }
        if scrolling {
            // One line per second, moving with the data.
            let first = Int(ceil(map.start)), last = Int(floor(map.start + map.span))
            for second in stride(from: first, through: last, by: 1) {
                let x = map.x(Double(second))
                lines.move(to: CGPoint(x: x, y: map.plot.minY))
                lines.addLine(to: CGPoint(x: x, y: map.plot.maxY))
            }
        }
        context.stroke(lines, with: .color(.primary.opacity(0.06)), lineWidth: 0.5)

        var zero = Path()
        zero.move(to: CGPoint(x: map.plot.minX, y: map.plot.midY))
        zero.addLine(to: CGPoint(x: map.plot.maxX, y: map.plot.midY))
        context.stroke(zero, with: .color(.primary.opacity(0.16)), lineWidth: 0.75)
    }

    private func drawScaleLabels(_ context: inout GraphicsContext, _ map: Mapper) {
        let magnitude = map.scale >= 1 ? String(format: "%.0f", map.scale) : String(format: "%g", map.scale)
        for (value, label) in [(map.scale, "+" + magnitude), (0, "0"), (-map.scale, "−" + magnitude)] {
            let text = Text(label).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            context.draw(text, at: CGPoint(x: map.plot.maxX + 8, y: map.y(value)), anchor: .leading)
        }
    }

    private func drawTrace(_ context: inout GraphicsContext, _ channel: ScopeChannel,
                           _ samples: ArraySlice<MotionSample>, _ map: Mapper) {
        var path = Path()
        var previous: CGPoint?
        // Curves through the midpoints, so 25 Hz data reads as a smooth line.
        for sample in samples {
            let point = CGPoint(x: map.x(sample.t), y: map.y(channel.read(sample)))
            if let previous {
                path.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2),
                                  control: previous)
            } else {
                path.move(to: point)
            }
            previous = point
        }
        guard let last = previous else { return }
        path.addLine(to: last)
        context.stroke(path, with: .color(channel.color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    private func drawLiveDot(_ context: inout GraphicsContext, _ channel: ScopeChannel, _ map: Mapper, at edge: TimeInterval) {
        guard let value = Trace.value(at: edge, in: frame.samples, read: channel.read) else { return }
        let center = CGPoint(x: map.plot.maxX, y: map.y(value))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)),
                     with: .color(channel.color.opacity(0.18)))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)),
                     with: .color(channel.color))
    }
}

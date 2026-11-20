import SwiftUI

/// Where your head points: turn on the horizontal axis, nod on the vertical, with a fading
/// trail of the last few seconds.
struct HeadDirectionPlot: View {
    let frame: LiveFrame

    static let yawRange = 60.0
    static let pitchRange = 40.0
    static let trailSeconds = 3.0

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14)
            drawGrid(&context, rect)
            guard let edge = frame.edge else { return }
            drawTrail(&context, rect, edge: edge)
            if let pose = frame.pose {
                let p = point(pose, in: rect)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)),
                             with: .color(.accentColor.opacity(0.18)))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(.accentColor))
            }
        }
        .frame(minHeight: 150, maxHeight: .infinity)
        .overlay {
            if frame.edge == nil {
                Text("Waiting for motion").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .background(Color.subtleFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Head direction")
    }

    /// Turning left (positive yaw) moves left; looking up moves up.
    private func point(_ pose: HeadPose, in rect: CGRect) -> CGPoint {
        let x = min(max(-Angles.degrees(pose.yaw) / Self.yawRange, -1), 1)
        let y = min(max(Angles.degrees(pose.pitch) / Self.pitchRange, -1), 1)
        return CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY - y * rect.height / 2)
    }

    private func drawGrid(_ context: inout GraphicsContext, _ rect: CGRect) {
        var rings = Path()
        for fraction in [1.0 / 3, 2.0 / 3, 1] {
            let w = rect.width * fraction, h = rect.height * fraction
            rings.addEllipse(in: CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h))
        }
        context.stroke(rings, with: .color(.primary.opacity(0.07)), lineWidth: 0.75)

        var cross = Path()
        cross.move(to: CGPoint(x: rect.minX, y: rect.midY)); cross.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        cross.move(to: CGPoint(x: rect.midX, y: rect.minY)); cross.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        context.stroke(cross, with: .color(.primary.opacity(0.14)), lineWidth: 0.75)

        let labels: [(String, CGPoint, UnitPoint)] = [
            ("Left", CGPoint(x: rect.minX - 6, y: rect.midY - 8), .leading),
            ("Right", CGPoint(x: rect.maxX + 6, y: rect.midY - 8), .trailing),
            ("Up", CGPoint(x: rect.midX + 6, y: rect.minY - 6), .topLeading),
            ("Down", CGPoint(x: rect.midX + 6, y: rect.maxY + 6), .bottomLeading),
        ]
        for (label, at, anchor) in labels {
            context.draw(Text(label).font(.caption2).foregroundStyle(.tertiary), at: at, anchor: anchor)
        }
    }

    private func drawTrail(_ context: inout GraphicsContext, _ rect: CGRect, edge: TimeInterval) {
        let start = edge - Self.trailSeconds
        let poses = Trace.window(from: start, to: edge, in: frame.samples).map {
            (t: $0.t, pose: HeadPose(sample: $0, yawReference: frame.yawReference))
        } + (frame.pose.map { [(t: edge, pose: $0)] } ?? [])
        for (a, b) in zip(poses, poses.dropFirst()) {
            // Crossing directly behind you would otherwise draw a line across the whole plot.
            guard abs(Angles.wrapped(b.pose.yaw - a.pose.yaw)) < .pi / 2,
                  abs(b.pose.yaw - a.pose.yaw) < .pi else { continue }
            let age = (b.t - start) / Self.trailSeconds
            var segment = Path()
            segment.move(to: point(a.pose, in: rect))
            segment.addLine(to: point(b.pose, in: rect))
            context.stroke(segment, with: .color(.accentColor.opacity(0.08 + 0.6 * age)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

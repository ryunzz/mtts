import SwiftUI

/// A wireframe head that turns, nods and tilts with yours. It's drawn as a mirror image:
/// turn left and it turns toward the left of the screen.
struct HeadOrientationView: View {
    let pose: HeadPose?

    var body: some View {
        Canvas { context, size in
            let camera = HeadCamera(size: size)
            let rotation = (pose ?? HeadPose(pitch: 0, roll: 0, yaw: 0)).orientation
            drawFloor(&context, camera)
            drawWire(&context, camera, rotation, front: false)
            drawBuds(&context, camera, rotation, front: false)
            drawVisor(&context, camera, rotation)
            drawWire(&context, camera, rotation, front: true)
            drawBuds(&context, camera, rotation, front: true)
            drawNose(&context, camera, rotation)
        }
        .opacity(pose == nil ? 0.4 : 1)
        .accessibilityElement()
        .accessibilityLabel("Head orientation")
    }

    private func drawFloor(_ context: inout GraphicsContext, _ camera: HeadCamera) {
        let z = HeadGeometry.floorHeight
        let ring = HeadGeometry.circle(radius: 1.25, z: z).map(camera.project)
        let shadow = HeadGeometry.circle(radius: 0.7, z: z).map(camera.project)
        context.fill(Path { $0.addLines(shadow); $0.closeSubpath() }, with: .color(.primary.opacity(0.05)))
        context.stroke(Path { $0.addLines(ring); $0.closeSubpath() }, with: .color(.primary.opacity(0.1)), lineWidth: 1)
        // Tick marking the forward direction you recentered on.
        var tick = Path()
        tick.move(to: camera.project(Vector3(0, 1.1, z)))
        tick.addLine(to: camera.project(Vector3(0, 1.45, z)))
        context.stroke(tick, with: .color(.primary.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    private func drawWire(_ context: inout GraphicsContext, _ camera: HeadCamera, _ rotation: Quaternion, front: Bool) {
        var wire = Path(), face = Path()
        for (index, line) in HeadGeometry.wireframe.enumerated() {
            let world = line.map(rotation.rotate)
            for i in 1..<line.count {
                let midDepth = camera.depth((world[i - 1] + world[i]) * 0.5)
                guard (midDepth > 0) == front else { continue }
                // The front half of the first meridian runs down the middle of the face.
                let isFace = index == 0 && line[i].y > 0
                let a = camera.project(world[i - 1]), b = camera.project(world[i])
                if isFace {
                    face.move(to: a); face.addLine(to: b)
                } else {
                    wire.move(to: a); wire.addLine(to: b)
                }
            }
        }
        context.stroke(wire, with: .color(.primary.opacity(front ? 0.32 : 0.09)), lineWidth: front ? 1 : 0.75)
        context.stroke(face, with: .color(.accentColor.opacity(front ? 1 : 0.25)),
                       style: StrokeStyle(lineWidth: front ? 2 : 1, lineCap: .round))
    }

    /// A band across the eyes, so the facing direction reads even head-on.
    private func drawVisor(_ context: inout GraphicsContext, _ camera: HeadCamera, _ rotation: Quaternion) {
        let facing = camera.depth(rotation.rotate(.unitY))
        guard facing > -0.35 else { return }
        let outline = HeadGeometry.visor.map { camera.project(rotation.rotate($0)) }
        let path = Path { $0.addLines(outline); $0.closeSubpath() }
        let strength = min(1, (facing + 0.35) / 0.8)
        context.fill(path, with: .color(.accentColor.opacity(0.22 * strength)))
        context.stroke(path, with: .color(.accentColor.opacity(0.7 * strength)), lineWidth: 1)
    }

    private func drawBuds(_ context: inout GraphicsContext, _ camera: HeadCamera, _ rotation: Quaternion, front: Bool) {
        for bud in HeadGeometry.buds {
            let world = rotation.rotate(bud.position)
            guard (camera.depth(world) > 0) == front else { continue }
            let center = camera.project(world)
            let radius = HeadGeometry.budRadius * camera.scale(at: world)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .color(.accentColor.opacity(front ? 0.9 : 0.3)))
            let label = Text(bud.label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            let offset = bud.position + Vector3(bud.position.x * 0.45, 0, 0)
            context.draw(label, at: camera.project(rotation.rotate(offset)))
        }
    }

    private func drawNose(_ context: inout GraphicsContext, _ camera: HeadCamera, _ rotation: Quaternion) {
        let base = rotation.rotate(HeadGeometry.noseBase)
        let tip = rotation.rotate(HeadGeometry.noseTip)
        let opacity = camera.depth(tip) > -0.3 ? 1.0 : 0.35
        var line = Path()
        line.move(to: camera.project(base))
        line.addLine(to: camera.project(tip))
        context.stroke(line, with: .color(.accentColor.opacity(opacity)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        let point = camera.project(tip)
        context.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)),
                     with: .color(.accentColor.opacity(opacity)))
    }
}

/// The head model, in the headphones' frame (x ear to ear, y forward, z up).
private enum HeadGeometry {
    static let radii = Vector3(0.8, 0.95, 1.05)
    static let floorHeight = -1.35
    static let budRadius = 0.11
    static let noseBase = Vector3(0, 0.95, 0)
    static let noseTip = Vector3(0, 1.6, 0)
    static let buds = [(label: "L", position: Vector3(-0.84, 0.05, -0.1)),
                       (label: "R", position: Vector3(0.84, 0.05, -0.1))]

    /// Eye-level band on the front of the head, as a closed outline.
    static let visor: [Vector3] = {
        let lons = stride(from: -55.0, through: 55, by: 5).map { $0 * .pi / 180 }
        let top = lons.map { surface(lat: 24 * .pi / 180, lon: $0, lift: 1.02) }
        let bottom = lons.reversed().map { surface(lat: 2 * .pi / 180, lon: $0, lift: 1.02) }
        return top + bottom
    }()

    static func surface(lat: Double, lon: Double, lift: Double = 1) -> Vector3 {
        Vector3(radii.x * cos(lat) * sin(lon), radii.y * cos(lat) * cos(lon), radii.z * sin(lat)) * lift
    }

    /// Meridians first (the face meridian is index 0), then parallels.
    static let wireframe: [[Vector3]] = meridians + parallels

    private static let meridians: [[Vector3]] = stride(from: 0.0, to: 180, by: 30).map { degrees in
        let lon = degrees * .pi / 180
        return (0...64).map { step in
            let theta = Double(step) / 64 * 2 * .pi
            return Vector3(radii.x * cos(theta) * sin(lon), radii.y * cos(theta) * cos(lon), radii.z * sin(theta))
        }
    }

    private static let parallels: [[Vector3]] = [-50.0, -25, 0, 25, 50].map { degrees in
        let lat = degrees * .pi / 180
        return (0...48).map { step in
            surface(lat: lat, lon: Double(step) / 48 * 2 * .pi)
        }
    }

    static func circle(radius: Double, z: Double) -> [Vector3] {
        (0..<48).map { step in
            let a = Double(step) / 48 * 2 * .pi
            return Vector3(radius * sin(a), radius * cos(a), z)
        }
    }
}

/// A camera in front of the face, slightly to one side and above, projecting with mild
/// perspective. Screen x is mirrored so the head moves like a reflection.
private struct HeadCamera {
    static let azimuth = 0.3
    static let elevation = 0.18
    static let focalLength = 5.5

    let center: CGPoint
    let unit: CGFloat
    let toCamera: Vector3
    let right: Vector3
    let up: Vector3

    init(size: CGSize) {
        center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        unit = min(size.width, size.height) * 0.34
        let d = Vector3(sin(Self.azimuth) * cos(Self.elevation), cos(Self.azimuth) * cos(Self.elevation), sin(Self.elevation))
        let forward = d * -1
        let cameraRight = forward.cross(.unitZ).normalized
        toCamera = d
        right = cameraRight * -1
        up = cameraRight.cross(forward)
    }

    func depth(_ p: Vector3) -> Double { p.dot(toCamera) }

    func scale(at p: Vector3) -> CGFloat {
        unit * Self.focalLength / (Self.focalLength - depth(p))
    }

    func project(_ p: Vector3) -> CGPoint {
        let k = scale(at: p)
        return CGPoint(x: center.x + p.dot(right) * k, y: center.y - p.dot(up) * k)
    }
}

import SwiftUI

/// The live telemetry screen: the connected headphones, stream health, and every motion
/// channel as it arrives.
struct LiveView: View {
    @Environment(AppModel.self) private var model

    static let batteryRefresh: Duration = .seconds(60)

    var body: some View {
        Page {
            HeadphoneBanner()
            LiveDeviceCard()
            HStack(alignment: .top, spacing: 16) {
                OrientationCard().frame(width: 300)
                GyroscopeCard()
            }
            .fixedSize(horizontal: false, vertical: true)
            HeadShortcutsCard()
            GestureClickCard()
            HStack(alignment: .top, spacing: 16) {
                AccelerometerCard()
                HeadDirectionCard().frame(width: 300)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 16) {
                MicrophoneCard()
                RecordingCard()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: model.device.output?.uid) {
            // Battery levels only update when the Bluetooth list is re-read.
            while !Task.isCancelled {
                model.device.reloadBluetooth()
                do {
                    try await Task.sleep(for: Self.batteryRefresh)
                } catch {
                    return
                }
            }
        }
    }
}

/// The active headphones and the health of their motion stream.
private struct LiveDeviceCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.motion.stats
        let streaming = model.headphoneStatus.isStreaming
        Card {
            HStack(alignment: .center, spacing: 14) {
                SymbolTile(symbol: model.headphoneSymbol, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.headphoneName).font(.title2.weight(.semibold))
                    Text(details).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: model.headphoneStatus, frozen: model.frozenMotion != nil)
            }

            Divider()

            HStack(alignment: .top, spacing: 0) {
                Metric(title: "Sample rate", value: streaming ? String(format: "%.1f", stats.rate) : "—", unit: "Hz")
                Metric(title: "Jitter", value: (streaming ? stats.jitter : nil).map { String(format: "%.1f", $0 * 1000) } ?? "—",
                       unit: "ms")
                Metric(title: "Latency", value: (streaming ? stats.latency : nil).map { String(format: "%.0f", $0 * 1000) } ?? "—",
                       unit: "ms")
                Metric(title: "Dropped", value: streaming ? stats.dropped.formatted() : "—",
                       tint: stats.dropped > 0 && streaming ? .orange : .primary)
                ConnectedMetric(since: streaming ? model.motion.streamStartedAt : nil)
                BatteryMetric(battery: model.device.bluetooth?.battery)
            }

            if let tip = model.device.model?.fitTip, streaming {
                Label(tip, systemImage: "lightbulb")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.device.lookupError {
                Label("Couldn't read the Bluetooth model ID: \(error)", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var details: String {
        let device = model.device
        var parts: [String] = []
        if let headphones = device.model {
            if let fit = headphones.fit { parts.append(fit.rawValue) }
            parts.append(headphones.headTrackingLabel)
        }
        if let override = device.override, override != device.detectedModel {
            parts.append("set by hand")
        }
        if let info = device.bluetooth {
            if let firmware = info.firmware { parts.append("Firmware \(firmware)") }
            if let pid = info.productID { parts.append(String(format: "ID 0x%04X", pid)) }
        }
        return parts.isEmpty ? "Choose headphones from the menu in the sidebar." : parts.joined(separator: " · ")
    }
}

private struct StatusPill: View {
    let status: HeadphoneStatus
    let frozen: Bool

    var body: some View {
        HStack(spacing: 6) {
            if frozen {
                Image(systemName: "pause.fill").font(.caption2).foregroundStyle(.secondary)
                Text("Frozen").font(.callout.weight(.medium))
            } else {
                StatusDot(color: status.color)
                Text(status.title).font(.callout.weight(.medium))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.subtleFill, in: Capsule())
    }
}

private struct OrientationCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pose = model.readoutFrame.pose
        Card("Head Orientation", caption: "Moves like a mirror") {
            Button("Recenter", systemImage: "scope") { model.motion.recenter() }
                .buttonStyle(.borderless)
                .disabled(!model.canRecenter)
                .help("Make the direction you're facing now the forward direction")
        } content: {
            LiveTimeline { frame in
                HeadOrientationView(pose: frame.pose)
            }
            .frame(height: 200)
            HStack(spacing: 0) {
                AngleReadout(title: "Pitch", hint: "nod", radians: pose?.pitch, color: .orange)
                AngleReadout(title: "Roll", hint: "tilt", radians: pose?.roll, color: .purple)
                AngleReadout(title: "Yaw", hint: "turn", radians: pose?.yaw, color: .teal)
            }
        }
        .fillingHeight()
    }
}

/// A live scope with its current values underneath.
private struct ScopeCard: View {
    @Environment(AppModel.self) private var model
    let title: String
    let caption: String
    let channels: [ScopeChannel]
    let unit: String
    let minimumScale: Double
    let minHeight: CGFloat

    var body: some View {
        Card(title, caption: caption) {
            LiveTimeline { frame in
                LiveScope(frame: frame, channels: channels, minimumScale: minimumScale, minHeight: minHeight)
            }
            AxisReadouts(frame: model.readoutFrame, channels: channels, unit: unit)
        }
        .fillingHeight()
    }
}

private struct GyroscopeCard: View {
    var body: some View {
        ScopeCard(title: "Gyroscope", caption: "Rotation rate", channels: ScopeChannel.gyroscope,
                  unit: "°/s", minimumScale: 30, minHeight: 200)
    }
}

private struct AccelerometerCard: View {
    var body: some View {
        ScopeCard(title: "Accelerometer", caption: "Gravity removed", channels: ScopeChannel.accelerometer,
                  unit: "milli-g", minimumScale: 20, minHeight: 150)
    }
}

private struct HeadDirectionCard: View {
    var body: some View {
        Card("Where You're Looking", caption: "Last \(Int(HeadDirectionPlot.trailSeconds)) seconds") {
            LiveTimeline { frame in
                HeadDirectionPlot(frame: frame)
            }
        }
        .fillingHeight()
    }
}

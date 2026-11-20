import SwiftUI

enum Format {
    /// "+12.3", "−4.0", "0.0": a typographic minus, and no "−0".
    static func signed(_ value: Double, decimals: Int) -> String {
        let factor = pow(10, Double(decimals))
        let rounded = (value * factor).rounded() / factor
        let magnitude = String(format: "%.\(decimals)f", abs(rounded))
        if rounded > 0 { return "+" + magnitude }
        if rounded < 0 { return "−" + magnitude }
        return magnitude
    }
}

/// The legend under a scope, with each axis's current value.
struct AxisReadouts: View {
    let frame: LiveFrame
    let channels: [ScopeChannel]
    let unit: String

    var body: some View {
        HStack(spacing: 14) {
            ForEach(channels) { channel in
                HStack(spacing: 5) {
                    Circle().fill(channel.color).frame(width: 6, height: 6)
                    Text(channel.name).foregroundStyle(.secondary)
                    Text(frame.value(channel.read).map { Format.signed($0, decimals: 0) } ?? "—")
                        .monospacedDigit()
                        .frame(minWidth: 38, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
            Text(unit).foregroundStyle(.tertiary)
        }
        .font(.callout)
    }
}

/// A head angle in degrees, with what the movement is.
struct AngleReadout: View {
    let title: String
    let hint: String
    let radians: Double?
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(radians.map { Format.signed(Angles.degrees($0), decimals: 1) + "°" } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(hint).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// How long the current stream has been running.
struct ConnectedMetric: View {
    let since: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Streaming for").font(.caption).foregroundStyle(.secondary)
            Group {
                if let since {
                    Text(since, style: .timer)
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Left, right and case charge, when macOS reports them.
struct BatteryMetric: View {
    let battery: BluetoothDeviceInfo.Battery?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Battery").font(.caption).foregroundStyle(.secondary)
            if let levels, !levels.isEmpty {
                HStack(spacing: 10) {
                    ForEach(levels, id: \.label) { level in
                        HStack(spacing: 3) {
                            Image(systemName: Self.symbol(for: level.percent))
                                .foregroundStyle(level.percent <= 20 ? Color.red : Color.secondary)
                            Text(level.label).foregroundStyle(.secondary)
                            Text("\(level.percent)%").monospacedDigit()
                        }
                    }
                }
                .font(.callout)
                .frame(minHeight: 28)
            } else {
                Text("—").font(.system(size: 22, weight: .semibold, design: .rounded))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var levels: [(label: String, percent: Int)]? {
        guard let battery else { return nil }
        return [("L", battery.left), ("R", battery.right), ("Case", battery.caseLevel), ("", battery.main)]
            .compactMap { label, percent in percent.map { (label, $0) } }
    }

    static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

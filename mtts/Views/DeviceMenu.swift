import SwiftUI

/// The sidebar header: which headphones are active and how they're doing. Opens a menu to
/// switch the Mac's output to other headphones or set the model by hand.
struct DeviceMenu: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let device = model.device
        Menu {
            Section("Sound Output") {
                ForEach(device.outputs) { output in
                    Toggle(isOn: Binding(
                        get: { output.id == device.currentOutputID },
                        set: { if $0 { device.select(output) } })
                    ) {
                        Label(Self.title(for: output), systemImage: Self.symbol(for: output))
                    }
                }
            }
            if !device.pairedHeadphones.isEmpty {
                Section("Paired, Not Connected") {
                    ForEach(device.pairedHeadphones, id: \.self) { info in
                        Text(info.name)
                    }
                    .disabled(true)
                }
            }
            Section {
                ModelOverrideMenu()
                    .disabled(device.output?.isBluetooth != true)
            }
            Section {
                Button("Refresh Devices") { device.refresh() }
                Button("Bluetooth Settings…") { SystemSettings.open(SystemSettings.bluetooth) }
                Button("Sound Settings…") { SystemSettings.open(SystemSettings.sound) }
            }
        } label: {
            label
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
        .help("Choose which headphones mtts listens to")
    }

    private var label: some View {
        let status = model.headphoneStatus
        return HStack(spacing: 10) {
            SymbolTile(symbol: model.headphoneSymbol)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.headphoneName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusDot(color: status.color)
                    Text(status == .noHeadphones ? (model.device.output.map { "Playing on \($0.name)" } ?? "Not connected") : status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(hovering ? 0.08 : 0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    static func title(for output: HeadphoneDeviceMonitor.Output) -> String {
        let name = output.device.name
        guard let identified = output.identification?.model else { return name }
        let modelName = identified.family == .other || name.localizedCaseInsensitiveContains(identified.name)
            ? nil : identified.name
        let parts = [modelName, identified.headTracking == .unsupported ? "no head tracking" : nil].compactMap { $0 }
        return parts.isEmpty ? name : "\(name) — \(parts.joined(separator: ", "))"
    }

    static func symbol(for output: HeadphoneDeviceMonitor.Output) -> String {
        output.identification?.model.symbol ?? (output.device.isBluetooth ? "headphones" : "hifispeaker")
    }
}

/// "Treat As" submenu: pin the model when automatic detection can't recognize it.
private struct ModelOverrideMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let device = model.device
        Menu("Treat As") {
            Picker("Treat As", selection: Binding(
                get: { device.override?.id },
                set: { id in device.setOverride(id.flatMap(HeadphoneModel.model(id:))) })
            ) {
                Text(automaticTitle).tag(String?.none)
                ForEach([HeadphoneModel.Family.beats, .airPods], id: \.self) { family in
                    Section(family.rawValue) {
                        ForEach(HeadphoneModel.headTrackingModels.filter { $0.family == family }) { option in
                            Text(option.name).tag(Optional(option.id))
                        }
                    }
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var automaticTitle: String {
        guard let detected = model.device.detectedModel, detected.family != .other else { return "Automatic" }
        return "Automatic (\(detected.name))"
    }
}

/// Explains why motion isn't streaming and offers the one action that fixes it.
struct HeadphoneBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.headphoneStatus {
        case .streaming:
            EmptyView()
        case .noHeadphones:
            Banner(symbol: "headphones", title: "Connect your headphones",
                   message: "Put in your Powerbeats Pro 2 and make them the Mac's sound output. Motion comes from whichever headphones the Mac is playing through.",
                   tint: .accentColor) { switchOrSettings }
        case .waiting:
            Banner(symbol: "hourglass", title: "Waiting for motion", message: waitingMessage, tint: .orange) {
                switchOrSettings
            }
        case .unsupported(let name):
            Banner(symbol: "exclamationmark.triangle", title: "\(name) has no head tracking",
                   message: "macOS only shares motion from headphones with spatial-audio head tracking, such as Powerbeats Pro 2, Beats Fit Pro, AirPods Pro, AirPods 4 and AirPods Max.",
                   tint: .red) { switchOrSettings }
        case .denied:
            Banner(symbol: "hand.raised", title: "Motion access is off",
                   message: "Allow mtts under Privacy & Security › Motion & Fitness, then reopen the app.",
                   tint: .red) {
                Button("Open Settings") { SystemSettings.open(SystemSettings.motionPrivacy) }
            }
        case .unavailable(let message):
            Banner(symbol: "exclamationmark.triangle", title: "Motion unavailable", message: message, tint: .red) {
                EmptyView()
            }
        }
    }

    private var waitingMessage: String {
        let name = model.device.model?.name ?? "your headphones"
        if model.device.model?.headTracking == .unknown {
            return "If nothing streams with \(name) in, the model may lack head tracking. If it was misidentified, set it under Treat As in the device menu."
        }
        return "Wear both earbuds. Motion starts once \(name) are in your ears and playing to this Mac."
    }

    @ViewBuilder
    private var switchOrSettings: some View {
        if let suggestion = model.switchSuggestion {
            Button("Use \(suggestion.identification?.model.name ?? suggestion.device.name)") {
                model.device.select(suggestion)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Bluetooth Settings…") { SystemSettings.open(SystemSettings.bluetooth) }
        }
    }
}

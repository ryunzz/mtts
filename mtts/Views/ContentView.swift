import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            Group {
                switch model.screen {
                case .live: LiveView()
                case .train: TrainView()
                case .decode: DecodeView()
                }
            }
            .navigationTitle(model.screen.rawValue)
            .navigationSubtitle(subtitle)
            .toolbar {
                if model.screen == .live {
                    ToolbarItem(placement: .primaryAction) {
                        FreezeToolbarButton()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    RecordToolbarButton()
                }
            }
        }
    }

    private var subtitle: String {
        switch model.screen {
        case .live:
            model.headphoneName
        case .train:
            "\(model.activeTemplates.count) takes · \(model.dataset.vocabulary.count) words"
        case .decode:
            model.decodeMode.rawValue
        }
    }
}

private struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(selection: screenSelection) {
            Section("Workspace") {
                ForEach(AppModel.Screen.allCases) { screen in
                    Label(screen.rawValue, systemImage: screen.symbol)
                        .badge(screen == .train ? model.activeTemplates.count : 0)
                        .tag(screen)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            DeviceMenu()
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 8)
        }
    }

    private var screenSelection: Binding<AppModel.Screen?> {
        Binding(get: { model.screen }, set: { if let screen = $0 { model.screen = screen } })
    }
}

private struct RecordToolbarButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recorder = model.recorder
        Button {
            recorder.isRecording ? recorder.stop() : recorder.start(audio: model.audio)
        } label: {
            if recorder.isRecording, let startedAt = recorder.startedAt {
                Label {
                    Text(startedAt, style: .timer).monospacedDigit()
                } icon: {
                    Image(systemName: "stop.circle.fill").foregroundStyle(.red)
                }
                .labelStyle(.titleAndIcon)
            } else {
                Label("Record Session", systemImage: "record.circle")
            }
        }
        .help(recorder.isRecording
              ? "Stop recording"
              : "Record synchronized motion, audio and marks to ~/Documents/mtts/Sessions")
    }
}

/// Holds the live plots still so a moment can be inspected.
private struct FreezeToolbarButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let frozen = model.frozenMotion != nil
        Button {
            model.toggleFreeze()
        } label: {
            Label(frozen ? "Resume" : "Freeze", systemImage: frozen ? "play.fill" : "pause.fill")
        }
        .disabled(!model.canFreeze)
        .help(frozen ? "Resume the live plots" : "Freeze the live plots to look at a moment")
    }
}

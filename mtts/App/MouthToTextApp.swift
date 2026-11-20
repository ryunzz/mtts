import SwiftUI

@main
struct MouthToTextApp: App {
    @State private var model: AppModel

    init() {
        // Before the model loads, so it finds takes recorded under the app's old name.
        LegacyData.migrate()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup(AppInfo.name) {
            ContentView()
                .environment(model)
                .frame(minWidth: 1020, minHeight: 700)
                .task { model.start() }
        }
        .defaultSize(width: 1200, height: 820)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
    }
}

import SwiftUI

@main
struct NebulaForgeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1440, height: 900)
    }
}

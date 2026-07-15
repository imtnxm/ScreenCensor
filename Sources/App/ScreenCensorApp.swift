import SwiftUI

@main
struct ScreenCensorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("ScreenCensor", systemImage: "eye.slash.circle.fill") {
            MenuBarView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)
    }
}

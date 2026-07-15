import AppKit
import SwiftUI

@main
struct ScreenCensorApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            if let image = NSImage(named: "MenuBarIcon") {
                Image(nsImage: image)
            } else {
                Image(systemName: "eye.slash.circle.fill")
            }
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI

@main
struct CameraTunerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Camera Tuner") {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Cameras") {
                    model.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Reload Camera Controls") {
                    model.reloadHardware()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }
    }
}

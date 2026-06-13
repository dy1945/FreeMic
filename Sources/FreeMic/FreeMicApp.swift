import SwiftUI
import Foundation

@main
struct FreeMicApp: App {
    @StateObject private var audio: AudioManager

    init() {
        let manager = AudioManager()
        // Headless debug path: print device state and exit without showing UI.
        if CommandLine.arguments.contains("--list") {
            manager.printDebug()
            exit(0)
        }
        _audio = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(audio: audio)
        } label: {
            Image(systemName: "headphones")
        }
        .menuBarExtraStyle(.window)
    }
}

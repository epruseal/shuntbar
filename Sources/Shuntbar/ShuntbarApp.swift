import AppKit
import SwiftUI

@main
struct ShuntbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PoolStore()

    var body: some Scene {
        MenuBarExtra {
            PoolView(store: store)
        } label: {
            MenuBarIcon(store: store)
        }
        .menuBarExtraStyle(.window)

        // Standalone, stay-open copy of the popover for people who want the
        // pool visible all the time. It keeps updating on the polling cycle.
        Window("Shunt Pool", id: "pool") {
            PoolView(store: store, showsWindowButton: false)
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // LSUIElement covers the bundled app; this also hides the Dock icon when
    // launched bare via `swift run`.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarIcon: View {
    let store: PoolStore

    var body: some View {
        Image(systemName: store.hasProblem ? "exclamationmark.triangle" : "speedometer")
    }
}

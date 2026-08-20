import AppKit
import SwiftUI

struct SettingsView: View {
    let store: PoolStore
    @AppStorage(PoolStore.hostKey) private var host = ""
    @AppStorage(PoolStore.intervalKey) private var interval = 60.0
    @State private var token = ""
    @State private var tokenLoaded = false

    var body: some View {
        Form {
            TextField(
                "Server",
                text: $host,
                prompt: Text(verbatim: "http://localhost:3001")
            )
            .autocorrectionDisabled()
            SecureField(
                "Admin token",
                text: $token,
                prompt: Text("x-shunt-admin-token value")
            )
            Text("The token is stored in the macOS Keychain, not in preferences.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Refresh every", selection: $interval) {
                Text("10 seconds").tag(10.0)
                Text("30 seconds").tag(30.0)
                Text("1 minute").tag(60.0)
                Text("5 minutes").tag(300.0)
            }
            HStack {
                Spacer()
                Button("Apply") { apply() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            // Accessory apps open the Settings window behind other apps
            // unless activated explicitly.
            NSApp.activate(ignoringOtherApps: true)
            if !tokenLoaded {
                token = Keychain.loadToken() ?? ""
                tokenLoaded = true
            }
        }
    }

    private func apply() {
        Keychain.saveToken(token)
        store.refreshNow()
    }
}

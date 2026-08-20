import AppKit
import SwiftUI

struct PoolView: View {
    let store: PoolStore
    /// Hidden when this view already lives in the standalone window.
    var showsWindowButton = true
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            switch store.state {
            case .unconfigured:
                unconfigured
            case .failed(let message):
                failed(message)
            case .loaded(let pool):
                providers(pool)
            }
        }
        .padding(12)
        .frame(width: 400)
        .onAppear { store.refreshNow() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Shunt Pool").font(.headline)
            Spacer()
            if let updated = store.lastUpdated {
                Text(updated, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                store.refreshNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isRefreshing)
            .help("Refresh now")
            if showsWindowButton {
                Button {
                    openWindow(id: "pool")
                    NSApp.activate(ignoringOtherApps: true)
                    closePopover()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("Open as a window")
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Shuntbar")
        }
        // The standalone window hands initial key focus to the first
        // control, which paints a focus ring on these icon-only buttons.
        .focusEffectDisabled()
    }

    private var unconfigured: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set the shunt server URL and admin token to get started.")
                .foregroundStyle(.secondary)
            SettingsLink {
                Text("Open Settings")
            }
        }
        .padding(.vertical, 4)
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
            Button("Retry") { store.refreshNow() }
        }
        .padding(.vertical, 4)
    }

    private func providers(_ pool: PoolResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pool.providers, id: \.provider) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(provider.provider)
                            .font(.subheadline.weight(.semibold))
                        if let auth = provider.auth {
                            Text(auth)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(sorted(provider.accounts), id: \.name) { account in
                        AccountRow(account: account)
                    }
                }
            }
        }
    }

    private func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted {
            ($0.priority, $0.name) < ($1.priority, $1.name)
        }
    }

    private func closePopover() {
        dismiss()
        // Fallback for macOS versions where dismiss() is a no-op inside
        // MenuBarExtra content: close the status-bar panel directly.
        for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
            window.close()
        }
    }
}

struct AccountRow: View {
    let account: Account

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(account.name)
                    .font(.callout.weight(.medium))
                if let plan = account.plan {
                    Text(titleCased(plan))
                        .font(.caption2)
                        .padding(.vertical, 1)
                        .padding(.horizontal, 5)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(.secondary)
                }
                Text("P\(account.priority)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let headroom = account.headroomSecs {
                    Text("headroom \(signedHours(headroom))")
                        .font(.caption)
                        .foregroundStyle(headroom < 0 ? .orange : .secondary)
                }
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                windowRow("5h", account.utilization5h, account.reset5h)
                windowRow("7d", account.utilization7d, account.reset7d)
                windowRow("7d Fable", account.utilization7dOi, account.reset7dOi)
            }
            .padding(.leading, 14)
        }
    }

    @ViewBuilder
    private func windowRow(_ label: String, _ utilization: Double?, _ reset: Int?) -> some View {
        if let utilization {
            GridRow {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: min(max(utilization, 0), 1))
                    .tint(barColor(utilization))
                    .frame(width: 110)
                Text(utilization, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .gridColumnAlignment(.trailing)
                Text(resetText(reset))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Color plus an always-present text label, so state never relies on
    // color alone.
    private var statusParts: (text: String, color: Color) {
        if account.disabled { return ("disabled", .gray) }
        var labels: [String] = []
        var color: Color = .orange
        if account.status == "rejected" {
            labels.append("rejected")
            color = .red
        }
        if let cooldown = account.cooldownSecsRemaining, cooldown > 0 {
            labels.append("cooldown \(shortDuration(cooldown))")
        }
        if let fable = account.cooldownFableSecsRemaining, fable > 0 {
            labels.append("fable cooldown \(shortDuration(fable))")
        }
        if account.nearQuota {
            labels.append("near quota")
        }
        if labels.isEmpty {
            if account.available { return ("available", .green) }
            if !account.hasState { return ("unused", .gray) }
            return ("unavailable", .orange)
        }
        return (labels.joined(separator: " / "), color)
    }

    private var statusText: String { statusParts.text }
    private var statusColor: Color { statusParts.color }

    private func barColor(_ utilization: Double) -> Color {
        if utilization >= 1.0 { return .red }
        if utilization >= 0.8 { return .orange }
        return .accentColor
    }

    private func resetText(_ ts: Int?) -> String {
        guard let ts else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ts))
        let remaining = date.timeIntervalSinceNow
        if remaining <= 0 { return "resetting" }
        let absolute: String
        if remaining < 86400 {
            absolute = date.formatted(date: .omitted, time: .shortened)
        } else {
            absolute = date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return "\(absolute) (\(shortDuration(Int(remaining))))"
    }

    private func shortDuration(_ seconds: Int) -> String {
        if seconds < 3600 { return "\(max(seconds, 60) / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h \(seconds % 3600 / 60)m" }
        return "\(seconds / 86400)d \(seconds % 86400 / 3600)h"
    }

    private func signedHours(_ seconds: Int) -> String {
        String(format: "%+.1fh", Double(seconds) / 3600)
    }

    private func titleCased(_ text: String) -> String {
        text.split(separator: " ").map { word in
            guard let first = word.first else { return String(word) }
            return String(first).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }
}

import Foundation
import Observation

@MainActor
@Observable
final class PoolStore {
    enum State: Equatable {
        case unconfigured
        case loaded(PoolResponse)
        case failed(String)
    }

    static let hostKey = "host"
    static let intervalKey = "refreshInterval"

    private(set) var state: State = .unconfigured
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private var loopTask: Task<Void, Never>?
    /// Set when refresh() is called while a fetch is in flight, so the
    /// request is honored right after instead of being dropped (the settings
    /// may have changed mid-fetch).
    private var rerunRequested = false

    /// Drives the menu bar warning icon: fetch failed, not configured yet, or
    /// some provider has no available account left.
    var hasProblem: Bool {
        switch state {
        case .unconfigured, .failed:
            return true
        case .loaded(let pool):
            return pool.providers.contains { provider in
                !provider.accounts.isEmpty && provider.accounts.allSatisfy { !$0.available }
            }
        }
    }

    init() {
        startAutoRefresh()
    }

    /// The store lives for the whole app lifetime, so the loop task holding
    /// `self` strongly is intentional.
    func startAutoRefresh() {
        loopTask?.cancel()
        loopTask = Task {
            while !Task.isCancelled {
                await refresh()
                // Interval is re-read every cycle so a settings change takes
                // effect after at most one stale sleep.
                let stored = UserDefaults.standard.double(forKey: Self.intervalKey)
                let interval = stored > 0 ? max(10, stored) : 60
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func refreshNow() {
        Task { await refresh() }
    }

    func refresh() async {
        if isRefreshing {
            rerunRequested = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            rerunRequested = false
            await fetchOnce()
        } while rerunRequested
    }

    private func fetchOnce() async {
        let host = (UserDefaults.standard.string(forKey: Self.hostKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = Keychain.loadToken() ?? ""
        guard !host.isEmpty, !token.isEmpty else {
            state = .unconfigured
            return
        }
        do {
            let pool = try await PoolClient.fetch(host: host, token: token)
            state = .loaded(pool)
            lastUpdated = Date()
        } catch {
            let message = (error as? ShuntError)?.errorDescription ?? error.localizedDescription
            state = .failed(message)
        }
    }
}

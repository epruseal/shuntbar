import Foundation

// Wire types mirror shunt's `GET /admin/pool` response (src/accounts.rs
// AccountSnapshot). Explicit CodingKeys because keys like `utilization_5h`
// and `utilization_7d_oi` do not round-trip through convertFromSnakeCase.

struct PoolResponse: Decodable, Equatable {
    let providers: [ProviderPool]
}

struct ProviderPool: Decodable, Equatable {
    let provider: String
    let auth: String?
    let accounts: [Account]
}

struct Account: Decodable, Equatable {
    let name: String
    let priority: Int
    let disabled: Bool
    let available: Bool
    let nearQuota: Bool
    let hasState: Bool
    let status: String?
    let cooldownSecsRemaining: Int?
    let cooldownFableSecsRemaining: Int?
    /// Burn-rate headroom in seconds; negative means the account is projected
    /// to run out before its tightest reset. Only present when the server has
    /// `[server.pool]` configured.
    let headroomSecs: Int?
    let utilization5h: Double?
    let reset5h: Int?
    let utilization7d: Double?
    let reset7d: Int?
    /// The `7d_oi` window is the Fable-scoped weekly limit.
    let utilization7dOi: Double?
    let reset7dOi: Int?

    enum CodingKeys: String, CodingKey {
        case name, priority, disabled, available, status
        case nearQuota = "near_quota"
        case hasState = "has_state"
        case cooldownSecsRemaining = "cooldown_secs_remaining"
        case cooldownFableSecsRemaining = "cooldown_fable_secs_remaining"
        case headroomSecs = "headroom_secs"
        case utilization5h = "utilization_5h"
        case reset5h = "reset_5h"
        case utilization7d = "utilization_7d"
        case reset7d = "reset_7d"
        case utilization7dOi = "utilization_7d_oi"
        case reset7dOi = "reset_7d_oi"
    }
}

enum ShuntError: LocalizedError, Equatable {
    case invalidURL
    case tokenRejected
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL. Use http(s)://host:port."
        case .tokenRejected: return "Admin token rejected (HTTP 401/403)."
        case .server(let code): return "Server error (HTTP \(code))."
        case .decoding: return "Unexpected response format."
        }
    }
}

enum PoolClient {
    static func poolURL(host: String) -> URL? {
        var base = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/admin/pool"),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else { return nil }
        return url
    }

    static func fetch(host: String, token: String) async throws -> PoolResponse {
        guard let url = poolURL(host: host) else { throw ShuntError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "x-shunt-admin-token")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShuntError.server(-1) }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw ShuntError.tokenRejected
        default: throw ShuntError.server(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(PoolResponse.self, from: data)
        } catch {
            throw ShuntError.decoding
        }
    }
}

import XCTest
@testable import Shuntbar

final class PoolClientTests: XCTestCase {
    // Anonymized copy of a real /admin/api/pool response: one account with every
    // field populated, one with the null-heavy shape codex accounts produce.
    private let fixture = """
    {
        "providers": [
            {
                "provider": "anthropic",
                "auth": "claude_oauth",
                "accounts": [
                    {
                        "available": false,
                        "cooldown_fable_secs_remaining": null,
                        "cooldown_secs_remaining": 2151,
                        "disabled": false,
                        "has_state": true,
                        "headroom_secs": null,
                        "name": "alice-claude",
                        "near_quota": true,
                        "plan": "max",
                        "priority": 100,
                        "reset_5h": 1787211600,
                        "reset_7d": 1787511600,
                        "reset_7d_oi": 1787511600,
                        "status": "rejected",
                        "utilization_5h": 0.05,
                        "utilization_7d": 1.0,
                        "utilization_7d_oi": 0.76
                    },
                    {
                        "available": true,
                        "cooldown_fable_secs_remaining": null,
                        "cooldown_secs_remaining": null,
                        "disabled": false,
                        "has_state": true,
                        "headroom_secs": -13922,
                        "name": "bob-claude",
                        "near_quota": false,
                        "priority": 100,
                        "reset_5h": 1787210400,
                        "reset_7d": 1787378400,
                        "reset_7d_oi": 1787378400,
                        "status": "allowed",
                        "utilization_5h": 0.9,
                        "utilization_7d": 0.09,
                        "utilization_7d_oi": 0.08
                    }
                ]
            },
            {
                "provider": "codex",
                "auth": "chatgpt_oauth",
                "accounts": [
                    {
                        "available": false,
                        "cooldown_fable_secs_remaining": null,
                        "cooldown_secs_remaining": null,
                        "disabled": false,
                        "has_state": true,
                        "headroom_secs": null,
                        "name": "alice-codex",
                        "near_quota": true,
                        "priority": 50,
                        "reset_5h": null,
                        "reset_7d": 1787422521,
                        "reset_7d_oi": null,
                        "status": null,
                        "utilization_5h": null,
                        "utilization_7d": 1.0,
                        "utilization_7d_oi": null
                    }
                ]
            }
        ]
    }
    """

    func testDecodesFullAndNullHeavyAccounts() throws {
        let pool = try JSONDecoder().decode(PoolResponse.self, from: Data(fixture.utf8))
        XCTAssertEqual(pool.providers.count, 2)

        let anthropic = pool.providers[0]
        XCTAssertEqual(anthropic.provider, "anthropic")
        XCTAssertEqual(anthropic.auth, "claude_oauth")
        XCTAssertEqual(anthropic.accounts.count, 2)

        let alice = anthropic.accounts[0]
        XCTAssertEqual(alice.name, "alice-claude")
        XCTAssertEqual(alice.priority, 100)
        XCTAssertFalse(alice.available)
        XCTAssertTrue(alice.nearQuota)
        XCTAssertTrue(alice.hasState)
        XCTAssertEqual(alice.status, "rejected")
        XCTAssertEqual(alice.cooldownSecsRemaining, 2151)
        XCTAssertNil(alice.cooldownFableSecsRemaining)
        XCTAssertNil(alice.headroomSecs)
        XCTAssertEqual(alice.utilization5h, 0.05)
        XCTAssertEqual(alice.reset5h, 1_787_211_600)
        XCTAssertEqual(alice.utilization7d, 1.0)
        XCTAssertEqual(alice.utilization7dOi, 0.76)
        XCTAssertEqual(alice.plan, "max")

        let bob = anthropic.accounts[1]
        XCTAssertEqual(bob.headroomSecs, -13922)
        XCTAssertTrue(bob.available)
        XCTAssertNil(bob.plan)

        let codex = pool.providers[1].accounts[0]
        XCTAssertEqual(codex.priority, 50)
        XCTAssertNil(codex.status)
        XCTAssertNil(codex.utilization5h)
        XCTAssertNil(codex.reset5h)
        XCTAssertNil(codex.utilization7dOi)
        XCTAssertEqual(codex.utilization7d, 1.0)
        XCTAssertEqual(codex.reset7d, 1_787_422_521)
    }

    func testMissingOptionalKeysDecode() throws {
        // serde skips None fields entirely, so absent keys must decode too.
        let minimal = """
        {"providers":[{"provider":"anthropic","auth":"claude_oauth","accounts":[
            {"name":"fresh","priority":100,"disabled":false,"available":true,
             "near_quota":false,"has_state":false}
        ]}]}
        """
        let pool = try JSONDecoder().decode(PoolResponse.self, from: Data(minimal.utf8))
        let account = pool.providers[0].accounts[0]
        XCTAssertEqual(account.name, "fresh")
        XCTAssertNil(account.utilization5h)
        XCTAssertNil(account.cooldownSecsRemaining)
        XCTAssertNil(account.status)
        XCTAssertNil(account.plan)
    }

    func testPoolURLValidation() {
        XCTAssertEqual(
            PoolClient.poolURL(host: "http://localhost:3001")?.absoluteString,
            "http://localhost:3001/admin/api/pool"
        )
        XCTAssertEqual(
            PoolClient.poolURL(host: " https://example.com:3001/ ")?.absoluteString,
            "https://example.com:3001/admin/api/pool"
        )
        XCTAssertNil(PoolClient.poolURL(host: "ftp://example.com"))
        XCTAssertNil(PoolClient.poolURL(host: "localhost:3001"))
        XCTAssertNil(PoolClient.poolURL(host: ""))
    }

    // The legacy path stays reachable so the app still works against a shunt
    // that predates the routed admin shell.
    func testLegacyPoolURLKeepsTheOldPath() {
        XCTAssertEqual(
            PoolClient.poolURL(host: "http://localhost:3001", path: PoolClient.legacyPoolPath)?
                .absoluteString,
            "http://localhost:3001/admin/pool"
        )
    }

    // Live integration check, opt-in via environment so no personal endpoint
    // ships in the repo: SHUNTBAR_TEST_HOST / SHUNTBAR_TEST_TOKEN.
    func testLiveFetchIfConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["SHUNTBAR_TEST_HOST"], let token = env["SHUNTBAR_TEST_TOKEN"] else {
            throw XCTSkip("SHUNTBAR_TEST_HOST / SHUNTBAR_TEST_TOKEN not set")
        }
        let pool = try await PoolClient.fetch(host: host, token: token)
        XCTAssertFalse(pool.providers.isEmpty)
        XCTAssertFalse(pool.providers.flatMap(\.accounts).isEmpty)
    }
}

# Shuntbar

A macOS menu bar app that shows account-pool usage of a
[shunt](https://github.com/pleaseai/shunt) server at a glance.

Shuntbar polls `GET /admin/pool` and shows, per provider and per account:

- utilization bars for the 5h, 7d, and 7d Fable-scoped quota windows
- reset times (absolute and remaining)
- selection priority, availability, cooldowns, near-quota state
- burn-rate headroom when the server has `[server.pool]` configured

The menu bar shows only an icon; it switches to a warning triangle when the
fetch fails, the app is not configured yet, or any provider has no available
account left.

## Requirements

- macOS 14 or later
- Xcode command line tools (Swift 5.9+) to build

No third-party dependencies; the app uses only system frameworks.

## Build and install

Download the zip from the [Releases](../../releases) page, unzip, and move
`Shuntbar.app` to `/Applications`. The bundle is ad-hoc signed (no
Developer ID), so macOS quarantines the download; clear it once before
the first launch:

```sh
xattr -d com.apple.quarantine /Applications/Shuntbar.app
```

Or build from source, which needs no quarantine step:

```sh
make app
cp -R Shuntbar.app /Applications/
open /Applications/Shuntbar.app
```

`make test` runs the unit tests. `make run` builds and launches the bundle
from the working directory.

## Configure

Click the menu bar icon, open Settings (gear button), then set:

- **Server**: your shunt base URL, e.g. `http://localhost:3001`
- **Admin token**: the value shunt expects in the `x-shunt-admin-token`
  header. It is stored in the macOS Keychain, never in preferences.
- **Refresh every**: polling interval (10s to 5min, default 1min)

Press **Apply** to save the token and refresh immediately.

## Start at login

Enable the "Start at login" checkbox in the app's Settings. It uses
SMAppService, so the same entry also shows up (and can be managed)
under System Settings → General → Login Items. The checkbox only works
when the app runs from a real .app bundle.

## Notes

- The bundle is ad-hoc signed. After rebuilding, macOS may ask again for
  permission to read the Keychain item; choose "Always Allow" to silence it.
- `Info.plist` sets `NSAllowsArbitraryLoads` because self-hosted shunt
  servers are commonly plain http on a LAN, which App Transport Security
  would otherwise block. Use https if your server has it.
- On macOS 15+ the first connection to a LAN host triggers the Local
  Network permission prompt; accept it so the app can reach your server.

## License

MIT

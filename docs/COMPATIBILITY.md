# Compatibility

The app targets the standard **Pterodactyl 1.x Client API** at `/api/client` and Wings WebSockets. A compatible provider must expose those endpoints and permit Client API keys.

| Area | Requirement or limit |
| --- | --- |
| Connection | HTTPS with a trusted certificate. No insecure TLS bypass. Panel subdirectory paths are preserved. |
| Console | Reachable `wss://` Wings endpoint and `websocket.connect`. Commands also require `control.console`. |
| Files | Appropriate file grants; uploads/downloads use panel-issued signed URLs without forwarding the panel API key. |
| Backup | Creation, restore and download depend on permissions and the provider's storage implementation. Some providers offer restore only. |
| Schedule | Standard cron/task endpoints. Confirm the panel's time zone; it is not supplied by the standard Client API. |
| Minecraft | Java server commands and readable JAR/configuration files. Player/TPS output parsing can be affected by language, plugins or suppressed logs. |
| Other games | General console, power, file, backup and management features. No game-specific player API is assumed. |
| Widgets | Matching App Groups/keychain entitlement in app and extension. Manual snapshot fallback is available. iOS schedules refresh. |
| Live Activities | Foreground resource updates; background values are timestamped and become stale. No push relay is included. |

No AMP, provider-specific endpoints or Admin Suite integration is included. The app has no marketplace authentication, provider billing functions or runtime catalog API keys.

Pterodactyl 2.x and heavily modified forks are not claimed as verified. Actual host access, signing services, large transfers and game/plugin combinations need device testing. CI validates simulated workflows and isolated behavior; it does not authenticate against your servers.

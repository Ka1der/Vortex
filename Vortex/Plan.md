# PROJECT SPECIFICATION: Vortex VPN Client (iOS, iPadOS, macOS)

## 1. Project Overview & Core Objectives
Build a minimalist, high-performance multiplatform VPN client for iOS 17+, iPadOS 17+, and macOS 14+ using **SwiftUI** and **Apple NetworkExtension (`NEPacketTunnelProvider`)**.
The UI/UX must closely follow the compact, utility-first dark design of **Shadowrocket**: single-screen control for connection toggle, routing mode selector, connectivity test, local servers, and remote subscriptions.

### Supported Protocols (Outbounds)
1. **VLESS** — Full production support: `XTLS-RPRX-Vision`, Reality, TLS, TCP/UDP, gRPC, WebSocket.
2. **Proprietary Protocol (`vortex_proto`)** — Modular outbound interface/stub awaiting final backend specification.
3. **VK Call Tunnel (`vk_call_tunnel`)** — Transport/Outbound layer tunneling packets via VK Calls TURN/WebRTC relay; modular stub awaiting backend specification.

### Routing Engine (Proxy / Domain / Global / Block)
Strictly rule-based domain and IP routing (No Per-App VPN):
- **Global Routing Modes:**
  - `CONFIG` (Rule-based): Routes traffic according to active domain/IP/Geo rules.
  - `PROXY` (Global): All traffic is routed through the selected active VPN node.
  - `DIRECT`: All traffic bypasses the tunnel directly to the physical interface.
  - `BLOCK` (Strict/Kill-switch or Rule Reject): Drops matching traffic.
- **Rule Actions:**
  - `PROXY` — Route via active VPN outbound.
  - `DIRECT` — Route directly via physical interface (`en0` / `pdp_ip0`).
  - `BLOCK` — Drop connection (Ads, trackers, telemetry, or undesired protocols).
- **Rule Matching Types:**
  - `DOMAIN` (Exact match)
  - `DOMAIN-SUFFIX` (e.g., `ru`, `google.com`)
  - `DOMAIN-KEYWORD` (e.g., `instagram`)
  - `IP-CIDR` (e.g., `192.168.0.0/16`, `91.108.4.0/22`)
  - `GEOIP` & `GEOSITE` (Lightweight `.srs` binary rule-sets, e.g., `ru`, `private`, `category-ads-all`)

---

## 2. System Architecture & Tech Stack
- **UI & Host App:** Swift 6, SwiftUI, Observation framework (`@Observable`), UserDefaults / JSON storage in shared container.
- **System Tunnel:** `NEPacketTunnelProvider` (NetworkExtension framework).
- **Core Networking Engine:** Custom wrapper around **sing-box (`libbox`)** in Go, compiled into `VortexCore.xcframework` via `gomobile` / `libbox`.
- **IPC (Host App <-> Tunnel Extension):**
  - Shared container via **App Groups** (`group.com.vortex.vpn`).
  - Real-time status, latency tests, and traffic counters via `NETunnelProviderSession.sendProviderMessage`.
- **Strict Hardware Constraint:** The `VortexTunnelExtension` target on iOS/iPadOS MUST stay under **40 MB RAM** (Hard iOS Jetsam limit is 50 MB).

---

## 3. Repository & Directory Structure

- `VortexVPN/`
  - `CoreGo/` — Go wrapper around sing-box + custom protocol adapters
    - `go.mod`
    - `bridge/bridge.go` — Exported interfaces for Swift (`StartTunnel`, `StopTunnel`, `GetStats`, `URLTest`)
    - `outbound/proprietary/proprietary.go` — Stub for Proprietary Protocol Outbound
    - `outbound/vkcall/vkcall.go` — Stub for VK Call TURN/WebRTC Transport
    - `scripts/build_xcframework.sh` — Builds `VortexCore.xcframework` (iOS, iOS Simulator, macOS)
  - `Shared/` — Shared Swift package/target (compiled into both Host App and Extension)
    - `Config/AppGroup.swift` — Shared container URLs & `UserDefaults(suiteName:)`
    - `Config/ConfigBuilder.swift` — Generates `sing-box` JSON configuration from Swift models
    - `Config/SubscriptionParser.swift` — Parses `vless://`, `vortex://`, `vkcall://`, and Base64 subscriptions
    - `Models/ServerNode.swift` — Unified node model (VLESS, Proprietary, VK Call)
    - `Models/SubscriptionGroup.swift` — Remote subscription metadata (upload, download, total, expire)
    - `Models/RoutingRule.swift` — Routing modes (`Proxy`, `Direct`, `Block`) and domain/IP rules
    - `VPNController/TunnelManager.swift` — Wrapper around `NETunnelProviderManager`
  - `VortexApp/` — Main SwiftUI Target (iOS, iPadOS, macOS)
    - `VortexApp.swift`
    - `Views/MainTabView.swift` — Bottom tab bar (`Главная`, `Настройка`, `Данные`, `Настройки`)
    - `Views/HomeView.swift` — Shadowrocket-style dashboard (Active switch, Routing row, Ping test, Local & Sub lists)
    - `Views/RoutingView.swift` — Global mode selector + Domain/IP rule list editor (`PROXY`, `DIRECT`, `BLOCK`)
    - `Views/DataStatsView.swift` — Live traffic stats, connection log, and extension RAM monitor
    - `Views/SettingsView.swift` — DNS, MTU (`1280` default), On-Demand rules
    - `Views/NodeEditorView.swift` — Manual configuration sheet for VLESS / Proprietary / VK Call
  - `VortexTunnelExtension/` — `NEPacketTunnelProvider` Target
    - `PacketTunnelProvider.swift` — Tunnel lifecycle, `utun` file descriptor handoff to `VortexCore`
    - `VortexTunnelExtension.entitlements`

---

## 4. Step-by-Step Implementation Plan

### Phase 1: Project Scaffolding & Shared Data Models (`Shared/Models`)
1. Set up the multiplatform workspace (`VortexApp`, `VortexTunnelExtension`, `Shared`).
2. Implement `AppGroup.swift` using `group.com.vortex.vpn` with helpers for `config.json` path and shared `UserDefaults`.
3. Create `ServerNode` (`Identifiable`, `Codable`, `Hashable`) with `ProtocolType`:
   - `vless`: `uuid`, `address`, `port`, `flow` (`xtls-rprx-vision`), `security` (`reality` / `tls` / `none`), `sni`, `publicKey` (`pbk`), `shortId` (`sid`), `fingerprint` (`fp`), `network` (`tcp` / `udp` / `grpc` / `ws`).
   - `proprietary`: `address`, `port`, `secretKey`, `obfuscationMode`, `extraParams: [String: String]`.
   - `vkCall`: `callJoinLink`, `relayAddress`, `relayPort`, `turnCredentials`, `secretKey`.
4. Create `SubscriptionGroup` (`Identifiable`, `Codable`):
   - Fields: `id`, `title`, `url`, `uploadBytes`, `downloadBytes`, `totalBytes`, `expireTimestamp`, `lastUpdated`, `nodes: [ServerNode]`.
5. Create `RoutingRule` & `RoutingMode`:
   - `GlobalRoutingMode`: `.config` (Rule-based), `.proxy` (Global), `.direct`, `.block`.
   - `RuleType`: `.domain`, `.domainSuffix`, `.domainKeyword`, `.ipCidr`, `.geoip`, `.geosite`.
   - `RuleAction`: `.proxy`, `.direct`, `.block`.
   - Provide a default preset list:
     - `GEOSITE: category-ads-all -> BLOCK`
     - `DOMAIN-SUFFIX: ru -> DIRECT`
     - `DOMAIN-SUFFIX: рф -> DIRECT`
     - `GEOIP: ru -> DIRECT`
     - `GEOIP: private -> DIRECT`
     - `FINAL -> PROXY`

### Phase 2: URI & Subscription Parser (`Shared/Config/SubscriptionParser.swift`)
1. Implement parser for standard `vless://` links:
   - Format: `vless://<uuid>@<host>:<port>?security=reality&encryption=none&pbk=<pbk>&fp=chrome&type=tcp&flow=xtls-rprx-vision&sni=<sni>&sid=<sid>#<Remark>`
2. Implement parser for custom `vortex://` and `vkcall://` URI schemes so all 3 protocols can coexist in a single Base64 subscription link:
   - `vortex://<secret>@<host>:<port>?mode=<mode>#<Remark>`
   - `vkcall://<call_id>@<relay_host>:<port>?key=<secret>&vk_link=<encoded_url>#<Remark>`
3. Implement `SubscriptionFetcher` that downloads a subscription URL:
   - Parses `Subscription-Userinfo` HTTP header (`upload=...; download=...; total=...; expire=...`) to display traffic stats like `↑:508.8M, ↓:28.38G, TOT:0.00K, EXPIRE:∞`[cite: 1].
   - Decodes Base64 payload into an array of `ServerNode`.

### Phase 3: Configuration Builder (`Shared/Config/ConfigBuilder.swift`)
1. [x] Generate a valid `sing-box` JSON configuration from the currently selected `ServerNode`, `GlobalRoutingMode`, and `[RoutingRule]`.
2. [x] **Anti-Loop Protection (Critical):**
   - Automatically extract the IP/domain of the active VPN server and all VK Call signaling/TURN domains (`*.vk.com`, `*.mycdn.me`, `*.userapi.com` when `vkCall` mode is active) and place them at the very top of the routing table with action `direct`.
3. [x] **Modern Sing-box Rule-Set Architecture (1.8+ / 1.10+):**
   - Completely eliminate deprecated `route.geoip` and `route.geosite` monolithic `.db` keys to prevent iOS Packet Tunnel OOM crashes (>50 MB).
   - Use modern `route.rule_set` with `type: "local"` and `format: "binary"` pointing to `<AppGroup>/RuleSets/*.srs`.
   - Strict fallback protection: unverified or missing `.srs` files are safely omitted from `rule_set` and `route.rules`.
4. [x] **DNS Routing:**
   - Remote DNS (`https://1.1.1.1/dns-query`) detained via `proxy` outbound.
   - Direct DNS (`77.88.8.8`) detained via `direct` outbound for `.ru` domains and server hostname resolution.
5. [x] **TUN Settings:**
   - Virtual subnet: `172.19.0.1/30`.
   - MTU: `1280` (mandatory when using `vkCall` due to STUN/TURN/WebRTC header overhead; configurable up to `1400` for pure VLESS).

### Phase 3.5: Binary Rule Sets (.srs) & Offline-First Management (`RuleSetManager.swift`)
1. [x] **Bundled Offline Rule Sets:**
   - Pre-pack lightweight compiled binary `.srs` files into application resources (`geoip-ru.srs`, `geosite-category-ru.srs`, `geosite-category-ads-all.srs`, total < 70 KB).
2. [x] **Integrity & Compatibility Validation:**
   - Enforce `validateSRSFile(at: URL)` ensuring size > 512B and ASCII magic header `[0x53, 0x52, 0x53]` (`"SRS"`), preventing HTML error pages / TSPU blocks from corrupting local rule sets.
3. [x] **Atomic Updates with Fallback Mirrors:**
   - Download fresh rule sets supporting primary GitHub and resilient CDN/proxy mirrors (`fastly.jsdelivr.net`, `mirror.ghproxy.com`).
   - Validate before atomic file swap and update `AppGroup.userDefaults` metadata (`lastRuleSetUpdateDate`, `ruleSetFileSizes`).
   - Hot-reload active tunnel via `TunnelManager.reloadRules()` and IPC message `.reloadRules`.
4. [x] **Automatic Background Updates:**
   - Configurable auto-update (default every 7 days / 604,800 sec) executed on startup and app foregrounding.
5. [x] **Shadowrocket-Styled UI Integration (`RuleSetsCardView`):**
   - File status rows with availability badges, KB sizes, auto-update toggle, last update timestamp, and "Обновить базы сейчас" button with progress spinner in both `RoutingView.swift` and `SettingsView.swift`.

### Phase 4: Minimalist Shadowrocket-Style UI (`VortexApp`)
Build the interface in dark mode (`Color.black` background, `#1C1C1E` grouped cards, `#FF9500` orange selection dots, `#34C759` / `#007AFF` accents)[cite: 1]:
1. **Tab 1 — `Главная` (`HomeView.swift`)[cite: 1]:**
   - **Top Bar:** Left button: QR/Clipboard import; Center: Title `Vortex`; Right button: `+` (Add node or Subscription URL)[cite: 1].
   - **Top Control Group Card[cite: 1]:**
     - Row 1: Rocket/Shield icon + Active node name + VPN Master Toggle (`Switch`)[cite: 1].
     - Row 2: Gear icon + `Маршрутизация` (`Routing`) + current mode label (`Настройка >`) opening quick mode picker (`Конфигурация`, `Прокси`, `Напрямую`, `Блокировка`)[cite: 1].
     - Row 3: Gauge icon + `Тест подключения` (`Connectivity Test`) — triggers parallel TCP/HTTP ping across nodes[cite: 1].
   - **Section `Локальные серверы` (`Local Servers`)[cite: 1]:**
     - Collapsible card header[cite: 1].
     - Server rows: Active orange dot indicator (if selected), Country flag emoji/icon, Node Title, Subtitle in caps (`VLESS / XTLS-RPRX-VISION / UDP`[cite: 1], `VORTEX / PROPRIETARY / UDP`, or `VK-CALL / TURN-RELAY / UDP`), latency badge (`45 ms`), and `(i)` info button[cite: 1].
   - **Section `Подписки` (`Subscriptions`)[cite: 1]:**
     - Collapsible card per subscription showing title/IP, refresh button, and traffic line (`↑:508.8M, ↓:28.38G, TOT:0.00K, EXPIRE:∞`)[cite: 1], followed by its server rows[cite: 1].
2. **Tab 2 — `Настройка` (`RoutingView.swift`)[cite: 1]:**
   - Segmented picker for Global Mode (`Rule` / `Global Proxy` / `Direct`).
   - Searchable list of domain/IP rules grouped or badged by `PROXY` (Blue), `DIRECT` (Green), `BLOCK` (Red).
   - `+` sheet to add custom rule (`Type`: `DOMAIN`, `DOMAIN-SUFFIX`, `DOMAIN-KEYWORD`, `IP-CIDR`; `Action`: `PROXY`, `DIRECT`, `BLOCK`; `Value`: string).
3. **Tab 3 — `Данные` (`DataStatsView.swift`)[cite: 1]:**
   - Real-time TX/RX speed and session totals.
   - Packet Tunnel memory usage readout (`RAM: 24.5 MB / 50 MB`).
   - Recent connections log with matched rule badge.
4. **Tab 4 — `Настройки` (`SettingsView.swift`)[cite: 1]:**
   - MTU selector (`1280` - `1420`).
   - DNS configuration.
   - VK Call pre-auth helper (WebView sheet to handle VK captcha/token retrieval in Host App before passing token to Tunnel Extension).

### Phase 5: Go Core Engine & Protocol Stubs (`CoreGo`)
1. Initialize Go module with `sing-box` library dependencies.
2. Implement `bridge.go` exposing C-compatible/Gomobile functions:
   - `StartVortexTunnel(configJSON string, tunFd int32) error`
   - `StopVortexTunnel() error`
   - `MeasureNodeLatency(nodeJSON string) int64`
   - `GetTrafficStats() string`
3. Configure strict memory limits inside Go `init()`:
   - `debug.SetMemoryLimit(32 * 1024 * 1024)`
   - `debug.SetGCPercent(15)`
4. Create clean stub packages in `CoreGo/outbound/proprietary` and `CoreGo/outbound/vkcall` with documented `TODO(backend-spec)` markers for packet framing, encryption, and VK TURN allocation.

### Phase 6: System Packet Tunnel (`VortexTunnelExtension`)
1. Implement `PacketTunnelProvider: NEPacketTunnelProvider`.
2. In `startTunnel`:
   - Load `config.json` from `AppGroup`.
   - Apply `NEPacketTunnelNetworkSettings` (IPv4 `172.19.0.1`, Subnet `255.255.255.252`, DNS `172.19.0.2`, MTU from config).
   - Obtain the `utun` file descriptor (`packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32` or fallback to `packetFlow.readPackets` loop).
   - Pass execution to `VortexCore` (or `MockTunnelEngine` when building without the Go binary during UI testing).
3. Handle `stopTunnel` and `handleAppMessage` cleanly.

---

## 5. Agent Execution Instructions
1. **No Per-App VPN:** Do not use `NEAppProxyProvider` or per-app rules. Routing is strictly domain/IP/Geo-based.
2. **Compile-Ready First:** Implement a `TunnelEngineProtocol` in Swift with two implementations:
   - `MockTunnelEngine` (simulates connection state, traffic counters, and latency pings so the UI and config generation run out-of-the-box in Xcode Simulator and macOS without requiring `gomobile` compilation first).
   - `LibboxTunnelEngine` (hooks into `VortexCore.xcframework`).
3. **Execution Order:**
   - **Step 1:** Generate all `Shared` models, `SubscriptionParser` (with full `vless://`, `vortex://`, `vkcall://` support), and `ConfigBuilder`.
   - **Step 2:** Generate the complete SwiftUI `VortexApp` matching the Shadowrocket dark layout[cite: 1].
   - **Step 3:** Generate `VortexTunnelExtension` (`PacketTunnelProvider.swift`) and `TunnelManager.swift`.
   - **Step 4:** Generate the `CoreGo` directory with the Go wrapper, protocol stubs, and `build_xcframework.sh`.

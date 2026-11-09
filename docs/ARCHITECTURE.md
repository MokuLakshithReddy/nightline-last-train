# NIGHTLINE: Architecture & System Responsibilities

## 1. System Philosophy & Authority Boundary

```text
ROBLOX CLIENT (Untrusted)
  Input / UI / Camera / Audio / Local Visuals
          │
          │ Validated RemoteEvents / ProximityPrompts
          ▼
ROBLOX SERVER (Authoritative)
  RoundService  ──► StationService  ──► ObjectiveService
  MonsterService ──► InventoryService ──► RewardService
  PlayerDataService ──► SecurityService ──► AnalyticsService
          │
          ▼
ROBLOX PLATFORM SERVICES
  DataStoreService / MarketplaceService / SoundService
```

### Server Invariants:
1. **Server Authoritative State:** The server owns round state, timers, player rosters, inventory items, objective verification, monster simulation, damage calculations, scrap rewards, and persistent storage.
2. **Untrusted Client Inputs:** Never trust any client claim of completion, distance, or item ownership. Every RemoteEvent call is subjected to sender validation, rate limiting, phase checks, and range bounds checks.
3. **Idempotence & Cleanup:** Round cycles transition cleanly between states (`WAITING`, `INTERMISSION`, `BOARDING`, `TRAVEL`, `EXPLORATION`, `EXTRACTION`, `RETURN`, `RESULTS`), and every temporary asset in `Workspace.World.Runtime` is guaranteed to be collected.

---

## 2. Service Responsibilities

| Service | Primary Domain | Hard Constraints |
|---|---|---|
| `RoundService` | Core game loop, authoritative timers, player rosters, state machine transitions. | Never accept client timers; prevent overlapping rounds. |
| `StationService` | Procedural selection of objective markers, dynamic loading and unloading of Station templates. | Never award currency directly; isolate map state per round. |
| `ObjectiveService` | Mission lifecycle (Restore Power, Recover Cargo, Repair Signal), progress validation. | Reject any client claim that an objective is complete without server validation. |
| `MonsterService` | Spawning and lifecycle of The Hollow, noise event broker, perception checks, attack validation. | Throttle path calculations; never raycast every frame; validate attacks serverside. |
| `InventoryService` | 2-slot equipment loadouts, mission item state, pickup atomic handshakes. | Never allow client to specify arbitrary item IDs or counts. |
| `InteractionService`| Unified handling of `ProximityPrompt` events with debounce, distance, and living state validation. | Do not rely on client-side prompt feedback as proof of interaction. |
| `RewardService` | Server-calculated payout for primary objective + extraction bonus + optional scrap caches. | Keep formula deterministic and reward grants strictly idempotent. |
| `PlayerDataService` | Safe profile loading, retries, versioned schema migrations, session locking, and dirty-state saves. | Never overwrite valid profiles with blank defaults on load failures. |
| `SecurityService` | Sliding-window rate limiters, token bucket filters, and sanity verifications for remotes. | Must be reusable across all remote dispatch points. |
| `AnalyticsService` | Key telemetry points (`FirstSessionStarted`, `ExpeditionStarted`, `ObjectiveCompleted`, `PlayerExtracted`, `ExpeditionEnded`). | Strip all PII; record only high-signal gameplay funnels. |

---

## 3. Client Controllers

| Controller | Responsibilities |
|---|---|
| `UIController` | Responsive HUD rendering, round timers, objective progress, notification banners, extraction alerts. |
| `InputController` | Device-agnostic input binding (Keyboard/Mouse, Touch Screen, Gamepad Controller). |
| `CameraController` | Cinematic camera transitions during Train Travel and Return states. |
| `InteractionController`| Custom prompt styling, interaction feedback, visual audio cues. |
| `AudioController` | Dynamic music layering, train rumble, station ambience, monster proximity heartbeat. |
| `EffectsController` | Lighting adjustments, flickering bulbs, steam/fog emitters, screen shakes on train departure. |


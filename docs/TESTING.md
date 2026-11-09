# NIGHTLINE: Testing & Verification Matrix

## Testing Methodologies

Testing in NIGHTLINE is conducted across three levels:
1. **Static Analysis & Linting:** Strict Luau typing validation, syntax checks, and Selene linter rules.
2. **Local Project Build Verification:** Automated compilation into valid Roblox binary places (`.rbxl`) using Rojo CLI.
3. **Runtime Engine Simulation:** Studio play mode (F5), Local Server Multi-Client simulation (1–6 players), and client-server network replication validation.

---

## Test Cases & Verification Log

| Test ID | System / Target | Precondition | Test Execution | Expected Result | Result |
|---|---|---|---|---|---|
| **M0-T1** | Project Build | Valid project file & source trees | Run `rojo build -o Nightline.rbxl` | Success code 0, binary `.rbxl` generated without errors | ✅ Passed |
| **M0-T2** | Static Lint | Selene configured for roblox std | Run `selene src` | 0 errors, 0 unresolved warnings | ✅ Passed (0 err, 0 warn) |
| **M0-T3** | Remote Contract | Remotes folder in ReplicatedStorage | Server Bootstrap initializes remotes | All 9 documented RemoteEvents present and typed | ✅ Passed |
| **M1-T1** | Hub Generation | Empty / new place | Server starts with HubBuilder | `Workspace.World.Hub` created with Train, Platform, Spawns, Workshop | ✅ Passed |
| **M1-T2** | Player Spawning | Hub loaded | Player joins session | Character spawns inside Hub safe zone with default walkspeed | ✅ Passed |
| **M1-T3** | Round State Flow | 1 player in Hub | Advance from `WAITING` | Cycles `WAITING` -> `INTERMISSION` -> `BOARDING` -> `TRAVEL` -> `EXPLORATION` -> `EXTRACTION` -> `RETURN` -> `RESULTS` -> `WAITING` | ✅ Passed |
| **M1-T4** | Roster Locking | Round in `BOARDING` | Player joins mid-phase | Existing player roster locked; late joiner stays in Hub spectator mode | ✅ Passed |
| **M1-T5** | State Cleanup | Round completes / ends early | Round finishes `RESULTS` or aborts | All runtime station models removed; server state resets cleanly | ✅ Passed |
| **M1-T6** | UI & Countdown | Client connected | Server broadcasts `RoundStateChanged` | HUD displays accurate state name, formatted timer, and broadcast notification | ✅ Passed |
| **M2-T1** | Station 001 Zones | Round enters `EXPLORATION` | StationService generates station | All 6 zones created: Platform, Concourse, Maintenance, ControlRoom, CargoStorage, UndergroundTunnel | ✅ Passed |
| **M2-T2** | Restore Power | `RestorePower` active | Collect 3 fuses & install in sockets | Breaker lights switch red to green, progress 3/3, mission completed | ✅ Passed |
| **M2-T3** | Recover Cargo | `RecoverCargo` active | Pick up 2 crates & deliver to platform | Crates weld to back, platform pallet stores crates, progress 2/2 | ✅ Passed |
| **M2-T4** | Repair Signal | `RepairSignal` active | Reboot 3 communication terminals | Terminal screens switch red offline to green online, progress 3/3 | ✅ Passed |
| **M2-T5** | Scrap Caches | Round in `EXPLORATION` | Scavenge optional caches | Stored as unbanked loot in memory; banked only upon successful extraction | ✅ Passed |
| **M2-T6** | Extraction Zone | Round enters `RETURN` | Check character position | Players inside extraction volume receive +50 Scrap extraction bonus | ✅ Passed |
| **M2-T7** | Runtime Cleanup | Round enters `RESULTS`/`WAITING` | StationService.UnloadStation() | All active station parts, prompts, and dropped crates destroyed | ✅ Passed |
| **M3-T1** | Hollow Model | Round enters `EXPLORATION` | MonsterService spawns model | Slender shadow figure with dark slate torso, head, particle smoke, glowing eyes, and Humanoid | ✅ Passed |
| **M3-T2** | Patrol Behavior | Monster spawned | No player noise or sight | Moves along waypoints across Concourse, Maintenance, Cargo, Control, and Tunnel at 10 studs/s | ✅ Passed |
| **M3-T3** | Hearing Detection | Player runs or walks | Heartbeat emits noise radius | Sprints (45 stud radius) alert creature to `INVESTIGATE` position; walks (20 studs) remain quieter | ✅ Passed |
| **M3-T4** | Line-of-Sight Sight | Player enters 110 deg FOV | Raycast check against walls | Direct sight triggers `CHASE` (19 studs/s); walls block line-of-sight | ✅ Passed |
| **M3-T5** | Search & Return | Player breaks sight & escapes | Run outside max range | Creature searches last known position for 8s, then returns to patrol route | ✅ Passed |
| **M3-T6** | Attack & Elimination | Creature reaches 5.5 studs | Line-of-sight hit validation | 0.4s eye flash telegraph, eliminates player from expedition, teleports to Hub, no data lost | ✅ Passed |
| **M3-T7** | Server Ownership | Physics check | Network owner inspection | Creature HumanoidRootPart network owner is nil (server-authoritative, exploit-immune) | ✅ Passed |
| **M3-T8** | Runtime Despawn | Round enters `RETURN` | MonsterService.DespawnMonster() | Model destroyed, AI loop thread canceled, noise listeners cleanly disconnected | ✅ Passed |
| **M4-T1** | Profile Lifecycle | Player joins / leaves | PlayerDataService load & save | Safe profile load with schema validation; dirty-state serialized saving | ✅ Passed |
| **M4-T2** | Overwrite Protection | DataStore mock failure | Simulate fetch error | Profile marked read-only; never overwrites stored data with defaults | ✅ Passed |
| **M4-T3** | Idempotent Grants | Round completes | RewardService.AwardExpeditionRewards | Single grant per roundId/player; duplicate invocations ignored | ✅ Passed |
| **M4-T4** | Train Upgrade Purchase| Player interacts with terminal | Fire `RequestPurchaseUpgrade` | Validates scrap cost, deducts balance, marks owned, syncs profile | ✅ Passed |
| **M4-T5** | Artifact Collection | Pick up artifact in tunnel | Survive and extract on train | Added to player permanent `Artifacts` set; recorded in profile | ✅ Passed |
| **M4-T6** | Upgrade Shop UI | Open terminal in train carriage | UIController toggles modal | Shows real-time Scrap balance, artifact count, and live purchase buttons | ✅ Passed |
| **M5-T1** | Mobile Controls | Touch enabled device | InputController binds ContextAction | On-screen touch buttons for Sprint and Item slots positioned responsively | ✅ Passed |
| **M5-T2** | Audio State Layers | Round transitions | AudioController updates volume | Train rumble in Hub/Travel; eerie station drone in Exploration; klaxon in Extraction | ✅ Passed |
| **M5-T3** | Heartbeat Distance | Player approaches creature | Distance check < 60 studs | Volume and playback speed increase as creature nears; fades out upon evasion | ✅ Passed |
| **M5-T4** | Lighting Ambience | Station entered | EffectsController applies fog | Smooth transition to dense sub-level fog (FogEnd 160) and dark mood lighting | ✅ Passed |
| **M5-T5** | Camera Shake | Train departs / arrives | EffectsController.ShakeCamera() | Directional rotational camera shake during travel transitions | ✅ Passed |
| **M6-T1** | Remote Rate Limiting| Client fires spam requests | SecurityService token bucket | Calls exceeding 10/s throttled and rejected with structured server warning | ✅ Passed |
| **M6-T2** | Distance Exploit Guard| Remote called from afar | SecurityService distance check | Prompt calls > MaxInteractionDistance rejected; server position verified | ✅ Passed |
| **M6-T3** | String Sanitization | Invalid or oversized payload | ValidateString check | Payloads > 32/128 characters truncated or rejected; type safety enforced | ✅ Passed |
| **M6-T4** | Mid-Round Disconnect | Player disconnects during run | PlayerRemoving handler | Safely removed from activeRoster; no nil exceptions or stuck timers | ✅ Passed |
| **M6-T5** | All-Player Departure | All active players leave | RoundService abort check | Expedition safely aborts to Results and cleans up runtime station instances | ✅ Passed |
| **M6-T6** | Late-Joiner Routing | Join while station active | CharacterAdded handler | Player spawns in Hub safe zone; spectator status assigned until next round | ✅ Passed |
| **FIX-T1**| Unbanked Scrap Guard | Player eliminated with scrap | ObjectiveService unbanked table | Unbanked scrap not awarded to permanent profile unless extracted | ✅ Passed |
| **FIX-T2**| Session Locking Lease| Dual server simulation | DataStore UpdateAsync with JobId | Conflicting session detected; aborts overwrite; releases on player leave | ✅ Passed |
| **FIX-T3**| Equipment Phase Check| Request swap mid-exploration | Bootstrap phase verification | Swaps rejected outside Hub phases (`WAITING`/`INTERMISSION`/`BOARDING`) | ✅ Passed |
| **FIX-T4**| Central Interaction Precondition | Interaction triggered | Central validator in ObjectiveService | Rejects if not rostered, dead, wrong phase, or wrong mission type | ✅ Passed |
| **FIX-T5**| Persistent Idempotency & Stats | Expedition with 0 payout | RewardService.AwardExpeditionRewards | `LastProcessedRoundId` stored in profile; `Statistics.Runs` increments on all runs | ✅ Passed |
| **FIX-T6**| Session Lock Heartbeat & Result Check | Long server session / failed lock | PlayerDataService UpdateAsync | Verifies result ~= nil and strict server ownership; auto-refreshes 300s lease | ✅ Passed |
| **FIX-T7**| Flare Consumable Deduction & Ownership | Equip & throw flare without locker | InventoryService & EquipmentService | Deducts 10 Scrap on equip if not unlocked; validates and consumes slot item on throw | ✅ Passed |
| **FIX-T8**| EquipmentService Bootstrap Integration | Server boot & remote listeners | Bootstrap.server.luau Init() | EquipmentService required and initialized; ToggleFlashlight and ThrowFlare active | ✅ Passed |
| **FIX-T9**| Extraction-Phase Objective Lockdown | Interaction triggered during EXTRACTION | ObjectiveService phase check | Objectives/caches locked during EXTRACTION; only cargo delivery permitted | ✅ Passed |
| **FIX-T10**| ProximityPrompt Security Permission | Trigger ProximityPrompt | InteractionService cooldown validation | Prompt Instance used as weak table key (no GetDebugId call); interactions succeed without permission error | ✅ Passed |
| **FIX-T11**| Network Ownership & Loop Guard | Exploration phase start | Monster spawn and round transition | Model parented to Workspace before SetNetworkOwner; round loop protected with pcall against NPC failures | ✅ Passed |
| **FIX-T12**| Line-of-Sight & Attack Revalidation | Player in vision & attack windup | Raycast filter against monster model | Creature excludes monster model instead of Workspace; rechecks LOS after 0.4s windup behind cover | ✅ Passed |
| **FIX-T13**| Integer Equipment Slot Validation | Fire RequestEquipment with non-integer / NaN / out-of-bounds slot (e.g. 1.5, 0, 3, NaN) | SecurityService.ValidateInteger & InventoryService.SetSlotItem | Rejected before Scrap deduction or inventory mutation; Scrap balance and slots 1 & 2 unchanged | ✅ Passed |
| **FIX-T14**| Equipment Remote Abuse & Phase-Gating | Spam toggle/throw, dead player, non-rostered player, wrong phase, or unequipped item | EquipmentService validation & rate limits | Requests rejected; no items consumed, no parts spawned, no state changes | ✅ Passed |
| **FIX-T15**| Read-Only Profile & Cosmetic Reconciliation | Contested session lock or load failure | PlayerDataService.IsProfileWritable & reconcileProfile | Mutations rejected when read-only; OwnedCosmetics & EquippedCosmetics safely restored from DataStore | ✅ Passed |
| **FIX-T16**| State-Aware Phase Wait & Abort Protection | All players leave during exploration/extraction | RoundService.WaitForPhase & TransitionTo | WaitForPhase binds to stateGeneration; aborting to RESULTS returns false immediately and never regresses to EXTRACTION | ✅ Passed |
| **FIX-T17**| Server-Authoritative Sprint & Movement Sanity | Sprint request / abnormal displacement / speed exploit | MovementService heartbeat check & RequestSprint | Authoritative sprint speed enforced; unauthorized speed capped; rubberbanding on illegal displacement with teleport grace periods | ✅ Passed |
| **FIX-T18**| Hub Upgrade Terminal Validation | Fire RequestPurchaseUpgrade from dead, distant, or non-Hub players or during exploration/extraction | Bootstrap.server.luau remote validation & HubBuilder.GetUpgradeTerminal | Purchases rejected outside WAITING/INTERMISSION/BOARDING, when dead, or when beyond interaction distance; Scrap balance and upgrades unchanged | ✅ Passed |
| **FIX-T19**| Server-Authoritative Destination Voting | Fire RequestDestinationVote during preparation vs post-departure, with valid/invalid station IDs, changed votes, ties, and disconnects | RoundService.RecordDestinationVote & TallyDestinationVotes | Votes accepted only in Hub preparation; single vote per player tracked; ties resolved deterministically; winning station loaded in EXPLORATION | ✅ Passed |
| **FIX-T20**| Camera Travel & Return Transitions | Round enters TRAVEL/RETURN; respawn/disconnect/interrupted phases | CameraController.PlayTravelTransition & RestorePlayerCamera | Scriptable smooth camera tween plays during TRAVEL/RETURN; cleanly restored to Custom on phase completion, respawn, or error; never stuck in Scriptable | ✅ Passed |
| **FIX-T21**| Contextual ProximityPrompt Presentation | ProximityPrompt shown/hidden/held/triggered under Keyboard, Gamepad, and Touch | InteractionController custom billboard & input styling | Custom stylized HUD prompts rendered with dynamic key badge ([E]/[X]/[TAP]), smooth hold progress animation, trigger pulse feedback, and error flash; server authority strictly retained | ✅ Passed |
| **FIX-T22**| Gameplay Telemetry & Roblox Analytics Pipeline | Session start, expedition begin/finish, objective progress, extraction, death, and upgrade purchase | AnalyticsService, PlayerDataService, RoundService, ObjectiveService, MonsterService | Validates attribute hygiene (non-PII, bounds, count limits); fires custom and economy telemetry without throwing; events recorded in ring buffer | ✅ Passed |
| **FIX-T23**| MarketplaceService Receipt Processing & Game Pass Entitlements | Simulate ProcessReceipt with duplicate receipts, unowned/unlisted IDs, read-only profiles, and game pass ownership | PurchaseService, MonetizationConfig, PlayerDataService | Duplicate receipts granted idempotently; invalid products deferred (NotProcessedYet); writable profile verified; game passes synchronized on join/prompt | ✅ Passed |
| **FIX-T24**| Executable Automated Test Suite & CI | Pull request or push to main branch; local CLI execution | GitHub Actions CI workflow, Rojo build, Selene lint, and tests/run_tests.py | 14 automated test suites pass without regression; Rojo compiles binary place; Selene lints with 0 errors; build and test artifacts uploaded | ✅ Passed |
| **FIX-T25**| Evidence-Based Release Sign-Off | Documentation review & milestone status check | DEVELOPMENT_PROGRESS.md, RELEASE_GUIDE.md, and TESTING.md reconciliation | Separates automated CI guarantees from manual Studio staging; removes unsubstantiated production claims; milestones aligned with executable evidence | ✅ Passed |
| **FIX-T26**| Flashlight Toggle State Lifecycle & Model Separation | Repeated toggle requests, missing torso, character respawn, off -> on -> off -> on cycles | EquipmentService.ToggleFlashlight, AttachFlashlightModel & IsFlashlightOn | State and model attachment decoupled; IsFlashlightOn matches physical model state; toggling off cleanly removes model and disables light; respawns auto-clean | ✅ Passed |
| **FIX-T27**| Developer Product Durable Receipt Persistence & Retry Rollback | Server restart/crash, DataStore failure, duplicate receipts, unlisted product IDs, read-only profile | PurchaseService.ProcessReceipt, PlayerDataService.SaveProfile & UpdateAsync | Receipt IDs persisted atomically in PlayerProfile.ProcessedReceipts via UpdateAsync; SaveProfile exposes boolean status; in-memory state rolls back if save fails; duplicate receipts return PurchaseGranted idempotently; unlisted product IDs rejected | ✅ Passed |
| **FIX-T28**| Player-Facing Destination Voting Interface & Remote Wiring | Cast votes during WAITING/INTERMISSION/BOARDING, phase transitions, closed voting, gamepad/touch navigation | UIController.BuildDestinationVotingUI, CastVote, UpdateDestinationVotes & Remotes | Client UI dynamically displays server options and live tallies; votes dispatch via RequestDestinationVote; buttons disable when voting closes; supports mouse, touch, and gamepad selection | ✅ Passed |
| **FIX-T29**| Telemetry Player Attribution, Economy Enum Strings & Error Visibility | Trigger expedition start/end, upgrade purchase, and simulate backend dispatch failures | AnalyticsService, RoundService.luau & RobloxAnalytics | Resolves player attribution for round-level events without passing nil to LogCustomEvent; converts economy transaction type to documented string Name ("Shop"); records aggregate summaries in local buffer; counts and logs dispatch failures | ✅ Passed |
| **FIX-T30**| Hollow Footstep Noise Cadence Throttling & Movement Filtering | 6-player movement load, sprint vs walk, stationary players, airborne jumping, non-rostered players | MonsterService.SpawnMonster, DespawnMonster & MonsterConfig | Replaced per-frame Heartbeat noise flood with distance & interval cadence (walk 0.5s / run 0.3s, min 2 studs); excludes dead, stationary, airborne, and unrostered players; ensures single listener lifecycle; bounds max 6-player emission rate to < 20 events/sec | ✅ Passed |
| **FIX-T31**| Comprehensive Movement Sanity & Solid Wall-Traversal Protection | Speed hacks, vertical flings, gravity freefalls, slope climbs, wall traversal raycasts, safe rollback validation | MovementService.CheckMovementSanity, getSafeRollbackCFrame, RegisterTeleport & Heartbeat | Validates vertical displacement (upward flings > 50 studs/s, downward anomalies > 220 studs/s); raycasts trajectory against solid architecture; validates rollback floor before rubberbanding; tracks and decays violation counts; preserves explicit teleport grace | ✅ Passed |
| **FIX-T32**| Concurrent ProcessReceipt In-Flight Locks & Exception Safety | Concurrent duplicate callbacks for same PurchaseId, per-player serialization, failed save retry, exception recovery | PurchaseService.ProcessReceipt, inFlightReceipts & inFlightPlayers | Added in-flight receipt locks and per-player serialization preventing duplicate grants under concurrent callbacks; guarantees in-flight lock release on error/abort; preserves retry safety until durable save succeeds | ✅ Passed |

---

## Automated vs. Manual Verification Boundary

To ensure evidence-based quality without unsubstantiated claims, NIGHTLINE distinguishes between reproducible automated CI verification and manual Studio physical testing:

### 1. Fully Automated Checks (Reproducible in CI via `.github/workflows/ci.yml`)
- **Linter & Static Typing:** `selene src/` validates all Luau source files against the Roblox standard library (0 errors, 0 warnings).
- **Rojo Compilation:** `rojo build default.project.json --output Nightline.rbxlx` compiles the full DataModel hierarchy into a valid binary Roblox place file.
- **Automated Regression Suite (`tests/run_tests.py`):**
  - Project configuration & remote contract declarations.
  - Integer equipment slot bounds, NaN, float, and string rejection (`FIX-T13`).
  - Hub-phase gating, living humanoid checks, and equipment loadout rules (`FIX-T14`).
  - Terminal distance validation (`FIX-T18`).
  - Destination vote tallying, duplicate-vote prevention, and deterministic tie-breaking (`FIX-T19`).
  - Hollow monster model exclusion in raycast filters and 0.4s windup LOS recheck (`FIX-T12`).
  - State generation counters and cancellation of stale phase waits (`FIX-T16`).
  - Profile reconciliation, cosmetic restoration, and read-only session lock protection (`FIX-T15`).
  - Weak-table instance-keyed ProximityPrompt cooldown registry (`FIX-T10`).
  - CameraController travel/return transitions and fail-safe Custom camera restoration (`FIX-T20`).
  - Contextual ProximityPrompt input adapters for Keyboard, Gamepad, and Touch (`FIX-T21`).
  - Analytics telemetry schema sanitation and funnel call sites (`FIX-T22`).
  - MarketplaceService developer product idempotency and game pass catalog integrity (`FIX-T23`).

### 2. Manual Roblox Studio Testing (Required Prior to Major Public Release)
- **Multi-Client Local Server (2-6 Players):** Validates network latency, physical carriage crowding, and rubberbanding feel under simulated packet drops.
- **Physical Gamepad & Mobile Touch Devices:** Validates on-screen touch button layouts, thumbstick deadzones, and vibration triggers on real mobile/console hardware.
- **Lighting & Atmospheric Fog:** Subjective tuning of volumetric fog density and lantern warm-glow falloffs in live Studio viewport.

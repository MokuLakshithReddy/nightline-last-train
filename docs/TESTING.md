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

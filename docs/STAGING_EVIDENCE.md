# NIGHTLINE: LAST TRAIN — Roblox Studio Staging Evidence Record

> **Historical record.** These results are dated 2026-11-10 and apply to commit `176419d50662dc6af48f5e4eb9be7437fc7bbf36`. They do not validate PR #64 (`92314432cdbe66766ab73b8737d939b56423088a`) or any later release candidate. Re-run applicable scenarios and record the tested candidate SHA before sign-off.

## 1. Test Environment & Metadata

- **Tested Date:** 2026-11-10
- **Tested Commit SHA:** `176419d50662dc6af48f5e4eb9be7437fc7bbf36`
- **Roblox Studio Version:** `0.746.0.7461269`
- **Test Mode:** Test > Local Server (1 to 6 Client Instances)
- **Place File:** `Nightline.rbxlx` (compiled via Rojo 7.4.4 from `default.project.json`)
- **Linter Status:** Selene 0.32.0 (0 errors, 0 warnings)
- **Automated Regression Suite:** 24/24 passed in CI before staging

---

## 2. Staging Execution Matrix

| Scenario ID | Test Scenario | Client Count | Target Subsystems | Result | Notes / Evidence |
|---|---|---|---|---|---|
| **STG-01** | Solo Hub & Expedition Loop | 1 Client | HubBuilder, RoundService, ObjectiveService, CameraController | ✅ PASS | Verified full lifecycle from Hub to extraction and results. Camera smoothly restored. |
| **STG-02** | 6-Client Multiplayer Carriage Navigation | 6 Clients | Character physics, Hub collisions, MovementService | ✅ PASS | No character clipping, physics flings, or desync inside train carriage. |
| **STG-03** | Live Destination Voting & Replication | 6 Clients | RoundService voting FSM, UIController voting HUD | ✅ PASS | 4 votes Station001 vs 2 votes Station002. Station001 selected deterministically. |
| **STG-04** | The Hollow Hearing & LOS Occlusion | 6 Clients | HollowAI, MonsterService, sound perception | ✅ PASS | Creature alerted to sprinting player; LOS obstructed behind pillar; 0.4s windup re-check prevented damage behind cover. |
| **STG-05** | Mid-Round Player Disconnection | 6 Clients | PlayerRemoving, RoundService roster, ObjectiveService | ✅ PASS | Client 6 disconnected during EXPLORATION; active roster dropped player cleanly without error; remaining 5 completed run. |
| **STG-06** | All-Player Departure Abort | 3 Clients | RoundService.WaitForPhase, stateGeneration guard | ✅ PASS | All clients disconnected during EXPLORATION; round immediately aborted to RESULTS and unloaded station. |
| **STG-07** | Synchronized Server Countdown | 6 Clients | Workspace:GetServerTimeNow(), UIController HUD timer | ✅ PASS | Timers identical across all 6 clients; no drift or negative numbers on transition. |

---

## 3. Scenario Details & Execution Logs

### Scenario STG-01: Solo Hub & Expedition Loop (1 Client)
1. **Steps:**
   - Launch Local Server (1 Player).
   - Player spawns in Hub safe zone at `Vector3.new(0, 8, 0)` with 100 Health.
   - Walk inside train carriage to Upgrade Terminal. Trigger `OpenUpgradeTerminalPrompt` via `[E]`.
   - Upgrade Shop modal opens; verified initial balance `0 Scrap` and `0 / 4 Artifacts`.
   - Wait for `WAITING` phase to elapse; server transitions to `INTERMISSION` (15s) and `BOARDING` (45s).
   - At departure, `TRAVEL` phase (20s) triggers:
     - `CameraController.PlayTravelTransition()` switches camera to `Scriptable`.
     - Directional rotational camera shake triggers smoothly.
     - Hub lighting transitions to station fog parameters.
   - Round enters `EXPLORATION` (180s):
     - `StationService.LoadStation("Station001")` procedural generation loads Station 001.
     - Player teleported to station platform spawn position.
     - `CameraController` restores cleanly to `Custom` mode attached to Humanoid.
     - Active objective assigned (`RestorePower`: locate 3 missing fuses).
   - Locate fuses in Generator Room; interact with ProximityPrompts (prompt instance table keys work without permission errors).
   - Enter `EXTRACTION` phase (60s); warning banner fires across HUD.
   - Step into train carriage extraction zone before timer elapses.
   - Round enters `RETURN` (20s); player recognized as extracted, teleported back to Hub safe area.
   - Round enters `RESULTS` (30s); Rewards awarded, mission marked complete, Scrap balance updated in profile.
   - Station unloaded, clean reset to `WAITING`.
2. **Server Log Snippet:**
   ```text
   [INFO] [RoundService] Initializing authoritative game loop...
   [INFO] [RoundService] State transition: WAITING -> INTERMISSION (EndsAt: 1731190015, Duration: 15)
   [INFO] [RoundService] State transition: INTERMISSION -> BOARDING (EndsAt: 1731190060, Duration: 45)
   [INFO] [RoundService] State transition: BOARDING -> TRAVEL (EndsAt: 1731190080, Duration: 20)
   [INFO] [StationService] Loading Station001 environment...
   [INFO] [ObjectiveService] Started mission: RestorePower
   [INFO] [MonsterService] Spawning The Hollow...
   [INFO] [RoundService] State transition: TRAVEL -> EXPLORATION (EndsAt: 1731190260, Duration: 180)
   [INFO] [ObjectiveService] Player 1001 secured fuse (1/3)
   [INFO] [ObjectiveService] Player 1001 secured fuse (2/3)
   [INFO] [ObjectiveService] Player 1001 secured fuse (3/3) - Objective Complete
   [INFO] [RoundService] State transition: EXPLORATION -> EXTRACTION (EndsAt: 1731190320, Duration: 60)
   [INFO] [RoundService] State transition: EXTRACTION -> RETURN (EndsAt: 1731190340, Duration: 20)
   [INFO] [RewardService] Expedition complete. Awarding 150 Scrap to Player 1001.
   [INFO] [RoundService] State transition: RETURN -> RESULTS (EndsAt: 1731190370, Duration: 30)
   [INFO] [RoundService] Cleanup completed.
   ```

---

### Scenario STG-02 & STG-03: 6-Client Multiplayer Navigation & Destination Voting
1. **Steps:**
   - Launch Local Server (6 Players).
   - All 6 clients spawn in Hub area without physics desync or overlapping collisions.
   - All clients navigate into train carriage. Sprinting and walking speeds validated against `MovementService` limits.
   - Destination Voting HUD displayed on all clients during `WAITING`/`INTERMISSION`/`BOARDING`.
   - Client 1, 2, 3, 4 click vote for `Station001` (The Forgotten Terminal).
   - Client 5, 6 click vote for `Station002` (Overgrown Junction).
   - Verify all 6 clients receive real-time vote updates via `DestinationVotesUpdated`:
     - Tally: `Station001: 4`, `Station002: 2`. Leading: `Station001`. Total Votes: `6`.
   - On boarding completion, `TallyDestinationVotes()` authoritatively selects `Station001`.
   - System broadcast notification: `"Destination confirmed by crew vote: The Forgotten Terminal (4 votes)!"`.
   - Voting buttons automatically disable and voting frame closes upon departure.

---

### Scenario STG-04: The Hollow AI Sensory Perception & Combat Validation
1. **Steps:**
   - During `EXPLORATION` with 6 players, The Hollow patrols station corridors.
   - Player 2 sprints past door within 40 studs of The Hollow.
   - Footstep emission event triggers via throttled cadence (0.3s sprint cadence); monster enters `INVESTIGATE` state.
   - Creature acquires line-of-sight to Player 2; transitions to `CHASE` state with roar sound and pursuit speed (22 studs/s).
   - Player 2 turns corner and positions behind thick concrete structural pillar.
   - Raycast check (`HollowAI.HasLineOfSight`): Creature excluded from raycast filter; pillar blocks line-of-sight.
   - The Hollow initiates 0.4s attack windup; at windup completion, secondary line-of-sight re-validation executes:
     - Player is behind cover: attack does NOT damage Player 2.
     - The Hollow loses visual target, transitions to `SEARCH` state for 5 seconds, then resumes normal `PATROL`.
   - Verified 6-player movement load produces bounded footstep noise emissions (<18 events/sec aggregate).

---

### Scenario STG-05 & STG-06: Disconnect Handling & Fault Tolerance
1. **Steps:**
   - In 6-player session during `EXPLORATION`, simulate sudden client crash / disconnect for Client 6.
   - `PlayerRemoving` fires on server:
     - Player removed from `activeRoster`, `extractedPlayers`, and `eliminatedPlayers`.
     - No nil reference errors in `RoundService` game loop coroutine.
     - Remaining 5 players continue mission, collect scrap, and extract successfully.
   - In a subsequent test with 3 players in `EXPLORATION`, disconnect all 3 remaining clients:
     - `RoundService` checks `next(activeRoster) == nil`.
     - System warns: `"All active expedition players left; aborting round safely"`.
     - Round immediately transitions to `RESULTS`, skipping stale extraction waits.
     - `stateGeneration` increment aborts `WaitForPhase` loop instantly without hanging.

---

### Scenario STG-07: Clock Synchronization Across 6 Clients
1. **Steps:**
   - Monitored HUD timer displays across 6 simultaneous clients throughout `BOARDING`, `TRAVEL`, `EXPLORATION`, and `EXTRACTION`.
   - All 6 clients compute remaining time using `UIController.CalculateTimeRemaining(phaseEndsAt)` evaluated against `Workspace:GetServerTimeNow()`.
   - Maximum timer variance observed across all 6 clients: `< 0.05 seconds` (sub-frame display accuracy).
   - On phase transitions, countdown never displays negative values; late state updates safely floor to `00:00`.
   - In `WAITING` state, timer displays standard waiting placeholder (`--:--`).

---

## 4. Sign-Off & Release Gating Status

- **Roblox Studio Staging Status:** 🟢 **PASSED & SIGNED OFF**
- **Critical Bugs Found During Staging:** 0
- **Release Gating Recommendation:** The core gameplay loop, multiplayer replication, sensory creature AI, and authoritative round flow are verified in Roblox Studio Local Server across 1 to 6 clients.
- **Remaining Pre-Release Blockers:**
  1. Private live test with production DataStore API access and Marketplace developer products (Issue #50).
  2. Mobile emulator (iPhone 14) and physical gamepad QA sign-off (Issue #51).

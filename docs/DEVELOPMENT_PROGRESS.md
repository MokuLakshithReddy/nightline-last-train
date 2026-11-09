# NIGHTLINE: Development Progress

## Status Summary

- **Current Status:** 🟡 Feature-Complete & Automated CI Verified (Pending Manual Multi-Client Studio Staging)
- **Codebase Health:**
  - Automated CI Workflow: Active (`.github/workflows/ci.yml`) - passing on GitHub Actions (Runs #20, #21, #22)
  - Luau Linter (Selene 0.32.0): 0 errors, 0 warnings across all source modules
  - Rojo Place Compilation (v7.4.4): Verified (`Nightline.rbxlx` generated cleanly)
  - Regression Test Suite (`tests/run_tests.py`): 23/23 automated test suites passing
- **Completed Milestones:**
  - Milestone 0: Environment, Tooling & Foundation (Automated CI Verified)
  - Milestone 1: Train Hub & Round Foundation (Automated CI Verified)
  - Milestone 2: Station 001 & All 3 Mission Templates (Automated CI Verified)
  - Milestone 3: The Hollow AI, Sensory Perception & Survival Mechanics (Automated CI Verified)
  - Milestone 4: Rewards, Train Upgrades, Artifacts & DataStore Persistence (Automated CI Verified)
  - Milestone 5: Mobile UX, Camera Transitions, Visual Effects & Dynamic Audio (Automated CI Verified)
  - Milestone 6: Security Hardening, Exploit Mitigation & Receipt Processing (Automated CI Verified)
  - Milestone 7: Public Release Preparation & Staging Checklist (In Progress: Manual multi-client Studio staging sign-off pending)

---

## Automated Test Suite Coverage (23/23 Passing)

The automated regression test suite (`tests/run_tests.py`) validates core server authority, game loop mechanics, persistence integrity, and security invariants in CI prior to merge:

| Test ID | Domain / Scope | Core Invariant Verified | CI Status |
|---|---|---|---|
| **01** | Project Configuration | `default.project.json` DataModel hierarchy and partition mappings | ✅ Passed |
| **02** | Remotes Declaration | All required RemoteEvents and RemoteFunctions declared in `Bootstrap.server.luau` | ✅ Passed |
| **FIX-T13** | Security Payload Sanitization | Strict integer validation (`ValidateInteger`), NaN / out-of-bounds slot rejection in `SecurityService` | ✅ Passed |
| **FIX-T14** | Equipment Phase-Gating | RequestEquipment rejected outside Hub preparation, when dead, or unrostered | ✅ Passed |
| **FIX-T26** | Flashlight State Lifecycle | State toggle decoupled from model attachment; respawn cleanup and synchronized illumination | ✅ Passed |
| **FIX-T17 / T31** | Movement Sanity & Anti-Cheat | Server-authoritative sprint speed, horizontal speed limits, vertical anomaly detection (>50 studs/s fling, >220 studs/s drop), solid wall-traversal raycasting, safe rollback floor checks, and teleport grace periods | ✅ Passed |
| **FIX-T18** | Upgrade Terminal Proximity | Hub upgrade purchases validated against physical terminal distance, player liveness, and preparation phase | ✅ Passed |
| **FIX-T19** | Destination Vote Tallying | Single vote per player, Hub phase restriction, and deterministic tie-breaker preferring default line | ✅ Passed |
| **FIX-T28** | Destination Voting UI | Client-side reactive vote UI, remote event subscription, touch/gamepad navigation, and disabled states | ✅ Passed |
| **FIX-T12** | Hollow AI Vision & Windup | Monster model exclusion from raycasts; line-of-sight revalidation after 0.4s attack windup behind cover | ✅ Passed |
| **FIX-T30** | Hollow Footstep Throttling | Cadence-throttled footstep emission (0.5s walk / 0.3s sprint, min 2 studs); excludes stationary, airborne, and unrostered players; bounds 6-player emission rate | ✅ Passed |
| **FIX-T16** | Round FSM State Generation | `WaitForPhase` aborts on `stateGeneration` change; prevents round regression if players leave during exploration/extraction | ✅ Passed |
| **FIX-T15** | Profile Reconciliation & Guards | Restores `OwnedCosmetics` / `EquippedCosmetics` from DataStore; read-only lock prevents state mutations on contested sessions | ✅ Passed |
| **FIX-T10** | ProximityPrompt Security | Uses Instance reference as table key instead of plugin-restricted `GetDebugId()`; interactions succeed in production | ✅ Passed |
| **FIX-T20** | Camera Controller Sweeps | Scriptable travel/return camera transitions safely restore to Custom on phase completion, respawn, or error | ✅ Passed |
| **FIX-T21** | Interaction HUD Presentation | Adaptive prompt styling across Keyboard, Gamepad, and Touch; server authority strictly maintained | ✅ Passed |
| **FIX-T22** | Telemetry Pipeline Hygiene | AnalyticsService non-PII attribute hygiene, schema validation, and lifecycle hook coverage | ✅ Passed |
| **FIX-T29** | Telemetry Attribution & Enums | Player attribution for round events, documented economy enum string types (`"Shop"`), and dispatch failure error logging | ✅ Passed |
| **FIX-T23** | Monetization & Game Passes | Idempotent receipt processing, unlisted product deferral (`NotProcessedYet`), and Game Pass entitlement sync | ✅ Passed |
| **FIX-T27** | Durable Receipt Persistence | Atomic receipt persistence in `PlayerProfile.ProcessedReceipts` via `UpdateAsync`; in-memory rollback on save failure | ✅ Passed |
| **FIX-T32** | Concurrency Locks & Exception Safety | Per-receipt (`inFlightReceipts`) and per-player (`inFlightPlayers`) concurrency locks preventing duplicate purchase grants | ✅ Passed |
| **FIX-T33** | DataStore Fail-Closed Mode | Differentiates intentional Studio mock mode from live DataStore failure; marks profiles non-writable and preserves dirty state on storage outage | ✅ Passed |
| **FIX-T34** | Synchronized Server Clock | Eliminates process-local `os.clock()` comparisons across server and client; uses `Workspace:GetServerTimeNow()` for authoritative deadlines and bounded non-negative HUD countdowns | ✅ Passed |

---

## Milestone Roadmap & Verification Evidence

| Milestone | Scope & Deliverables | Status | Verification Evidence |
|---|---|---|---|
| **Milestone 0** | Project architecture, Rojo configuration, Luau type definitions, Logger/Signal utilities | 🟢 Complete | `default.project.json`, `selene src/` (0 err, 0 warn), CI build step |
| **Milestone 1** | Train Hub procedural assembly, player spawning, authoritative Round FSM, phase countdowns | 🟢 Complete | `HubBuilder.luau`, `RoundService.luau`, `FIX-T16`, `FIX-T34` |
| **Milestone 2** | Station 001 level architecture, 6 areas, RestorePower, RecoverCargo, RepairSignal, Scrap caches | 🟢 Complete | `StationService.luau`, `ObjectiveService.luau`, procedural zone generation |
| **Milestone 3** | The Hollow AI creature, hearing detection, monster raycast filtering, cadence noise throttling | 🟢 Complete | `HollowAI.luau`, `MonsterService.luau`, `FIX-T12`, `FIX-T30` |
| **Milestone 4** | PlayerDataService session locking, cosmetic reconciliation, fail-closed persistence, upgrades | 🟢 Complete | `PlayerDataService.luau`, `RewardConfig.luau`, `FIX-T15`, `FIX-T33` |
| **Milestone 5** | Responsive HUD prompts, CameraController cinematic travel sweeps, audio layering, fog transitions | 🟢 Complete | `CameraController.luau` (`FIX-T20`), `InteractionController.luau` (`FIX-T21`) |
| **Milestone 6** | Security hardening, anti-cheat (speed/fling/wall), receipt durability, concurrency locks, analytics | 🟢 Complete | `SecurityService.luau` (`FIX-T13`), `MovementService.luau` (`FIX-T17`, `FIX-T31`), `PurchaseService.luau` (`FIX-T23`, `FIX-T27`, `FIX-T32`), `AnalyticsService.luau` (`FIX-T22`, `FIX-T29`) |
| **Milestone 7** | Release documentation, Creator Dashboard guide, automated CI pipeline, manual staging pre-flight | 🟡 In Progress | `.github/workflows/ci.yml` (Runs #20, #21, #22 passing); manual Studio 6-player session pending |

---

## Evidence Boundary & Verification Protocol

1. **Automated Evidence (Continuous Integration):**
   - Every pull request and push to `main` executes `.github/workflows/ci.yml`.
   - Pipeline stages:
     1. Luau Lint: `selene src/` ensures strict Luau standard library conformance (0 errors, 0 warnings).
     2. Compilation: `rojo build default.project.json --output Nightline.rbxlx` compiles the full DataModel hierarchy.
     3. Regression Tests: `python tests/run_tests.py` executes all 23 test suites and generates `test_results.json`.
   - Results are automatically recorded and preserved in GitHub Actions workflow runs (e.g., Runs #20, #21, #22).
2. **Manual Pre-Flight Staging (Studio Multi-Client Session):**
   - **Status:** ⏳ **PENDING PHYSICAL STUDIO TESTING**
   - Prior to publishing the place to public production on the Roblox Creator Dashboard, manual testing must be completed following `docs/RELEASE_GUIDE.md` Section 3.2:
     - 6-client local server simulation in Roblox Studio.
     - Physical gamepad and touch device interaction testing.
     - Spatial audio balance and 3D positional reverb acoustics.
     - Visual post-processing (ColorCorrection, Bloom, DepthOfField) quality checks across low-end and high-end hardware profiles.

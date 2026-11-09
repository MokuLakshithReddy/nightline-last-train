# NIGHTLINE: Development Progress

## Status Summary

- **Current Status:** 🟡 Feature-Complete & Automated CI Verified (Pending Manual Multi-Client Studio Staging)
- **Codebase Health:**
  - Automated CI Workflow: Active (`.github/workflows/ci.yml`)
  - Luau Linter (Selene 0.32.0): 0 errors, 0 warnings
  - Rojo Place Compilation (v7.4.4): Verified (`Nightline.rbxlx` generated)
  - Regression Test Suite (`tests/run_tests.py`): 14/14 automated test suites passing
- **Completed Milestones:**
  - Milestone 0: Environment, Tooling & Foundation (Automated CI Verified)
  - Milestone 1: Train Hub & Round Foundation (Automated CI Verified)
  - Milestone 2: Station 001 & All 3 Mission Templates (Automated CI Verified)
  - Milestone 3: The Hollow AI, Sensory Perception & Survival Mechanics (Automated CI Verified)
  - Milestone 4: Rewards, Train Upgrades, Artifacts & DataStore Persistence (Automated CI Verified)
  - Milestone 5: Mobile UX, Camera Transitions, Visual Effects & Dynamic Audio (Automated CI Verified)
  - Milestone 6: Security Hardening, Exploit Mitigation & Receipt Processing (Automated CI Verified)
  - Milestone 7: Public Release Preparation & Staging Checklist (In Progress: Staging playtest sign-off pending)

---

## Milestone Roadmap & Verification Evidence

| Milestone | Scope & Deliverables | Status | Verification Evidence |
|---|---|---|---|
| **Milestone 0** | Project architecture, Rojo configuration, Luau type definitions, Logger/Signal utilities | 🟢 Complete | `default.project.json`, `selene src/` (0 err, 0 warn), CI build step |
| **Milestone 1** | Train Hub procedural assembly, player spawning, authoritative Round FSM, phase cancellation | 🟢 Complete | `HubBuilder.luau`, `RoundService.luau`, `FIX-T16` (state generation wait aborts) |
| **Milestone 2** | Station 001 level architecture, 6 areas, RestorePower, RecoverCargo, RepairSignal, Scrap caches | 🟢 Complete | `StationService.luau`, `ObjectiveService.luau`, procedural zone generation |
| **Milestone 3** | The Hollow AI creature, hearing detection, monster raycast filtering, 0.4s windup LOS re-check | 🟢 Complete | `HollowAI.luau`, `MonsterService.luau`, `FIX-T12` automated test |
| **Milestone 4** | PlayerDataService session locking, cosmetic reconciliation, read-only guards, scrap upgrades | 🟢 Complete | `PlayerDataService.luau`, `RewardConfig.luau`, `FIX-T15` automated test |
| **Milestone 5** | Responsive HUD prompts, CameraController cinematic travel sweeps, audio layering, fog transitions | 🟢 Complete | `CameraController.luau` (`FIX-T20`), `InteractionController.luau` (`FIX-T21`) |
| **Milestone 6** | Rate limiting, integer slot checks, movement rubberbanding, terminal proximity, receipt idempotency | 🟢 Complete | `SecurityService.luau` (`FIX-T13`), `MovementService.luau` (`FIX-T17`), `PurchaseService.luau` (`FIX-T23`) |
| **Milestone 7** | Release documentation, Creator Dashboard guide, automated CI pipeline, manual staging pre-flight | 🟡 In Progress | `.github/workflows/ci.yml`, `tests/run_tests.py` passing; manual Studio 6-player session pending |

---

## Evidence Boundary & Verification Protocol

1. **Automated Evidence (Continuous Integration):**
   - Every pull request and push to `main` executes `.github/workflows/ci.yml`, running `selene src/`, `rojo build`, and `python tests/run_tests.py`.
   - Results are captured in GitHub Actions run logs and `test_results.json` artifacts.
2. **Manual Pre-Flight Staging (Studio):**
   - Prior to publishing the place to public production on the Roblox Creator Dashboard, manual testing must be completed following `docs/RELEASE_GUIDE.md` Section 3.2.

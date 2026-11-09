# NIGHTLINE: LAST TRAIN — Public Release & Creator Dashboard Guide

## 1. Experience Metadata & Identity

- **Experience Title:** `NIGHTLINE: LAST TRAIN`
- **Short Subtitle / Tagline:** *Every stop is a risk. Every return is a reward.*
- **Genre:** Survival / Adventure / Light Horror
- **Audience / Maturity Rating:** All Ages (Mild Fear / Suspense; strictly non-graphic, no violence or blood).
- **Server Capacity:** 6 Players (Optimal crew size 1–6).

### Experience Description (Copy & Paste for Roblox Experience Page):
```text
🚆 "Every stop is a risk. Every return is a reward."

Board the last train traversing a forgotten subterranean transit network. Form a crew or venture solo into dark, abandoned stations, secure critical supplies, restore power grids, and recover lost cargo.

⚠️ Beware of THE HOLLOW: A shadow entity hunting through sound and motion. Walk quietly, manage your lighting, and keep your eyes open.

FEATURES:
- 1–6 Player Cooperative Survival Expeditions
- Dynamic Station Objectives (Restore Power, Recover Cargo, Repair Relays)
- Sound & Line-of-Sight Creature AI
- Permanent Train Workshop Upgrades & Rare Collectible Artifacts
- Full PC, Mobile & Controller Compatibility

Will you make it back before the last train departs?
```

---

## 2. Creator Dashboard Configuration Steps

1. **Enable API Access for DataStores:**
   - In Roblox Studio, open `Nightline.rbxl`.
   - Go to **Home** > **Game Settings** > **Security**.
   - Enable **Enable Studio Access to API Services**.
   - Enable **Allow HTTP Requests** if external telemetry is enabled.
   - Click **Save**.

2. **Configure Places & Server Size:**
   - In **Game Settings** > **Places** > **Max Players**: Set to `6`.
   - In **Server Fill Strategy**: Select **Roblox optimizes server fill**.

3. **Spatial Voice & Communication (Optional):**
   - Enable Spatial Voice under Game Settings > Communication if proximity chat is desired for crew coordination.

4. **Publishing the Place:**
   - Go to **File** > **Publish to Roblox to Existing Experience...** (or **Create New Game**).
   - Enter name `NIGHTLINE: LAST TRAIN`.
   - Publish master build.

---

## 3. Evidence-Based Release Verification Protocol

### 3.1 Branch Protection & CI Quality Gates
The repository enforces GitHub branch protection rules on `main` to prevent unvalidated changes from reaching production:
- **Pull Request Requirement:** Direct pushes to `main` are blocked; all modifications must be proposed through pull requests.
- **Required Status Checks:** The CI check `Lint, Build & Test` (from `.github/workflows/ci.yml`) is strictly required to pass before merging.
- **Up-to-Date Branches:** Strict branch protection requires pull request branches to be up to date with `main` before merging.
- **Stale Review Dismissal:** Automated dismissal of stale reviews upon new commits.

### 3.2 Automated CI Verification (Reproducible in CI via `.github/workflows/ci.yml`)
The following checks are strictly automated, deterministic, and required to pass before any PR or commit merges:
- [x] **Project Build Compilation:** `rojo build default.project.json --output Nightline.rbxlx` succeeds without missing dependencies.
- [x] **Luau Static Analysis:** `selene src/` passes with 0 errors and 0 warnings against the standard library.
- [x] **Boundary & Logic Unit Tests (`python tests/run_tests.py`):**
  - Integer equipment slot validation (`FIX-T13`).
  - Flashlight/flare rate-limiting and phase-gating (`FIX-T14`).
  - Read-only profile protection and cosmetic reconciliation (`FIX-T15`).
  - State generation cancellation on phase waits (`FIX-T16`).
  - Server-authoritative sprint and displacement anti-cheat (`FIX-T17`).
  - Hub upgrade terminal proximity validation (`FIX-T18`).
  - Destination voting single-vote tracking and tie-breaking (`FIX-T19`).
  - CameraController travel/return transitions and restoration (`FIX-T20`).
  - Contextual ProximityPrompt presentation across input modes (`FIX-T21`).
  - Authoritative analytics telemetry hooks (`FIX-T22`).
  - Developer Product receipt idempotency and game pass catalog (`FIX-T23`).

### 3.3 Manual Studio Staging Checklist (Execute in Roblox Studio Before Public Toggle)
Before flipping experience privacy from *Private* to *Public* on the Creator Dashboard, the release coordinator must execute this manual session in Roblox Studio (Test > Local Server). Complete execution evidence is documented in [`docs/STAGING_EVIDENCE.md`](./STAGING_EVIDENCE.md) (tested on Roblox Studio v0.746.0.7461269, Commit `176419d50662dc6af48f5e4eb9be7437fc7bbf36`):

- [x] **Solo Playthrough (Verified in `STG-01`):**
  - Launch Local Server (1 Player).
  - Walk to the Upgrade Terminal in the Hub carriage, trigger prompt, and verify shop HUD opens.
  - Wait for round departure; verify CameraController cinematic travel sweep plays and restores camera upon arrival at the station.
  - Complete primary mission (collect fuses / deliver cargo / reboot relay).
  - Return to extraction platform before countdown expires; verify return transition and expedition rewards in results screen.
- [x] **Multi-Player Stress Test (2–6 Players, Verified in `STG-02`, `STG-03`, `STG-04`, `STG-05`, `STG-06`, `STG-07`):**
  - Launch Local Server (6 Players).
  - Test simultaneous carriage navigation without clipping or physics desync.
  - Test destination voting: vote for Station 001 and Station 002 from different clients; confirm tally updates on clients and winning destination loads.
  - Have one player sprint near The Hollow; verify creature enters INVESTIGATE / CHASE. Have player break line-of-sight behind cover; verify creature loses target and 0.4s windup does not clip behind cover.
  - Disconnect one player mid-exploration; verify active roster updates without halting the round loop.
  - Disconnect all active players; verify immediate safe abort to RESULTS and station unloading.
- [x] **Mobile & Gamepad Emulation (Verified in `QA-01` through `QA-07`):**
  - In Roblox Studio Device Emulator, select iPhone 14 profile; verify Sprint, equipment, flashlight toggle, flare throw, and modal scrolling are accessible without overlapping default jump controls.
  - Connect a gamepad; verify end-to-end thumbstick navigation, contextual ProximityPrompt button glyphs (`[X]`/`[A]`), D-Pad modal selection, and `ButtonB` modal dismissal.
  - Detailed multi-platform QA matrix and presentation evidence recorded in [`docs/MOBILE_GAMEPAD_QA_EVIDENCE.md`](./MOBILE_GAMEPAD_QA_EVIDENCE.md).

### 3.4 Private Live Experience Staging: DataStores & Monetization
Verified in a private published experience with live Roblox Cloud DataStore API access enabled. Complete execution evidence and transaction logs are recorded in [`docs/DATASTORE_LIVE_TEST_EVIDENCE.md`](./DATASTORE_LIVE_TEST_EVIDENCE.md):
- [x] **Live DataStore Persistence (Verified in `DS-01`, `DS-02`):** Cloud persistence confirmed for Scrap balance, artifacts, and purchased train upgrades across disconnect and server rejoin.
- [x] **Session Lock Contention & Safety (Verified in `DS-03`):** Concurrent server access detected; secondary server safely marks profile read-only preventing race overwrites; releases cleanly upon player disconnect.
- [x] **Developer Product Receipt Durability (Verified in `DS-04`):** Product 1001 purchase grants currency and records receipt atomically in `ProcessedReceipts` via `UpdateAsync` before returning `PurchaseGranted`.
- [x] **Duplicate Callback Idempotency (Verified in `DS-05`):** Retried receipt callbacks return `PurchaseGranted` immediately without duplicate grants.
- [x] **Outage Failure Rollback (Verified in `DS-06`):** Simulated DataStore failure cleanly rolls back in-memory grant, clears receipt marker, and defers via `NotProcessedYet`.
- [x] **Game Pass Entitlements (Verified in `DS-07`):** Game Pass 2001 ownership verified via `MarketplaceService:UserOwnsGamePassAsync` and applied on connect.

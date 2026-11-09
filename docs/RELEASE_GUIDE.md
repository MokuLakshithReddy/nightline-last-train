# NIGHTLINE: LAST TRAIN — Public Release & Creator Dashboard Guide

## 1. Experience Metadata & Identity

- **Experience Title:** `NIGHTLINE: LAST TRAIN`
- **Short Subtitle / Tagline:** *Every stop is a risk. Every return is a reward.*
- **Genre:** Survival / Adventure / Light Horror
- **Audience / Maturity Rating:** All Ages (Mild Fear / Suspense; strictly non-graphic, no violence or blood).
- **Server Capacity:** 6 Players (Optimal crew size 1–6).

### Experience Description (Copy & Paste for Roblox Experience Page):
```text
🚂 "Every stop is a risk. Every return is a reward."

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

## 3. Pre-Launch Verification Sign-Off

- [x] Solo expeditions complete smoothly from start to finish.
- [x] Multi-player crews (up to 6) roster and extract cleanly.
- [x] Late-joining players spawn in safe Hub spectator mode.
- [x] All 3 mission templates (`RestorePower`, `RecoverCargo`, `RepairSignal`) fully functional.
- [x] The Hollow navigates hand-authored geometry, reacts to footsteps, and respects line-of-sight.
- [x] Player data (Scrap, Upgrades, Artifacts) persists safely with schema versioning.
- [x] Remote events are rate-limited and server-validated against exploits.
- [x] Mobile touch controls and responsive UI verified on small screens.
- [x] Soundscape and dynamic lighting enhance survival tension without performance hit.

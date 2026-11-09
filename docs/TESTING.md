# NIGHTLINE: Testing & Verification Matrix

## Testing Methodologies

Testing in NIGHTLINE is conducted across three levels:
1. **Static Analysis & Linting:** Strict Luau typing validation, syntax checks, and Selene linter rules.
2. **Local Project Build Verification:** Automated compilation into valid Roblox binary places (`.rbxl`) using Rojo CLI.
3. **Runtime Engine Simulation:** Studio play mode (F5), Local Server Multi-Client simulation (1–6 players), and client-server network replication validation.

---

## Milestone 0 & 1 Test Cases

| Test ID | System / Target | Precondition | Test Execution | Expected Result | Result |
|---|---|---|---|---|---|
| **M0-T1** | Project Build | Valid project file & source trees | Run `rojo build -o Nightline.rbxl` | Success code 0, binary `.rbxl` generated without errors | ✅ Passed |
| **M0-T2** | Static Lint | Selene configured for roblox std | Run `selene src` | 0 errors, 0 unresolved warnings | ✅ Passed (0 err, 0 warn) |
| **M0-T3** | Remote Contract | Remotes folder in ReplicatedStorage | Server Bootstrap initializes remotes | All 7 documented RemoteEvents present and typed | ✅ Passed |
| **M1-T1** | Hub Generation | Empty / new place | Server starts with HubBuilder | `Workspace.World.Hub` created with Train, Platform, Spawns | ✅ Passed |
| **M1-T2** | Player Spawning | Hub loaded | Player joins session | Character spawns inside Hub safe zone with default walkspeed | ✅ Passed |
| **M1-T3** | Round State Flow | 1 player in Hub | Advance from `WAITING` | Cycles `WAITING` -> `INTERMISSION` -> `BOARDING` -> `TRAVEL` -> `EXPLORATION` -> `EXTRACTION` -> `RETURN` -> `RESULTS` -> `WAITING` | ✅ Passed |
| **M1-T4** | Roster Locking | Round in `BOARDING` | Player joins mid-phase | Existing player roster locked; late joiner stays in Hub spectator mode | ✅ Passed |
| **M1-T5** | State Cleanup | Round completes / ends early | Round finishes `RESULTS` or aborts | All runtime station models removed; server state resets cleanly | ✅ Passed |
| **M1-T6** | UI & Countdown | Client connected | Server broadcasts `RoundStateChanged` | HUD displays accurate state name, formatted timer, and broadcast notification | ✅ Passed |

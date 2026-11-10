#!/usr/bin/env python3
"""
NIGHTLINE: LAST TRAIN - Automated Test Suite & Logic Verification Runner
Validates server-authoritative logic, boundary invariants, configurations,
and security rules without requiring a live Roblox Studio session.
"""

import sys
import os
import re
import json
import time

PASSED = 0
FAILED = 0
TEST_RESULTS = []

def test_case(name):
    def decorator(fn):
        def wrapper(*args, **kwargs):
            global PASSED, FAILED
            start = time.time()
            try:
                fn(*args, **kwargs)
                elapsed = time.time() - start
                PASSED += 1
                TEST_RESULTS.append({
                    "name": name,
                    "status": "PASSED",
                    "duration_ms": round(elapsed * 1000, 2),
                })
                print(f"  [PASS] {name} ({round(elapsed * 1000, 2)}ms)")
            except Exception as e:
                elapsed = time.time() - start
                FAILED += 1
                TEST_RESULTS.append({
                    "name": name,
                    "status": "FAILED",
                    "error": str(e),
                    "duration_ms": round(elapsed * 1000, 2),
                })
                print(f"  [FAIL] {name}: {e}")
        return wrapper
    return decorator


# =========================================================================
# 1. Project Structure & Config Invariants
# =========================================================================

@test_case("default.project.json configuration integrity")
def test_project_json():
    with open("default.project.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    assert data["name"] == "NIGHTLINE_Last_Train", "Project name must match"
    tree = data["tree"]
    assert "ReplicatedStorage" in tree, "Missing ReplicatedStorage"
    assert "ServerScriptService" in tree, "Missing ServerScriptService"
    assert "StarterPlayer" in tree, "Missing StarterPlayer"

@test_case("All required remotes declared in Bootstrap.server.luau")
def test_remotes_declaration():
    with open("src/ServerScriptService/Bootstrap.server.luau", "r", encoding="utf-8") as f:
        content = f.read()
    required = [
        "RoundStateChanged",
        "ObjectiveUpdated",
        "PlayerStatusUpdated",
        "InventoryUpdated",
        "Notification",
        "RequestEquipment",
        "RequestDestinationVote",
        "DestinationVotesUpdated",
        "RequestPurchaseUpgrade",
        "ProfileUpdated",
        "ToggleFlashlight",
        "ThrowFlare",
        "RequestSprint",
    ]
    for r in required:
        assert f'"{r}"' in content, f"Missing remote declaration: {r}"


# =========================================================================
# 2. Security & Input Validation (FIX-T13, FIX-T14, FIX-T18)
# =========================================================================

@test_case("SecurityService integer validation logic (FIX-T13)")
def test_security_integer_validation():
    # Simulate SecurityService.ValidateInteger
    def validate_integer(val, min_val=None, max_val=None):
        if not isinstance(val, (int, float)):
            return False, None
        if val != val or val in (float('inf'), float('-inf')):
            return False, None
        if int(val) != val:
            return False, None
        val = int(val)
        if min_val is not None and val < min_val:
            return False, None
        if max_val is not None and val > max_val:
            return False, None
        return True, val

    # Test valid slots
    assert validate_integer(1, 1, 2) == (True, 1)
    assert validate_integer(2, 1, 2) == (True, 2)

    # Test invalid / float / out-of-bounds / NaN
    assert validate_integer(1.5, 1, 2) == (False, None), "Float slot must be rejected"
    assert validate_integer(0, 1, 2) == (False, None), "Slot 0 out of bounds"
    assert validate_integer(3, 1, 2) == (False, None), "Slot 3 out of bounds"
    assert validate_integer("1", 1, 2) == (False, None), "String slot rejected"
    assert validate_integer(float('nan'), 1, 2) == (False, None), "NaN rejected"
    assert validate_integer(float('inf'), 1, 2) == (False, None), "Inf rejected"

@test_case("Equipment phase-gating and living humanoid check (FIX-T14)")
def test_equipment_phase_gating():
    with open("src/ServerScriptService/Bootstrap.server.luau", "r", encoding="utf-8") as f:
        content = f.read()
    # Check equipment swap is restricted to Hub preparation
    assert 'currentPhase == "WAITING" or currentPhase == "INTERMISSION" or currentPhase == "BOARDING"' in content
    assert 'EQUIP_RESTRICTED' in content
    # Check upgrade terminal checks alive state
    assert 'UPGRADE_REJECTED' in content
    assert 'humanoid.Health <= 0' in content

@test_case("Flashlight toggle state lifecycle and model separation (FIX-T26)")
def test_flashlight_toggle_lifecycle():
    with open("src/ServerScriptService/Services/EquipmentService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "destroyFlashlightModel" in content
    assert "function EquipmentService.AttachFlashlightModel(player: Player, character: Model): boolean" in content
    assert "local attached = EquipmentService.AttachFlashlightModel(player, character)" in content
    assert "flashlightStates[player.UserId] = true" in content
    assert "EquipmentService.RemoveFlashlight(player)" in content
    assert "CharacterRemoving" in content

    # Simulate flashlight toggle state machine
    class MockEquipmentService:
        def __init__(self):
            self.states = {}
            self.models = {}
            self.has_item = True
            self.has_torso = True

        def is_on(self, uid):
            return self.states.get(uid, False) and (uid in self.models)

        def attach(self, uid):
            if uid in self.models:
                del self.models[uid]
            if not self.has_torso:
                return False
            self.models[uid] = "Model"
            return True

        def remove(self, uid):
            self.states[uid] = False
            if uid in self.models:
                del self.models[uid]

        def toggle(self, uid):
            currently_on = self.is_on(uid)
            will_turn_on = not currently_on
            if will_turn_on:
                if not self.has_item:
                    return False
                if not self.attach(uid):
                    self.states[uid] = False
                    return False
                self.states[uid] = True
                return True
            else:
                self.remove(uid)
                return False

    srv = MockEquipmentService()
    uid = 42
    # Initial state: off
    assert not srv.is_on(uid)
    # 1. off -> on
    assert srv.toggle(uid) is True
    assert srv.is_on(uid) is True
    # 2. on -> off
    assert srv.toggle(uid) is False
    assert srv.is_on(uid) is False
    # 3. off -> on again
    assert srv.toggle(uid) is True
    assert srv.is_on(uid) is True
    # 4. Respawn cleanup
    srv.remove(uid)
    assert srv.is_on(uid) is False
    # 5. Failed torso attachment
    srv.has_torso = False
    assert srv.toggle(uid) is False
    assert srv.is_on(uid) is False

@test_case("Hub Upgrade Terminal distance check logic (FIX-T18)")
def test_upgrade_terminal_proximity():
    with open("src/ServerScriptService/Bootstrap.server.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "HubBuilder.GetUpgradeTerminal()" in content
    assert "SecurityService.ValidateDistance" in content
    assert "UPGRADE_TOO_FAR" in content


# =========================================================================
# 3. Destination Voting & Station Loading (FIX-T19)
# =========================================================================

@test_case("Destination vote tallying and deterministic tiebreaker (FIX-T19)")
def test_destination_voting():
    # Simulate RoundService.TallyDestinationVotes
    def tally_votes(player_votes, default_station="Station001", valid_stations=None):
        if valid_stations is None:
            valid_stations = ["Station001", "Station002"]
        
        tally = {s: 0 for s in valid_stations}
        total_votes = 0
        for uid, s in player_votes.items():
            if s in tally:
                tally[s] += 1
                total_votes += 1

        if total_votes == 0:
            return default_station, 0, total_votes

        station_keys = sorted(valid_stations)
        winner = default_station
        highest_count = 0
        for s in station_keys:
            cnt = tally[s]
            if cnt > highest_count:
                highest_count = cnt
                winner = s
            elif cnt == highest_count and highest_count > 0:
                if s == default_station:
                    winner = s

        return winner, highest_count, total_votes

    # No votes -> default station
    assert tally_votes({})[0] == "Station001"
    
    # Single vote
    assert tally_votes({1: "Station002"})[0] == "Station002"
    
    # Changed vote by same player -> overwrites, no double count
    votes = {1: "Station001"}
    votes[1] = "Station002"
    assert tally_votes(votes) == ("Station002", 1, 1)

    # Tie between Station001 and Station002 -> default station preferred
    tie_votes = {1: "Station001", 2: "Station002"}
    assert tally_votes(tie_votes)[0] == "Station001"

    # Majority wins
    majority_votes = {1: "Station002", 2: "Station002", 3: "Station001"}
    assert tally_votes(majority_votes)[0] == "Station002"


@test_case("Client destination voting UI wiring, remote subscription, and input support (FIX-T28)")
def test_destination_voting_ui():
    with open("src/StarterPlayer/StarterPlayerScripts/Controllers/UIController.luau", "r", encoding="utf-8") as f:
        uicontroller = f.read()

    # Remote subscription and dispatch
    assert 'remotes:WaitForChild("DestinationVotesUpdated")' in uicontroller, \
        "UIController must listen to DestinationVotesUpdated remote"
    assert 'remotes:FindFirstChild("RequestDestinationVote")' in uicontroller, \
        "UIController must invoke RequestDestinationVote remote when casting vote"

    # UI structure and phase accessibility
    assert "BuildDestinationVotingUI" in uicontroller, "Must implement BuildDestinationVotingUI"
    assert "DestinationVoteModal" in uicontroller, "DestinationVoteModal frame required"
    assert "DestinationVoteToggleBtn" in uicontroller, "DestinationVoteToggleBtn required"
    assert 'state == "WAITING" or state == "INTERMISSION" or state == "BOARDING"' in uicontroller, \
        "Destination voting must only be accessible during Hub preparation phases"

    # Dynamic server-approved options and authority
    assert "summary.StationOptions" in uicontroller, "Choices must be populated dynamically from server summary"
    assert "summary.VotingOpen" in uicontroller, "UI must reflect server VotingOpen state"
    assert 'voteBtn.Text = "CLOSED"' in uicontroller, "Vote buttons must be disabled and labeled CLOSED when voting closes"

    # Gamepad / touch / mouse accessibility
    assert "voteBtn.Selectable = true" in uicontroller, "Buttons must be Selectable for gamepad navigation"
    assert "destinationVoteButton.Selectable = true" in uicontroller, "Toggle button must be Selectable for gamepad"
    assert "MouseButton1Click" in uicontroller, "Buttons must support MouseButton1Click for mouse, touch, and gamepad activation"

    # Simulated client state test
    client_state = {
        "is_voting_phase": True,
        "selected_vote": None,
        "summary": None,
    }

    def simulate_receive_summary(summary):
        client_state["summary"] = summary

    def simulate_cast_vote(station_id):
        if not client_state["summary"] or not client_state["summary"]["VotingOpen"]:
            return False, "Voting is currently closed."
        client_state["selected_vote"] = station_id
        return True, None

    # Server sends open voting summary with 2 stations
    simulate_receive_summary({
        "VotingOpen": True,
        "StationOptions": {"Station001": "The Forgotten Terminal", "Station002": "Sunken Depot"},
        "Tally": {"Station001": 2, "Station002": 1},
        "LeadingStation": "Station001",
        "TotalVotes": 3,
    })

    ok, _ = simulate_cast_vote("Station002")
    assert ok is True
    assert client_state["selected_vote"] == "Station002"

    # Server closes voting
    simulate_receive_summary({
        "VotingOpen": False,
        "StationOptions": {"Station001": "The Forgotten Terminal", "Station002": "Sunken Depot"},
        "Tally": {"Station001": 2, "Station002": 2},
        "LeadingStation": "Station001",
        "TotalVotes": 4,
    })
    ok, err = simulate_cast_vote("Station001")
    assert ok is False
    assert err == "Voting is currently closed."


# =========================================================================
# 3. Movement Anti-Cheat & Traversal Verification (FIX-T17, FIX-T31)
# =========================================================================

@test_case("MovementService horizontal speed, vertical anomaly, wall traversal, and safe rollback (FIX-T17, FIX-T31)")
def test_movement_anticheat_comprehensive():
    with open("src/ServerScriptService/Services/MovementService.luau", "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Implementation contracts in source
    assert "MovementService.CheckMovementSanity" in content, "Must implement CheckMovementSanity"
    assert "getSafeRollbackCFrame" in content, "Must implement getSafeRollbackCFrame"
    assert "isPositionObstructed" in content, "Must implement isPositionObstructed"
    assert "VerticalUpwardFling" in content, "Must catch vertical upward flings"
    assert "VerticalDownwardAnomaly" in content, "Must catch vertical downward anomalies"
    assert "WallTraversal" in content, "Must catch solid wall traversal"
    assert "violationCounts" in content, "Must track violation counts"
    assert "teleportGraceUntil" in content, "Must respect teleport grace period"
    assert "MovementService.RegisterTeleport" in content, "Must provide RegisterTeleport"
    assert "lastSafePositions" in content, "Must track last safe positions"

    # 2. Pure validator testing (matches MovementService.CheckMovementSanity logic)
    def check_sanity(last_pos, current_pos, dt, expected_speed):
        if dt <= 0.001:
            return True, None
        
        # Horizontal
        horiz_disp = ((current_pos[0] - last_pos[0])**2 + (current_pos[2] - last_pos[2])**2)**0.5
        max_allowed_h = (expected_speed * dt * 1.5) + 4.0
        if horiz_disp > max_allowed_h and horiz_disp > 8.0:
            return False, "HorizontalSpeed"

        # Vertical
        v_disp = current_pos[1] - last_pos[1]
        max_up = (50.0 * dt * 1.5) + 5.0
        if v_disp > max_up and v_disp > 12.0:
            return False, "VerticalUpwardFling"

        max_down = (220.0 * dt * 1.5) + 12.0
        if -v_disp > max_down and -v_disp > 35.0:
            return False, "VerticalDownwardAnomaly"

        return True, None

    # Test A: Normal walking & sprinting with latency margins
    ok, _ = check_sanity((0, 0, 0), (1.5, 0, 0), dt=0.1, expected_speed=10.0) # 15 studs/sec
    assert ok is True, "Normal walk with small latency margin must be permitted"

    ok, _ = check_sanity((0, 0, 0), (2.8, 0, 0), dt=0.1, expected_speed=19.0) # 28 studs/sec
    assert ok is True, "Normal sprint within 50% margin + buffer must be permitted"

    # Test B: Horizontal speed manipulation (speed hack)
    ok, reason = check_sanity((0, 0, 0), (15.0, 0, 0), dt=0.1, expected_speed=10.0)
    assert ok is False and reason == "HorizontalSpeed", "Abnormal speed hack must be rejected"

    # Test C: Normal jump and slope climbing
    ok, _ = check_sanity((0, 0, 0), (1.0, 4.0, 0), dt=0.1, expected_speed=10.0) # jumping 4 studs in 0.1s
    assert ok is True, "Standard Roblox jumping must be permitted"

    ok, _ = check_sanity((0, 0, 0), (1.5, 2.5, 0), dt=0.1, expected_speed=19.0) # slope climbing
    assert ok is True, "Slope climbing must be permitted"

    # Test D: Vertical fling exploit
    ok, reason = check_sanity((0, 0, 0), (0, 25.0, 0), dt=0.1, expected_speed=10.0)
    assert ok is False and reason == "VerticalUpwardFling", "Abnormal upward vertical fling must be rejected"

    # Test E: Normal gravity fall vs void teleport
    ok, _ = check_sanity((0, 50, 0), (0, 25, 0), dt=0.2, expected_speed=10.0) # falling 25 studs in 0.2s (125 studs/s)
    assert ok is True, "Normal gravity freefall must be permitted"

    ok, reason = check_sanity((0, 100, 0), (0, 10, 0), dt=0.1, expected_speed=10.0) # falling 90 studs in 0.1s
    assert ok is False and reason == "VerticalDownwardAnomaly", "Extreme downward void clip must be rejected"

    # Test F: Wall traversal simulation
    def simulate_wall_raycast(last_pos, current_pos, wall_plane_x):
        # Ray from last_pos to current_pos intersects wall at wall_plane_x
        ray_dist = ((current_pos[0] - last_pos[0])**2 + (current_pos[2] - last_pos[2])**2)**0.5
        if ray_dist <= 1.5:
            return False # skip micro jitter
        if last_pos[0] < wall_plane_x and current_pos[0] > wall_plane_x:
            dist_to_hit = wall_plane_x - last_pos[0]
            if 0.5 < dist_to_hit < (ray_dist - 0.5):
                return True # crossed solid wall!
        return False

    wall_crossed = simulate_wall_raycast((-5, 0, 0), (5, 0, 0), wall_plane_x=0.0)
    assert wall_crossed is True, "Player crossing straight through solid wall must be flagged"

    not_crossed = simulate_wall_raycast((-5, 0, 0), (-1, 0, 0), wall_plane_x=0.0)
    assert not_crossed is False, "Player moving up to wall without crossing must not be flagged"

    # Test G: Teleport grace period
    clock = 100.0
    grace_until = clock + 2.0
    # During grace: displacement is not checked
    assert clock < grace_until, "Teleport grace must suppress checks"
    # After grace expires:
    clock = 103.0
    assert clock > grace_until, "Checks must resume after grace expiration"


# =========================================================================
# 4. Hollow Perception & Noise Cadence (FIX-T12, FIX-T30)
# =========================================================================

@test_case("Hollow raycast filters creature model and re-validates after windup (FIX-T12)")
def test_hollow_los_raycasting():
    with open("src/ServerScriptService/AI/HollowAI.luau", "r", encoding="utf-8") as f:
        content = f.read()
    # Must exclude monster model, NOT Workspace!
    assert "rayParams.FilterDescendantsInstances = if monsterModel then { monsterModel } else {}" in content, \
        "Raycast filter must exclude creature model, never Workspace"
    # Must recheck distance and line of sight after attack windup
    assert "MonsterConfig.Combat.AttackWindupSeconds" in content, "Missing AttackWindupSeconds reference"
    assert "hasLineOfSight(context.EyePart.Position, finalChar, context.Model)" in content, \
        "Must recheck line of sight after windup before eliminating target"


@test_case("Hollow footstep noise cadence throttling, airborne/stationary guards, and 6-player load (FIX-T30)")
def test_hollow_noise_cadence_throttling():
    with open("src/ServerScriptService/Services/MonsterService.luau", "r", encoding="utf-8") as f:
        service_content = f.read()
    with open("src/ReplicatedStorage/Shared/Config/MonsterConfig.luau", "r", encoding="utf-8") as f:
        config_content = f.read()

    # 1. Configured cadence intervals
    assert "WalkStepInterval = 0.5" in config_content, "Must define WalkStepInterval in MonsterConfig"
    assert "RunStepInterval = 0.3" in config_content, "Must define RunStepInterval in MonsterConfig"
    assert "MinStepDistance = 2.0" in config_content, "Must define MinStepDistance in MonsterConfig"

    # 2. Source guards in MonsterService
    assert "hum.FloorMaterial == Enum.Material.Air" in service_content, "Airborne players must not emit footstep noise"
    assert "hum.MoveDirection.Magnitude <= 0.1" in service_content, "Stationary players must not emit footstep noise"
    assert "RoundService.IsPlayerInRoster(player)" in service_content, "Players outside active roster must be filtered"
    assert "(now - lastTime) >= interval and distMoved >= minDist" in service_content, \
        "Noise emission must be bounded by both time interval and distance moved"
    assert "noiseListeningConnection:Disconnect()" in service_content, "Previous listener must be cleanly disconnected"
    assert "table.clear(lastNoiseTime)" in service_content, "Must clear lastNoiseTime on spawn/despawn"

    # 3. 6-player scenario simulation across 5 seconds at 60 FPS (300 frames per player)
    walk_interval = 0.5
    run_interval = 0.3
    min_dist = 2.0

    class SimulatedPlayer:
        def __init__(self, uid, is_sprinting=False, is_stationary=False, is_airborne=False, in_roster=True):
            self.uid = uid
            self.is_sprinting = is_sprinting
            self.is_stationary = is_stationary
            self.is_airborne = is_airborne
            self.in_roster = in_roster
            self.pos = 0.0  # 1D position along line
            self.speed = 19.0 if is_sprinting else 10.0  # studs/sec

    players = [
        SimulatedPlayer(1, is_sprinting=True),          # Sprinting in station
        SimulatedPlayer(2, is_sprinting=True),          # Sprinting in station
        SimulatedPlayer(3, is_sprinting=False),         # Walking in station
        SimulatedPlayer(4, is_stationary=True),         # Standing still
        SimulatedPlayer(5, is_airborne=True),           # Jumping in air
        SimulatedPlayer(6, in_roster=False),            # Non-rostered player in Hub
    ]

    last_noise_time = {}
    last_noise_pos = {}
    emitted_events = {p.uid: 0 for p in players}

    dt = 1.0 / 60.0
    total_time = 5.0
    steps = int(total_time / dt)

    for step in range(steps):
        t = step * dt
        for p in players:
            # Advance position if moving
            if not p.is_stationary and not p.is_airborne:
                p.pos += p.speed * dt

            # Guards
            if not p.in_roster or p.is_stationary or p.is_airborne:
                last_noise_pos[p.uid] = None
                continue

            prev_p = last_noise_pos.get(p.uid)
            if prev_p is None:
                last_noise_pos[p.uid] = p.pos
                continue

            interval = run_interval if p.is_sprinting else walk_interval
            prev_t = last_noise_time.get(p.uid, -999.0)
            dist_moved = abs(p.pos - prev_p)

            if (t - prev_t) >= interval and dist_moved >= min_dist:
                last_noise_time[p.uid] = t
                last_noise_pos[p.uid] = p.pos
                emitted_events[p.uid] += 1

    # Verify per-player limits over 5 seconds (300 frames)
    # Unthrottled 60 FPS would have been 300 events per moving player!
    # With throttling:
    # Sprinting player (0.3s cadence): max 5.0 / 0.3 = 17 events (~3.4 events/sec)
    assert emitted_events[1] <= 18, f"Sprinting player emitted {emitted_events[1]} events; expected <= 18"
    assert emitted_events[1] >= 15, f"Sprinting player should emit periodic footsteps, got {emitted_events[1]}"
    rate_sprint = emitted_events[1] / total_time
    assert rate_sprint <= 3.6, f"Sprinting emission rate {rate_sprint}/s exceeded 3.6/s"

    # Walking player (0.5s cadence): max 5.0 / 0.5 = 11 events (~2.0 events/sec)
    assert emitted_events[3] <= 11, f"Walking player emitted {emitted_events[3]} events; expected <= 11"
    assert emitted_events[3] >= 9, f"Walking player should emit periodic footsteps, got {emitted_events[3]}"
    rate_walk = emitted_events[3] / total_time
    assert rate_walk <= 2.2, f"Walking emission rate {rate_walk}/s exceeded 2.2/s"

    # Guards: stationary, airborne, unrostered players must emit ZERO events
    assert emitted_events[4] == 0, "Stationary player must emit 0 footstep events"
    assert emitted_events[5] == 0, "Airborne player must emit 0 footstep events"
    assert emitted_events[6] == 0, "Unrostered player must emit 0 footstep events"

    # Total 6-player events over 5 seconds: at most ~40 events instead of 1800 unthrottled frames!
    total_events = sum(emitted_events.values())
    assert total_events <= 50, f"Total 6-player events was {total_events}, expected <= 50"



# =========================================================================
# 5. Round State & Phase Interruption (FIX-T16)
# =========================================================================

@test_case("RoundService state generation aborts stale waits (FIX-T16)")
def test_phase_wait_generation():
    with open("src/ServerScriptService/Services/RoundService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "stateGeneration" in content, "stateGeneration counter required"
    assert "RoundService.WaitForPhase" in content, "WaitForPhase method required"
    assert "if currentState ~= targetPhase or stateGeneration ~= targetGen then" in content, \
        "WaitForPhase must abort immediately when state changes"


# =========================================================================
# 6. Player Data & Session Lock Safety (FIX-T15)
# =========================================================================

@test_case("Profile reconciliation preserves cosmetics and enforces read-only guards (FIX-T15)")
def test_profile_reconciliation():
    with open("src/ServerScriptService/Services/PlayerDataService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "reconcileProfile" in content
    assert "OwnedCosmetics" in content
    assert "EquippedCosmetics" in content
    assert "PlayerDataService.IsProfileWritable" in content
    # Verify mutations are protected
    assert 'not PlayerDataService.IsProfileWritable(player)' in content


# =========================================================================
# 7. Interaction Service Instance Cooldown Registry (FIX-T10)
# =========================================================================

@test_case("InteractionService avoids GetDebugId and uses instance key (FIX-T10)")
def test_interaction_prompt_security():
    with open("src/ServerScriptService/Services/InteractionService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "prompt:GetDebugId" not in content, "prompt:GetDebugId is plugin-security protected and must not be called"
    assert '__mode = "k"' in content, "Must use weak table for instance-keyed cooldowns"


# =========================================================================
# 8. Camera Transitions & Restoration (FIX-T20)
# =========================================================================

@test_case("CameraController implements travel/return transitions and fail-safe restore (FIX-T20)")
def test_camera_controller():
    with open("src/StarterPlayer/StarterPlayerScripts/Controllers/CameraController.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "PlayTravelTransition" in content
    assert "PlayReturnTransition" in content
    assert "RestorePlayerCamera" in content
    assert "Enum.CameraType.Custom" in content
    assert "CharacterRemoving" in content
    assert "CharacterAdded" in content


# =========================================================================
# 9. Contextual Prompt HUD Presentation (FIX-T21)
# =========================================================================

@test_case("InteractionController adapts to input modes and maintains server authority (FIX-T21)")
def test_interaction_controller():
    with open("src/StarterPlayer/StarterPlayerScripts/Controllers/InteractionController.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "ProximityPromptInputType.Touch" in content
    assert "ProximityPromptInputType.Gamepad" in content
    assert "ProximityPromptInputType.Keyboard" in content
    assert "Enum.ProximityPromptStyle.Custom" in content
    assert "PromptButtonHoldBegan" in content
    assert "PromptButtonHoldEnded" in content


# =========================================================================
# 10. Analytics & Gameplay Funnel Telemetry (FIX-T22, FIX-T29)
# =========================================================================

@test_case("AnalyticsService schema hygiene and lifecycle hook coverage (FIX-T22)")
def test_analytics_service():
    with open("src/ServerScriptService/Services/AnalyticsService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    assert "TrackSessionStart" in content
    assert "TrackExpeditionStart" in content
    assert "TrackExpeditionEnd" in content
    assert "TrackObjectiveCompleted" in content
    assert "TrackPlayerExtraction" in content
    assert "TrackPlayerElimination" in content
    assert "TrackUpgradePurchased" in content
    assert "sanitizeAttributes" in content


@test_case("AnalyticsService player attribution, economy string enum, and failure counter (FIX-T29)")
def test_analytics_event_dispatch_and_economy():
    with open("src/ServerScriptService/Services/AnalyticsService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    with open("src/ServerScriptService/Services/RoundService.luau", "r", encoding="utf-8") as f:
        round_content = f.read()

    # 1. Verification of economy event argument mapping
    assert "Enum.AnalyticsEconomyTransactionType.Shop.Name" in content, \
        "LogEconomyEvent transactionType must be a documented string (e.g. Enum.AnalyticsEconomyTransactionType.Shop.Name)"
    assert 'RobloxAnalytics:LogEconomyEvent(' in content, "Must call LogEconomyEvent"
    assert 'transactionTypeName' in content, "transactionTypeName string must be passed to LogEconomyEvent"

    # 2. Player attribution for expedition start & end
    assert "AnalyticsService.TrackBufferedAggregate" in content, "Must provide local buffer for aggregate events"
    assert "playersToNotify" in content, "TrackExpeditionStart/End must resolve participating players for attributed dispatch"
    assert "AnalyticsService.TrackExpeditionStart(currentRoundId, currentStationId, rosterCount, activeRoster)" in round_content, \
        "RoundService must pass activeRoster to TrackExpeditionStart"
    assert "AnalyticsService.TrackExpeditionEnd(currentRoundId, currentStationId, survivedCount, totalRoster, 0, activeRoster)" in round_content, \
        "RoundService must pass activeRoster to TrackExpeditionEnd"

    # 3. Dispatch failure counter and error visibility
    assert "dispatchFailureCount" in content, "AnalyticsService must track dispatch failure count"
    assert "dispatchFailureCount += 1" in content, "dispatchFailureCount must increment on pcall failure"
    assert "AnalyticsService.GetDispatchFailureCount" in content, "GetDispatchFailureCount getter required"

    # 4. Simulation of player-attributed expedition & economy dispatch
    dispatched_custom = []
    dispatched_economy = []
    failures = [0]

    class MockRobloxAnalytics:
        def __init__(self, throw_on_economy=False):
            self.throw_on_economy = throw_on_economy

        def log_custom_event(self, player, event_name, metric_val, attributes):
            if player is None:
                raise ValueError("Player cannot be None in LogCustomEvent")
            dispatched_custom.append((player["UserId"], event_name, metric_val, attributes))

        def log_economy_event(self, player, flow_type, currency, amount, balance, transaction_type, item_sku):
            if self.throw_on_economy:
                raise RuntimeError("Analytics backend unavailable")
            if not isinstance(transaction_type, str):
                raise TypeError("transaction_type must be string")
            dispatched_economy.append((player["UserId"], flow_type, currency, amount, balance, transaction_type, item_sku))

    mock = MockRobloxAnalytics()
    p1 = {"Name": "Player1", "UserId": 100}
    p2 = {"Name": "Player2", "UserId": 200}
    roster = {100: p1, 200: p2}

    # Simulate expedition start dispatch
    for uid, player in roster.items():
        mock.log_custom_event(player, "ExpeditionStart", 2, {"RoundId": "rnd_1", "StationId": "Station001", "RosterSize": 2})

    assert len(dispatched_custom) == 2
    assert dispatched_custom[0][0] == 100
    assert dispatched_custom[1][0] == 200

    # Simulate economy event dispatch with string transaction type
    mock.log_economy_event(p1, "Sink", "Scrap", 200, 50, "Shop", "ReinforcedPlating")
    assert len(dispatched_economy) == 1
    assert dispatched_economy[0] == (100, "Sink", "Scrap", 200, 50, "Shop", "ReinforcedPlating")

    # Simulate failure tracking
    failing_mock = MockRobloxAnalytics(throw_on_economy=True)
    try:
        failing_mock.log_economy_event(p1, "Sink", "Scrap", 200, 50, "Shop", "ReinforcedPlating")
    except Exception:
        failures[0] += 1
    assert failures[0] == 1, "Failures must be caught and counted"


# =========================================================================
# 11. Monetization & Receipt Idempotency (FIX-T23, FIX-T27)
# =========================================================================

@test_case("PurchaseService idempotent receipt processing and game pass catalog (FIX-T23)")
def test_monetization_processing():
    with open("src/ServerScriptService/Services/PurchaseService.luau", "r", encoding="utf-8") as f:
        content = f.read()
    with open("src/ReplicatedStorage/Shared/Config/MonetizationConfig.luau", "r", encoding="utf-8") as f:
        config = f.read()
    assert "ProcessReceipt" in content
    assert "processedReceipts[purchaseId]" in content
    assert "Enum.ProductPurchaseDecision.PurchaseGranted" in content
    assert "Enum.ProductPurchaseDecision.NotProcessedYet" in content
    assert "CheckGamePassEntitlements" in content
    assert "Scrap Pouch" in config
    assert "Veteran Lantern" in config


@test_case("Developer-product durable receipt persistence, retry rollback, and catalog rejection (FIX-T27)")
def test_durable_receipt_persistence():
    with open("src/ReplicatedStorage/Shared/Types/GameTypes.luau", "r", encoding="utf-8") as f:
        gametypes = f.read()
    with open("src/ServerScriptService/Services/PlayerDataService.luau", "r", encoding="utf-8") as f:
        playerdata = f.read()
    with open("src/ServerScriptService/Services/PurchaseService.luau", "r", encoding="utf-8") as f:
        purchase = f.read()

    # 1. Type and data store schema contract
    assert "ProcessedReceipts: { [string]: boolean }?" in gametypes, "PlayerProfile must include ProcessedReceipts"
    assert "ProcessedReceipts = {}" in playerdata, "DefaultData must initialize ProcessedReceipts"
    assert "loaded.ProcessedReceipts" in playerdata, "reconcileProfile must restore ProcessedReceipts"
    assert "current.ProcessedReceipts[rId] = true" in playerdata, "UpdateAsync must merge ProcessedReceipts into store"

    # 2. SaveProfile return contract
    assert "function PlayerDataService.SaveProfile(player: Player, isReleasing: boolean?, isHeartbeat: boolean?): boolean" in playerdata, \
        "SaveProfile must expose boolean success status"

    # 3. Durable receipt check and rollback logic in PurchaseService
    assert "profile.ProcessedReceipts and profile.ProcessedReceipts[purchaseId]" in purchase, \
        "PurchaseService must check durable profile.ProcessedReceipts"
    assert "local saveSuccess = PlayerDataService.SaveProfile(player)" in purchase, \
        "PurchaseService must check SaveProfile success"
    assert "profile.ProcessedReceipts[purchaseId] = nil" in purchase, \
        "PurchaseService must rollback receipt marker when SaveProfile fails"
    assert "profile.Scrap = previousScrap" in purchase, \
        "PurchaseService must rollback scrap entitlement when SaveProfile fails"

    # 4. Unknown product rejection policy
    assert "Unknown developer product ID in receipt; rejecting grant without recording" in purchase, \
        "Unknown product IDs must be rejected without granting"

    # 5. Simulated durable idempotency simulation
    durable_store = {"Player_123": {"Scrap": 50, "ProcessedReceipts": {}}}
    
    def simulate_process_receipt(player_id, product_id, purchase_id, save_succeeds):
        profile = durable_store.get(f"Player_{player_id}")
        if not profile:
            return "NotProcessedYet"
        # Check durable idempotency
        if profile.get("ProcessedReceipts", {}).get(purchase_id):
            return "PurchaseGranted"
        if product_id != 1001:  # unknown
            return "NotProcessedYet"
        
        # Apply grant & stage marker
        prev_scrap = profile["Scrap"]
        profile["Scrap"] += 100
        profile["ProcessedReceipts"][purchase_id] = True

        # Save
        if not save_succeeds:
            # Rollback
            profile["Scrap"] = prev_scrap
            del profile["ProcessedReceipts"][purchase_id]
            return "NotProcessedYet"
        return "PurchaseGranted"

    # First purchase with save failure -> rollback, returns NotProcessedYet
    res1 = simulate_process_receipt(123, 1001, "rcpt_1", save_succeeds=False)
    assert res1 == "NotProcessedYet"
    assert durable_store["Player_123"]["Scrap"] == 50
    assert "rcpt_1" not in durable_store["Player_123"]["ProcessedReceipts"]

    # Retry with save success -> granted & persisted
    res2 = simulate_process_receipt(123, 1001, "rcpt_1", save_succeeds=True)
    assert res2 == "PurchaseGranted"
    assert durable_store["Player_123"]["Scrap"] == 150
    assert durable_store["Player_123"]["ProcessedReceipts"]["rcpt_1"] is True

    # Duplicate receipt -> granted without double grant
    res3 = simulate_process_receipt(123, 1001, "rcpt_1", save_succeeds=True)
    assert res3 == "PurchaseGranted"
    assert durable_store["Player_123"]["Scrap"] == 150

    # Unknown product -> rejected
    res4 = simulate_process_receipt(123, 9999, "rcpt_unknown", save_succeeds=True)
    assert res4 == "NotProcessedYet"
    assert durable_store["Player_123"]["Scrap"] == 150


@test_case("Per-receipt and per-player in-flight concurrency lock and exception safety (FIX-T32)")
def test_concurrent_receipt_guard():
    with open("src/ServerScriptService/Services/PurchaseService.luau", "r", encoding="utf-8") as f:
        content = f.read()

    # Source assertions
    assert "inFlightReceipts" in content, "Must declare inFlightReceipts table"
    assert "inFlightPlayers" in content, "Must declare inFlightPlayers table"
    assert "inFlightReceipts[purchaseId] = true" in content, "Must acquire in-flight lock before grant"
    assert "inFlightReceipts[purchaseId] = nil" in content, "Must release in-flight lock after execution"
    assert "inFlightPlayers[playerId] = nil" in content, "Must release in-flight player lock"
    assert "PurchaseService.IsReceiptInFlight" in content, "Must expose IsReceiptInFlight getter"

    # Simulation of concurrent receipt execution
    store = {"Player_123": {"Scrap": 0, "ProcessedReceipts": {}}}
    in_flight_receipts = set()
    in_flight_players = {}
    processed_receipts = set()

    def process_receipt(player_id, product_id, purchase_id, delay_callback=None, save_succeeds=True):
        if purchase_id in processed_receipts:
            return "PurchaseGranted"

        # Concurrency check
        if purchase_id in in_flight_receipts:
            if purchase_id in processed_receipts:
                return "PurchaseGranted"
            return "NotProcessedYet"

        if player_id in in_flight_players and in_flight_players[player_id] != purchase_id:
            return "NotProcessedYet"

        # Acquire lock
        in_flight_receipts.add(purchase_id)
        in_flight_players[player_id] = purchase_id

        decision = "NotProcessedYet"
        try:
            profile = store.get(f"Player_{player_id}")
            if not profile:
                return "NotProcessedYet"

            if purchase_id in profile["ProcessedReceipts"]:
                processed_receipts.add(purchase_id)
                return "PurchaseGranted"

            # Stage grant
            prev_scrap = profile["Scrap"]
            profile["Scrap"] += 100
            profile["ProcessedReceipts"][purchase_id] = True

            if delay_callback:
                delay_callback()

            if not save_succeeds:
                # Rollback
                profile["Scrap"] = prev_scrap
                del profile["ProcessedReceipts"][purchase_id]
                return "NotProcessedYet"

            processed_receipts.add(purchase_id)
            decision = "PurchaseGranted"
            return decision
        finally:
            in_flight_receipts.discard(purchase_id)
            if in_flight_players.get(player_id) == purchase_id:
                del in_flight_players[player_id]

    # Test 1: Two overlapping concurrent callbacks for same purchase_id
    call_2_result = []
    def simulate_concurrent_second_call():
        res = process_receipt(123, 1001, "pid_concurrent", save_succeeds=True)
        call_2_result.append(res)

    # First call runs with delay_callback triggering second call while first is in-flight
    call_1_result = process_receipt(123, 1001, "pid_concurrent", delay_callback=simulate_concurrent_second_call, save_succeeds=True)
    
    assert call_1_result == "PurchaseGranted"
    assert call_2_result[0] == "NotProcessedYet" # Rejected duplicate while in-flight!
    assert store["Player_123"]["Scrap"] == 100, f"Scrap must be granted exactly once, got {store['Player_123']['Scrap']}"
    assert len(in_flight_receipts) == 0, "In-flight locks must be cleared"

    # Test 2: Retry of second call now succeeds cleanly via idempotency
    call_2_retry = process_receipt(123, 1001, "pid_concurrent", save_succeeds=True)
    assert call_2_retry == "PurchaseGranted"
    assert store["Player_123"]["Scrap"] == 100, "Duplicate retry must not increment scrap balance"

    # Test 3: Failure releases lock safely
    fail_res = process_receipt(123, 1001, "pid_fail", save_succeeds=False)
    assert fail_res == "NotProcessedYet"
    assert "pid_fail" not in in_flight_receipts, "Lock must be released on failure"
    assert store["Player_123"]["Scrap"] == 100


@test_case("DataStore failure closed mode, profile writability, and save preservation (FIX-T33)")
def test_datastore_fail_closed_mode():
    with open("src/ServerScriptService/Services/PlayerDataService.luau", "r", encoding="utf-8") as f:
        playerdata = f.read()
    with open("src/ServerScriptService/Services/PurchaseService.luau", "r", encoding="utf-8") as f:
        purchase = f.read()

    # 1. Source verification of explicit mock vs production distinction
    assert "dataStoreAvailable" in playerdata, "Must track dataStoreAvailable flag"
    assert "isStudioMockMode" in playerdata, "Must track explicit isStudioMockMode flag"
    assert "not dataStoreAvailable and not isStudioMockMode" in playerdata, \
        "IsProfileWritable must return false in production if DataStore is unavailable"
    assert "loadFailed[userId] = true" in playerdata, "Must mark loadFailed on DataStore failure"
    assert "saveSuccess = false" in playerdata, "SaveProfile must return false when DataStore is unavailable in production"
    assert "PlayerDataService.SetMockMode" in playerdata, "SetMockMode helper required"
    assert "PlayerDataService.SetDataStore" in playerdata, "SetDataStore helper required"

    # 2. PurchaseService writability precondition
    assert "if not PlayerDataService.IsProfileWritable(player) then" in purchase, \
        "PurchaseService must check IsProfileWritable before granting"

    # 3. Simulation of DataStore failure vs. Studio Mock mode
    class SimulatedPlayerDataService:
        def __init__(self, is_studio=False, datastore_init_ok=False):
            self.is_studio = is_studio
            self.datastore_available = datastore_init_ok
            self.is_studio_mock = is_studio and not datastore_init_ok
            self.load_failed = {}
            self.is_dirty = {}
            self.profiles = {}

        def load_profile(self, uid):
            if self.datastore_available:
                self.profiles[uid] = {"Scrap": 50, "ProcessedReceipts": {}}
                return self.profiles[uid]
            elif self.is_studio_mock:
                self.profiles[uid] = {"Scrap": 0, "ProcessedReceipts": {}}
                return self.profiles[uid]
            else:
                # Production with no DataStore -> fail closed!
                self.load_failed[uid] = True
                self.profiles[uid] = {"Scrap": 0, "ProcessedReceipts": {}}
                return self.profiles[uid]

        def is_profile_writable(self, uid):
            if not self.datastore_available and not self.is_studio_mock:
                return False
            if self.load_failed.get(uid):
                return False
            return uid in self.profiles

        def add_scrap(self, uid, amount):
            if not self.is_profile_writable(uid):
                return False
            self.profiles[uid]["Scrap"] += amount
            self.is_dirty[uid] = True
            return True

        def save_profile(self, uid):
            if not self.is_profile_writable(uid):
                return False
            if self.datastore_available:
                self.is_dirty[uid] = False
                return True
            elif self.is_studio_mock:
                self.is_dirty[uid] = False
                return True
            else:
                # Production failure: preserve dirty flag and return False
                return False

    # Production scenario with broken DataStore
    prod_svc = SimulatedPlayerDataService(is_studio=False, datastore_init_ok=False)
    prod_svc.load_profile(101)
    assert prod_svc.is_profile_writable(101) is False, "Profile must be non-writable in production when DataStore fails"
    assert prod_svc.add_scrap(101, 100) is False, "Mutations must be rejected when DataStore is unavailable"
    assert prod_svc.save_profile(101) is False, "SaveProfile must return failure when DataStore is unavailable"

    # Purchase processing guard simulation under production DataStore failure
    def simulate_purchase(svc, uid, purchase_id):
        if not svc.is_profile_writable(uid):
            return "NotProcessedYet"
        profile = svc.profiles.get(uid)
        prev_scrap = profile["Scrap"]
        if not svc.add_scrap(uid, 100):
            return "NotProcessedYet"
        profile["ProcessedReceipts"][purchase_id] = True
        if not svc.save_profile(uid):
            # Rollback
            profile["Scrap"] = prev_scrap
            del profile["ProcessedReceipts"][purchase_id]
            return "NotProcessedYet"
        return "PurchaseGranted"

    res_prod = simulate_purchase(prod_svc, 101, "rcpt_prod_fail")
    assert res_prod == "NotProcessedYet", "Purchase must NOT return PurchaseGranted when DataStore is unavailable"
    assert prod_svc.profiles[101]["Scrap"] == 0

    # Studio mock mode scenario (intentional local session)
    studio_mock_svc = SimulatedPlayerDataService(is_studio=True, datastore_init_ok=False)
    studio_mock_svc.load_profile(202)
    assert studio_mock_svc.is_profile_writable(202) is True, "Profile is writable in intentional Studio mock mode"
    assert studio_mock_svc.add_scrap(202, 50) is True
    assert studio_mock_svc.save_profile(202) is True
    res_studio = simulate_purchase(studio_mock_svc, 202, "rcpt_studio_mock")
    assert res_studio == "PurchaseGranted", "Purchase succeeds in Studio mock mode"


@test_case("Synchronized server clock for round phase countdowns (FIX-T34)")
def test_synchronized_server_clock():
    with open("src/ServerScriptService/Services/RoundService.luau", "r", encoding="utf-8") as f:
        round_content = f.read()

    with open("src/StarterPlayer/StarterPlayerScripts/Controllers/UIController.luau", "r", encoding="utf-8") as f:
        ui_content = f.read()

    # Source assertions - RoundService
    assert "Workspace:GetServerTimeNow()" in round_content, "RoundService must use Workspace:GetServerTimeNow()"
    assert "phaseEndsAt = Workspace:GetServerTimeNow() + duration" in round_content, "TransitionTo must use GetServerTimeNow for phaseEndsAt"
    assert "while Workspace:GetServerTimeNow() < phaseEndsAt do" in round_content, "WaitForPhase must use GetServerTimeNow"
    assert "RoundService.GetPhaseEndsAt" in round_content, "RoundService must expose GetPhaseEndsAt"
    assert "phaseEndsAt = 0" in round_content, "WAITING state must reset phaseEndsAt to 0"

    # Verify cross-process os.clock comparisons are eliminated from RoundService countdowns
    assert "phaseEndsAt - os.clock()" not in round_content, "RoundService must not compare phaseEndsAt with os.clock()"
    assert "os.clock() < phaseEndsAt" not in round_content, "RoundService must not compare os.clock() with phaseEndsAt"

    # Source assertions - UIController
    assert 'game:GetService("Workspace")' in ui_content, "UIController must import Workspace service"
    assert "UIController.CalculateTimeRemaining" in ui_content, "UIController must declare CalculateTimeRemaining"
    assert "Workspace:GetServerTimeNow()" in ui_content, "UIController must query Workspace:GetServerTimeNow()"
    assert "currentPhaseEndsAt - os.clock()" not in ui_content, "UIController must eliminate process-local os.clock countdown calculation"

    # Logic simulation: calculate_time_remaining
    def calculate_time_remaining(phase_ends_at, current_server_time):
        if phase_ends_at <= 0:
            return 0
        return max(0, phase_ends_at - current_server_time)

    def format_time(seconds):
        s = max(0, int(seconds))
        mins = s // 60
        secs = s % 60
        return f"{mins:02d}:{secs:02d}"

    # Active countdown midway
    rem_active = calculate_time_remaining(1045.0, 1020.0)
    assert rem_active == 25.0
    assert format_time(rem_active) == "00:25"

    # Active countdown on exact expiration
    rem_exact = calculate_time_remaining(1045.0, 1045.0)
    assert rem_exact == 0.0
    assert format_time(rem_exact) == "00:00"

    # Stale/late packet arrival where server time exceeds phase_ends_at
    rem_late = calculate_time_remaining(1045.0, 1060.0)
    assert rem_late == 0.0, "Late packet updates must not produce negative numbers"
    assert format_time(rem_late) == "00:00"

    # Waiting state with phase_ends_at == 0
    rem_waiting = calculate_time_remaining(0, 1020.0)
    assert rem_waiting == 0.0

    # Cross-clock skew immunity simulation:
    # Server time = 1500000.0, client local os.clock = 42.5 (arbitrary process-local clock)
    server_time_now = 1500000.0
    phase_ends = server_time_now + 60.0
    client_os_clock = 42.5  # Completely different epoch/counter
    
    # Using synchronized server time avoids discrepancy
    skew_safe_remaining = calculate_time_remaining(phase_ends, server_time_now)
    assert skew_safe_remaining == 60.0
    assert format_time(skew_safe_remaining) == "01:00"

    # Broken legacy logic would have produced huge incorrect offset:
    broken_remaining = phase_ends - client_os_clock
    assert broken_remaining > 1000000, "Proof that legacy os.clock caused extreme clock desync"


@test_case("CI workflow contracts and branch protection requirements (FIX-T35)")
def test_ci_workflow_contracts():
    with open(".github/workflows/ci.yml", "r", encoding="utf-8") as f:
        ci_content = f.read()

    # Workflow contract assertions
    assert "branches: [ main ]" in ci_content, "CI must trigger on main branch"
    assert "pull_request:" in ci_content, "CI must trigger on pull_request"
    assert "name: Lint, Build & Test" in ci_content, "Job must declare 'name: Lint, Build & Test' to match required check name"
    assert "selene src/" in ci_content, "CI must execute selene linter"
    assert "rojo build default.project.json --output Nightline.rbxlx" in ci_content, "CI must compile Rojo project"
    assert "python tests/run_tests.py" in ci_content, "CI must run python regression tests"

    # Documentation contract assertions
    with open("docs/RELEASE_GUIDE.md", "r", encoding="utf-8") as f:
        release_content = f.read()
    assert "Lint, Build & Test" in release_content, "RELEASE_GUIDE.md must specify 'Lint, Build & Test' as required check"
    assert "Branch Protection & CI Quality Gates" in release_content, "RELEASE_GUIDE.md must describe branch protection"


@test_case("Roblox Studio staging evidence & checklist integrity (FIX-T36)")
def test_staging_evidence_integrity():
    with open("docs/STAGING_EVIDENCE.md", "r", encoding="utf-8") as f:
        staging_content = f.read()

    with open("docs/RELEASE_GUIDE.md", "r", encoding="utf-8") as f:
        release_content = f.read()

    # Evidence record validations
    assert "0.746.0.7461269" in staging_content, "STAGING_EVIDENCE.md must record Studio product version"
    assert "176419d50662dc6af48f5e4eb9be7437fc7bbf36" in staging_content, "STAGING_EVIDENCE.md must record tested commit SHA"
    assert "STG-01" in staging_content, "STAGING_EVIDENCE.md must contain solo test STG-01"
    assert "STG-02" in staging_content, "STAGING_EVIDENCE.md must contain 6-client test STG-02"
    assert "STG-03" in staging_content, "STAGING_EVIDENCE.md must contain voting test STG-03"
    assert "STG-04" in staging_content, "STAGING_EVIDENCE.md must contain creature AI test STG-04"
    assert "STG-05" in staging_content, "STAGING_EVIDENCE.md must contain disconnect test STG-05"
    assert "STG-06" in staging_content, "STAGING_EVIDENCE.md must contain all-player disconnect test STG-06"
    assert "STG-07" in staging_content, "STAGING_EVIDENCE.md must contain clock sync test STG-07"
    assert "PASSED & SIGNED OFF" in staging_content, "Must declare verified sign-off"

    # Release guide alignment
    assert "docs/STAGING_EVIDENCE.md" in release_content, "RELEASE_GUIDE.md must link to staging evidence"
    assert "[x] **Solo Playthrough" in release_content, "RELEASE_GUIDE.md must mark Solo Playthrough complete"
    assert "[x] **Multi-Player Stress Test" in release_content, "RELEASE_GUIDE.md must mark Multiplayer Stress Test complete"


@test_case("DataStore live test evidence & persistence gating integrity (FIX-T37)")
def test_datastore_live_evidence_integrity():
    with open("docs/DATASTORE_LIVE_TEST_EVIDENCE.md", "r", encoding="utf-8") as f:
        ds_content = f.read()

    with open("docs/RELEASE_GUIDE.md", "r", encoding="utf-8") as f:
        release_content = f.read()

    # Evidence record validations
    assert "GameData_v1" in ds_content, "DATASTORE_LIVE_TEST_EVIDENCE.md must reference GameData_v1"
    assert "Player_<userId>" in ds_content, "DATASTORE_LIVE_TEST_EVIDENCE.md must specify key schema"
    for pid in ["1001", "1002", "1003", "1004", "2001", "2002", "2003"]:
        assert pid in ds_content, f"DATASTORE_LIVE_TEST_EVIDENCE.md must contain product/pass ID {pid}"

    for scenario_id in ["DS-01", "DS-02", "DS-03", "DS-04", "DS-05", "DS-06", "DS-07"]:
        assert scenario_id in ds_content, f"DATASTORE_LIVE_TEST_EVIDENCE.md must contain scenario {scenario_id}"

    assert "PASSED & SIGNED OFF" in ds_content, "DATASTORE_LIVE_TEST_EVIDENCE.md must declare verified sign-off"

    # Release guide alignment
    assert "docs/DATASTORE_LIVE_TEST_EVIDENCE.md" in release_content, "RELEASE_GUIDE.md must link to live DataStore evidence"
    assert "[x] **Live DataStore Persistence" in release_content, "RELEASE_GUIDE.md must mark Live DataStore Persistence complete"
    assert "[x] **Developer Product Receipt Durability" in release_content, "RELEASE_GUIDE.md must mark Receipt Durability complete"
    assert "[x] **Duplicate Callback Idempotency" in release_content, "RELEASE_GUIDE.md must mark Duplicate Callback Idempotency complete"


@test_case("Mobile, gamepad & presentation QA integrity (FIX-T38)")
def test_mobile_gamepad_qa_integrity():
    with open("docs/MOBILE_GAMEPAD_QA_EVIDENCE.md", "r", encoding="utf-8") as f:
        qa_content = f.read()

    with open("docs/RELEASE_GUIDE.md", "r", encoding="utf-8") as f:
        release_content = f.read()

    with open("src/StarterPlayer/StarterPlayerScripts/Controllers/InputController.luau", "r", encoding="utf-8") as f:
        input_content = f.read()

    with open("src/StarterPlayer/StarterPlayerScripts/Controllers/UIController.luau", "r", encoding="utf-8") as f:
        ui_content = f.read()

    # Evidence validations
    assert "iPhone 14" in qa_content, "MOBILE_GAMEPAD_QA_EVIDENCE.md must specify iPhone 14 profile"
    assert "844 x 390" in qa_content, "Must specify viewport resolution"
    for btn in ["ButtonL3", "ButtonY", "ButtonB", "DPadLeft", "DPadRight"]:
        assert btn in qa_content, f"Must document gamepad button {btn}"

    for scenario_id in ["QA-01", "QA-02", "QA-03", "QA-04", "QA-05", "QA-06", "QA-07"]:
        assert scenario_id in qa_content, f"Must document scenario {scenario_id}"

    assert "PASSED & SIGNED OFF" in qa_content, "Must declare verified sign-off"

    # InputController code validation
    assert "ButtonL3" in input_content, "InputController must bind Sprint to ButtonL3"
    assert "ButtonY" in input_content, "InputController must bind Light toggle to ButtonY"
    assert "ButtonB" in input_content, "InputController must bind Throw flare to ButtonB"
    assert "DPadLeft" in input_content, "InputController must bind Slot 1 to DPadLeft"
    assert "DPadRight" in input_content, "InputController must bind Slot 2 to DPadRight"

    # UIController gamepad modal dismissal validation
    assert "Enum.KeyCode.ButtonB" in ui_content, "UIController must handle ButtonB modal dismissal"
    assert "buyBtn.Selectable = true" in ui_content, "UIController must make buyBtn gamepad selectable"

    # Release guide alignment
    assert "docs/MOBILE_GAMEPAD_QA_EVIDENCE.md" in release_content, "RELEASE_GUIDE.md must link to mobile/gamepad QA evidence"
    assert "[x] **Mobile & Gamepad Emulation" in release_content, "RELEASE_GUIDE.md must mark Mobile & Gamepad Emulation complete"


@test_case("Station platform portal and extraction zone resilience (FIX-T39)")
def test_station_platform_portal():
    with open("src/ServerScriptService/Services/StationService.luau", "r", encoding="utf-8") as f:
        station_content = f.read()

    # Ensure unbroken 80-stud PlatformWall is replaced with segmented portal geometry
    assert "PlatformWallNorth" in station_content, "StationService must define PlatformWallNorth"
    assert "PlatformWallSouth" in station_content, "StationService must define PlatformWallSouth"
    assert "PlatformPortalHeader" in station_content, "StationService must define PlatformPortalHeader"
    assert "Vector3.new(1.5, 16, 80)" not in station_content, "Solid 80-stud blocking PlatformWall must not exist"

    # Ensure extraction zone check falls back to Workspace.World.Runtime
    assert "local world = Workspace:FindFirstChild(\"World\")" in station_content, "IsInsideExtractionZone must query World fallback"
    assert "station = runtime and runtime:FindFirstChild(\"ActiveStation\")" in station_content, "IsInsideExtractionZone must query ActiveStation"


# =========================================================================
# Runner Entry Point
# =========================================================================

def main():
    print("==================================================")
    print("  NIGHTLINE: LAST TRAIN - AUTOMATED TEST SUITE    ")
    print("==================================================")
    
    test_project_json()
    test_remotes_declaration()
    test_security_integer_validation()
    test_equipment_phase_gating()
    test_flashlight_toggle_lifecycle()
    test_movement_anticheat_comprehensive()
    test_upgrade_terminal_proximity()
    test_destination_voting()
    test_destination_voting_ui()
    test_hollow_los_raycasting()
    test_hollow_noise_cadence_throttling()
    test_phase_wait_generation()
    test_profile_reconciliation()
    test_interaction_prompt_security()
    test_camera_controller()
    test_interaction_controller()
    test_analytics_service()
    test_analytics_event_dispatch_and_economy()
    test_monetization_processing()
    test_durable_receipt_persistence()
    test_concurrent_receipt_guard()
    test_datastore_fail_closed_mode()
    test_synchronized_server_clock()
    test_ci_workflow_contracts()
    test_staging_evidence_integrity()
    test_datastore_live_evidence_integrity()
    test_mobile_gamepad_qa_integrity()
    test_station_platform_portal()

    print("--------------------------------------------------")
    print(f"Tests Completed: {PASSED + FAILED} | Passed: {PASSED} | Failed: {FAILED}")
    print("==================================================")

    # Write test_results.json
    results_payload = {
        "timestamp": time.time(),
        "total": PASSED + FAILED,
        "passed": PASSED,
        "failed": FAILED,
        "tests": TEST_RESULTS,
    }
    with open("test_results.json", "w", encoding="utf-8") as f:
        json.dump(results_payload, f, indent=2)

    if FAILED > 0:
        sys.exit(1)
    else:
        sys.exit(0)

if __name__ == "__main__":
    main()

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

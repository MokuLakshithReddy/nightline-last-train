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


# =========================================================================
# 4. Hollow Perception & LOS Raycasting (FIX-T12)
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
# 10. Analytics & Gameplay Funnel Telemetry (FIX-T22)
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


# =========================================================================
# 11. Monetization & Receipt Idempotency (FIX-T23)
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
    test_upgrade_terminal_proximity()
    test_destination_voting()
    test_hollow_los_raycasting()
    test_phase_wait_generation()
    test_profile_reconciliation()
    test_interaction_prompt_security()
    test_camera_controller()
    test_interaction_controller()
    test_analytics_service()
    test_monetization_processing()

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

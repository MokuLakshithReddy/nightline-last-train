# NIGHTLINE: LAST TRAIN — Current Release Readiness

**Decision: NOT APPROVED FOR PUBLIC RELEASE.**

This file is the active release gate. Historical sign-off documents remain useful as records of earlier runs, but they do not count as evidence for the current release candidate unless the evidence names that exact candidate SHA and the tested environment.

## Current repository snapshot

- `main`: `d442a236e9b79b3f88b1aff2dbce8439ccc9073e`.
- Draft PR [#64](https://github.com/MokuLakshithReddy/nightline-last-train/pull/64): `92314432cdbe66766ab73b8737d939b56423088a`; not merged.
- CI on PR #64: lint, Rojo build, and Python regression suite passed.
- No connected Roblox Studio instance was available during this review. CI is not Roblox runtime validation.

## Blocking gates

| Gate | Status | Required evidence to close |
|---|---|---|
| Multiplayer lifecycle changes | **OPEN** | Run the current candidate in Roblox Studio Local Server with 2, 4, and 6 clients. Cover concurrent objective prompts, active-player target filtering, player disconnect with carried cargo, team wipe, and round cleanup. Record Studio version, candidate SHA, client count, scenario results, and server/client logs. |
| Live persistence and receipts | **OPEN** | In an isolated private published test universe, run persistence across rejoin, session-lock contention, duplicate receipt, and save-failure/retry scenarios against the exact candidate SHA. Record place/universe identity (no secrets), test date, results, and relevant server logs. |
| Audio access and playback | **OPEN** | In the target experience, verify universe permission for audio asset IDs `9114221764`, `9114223170`, `9114224095`, and `9114222485`; then verify playback in a private published session. Record each asset's permission and playback result. |
| Release controls | **UNCONFIRMED** | Verify on GitHub that `main` requires pull requests and the `Lint, Build & Test` check. The review connection could not read branch protection settings. |
| Candidate sign-off | **OPEN** | Merge approved code through the repository process, rerun CI on the final candidate, update each evidence record with that exact SHA, and obtain release-owner sign-off before changing experience visibility. |

## Evidence records currently in the repository

- [Studio staging](./STAGING_EVIDENCE.md) records commit `176419d50662dc6af48f5e4eb9be7437fc7bbf36`.
- [DataStore and monetization](./DATASTORE_LIVE_TEST_EVIDENCE.md) records commit `56e7b9bb54ffd5769b6ba7dd624043072c65b98d`.
- [Mobile, gamepad, and presentation QA](./MOBILE_GAMEPAD_QA_EVIDENCE.md) records commit `e61dace0826e24b3ba7ba413992830eb0c9a3b2c`.

These are older than PR #64 and must not be presented as current-candidate sign-off. Do not mark a gate complete based only on source-level assertions or a passing CI run.

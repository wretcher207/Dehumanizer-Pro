# MEMORY.md — DeHumanizer Pro

## Repo conventions

- The script ships at **two** paths, bit-identical: `/dehumanizer-pro.lua` (root, source-of-truth) and `/Scripts/dehumanizer-pro.lua` (ReaPack install target, referenced by `index.xml`). Any edit must be mirrored to both, or installed users get stale code while the repo source looks updated. Workflow: edit root → `luac -p` → `cp dehumanizer-pro.lua Scripts/dehumanizer-pro.lua` → `diff` → `git add` both.
- Default branch is `main`; David ships directly. No CI gate beyond syntax.

---

## Session 2026-06-16 — Adversarial review + 3 fix PRs

### Worked on
Adversarial review of `dehumanizer-pro.lua` (766 lines, ReaImGui velocity + timing humanizer for drum MIDI). Catalogued 12 critical, 8 performance, 10 structural issues. Patched the highest-impact subset across three independent PRs against `main`.

### Completed (luac-clean, behaviorally unverified — needs a Reaper session)
- [PR #1](https://github.com/wretcher207/Dehumanizer-Pro/pull/1) `fix/velocity-preview-parity-undo-scope` — commit `29f8c0f`
  - **C1** Unified `compute_velocities()` for preview + APPLY (seeded LCG, no more lying preview dots)
  - **C2** Golden-rule bump pushes deterministically away from `last_vel`
  - **C5** APPLY VELOCITY refetches selection inside the click handler
  - **C7** Undo scoped to `UNDO_STATE_ITEMS (4)` instead of `-1`
- [PR #2](https://github.com/wretcher207/Dehumanizer-Pro/pull/2) `fix/persist-rolemap-singleton-guard` — commit `6543b2c`
  - **C3** `ROLE_MAP` "Learn from Selection" persists to ExtState + auto-saves immediately
  - **C9** Singleton heartbeat (2s timeout) blocks duplicate launches; cached `_ctx` + `ValidatePtr`
- [PR #3](https://github.com/wretcher207/Dehumanizer-Pro/pull/3) `fix/timing-engine-per-note-tempo` — commit `3a6cc67`
  - **C4** `apply_timing` replaces single-BPM ratio with per-note `MIDI_GetProjTimeFromPPQPos` round-trip — costs 2 API calls per note (APPLY-time only)

### In progress
Nothing in flight. Three PRs await David's review and **actual-Reaper verification**. Per anti-lying rule: luac success is not behavior success.

### Decisions made
- **One bundle vs three PRs** → three. Each PR clusters by theme (velocity correctness / lifecycle / timing math). Rejected the single bundle because review and revert get hard when unrelated risk profiles mix.
- **Preview seed = hash(note_count, params, sampled curve points)** → stable per frame, reflects the random pipeline. Rejected per-frame `math.random` (flicker) and full deterministic preview without randomness (the original bug — preview ≠ apply).
- **Per-note ms→PPQ via project-time round-trip** in `apply_timing`. Rejected caching tempo curve in Lua (premature optimization; APPLY-only cost is sub-ms).
- **Preserve note duration in PPQ across timing nudge** (only the start gets re-projected). Rejected re-projecting `endppq` too — would silently retime note ends as a side effect of nudging starts. Conservative humanizer behavior.
- **`ROLE_MAP` persistence as side effect of `load_settings`** rather than returned in the settings table. Documented in code. Rejected returning + re-assigning in `run()` (more caller churn, same net effect).
- **C4 tempo math** kept `get_tempo_info()` unchanged because it only powers the slider tooltip preview, which is a rough display estimate by design.

### Next session priorities
Pick from remaining review items, rough value order:
- **C6** APPLY silently no-ops on empty selection — add status line + selection fallback
- **C11** On-beat detection only works on quarter-note grid — pull from `MIDI_GetGrid`
- **C8 / C10** Integer drift step + hardcoded phrase gap → continuous slider + UI control
- **P1** `get_notes` runs even when window collapsed — gate behind ImGui visibility
- **P4** Batched single-blob settings persistence (one ExtState write instead of ~30)
- **S1** `xpcall` + `debug.traceback` for richer error logs

**Highest-risk verification owed**: PR #3 (C4). The tempo-ramp test in the PR body (120 → 180 ramp; rush should feel uniform across the ramp instead of compressing toward the start) is the load-bearing check. Run that in Reaper before merging.

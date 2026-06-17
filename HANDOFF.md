# HANDOFF.md — DeHumanizer Pro

For the next chat. Resume from zero context.

## Current status

`main` is unchanged from `0f8aa62` (v5.4). Three open PRs proposing fixes from an adversarial review of `dehumanizer-pro.lua`. None merged yet. None behaviorally verified — luac syntax only.

## What shipped this session

Adversarial review of `dehumanizer-pro.lua` produced 12 critical / 8 perf / 10 structural findings. The top-priority subset was split into three independent PRs.

| PR | Branch | Findings | Risk |
|---|---|---|---|
| [#1](https://github.com/wretcher207/Dehumanizer-Pro/pull/1) | `fix/velocity-preview-parity-undo-scope` | C1 preview parity, C2 golden-rule direction, C5 stale selection refetch, C7 undo scope | Velocity engine semantics change |
| [#2](https://github.com/wretcher207/Dehumanizer-Pro/pull/2) | `fix/persist-rolemap-singleton-guard` | C3 ROLE_MAP persistence + auto-save, C9 singleton + context cache | New ExtState keys (schema additive) |
| [#3](https://github.com/wretcher207/Dehumanizer-Pro/pull/3) | `fix/timing-engine-per-note-tempo` | C4 per-note ms→PPQ via project-time | Timing math change |

All three branch off `main`, touch only `dehumanizer-pro.lua` + `Scripts/dehumanizer-pro.lua`, and are independent (no shared lines). Mergeable in any order.

See [MEMORY.md](MEMORY.md) for decisions and the open punch list.

## How to verify before merging

You'll need Reaper open with the script installed. PR bodies have the per-PR test plan; the load-bearing checks:

- **PR #1**: Draw a velocity curve, hover the canvas — orange preview dots should match the velocities that land after clicking APPLY VELOCITY. Pre-fix, they didn't.
- **PR #1**: After APPLY, `Ctrl+Z` should revert only the MIDI item, not snapshot the whole project.
- **PR #2**: Click "Learn from Selection" with a new pitch selected, quit Reaper, reopen. The learned pitch should still be in the role.
- **PR #2**: Launch the script. While the window is open, fire the toolbar action again. A modal should say "already running" instead of opening a duplicate.
- **PR #3** (highest risk): Project with a tempo ramp 120 → 180 across the item. APPLY TIMING with lean=+10ms. The rush should feel uniform across the ramp, not compressed toward the start.

## Repo gotchas

- The script lives at **two paths**: `/dehumanizer-pro.lua` and `/Scripts/dehumanizer-pro.lua`. `index.xml` points at the `Scripts/` copy (ReaPack install target). Both must stay bit-identical. See conventions section in [MEMORY.md](MEMORY.md).
- Default branch is `main`. David ships to main directly. No CI gate beyond syntax (`luac -p`).
- ExtState namespace: `DEAD_PIXEL_DEHUMANIZER`. PR #2 adds `rolemap_<role>` and `instance_heartbeat` keys.

## Where to start next chat

Two reasonable entry points:

1. **"Let's verify and merge the three PRs"** — walk the PR test plans in Reaper, then merge in any order (they don't conflict).
2. **"Keep going down the review punch list"** — pick from MEMORY.md → Next session priorities. C6 (selection no-op) and C11 (grid-aware on-beat) are the next-cheapest high-value items.

## Reference

- Full review findings: PR descriptions on GitHub (linked above) — restated from the original adversarial dissection.
- Decision log: [MEMORY.md](MEMORY.md)
- Errors that needed >2 attempts: none this session.

> **ReaPack users:** This script is now distributed through the unified Dead Pixel Design repository.
> Add this URL in REAPER under `Extensions → ReaPack → Import repositories`:
> ```
> https://raw.githubusercontent.com/wretcher207/dead-pixel-design/main/index.xml
> ```
> The `index.xml` in this repo is preserved for backward compatibility but will not receive new entries.

---

# DeHumanizer Pro

![REAPER](https://img.shields.io/badge/REAPER-6%2B-green?style=flat-square)
![Lua](https://img.shields.io/badge/Lua-ReaScript-blue?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-yellow?style=flat-square)
![Status](https://img.shields.io/badge/Status-Production--Ready-brightgreen?style=flat-square)

**Intentional dynamics shaping for modern drum programming.**

Most humanizers spray random jitter across your MIDI and call it "feel." DeHumanizer Pro gives you two independent, drawable engines — one for velocity, one for timing — so you sculpt the dynamics and groove of a phrase with surgical precision, not dice rolls.

---

## Features

### Velocity Engine

- **Drawable velocity curve** — paint a velocity shape across the full phrase with interpolated brush strokes
- **Role-aware filtering** — target Kicks, Snare, Hihat, Ride, Toms, Cymbals, or All independently
- **Learn from Selection** — select a note in the MIDI editor to teach a role new pitches on the fly
- **Smart Phrase Reset** — drift and golden-rule logic reset at phrase boundaries (configurable gap threshold)
- **Live velocity preview** — see predicted output overlaid on original notes before committing
- **Drift Tension** — controls how much the velocity wanders over consecutive hits
- **Apply Strength** — blend between original velocity and the shaped curve (0% = untouched, 100% = full curve)
- **Right-click erase** — paint the curve back to center with the right mouse button
- **Full persistence** — curve shape and all slider values survive script close / REAPER restart

### Timing Engine

- **Per-role lean (rush/drag)** — bias each kit piece ahead of or behind the beat in milliseconds
- **Per-role scatter** — add timing variance with a biased bell-curve distribution (most hits stay near center)
- **Beat-aware tightening** — beats 1, 2, 3, 4 automatically receive 30% of the scatter value to stay grounded
- **Drawable scatter curve (per role)** — paint a timing variance multiplier across the phrase (0× at bottom, 1× at center, 2× at top) to shape where the groove loosens up and where it locks in
- **Tempo-aware PPQ math** — all timing offsets are computed relative to the current project tempo
- **BPM-aware tooltip** — hover the (?) icon next to any role for a live preview of lean offset in ms, PPQ, and direction
- **Independent apply** — APPLY TIMING only moves notes in time; it never touches velocity

---

## Prerequisites

- **REAPER** 6.0 or later
- **ReaImGui** — install via ReaPack: `Extensions → ReaPack → Browse packages → search "ReaImGui"`

---

## Installation

### Via ReaPack (recommended)

1. Open REAPER
2. Go to `Extensions → ReaPack → Import repositories…`
3. Paste this URL:
   ```
   https://raw.githubusercontent.com/wretcher207/dead-pixel-design/main/index.xml
   ```
4. Click OK, then `Extensions → ReaPack → Browse packages`
5. Search **DeHumanizer Pro**, right-click → Install
6. Restart REAPER or run `Actions → ReaPack: Synchronize packages`

### Manual Install

1. Download `dehumanizer-pro.lua` from the [Scripts](./Scripts/) folder
2. Place it in your REAPER `Scripts/` directory (usually `~/.config/REAPER/Scripts/` on Linux, `~/Library/Application Support/REAPER/Scripts/` on macOS, or `%APPDATA%\REAPER\Scripts\` on Windows)
3. In REAPER: `Actions → Show action list → Load ReaScript…` → select the file

---

## How To Use

### Velocity Engine

1. Open a MIDI item in the MIDI editor and **select the notes** you want to humanize.
2. Choose a **Target Role** from the dropdown (or "All" for everything).
3. Set **Min Velocity** and **Max Velocity** to define the output range.
4. **Draw a velocity curve** on the canvas — the left edge is the start of the phrase, the right edge is the end. Bottom = Min Vel, Top = Max Vel.
5. Adjust **Drift Tension** (random walk between consecutive hits) and **Apply Strength** (blend amount).
6. Watch the orange **Preview** dots update in real time.
7. Click **APPLY VELOCITY** to commit changes.

### Timing Engine

1. With notes still selected, expand the **Timing Engine** section.
2. **Enable** one or more roles via the checkboxes.
3. Set **Lean** to push a role ahead (positive = rush) or behind (negative = drag) the beat.
4. Set **Scatter** to add random timing variance (bell-curve distributed).
5. Optionally **draw a Scatter Curve** for each role — this multiplies the scatter value across the phrase so you can have tight downbeats and loose fills.
6. Hover the **(?)** icon for a live tooltip showing the lean offset in ms, PPQ, direction, and effective scatter values at the current tempo.
7. Click **APPLY TIMING** to commit changes. Velocity is not affected.

> **Tip:** Velocity and Timing are fully independent. You can apply one, both, or neither — in any order.

---

## About

Built by **[Dead Pixel Design](https://www.deadpixeldesign.com)** — *we don't optimize, we haunt.*

© 2026 Dead Pixel Design
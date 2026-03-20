# Changelog

All notable changes to DeHumanizer Pro will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [5.4] - 2026-03-20

### Changed

- Renamed "PROCESS PHRASE" button to "APPLY VELOCITY" for symmetry with "APPLY TIMING" — makes it immediately clear that each button controls one engine only.

### Added

- Visible section header above the velocity curve area: ========== VELOCITY SHAPING ==========
- Visible section header above the timing engine section: ========== TIMING ENGINE ==========
- Axis context hint on velocity canvas: "Draw velocity shape: bottom = Min Vel, top = Max Vel"
- Updated window title and script header block to v5.4.

### Fixed

- Reduced default window height from 860 to 640 so the APPLY TIMING button is visible without scrolling on standard displays.
- Section headers use plain ASCII instead of UTF-8 box-drawing characters to avoid potential string encoding issues across Lua versions.

### Verified

- Velocity canvas (`"canvas"`) and per-role timing variance canvases (`"##tvcurvas_" .. role`) use independent ImGui widget IDs with no interaction bleed.

## [5.3] - 2026-02-01

### Added

- Timing Variance Curve: drawable per-role curve mapping phrase position to a scatter multiplier (0× at bottom, 1× at center, 2× at top).
- Per-role scatter curve persistence across sessions.
- Beat-aware tightening: beats 1/2/3/4 automatically receive 30% of scatter to stay grounded.
- BPM-aware tooltip: hover (?) for live preview of lean offset in ms, PPQ, and direction at current tempo.

## [5.0] - 2026-01-01

### Added

- Timing Engine: per-role lean (rush/drag) and scatter sliders.
- Biased bell-curve distribution for timing variance (most hits cluster near center).
- Tempo-aware PPQ math — all timing offsets computed relative to project tempo.
- Per-role enable/disable checkboxes.
- APPLY TIMING button (independent of velocity processing).

## [4.5] - 2025-06-01

### Added

- Velocity preview: orange dots overlaid on canvas show predicted output before committing.
- Curve persistence: velocity curve shape and all slider values survive script close and REAPER restart.
- Mouse interpolation: smooth curve painting between frames (no gaps at fast mouse speeds).
- Right-click erase: paint the velocity curve back to center with RMB.
- Canvas legend: Original / Preview dot indicators and LMB:draw / RMB:erase hint.

## [4.4] - 2025-05-15

### Fixed

- Learn from Selection (previously "Learn Pitch") — now correctly adds selected note pitches to the active role.
- Nil velocity crash on edge cases where notes had no velocity data.
- Phrase boundary reset logic — drift and golden-rule state now properly reset at phrase gaps.

### Removed

- Orphaned state variables from earlier development.

## [4.3] - 2025-05-01

### Added

- Initial public release.
- Drawable velocity curve with role-aware filtering.
- Smart Phrase Reset logic.
- Drift Tension and Apply Strength controls.
- Min/Max Velocity range.
- ReaPack distribution via index.xml.

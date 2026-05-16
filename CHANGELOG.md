# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] — 2026-05-16

### Changed
- **Wrapper script reads enabled providers from `~/.codexbar/config.json`**
  instead of hardcoding `(codex claude gemini)`. A Codex-only user no longer
  sees Claude/Gemini error tabs. Override per-instance with
  `CODEXBAR_PROVIDERS="codex claude"` if you need to bypass the config.
- **Default refresh interval dropped from 60 s to 30 s** and the module now
  declares `signal: 8`, so a `pkill -RTMIN+8 waybar` forces an immediate
  refresh. The popover sends that signal after a Save so the bar reflects
  toggled providers without waiting for the next tick.
- **`install.sh` now hard-fails if the `codexbar` CLI is missing**, with the
  exact tarball + libxml2-legacy commands inline. Previous behaviour was a
  soft warning that left users with a silent half-install.
- **Inline Settings view** (already in 0.1.1 — moved out of Unreleased):
  clicking *Settings…* swaps the popover body to a scrollable provider
  list with per-provider toggle switches and a *Save* button. macOS-only
  providers appear in a separate grayed section with a hint, so users
  don't waste time enabling things that can't work on Linux.

## [0.1.0] — 2026-05-16

### Added
- `codexbar.sh` — Waybar custom-module backend that polls the CodexBar Linux
  CLI per provider with a configurable stagger, caches the last successful
  snapshot, and emits Waybar JSON (`text` / `tooltip` / `class` / `percentage`)
  keyed on the highest used-percent.
- `codexbar-popup.py` — GTK4 + `gtk4-layer-shell` popover that mirrors the
  macOS menu: provider tab strip, flat sections, thin progress bars, reset
  countdowns, credit balances. Auto-detects `libgtk4-layer-shell.so` across
  Arch / Debian / Fedora.
- `codexbar.jsonc` — Waybar module definition with click-to-open and
  right-click `notify-send` fallback.
- `codexbar.css` — `ok` / `warning` / `critical` / `stale` state styling for
  the Waybar entry.
- `install.sh` — idempotent installer.

[Unreleased]: https://github.com/Marouan-chak/codexbar-waybar/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/Marouan-chak/codexbar-waybar/releases/tag/v0.1.1
[0.1.0]: https://github.com/Marouan-chak/codexbar-waybar/releases/tag/v0.1.0

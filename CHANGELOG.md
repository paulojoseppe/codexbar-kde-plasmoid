# Changelog

All notable changes to this project will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Settings is now an inline view inside the popover** — no external editor,
  no JSON file opened in a browser. Clicking *Settings…* swaps the popup
  body to a scrollable provider list with per-provider toggle switches.
  *Save* writes back to `~/.codexbar/config.json` and refreshes the data;
  *Back* cancels.
- Linux-unsupported providers (macOS-only web/cookie sources) appear in their
  own grayed-out section with a "macOS only" hint, so it's obvious why you
  can't enable them without trial-and-error.

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

[Unreleased]: https://github.com/Marouan-chak/codexbar-waybar/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Marouan-chak/codexbar-waybar/releases/tag/v0.1.0

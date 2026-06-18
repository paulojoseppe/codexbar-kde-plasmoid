#!/usr/bin/env bash
# Install CodexBar as a KDE Plasma widget.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_ID="dev.codexbar.plasma"
PLASMOID_SRC="$SCRIPT_DIR/package"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PLASMOID_DST="$DATA_HOME/plasma/plasmoids/$PLASMOID_ID"

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

if ! command -v codexbar >/dev/null 2>&1; then
    red "'codexbar' is not on PATH. Install the CodexBar Linux CLI first."
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    red "Missing dependency: jq"
    exit 1
fi

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    red "Missing dependency: kpackagetool6"
    exit 1
fi

kpackagetool6 --type Plasma/Applet --upgrade "$PLASMOID_SRC" >/dev/null \
    || kpackagetool6 --type Plasma/Applet --install "$PLASMOID_SRC" >/dev/null

chmod 0755 "$PLASMOID_DST/contents/scripts/codexbar.sh"

COMPILER=""
for cmd in gcc clang cc; do
    if command -v "$cmd" >/dev/null 2>&1; then
        COMPILER="$cmd"
        break
    fi
done

if [[ -n "$COMPILER" ]]; then
    if "$COMPILER" -shared -fPIC -o "$PLASMOID_DST/contents/scripts/cert_redirect.so" "$SCRIPT_DIR/cert_redirect.c" -ldl 2>/dev/null; then
        green "Compiled SSL redirect shim."
    else
        yellow "Could not compile SSL redirect shim; Antigravity may need manual setup."
    fi
else
    yellow "No C compiler found. Skipping Antigravity SSL redirect shim."
fi

green "Installed Plasma widget: $PLASMOID_ID"
cat <<EOF

Add it from Plasma's widget picker:
  Right-click panel or desktop -> Add Widgets -> search "CodexBar"

If Plasma does not show it immediately, restart plasmashell:
  systemctl --user restart plasma-plasmashell.service

Backend script:
  $PLASMOID_DST/contents/scripts/codexbar.sh
EOF

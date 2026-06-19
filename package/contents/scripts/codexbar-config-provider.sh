#!/usr/bin/env bash
set -u

provider="${1:-}"
enabled="${2:-}"

if [[ ! "$provider" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "invalid provider: $provider" >&2
    exit 2
fi

case "$enabled" in
    true|false) ;;
    *) echo "enabled must be true or false" >&2; exit 2 ;;
esac

verb="disable"
[[ "$enabled" == "true" ]] && verb="enable"

try_cli() {
    local bin="${CODEXBAR_BIN:-${HOME}/.local/bin/codexbar}"
    if [[ -x "$bin" ]]; then
        "$bin" config "$verb" --provider "$provider"
        return $?
    fi
    if command -v codexbar >/dev/null 2>&1; then
        codexbar config "$verb" --provider "$provider"
        return $?
    fi
    return 127
}

if try_cli >/dev/null 2>&1; then
    exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required for config fallback" >&2
    exit 127
fi

config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/codexbar"
config_path="${config_dir}/config.json"
mkdir -p "$config_dir"

tmp="$(mktemp "${config_dir}/config.json.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT

if [[ -f "$config_path" ]]; then
    jq --arg p "$provider" --argjson e "$enabled" '
        .version = (.version // 1)
        | .providers = (.providers // [])
        | (any(.providers[]?; .id == $p)) as $exists
        | if $exists then
            .providers |= map(if .id == $p then .enabled = $e else . end)
          else
            .providers += [{id: $p, enabled: $e}]
          end
    ' "$config_path" > "$tmp" && mv "$tmp" "$config_path"
else
    jq -n --arg p "$provider" --argjson e "$enabled" \
        '{version: 1, providers: [{id: $p, enabled: $e}]}' > "$tmp" \
        && mv "$tmp" "$config_path"
fi

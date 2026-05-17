#!/usr/bin/env bash
# Waybar custom module for CodexBar (Linux CLI).
# Fetches usage from configured providers sequentially (with a small stagger
# to avoid per-provider rate limits) and emits Waybar JSON
# ({"text","tooltip","class","percentage"}) keyed on the most-constrained window.
# Last successful per-provider snapshot is cached, so a transient 429 is masked
# until the next refresh recovers it.
#
# Linux-only providers — cookies/web providers are macOS-only. The list is
# read from ~/.codexbar/config.json (use the popover's Settings view to
# manage it); falls back to codex+claude+gemini if the file is missing.

set -u

CODEXBAR="${CODEXBAR_BIN:-${HOME}/.local/bin/codexbar}"
CONFIG_PATH="${HOME}/.codexbar/config.json"
STATE_PATH="${XDG_CONFIG_HOME:-${HOME}/.config}/codexbar-waybar/state.json"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/codexbar-waybar"
mkdir -p "$CACHE_DIR"

# Per-instance bar provider selection (written by the popup's Settings view).
# `null` (or unset) means "show the highest used% across providers".
BAR_PROVIDER=""
if [[ -f "$STATE_PATH" ]] && command -v jq >/dev/null 2>&1; then
    BAR_PROVIDER="$(jq -r '.barProvider // empty' "$STATE_PATH" 2>/dev/null)"
fi
[[ -n "${CODEXBAR_BAR_PROVIDER:-}" ]] && BAR_PROVIDER="$CODEXBAR_BAR_PROVIDER"

# Read enabled providers from the codexbar CLI's config, fall back to a
# sensible default if it's missing or unreadable. Override with the
# CODEXBAR_PROVIDERS env var (space-separated list) when you want to bypass
# config.json for a specific waybar instance.
if [[ -n "${CODEXBAR_PROVIDERS:-}" ]]; then
    # shellcheck disable=SC2206
    PROVIDERS=( ${CODEXBAR_PROVIDERS} )
elif [[ -f "$CONFIG_PATH" ]] && command -v jq >/dev/null 2>&1; then
    readarray -t PROVIDERS < <(jq -r '[.providers[]? | select(.enabled == true) | .id] | .[]' "$CONFIG_PATH" 2>/dev/null)
    [[ ${#PROVIDERS[@]} -eq 0 ]] && PROVIDERS=(codex claude gemini)
else
    PROVIDERS=(codex claude gemini)
fi

# Per-provider --source override. Codex/Claude need explicit oauth on Linux
# (their `auto` falls back to web first, which is macOS-only).
declare -A SOURCE_OVERRIDES=(
    [codex]=oauth
    [claude]=oauth
)

# If the primary source returns a provider-level error (e.g. Claude OAuth
# hitting HTTP 429), fall back to this source. Mostly useful for Claude
# where the local CLI logs have the same windowing data.
declare -A FALLBACK_SOURCES=(
    [claude]=cli
)

fetch_one() {
    local p="$1" src="$2"
    local args=(usage --provider "$p" --format json --no-color)
    [[ -n "$src" ]] && args+=(--source "$src")
    "$CODEXBAR" "${args[@]}" 2>/dev/null
}

fetch_provider() {
    local p="$1"
    local primary="${SOURCE_OVERRIDES[$p]:-}"
    local fallback="${FALLBACK_SOURCES[$p]:-}"

    local body
    body="$(fetch_one "$p" "$primary")"

    # Only retry when the response is a valid array with a provider-level
    # error — network failures and rate limits land here. Auth misconfig
    # surfaces the same way; the fallback may still error, which is fine
    # because the cache layer will mask it.
    if [[ -n "$fallback" ]] \
        && echo "$body" | jq -e 'type == "array" and (.[0].error // null) != null' >/dev/null 2>&1; then
        body="$(fetch_one "$p" "$fallback")"
    fi

    echo "$body"
}

# Sequential fetch with a small stagger between providers (avoids 429s).
STAGGER_SECS="${CODEXBAR_STAGGER:-0.5}"
LAST_GOOD="$CACHE_DIR/last.json"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

i=0
for p in "${PROVIDERS[@]}"; do
    (( i > 0 )) && sleep "$STAGGER_SECS"
    fetch_provider "$p" > "$tmpdir/$p.json"
    i=$((i + 1))
done

merged="["
first=1
for p in "${PROVIDERS[@]}"; do
    body="$(cat "$tmpdir/$p.json")"
    # CLI returns a JSON array; unwrap and append elements.
    if [[ -z "$body" ]] || ! echo "$body" | jq -e 'type == "array"' >/dev/null 2>&1; then
        continue
    fi
    inner="$(echo "$body" | jq -c '.[]')"
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        if (( first )); then
            merged+="$entry"
            first=0
        else
            merged+=",$entry"
        fi
    done <<< "$inner"
done
merged+="]"

# Fill in errored providers with the last successful snapshot (marks them stale).
if [[ -f "$LAST_GOOD" ]] && [[ "$merged" != "[]" ]]; then
    merged="$(jq -c --argjson prev "$(cat "$LAST_GOOD")" '
        ([$prev[]? | select(.error | not) | {key: .provider, value: .}] | from_entries) as $ok_prev
        | map(if .error and $ok_prev[.provider]
              then $ok_prev[.provider] + {stale: true}
              else . end)
    ' <<< "$merged")"
fi

# Persist snapshot if at least one provider succeeded.
if [[ "$merged" != "[]" ]] && echo "$merged" | jq -e 'any(.error | not)' >/dev/null 2>&1; then
    echo "$merged" > "$LAST_GOOD"
fi

if [[ "$merged" == "[]" ]]; then
    printf '{"text":"","tooltip":"CodexBar: no provider data","class":"stale","percentage":0}\n'
    exit 0
fi

echo "$merged" | jq -c --arg now "$(date -u +%FT%TZ)" --arg bar_provider "$BAR_PROVIDER" '
    # Collect all usage windows across providers
    def provider_name(p):
        {codex:"Codex", claude:"Claude", gemini:"Gemini",
         copilot:"Copilot", openai:"OpenAI", cursor:"Cursor",
         vertexai:"Vertex AI", openrouter:"OpenRouter"}[p] // (p | ascii_upcase);

    # Insert spaces the providers omit. Claude OAuth gives "May 17 at 6:20AM"
    # (no space before AM/PM); Claude CLI gives "Resets6:20am(Europe/Paris)"
    # (no space anywhere). Normalise both to a single, consistent style.
    def normalize_reset:
        sub("^Resets(?=\\S)"; "Resets ")
        | sub("^resets(?=\\S)"; "resets ")
        | gsub("(?<=\\S)\\("; " (")
        | gsub(",(?=\\S)"; ", ")
        | gsub("(?<=\\d)(?=[AaPp][Mm]\\b)"; " ");

    def reset_phrase(d):
        if d == null then ""
        else (d | normalize_reset) as $clean
             | if ($clean | test("^[Rr]esets")) then " — \($clean)"
               else " — resets \($clean)" end
        end;

    def fmt_window(w; name):
        if w == null or w.usedPercent == null then empty
        else "\(name): \(w.usedPercent)%" + reset_phrase(w.resetDescription)
        end;

    def provider_lines(entry):
        if entry.error then
            "\(provider_name(entry.provider)): error — \(entry.error.message)"
        else
            [
                fmt_window(entry.usage.primary;   "\(provider_name(entry.provider)) primary"),
                fmt_window(entry.usage.secondary; "\(provider_name(entry.provider)) secondary"),
                fmt_window(entry.usage.tertiary;  "\(provider_name(entry.provider)) tertiary")
            ] | map(select(. != null)) | join("\n")
        end;

    def max_pct(entry):
        if entry.error then 0
        else
            [entry.usage.primary.usedPercent,
             entry.usage.secondary.usedPercent,
             entry.usage.tertiary.usedPercent]
            | map(select(. != null)) | (max // 0)
        end;

    def pct_or_null(w):
        if w == null or w.usedPercent == null then null
        else (w.usedPercent | floor) end;

    # When the user has pinned a provider for the bar text, surface session
    # and weekly inline ("3% • 12%"). Otherwise emit the global max%.
    def bar_text(entry):
        if entry == null or entry.error then "🤖 ⚠"
        else
            [pct_or_null(entry.usage.primary),
             pct_or_null(entry.usage.secondary)]
            | map(select(. != null))
            | if length == 0 then "🤖 —"
              elif length == 1 then "🤖 \(.[0])%"
              else "🤖 \(.[0])% • \(.[1])%" end
        end;

    . as $all
    | ($all | map(max_pct(.)) | max // 0) as $pct
    | ($all | map(provider_lines(.)) | map(select(. != ""))) as $lines
    | ($all | all(.error)) as $all_errored
    | ($all | any(.stale == true)) as $any_stale
    | (if $bar_provider == "" then null
       else ($all | map(select(.provider == $bar_provider)) | .[0]) end) as $pinned
    | {
        text: (if $pinned != null then bar_text($pinned)
               elif $all_errored then "🤖 ⚠"
               else "🤖 \($pct)%" end),
        tooltip: ($lines | join("\n")),
        class: (if $all_errored then "stale"
                elif $pct >= 90 then "critical"
                elif $pct >= 70 then "warning"
                elif $any_stale then "stale"
                else "ok" end),
        percentage: $pct
    }
'

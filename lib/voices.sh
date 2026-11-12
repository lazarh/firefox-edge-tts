#!/usr/bin/env bash
# Slice 2: the Edge TTS voice catalogue.
#
# Edge voices live on Microsoft's service: there are no model files to download
# and no checksums to verify. The catalogue itself reports each voice's gender
# and locale, which is exactly what speech-dispatcher and Firefox need.

DEFAULT_VOICE="bg-BG-BorislavNeural"

# Short list offered first in the interactive menu, before freeform entry.
POPULAR_VOICES=(
    "bg-BG-BorislavNeural:Bulgarian (Borislav) - the default for this script"
    "bg-BG-KalinaNeural:Bulgarian (Kalina)"
    "en-US-AriaNeural:US English (Aria)"
    "en-US-AndrewNeural:US English (Andrew)"
    "en-GB-SoniaNeural:UK English (Sonia)"
    "de-DE-KatjaNeural:German (Katja)"
    "fr-FR-DeniseNeural:French (Denise)"
)

require_jq() { have jq || die "jq is required (apt-get install jq) to read the voice catalogue."; }

# Fetch the catalogue to the cache file and return its path.
# All progress output goes to stderr: callers capture stdout as the path.
fetch_voices_index() {
    require_jq
    [ -x "$EDGE_VENV/bin/python" ] \
        || die "edge-tts is not installed yet; run: $0 --install"

    local tmp
    mkdir -p "$VOICE_CACHE_DIR"
    tmp=$(mktemp "$VOICE_CACHE.XXXXXX") || die "cannot write to $VOICE_CACHE_DIR"

    info "fetching the Edge TTS voice catalogue" >&2
    if ! "$EDGE_VENV/bin/python" - <<'PY' > "$tmp"
import asyncio
import json

import edge_tts

print(json.dumps(asyncio.run(edge_tts.list_voices()), ensure_ascii=False))
PY
    then
        rm -f "$tmp"
        die "could not fetch the voice catalogue (are you online?)"
    fi

    jq -e 'type == "array" and length > 0' "$tmp" >/dev/null 2>&1 \
        || { rm -f "$tmp"; die "the voice catalogue response was not valid JSON"; }

    mv "$tmp" "$VOICE_CACHE" || { rm -f "$tmp"; die "could not install $VOICE_CACHE"; }
    printf '%s\n' "$VOICE_CACHE"
}

# Return the cached catalogue, fetching it if needed. Pass "yes" to force a
# refresh from the service.
voices_index() {
    local refresh="${1:-no}"
    if [ "$refresh" = "yes" ] || [ ! -s "$VOICE_CACHE" ]; then
        fetch_voices_index
    else
        printf '%s\n' "$VOICE_CACHE"
    fi
}

refresh_voices() {
    local idx count
    idx=$(fetch_voices_index)
    count=$(jq 'length' "$idx")
    ok "voice catalogue refreshed ($count voices)"
    dim "default voice: $DEFAULT_VOICE"
}

# One field from the array entry whose ShortName is $2.
voice_field() {
    jq -r --arg k "$2" --arg f "$3" \
        '.[] | select(.ShortName == $k) | .[$f] // empty' "$1" | head -1
}

voice_gender()       { voice_field "$1" "$2" Gender; }
voice_locale()       { voice_field "$1" "$2" Locale; }
voice_friendly_name() { voice_field "$1" "$2" FriendlyName; }
voice_status()       { voice_field "$1" "$2" Status; }

voice_exists_in_index() {
    jq -e --arg k "$2" 'any(.[]; .ShortName == $k)' "$1" >/dev/null 2>&1
}

# speech-dispatcher voice type (MALE1/FEMALE1/...) for a catalogue voice.
voice_type_from_gender() {
    case "$1" in
        Female) printf 'FEMALE1\n' ;;
        Male)   printf 'MALE1\n' ;;
        *)      printf 'MALE1\n' ;;
    esac
}

voice_type() {
    local idx=$1 key=$2
    voice_type_from_gender "$(voice_gender "$idx" "$key")"
}

# Verify a freeform key has the catalogue's shape before hitting the network.
validate_voice_key() {
    local key=$1
    case "$key" in
        *[!A-Za-z0-9_-]*|'') die "Invalid voice name '$key'. Use a catalogue short name, e.g. bg-BG-BorislavNeural." ;;
    esac
}

# Validate a voice name against the catalogue (fetched or cached).
validate_voice() {
    local key=$1 idx
    validate_voice_key "$key"
    idx=$(voices_index)
    voice_exists_in_index "$idx" "$key" \
        || die "Voice '$key' is not in the Edge TTS catalogue. Run --refresh-voices and try again."
}

# Print every voice in the cached catalogue.
list_available_voices() {
    local idx
    idx=$(voices_index)
    log ""
    log "Edge TTS voices (cached catalogue):"
    jq -r '.[] | [.ShortName, .Gender, .Locale, .Status] | @tsv' "$idx" \
        | awk -F'\t' '{ printf "  %-36s %-8s %-8s %s\n", $1, $2, $3, $4 }'
    log ""
    dim "voices are provided online; refresh with: $0 --refresh-voices"
}

# Interactive menu: popular voices first, then freeform catalogue entry.
#
# Everything the user should SEE goes to stderr. The caller captures this
# function's stdout as the chosen voice, so printing the menu there would make
# the menu itself the "voice name".
choose_voice_interactively() {
    require_jq
    local idx
    idx=$(voices_index)

    log "" >&2
    log "Popular Edge TTS voices:" >&2
    local i entry key desc
    i=1
    for entry in "${POPULAR_VOICES[@]}"; do
        key=${entry%%:*}
        desc=${entry#*:}
        printf '  %2d) %-26s %s\n' "$i" "$key" "$C_DIM$desc$C_OFF" >&2
        i=$((i + 1))
    done
    printf '  %2d) %-26s %s\n' "$i" "custom" "$C_DIM(type any voice from the catalogue; see --list-voices)$C_OFF" >&2

    # A newline pressed while the catalogue was downloading is still buffered in
    # the terminal. Drain pending input so the menu does not auto-answer with the
    # default before the user has even read it.
    while IFS= read -r -t 0.05 _ </dev/tty 2>/dev/null; do :; done

    local choice
    printf '\nSelect a voice [1-%d, default 1]: ' "$i" >&2
    read -r choice </dev/tty || choice=""
    choice=${choice:-1}

    if [ "$choice" = "$i" ]; then
        printf 'Voice name (e.g. bg-BG-BorislavNeural): ' >&2
        read -r key </dev/tty || die "no voice selected"
        validate_voice_key "$key"
    else
        local n=0
        key=""
        for entry in "${POPULAR_VOICES[@]}"; do
            n=$((n + 1))
            [ "$n" -eq "$choice" ] && key=${entry%%:*}
        done
        [ -n "$key" ] || die "invalid selection: $choice"
    fi

    voice_exists_in_index "$idx" "$key" \
        || die "Voice '$key' is not in the Edge TTS catalogue."

    printf '%s\n' "$key"
}

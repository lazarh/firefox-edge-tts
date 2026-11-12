#!/usr/bin/env bash
# Slice 4: verification. Confirms the whole chain works before telling the user
# to open Firefox, so a failure is reported here rather than silently in Reader Mode.

# A short phrase in the voice's language. Falls back to English for non-Bulgarian
# voices so the test is not read with the wrong phonemes.
test_phrase_for_lang() {
    case "${1%%-*}" in
        bg) printf '%s' "Здравей, свят. Това е Edge TTS, който чете текста ти." ;;
        *)  printf '%s' "Hello, world. This is Edge TTS reading text for you." ;;
    esac
}

# Speak a phrase through speech-dispatcher and report whether audio was produced.
# Checks the wrapper directly (fast, no daemon) and then via spd-say (end-to-end).
test_voice() {
    local voice_key=$1 lang="${2:-$TEST_LANG}"
    local phrase bytes logdir pause pause_arg=()

    log ""
    info "testing $voice_key"

    if [ ! -x "$EDGE_SPEAK" ]; then
        err "edge-speak bridge not found: $EDGE_SPEAK"
        dim "re-run: $0 --install"
        return 1
    fi

    phrase=$(test_phrase_for_lang "$lang")

    # Exercise the same pause setting the module will use.
    pause=$(state_get pause 2>/dev/null || true)
    if [ -n "$pause" ] && [ "$pause" != "natural" ]; then
        pause_arg=(--pause "$pause")
    fi

    # 1. Direct wrapper check: real audio bytes from the online service.
    bytes=$(printf '%s' "$phrase" | "$EDGE_SPEAK" --voice "$voice_key" ${pause_arg[@]+"${pause_arg[@]}"} 2>/dev/null | wc -c)
    if [ "${bytes:-0}" -lt 1000 ]; then
        logdir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/speech-dispatcher/log"
        err "edge-tts produced no usable audio (${bytes} bytes)"
        dim "check that you are online and the service is reachable:"
        dim "  $EDGE_BIN --list-voices | head"
        dim "module log: $logdir/edge-tts.log"
        return 1
    fi
    ok "edge-tts synthesised $(human_size "$bytes") of audio"

    # 2. End-to-end check through speech-dispatcher, if a daemon is reachable.
    if have spd-say; then
        if spd-say -l "$lang" "$phrase" 2>/dev/null; then
            ok "speech-dispatcher accepted the request"
        else
            warn "spd-say could not reach speech-dispatcher; log in again and retry"
        fi
    fi

    log ""
    ok "verification passed"
}

# Print the manual Reader Mode check, plus what to do when it fails.
print_firefox_instructions() {
    local voice_key=$1 voice_set="${2:-no}" lang_short
    lang_short=$(state_get lang 2>/dev/null | cut -d- -f1)
    [ -n "$lang_short" ] || lang_short="$TEST_LANG"

    log ""
    info "try it in Firefox"
    cat <<EOF

  1. Start or restart Firefox ESR.
  2. Open any article and press ${C_BLU}Ctrl+R${C_OFF} to enter Reader Mode
     (View -> Reader Mode if the shortcut is taken).
  3. Press ${C_BLU}V${C_OFF} to start narration, or use the Listen button.
EOF

    if [ "$voice_set" = "no" ]; then
        cat <<EOF

  ${C_YLW}Firefox's Narrate voice was not switched, so it will still sound like
  espeak-ng. Close Firefox completely, then run:${C_OFF}

      ${C_BLU}$0 --set-firefox-voice${C_OFF}
EOF
    fi

    cat <<EOF

  Narrated articles should now sound like Edge TTS ($voice_key)
  rather than robotic espeak-ng.

${C_DIM}If narration is still robotic:${C_OFF}
  * Check the voice is registered:  spd-say -L | grep $voice_key
    ${C_DIM}(language must read "$lang_short", not the full locale)$C_OFF
  * Check the module log:       ${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}/speech-dispatcher/log/edge-tts.log
  * Point Firefox at edge-tts:  $0 --set-firefox-voice   ${C_DIM}(close Firefox first)$C_OFF
  * Re-run:                     $0 --test

  Edge TTS is online-only; if the service is unreachable, narration stops.

EOF
}

# Report what is installed without changing anything.
show_status() {
    log ""
    info "firefox-edge-tts status"

    if edge_available; then
        printf '  %-22s %s\n' "edge-tts runtime" "$(edge_version)"
    else
        printf '  %-22s %s\n' "edge-tts runtime" "$(printf '%snot installed%s' "$C_YLW" "$C_OFF")"
    fi

    if have firefox-esr; then
        printf '  %-22s %s\n' "firefox-esr" "$(firefox-esr --version 2>/dev/null || echo present)"
    else
        printf '  %-22s %s\n' "firefox-esr" "$(printf '%snot found%s' "$C_YLW" "$C_OFF")"
    fi

    if spd_is_configured; then
        printf '  %-22s %s\n' "speech-dispatcher" "$(printf '%sconfigured%s' "$C_GRN" "$C_OFF")"
    else
        printf '  %-22s %s\n' "speech-dispatcher" "$(printf '%snot configured%s' "$C_YLW" "$C_OFF")"
    fi

    local voice locale gender pause
    voice=$(state_get voice 2>/dev/null || true)
    if [ -n "$voice" ]; then
        locale=$(state_get lang 2>/dev/null || true)
        gender=$(state_get gender 2>/dev/null || true)
        printf '  %-22s %s\n' "configured voice" "$voice (${locale:-?}, ${gender:-?})"
    else
        printf '  %-22s %s\n' "configured voice" "$(printf '%snone%s' "$C_YLW" "$C_OFF")"
    fi

    pause=$(state_get pause 2>/dev/null || true)
    if [ -z "$pause" ] || [ "$pause" = "natural" ]; then
        printf '  %-22s %s\n' "paragraph pause" "service default (natural)"
    else
        printf '  %-22s %s\n' "paragraph pause" "${pause} ms after each paragraph"
    fi

    if [ -s "$VOICE_CACHE" ]; then
        printf '  %-22s %s\n' "voice catalogue" "$(jq 'length' "$VOICE_CACHE" 2>/dev/null || echo '?') voices cached"
    else
        printf '  %-22s %s\n' "voice catalogue" "$(printf '%snot fetched%s' "$C_YLW" "$C_OFF")"
    fi

    if piper_installed_any; then
        printf '  %-22s %s\n' "old firefox-piper" "$(printf '%spresent%s (remove with --cleanup-piper)' "$C_YLW" "$C_OFF")"
    fi

    log ""
}

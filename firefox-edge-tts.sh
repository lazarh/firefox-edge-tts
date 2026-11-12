#!/usr/bin/env bash
#
# firefox-edge-tts — install Edge TTS (edge-tts) and use it for Firefox ESR
# Reader Mode on Debian 13, replacing the robotic espeak-ng narration.
#
# The chain this wires up:
#   firefox-esr  ->  speech-dispatcher  ->  sd_generic  ->  edge-tts  ->  mpg123  ->  pw-cat
#
# Everything is installed per-user: no files in /etc, and the only root access is
# apt for the packages Debian already expects you to have.
#
# Edge TTS is an ONLINE service. Narration needs internet access, and the text
# being spoken is sent to Microsoft's speech endpoint. There is no local
# fallback: when the service is unreachable, narration stops.
#
# Usage:
#   firefox-edge-tts.sh --install          install (interactive voice menu)
#   firefox-edge-tts.sh --install --voice bg-BG-BorislavNeural   pick a voice directly
#   firefox-edge-tts.sh --install          non-interactively, using the default voice
#   firefox-edge-tts.sh --list-voices      voices in the cached catalogue
#   firefox-edge-tts.sh --refresh-voices   refresh the cached voice catalogue
#   firefox-edge-tts.sh --status           what is installed
#   firefox-edge-tts.sh --test             verify the chain works
#   firefox-edge-tts.sh --uninstall        remove and restore espeak-ng
#   firefox-edge-tts.sh --cleanup-piper    remove a leftover firefox-piper install
#   firefox-edge-tts.sh --set-firefox-voice   point Firefox's Narrate at edge-tts
#
# Note on --set-firefox-voice: CLOSE FIREFOX FIRST. Firefox rewrites its profile
# prefs from memory when it exits, so a preference change made while it is
# running is silently discarded. The script refuses to edit rather than appear to
# succeed and lose the change.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/edge.sh
. "$SCRIPT_DIR/lib/edge.sh"
# shellcheck source=lib/voices.sh
. "$SCRIPT_DIR/lib/voices.sh"
# shellcheck source=lib/speechd.sh
. "$SCRIPT_DIR/lib/speechd.sh"
# shellcheck source=lib/verify.sh
. "$SCRIPT_DIR/lib/verify.sh"
# shellcheck source=lib/firefox.sh
. "$SCRIPT_DIR/lib/firefox.sh"
# shellcheck source=lib/uninstall.sh
. "$SCRIPT_DIR/lib/uninstall.sh"

# Per-user locations. Debian 13 targets XDG paths.
EDGE_HOME="${EDGE_HOME:-$HOME/.local/share/edge-tts}"
EDGE_VENV="$EDGE_HOME/venv"
EDGE_BIN="$EDGE_HOME/bin/edge-tts"
EDGE_SPEAK="$EDGE_HOME/edge-speak"
VOICE_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/firefox-edge-tts"
VOICE_CACHE="$VOICE_CACHE_DIR/voices.json"

# Edge TTS always returns 24 kHz mono MP3; mpg123 decodes it to s16le at the
# same rate so the player never needs to know about MP3.
EDGE_SAMPLE_RATE=24000

# Default language used by --test when the state file has no language yet.
# Bulgarian is the project default and exercises non-Latin text end to end.
TEST_LANG="bg"

usage() {
    # Print the header comment block, minus the leading "# " and the shebang.
    sed -n '/^# firefox-edge-tts/,/^$/p' "${BASH_SOURCE[0]}" | sed -e 's/^# \{0,1\}//' -e '/^$/d'
}

# Install: preflight -> dependencies -> runtime -> voice -> configure -> verify.
do_install() {
    local voice="${1:-}"

    require_debian13
    require_espeak_fallback
    warn_if_piper_installed

    install_dependencies
    install_edge_runtime

    # Voice: explicit flag, else interactive menu, else the documented default.
    if [ -z "$voice" ]; then
        if is_interactive; then
            voice=$(choose_voice_interactively) || exit 1
        else
            voice="$DEFAULT_VOICE"
            dim "no --voice given and not interactive; using default $voice"
        fi
    fi

    validate_voice "$voice"

    configure_speech_dispatcher "$voice"
    restart_speech_dispatcher

    local lang
    lang=$(state_get lang 2>/dev/null || true)
    test_voice "$voice" "${lang:-$TEST_LANG}"

    # edge-tts being installed is not enough: Firefox still requests whatever
    # speech-dispatcher voice it had before, so it would keep speaking through
    # espeak-ng. Offer to repoint it now, rather than leaving the user with a
    # working install that sounds unchanged.
    log ""
    info "pointing Firefox's Narrate at edge-tts"
    local voice_set=no
    if set_firefox_voice "$voice"; then
        voice_set=yes
    else
        warn "could not update the Firefox voice automatically"
        dim "close Firefox, then run: $0 --set-firefox-voice"
    fi

    print_firefox_instructions "$voice" "$voice_set"
}

# Which voice is currently configured, for --test.
configured_voice() {
    [ -f "$SPD_STATE" ] || return 1
    state_get voice
}

main() {
    # No arguments shows help rather than installing. Installing needs network
    # and rewrites the user's speech-dispatcher config, so it must be asked for.
    local command="help" voice="" uninstall_args=()

    while [ $# -gt 0 ]; do
        case "$1" in
            --install)   command="install"; shift ;;
            --uninstall) command="uninstall"; shift ;;
            --test)      command="test"; shift ;;
            --set-firefox-voice) command="set-voice"; shift ;;
            --status)    command="status"; shift ;;
            --list-voices) command="list-voices"; shift ;;
            --refresh-voices) command="refresh-voices"; shift ;;
            --cleanup-piper) command="cleanup-piper"; shift ;;
            --voice)
                [ $# -ge 2 ] || die "--voice needs a voice name, e.g. bg-BG-BorislavNeural"
                voice="$2"; command="install"; shift 2 ;;
            --voice=*)   voice="${1#*=}"; command="install"; shift ;;
            -h|--help)   usage; return 0 ;;
            --version)   printf 'firefox-edge-tts (targets Debian 13, requires edge-tts >= %s)\n' "$EDGE_MIN_VERSION"; return 0 ;;
            # Passed through to uninstall so the flag works before or after the verb.
            --purge-packages) uninstall_args+=("$1"); shift ;;
            *) die "unknown option: $1 (try --help)" ;;
        esac
    done

    case "$command" in
        help)
            usage
            ;;
        install)
            do_install "$voice"
            ;;
        uninstall)
            uninstall_all ${uninstall_args[@]+"${uninstall_args[@]}"}
            ;;
        test)
            require_debian13
            local active lang
            active=$(configured_voice) || die "nothing configured yet; run: $0 --install"
            lang=$(state_get lang 2>/dev/null || true)
            test_voice "$active" "${lang:-$TEST_LANG}"
            print_firefox_instructions "$active" yes
            ;;
        set-voice)
            require_debian13
            local target
            target=$(configured_voice) || die "nothing configured yet; run: $0 --install"
            set_firefox_voice "$target"
            ;;
        status)
            show_status
            ;;
        list-voices)
            list_available_voices
            ;;
        refresh-voices)
            refresh_voices
            ;;
        cleanup-piper)
            require_debian13
            cleanup_piper_install
            ;;
    esac
}

main "$@"

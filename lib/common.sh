#!/usr/bin/env bash
# Shared helpers: logging, paths, and system guards.

# Colours only when attached to a terminal, so piped output stays clean.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$'\033[1;31m'; C_GRN=$'\033[1;32m'; C_YLW=$'\033[1;33m'
    C_BLU=$'\033[1;34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
    C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_DIM=''; C_OFF=''
fi

log()   { printf '%s\n' "$*"; }
info()  { printf '%s==>%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
ok()    { printf '%s  ok%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '%swarn%s %s\n' "$C_YLW" "$C_OFF" "$*" >&2; }
err()   { printf '%sfail%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die()   { err "$*"; exit 1; }
dim()   { printf '%s%s%s\n' "$C_DIM" "$*" "$C_OFF"; }

have() { command -v "$1" >/dev/null 2>&1; }

# Confirm we are on Debian 13 (trixie). Debian 13 is the only supported target;
# the package and speech-dispatcher landscape differs on other releases.
require_debian13() {
    have dpkg || die "dpkg not found; this script targets Debian 13."
    local version codename
    version=$(dpkg-query -W -f='${Version}' debian_version 2>/dev/null || true)
    [ -n "$version" ] || version=$(cut -d. -f1 /etc/debian_version 2>/dev/null)
    codename=$(. /etc/os-release 2>/dev/null && printf '%s' "${VERSION_CODENAME:-}")
    case "$version" in
        13|13.*) : ;;
        *) die "Debian 13 (trixie) required, found version '${version:-unknown}'. Out of scope for this script." ;;
    esac
    [ "$codename" = "trixie" ] || warn "Debian version 13 but codename '$codename' (expected 'trixie')."
}

# sudo only when we do not already have root, and never hang on a password prompt
# when running non-interactively.
sudo_() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif have sudo; then
        sudo "$@"
    else
        die "root required for: $* (install sudo or run as root)"
    fi
}

# True when the user can drive an interactive prompt. Used to decide whether a
# missing flag should abort or fall back to a menu.
is_interactive() { [ -t 0 ] && [ -t 1 ]; }

human_size() {
    local bytes=${1:-0}
    awk -v b="$bytes" 'BEGIN{
        split("B KiB MiB GiB", u, " ");
        i = 1;
        while (b >= 1024 && i < 4) { b /= 1024; i++ }
        printf (i == 1 ? "%d %s\n" : "%.1f %s\n"), b, u[i];
    }'
}

# Read a key from the state file written at install time. The file path is
# defined in lib/speechd.sh, but this helper is used from several slices.
state_get() {
    [ -f "$SPD_STATE" ] || return 1
    sed -n "s/^$1=//p" "$SPD_STATE" | head -1
}

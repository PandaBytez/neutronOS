#!/usr/bin/env bash
set -euo pipefail

# Seed the niri + Noctalia defaults.
#
# The niri config is NOT written here: it lives in /etc/skel so it is copied
# into every new account's home, and editing it per-user is the supported way to
# customise niri. Rewriting it from a system path on every boot would fight the
# user.
#
# What this does do is make sure the pieces the skel config depends on are
# actually present and consistent, and fail loudly if they are not.

echo "==> Checking niri + Noctalia wiring..."

# Install the system-wide niri config.
#
# /etc/skel is NOT enough: skel only populates home directories at account
# creation, so a user who rebased onto this image from an existing install never
# receives it, and niri silently falls back to its built-in defaults -- which
# spawn nothing and therefore never start Noctalia. /etc/niri/config.kdl is the
# system location niri reads when the user has no config of their own, so it
# covers both new and pre-existing accounts.
#
# niri picks exactly ONE config: $XDG_CONFIG_HOME/niri/config.kdl if present,
# otherwise /etc/niri/config.kdl. It does not merge them. A user who wants to
# customise copies the system file: `cp /etc/niri/config.kdl ~/.config/niri/`.
echo "==> Installing /etc/niri/config.kdl (system default for all users)..."
mkdir -p /etc/niri
install -m 0644 /etc/skel/.config/niri/config.kdl /etc/niri/config.kdl

fail=0
check() {
    local what="$1" path="$2"
    if [ -e "$path" ]; then
        echo "ok    $what"
    else
        echo "FAIL  $what (missing: $path)"
        fail=1
    fi
}

# Files the shipped config.kdl depends on.
check "niri session file"        /usr/share/wayland-sessions/niri.desktop
check "niri portal config"       /usr/share/xdg-desktop-portal/niri-portals.conf
check "niri systemd unit"        /usr/lib/systemd/user/niri.service
check "niri-session helper"      /usr/bin/niri-session
check "Noctalia desktop entry"   /usr/share/applications/dev.noctalia.Noctalia.desktop
check "skel niri config"         /etc/skel/.config/niri/config.kdl
check "system niri config"       /etc/niri/config.kdl
check "skel ghostty config"     /etc/skel/.config/ghostty/config
check "greetd config"            /etc/greetd/config.toml

# The config niri will actually read for an account with no personal config.
# This is the one that decides whether Noctalia starts at all, so assert the
# spawn is there and that nothing we removed is referenced.
sysconf=/etc/niri/config.kdl
if grep -qE '^\s*spawn-at-startup "noctalia"' "$sysconf"; then
    echo "ok    system config starts Noctalia at startup"
else
    echo "FAIL  $sysconf does not spawn noctalia -- sessions would start with no shell"
    fail=1
fi
if grep -qE '^\s*spawn-at-startup "waybar"|spawn "(fuzzel|swaylock)"' "$sysconf"; then
    echo "FAIL  $sysconf still spawns waybar/fuzzel/swaylock"
    fail=1
else
    echo "ok    system config spawns neither waybar, fuzzel nor swaylock"
fi

# The skel config must not reference anything we removed either.
if grep -qE '^\s*spawn-at-startup "waybar"|spawn "(fuzzel|swaylock)"' /etc/skel/.config/niri/config.kdl; then
    echo "FAIL  skel niri config still spawns waybar/fuzzel/swaylock"
    fail=1
else
    echo "ok    skel niri config spawns neither waybar, fuzzel nor swaylock"
fi

# The skel config must actually parse. Run it through niri's own validator
# against the installed niri, so a niri upgrade that changes the config schema
# fails the build instead of leaving users with an unbootable session.
if command -v niri >/dev/null 2>&1; then
    vdir=$(mktemp -d)
    mkdir -p "$vdir/.config/niri"
    cp /etc/skel/.config/niri/config.kdl "$vdir/.config/niri/config.kdl"
    if out=$(HOME="$vdir" niri validate 2>&1); then
        echo "ok    skel niri config validates against $(niri --version 2>/dev/null | head -1)"
    else
        echo "FAIL  skel niri config does not validate:"
        echo "$out" | head -12 | sed 's/^/        /'
        fail=1
    fi
    rm -rf "$vdir"
fi

if [ "$fail" -ne 0 ]; then
    echo "==> niri/Noctalia wiring FAILED"
    exit 1
fi
echo "==> niri + Noctalia wiring OK."

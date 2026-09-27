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
check "skel alacritty config"    /etc/skel/.config/alacritty/alacritty.toml
check "greetd config"            /etc/greetd/config.toml

# The skel config must not reference anything we removed.
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

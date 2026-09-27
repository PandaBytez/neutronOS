#!/usr/bin/env bash
# Build gate: assert the image really is niri-only, and that nothing we meant
# to keep was stripped along the way. Any failure aborts the build.
set -euo pipefail

fail=0

absent() {
    local found
    found=$(rpm -qa --qf '%{name}\n' | grep -E "$1" | tr '\n' ' ' || true)
    if [ -n "$found" ]; then
        echo "FAIL  still installed: $found"
        fail=1
    else
        echo "ok    absent: $1"
    fi
}

present() {
    local missing
    missing=$(rpm -q "$@" 2>&1 | grep 'not installed' | tr '\n' ' ' || true)
    if [ -n "$missing" ]; then
        echo "FAIL  missing: $missing"
        fail=1
    else
        echo "ok    present: $*"
    fi
}

echo "==> Verifying desktop stack"

# --- No KDE, and no KDE collateral. bazzite-gnome never shipped Plasma; this
# --- guards against a base bump reintroducing it, and against the install
# --- closure dragging KF6/Breeze back in.
absent '^(plasma-|libplasma|kwin|kwin_wayland|ksmserver|kded|kwallet)'
absent '^(sddm|plasmalogin|plasma-login-manager)'
absent '^kf6-(kirigami|sonnet|qqc2|kitemmodels|purpose|kdeclarative|bluez|prison|kded)'
absent '^(kde-l10n|kde-i18n|kdeaccessibility|kde-style-)'

# --- No GNOME desktop. Deliberately NOT a blanket ^gnome- ban:
# --- xdg-desktop-portal-gnome is required by niri for screencast, and it pulls
# --- gnome-desktop / gnome-menus in as libraries. Those are libraries, not a
# --- desktop, and the specific pieces below are what must be gone.
absent '^(gnome-shell|gnome-session|gnome-settings-daemon|gnome-control-center)'
absent '^(gdm|mutter|yelp|nautilus)'
absent '^(gnome-bluetooth|gnome-disk-utility|gnome-color-manager|gnome-remote-desktop)'
absent '^(evolution-.*|gcr)$'
# epiphany (GNOME Web) was the base's only browser; the default is LibreWolf.
absent '^epiphany'
# Non-free, dropped deliberately for a redistributable public image.
absent '^displaylink'

# --- No leftover desktop from earlier iterations of this image.
absent '^(cosmic-|ptyxis|vicinae|yazi|ghostty|Thunar)'

# --- The session itself.
present niri noctalia tuigreet alacritty greetd
present xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
present fish accountsservice

# Files, not packages, that the desktop depends on.
for f in /usr/share/wayland-sessions/niri.desktop \
         /usr/share/xdg-desktop-portal/niri-portals.conf \
         /usr/lib/systemd/user/niri.service \
         /usr/bin/niri-session \
         /etc/greetd/config.toml \
         /etc/skel/.config/niri/config.kdl \
         /etc/skel/.config/alacritty/alacritty.toml; do
    if [ -e "$f" ]; then
        echo "ok    file: $f"
    else
        echo "FAIL  missing file: $f"
        fail=1
    fi
done

# --- Shared infrastructure the strip must not have taken with it.
present mesa-dri-drivers mesa-libEGL pipewire
present gnome-keyring gnome-keyring-pam gvfs avahi bluez flatpak

# --- The gaming layer from the bazzite base must survive the strip, including
# --- the OGC kernel this image exists for.
present terra-gamescope terra-mangohud terra-release-mesa steam
if rpm -q kernel-core | grep -q -- '-ogc'; then
    echo "ok    OGC kernel: $(rpm -q kernel-core)"
else
    echo "FAIL  OGC kernel missing: $(rpm -q kernel-core 2>&1)"
    fail=1
fi

# --- Display manager and shell.
if systemctl is-enabled greetd.service >/dev/null 2>&1; then
    echo "ok    enabled: greetd.service"
else
    echo "FAIL  greetd.service is not enabled"
    fail=1
fi
if grep -q tuigreet /etc/greetd/config.toml; then
    echo "ok    greetd uses tuigreet"
else
    echo "FAIL  greetd config does not reference tuigreet"
    fail=1
fi
if grep -qx "/usr/bin/fish" /etc/shells; then
    echo "ok    /etc/shells lists /usr/bin/fish"
else
    echo "FAIL  /etc/shells does not list /usr/bin/fish"
    fail=1
fi
if grep -qx "SHELL=/usr/bin/fish" /etc/default/useradd; then
    echo "ok    useradd default shell: /usr/bin/fish"
else
    echo "FAIL  /etc/default/useradd SHELL is not /usr/bin/fish"
    fail=1
fi

# --- LibreWolf must be the system default browser. /etc/xdg/mimeapps.list is
# --- the system-wide location; ~/.config/mimeapps.list would be root's.
# --- The flatpaks come from BlueBuild's default-flatpaks module, which the
# --- local Containerfile does not reproduce, so this block self-skips when the
# --- flatpak is genuinely absent rather than reporting a misleading failure.
mime=/etc/xdg/mimeapps.list
if flatpak list --system --app --columns=application 2>/dev/null | grep -q 'io.gitlab.librewolf-community'; then
    for m in x-scheme-handler/http x-scheme-handler/https text/html; do
        if grep -qE "^$m=io\.gitlab\.librewolf-community\.desktop$" "$mime" 2>/dev/null; then
            echo "ok    default for $m: LibreWolf"
        else
            echo "FAIL  $m is not defaulted to LibreWolf in $mime"
            fail=1
        fi
    done
else
    echo "skip  LibreWolf flatpak not installed (BlueBuild default-flatpaks module)"
    if grep -qE '^x-scheme-handler/https=' "$mime" 2>/dev/null; then
        echo "ok    https handler still declared in $mime"
    else
        echo "FAIL  $mime has no https handler at all"
        fail=1
    fi
fi
# The base ships a Bazaar entry; appending must not have destroyed it.
if grep -q 'io.github.kolunmi.Bazaar.desktop' "$mime" 2>/dev/null; then
    echo "ok    base Bazaar MIME entry preserved"
else
    echo "FAIL  base Bazaar MIME entry was lost"
    fail=1
fi

# --- The symlinked system directories must resolve, or scripts that write to
# --- them silently abort under set -e.
for d in /opt /usr/local; do
    if [ -d "$d" ]; then
        echo "ok    $d resolves -> $(readlink -f "$d")"
    else
        echo "FAIL  $d does not resolve"
        fail=1
    fi
done

# --- No stale session files for desktops that are not installed.
leftover=$(ls /usr/share/wayland-sessions/ 2>/dev/null \
    | grep -E '^(plasma|gnome|hyprland|cosmic|sway|hypr)' | tr '\n' ' ' || true)
if [ -n "$leftover" ]; then
    echo "FAIL  stale session files: $leftover"
    fail=1
else
    echo "ok    no Plasma/GNOME/Hyprland/COSMIC session files"
fi

if [ "$fail" -ne 0 ]; then
    echo "==> Desktop verification FAILED"
    exit 1
fi
echo "==> Desktop verification passed: niri-only, no KDE, no GNOME desktop."

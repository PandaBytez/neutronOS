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
present fish accountsservice cliphist wlsunset brightnessctl playerctl wl-clipboard

# Noctalia drives monitor brightness through ddcutil. The base provides it as
# terra-ddcutil, so assert the capability rather than the package name --
# installing Fedora's ddcutil on top is a hard conflict.
#
# Command substitution, not `rpm -qa ... | grep -qx`. The -q makes grep exit on
# the first match, rpm takes SIGPIPE and dies 141, and under `set -o pipefail`
# that turns a successful match into a false failure. Every other check in this
# script uses the substitution form for the same reason.
ddc_providers=$(rpm -qa --qf '%{name}\n' | grep -xE '(terra-)?ddcutil' | tr '\n' ' ' || true)
if [ -n "$ddc_providers" ]; then
    echo "ok    ddcutil provider present: $ddc_providers"
else
    echo "FAIL  no ddcutil provider (need ddcutil or terra-ddcutil for Noctalia brightness)"
    fail=1
fi

# Files, not packages, that the desktop depends on.
for f in /usr/share/wayland-sessions/niri.desktop \
         /usr/share/xdg-desktop-portal/niri-portals.conf \
         /usr/lib/systemd/user/niri.service \
         /usr/bin/niri-session \
         /etc/greetd/config.toml \
         /etc/skel/.config/niri/config.kdl \
         /etc/niri/config.kdl \
         /etc/skel/.config/alacritty/alacritty.toml; do
    if [ -e "$f" ]; then
        echo "ok    file: $f"
    else
        echo "FAIL  missing file: $f"
        fail=1
    fi
done

# The system niri config is the one every account reads when it has no personal
# config, and the only thing that starts Noctalia. Assert both the file and the
# spawn line, so this cannot silently regress the way skel-only did.
if [ -e /etc/niri/config.kdl ]; then
    if grep -qE '^[[:space:]]*spawn-at-startup "noctalia"' /etc/niri/config.kdl; then
        echo "ok    /etc/niri/config.kdl starts Noctalia"
    else
        echo "FAIL  /etc/niri/config.kdl does not spawn noctalia"
        fail=1
    fi
    if grep -qE '^[[:space:]]*spawn-at-startup "waybar"|spawn "(fuzzel|swaylock)"' /etc/niri/config.kdl; then
        echo "FAIL  /etc/niri/config.kdl still spawns waybar/fuzzel/swaylock"
        fail=1
    else
        echo "ok    /etc/niri/config.kdl references no removed component"
    fi
else
    echo "FAIL  /etc/niri/config.kdl missing -- skel alone does not cover existing accounts"
    fail=1
fi

# --- Shared infrastructure the strip must not have taken with it.
present mesa-dri-drivers mesa-libEGL pipewire

# GameMode. The package is not enough: Fedora ships no user-preset for it, so
# the daemon is only running if the wants symlink exists. Assert all three --
# package, unit, and enablement -- because "installed" silently not running is
# exactly the failure nobody notices until a game stutters.
present gamemode
if [ -e /usr/lib/systemd/user/gamemoded.service ]; then
    echo "ok    gamemoded user unit present"
else
    echo "FAIL  /usr/lib/systemd/user/gamemoded.service missing"
    fail=1
fi
if [ -L /etc/systemd/user/default.target.wants/gamemoded.service ] || \
   [ -e /etc/systemd/user/default.target.wants/gamemoded.service ]; then
    echo "ok    gamemoded enabled for every user"
else
    echo "FAIL  gamemoded is not enabled -- the package ships no preset, so it never starts"
    fail=1
fi
# The auto-activation shim is what makes it work without per-game config.
if rpm -ql gamemode 2>/dev/null | grep -q 'libgamemodeauto\.so'; then
    echo "ok    libgamemodeauto present (auto-activation)"
else
    echo "FAIL  libgamemodeauto missing -- games would need gamemoderun manually"
    fail=1
fi
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

# The greeter's privilege-drop user must actually exist, or greetd cannot start
# and the machine comes up to a black screen. systemd-sysusers creates it at boot
# from /usr/lib/sysusers.d/greetd.conf, so in a build container it is absent from
# /etc/passwd -- accept either an existing account or a sysusers declaration.
greeter_user=$(sed -n 's/^user[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' /etc/greetd/config.toml)
if [ -z "$greeter_user" ]; then
    echo "ok    greetd has no user= (runs the greeter as root)"
elif getent passwd "$greeter_user" >/dev/null 2>&1; then
    echo "ok    greetd user exists: $greeter_user"
elif grep -rqsE "^u[[:space:]]+$greeter_user[[:space:]]" /usr/lib/sysusers.d/; then
    echo "ok    greetd user '$greeter_user' is created by sysusers at boot"
else
    echo "FAIL  greetd user '$greeter_user' exists in neither /etc/passwd nor sysusers.d -- greetd will fail to start"
    fail=1
fi

# The greeter's state directory. tuigreet writes its last-user/session state
# here, and it is created by greetd's tmpfiles.d at boot.
if [ -d /var/lib/greetd ]; then
    echo "ok    /var/lib/greetd present"
else
    echo "FAIL  /var/lib/greetd missing (greetd tmpfiles.d should create it)"
    fail=1
fi

# The greeter binary greetd is told to run must exist and be executable. The
# command is a bare name in config.toml, so resolve it through PATH -- testing
# [ -x tuigreet ] would look for it relative to the cwd and always fail.
greeter_cmd=$(sed -n 's/^command[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' /etc/greetd/config.toml | awk '{print $1}')
greeter_path=$(command -v "$greeter_cmd" 2>/dev/null || true)
if [ -z "$greeter_cmd" ]; then
    echo "FAIL  could not parse the greeter command from /etc/greetd/config.toml"
    fail=1
elif [ -n "$greeter_path" ] && [ -x "$greeter_path" ]; then
    echo "ok    greetd session command is executable: $greeter_cmd -> $greeter_path"
else
    echo "FAIL  greetd session command not found on PATH: ${greeter_cmd:-<unparsed>}"
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

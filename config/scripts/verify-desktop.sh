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
# Non-free, dropped deliberately for a redistributable public image. The base
# has not shipped it since the move off bazzite-gnome, so this is a licensing
# guard rather than a fix.
absent '^displaylink'

# --- No gaming stack. This image was a gaming image (bazzite-gnome, OGC kernel,
# --- Steam) and stopped being one; the base moved to ublue-os/base-main to make
# --- that possible. base-main is a stable tag, so a future bump could quietly
# --- bring any of this back. Assert its absence for the same reason the KDE and
# --- GNOME bans above exist.
absent '^(steam|proton|gamescope|gamemode|terra-|lutris|heroic)'

# --- No leftover desktop from earlier iterations of this image.
absent '^(cosmic-|ptyxis|vicinae|yazi|ghostty|Thunar)'

# --- The session itself.
present niri noctalia tuigreet alacritty greetd
present xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk
present fish accountsservice cliphist wlsunset brightnessctl playerctl wl-clipboard

# Noctalia drives monitor brightness through ddcutil.
#
# This used to accept `terra-ddcutil` as an alternative provider, because the
# old bazzite-gnome base shipped that and installing Fedora's ddcutil over it was
# a hard conflict. Both halves of that are now false: base-main has no terra
# repo, so terra-ddcutil cannot be present (it is banned above), and the recipe
# deliberately installs Fedora's ddcutil. So this is now a plain presence check.
#
# Command substitution, not `rpm -q ddcutil | grep -qx`. The -q makes grep exit on
# the first match, rpm takes SIGPIPE and dies 141, and under `set -o pipefail`
# that turns a successful match into a false failure. Every other check in this
# script uses the substitution form for the same reason.
present ddcutil

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

# --- Desktop runtime infrastructure. base-main has no desktop, so these are
# --- declared explicitly in the recipe rather than inherited. Assert them all:
# --- each one is a silent, confusing failure if the base ever stops providing
# --- it. NetworkManager is the critical one -- this is a laptop image, and a
# --- missing NetworkManager means no Wi-Fi after a reboot, with no error on the
# --- console beyond the icon not appearing.
present pipewire wireplumber
present gnome-keyring gnome-keyring-pam gvfs avahi bluez flatpak
present NetworkManager mesa-dri-drivers mesa-libEGL mesa-vulkan-drivers

# --- The kernel must be the stock signed Fedora one, NOT the OGC gaming kernel.
# --- This is the assertion that pins the bazzite-gnome -> base-main move: OGC
# --- was Bazzite's default kernel and would be a silent regression, since it
# --- still boots fine and nothing else here would notice.
kernel=$(rpm -q kernel-core 2>/dev/null || true)
if [ -z "$kernel" ]; then
    # "no -ogc in the output" is not the same as "a stock kernel is installed".
    # An absent kernel-core would otherwise sail through this check.
    echo "FAIL  kernel-core is not installed"
    fail=1
elif printf '%s' "$kernel" | grep -q -- '-ogc'; then
    echo "FAIL  OGC gaming kernel present, want the stock Fedora kernel: $kernel"
    fail=1
else
    echo "ok    stock kernel: $kernel"
fi

# --- TLP. The package alone does nothing: it ships a systemd service with no
# --- preset that starts TLP and applies /etc/tlp.conf, so without the unit
# --- being enabled a DE-less session silently has no power management at all
# --- and the laptop just runs hot and flat. Assert package, binary and
# --- enablement -- "installed but not running" is the failure mode.
present tlp
if [ -x /usr/sbin/tlp ]; then
    echo "ok    tlp binary: /usr/sbin/tlp"
else
    echo "FAIL  /usr/sbin/tlp missing or not executable"
    fail=1
fi
if systemctl is-enabled tlp.service >/dev/null 2>&1; then
    echo "ok    enabled: tlp.service"
else
    echo "FAIL  tlp.service is not enabled -- battery and thermals unmanaged"
    fail=1
fi
# tlp-pd is the power-profiles-daemon integration. There is no
# power-profiles-daemon in a DE-less image, so shipping it would be dead
# weight that also creates a second thing that thinks it owns power policy.
absent '^(tlp-pd|power-profiles-daemon)$'

# --- The development layer. Container toolchains are the point of this image.
present podman podman-docker uidmap distrobox
present gcc gcc-c++ make cmake ninja-build pkgconf-pkg-config gdb
present git git-delta git-lfs ripgrep fd-find bat eza tree fzf zoxide direnv
present tmux lazygit gh jq yq shellcheck shfmt btop sqlite man-pages

# podman-docker is what provides the `docker` CLI. Distros, Dockerfiles and CI
# docs assume it exists, and its absence is confusing rather than obvious.
if [ -x /usr/bin/docker ]; then
    echo "ok    docker CLI shim present (podman-docker)"
else
    echo "FAIL  /usr/bin/docker missing -- podman-docker did not provide the shim"
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

# The greeter's state directory, created at boot by greetd's tmpfiles.d.
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

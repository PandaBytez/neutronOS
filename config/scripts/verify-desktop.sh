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
#
# The terra-* alternation is deliberately NARROW. We now install terra-release on
# purpose, to get Ghostty and the Nerd Font, so a blanket `^terra-` ban would fail
# every build. What must never come back are the patched, gaming-oriented builds
# the old base shipped: terra-gamescope, terra-mangohud, terra-ddcutil, and the
# subrepos that carry patched versions of Fedora packages.
absent '^(steam|proton|gamescope|gamemode|lutris|heroic)'
absent '^terra-(gamescope|mangohud|ddcutil|client|systemd|udisk$|release-(mesa|extras|nvidia|multimedia))'

# --- Terra, the one third-party repo, scoped as narrowly as it can be.
#
# Only the base `terra` repo may be enabled. `terra-release-extras` is the
# dangerous one: its own docs say it carries "packages which conflict with Fedora
# packages in some way, such as being a patched version of the same package".
# That is also the most plausible route by which the KF6 leftovers this image
# used to strip would come back. Assert the repo file exists and the extras
# subrepo is absent.
if [ -f /etc/yum.repos.d/terra.repo ]; then
    echo "ok    Terra repo enabled (ghostty + nerd fonts source)"
else
    echo "FAIL  /etc/yum.repos.d/terra.repo missing -- ghostty could not have been installed"
    fail=1
fi
absent '^terra-release-(extras|mesa|nvidia|multimedia)$'

# --- No leftover desktop from earlier iterations of this image.
# ghostty was on this list as a leftover from an earlier iteration and is now the
# shipped terminal, so it was removed. Do not re-add it.
absent '^(cosmic-|ptyxis|vicinae|yazi|Thunar)'

# --- The session itself.
present niri noctalia ghostty greetd
# tuigreet is the fallback login screen, kept installed on purpose: a broken
# greeter means no way to log in without a live USB. post-install.sh documents the
# one-line switch in the README.
present tuigreet
present noctalia-greeter dbus-daemon polkit
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
         /etc/skel/.config/ghostty/config; do
    if [ -e "$f" ]; then
        echo "ok    file: $f"
    else
        echo "FAIL  missing file: $f"
        fail=1
    fi
done

# --- The terminal binding. niri spawns the terminal by bare name, so a config
# --- that still says "alacritty" after Alacritty was removed does not error --
# --- Mod+T just silently does nothing. That is the exact failure the build gate
# --- exists to catch, so assert the binary and the spawn line agree.
present jetbrainsmono-nerd-fonts
if command -v ghostty >/dev/null 2>&1; then
    echo "ok    ghostty on PATH: $(command -v ghostty)"
else
    echo "FAIL  ghostty not on PATH"
    fail=1
fi
for cfg in /etc/skel/.config/niri/config.kdl /etc/niri/config.kdl; do
    [ -e "$cfg" ] || continue
    if grep -qE 'spawn "ghostty"' "$cfg"; then
        echo "ok    $cfg spawns ghostty"
    else
        echo "FAIL  $cfg does not spawn ghostty -- Mod+T would be dead"
        fail=1
    fi
    if grep -q 'alacritty' "$cfg"; then
        echo "FAIL  $cfg still references alacritty, which is no longer installed"
        fail=1
    fi
done
# The shipped ghostty config must name the Nerd Font, not the plain one. Fedora
# also packages jetbrains-mono-fonts, so a careless downgrade would still leave a
# font installed and merely break every icon in eza/bat/fzf output.
if grep -qE '^font-family[[:space:]]*=[[:space:]]*JetBrainsMono Nerd Font' \
        /etc/skel/.config/ghostty/config; then
    echo "ok    ghostty config requests the Nerd Font"
else
    echo "FAIL  ghostty config does not request JetBrainsMono Nerd Font"
    fail=1
fi

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
if grep -q 'noctalia-greeter-session' /etc/greetd/config.toml; then
    echo "ok    greetd uses noctalia-greeter-session"
else
    echo "FAIL  greetd config does not reference noctalia-greeter-session"
    fail=1
fi
# greetd must run the SESSION wrapper, not the UI binary. The wrapper starts the
# bundled wlroots compositor the UI runs inside; pointing greetd at
# `noctalia-greeter` directly leaves WAYLAND_DISPLAY unset and the login screen
# never appears.
#
# Compare the BASENAME of the resolved command rather than pattern-matching the
# file: post-install.sh writes an absolute path, so a regression to
# command = "/usr/bin/noctalia-greeter" would not match a pattern anchored on
# the bare name.
greeter_bin=$(sed -n 's/^command[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    /etc/greetd/config.toml | awk '{print $1}' | xargs -r basename 2>/dev/null || true)
if [ "$greeter_bin" = "noctalia-greeter" ]; then
    echo "FAIL  greetd runs the greeter UI directly; it must run noctalia-greeter-session"
    fail=1
else
    echo "ok    greetd does not run the bare greeter binary (runs: ${greeter_bin:-<unparsed>})"
fi
# --session niri is pinned so a future second session cannot silently become the
# default. Resolve it the same way the compositor's own session file is checked.
if grep -qE 'command[[:space:]]*=.*--session niri' /etc/greetd/config.toml; then
    echo "ok    greetd pins --session niri"
else
    echo "FAIL  greetd does not pin --session niri"
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

# The greeter's state directory is created at BOOT, so assert the tmpfiles.d
# drop-in rather than the directory. Checking the directory here would pass in the
# build container -- /var is writable during a build -- while telling us nothing
# about the deployed system, because /var is a separate partition in a bootc image
# and build-time content there does not ship.
if [ -f /usr/lib/tmpfiles.d/neutronos-greeter.conf ]; then
    if grep -q '^d /var/lib/noctalia-greeter' /usr/lib/tmpfiles.d/neutronos-greeter.conf; then
        echo "ok    tmpfiles.d creates /var/lib/noctalia-greeter at boot"
    else
        echo "FAIL  neutronos-greeter.conf does not create /var/lib/noctalia-greeter"
        fail=1
    fi
else
    echo "FAIL  /usr/lib/tmpfiles.d/neutronos-greeter.conf missing -- the greeter has no state dir on the deployed system"
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

# --- The installer, /usr/bin/neutronos-install --------------------------------
#
# This is a shipped feature, not a convenience: it is how a machine gets a
# neutronOS on it. Assert the pieces it depends on, because every one of them
# fails halfway through wiping a disk if it is missing, which is the worst
# possible time to find out.
present cryptsetup btrfs-progs dosfstools tpm2-tools newt

# newt is the RPM that ships /usr/bin/whiptail, and whichname the RPM is called
# is not the capability we care about. Assert the binary, the way the Mesa and
# ddcutil checks assert the capability rather than the provider.
for tool in whiptail bootc; do
    if path=$(command -v "$tool" 2>/dev/null || true) && [ -n "$path" ]; then
        echo "ok    installer tool: $tool -> $path"
    else
        echo "FAIL  installer tool not on PATH: $tool"
        fail=1
    fi
done

# The installer passes these to `bootc install to-filesystem`; if a bootc upgrade
# renames or drops one, the installer fails at install time rather than at build
# time, so assert the interface here instead.
tofs_help=$(bootc install to-filesystem --help 2>&1 || true)
for flag in --karg --root-mount-spec --boot-mount-spec --skip-finalize; do
    found=$(printf '%s\n' "$tofs_help" | grep -F -c -- "$flag" || true)
    if [ "${found:-0}" -gt 0 ]; then
        echo "ok    bootc install to-filesystem supports $flag"
    else
        echo "FAIL  bootc install to-filesystem no longer supports $flag; the installer needs it"
        fail=1
    fi
done
if bootc install finalize --help >/dev/null 2>&1; then
    echo "ok    bootc install finalize exists"
else
    echo "FAIL  bootc install finalize missing; the installer cannot finalize the target"
    fail=1
fi

# Which bootloader and root filesystem this image hands `bootc install` is the
# image's business, not the installer's -- it adapts. Log the resolved config so
# a base bump that changes it is visible in the build log.
install_cfg=$(cat /usr/lib/bootc/install/*.toml /etc/bootc/install/*.toml 2>/dev/null | tr '\n' ' ' || true)
echo "info  bootc install config:${install_cfg:- <none, bootc defaults apply>}"

# --- Anything not in Fedora comes from Homebrew --------------------------------
#
# `lazygit` is not packaged for Fedora, and asking rpm-ostree for it fails the
# whole build with "Packages not found". It is a Homebrew formula instead, applied
# in one batch from the image's Brewfile rather than by asking users to type
# `brew install` after every rebase.
brewfile=/usr/share/homebrew/Brewfile
if [ -f "$brewfile" ] && grep -Eq '^brew "lazygit"' "$brewfile"; then
    echo "ok    Homebrew bundle carries the non-Fedora CLI tools: $brewfile"
else
    echo "FAIL  $brewfile missing or has no lazygit -- nothing provides it, since Fedora does not"
    fail=1
fi
if systemctl is-enabled neutronos-brew-bundle.service >/dev/null 2>&1; then
    echo "ok    neutronos-brew-bundle.service enabled"
else
    echo "FAIL  neutronos-brew-bundle.service not enabled; the Brewfile would never be applied"
    fail=1
fi

# newuidmap/newgidmap are what rootless podman and the first `distrobox enter`
# need. Fedora puts them in shadow-utils; `uidmap` is the Debian package name and
# does not exist in Fedora, which is what broke the build. Assert the capability
# rather than a package name, so a base bump that moves the binaries fails the
# build instead of breaking every container silently.
if command -v newuidmap >/dev/null 2>&1; then
    echo "ok    newuidmap present: $(command -v newuidmap) (rootless podman)"
else
    echo "FAIL  newuidmap missing -- rootless podman and distrobox cannot map subordinate UIDs"
    fail=1
fi

if [ -x /usr/bin/neutronos-install ]; then
    echo "ok    installer present and executable: /usr/bin/neutronos-install"
else
    # BlueBuild's files module has no mode key, so the committed git exec bit is
    # the only thing that makes this executable in the CI image.
    echo "FAIL  /usr/bin/neutronos-install missing or not executable"
    fail=1
fi

# The live ISO has to start the installer by itself, with nothing typed. That
# works by a systemd unit taking tty1, gated on the kernel argument that
# disk_config/live.toml appends, while the greeter is condition-skipped so the two
# do not fight over the VT. Both halves are required: with only the unit, the
# greeter races it; with only the drop-in, there is no installer at all.
install_unit=/usr/lib/systemd/system/neutronos-install.service
if [ -f "$install_unit" ]; then
    echo "ok    installer service present: $install_unit"
else
    echo "FAIL  $install_unit missing; the live ISO would boot to nothing"
    fail=1
fi
# systemctl is-enabled is a symlink check and works in the build container, which
# is how the greetd and tlp checks above already work. `systemctl cat` is not used
# here on purpose: it wants a running systemd.
if systemctl is-enabled neutronos-install.service >/dev/null 2>&1; then
    echo "ok    neutronos-install.service enabled"
else
    echo "FAIL  neutronos-install.service not enabled; the live ISO would not start it"
    fail=1
fi
greetd_live_dropin=/usr/lib/systemd/system/greetd.service.d/10-neutronos-live.conf
if [ -f "$greetd_live_dropin" ] &&
    grep -q '^ConditionKernelCommandLine=!neutronos.live' "$greetd_live_dropin"; then
    echo "ok    greeter skipped on the live ISO: $greetd_live_dropin"
else
    echo "FAIL  $greetd_live_dropin missing or wrong -- the greeter would fight the installer for vt1"
    fail=1
fi
if grep -q 'TTYPath=/dev/tty1' "$install_unit"; then
    echo "ok    installer service takes tty1 (whiptail needs a controlling terminal)"
else
    echo "FAIL  $install_unit has no TTYPath=/dev/tty1; whiptail will fail to start"
    fail=1
fi
# The single source of truth for "this is the live session", and the one thing
# that must agree between the ISO build and the unit.
if [ -f disk_config/live.toml ] && grep -q 'neutronos.live=1' disk_config/live.toml; then
    echo "ok    disk_config/live.toml appends the marker the installer unit looks for"
else
    echo "skip  disk_config/live.toml not in the build context (only present in a source checkout)"
fi
# The single source of truth for "this is the live session", and the one thing
# that must agree between the ISO build and the unit.
if [ -f disk_config/live.toml ] && grep -q 'neutronos.live=1' disk_config/live.toml; then
    echo "ok    disk_config/live.toml appends the marker the installer unit looks for"
else
    echo "skip  disk_config/live.toml not in the build context (only present in a source checkout)"
fi

# TPM2 auto-unlock is documented as `sudo luks-enable-tpm2-autounlock` after the
# first boot. That script comes from ublue-os-luks in the base, and it is the
# whole reason the installer does not ship its own enrolment code.
if command -v luks-enable-tpm2-autounlock >/dev/null 2>&1; then
    echo "ok    TPM2 auto-unlock available (ublue-os-luks)"
else
    echo "FAIL  luks-enable-tpm2-autounlock missing -- ublue-os-luks is not in the base"
    fail=1
fi

# The initramfs is what actually unlocks the disk at boot, and dracut-install
# silently omits the tpm2-tss module when its userspace binaries are absent from
# the image -- so the enrolment script would appear to work and the disk would
# never auto-unlock. Check the initramfs, not just the package.
# Per the README: never `cmd | grep -q` under pipefail, always command substitution.
initramfs=$(ls -1 /usr/lib/modules/*/initramfs.img 2>/dev/null | head -1 || true)
if [ -z "$initramfs" ]; then
    echo "skip  no /usr/lib/modules/*/initramfs.img; cannot check for tpm2-tss"
else
    modules=$(lsinitrd "$initramfs" 2>/dev/null | grep -F 'tpm2-tss' || true)
    if [ -n "$modules" ]; then
        echo "ok    initramfs carries tpm2-tss: $initramfs"
    else
        echo "FAIL  $initramfs has no tpm2-tss module; TPM2 auto-unlock cannot work"
        fail=1
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "==> Desktop verification FAILED"
    exit 1
fi
echo "==> Desktop verification passed: niri-only, no KDE, no GNOME desktop."

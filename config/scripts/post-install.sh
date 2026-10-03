#!/usr/bin/env bash
set -euo pipefail

echo "==> Running post-installation configuration for neutronOS..."

# 1. Ensure fish is registered in /etc/shells, otherwise usermod refuses it.
#    (chsh is the usual tool but does not exist on this base -- Universal Blue's
#    Containerfile does `rm -f /usr/bin/chsh`. See README.)
if ! grep -qx "/usr/bin/fish" /etc/shells; then
    echo "/usr/bin/fish" >> /etc/shells
fi

# 2. Default shell for accounts created from here on. This is the only
#    build-time lever: the first real account is created after the image is
#    written, and /etc/default/useradd is what useradd-family tooling reads.
#    It does NOT rewrite an already-existing account -- use
#    `usermod -s /usr/bin/fish $USER` (`chsh` does not exist on this base).
sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd 2>/dev/null || true

# 3. greetd + the Noctalia Greeter. The base has no display manager at all
#    (base-main logs
#    in on getty), but drop the stale symlink defensively anyway: greetd's
#    greeter becomes display-manager.service, and a dangling link left by
#    another package would leave the display manager broken.
systemctl disable gdm.service sddm.service 2>/dev/null || true
rm -f /etc/systemd/system/display-manager.service
mkdir -p /etc/greetd

# Resolve the greeter's session wrapper at build time rather than hardcoding a
# path. The upstream docs are explicit that the path depends on how it was
# installed -- /usr/bin on packaged installs, NOT /usr/local -- and greetd runs a
# bare command name, so a wrong path is a black screen at login.
#
# It must be `noctalia-greeter-session`, not `noctalia-greeter`: greetd launches
# the session wrapper, which starts the bundled wlroots compositor that the
# greeter UI runs inside. Pointing greetd straight at the UI binary leaves
# WAYLAND_DISPLAY unset and the login screen never appears.
GREETER_BIN=$(command -v noctalia-greeter-session || true)
if [ -z "$GREETER_BIN" ]; then
    echo "FAIL  noctalia-greeter-session not on PATH; the greeter cannot start" >&2
    exit 1
fi

cat <<EOF > /etc/greetd/config.toml
[terminal]
vt = "1"

[default_session]
# greetd runs $GREETER_BIN, which starts the bundled wlroots compositor and
# runs the Noctalia login UI inside it. --session niri is set explicitly rather
# than relying on "first discovered session": niri.desktop is the only session in
# this image, but pinning it means a future second session cannot silently
# become the default.
#
# The user here MUST be the one greetd's own /usr/lib/sysusers.d/greetd.conf
# creates, which is "greetd" -- not "greeter", which is the name the upstream
# greetd docs and the Arch wiki use and which does NOT exist on Fedora. Naming a
# missing user makes greetd fail to setuid, so display-manager.service dies and
# graphical.target has nothing to draw: a black screen with no error.
#
# tuigreet is still installed as a fallback. To recover from a broken login
# screen without a live USB, replace the command line above with:
#   command = "tuigreet --time --remember --asterisks"
# then `systemctl restart greetd`.
command = "$GREETER_BIN -- --session niri"
user = "greetd"
EOF
systemctl enable greetd.service

# The greeter's own system setup. It creates /var/lib/noctalia-greeter/ and
# greeter.toml, owned by the greetd session user. Its location has moved between
# releases, so look for it rather than assuming a path.
#
# Note that /var is a separate partition in a bootc image, so anything this writes
# there is NOT part of the deployment -- the directory is instead created at boot
# by /usr/lib/tmpfiles.d/neutronos-greeter.conf, and the greeter falls back to
# its built-in defaults if greeter.toml is absent (upstream's documented
# behaviour). What matters from this script is the stdout, which is a
# ready-to-paste greetd config block, so log it rather than discarding it.
echo "==> Running the Noctalia greeter's system setup..."
greeter_setup=$(find /usr -name 'setup_greeter_system.sh' -type f 2>/dev/null | head -1 || true)
if [ -n "$greeter_setup" ]; then
    "$greeter_setup" || echo "    setup script exited non-zero; continuing"
    echo "    ran $greeter_setup (its output above is a greetd block; this image writes its own)"
else
    mkdir -p /var/lib/noctalia-greeter
    echo "    setup script not found; relying on the tmpfiles.d drop-in for the state dir"
fi

# 4. TLP for laptop power management.
#    A DE-less niri session ships no power daemon at all: GNOME's
#    power-profiles-daemon and KDE's powerdevil are both absent because there is
#    no desktop. TLP is therefore the only thing tuning the CPU governor, USB
#    autosuspend and audio codec power, and it also exposes ThinkPad charge
#    thresholds.
#
#    Enabling the unit is the whole job -- `tlp start` runs from the service on
#    boot, and TLP's settings all live in /etc/tlp.conf, so no configuration is
#    written here. tlp-pd is deliberately NOT installed: it is the
#    power-profiles-daemon integration and there is no power-profiles-daemon
#    here to integrate with.
systemctl enable tlp.service

# 5. LibreWolf as the system default browser.
#    `xdg-mime default` is NOT used: it writes to $HOME/.config/mimeapps.list,
#    and during a build $HOME is root's, so it would land where no real user
#    looks. /etc/xdg/mimeapps.list is the system-wide location and is not owned
#    by any package, so appending is safe. The base ships this file with a
#    Bazaar entry for application/vnd.flatpak.ref, which is preserved.
LIBREWOLF_DESKTOP=io.gitlab.librewolf-community.desktop
MIME_FILE=/etc/xdg/mimeapps.list
if [ -f "$MIME_FILE" ] && grep -qF "$LIBREWOLF_DESKTOP" "$MIME_FILE"; then
    echo "    LibreWolf already registered as default"
else
    tmp=$(mktemp)
    touch "$tmp"
    if [ -f "$MIME_FILE" ]; then
        cp "$MIME_FILE" "$tmp"
    else
        printf '[Default Applications]\n' > "$tmp"
    fi
    # Ensure a [Default Applications] group exists before appending to it.
    if ! grep -q '^\[Default Applications\]' "$tmp"; then
        printf '[Default Applications]\n' >> "$tmp"
    fi
    for mime in x-scheme-handler/http x-scheme-handler/https text/html; do
        printf '%s=%s\n' "$mime" "$LIBREWOLF_DESKTOP" >> "$tmp"
    done
    cat "$tmp" > "$MIME_FILE"
    rm -f "$tmp"
    echo "    LibreWolf set as default for http/https/text-html"
fi

echo "==> Post-installation configuration complete."

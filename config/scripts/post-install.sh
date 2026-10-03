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

# 3. greetd + tuigreet. The base has no display manager at all (base-main logs
#    in on getty), but drop the stale symlink defensively anyway: greetd's
#    greeter becomes display-manager.service, and a dangling link left by
#    another package would leave the display manager broken.
systemctl disable gdm.service sddm.service 2>/dev/null || true
rm -f /etc/systemd/system/display-manager.service
mkdir -p /etc/greetd
cat <<'EOF' > /etc/greetd/config.toml
[terminal]
vt = "1"

[default_session]
# tuigreet reads /usr/share/wayland-sessions and offers Niri. Sessions are not
# filtered: niri.desktop is the only one in the image, so it is the only choice.
#
# The user here MUST be the one greetd's own /usr/lib/sysusers.d/greetd.conf
# creates, which is "greetd" -- not "greeter", which is the name the upstream
# greetd docs and the Arch wiki use and which does NOT exist on Fedora. Naming a
# missing user makes greetd fail to setuid, so display-manager.service dies and
# graphical.target has nothing to draw: a black screen with no error.
command = "tuigreet --time --remember --asterisks"
user = "greetd"
EOF
systemctl enable greetd.service

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

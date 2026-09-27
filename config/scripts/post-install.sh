#!/usr/bin/env bash
set -euo pipefail

echo "==> Running post-installation configuration for neutronOS..."

# 1. Ensure fish is registered in /etc/shells, otherwise chsh refuses it.
if ! grep -qx "/usr/bin/fish" /etc/shells; then
    echo "/usr/bin/fish" >> /etc/shells
fi

# 2. Default shell for accounts created from here on. This is the only
#    build-time lever: the first real account is created after the image is
#    written, and /etc/default/useradd is what useradd-family tooling reads.
#    It does NOT rewrite an already-existing account -- use `chsh`.
sed -i 's|^SHELL=.*|SHELL=/usr/bin/fish|' /etc/default/useradd 2>/dev/null || true

# 3. greetd + tuigreet. gdm was removed by strip-gnome.sh, but drop the stale
#    symlink defensively: greetd's greeter becomes display-manager.service, and
#    a dangling link to gdm.service would leave the display manager broken.
systemctl disable gdm.service sddm.service 2>/dev/null || true
rm -f /etc/systemd/system/display-manager.service
mkdir -p /etc/greetd
cat <<'EOF' > /etc/greetd/config.toml
[terminal]
vt = "1"

[default_session]
# tuigreet reads /usr/share/wayland-sessions and offers Niri. Sessions are not
# filtered: niri.desktop is the only one in the image, so it is the only choice.
command = "tuigreet --time --remember --asterisks"
user = "greeter"
EOF
systemctl enable greetd.service

# 4. LibreWolf as the system default browser.
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

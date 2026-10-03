# Containerfile for building neutronOS locally or without BlueBuild.
# Mirrors config/recipe.yml -- keep the two in sync.
#
# Two modules are NOT reproduced here because they only exist inside BlueBuild:
#   - `brew`              (Homebrew lands in /home/linuxbrew)
#   - `default-flatpaks`  (Bazaar, LibreWolf, Gear Lever, DistroShelf)
# A local build therefore has no Homebrew and no flatpaks, and the LibreWolf
# MIME assertions in verify-desktop.sh will fail. That is expected: use
# BlueBuild (or push to main) for a complete image.
FROM ghcr.io/ublue-os/base-main:latest

# Copy configuration scripts and files
COPY config/scripts /tmp/scripts
COPY config/files /

# COPY preserves the source mode, so a script committed without +x fails at RUN.
RUN chmod +x /tmp/scripts/*.sh

# Resolve the dangling /opt and /usr/local symlinks
RUN /tmp/scripts/pre-install.sh

# Install the session, the desktop runtime infrastructure and the dev layer.
# All of these are Fedora 44 main. niri pulls xwayland-satellite.
#
# The infrastructure packages are named explicitly even when the base may
# already have them: on a desktop-less base an inherited dependency is not
# guaranteed, and verify-desktop.sh asserts every one of them. NetworkManager
# matters most -- this is a laptop image.
RUN dnf install -y \
      niri noctalia tuigreet greetd greetd-selinux \
      dbus-daemon polkit \
      xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
      fish \
      pipewire wireplumber gnome-keyring gnome-keyring-pam gvfs avahi bluez \
      NetworkManager \
      ddcutil accountsservice cliphist wlsunset brightnessctl playerctl \
      wl-clipboard \
      podman podman-docker uidmap distrobox \
      gcc gcc-c++ make cmake ninja-build pkgconf-pkg-config gdb \
      git git-delta git-lfs ripgrep fd-find bat eza tree fzf zoxide direnv \
      tmux lazygit gh jq yq shellcheck shfmt btop sqlite man-pages \
      tlp && \
    dnf clean all

# Enable the Terra repository, which carries Ghostty, the Nerd Font build and the
# Noctalia greeter.
# Deliberately a separate step AFTER the install above: once Terra is enabled the
# resolver can see its versions of anything, so enabling it in the same
# transaction as the session risks picking Terra's build over Fedora's. Base
# repo only -- terra-release-extras and -mesa are never installed.
RUN /tmp/scripts/terra-repo.sh

# The terminal, the font and the greeter. None is in Fedora main: Ghostty is not
# packaged for Fedora at all, Fedora's jetbrains-mono-fonts lacks the Nerd glyphs
# that eza/bat/fzf/git-delta need for their icons, and the greeter is Terra-only.
RUN dnf install -y ghostty jetbrainsmono-nerd-fonts noctalia-greeter && \
    dnf clean all

# Post-install: fish, greetd+noctalia-greeter, TLP, LibreWolf MIME default
RUN /tmp/scripts/post-install.sh && rm -rf /tmp/scripts

# Check the niri/Noctalia wiring and validate the shipped config
COPY config/scripts/niri-defaults.sh /tmp/niri-defaults.sh
COPY config/scripts/verify-desktop.sh /tmp/verify-desktop.sh
RUN chmod +x /tmp/niri-defaults.sh /tmp/verify-desktop.sh && \
    /tmp/niri-defaults.sh && \
    bash /tmp/verify-desktop.sh

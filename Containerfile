# Containerfile for building neutronOS locally or without BlueBuild.
# Mirrors config/recipe.yml -- keep the two in sync.
#
# Two modules are NOT reproduced here because they only exist inside BlueBuild:
#   - `brew`              (Homebrew lands in /home/linuxbrew)
#   - `default-flatpaks`  (Bazaar, LibreWolf, Proton Plus, Gear Lever, LACT,
#                           DistroShelf)
# A local build therefore has no Homebrew and no flatpaks, and the LibreWolf
# MIME assertions in verify-desktop.sh will fail. That is expected: use
# BlueBuild (or push to main) for a complete image.
FROM ghcr.io/ublue-os/bazzite-gnome:latest

# Copy configuration scripts and files
COPY config/scripts /tmp/scripts
COPY config/files /

# COPY preserves the source mode, so a script committed without +x fails at RUN.
RUN chmod +x /tmp/scripts/*.sh

# Resolve the dangling /opt and /usr/local symlinks
RUN /tmp/scripts/pre-install.sh

# Remove the GNOME desktop inherited from the base. Before the install so the
# dnf cascade has none of our own apps to swallow.
RUN /tmp/scripts/strip-gnome.sh

# Install the session. Everything is Fedora 44 main; no COPRs, no third-party
# repos. niri pulls xwayland-satellite.
RUN dnf install -y \
      niri noctalia tuigreet greetd greetd-selinux \
      xdg-desktop-portal xdg-desktop-portal-gnome xdg-desktop-portal-gtk \
      alacritty fish accountsservice \
      cliphist wlsunset brightnessctl playerctl wl-clipboard && \
    dnf clean all

# Remove the KDE leftovers the install closure drags in
RUN /tmp/scripts/strip-kde-leftovers.sh

# Post-install: fish, greetd+tuigreet, LibreWolf MIME default
RUN /tmp/scripts/post-install.sh && rm -rf /tmp/scripts

# Check the niri/Noctalia wiring and validate the shipped config
COPY config/scripts/niri-defaults.sh /tmp/niri-defaults.sh
COPY config/scripts/verify-desktop.sh /tmp/verify-desktop.sh
RUN chmod +x /tmp/niri-defaults.sh /tmp/verify-desktop.sh && \
    /tmp/niri-defaults.sh && \
    bash /tmp/verify-desktop.sh

#!/usr/bin/env bash
set -euo pipefail

# Remove the GNOME desktop inherited from the bazzite-gnome base so COSMIC is
# the only session. The package list was measured by diffing bazzite-gnome
# against a COSMIC-only base (ublue-os/base-main + @cosmic-desktop) and keeping
# the gnome-desktop comps group members that exist only in the GNOME image.
#
# There is no orphan sweep here: in a bootc/ostree image every package is
# installed with reason=user, so `dnf5 autoremove` reports "Nothing to do" and
# `dnf5 repoquery --unneeded` returns nothing. dnf cannot tell an orphan from a
# leaf package, so the removal set is explicit and verify-desktop.sh is the gate.
#
# Deliberately KEPT, despite being GNOME-adjacent:
#   gvfs                 cosmic-files mounts removable media through it
#   gnome-keyring(-pam)  keyring unlock, shared with the COSMIC session
#   ibus*, fcitx5-*      input methods, DE-independent
#   cosmic-files         the only file manager, and cosmic-term the only terminal
# Bazaar is the only store: it is a flatpak, so cosmic-store is not installed.
# nautilus-extensions has to be named explicitly: it is only reachable through
# nautilus-gsconnect, and dnf will not cascade it away on its own because every
# package in a bootc image is installed with reason=user.
#   mesa-*               graphics drivers
#   fprintd-pam          hard requirement of cosmic-greeter
#   xdg-desktop-portal   portal framework cosmic's portal plugs into
#   avahi, bluez, flatpak  used by the gaming/portal stack

# The removal sets are bash arrays rather than one long backslash continuation
# because a "#" comment inside a continuation comments out the rest of the
# logical line, silently turning `dnf5 remove` into a no-argument call.
shell_stack=(
  gnome-shell gnome-shell-common gnome-session gnome-session-wayland-session
  gnome-settings-daemon gnome-desktop3 gnome-desktop4
  gnome-shell-extension-common gnome-shell-extension-gsconnect
  gnome-shell-extension-user-theme gnome-search-yafti gnome-rounded-blur
  gnome-browser-connector gnome-app-list
)

# COSMIC ships its own portal backend, so the GNOME one goes.
portal_stack=(xdg-desktop-portal-gnome)

# gdm is the base's display manager; greetd + cosmic-greeter replaces it.
dm_and_compositor=(gdm mutter mutter-common)

# Settings, shell accessories and the GNOME apps that have no COSMIC
# counterpart here. cosmic-files and cosmic-term are the COSMIC-native file
# manager and terminal.
apps=(
  gnome-control-center gnome-control-center-filesystem
  gnome-disk-utility gnome-bluetooth gnome-color-manager
  gnome-remote-desktop gnome-remote-desktop-libs
  gnome-online-accounts gnome-online-accounts-libs gnome-autoar
  gnome-user-share gnome-user-docs gnome-backgrounds gnome-menus
  gnome-epub-thumbnailer glycin-thumbnailer gst-thumbnailers
  yelp yelp-libs yelp-xsl papers papers-nautilus rygel vte-profile
  nautilus nautilus-extensions nautilus-gsconnect nautilus-python
  xdg-user-dirs-gtk epiphany-runtime
)

# Evolution PIM stack plus libraries only it needed.
pim_and_libs=(
  evolution-data-server evolution-data-server-langpacks
  evolution-ews-core evolution-ews-langpacks gcr colord-gtk4
  libgee libgweather geoclue2-libs
)

# GNOME-flavoured extras that bazzite-gnome adds on top of the base.
gnome_extras=(
  steamdeck-gnome-presets rom-properties-gtk4 rom-properties-localsearch3
)

# displaylink ships the only non-free, non-redistributable driver in the base
# (DisplayLink Software License Agreement) and is a niche USB docking driver
# almost nobody uses. Dropped so the image is cleanly redistributable.
nonfree=(displaylink)

# Leaked dependencies. Measured with `rpm -q --whatrequires` after the strip
# above: nothing in the image requires these any more. They are listed because
# dnf cannot find them itself in a bootc/ostree image (see header).
#
# kf6-ki18n, kf6-kimageformats and kf6-kquickcharts are not listed because they
# are still required by qt6-controllable, f44-backgrounds-base and
# qqc2-breeze-style; dnf5 removes them or keeps them as it sees fit.
#
# dnf5 also cascades the rest of the kf6 set away with these, including
# kf6-breeze-icons and breeze-icon-theme. That is wanted here: Breeze is KDE's
# icon theme, cosmic-settings-daemon has no breeze requirement in F44, and
# cosmic-icon-theme plus adwaita-icon-theme cover the fallback.
# GNOME libraries and the web/document stack that lost its consumers above.
# gcr/gcr-libs/gcr3/gcr3-base all stay: gcr3 is required by gnome-keyring, which
# COSMIC uses for secrets, so dnf5 pulls the rest back in with it.
# pinentry-gnome3 stays because it prompts for the keyring passphrase.
gnome_leaked_libs=(
  gnome-bluetooth-libs
  papers-libs papers-thumbnailer papers-previewer
  desktop-backgrounds-gnome f44-backgrounds-gnome fedora-chromium-config-gnome
  exo xfce4-panel xfconf libxfce4ui libxfce4util libxfce4windowing
  garcon tumbler
  webkit2gtk4.1 webkitgtk6.0 javascriptcoregtk4.1 javascriptcoregtk6.0 gjs
  gtk2 gsound geocode-glib malcontent malcontent-ui-libs
  libnma-gtk4 libhandy libmediaart gspell hyphen
)

echo "==> Removing GNOME desktop (COSMIC becomes the only session)..."

dnf5 -y remove \
  "${shell_stack[@]}" \
  "${portal_stack[@]}" \
  "${dm_and_compositor[@]}" \
  "${apps[@]}" \
  "${pim_and_libs[@]}" \
  "${gnome_extras[@]}" \
  "${gnome_leaked_libs[@]}" \
  "${nonfree[@]}"

# gdm's post-install leaves /etc/systemd/system/display-manager.service as a
# symlink to gdm.service, which rpm does not remove with the package. Left
# behind it blocks cosmic-greeter's preset (it aliases display-manager.service)
# and would leave the display manager dangling.
rm -f /etc/systemd/system/display-manager.service

dnf5 -y clean all
echo "==> GNOME desktop removed."

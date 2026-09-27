#!/usr/bin/env bash
set -euo pipefail

# Second, deliberately tiny removal pass. It runs AFTER the install because
# BlueBuild installs with `rpm-ostree install`, whose dependency closure drags
# these in even though nothing requires them: they survived strip-gnome.sh in CI
# and failed the gate.
#
# The list is exactly what the gate caught, nothing more. An earlier version
# also removed kf6-karchive, kf6-kcolorscheme, kf6-kguiaddons, kf6-kcoreaddons,
# kf6-kwidgetsaddons, kf6-kcrash, kf6-kglobalaccel and kf6-kconfig. Dropping
# those is deliberate: in a single multi-package transaction dnf5 classified
# cosmic-session as a "dependent package" of kf6-karchive and wanted to take the
# whole COSMIC stack with it, even though `rpm --whatrequires` shows no link and
# cosmic-session links no KF6 library. The resolver is not predictable here, and
# a few hundred KiB of unused KF6 libs is a cheap price for a build that does
# not depend on dnf5's mood. Add to this list only on gate evidence.
#
# Breeze is KDE's icon and Qt theme. cosmic-icon-theme and adwaita-icon-theme
# are the fallback and cosmic-settings-daemon has no breeze requirement in F44,
# so losing Breeze is the intended outcome on a KDE-free image.
# kf6-ki18n, kf6-kimageformats, kf6-kquickcharts and kf6-breeze-icons are left
# alone because qt6-controllable, f44-backgrounds-base, qqc2-breeze-style and
# cosmic-settings-daemon still need them.

echo "==> Removing KDE leftovers pulled in by the install closure..."

dnf5 -y remove --no-autoremove \
  kf6-kirigami kf6-kirigami-addons kf6-sonnet kf6-sonnet-hunspell \
  kf6-qqc2-desktop-style \
  plasma-breeze-common plasma-breeze-qt6

dnf5 -y clean all
echo "==> KDE leftovers removed."

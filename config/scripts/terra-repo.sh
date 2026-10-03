#!/usr/bin/env bash
# Enable the Terra repository, and only Terra.
#
# Ghostty is not in Fedora main -- ghostty.org's own Fedora instructions point at
# either this repo or the scottames/ghostty COPR. Terra was chosen over the COPR
# because one repo covers both things we could not get from Fedora: `ghostty`
# itself and `jetbrainsmono-nerd-fonts` (Fedora main only ships the *plain*
# `jetbrains-mono-fonts`, whose missing Nerd glyphs turn eza/bat/fzf icons into
# tofu boxes). Using one third-party source for both beats two.
#
# This runs BEFORE the rpm-ostree module that installs ghostty, and AFTER the one
# that installs everything else. That ordering is load-bearing: once Terra is
# enabled its versions of any package are visible to the resolver, and a single
# transaction that both enabled the repo and installed the session could pick
# Terra's build of a package we deliberately take from Fedora. Resolving the
# Fedora set first and only then enabling Terra pins the earlier choices.
#
# ONLY the base `terra` repo is enabled. `terra-release-extras` is deliberately
# NOT installed: its own documentation says it holds "packages which conflict
# with Fedora packages in some way, such as being a patched version of the same
# package", and `terra-release-mesa` / `-nvidia` are equally unwanted here. The
# previous gaming base also shipped patched `terra-*` builds that dragged in
# KF6 packages nothing needed, which is why the strip pass existed at all.
# verify-desktop.sh asserts that none of those subrepos are enabled.
set -euo pipefail

FEDORA_MAJOR=$(rpm --eval '%{fedora')
REPO_URL="https://raw.githubusercontent.com/terrapkg/packages/f${FEDORA_MAJOR}/anda/terra/release/terra.repo"
DEST=/etc/yum.repos.d/terra.repo

echo "==> Enabling the Terra repository (base repo only)..."

if [ -e "$DEST" ]; then
    echo "    $DEST already present"
else
    curl -fsSL "$REPO_URL" -o "$DEST"
    echo "    installed $DEST from $REPO_URL"
fi

# Fail loudly rather than letting the next module's `rpm-ostree install ghostty`
# report a confusing "package not found".
if ! grep -q '^name=' "$DEST"; then
    echo "FAIL  $DEST does not look like a repo file" >&2
    exit 1
fi

# Install terra-release and terra-gpg-keys.
#
# The repo file's gpgkey is file:///etc/pki/rpm-gpg/RPM-GPG-KEY-terra$releasever --
# a LOCAL path, not a URL. That key file ships in terra-gpg-keys, which
# terra-release Requires. So dropping the .repo file alone leaves the repo
# enabled with no way to verify it, and the next module's install fails on
# signature verification. This is a chicken-and-egg: the key arrives *inside* the
# package we are fetching from the repo the key verifies. It is bootstrapped with
# --nogpgcheck --repofrompath, which is what Terra's own docs prescribe and what
# Bazzite does. Every install AFTER this one is signature-checked.
#
# terra-release alone ships only terra.repo. The subrepos that must never be
# enabled -- extras, mesa, nvidia, multimedia -- are separate packages
# (terra-release-extras and friends) and are deliberately not installed.
echo "==> Bootstrapping terra-release and terra-gpg-keys..."
dnf5 -y install --nogpgcheck \
    --repofrompath "terra,https://repos.fyralabs.com/terra\$releasever" \
    terra-release terra-gpg-keys

KEY=/etc/pki/rpm-gpg/RPM-GPG-KEY-terra$(rpm --eval '%{fedora')
if [ -e "$KEY" ]; then
    echo "    GPG key present: $KEY"
else
    echo "FAIL  $KEY missing; Terra packages cannot be verified" >&2
    exit 1
fi

# Make Terra LOWER priority than Fedora (Fedora's default is 99). The repo file
# ships with no priority, so on the user's laptop an `rpm-ostree upgrade` would
# otherwise see Terra's rolling builds of whatever Terra happens to carry --
# nerd-fonts, fuse-overlayfs, wl-clipboard, curl -- at the same priority as
# Fedora, and a newer Terra build could win. The intent is "Terra for exactly
# three packages", and this is the only place that intent can actually be
# enforced: the build gate only inspects the image at build time and cannot see
# what a later upgrade would do.
#
# Priority does not affect the three packages we want. ghostty,
# jetbrainsmono-nerd-fonts and noctalia-greeter exist ONLY in Terra, so there is
# no Fedora candidate for them to lose to.
dnf5 config-manager setopt 'terra.priority=150'
echo "    terra.priority=150 (below Fedora's 99, so Fedora wins any tie)"

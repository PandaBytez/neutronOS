# neutronOS

A terminal-focused, scrollable-tiling atomic desktop: **niri** + **Noctalia** on a Bazzite (Universal Blue) base with the **OGC gaming kernel**.

Not a GNOME or KDE image. There is no desktop environment underneath — just a compositor, a shell, and a gaming kernel.

---

## Features

- **Base** — `ghcr.io/ublue-os/bazzite-gnome`, GNOME stripped. Keeps the **OGC kernel** (`kernel-core-7.2.4-ogc3.1.fc44`), `terra-gamescope`, `terra-mangohud`, `terra-release-mesa`, Steam, akmods and the `ublue-os-*` hardware layer. Carries zero Plasma.
- **Compositor** — **niri 26.04** (Fedora main). Scrollable tiling: columns are the splits, so there is no nested window manager.
- **Shell** — **Noctalia 5.1.0** (Fedora main). Bar, launcher, notifications, OSD, lock screen, wallpaper and theming. Binary is `noctalia`; the v4 `noctalia-shell` name is legacy and not used.
- **Greeter** — **greetd + tuigreet**.
- **Terminal** — **Alacritty 0.17.0**. No split panes on purpose: niri's columns are the splits.
- **Shell** — pure **Fish**, with automatic **Homebrew** path integration.
- **Browser** — **LibreWolf** (flatpak), set as the system default for `http`, `https` and `text/html`.
- **Flatpaks** — Bazaar, LibreWolf, Proton Plus, Gear Lever, LACT, DistroShelf.

### Keybindings

| Key | Action |
| :--- | :--- |
| `Super+T` | Open Alacritty |
| `Super+D` | Noctalia launcher |
| `Super+Alt+L` | Lock screen |
| `Super+Shift+E` | Log out |
| `Super+Shift+/` | niri's full hotkey overlay |

The rest of niri's documented binding set is unmodified and available out of the box.

---

## Why this base

`bazzite-gnome` rather than a DE-less base, for two concrete reasons:

1. **The OGC kernel is only on the Bazzite base.** `ublue-os/base-main` and
   `base-nvidia` ship the stock Fedora kernel (`7.2.7-200.fc44`); the OGC kernel
   is not in Fedora main at all — Bazzite gets it from the `ublue-os/akmods`
   images and the `ublue-os/*` COPRs.
2. **The Terra repo comes with it.** Bazzite already enables `terra`,
   `terra-mesa` and `terra-extras`, which is where `noctalia-greeter` lives.

`bazzite-gnome` has zero Plasma, so there is no KDE to strip — only the GNOME
desktop it inherits, which `strip-gnome.sh` removes.

---

## Layout

| Path | Purpose |
| :--- | :--- |
| `config/recipe.yml` | BlueBuild recipe — the source of truth for CI builds |
| `config/scripts/pre-install.sh` | Resolves the dangling `/opt` and `/usr/local` symlinks |
| `config/scripts/strip-gnome.sh` | Removes the inherited GNOME desktop and `displaylink` |
| `config/scripts/strip-kde-leftovers.sh` | Removes KDE leftovers the install closure drags in |
| `config/scripts/post-install.sh` | Fish, greetd + tuigreet, LibreWolf MIME default |
| `config/scripts/niri-defaults.sh` | Checks the niri/Noctalia wiring and validates the shipped config |
| `config/scripts/verify-desktop.sh` | Build gate — 40+ assertions |
| `config/scripts/niri-defaults.sh` | Installs `/etc/niri/config.kdl` and validates it |
| `config/files/etc/skel/.config/niri/config.kdl` | niri config, derived from the packaged default |
| `config/files/etc/skel/.config/alacritty/alacritty.toml` | Terminal config |
| `Containerfile` | Local build, mirrors `config/recipe.yml` |

### Module order

```
pre-install → strip-gnome → install → strip-kde-leftovers → brew
→ flatpaks → skel → post-install → niri-defaults → verify
```

Three orderings are load-bearing, all learned the hard way:

- **`strip-gnome` runs before the install.** The GTK4 apps share dependencies
  with the GNOME set, and `dnf5 remove` takes dependents along with what you
  remove.
- **`strip-kde-leftovers` runs after the install.** BlueBuild installs with
  `rpm-ostree install`, whose closure drags in `kf6-sonnet`, `kf6-kirigami`,
  `kf6-qqc2-desktop-style`, `kf6-sonnet-hunspell` and `plasma-breeze-*` even
  though nothing requires them. Stripping first leaves them behind.
- **`post-install` runs after the flatpaks.** A system-scope `flatpak install`
  populates `/var/lib/flatpak/exports/`, which would otherwise race the browser
  MIME default.

---

## Notes for maintainers

- **All packages are Fedora 44 main.** No COPRs, no third-party repos. The one
  exception is the flatpaks, which come from Flathub.
- **The base image floats and can break the build without any change here.**
  `bazzite-gnome:latest` gained `terra-ddcutil` at some point, which `Provides:
  ddcutil`; the recipe's explicit `ddcutil` then became a hard conflict
  ("conflicting requests"). That is why `ddcutil` is not in the install list and
  the gate asserts the *capability* instead of the package name. When adding a
  package, check whether the base already provides it under a `terra-*` name.
- **Do not use `cmd | grep -q` in these scripts.** Under `set -o pipefail`,
  `grep -q` exits on first match, the producer takes SIGPIPE and exits 141, and
  the pipeline reports failure for a successful match. Every check uses command
  substitution (`x=$(cmd | grep ... || true)`) instead.
- **Do not add an orphan sweep.** In a bootc/ostree image every package is
  installed with `reason=user`, so `dnf5 autoremove` reports "Nothing to do" and
  `dnf5 repoquery --unneeded` returns nothing. Removal lists are explicit and
  were measured with `rpm -q --whatrequires`.
- **Never broaden `strip-kde-leftovers.sh`.** In a single multi-package
  transaction `dnf5` classified a package as a "dependent" of `kf6-karchive` and
  wanted to take the whole session stack with it — with no actual dependency.
  That list is exactly what the gate caught; add to it only on gate evidence.
- **`/opt`, `/usr/local`, `/root` and `/home` are all dangling symlinks** in
  these ostree images (`/opt -> var/opt`, `/usr/local -> ../var/usrlocal`, and so
  on) and their targets do not exist in a build container. Anything that writes
  there fails with "File exists", and under `set -e` that reads as a silent
  no-op. `pre-install.sh` creates the two we need.
- **The browser default must not use `xdg-mime default`.** That writes to
  `$HOME/.config/mimeapps.list`, and during a build `$HOME` is root's, so it
  would land where no real user looks. `post-install.sh` appends to
  `/etc/xdg/mimeapps.list` instead, preserving the base's Bazaar entry.
- **`/etc/skel` is NOT a system defaults mechanism.** It only populates home
  directories at *account creation*, so it does nothing for a user who rebases
  onto the image from an existing install. Shipping the niri config only in skel
  meant such a user had no config at all, niri fell back to its built-in defaults
  (which start nothing), and **Noctalia never launched**. The config is therefore
  also installed to `/etc/niri/config.kdl`, which niri reads when the user has no
  config of their own. niri uses exactly one file — the user's if it exists,
  otherwise `/etc/niri/config.kdl` — and does not merge them, so a user who wants
  to customise should copy it:
  `mkdir -p ~/.config/niri && cp /etc/niri/config.kdl ~/.config/niri/`
- **Alacritty has no system config path** — only `$XDG_CONFIG_HOME`. Its theming
  can therefore only be shipped via skel, so a pre-existing account keeps
  Alacritty's built-in defaults. To apply it:
  `mkdir -p ~/.config/alacritty && cp /etc/skel/.config/alacritty/alacritty.toml ~/.config/alacritty/`
- **The niri config is derived, not hand-written.** It is niri's packaged
  `default-config.kdl` with four substitutions, so the full binding set works out
  of the box. It deliberately omits niri 26.04-only directives
  (`background-effect`/blur): those only parse on 26.04+ and **niri refuses to
  start on an unparsable config**, so leaving them out keeps it working on 25.11
  too. `niri-defaults.sh` runs `niri validate` against the installed niri on
  every build, so a niri upgrade that changes the schema fails the build instead
  of shipping an unbootable session.
- **The gate is not a blanket `^gnome-` ban.** `xdg-desktop-portal-gnome` is
  *required* by niri for screencast and pulls `gnome-desktop` and `gnome-menus`
  in as libraries. Those are allowed; `gnome-shell`, `gdm`, `mutter` and
  friends are not.
- **Keep the `Containerfile` and `config/recipe.yml` in sync.** The Containerfile
  does not reproduce BlueBuild's `brew` or `default-flatpaks` modules, so a
  local build has no Homebrew and no flatpaks and the LibreWolf MIME checks
  self-skip.

### Licensing

This image is a **modified derivative of [`ublue-os/bazzite-gnome`](https://github.com/ublue-os/bazzite)**,
which is licensed **Apache-2.0**. Per section 4(b)–(d) of that licence, the
modifications made here are the GNOME desktop removal, the addition of the niri
session, and the desktop configuration; no copyright, patent, trademark or
attribution notices from the base have been removed.

- `steam` is redistributed unmodified, as Valve's own RPM.
- `displaylink` was **removed** — it is the only non-redistributable driver in
  the base (DisplayLink Software License Agreement).
- The 34 Callaway firmware packages are licensed "Redistributable, no
  modification permitted"; they are only ever removed, never modified.

---

## Build

### GitHub Actions

Every push to `main` triggers `.github/workflows/build.yml` (plus a weekly cron
on Sundays). The build **fails** if `verify-desktop.sh` finds any Plasma, GNOME
desktop, missing session component, or drifted default.

Images are published as:

```
ghcr.io/pandabytez/neutronos:latest     # rolling, tracks main
ghcr.io/pandabytez/neutronos:44         # rolling, Fedora 44
ghcr.io/pandabytez/neutronos:<sha>-44   # pinned to a commit
```

> Built with `--no-sign`, so there is no cosign signature and the
> `ostree-unverified-registry:` prefix is required when rebasing.

### Local

```bash
podman build -t neutron-niri:local -f Containerfile .
```

This omits Homebrew and the flatpaks (BlueBuild-only modules), so it is a
partial image. Use CI for the real thing.

## Rebase an existing host

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/pandabytez/neutronos:latest
systemctl reboot
```

To pin an exact build:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/pandabytez/neutronos@sha256:<digest>
```

Rollback if the session does not come up:

```bash
rpm-ostree rollback && systemctl reboot
```

Your home directory carries over, including any GNOME, KDE or COSMIC
dconf/gsettings from a previous desktop. For a clean profile instead of a
migrated one, remove `~/.config/dconf/user` before first login to niri.

**Fish** is the default shell for new accounts (`/etc/shells` and
`/etc/default/useradd`). It does not rewrite an existing account — use
`chsh -s /usr/bin/fish $USER` if your account landed on bash.

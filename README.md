# neutronOS

A terminal-focused, scrollable-tiling atomic **development** desktop: **niri** + **Noctalia** on the Universal Blue `base-main` image.

Not a GNOME or KDE image. There is no desktop environment underneath — just a compositor, a shell, and a container-first toolchain.

---

## Features

- **Base** — `ghcr.io/ublue-os/base-main`. No desktop, the stock signed Fedora kernel, Mesa and Intel drivers from negativo17's `fedora-multimedia` repo, Flathub as the default remote, `ublue-os-just` and the `ublue-os-*` hardware/update layer. Carries no Steam and no OGC gaming kernel.
- **Compositor** — **niri 26.04** (Fedora main). Scrollable tiling: columns are the splits, so there is no nested window manager.
- **Shell** — **Noctalia** (Fedora main). Bar, launcher, notifications, OSD, lock screen, wallpaper and theming. Binary is `noctalia`; the v4 `noctalia-shell` name is legacy and not used.
- **Greeter** — **greetd + Noctalia Greeter**, with **tuigreet kept installed as a fallback**.
- **Terminal** — **Ghostty** (Zig + GTK4). No split panes on purpose: niri's columns are the splits. Ships with an Adwaita-dark config, 95% opacity and **JetBrainsMono Nerd Font**.
- **Shell** — pure **Fish**, with automatic **Homebrew** path integration.
- **Containers** — **podman** (with the `docker` CLI shim) and **distrobox**. Language toolchains live in containers, not on the host.
- **Native build** — gcc/g++, make, cmake, ninja, pkgconf, gdb. Required *despite* the container strategy: Rust needs a C linker and `cc`, Go needs cgo, and `podman build` runs on the host.
- **Not-in-Fedora tools** — a **Homebrew bundle** at `/usr/share/homebrew/Brewfile`, applied on first boot. `lazygit` is the only entry today: it is not packaged for Fedora at all, and asking rpm-ostree for it fails the build.
- **Laptop** — **TLP** for battery, thermals and ThinkPad charge thresholds. A DE-less session has no power daemon otherwise.
- **Browser** — **LibreWolf** (flatpak), set as the system default for `http`, `https` and `text/html`.
- **Flatpaks** — Bazaar, LibreWolf, Gear Lever, DistroShelf.
- **Installer** — **`neutronos-install`**, a whiptail TUI that lives in the image. Boot the ISO and it starts by itself on tty1: no terminal, no command, just a menu of disks and a passphrase. It lays down the same ESP + unencrypted `/boot` + LUKS2/btrfs root every Universal Blue install produces, and takes about a minute.

### Dev environments

The image is immutable, so a native toolchain never updates without a rebuild. Two helpers are in `config.fish`:

```fish
dinit    # distrobox create --name (basename $PWD) --image fedora:latest
dsh      # distrobox enter (basename $PWD)
```

`distrobox` shares your home directory, so projects live on the host and the toolchain lives in the container. The container is named after the current directory, so each project gets its own toolchain automatically — no editing the config required. Rootless container support needs `newuidmap`/`newgidmap`, which Fedora puts in `shadow-utils` and the base already has; the build gate asserts `newuidmap` on `PATH`, because without it the first `dsh` fails in a way that looks like a distrobox bug rather than a missing package.

### Keybindings

| Key | Action |
| :--- | :--- |
| `Super+T` | Open Ghostty |
| `Super+D` | Noctalia launcher |
| `Super+Alt+L` | Lock screen |
| `Super+Shift+E` | Log out |
| `Super+Shift+/` | niri's full hotkey overlay |

The rest of niri's documented binding set is unmodified and available out of the box.

---

## Why this base

`base-main` rather than a DE-less Fedora image, for three concrete reasons:

1. **It is the only non-gaming Universal Blue base still built.** `ublue-os/main` consolidated in September 2025 to exactly three images — `base`, `kinoite` and `silverblue`. There is no longer a gaming-free GNOME variant to strip.
2. **Enhanced graphics drivers.** Mesa and the Intel drivers come from negativo17's `fedora-multimedia` repo rather than stock Fedora, so codec support and driver fixes are newer than what Fedora ships.
3. **The ublue hardware and update layer**, plus Flathub as the default remote and `ublue-os-just`.

The kernel is the stock Fedora one, signed via the `ublue-os/akmods` layer — the **OGC gaming kernel is gone**. See the note below on why it could not simply be removed.

### Why not keep `bazzite-gnome` and uninstall the game?

This image *was* a gaming image on `bazzite-gnome`, with the OGC kernel and Steam. Neither can be removed in place:

- **OGC is Bazzite's default kernel.** Bazzite gets it from the `ublue-os/akmods` images and the `ublue-os/*` COPRs; it is not in Fedora main. Removing it means installing stock `kernel-core` on top, which fights the base on every rebase.
- **Steam's dependency closure holds the firmware and Mesa layer** the display depends on. Pulling it risks the graphics stack, which is not a failure you want to debug on a laptop.

A base change is the only clean way to drop the gaming stack, so the base changed. `verify-desktop.sh` now asserts the *absence* of Steam, Proton, gamescope, gamemode and `terra-*`, so a future `base-main` bump cannot quietly reintroduce any of it.

---

## Layout

| Path | Purpose |
| :--- | :--- |
| `config/recipe.yml` | BlueBuild recipe — the source of truth for CI builds |
| `config/scripts/pre-install.sh` | Resolves the dangling `/opt` and `/usr/local` symlinks |
| `config/scripts/terra-repo.sh` | Enables the base `terra` repo (Ghostty + Nerd Font source) |
| `config/scripts/post-install.sh` | Fish, greetd + Noctalia Greeter, TLP, LibreWolf MIME default |
| `config/scripts/niri-defaults.sh` | Checks the niri/Noctalia wiring and validates the shipped config |
| `config/scripts/verify-desktop.sh` | Build gate |
| `config/files/etc/skel/.config/niri/config.kdl` | niri config, derived from the packaged default |
| `config/files/etc/skel/.config/ghostty/config` | Terminal config |
| `config/files/etc/skel/.config/fish/config.fish` | Shell config, Homebrew init, `distrobox` helpers |
| `config/files/usr/bin/neutronos-install` | The installer, shipped into the image at `/usr/bin/neutronos-install` |
| `config/files/usr/lib/systemd/system/neutronos-install.service` | Starts the installer on tty1 — on the ISO only, gated on `neutronos.live` |
| `config/files/usr/lib/systemd/system/greetd.service.d/10-neutronos-live.conf` | Skips the greeter on the ISO so it does not fight the installer for vt1 |
| `config/files/usr/share/homebrew/Brewfile` | Everything not in Fedora, applied as one `brew bundle` on first boot |
| `config/files/usr/lib/systemd/system/neutronos-brew-bundle.service` | Runs that bundle as the first user, once, and only stamps on success |
| `disk_config/live.toml` | The one thing that makes the ISO a live session: appends `neutronos.live=1` |
| `.github/workflows/build.yml` | BlueBuild job, plus the `live-iso` job that turns the image into a USB |
| `Containerfile` | Local build, mirrors `config/recipe.yml` |

### Module order

```
pre-install → install → terra-repo → install (ghostty) → brew
→ flatpaks → files (skel + installer + units) → post-install
→ niri-defaults → verify
```

The `files` module carries more than skel now: `/usr/bin/neutronos-install` and the
two systemd units that make the live ISO boot into the installer. `post-install`
runs after it because that is where `systemctl enable` happens — the units have to
be on disk before they can be enabled.

Two orderings are load-bearing:

- **`terra-repo` runs after the Fedora install and before the Ghostty install.** Once Terra is enabled the resolver can see its versions of *anything*, so a transaction that both enabled the repo and installed the session could pick Terra's build of a package we deliberately take from Fedora. Resolving the Fedora set first pins those choices.
- **`post-install` runs after the flatpaks.** A system-scope `flatpak install` populates `/var/lib/flatpak/exports/`, which would otherwise race the browser MIME default.

There is no longer a `strip-gnome` or `strip-kde-leftovers` step — see below.

---

## Notes for maintainers

- **Almost all packages are Fedora 44 main. There are exactly two third-party sources, both deliberate:**
  1. **Flathub**, for the four flatpaks.
  2. **The base `terra` repo**, for `ghostty`, `jetbrainsmono-nerd-fonts` and
     `noctalia-greeter` — and nothing else.

  Terra was chosen over the `scottames/ghostty` COPR because one source then covers
  all three things Fedora cannot provide:

  - **Ghostty**, which is **not packaged for Fedora at all**; ghostty.org's own Fedora
    instructions point at this repo or that COPR.
  - **The Nerd Font build** (`jetbrainsmono-nerd-fonts`) — Fedora main only ships plain
    `jetbrains-mono-fonts`, whose missing Nerd glyphs turn every icon in `eza`, `bat`
    and `fzf` output into a tofu box.
  - **Noctalia Greeter**, which is Terra-only, and which is the same visual language
    as the shell it greets.

  Only the base `terra` repo is enabled. `terra-release-extras` is never installed —
  its own documentation says it carries packages "which conflict with Fedora
  packages in some way, such as being a patched version of the same package", and it
  is the most plausible route by which the KF6 leftovers this image used to strip
  would return. `verify-desktop.sh` asserts the extras, mesa, nvidia and multimedia
  subrepos are all absent, and that no patched `terra-*` gaming build is present.
- **Most infrastructure packages are declared explicitly on purpose.** `pipewire`, `wireplumber`, `gnome-keyring`, `gvfs`, `avahi`, `bluez` and `NetworkManager` are named in the recipe rather than inherited. On a desktop-less base an inherited dependency is not guaranteed, and each one fails silently if absent — a missing `NetworkManager` just means no Wi-Fi after a reboot. Naming them makes the image deterministic and lets the gate assert them. An `rpm-ostree install` of something already present is a no-op.

- **Mesa is the exception, and is deliberately *not* in the install list.** `ublue-os/main`'s install script already pulls `mesa-dri-drivers`, `mesa-libEGL`, `mesa-libGL`, `mesa-libgbm` and `mesa-vulkan-drivers` from negativo17's `fedora-multimedia` repo at `priority=90`, then runs `dnf5 versionlock add` on all of them. So:

  - They are **guaranteed** present, which is the opposite of the usual desktop-less-base assumption.
  - They are a **better** Mesa than stock Fedora — that repo is the codec-complete build, which is what makes LibreWolf video playback and hardware transcoding work.
  - They are **versionlocked**, so asking `rpm-ostree` to install an already-present, versionlocked package is at best a no-op and at worst a versionlock conflict that fails the build.

  The gate still asserts all three are present. The assertion is about the capability, not about who provides it — the same reasoning used for `ddcutil`. If you ever move off `base-main`, re-check whether the new base still versionlocks Mesa before re-adding these.
- **`ddcutil` is now the Fedora package.** It used to be `terra-ddcutil` (which `Provides: ddcutil`), and installing Fedora's on top failed with "conflicting requests". `base-main` has no terra repo, so the Fedora package is correct. The gate asserts the *capability*, not the name.
- **The base floats and can break the build without any change here.** When adding a package, check whether the base already provides it under a different name. When removing one, check what `rpm -q --whatrequires` says — the closure here is not always obvious.
- **Do not use `cmd | grep -q` in these scripts.** Under `set -o pipefail`, `grep -q` exits on first match, the producer takes SIGPIPE and exits 141, and the pipeline reports failure for a successful match. Every check uses command substitution (`x=$(cmd | grep ... || true)`) instead.
- **Do not add an orphan sweep.** In a bootc/ostree image every package is installed with `reason=user`, so `dnf5 autoremove` reports "Nothing to do" and `dnf5 repoquery --unneeded` returns nothing. Removal lists are explicit and were measured with `rpm -q --whatrequires`.
- **`strip-gnome.sh` and `strip-kde-leftovers.sh` are both gone, and the gate replaces them.** `strip-gnome` went because `base-main` has no desktop. `strip-kde-leftovers` went because its reason was Noctalia's **dependency closure on the Bazzite base**: Bazzite enables the `terra` repo, Noctalia's own docs tell Fedora users to install from Terra, and that Terra build pulled `kf6-sonnet`, `kf6-kirigami`, `kf6-qqc2-desktop-style`, `kf6-sonnet-hunspell` and `plasma-breeze-*` for nothing. `base-main` has no terra repo, so `noctalia` now resolves to the Fedora build — Quickshell plus Qt6 (`qtbase`, `qtmultimedia`, `qt6-qtsvg`) and no KF6 at all. The `absent '^kf6-…'` and `absent '^(plasma-|libplasma|…)'` assertions still guard this, so if a future Noctalia or base change reintroduces any of it the build fails and names the package. Reinstating the strip script is then a one-line change.
- **A note on that history, since it nearly caused a bad deletion:** the old `absent '^kf6-(kirigami|sonnet|…)'` pattern has an unbalanced `(`. It looks broken, but GNU grep tolerates it and matches correctly — verified by running the gate's own `absent()` against a stubbed package list, not by eyeballing the regex. Do not "fix" it on sight.
- **`/opt`, `/usr/local`, `/root` and `/home` are all dangling symlinks** in these ostree images (`/opt -> var/opt`, `/usr/local -> ../var/usrlocal`, and so on) and their targets do not exist in a build container. Anything that writes there fails with "File exists", and under `set -e` that reads as a silent no-op. `pre-install.sh` creates the two we need.
- **The browser default must not use `xdg-mime default`.** That writes to `$HOME/.config/mimeapps.list`, and during a build `$HOME` is root's, so it would land where no real user looks. `post-install.sh` appends to `/etc/xdg/mimeapps.list` instead, preserving the base's Bazaar entry.
- **`/etc/skel` is NOT a system defaults mechanism.** It only populates home directories at *account creation*, so it does nothing for a user who rebases onto the image from an existing install. Shipping the niri config only in skel meant such a user had no config at all, niri fell back to its built-in defaults (which start nothing), and **Noctalia never launched**. The config is therefore also installed to `/etc/niri/config.kdl`, which niri reads when the user has no config of their own. niri uses exactly one file — the user's if it exists, otherwise `/etc/niri/config.kdl` — and does not merge them, so a user who wants to customise should copy it:
  `mkdir -p ~/.config/niri && cp /etc/niri/config.kdl ~/.config/niri/`
- **`chsh` does not exist on this base.** Universal Blue's Containerfile does `rm -f /usr/bin/chsh`, so the usual advice fails with "command not found". Use `usermod -s /usr/bin/fish $USER`.
- **The greeter is `noctalia-greeter-session`, never `noctalia-greeter`.** greetd must launch the *session wrapper*, which starts the bundled wlroots compositor (`noctalia-greeter-compositor`) that the login UI runs inside. Point greetd at the UI binary and `WAYLAND_DISPLAY` is never set, so the login screen silently never appears. `verify-desktop.sh` asserts both that the wrapper is referenced and that the bare binary name is not.
- **The greeter's path is resolved at build time, not hardcoded.** Upstream is explicit that the install path varies (`/usr/bin` on packaged installs, explicitly *not* `/usr/local`), and greetd runs a bare command name, so a wrong path is a black screen at login. `post-install.sh` uses `command -v` and writes the result into `config.toml`.
- **`/var` does not ship in a bootc image, so nothing a build writes there persists.** `/var` is a separate partition created at boot; build-time content under it is not part of the deployment. That has two consequences:
  - The greeter's state directory `/var/lib/noctalia-greeter/` is created at boot by our own `/usr/lib/tmpfiles.d/neutronos-greeter.conf`, owned by the greetd session user. The gate asserts the *drop-in*, not the directory — asserting the directory would pass in the build container, where `/var` is writable, while telling us nothing about the deployed system. The upstream package ships no tmpfiles.d of its own and its drop-in hardcodes a `greeter` user that does not exist on Fedora.
  - `greeter.toml` written by the package's `setup_greeter_system.sh` does not survive either, so the greeter starts on its built-in defaults — which is upstream's documented behaviour — and writes the session, user and wallpaper you pick into the state directory as you go.
- **`dbus-daemon` is a hard requirement of `noctalia-greeter-session`**, and `polkit` is what lets Noctalia's *Settings → Shell → Security → Noctalia Greeter → Sync Now* copy wallpaper, palette and font to the login screen via `pkexec`. `accountsservice` (already installed) supplies the user avatars in the login picker.
- **`--session niri` is pinned in the greetd command line.** `niri.desktop` is the only session in this image so the "first discovered session" fallback would resolve correctly, but pinning it means a future second session cannot silently become the default.
- **`tuigreet` stays installed on purpose.** Noctalia Greeter is a young project (first commit May 2026) and it runs *before* authentication — if it fails to start there is no login screen and the machine needs a live USB. `tuigreet` costs one small RPM and gives a documented one-line way back in. See the recovery section below.
- **Ghostty has no system config path** — only `$XDG_CONFIG_HOME/ghostty/config`. Like Alacritty before it, its config can therefore only be shipped via skel, so a pre-existing account keeps Ghostty's built-in defaults. To apply it:
  `mkdir -p ~/.config/ghostty && cp /etc/skel/.config/ghostty/config ~/.config/ghostty/config`
  `theme = Adwaita Dark` resolves against the ~200 themes Ghostty ships in
  `/usr/share/ghostty/themes`, so it needs no external theme package.
- **The niri config is derived, not hand-written.** It is niri's packaged `default-config.kdl` with four substitutions, so the full binding set works out of the box. It deliberately omits niri 26.04-only directives (`background-effect`/blur): those only parse on 26.04+ and **niri refuses to start on an unparsable config**, so leaving them out keeps it working on 25.11 too. `niri-defaults.sh` runs `niri validate` against the installed niri on every build, so a niri upgrade that changes the schema fails the build instead of shipping an unbootable session.
- **No Noctalia config is shipped.** Only niri, Ghostty and fish have files in `config/files`. A Noctalia version bump therefore needs no migration work here, and a broken Noctalia leaves niri running with a usable `Mod+T` terminal.
- **Terra's GPG key is bootstrapped explicitly, and it is a chicken-and-egg.** `terra.repo` does not point at a URL for its key — it says `gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-terra$releasever`, a path that ships inside `terra-gpg-keys`, which `terra-release` requires. Dropping the repo file alone therefore leaves Terra enabled with no way to verify it, and the next install fails on signature verification. `terra-repo.sh` bootstraps the pair with `--nogpgcheck --repofrompath`, which is what Terra's docs prescribe and what Bazzite does; every install after that is signature-checked.
- **Terra is pinned below Fedora in priority.** The upstream repo file ships with no `priority=`, and it is baked into the image, so on your laptop a later `rpm-ostree upgrade` would otherwise see Terra's rolling builds of whatever Terra happens to carry (`nerd-fonts`, `fuse-overlayfs`, `wl-clipboard`, `curl`, …) at the same priority as Fedora, and a newer Terra build could win. `terra-repo.sh` sets `terra.priority=150`, below Fedora's default of 99, so "Terra for exactly three packages" is enforced where it can actually be enforced. The build gate cannot catch this — it only inspects the image at build time. Priority does not affect the three packages we want, since they exist only in Terra and have no Fedora candidate to lose to.
- **The gate is not a blanket `^gnome-` ban.** `xdg-desktop-portal-gnome` is *required* by niri for screencast and pulls `gnome-desktop` and `gnome-menus` in as libraries. Those are allowed; `gnome-shell`, `gdm`, `mutter` and friends are not.
- **TLP is enabled, and `tlp-pd` must stay absent.** `tlp-pd` is the `power-profiles-daemon` integration; there is no `power-profiles-daemon` in a DE-less image, and two things believing they own power policy is a bug. TLP's settings all live in `/etc/tlp.conf`; nothing is written at build time.
- **Keep the `Containerfile` and `config/recipe.yml` in sync.** The Containerfile does not reproduce BlueBuild's `brew` or `default-flatpaks` modules, so a local build has no Homebrew and no flatpaks and the LibreWolf MIME checks self-skip.
- **The installer does not use `bootc install to-disk`, and that is deliberate.** `to-disk` can only offer `--block-setup tpm2-luks`, which seals the volume key to the TPM with **no passphrase** — no recovery key, and an unbootable disk if the TPM ever reseeds. bootc upstream says it should not be recommended for new deployments, and LUKS-with-passphrase is still an open upstream request ([bootc#1329](https://github.com/bootc-dev/bootc/issues/1329), also #421 and #2089). Upstream's own guidance is to set encryption up independently and point `bootc install to-filesystem` at the result, which is what Anaconda's bootc kickstart does and what `neutronos-install` does.
- **`/boot` is deliberately not encrypted.** This base boots GRUB + BLS (the `bootc` package ships the BLS `/usr/lib/kernel/install.conf` layout) and GRUB cannot read LUKS, so the kernels and their BLS entries have to live somewhere unencrypted. The partition sizes and the ESP label match the uBlue ISOs on purpose: a user who has installed uBlue before should see the same layout.
- **`newt` is the RPM that ships `/usr/bin/whiptail`,** and `cryptsetup`, `btrfs-progs` and `dosfstools` are what the installer runs. They are named explicitly for the same reason as the session infrastructure: each one fails *halfway through wiping someone's disk* if it is missing. The gate asserts `whiptail` as a capability rather than `newt` as a package name.
- **`tpm2-tools` has to be installed at build time, not at first boot,** because `dracut-install` silently omits a module whose userspace binaries it cannot find. Without it in the image the initramfs has no `tpm2-tss`, `luks-enable-tpm2-autounlock` appears to succeed, and the disk then never auto-unlocks. The gate therefore greps the **initramfs** for `tpm2-tss` rather than asserting the package.
- **BlueBuild's `files` module has no `mode` key.** `COPY` preserves the source mode, so the exec bit has to be committed in git — that is the only thing making `/usr/bin/neutronos-install` executable in the CI image, and the gate checks `[ -x ]`.
- **The `files` module must list `source: usr`.** It listed only `etc/skel`, which left `/usr/lib/tmpfiles.d/neutronos-greeter.conf` out of the BlueBuild image entirely — build-time content under `/var` does not ship, and the greeter needs that drop-in at boot. The `Containerfile`'s `COPY config/files /` always copied it, which is exactly how the two drifted apart.
- **The installer starts itself from GRUB, with nothing typed.** On the live ISO `neutronos-install.service` takes tty1 and runs the TUI, which is the whole reason the ISO and the installed system are distinguished by one kernel argument (`neutronos.live=1`, appended by `disk_config/live.toml`). Three details are load-bearing:
  - **`TTYPath=/dev/tty1` plus `StandardInput=tty`** is what makes whiptail work at all. A systemd service has no controlling terminal, and whiptail initialises a curses screen on `/dev/tty`, so without this it fails on startup rather than drawing a box.
  - **The greeter is skipped with a systemd condition, not `Conflicts=`.** `greetd.service.d/10-neutronos-live.conf` carries `ConditionKernelCommandLine=!neutronos.live`. Two units both wanting vt1 produce a visible tug-of-war on the console; a skipped unit costs nothing.
  - **The unit is enabled unconditionally and does nothing on an installed system.** Do not "fix" that by gating the enable on something else: the condition is the gate, and a wrong condition means a working machine whose console is an installer.
- **The live ISO is built on the weekly rebuild and on demand, not on every push.** It is ~2 GB and takes ~15 minutes; nobody reinstalls because a script changed. Dispatch the `Build neutronOS Image` workflow by hand to get one for the current `main`.
- **The installer refuses any disk with a mounted partition,** independently of hiding the running disk from the menu. On the live ISO that is what stops someone picking the USB stick they are booting from, which is the worst available mistake.
- **`uidmap` is not a Fedora package, and `lazygit` is not either.** Naming them in the recipe failed the build outright with `Packages not found: uidmap, lazygit` after the base moved to `base-main`; the old gaming base carried them in repos `base-main` does not have. Fedora puts `newuidmap`/`newgidmap` in `shadow-utils` (`uidmap` is the *Debian* name for the same binaries), and `lazygit` has no Fedora packaging at all. The gate now asserts `newuidmap` on `PATH` — the capability rootless podman actually needs, independent of the RPM — and `lazygit` moved to the Homebrew bundle.
- **Anything not in Fedora belongs in `/usr/share/homebrew/Brewfile`,** applied by `neutronos-brew-bundle.service` on the first boot. Not at build time: `/var` is empty on a fresh deployment, so a brew installation made during the build would be discarded rather than shipped — the same trap as the greeter's tmpfiles.d. And not by asking users to type `brew install` after every rebase. The service runs as UID 1000 because Homebrew refuses to run as root and that is the first account by construction; it stamps `/var/lib/neutronos/brew-bundle-done` only on success, so a bundle that failed for want of network is retried on the next boot instead of being skipped forever.
- **The installer's last job is creating the first account,** because `bootc install` deliberately creates none. Without it the Noctalia Greeter comes up with nobody to log in as. `useradd -m` is what makes a fresh install pick up `/etc/skel`, and `-s /usr/bin/fish` stands in for `chsh`, which this base deletes.

### Licensing

This image is a **modified derivative of [`ublue-os/base-main`](https://github.com/ublue-os/main)**, which is licensed **Apache-2.0**. Per section 4(b)–(d), the modifications made here are the addition of the niri session, the desktop configuration, and the development layer; no copyright, patent, trademark or attribution notices from the base have been removed.

The 34 Callaway firmware packages are licensed "Redistributable, no modification permitted"; they are only ever removed, never modified.

---

## Build

### GitHub Actions

Every push to `main` triggers `.github/workflows/build.yml` (plus a weekly cron on Sundays). The build **fails** if `verify-desktop.sh` finds any Plasma, GNOME desktop, gaming package, missing session component, missing dev tool, or drifted default.

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
podman build -t neutron-dev:local -f Containerfile .
```

This omits Homebrew and the flatpaks (BlueBuild-only modules), so it is a
partial image. Use CI for the real thing.

### The live ISO locally

Same invocation CI uses, so a local ISO matches the artifact:

```bash
sudo podman pull ghcr.io/pandabytez/neutronos:latest
mkdir -p output
sudo podman run --rm --privileged --pull=newer --net=host \
  --security-opt label=type:unconfined_t \
  -v "$PWD/disk_config/live.toml:/config.toml:ro" \
  -v "$PWD/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  quay.io/centos-bootc/bootc-image-builder:latest \
  --type live-iso --use-librepo=True --rootfs=btrfs \
  ghcr.io/pandabytez/neutronos:latest
find output -name '*.iso'
```

`disk_config/live.toml` is what makes the ISO boot into the installer instead of
the greeter. Drop that `-v` and you get an ordinary live image of neutronOS.

## Recover from a broken login screen

The greeter runs before authentication, so if it fails to start you get a black
screen and no way in. `tuigreet` is installed for exactly this. From a TTY
(<kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>F3</kbd>) or any live environment:

```bash
sudo sed -i 's|^command = .*|command = "tuigreet --time --remember --asterisks"|' /etc/greetd/config.toml
sudo systemctl restart greetd
```

That edit is not persistent across a rebase — put it back afterwards with
`sudo rpm-ostree override replace /etc/greetd/config.toml` once the cause is
fixed. To see why the greeter failed:

```bash
sudo journalctl -u greetd -b
```

## Install

### From the ISO

Download `neutronos-live.iso` from the artifacts of the latest successful
[workflow run](../../actions/workflows/build.yml), write it to a USB stick, boot
it, and the installer starts on its own. There is nothing to type.

Six questions: which disk, a confirmation that names the disk, a username, a
hostname, and the encryption passphrase twice. Then it partitions, creates the
LUKS2 container, formats btrfs, writes the image with
`bootc install to-filesystem`, creates the first account, and tells you to pull
the stick and reboot.

### From an installed neutronOS

```bash
sudo neutronos-install
```

Same TUI, same questions. Useful for reinstalling onto different hardware.

### Then

The root filesystem is **encrypted**. The passphrase is typed once during install
and then at every boot, and there is no recovery key — keep it. After the first
boot you can seal the volume key to the machine's TPM and stop being asked:

```bash
sudo luks-enable-tpm2-autounlock
```

That script ships in the base (`ublue-os-luks`) and seals to PCR 7+14, i.e.
Secure Boot and MokList state. A firmware update or a MOK change invalidates the
seal and you fall back to the passphrase; that is the intended trade-off. Run it
**from the installed system**, never from the installer: enrolling from an
installer seals against the *installer's* PCR 7, which the installed system never
boots with, and the disk then never unlocks again.

A fresh install is the only path that gets `/etc/skel` applied, so niri,
Ghostty and fish come pre-configured. Rebasing an existing install does not.

### Rebasing an existing install

> **If you are coming from the old gaming neutronOS, this is a base change**
> (`bazzite-gnome` → `base-main`). A fresh install is the low-risk path. If you
> rebase an existing one, keep `rpm-ostree rollback` armed and be ready to
> reboot twice.

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
`usermod -s /usr/bin/fish $USER` if your account landed on bash (`chsh` is not
present on this base).

**TLP applies its settings at boot.** After the first reboot, check it took:

```bash
sudo tlp-stat -s
```

# Cachy Omarchy Overlay — SPEC.md

> Status: **Rewrite / New Architecture**
> Version: **Spec 1.0**
> Date: 2026-08-16
> Target: **CachyOS + Hyprland**
> Upstream: **Omarchy Quattro**
> Packaging: **Arch Linux packages**
>
> This specification **supersedes all previous Walker-port and custom `coo-shell`
> specifications**. Existing implementation based on those designs is considered
> legacy and may be deleted.

---

# 1. Executive Summary

The project goal is no longer to reimplement the Omarchy Quattro launcher.

The new goal is:

> **Reuse the original Omarchy Quattro implementation wherever possible, package
> only the required upstream components for CachyOS, and continuously rebuild
> those packages as Omarchy evolves.**

The project will produce a CachyOS-safe subset of Omarchy instead of installing
the official `omarchy` package directly.

The primary user experience remains:

```text
SUPER + SPACE  -> Omarchy Quattro launcher / menu
SUPER + K      -> Omarchy-style keybinding UI
```

But the implementation strategy changes completely.

Old strategy:

```text
Omarchy source
    ↓
analyze QML
    ↓
reimplement / port launcher
    ↓
custom coo-shell
```

New strategy:

```text
Official Omarchy upstream
        ↓
pin exact version + commit
        ↓
extract/package required runtime
        ↓
minimal compatibility patches only if necessary
        ↓
Arch package
        ↓
install on CachyOS
```

The governing rule is:

> **Reuse upstream first. Package second. Patch only when necessary.
> Reimplement only as a last resort.**

---

# 2. Why This Rewrite Exists

Omarchy Quattro moved core Omarchy runtime files into Arch packages.

The official `omarchy` package contains, among other things:

```text
/usr/bin/omarchy-*
/usr/share/omarchy/install/
/usr/share/omarchy/migrations/
/usr/share/omarchy/themes/
/usr/share/omarchy/shell/
```

The Quickshell desktop shell — including the Quattro menu implementation — is
therefore already a packaged runtime artifact.

However, the official `omarchy` package is **not safe to install as a
launcher-only dependency on CachyOS**.

Its dependency tree includes:

```text
omarchy-settings
limine
limine-mkinitcpio-hook
limine-snapper-sync
snapper
sddm
...
```

`omarchy-settings` also installs or modifies system-wide configuration,
including files under:

```text
/etc
/usr/lib/systemd
/usr/share/uwsm
/etc/sddm.conf.d
/etc/mkinitcpio.conf.d
/etc/limine-entry-tool.d
```

Its install script intentionally overwrites several files, including:

```text
/etc/os-release
/etc/security/faillock.conf
/etc/nsswitch.conf
/etc/plymouth/plymouthd.conf
/etc/skel/.bashrc
```

That behavior is appropriate for a full Omarchy system but unacceptable for
this project.

Therefore:

```text
sudo pacman -S omarchy
```

is explicitly **not** the installation strategy.

Instead, this project creates a **CachyOS-specific package boundary around the
Omarchy Quattro runtime**.

---

# 3. Product Vision

A CachyOS user should be able to install a small set of packages:

```text
cachy-omarchy-shell
cachy-omarchy-overlay
```

and gain selected Omarchy Quattro desktop UX while keeping CachyOS itself.

Conceptually:

```text
CachyOS
├── CachyOS kernel
├── CachyOS repositories
├── existing Hyprland config
├── existing Waybar
├── existing notification daemon
├── existing login manager
│
├── cachy-omarchy-shell
│    └── upstream Omarchy Quattro runtime subset
│
└── cachy-omarchy-overlay
     ├── launch wrappers
     ├── user service
     ├── Hyprland bindings
     ├── compatibility environment
     └── update/build tooling
```

The project must not turn CachyOS into Omarchy.

---

# 4. Primary Goals

## 4.1 Launcher

```text
SUPER + SPACE
```

opens the original or minimally adapted Omarchy Quattro menu.

The preference order is:

1. original upstream component unchanged;
2. upstream component with environment/path adaptation;
3. small patch;
4. maintained compatibility shim;
5. reimplementation only when unavoidable.

---

## 4.2 Keybinding UI

```text
SUPER + K
```

should expose a useful keybinding dialog.

Preferred order:

1. reuse existing upstream Quattro mechanism;
2. adapt it to CachyOS Hyprland configuration;
3. reuse old project parser code if necessary;
4. custom UI only as a last resort.

---

## 4.3 Safe CachyOS Integration

The installation must not modify or replace:

```text
CachyOS identity
bootloader
kernel
initramfs policy
Plymouth
SDDM
system-wide PAM policy
system-wide NSS configuration
existing Waybar
```

Revised in v0.2.0 (M8). The desktop-surface entries — notification daemon and
lock screen — left this list. Installing cachy-omarchy is a statement that you
want what Omarchy provides, so its bar, notifications, OSD and lock come up on
upstream defaults; suppression is now the opt-out, not the default. Waybar
stays on the list because a bar is the one surface where two of them side by
side is unusable rather than merely redundant.

What replaced "must not modify" for the surfaces that left the list is not
"may do anything". No package of ours owns a path under `/etc` or a system
unit for a competing daemon, and no command of ours stops, masks, disables or
uninstalls a running one. Taking over is something the user consents to; a
D-Bus name changing hands when the shell starts is the mechanism, and it is
reversible by not starting the shell.

---

## 4.4 Repeatable Package Rebuilds

The project must support continuously rebuilding packages as upstream Omarchy
releases new versions.

The update pipeline must support:

```text
discover upstream release
        ↓
pin upstream version + commit
        ↓
update source lock
        ↓
apply local patches
        ↓
build packages
        ↓
package audit
        ↓
runtime smoke tests
        ↓
install only if tests pass
```

An upstream update must never automatically replace a working installation when
the new build or tests fail.

---

# 5. Non-Goals

The project does **not** aim to:

- install the full Omarchy distribution;
- make CachyOS identify itself as Omarchy;
- use the official `omarchy-settings` package;
- install the Omarchy boot stack;
- configure Limine;
- configure Snapper automatically;
- replace SDDM;
- replace UWSM configuration globally;
- replace PipeWire configuration;
- replace PAM / faillock policy;
- copy all Omarchy applications;
- copy all Omarchy developer tools;
- maintain a full fork of Omarchy;
- reimplement the whole Quattro shell;
- automatically accept every new upstream version.

---

# 6. Architecture Principles

## 6.1 Upstream Is the Source of Truth

Omarchy owns the implementation of Quattro.

This project should not casually fork behavior.

For upstream-derived code:

```text
basecamp/omarchy
```

is authoritative.

Our repository owns:

```text
packaging
compatibility
integration
tests
update automation
```

---

## 6.2 Pin Every Build

Never build production packages from a floating branch.

Every package must resolve to:

```text
upstream version
upstream commit SHA
local package revision
```

Example:

```text
Omarchy version: 4.0.1
Commit:          abcdef1234...
Package:         cachy-omarchy-shell 4.0.1-1
```

---

## 6.3 Keep Local Diff Small

The preferred local diff is:

```text
0 patches
```

If patches are necessary, each patch must:

- have one clear purpose;
- include a comment explaining why;
- have an associated test;
- be reviewed on every upstream bump.

---

## 6.4 Separate Upstream Runtime from Local Integration

Upstream-derived files and CachyOS-specific files must be different packages.

This allows:

```text
upstream runtime update
```

without overwriting:

```text
user integration/configuration
```

---

## 6.5 Package Ownership Must Be Explicit

Every installed system file should be owned by one of our packages.

Avoid installer scripts that copy arbitrary files into `/usr`.

Preferred:

```text
pacman owns system files
```

User configuration may live under:

```text
~/.config/cachy-omarchy/
```

---

## 6.6 User Configuration Is Not Package State

Package upgrades should not overwrite user customizations.

Defaults belong under:

```text
/usr/share/cachy-omarchy/defaults/
```

Live user configuration belongs under:

```text
~/.config/cachy-omarchy/
```

---

# 7. Package Architecture

The project initially builds two packages.

## 7.1 `cachy-omarchy-shell`

### Purpose

Contains the upstream-derived Omarchy Quattro runtime required to run the shell
and menu.

This package tracks upstream Omarchy versions.

Example:

```text
cachy-omarchy-shell 4.0.0-1
cachy-omarchy-shell 4.0.1-1
cachy-omarchy-shell 4.0.1-2
```

Meaning:

```text
4.0.1   = upstream Omarchy version
-2      = our packaging revision
```

### Expected content

The exact content is determined by the dependency audit, but likely includes
some subset of:

```text
/usr/share/cachy-omarchy/upstream/shell/
/usr/share/cachy-omarchy/upstream/themes/
/usr/lib/cachy-omarchy/bin/
```

The package MUST NOT install:

```text
/etc/os-release
/etc/mkinitcpio.conf.d/*
/etc/limine-entry-tool.d/*
/etc/sddm.conf.d/*
/etc/security/*
/etc/nsswitch.conf
/etc/plymouth/*
/etc/skel/.bashrc
```

### Dependencies

Dependencies must be derived from actual runtime use.

Expected examples:

```text
quickshell
hyprland
jq
perl
```

Potential dependencies must be audited rather than blindly copied from the
official `omarchy` package.

The official `omarchy` dependency list must **not** be copied wholesale.

---

## 7.2 `cachy-omarchy-overlay`

### Purpose

Owns CachyOS-specific integration.

Expected content:

```text
/usr/bin/cachy-omarchy-shell
/usr/bin/cachy-omarchy-launcher
/usr/bin/cachy-omarchy-keybindings

/usr/share/cachy-omarchy/defaults/
```

It may depend on:

```text
cachy-omarchy-shell
```

It should evolve independently from the upstream version.

Example:

```text
cachy-omarchy-overlay 0.1.0-1
```

---

# 8. Why Two Packages

A single package would mix two independent concerns:

```text
upstream Quattro source
+
our CachyOS integration
```

Splitting them gives:

```text
cachy-omarchy-shell
    ↑
changes whenever Omarchy changes

cachy-omarchy-overlay
    ↑
changes whenever our integration changes
```

Benefits:

- smaller upgrade surface;
- easier rollback;
- cleaner ownership;
- easier debugging;
- fewer conflicts;
- ability to test new upstream shell builds against stable integration.

---

# 9. Filesystem Layout

## 9.1 Upstream Runtime

Preferred root:

```text
/usr/share/cachy-omarchy/upstream/
```

Example:

```text
/usr/share/cachy-omarchy/upstream/
├── shell/
├── themes/
└── version
```

Avoid owning:

```text
/usr/share/omarchy
```

unless an audit proves that upstream hardcoded paths make relocation
impractical.

If relocation is impossible, prefer a compatibility symlink or wrapper before
using the original path.

Any use of:

```text
/usr/share/omarchy
```

must be an explicit architecture decision.

---

## 9.2 Project Runtime

```text
/usr/share/cachy-omarchy/
├── upstream/
├── defaults/
└── metadata/
```

## 9.3 Executables

```text
/usr/bin/cachy-omarchy-shell
/usr/bin/cachy-omarchy-launcher
/usr/bin/cachy-omarchy-keybindings
/usr/bin/cachy-omarchy-doctor
/usr/bin/cachy-omarchy-build
/usr/bin/cachy-omarchy-update
```

## 9.4 User Config

```text
~/.config/cachy-omarchy/
├── config.jsonc
├── commands.jsonc
├── environment
└── hypr/
    └── bindings.conf
```

## 9.5 User State

```text
~/.local/state/cachy-omarchy/
├── logs/
├── backups/
└── update/
```

---

# 10. Upstream Lock File

Repository must contain:

```text
upstream.lock
```

Example format:

```bash
OMARCHY_VERSION=4.0.0
OMARCHY_COMMIT=f0020448ca87329199de7cb12f2015ebc4a3e5e7
OMARCHY_CHANNEL=stable
OMARCHY_REPOSITORY=https://github.com/basecamp/omarchy.git
```

Optional:

```bash
OMARCHY_TAG=v4.0.0
OMARCHY_SOURCE_SHA256=...
```

Rules:

- production builds MUST use `OMARCHY_COMMIT`;
- tag alone is insufficient;
- updating the lock file is a reviewable change;
- package version must agree with the lock file.

---

# 11. Upstream Metadata

Create:

```text
UPSTREAM.md
```

It records:

```text
Repository
Version
Commit
Release date
Source license
Components packaged
Components intentionally excluded
Known compatibility patches
Last tested CachyOS environment
```

This document is human-readable.

`upstream.lock` is machine-readable.

---

# 12. Repository Structure

```text
cachy-omarchy-overlay/
├── SPEC.md
├── README.md
├── LICENSE
├── UPSTREAM.md
├── upstream.lock
│
├── packages/
│   ├── cachy-omarchy-shell/
│   │   ├── PKGBUILD
│   │   ├── patches/
│   │   │   └── README.md
│   │   └── install/
│   │
│   └── cachy-omarchy-overlay/
│       ├── PKGBUILD
│       ├── src/
│       └── install/
│
├── bin/
│   ├── check-upstream
│   ├── update-upstream
│   ├── build-packages
│   ├── test-packages
│   ├── install-packages
│   ├── rollback
│   └── release
│
├── overlay/
│   ├── bin/
│   │   ├── cachy-omarchy-shell
│   │   ├── cachy-omarchy-launcher
│   │   ├── cachy-omarchy-keybindings
│   │   └── cachy-omarchy-doctor
│   │
│   ├── defaults/
│   └── hypr/
│
├── patches/
│   └── README.md
│
├── tests/
│   ├── package/
│   ├── runtime/
│   ├── integration/
│   └── fixtures/
│
├── docs/
│   ├── PACKAGE_AUDIT.md
│   ├── RUNTIME_DEPENDENCIES.md
│   ├── COMMAND_AUDIT.md
│   ├── PLUGIN_AUDIT.md
│   ├── UPDATE_PROCESS.md
│   ├── ROLLBACK.md
│   └── LEGACY_MIGRATION.md
│
└── build/
    └── .gitkeep
```

---

# 13. Runtime Strategy

The desired runtime is the original Omarchy Quattro shell tree.

Preferred:

```text
Quickshell
    ↓
upstream shell.qml
    ↓
upstream plugin registry
    ↓
omarchy.menu
```

The project should not start by extracting `Menu.qml`.

The smallest acceptable unit is whatever upstream itself requires for the menu
to function reliably.

This may be:

```text
entire shell/ directory
```

That is acceptable.

The primary optimization target is **dependency safety**, not minimizing file
count.

---

# 14. `OMARCHY_PATH` Compatibility

Official Omarchy commands use:

```text
OMARCHY_PATH
```

to locate shell assets.

The overlay wrapper may set:

```bash
export OMARCHY_PATH=/usr/share/cachy-omarchy/upstream
```

before starting or calling the shell.

Preferred wrapper behavior:

```bash
#!/usr/bin/env bash
export OMARCHY_PATH=/usr/share/cachy-omarchy/upstream
...
```

If upstream components use `/usr/share/omarchy` as a hardcoded path, the
dependency audit must classify each occurrence.

Classification:

```text
ENV-COMPATIBLE
PATCH-REQUIRED
HELPER-REQUIRED
UNSAFE
```

---

# 15. Launcher Invocation

Desired public command:

```bash
cachy-omarchy-launcher
```

Expected logical behavior:

```text
ensure shell is alive
        ↓
IPC
        ↓
toggle omarchy.menu
```

The wrapper should use the same IPC model as upstream when possible.

Conceptually:

```text
qs ipc ... call shell toggle omarchy.menu ...
```

Do not reimplement IPC unless required.

---

# 16. Shell Process

The shell is expected to be long-lived.

Preferred lifecycle:

```text
Hyprland session starts (hyprland.start event fires once)
        ↓
cachy-omarchy-shell --run  (launched via overlay/hypr/bindings.lua)
        ↓
Quickshell loads upstream shell tree (inherits Hyprland WAYLAND_DISPLAY)
        ↓
launcher hotkeys send IPC
```

Benefits:

- fast launcher;
- warm app index;
- matches upstream omarchy's launch model (shell/README.md 193–198);
- no startup race: the compositor environment is already correct when the
  shell launches, so the socket-wait workaround is unnecessary.

---

# 17. User Service

The shell is launched by Hyprland autostart, not a systemd user unit:

```text
/usr/share/cachy-omarchy/hypr/bindings.lua   (autostart: hl.on("hyprland.start", …))
/usr/bin/cachy-omarchy-shell --run           (wrapper: idempotent guard, QT wayland pin,
                                             QS_DISABLE_FILE_WATCHER=1, systemd-cat logging)
```

`--run` is foreground (Hyprland `exec` forks it). `--restart` kills the running
instance (precise `quickshell -n -p <path>` match) and relaunches detached.
There is no `Restart=on-failure` (R07 auto-recovery is not provided; recovery is
manual `--restart`). Migration from the former systemd unit requires
`cachy-omarchy-bindings --force` to refresh the live bindings copy.

The service must not:

- start a second Hyprland;
- stop, mask, disable or uninstall a running Waybar, notification daemon or
  lock helper — detect and report, never evict (revised in v0.2.0; this host
  has no Waybar installed, so coexistence remains unmeasured);
- keep upstream plugins suppressed by default. Since v0.2.0 the staged
  `shell.json` is the pinned upstream file verbatim, so bar, notifications,
  OSD, idle and lock come up enabled. Suppression is added back only where a
  live conflict has been measured, and the user opts out per surface
  (`~/.local/state/omarchy/toggles/bar-off` for the bar).

---

# 18. Plugin Policy

The upstream shell may contain many first-party plugins.

Each plugin must be classified:

```text
ENABLE
AVAILABLE
DISABLE
UNSUPPORTED
```

v0.1 target:

```text
omarchy.menu       ENABLE
keybindings UI     ENABLE or ADAPT
```

This was written for v0.1, which shipped a `shell.json` with an empty
`bar.layout` and eleven entries in `disabledPlugins`. v0.2.0 reversed that:

```text
bar                UPSTREAM DEFAULT  (user opts out via the bar-off toggle)
notifications      UPSTREAM DEFAULT  (takes over mako's D-Bus name; measured)
lock               UPSTREAM DEFAULT
OSD                UPSTREAM DEFAULT
```

The staged defaults file carries no `disabledPlugins` key at all, and
`tests/runtime/test_shell_config.sh` diffs it against the pinned upstream
commit so it cannot drift back silently.

The dependency audit must determine whether disabled plugins can remain
packaged but inactive.

Do not delete upstream files just because a plugin is disabled unless doing so
reduces a real dependency or conflict.

---

# 19. Hyprland Integration

Initial bindings:

```text
SUPER + SPACE -> cachy-omarchy-launcher
SUPER + K     -> cachy-omarchy-keybindings
```

The project must not overwrite the full Hyprland config.

Preferred user integration:

```conf
source = ~/.config/cachy-omarchy/hypr/bindings.conf
```

A helper can install a managed block:

```conf
# >>> cachy-omarchy >>>
source = ~/.config/cachy-omarchy/hypr/bindings.conf
# <<< cachy-omarchy <<<
```

Conflict detection is mandatory.

---

# 20. Conflict Policy

If existing config already binds:

```text
SUPER + SPACE
SUPER + K
```

default behavior:

```text
detect
warn
do not silently override
```

An explicit command may replace the binding.

Example:

```bash
cachy-omarchy-doctor --bindings
```

or:

```bash
cachy-omarchy-configure --force-bindings
```

---

# 21. Official `omarchy` Package Policy

The project MUST NOT depend on:

```text
omarchy
omarchy-settings
```

The project may depend on:

```text
omarchy-keyring
```

only if a concrete need exists.

Prefer official Arch/CachyOS packages for generic dependencies.

The official Omarchy repository should not be added to the user's global
pacman configuration merely to install this project unless the user explicitly
chooses that mode in the future.

---

# 22. Package Source Policy

`cachy-omarchy-shell` should build directly from the pinned upstream Git commit.

Conceptual PKGBUILD:

```bash
pkgname=cachy-omarchy-shell
pkgver=4.0.0
pkgrel=1

_commit=f0020448ca87329199de7cb12f2015ebc4a3e5e7

source=(
  "omarchy::git+https://github.com/basecamp/omarchy.git#commit=${_commit}"
)

package() {
  cd "$srcdir/omarchy"

  install -d "$pkgdir/usr/share/cachy-omarchy/upstream"

  cp -a shell     "$pkgdir/usr/share/cachy-omarchy/upstream/"
}
```

This example is illustrative.

The real PKGBUILD must be based on the runtime dependency audit.

---

# 23. Patch Policy

Patches live under:

```text
packages/cachy-omarchy-shell/patches/
```

Naming:

```text
0001-disable-conflicting-default-services.patch
0002-relocatable-omarchy-path.patch
```

Every patch must include metadata in:

```text
patches/README.md
```

Example:

```text
Patch:
0002-relocatable-omarchy-path.patch

Reason:
Upstream assumes /usr/share/omarchy for this component.

Upstream issue:
<optional>

Can remove when:
Upstream accepts OMARCHY_PATH for this location.

Tests:
tests/runtime/path-relocation.sh
```

---

# 24. Patch Budget

The project should track:

```text
PATCH_COUNT
PATCH_LINES_CHANGED
```

Goal:

```text
PATCH_COUNT as low as possible
```

If patch count continuously grows, stop and reassess architecture.

A patch that imports large parts of a custom replacement shell is a design
smell.

---

# 25. Build Pipeline

Public command:

```bash
./bin/build-packages
```

Pipeline:

```text
load upstream.lock
        ↓
validate version/commit
        ↓
fetch source
        ↓
apply patches
        ↓
build cachy-omarchy-shell
        ↓
build cachy-omarchy-overlay
        ↓
package audit
        ↓
store artifacts in build/
```

Output:

```text
build/
├── cachy-omarchy-shell-4.0.0-1-any.pkg.tar.zst
└── cachy-omarchy-overlay-0.1.0-1-any.pkg.tar.zst
```

---

# 26. Clean Build Requirement

Production/release builds should run in an isolated Arch-compatible build
environment.

Preferred progression:

## v0.1

```text
makepkg
```

supported for local development.

## release quality

Use a clean chroot / containerized Arch package build environment.

Reason:

- prevents accidental host dependency leakage;
- makes dependency declarations trustworthy;
- makes builds reproducible.

The exact tool may be selected during implementation based on the current Arch
toolchain.

---

# 27. Package Audit

Before installation, every built package must pass a file audit.

`cachy-omarchy-shell` is forbidden from owning paths such as:

```text
/etc/os-release
/etc/security/
/etc/nsswitch.conf
/etc/plymouth/
/etc/mkinitcpio.conf.d/
/etc/limine-entry-tool.d/
/etc/sddm.conf.d/
/boot/
/efi/
```

The test should fail the build if forbidden files appear.

Example conceptual check:

```bash
bsdtar -tf package.pkg.tar.zst
```

then compare against forbidden path rules.

---

# 28. Runtime Dependency Audit

Before Milestone 1 implementation, create:

```text
docs/RUNTIME_DEPENDENCIES.md
```

For every required upstream executable or service:

```text
name
where referenced
package providing it
required/optional
CachyOS availability
can disable?
fallback?
```

Example:

```text
quickshell
  Required: yes
  Purpose: shell runtime
  Provider: Arch/CachyOS package

hyprctl
  Required: yes
  Purpose: compositor integration

gum
  Required: unknown
  Purpose: referenced by helper scripts only?
  Decision: audit before adding dependency
```

Do not infer dependency just because official `omarchy` depends on it.

---

# 29. Upstream Update Model

Updates are not ordinary source pulls.

They are controlled packaging events.

Public commands:

```bash
./bin/check-upstream
./bin/update-upstream
```

---

# 30. `check-upstream`

Purpose:

Determine whether a newer compatible upstream Omarchy release exists.

Output example:

```text
Current:
  Omarchy 4.0.0
  f0020448...

Available:
  Omarchy 4.0.1
  abcdef12...

Status:
  update available
```

This command must not modify files.

---

# 31. `update-upstream`

Purpose:

Prepare an update branch/change locally.

Conceptual pipeline:

```text
discover new version
        ↓
resolve exact commit
        ↓
update upstream.lock
        ↓
update PKGBUILD pkgver/_commit
        ↓
reset pkgrel=1
        ↓
attempt patches
        ↓
build
        ↓
audit
        ↓
test
```

If any stage fails:

```text
DO NOT INSTALL
DO NOT MODIFY CURRENT PACKAGE
```

---

# 32. Update State Machine

```text
CURRENT WORKING VERSION
          │
          ▼
NEW UPSTREAM FOUND
          │
          ▼
SOURCE PINNED
          │
          ▼
PATCH APPLY
     ┌────┴────┐
     │ fail    │
     ▼         ▼
  ABORT      BUILD
               │
          ┌────┴────┐
          │ fail    │
          ▼         ▼
       ABORT      AUDIT
                    │
               ┌────┴────┐
               │ fail    │
               ▼         ▼
            ABORT       TEST
                          │
                     ┌────┴────┐
                     │ fail    │
                     ▼         ▼
                  ABORT      READY
                               │
                               ▼
                         OPTIONAL INSTALL
```

---

# 33. Never Auto-Install a Broken Update

`cachy-omarchy-update` must separate:

```text
build
```

from:

```text
install
```

Safe default:

```bash
cachy-omarchy-update
```

means:

```text
check + build + test
```

Installation should require:

```bash
cachy-omarchy-update --install
```

or a separate command.

---

# 34. Versioning

## `cachy-omarchy-shell`

Track upstream:

```text
pkgver = Omarchy version
pkgrel = packaging revision
```

Examples:

```text
4.0.0-1
4.0.0-2
4.0.1-1
```

## `cachy-omarchy-overlay`

Independent semantic version:

```text
0.1.0-1
0.2.0-1
```

---

# 35. Optional `-git` Package

Future:

```text
cachy-omarchy-shell-git
```

Purpose:

Track development commits for testing.

It must:

- conflict with stable `cachy-omarchy-shell`;
- never be installed automatically;
- be clearly marked experimental.

Stable users should track Omarchy releases, not arbitrary HEAD.

---

# 36. Rollback

Every successful build/install workflow must preserve enough information to
roll back.

Preferred package cache:

```text
~/.local/state/cachy-omarchy/packages/
```

or rely on the pacman cache when reliable.

Rollback command:

```bash
./bin/rollback
```

Conceptually:

```text
current 4.0.1-1
        ↓
select previous tested build
        ↓
pacman -U 4.0.0-2
        ↓
restart shell
        ↓
smoke test
```

Rollback must not restore unrelated CachyOS system files.

---

# 37. Installation

Initial developer installation:

```bash
./bin/build-packages
./bin/test-packages
./bin/install-packages
```

Eventually:

```bash
sudo pacman -U   build/cachy-omarchy-shell-*.pkg.tar.zst   build/cachy-omarchy-overlay-*.pkg.tar.zst
```

No install script should blindly copy files into `/usr`.

---

# 38. User Configuration Initialization

On first use, if:

```text
~/.config/cachy-omarchy/
```

does not exist, copy project defaults.

Do this with a user-level helper, not a package post-install script that assumes
a particular user.

Example:

```bash
cachy-omarchy-init
```

---

# 39. Runtime Commands

Minimum commands:

```text
cachy-omarchy-shell
cachy-omarchy-launcher
cachy-omarchy-keybindings
cachy-omarchy-doctor
cachy-omarchy-reload
```

Developer/update commands remain in the source repository initially.

---

# 40. Doctor

`cachy-omarchy-doctor` should check:

```text
CachyOS / Arch-family
Hyprland
Quickshell
cachy-omarchy-shell package
cachy-omarchy-overlay package
OMARCHY_PATH compatibility root
shell.qml
shell service
Quickshell process
IPC ping
omarchy.menu availability
launcher invocation
Hyprland binding conflict
keybinding invocation
```

It should also report installed package versions:

```text
Upstream Omarchy runtime: 4.0.1-1
Overlay integration:      0.2.0-1
```

---

# 41. Logging

Runtime logs:

```text
journalctl --user -u cachy-omarchy-shell
```

Optional user log directory:

```text
~/.local/state/cachy-omarchy/logs/
```

Do not log:

- clipboard contents;
- launcher query text by default;
- environment secrets.

---

# 42. Security Requirements

## 42.1 Source

Production builds use a pinned commit.

Never:

```bash
curl URL | sh
```

## 42.2 Packages

Package audit must verify forbidden paths.

## 42.3 Commands

Do not execute upstream Omarchy commands that assume a full Omarchy system
unless audited.

Every exposed command should be classified:

```text
SAFE
ADAPTED
DISABLED
```

## 42.4 Privilege

The shell runs as the user.

No Quickshell plugin gets root access.

Package installation uses pacman normally.

---

# 43. Upstream Helper Command Audit

Quattro shell/menu actions may invoke:

```text
omarchy-*
```

helpers.

Create:

```text
docs/COMMAND_AUDIT.md
```

For each referenced helper:

```text
command
called from
purpose
dependencies
safe on CachyOS?
package/copy/wrapper/disable
```

Example classification:

```text
omarchy-shell
  ADAPT
  Thin IPC wrapper.
  Replace with cachy-omarchy-shell wrapper.

omarchy-theme-set
  DISABLE initially
  Depends on full Omarchy theme workflow.
```

---

# 44. Compatibility Shim Policy

Small wrapper commands are preferred over invasive upstream patches.

Example:

```text
upstream expects:
omarchy-shell

we provide:
compat/bin/omarchy-shell
```

only inside the controlled runtime environment.

Avoid placing large numbers of fake `omarchy-*` commands globally in
`/usr/bin`.

Preferred search path:

```text
/usr/lib/cachy-omarchy/compat/bin
```

prepended only for the shell process.

---

# 45. Environment Isolation

The systemd user service can define:

```text
OMARCHY_PATH=/usr/share/cachy-omarchy/upstream
PATH=/usr/lib/cachy-omarchy/compat/bin:...
```

This allows compatibility helpers without polluting the user's general shell
environment.

---

# 46. Testing Layers

Testing is divided into four layers.

## 46.1 Package Tests

No graphical session required.

Test:

- package files;
- forbidden paths;
- declared dependencies;
- version metadata;
- lock consistency;
- patch application;
- reproducible source pin.

## 46.2 Static Runtime Tests

Inspect upstream/runtime tree.

Test:

- expected shell entry exists;
- expected plugin exists;
- no missing project wrapper;
- configuration paths resolve.

## 46.3 Shell Smoke Tests

Inside a Hyprland/Wayland session:

```text
service starts
IPC responds
menu plugin exists
menu can open
menu can close
```

## 46.4 Integration Tests

Manual or automated environment:

```text
SUPER + SPACE
SUPER + K
application launch
shell restart
package upgrade
package downgrade
```

---

# 47. Required Package Tests

At minimum:

```text
P01 forbidden /etc paths absent
P02 omarchy-settings not dependency
P03 limine not dependency
P04 sddm not dependency
P05 shell.qml packaged
P06 omarchy.menu packaged
P07 upstream commit matches lock
P08 pkgver matches lock
P09 patch set applies cleanly
P10 package can be removed cleanly
```

---

# 48. Required Runtime Tests

At minimum:

```text
R01 shell process starts
R02 shell IPC ping succeeds
R03 menu plugin is discoverable
R04 launcher toggles
R05 Escape closes launcher
R06 application can be launched
R07 restarting service recovers
R08 absence of Waybar modification
R09 no notification daemon is stopped, masked or uninstalled by us
R10 no lock helper is stopped, masked or uninstalled by us
```

R09 and R10 were reworded in v0.2.0. They used to read "absence of ... 
replacement", which the packaged defaults satisfied by disabling the upstream
plugins outright. That suppression is gone: the shell now provides
notifications and lock, and on this host it takes over mako's D-Bus name when
it starts. What survives, and what these criteria measure, is that we never
own a `/etc` path or system unit for a competing daemon and never stop one —
`tests/runtime/test_runtime_reliability.sh` audits both directions.

---

# 49. Required Update Tests

```text
U01 no-update exits cleanly
U02 new version updates lock
U03 pkgrel resets on pkgver update
U04 local revision can bump pkgrel
U05 patch failure blocks install
U06 build failure blocks install
U07 audit failure blocks install
U08 runtime failure blocks install
U09 previous package remains installable
U10 rollback works
```

---

# 50. Legacy Architecture Retirement

Previous implementation may contain:

```text
custom coo-shell
custom Quickshell host
ported Menu.qml
Walker theme
Walker launcher
custom app index
custom command index
```

These are no longer architectural requirements.

Default action:

```text
delete or archive
```

Do not preserve old code merely because it exists.

---

# 51. Legacy Code That May Be Reused

Generic code can be retained if it still fits the new design:

```text
Hyprland config discovery
managed source block insertion
keybinding conflict detection
backup helpers
doctor output helpers
test fixtures
recursive Hyprland source parser
```

Reuse must be based on usefulness, not sunk cost.

---

# 52. Migration Rule

A previous implementation feature should be retained only if:

```text
it solves a requirement in this SPEC
AND
it is simpler than using upstream
AND
it does not increase maintenance burden
```

Otherwise remove it.

---

# 53. Milestone 0 — Official Package Audit

## Goal

Understand exactly what can be reused without installing official Omarchy.

## Deliverables

```text
docs/PACKAGE_AUDIT.md
docs/RUNTIME_DEPENDENCIES.md
docs/COMMAND_AUDIT.md
docs/PLUGIN_AUDIT.md
```

## Tasks

Inspect official:

```text
omarchy PKGBUILD
omarchy-settings PKGBUILD
omarchy-settings.install
shell/
bin/omarchy-shell
```

Record:

- upstream paths;
- package dependencies;
- shell dependencies;
- helper commands;
- unsafe system integrations;
- menu plugin runtime needs.

## Exit Criteria

We can answer:

> "What is the minimum safe subset of Omarchy Quattro required to run
> `omarchy.menu` on CachyOS?"

No implementation beyond audit is required.

---

# 54. Milestone 1 — Minimal `cachy-omarchy-shell` Package

## Goal

Build the upstream shell runtime as a standalone Arch package.

## Requirements

- pinned upstream source;
- no `omarchy-settings`;
- no bootloader dependencies;
- no global CachyOS identity changes;
- package audit passes.

## Exit Criteria

```bash
makepkg
```

produces:

```text
cachy-omarchy-shell-<version>-<rel>-any.pkg.tar.zst
```

and forbidden-path audit passes.

---

# 55. Milestone 2 — Launch Original Quattro Shell

## Goal

Run the packaged upstream shell on CachyOS.

Implement only the compatibility needed to start it.

Likely tools:

```text
OMARCHY_PATH
compat PATH
systemd user service
small wrapper scripts
```

## Exit Criteria

```text
Quickshell process starts
IPC ping succeeds
no full Omarchy installation exists
```

---

# 56. Milestone 3 — Original Quattro Launcher

## Goal

Open the upstream `omarchy.menu`.

Implement:

```text
cachy-omarchy-launcher
SUPER + SPACE integration
```

Audit and disable unsupported menu commands.

## Exit Criteria

```text
SUPER + SPACE
```

opens the original/minimally patched Quattro launcher and launches normal
desktop applications.

---

# 57. Milestone 4 — Keybinding UI

## Goal

Provide:

```text
SUPER + K
```

Prefer upstream.

If upstream assumes Omarchy-specific config, adapt data collection while keeping
the upstream visual/runtime mechanism.

Use legacy parser only if useful.

---

# 58. Milestone 5 — Overlay Package

Package all CachyOS-specific integration as:

```text
cachy-omarchy-overlay
```

Remove ad-hoc installation scripts from the normal user path.

Exit:

```text
pacman owns all system integration files
```

---

# 59. Milestone 6 — Update/Rebuild Pipeline

Implement:

```text
check-upstream
update-upstream
build-packages
test-packages
install-packages
rollback
```

Exit:

A newer Omarchy release can be adopted without manually rewriting PKGBUILD
values.

---

# 60. Milestone 7 — Reliability

Implement:

```text
clean builds
package audits
runtime tests
doctor
upgrade test
rollback test
documentation
```

This is the v0.1 release candidate.

---

# 61. v0.1 Acceptance Criteria

All must be true:

- [x] Runs on CachyOS.
- [x] Omarchy OS is not installed.
- [x] Official `omarchy` package is not required.
- [x] Official `omarchy-settings` package is not required.
- [x] Quickshell is used.
- [x] Upstream Quattro shell source is reused.
- [x] Upstream source is pinned to a commit.
- [x] `cachy-omarchy-shell` builds successfully.
- [x] Package owns no forbidden system paths.
- [x] Long-running shell starts as user.
- [x] IPC works.
- [x] `SUPER + SPACE` opens Quattro launcher.
- [x] Normal applications can launch.
- [x] `SUPER + K` opens keybinding UI.
- [x] Existing Hyprland config is preserved.
- [ ] An installed Waybar is not removed or stopped by us. *(이 호스트에 Waybar 가 설치돼 있지 않아 공존은 여전히 미검증)*
- [x] A running notification daemon is not stopped, masked or uninstalled by us. *(v0.2.0 개정 — 셸이 알림을 제공하고 mako 의 D-Bus 이름을 인계받는다. 데몬을 죽이지는 않는다)*
- [ ] An installed lock helper is not removed or stopped by us. *(미검증 — hyprlock 등 live lock 설정과 상호작용 실측 안 함)*
- [x] Rebuild against a newer upstream release is automated.
- [x] Failed updates do not install.
- [x] Previous working package can be rolled back.

Evidence ledger: `docs/RC_GAP_INVENTORY.md` (측정됨 / 미검증 / 추론됨 구분). 라이브
실측 기록은 `docs/RUNTIME_STARTUP.md` §12–§16. 19/21 측정됨; 2건(Waybar 공존, lock
공존)은 호스트 환경 제약으로 미검증 — 패키지 설계는 보존하지만 라이브 입증은 안 됨.
0.1.2 release (cachy-omarchy-overlay 0.1.2-1) 시점 기준. R07 자동 복구는
systemd 유닛 제거(4c5731b)로 더 이상 shipped feature 가 아님(§16.6) — 이는 §61 의
명시 항목이 아님.

---

# 62. Update UX

Desired eventual user command:

```bash
cachy-omarchy-update
```

Output:

```text
Checking Omarchy upstream...

Installed runtime:
  4.0.0-2

Latest supported upstream:
  4.0.1

Preparing build...
  source      OK
  patches     OK
  package     OK
  audit       OK
  smoke test  OK

New package is ready:
  cachy-omarchy-shell-4.0.1-1

Run with --install to upgrade.
```

---

# 63. CI / Automation

Future repository CI should:

```text
check upstream releases
build packages
run package audit
run static tests
publish build artifacts
```

A scheduled upstream check may open an update PR.

The CI must **not** silently publish a release when runtime tests are required
but unavailable.

---

# 64. Future Local Repository

Once stable, packages may be served through a small pacman repository.

Example concept:

```text
[cachy-omarchy]
Server = ...
```

But this is explicitly deferred until:

- package boundaries are stable;
- signing is implemented;
- update tests are reliable.

Initial distribution is local `.pkg.tar.zst`.

---

# 65. Signing

Future published packages should be signed.

Do not copy the upstream Omarchy repository's trust configuration blindly.

A public package repository requires:

```text
own signing key
documented trust bootstrap
signed database/packages
```

This is out of scope for v0.1 local builds.

---

# 66. Failure Philosophy

The project must prefer:

```text
do nothing
```

over:

```text
break the desktop
```

If uncertain:

- do not install;
- do not overwrite;
- leave previous package in place;
- print actionable diagnostics.

Adopting upstream defaults in v0.2.0 did not weaken this. Coming up on
upstream defaults is a decision about what our own shell draws; it is not a
licence to reach into somebody else's daemon. The rule for a competing
surface is detect, report, and let the user decide:

- no command of ours stops, masks, disables or uninstalls a running daemon —
  not `init`, not `doctor`, not any install script;
- user state is never deleted to change a default. A `bar-off` toggle written
  by 0.1.x survives the upgrade; `doctor` prints the one-line `rm` and stops
  there;
- where a takeover is inherent to the mechanism — a D-Bus name changing hands
  when the shell starts — it must be measured, written down, and reversible by
  not starting the shell.

---

# 67. Development Rules for Coding Agents

Any AI/code agent implementing this specification MUST:

1. Read the entire SPEC.
2. Treat all earlier Walker/custom-shell specs as obsolete.
3. Start with Milestone 0.
4. Do not reimplement the launcher before proving upstream cannot be reused.
5. Never add `omarchy-settings` as a dependency.
6. Never add Limine merely because official Omarchy depends on it.
7. Never copy the official dependency list wholesale.
8. Pin exact upstream commits.
9. Keep patches minimal.
10. Add a test for every patch.
11. Keep upstream runtime and local integration in separate packages.
12. Run package forbidden-path audit before installation.
13. Never auto-install a build that failed tests.
14. Preserve rollback artifacts.
15. Avoid modifying `/etc` unless this SPEC explicitly allows it.
16. Never modify `/etc/os-release`.
17. Never replace SDDM/Plymouth/bootloader configuration.
18. Never assume the user's Hyprland config location without discovery.
19. Keep user settings outside package-owned system directories.
20. Prefer compatibility wrappers over invasive source patches.
21. Prefer source patches over full component rewrites.
22. Report upstream incompatibilities clearly.
23. Run shell/package tests before declaring a milestone complete.
24. Do not preserve legacy code solely because it is already implemented.

---

# 68. First Coding-Agent Prompt

```text
Read SPEC.md completely.

All previous Walker and custom coo-shell architecture is obsolete.

Implement Milestone 0 only.

Audit the pinned Omarchy Quattro release and produce:

- docs/PACKAGE_AUDIT.md
- docs/RUNTIME_DEPENDENCIES.md
- docs/COMMAND_AUDIT.md
- docs/PLUGIN_AUDIT.md

Focus on determining the minimum safe subset needed to run the original
Omarchy Quattro `omarchy.menu` on CachyOS.

Inspect:
- official omarchy PKGBUILD
- official omarchy-settings PKGBUILD
- omarchy-settings.install
- shell/
- bin/omarchy-shell
- every helper invoked by the menu/shell startup path

Classify dependencies as:
- REQUIRED
- OPTIONAL
- DISABLE
- UNSAFE

Classify source adaptations as:
- NONE
- ENVIRONMENT
- WRAPPER
- PATCH
- REIMPLEMENT

Do not implement a custom launcher.
Do not install omarchy or omarchy-settings.
Do not modify the host system.
Record the exact upstream version and commit used.
```

---

# 69. Second Coding-Agent Prompt

```text
Read SPEC.md and all Milestone 0 audit documents.

Implement Milestone 1 only.

Create packages/cachy-omarchy-shell/PKGBUILD.

Requirements:
- build from exact commit in upstream.lock
- package only audited runtime files
- no omarchy-settings dependency
- no Limine/Snapper/SDDM dependency unless audit proves a runtime requirement
- no forbidden /etc paths
- do not install the package yet

Add package tests:
- forbidden path audit
- lock/pkgver consistency
- expected shell files
- expected menu plugin
- dependency assertions

Build locally and report exact results.
```

---

# 70. Third Coding-Agent Prompt

```text
Read SPEC.md and audit documents.

Implement Milestone 2.

Goal:
Run the packaged original Omarchy Quattro shell on CachyOS.

Use, in preference order:
1. environment variables
2. controlled compatibility PATH
3. wrapper scripts
4. minimal patches

Do not build a new Quickshell host.

Add:
- cachy-omarchy-shell wrapper
- user systemd service
- IPC ping test

Do not enable bar/notifications/lock/OSD unless required for shell startup.
If upstream cannot start without one of these, document the dependency before
changing scope.
```

---

# 71. Fourth Coding-Agent Prompt

```text
Implement Milestone 3 only.

Use the running packaged upstream shell.

Create:
- cachy-omarchy-launcher
- Hyprland integration for SUPER+SPACE

Invoke the original upstream `omarchy.menu` through its IPC path.

Audit every Omarchy-specific command visible from the launcher:
- safe commands may remain
- adaptable commands get wrappers
- unsafe/full-OS commands are disabled

Do not replace the menu UI with custom QML.
```

---

# 72. Fifth Coding-Agent Prompt

```text
Implement Milestones 4 and 5.

Add SUPER+K keybinding UI, preferring upstream behavior.

Package all CachyOS-specific integration as cachy-omarchy-overlay.

The end state must be installable through pacman packages rather than scripts
copying files into /usr.
```

---

# 73. Sixth Coding-Agent Prompt

```text
Implement Milestones 6 and 7.

Create the upstream update/rebuild pipeline:

check-upstream
update-upstream
build-packages
test-packages
install-packages
rollback

Rules:
- exact upstream commit pin
- patch failure blocks install
- build failure blocks install
- package audit failure blocks install
- runtime test failure blocks install
- keep previous known-good package
- reset pkgrel to 1 when upstream pkgver changes
- allow pkgrel bump for packaging-only fixes
```

---

# 74. Definition of Done

The project is successful when:

```text
CachyOS
    +
normal existing desktop setup
    +
two controlled Arch packages
```

provides the desired Quattro UX:

```text
SUPER + SPACE -> original/minimally-adapted Quattro launcher
SUPER + K     -> keybinding UI
```

and can be upgraded with:

```text
new upstream Omarchy release
        ↓
rebuild package
        ↓
test
        ↓
optional install
```

without converting the machine into Omarchy.

---

# 75. Final Architecture Statement

The project is **not a launcher port**.

The project is **not a partial Omarchy installer**.

The project is:

> **A continuously rebuildable, CachyOS-safe Arch packaging and compatibility
> layer for selected Omarchy Quattro runtime components.**

The maintenance strategy is:

```text
UPSTREAM
  first

PACKAGE
  what we need

ISOLATE
  CachyOS-specific integration

PATCH
  only incompatibilities

TEST
  every update

INSTALL
  only known-good builds

ROLL BACK
  whenever necessary
```

That is the architecture going forward.

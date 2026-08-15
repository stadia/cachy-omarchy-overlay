# CachyOS Omarchy Quattro Overlay — SPEC.md

> Status: Draft v0.2  
> Updated: 2026-08-15  
> Target platform: CachyOS + Hyprland  
> UI runtime: Quickshell  
> Upstream reference: Omarchy `quattro` branch  
> Primary goal: Run an Omarchy Quattro-style launcher and keybinding UI on CachyOS without installing or replacing the full Omarchy desktop.

---

## 0. Executive Summary

This project is a **CachyOS desktop overlay**, not an Omarchy installer.

The first version originally targeted the older Walker-based Omarchy UX.  
That design is now replaced by a **Quickshell-based Quattro launcher port**.

The v0.1 product must provide:

```text
SUPER + SPACE  -> Quattro-style launcher / menu
SUPER + K      -> searchable keybinding cheat sheet
```

while preserving:

```text
CachyOS
Hyprland
existing user config
existing bar
existing notifications
existing lock screen
existing shell
```

The project must NOT require a full Omarchy installation.

---

# 1. Why the Architecture Changed

Older Omarchy versions used Walker for launcher/menu surfaces.

Omarchy Quattro instead runs the desktop UI through a long-lived Quickshell
process called `omarchy-shell`.

In Quattro:

```text
omarchy-shell
├── bar
├── menus
├── overlays
├── notifications
├── OSD
├── lock screen
├── services
└── plugins
```

The first-party Omarchy command menu is:

```text
plugin id: omarchy.menu
entry point: shell/plugins/menu/Menu.qml
kind: menu
```

It is summoned through shell IPC rather than started as an independent
Quickshell program.

Conceptually:

```text
keybind
  ↓
omarchy-shell shell summon omarchy.menu ...
  ↓
PluginRegistry
  ↓
Menu.qml
```

This matters because simply copying `Menu.qml` to CachyOS is not sufficient.

The upstream menu expects shell-provided runtime context such as:

```text
omarchyPath
shell
manifest
pluginRegistry
shared services
theme singletons
IPC lifecycle
```

Therefore this project needs a **small compatibility host** around the menu.

---

# 2. Project Positioning

Working name:

```text
cachy-omarchy-overlay
```

Short command prefix:

```text
coo
```

Meaning:

```text
Cachy Omarchy Overlay
```

The project is best understood as:

```text
CachyOS
  +
Hyprland
  +
Quickshell
  +
small Omarchy-compatible launcher host
```

NOT:

```text
CachyOS + full Omarchy
```

---

# 3. Product Goals

## 3.1 v0.1 Goals

A user should be able to run:

```bash
git clone <repo>
cd cachy-omarchy-overlay
./install.sh
```

and gain:

```text
SUPER + SPACE
    -> Quattro-style app/command launcher

SUPER + K
    -> Quattro-style searchable keybinding viewer
```

The installer should:

- detect CachyOS / Arch-family environment;
- detect Hyprland;
- install or validate Quickshell;
- install the project-owned Quickshell host;
- install the launcher plugin;
- install the keybinding plugin;
- add a small Hyprland source file;
- preserve all existing configuration;
- support reinstallation;
- support uninstall;
- support diagnosis with `doctor.sh`.

---

## 3.2 UX Goals

The launcher should feel close to Omarchy Quattro in:

- window placement;
- keyboard navigation;
- rounded visual surface;
- typography;
- result spacing;
- active row treatment;
- icon presentation;
- fuzzy search;
- app discovery;
- command discovery;
- near-instant summon time.

Exact pixel parity is desirable but is not a v0.1 requirement.

---

## 3.3 Secondary Goals

Later versions may support:

- clipboard overlay;
- emoji picker;
- power menu;
- theme switching;
- Waybar integration;
- optional Omarchy-style bar;
- notifications;
- OSD;
- plugin loading;
- custom user launcher entries;
- dynamic CachyOS theming.

---

# 4. Non-Goals

v0.1 MUST NOT:

- install Omarchy as an operating system;
- replace CachyOS repositories;
- replace the CachyOS kernel;
- replace Hyprland;
- replace Waybar;
- replace the user's notification daemon;
- replace the user's lock screen;
- replace the user's terminal;
- replace the user's shell;
- rewrite `~/.config/hypr`;
- install the full `omarchy-shell`;
- require `~/.local/share/omarchy`;
- depend on an Omarchy upgrade script;
- automatically track every upstream Quattro commit;
- implement every Omarchy menu action;
- execute missing Omarchy commands blindly.

---

# 5. Design Principles

## 5.1 Overlay, not replacement

User configuration is authoritative.

Project configuration lives separately:

```text
~/.config/cachy-omarchy-overlay/
```

Hyprland only imports one managed source.

---

## 5.2 Quickshell-native

The launcher should be implemented as a Quickshell surface.

Do not recreate Quattro UI using Walker unless a fallback is explicitly
implemented later.

---

## 5.3 Upstream-informed, independently runnable

The project may adapt source and ideas from Omarchy Quattro, but the result must
run independently on CachyOS.

No runtime dependency on:

```text
$OMARCHY_PATH
omarchy-shell
omarchy command
Omarchy themes directory
Omarchy shell.json
```

unless explicitly supplied through an optional compatibility adapter.

---

## 5.4 Minimal compatibility layer

Do not port the entire Omarchy shell just to show the launcher.

Only provide the services required by the launcher.

Preferred:

```text
small host
+
small API compatibility layer
+
ported menu
```

Avoid:

```text
fork entire omarchy-shell
```

---

## 5.5 Reversible

Every existing file modified by the installer must have:

- backup;
- managed markers;
- uninstall path.

---

## 5.6 Idempotent

Running:

```bash
./install.sh
./install.sh
./install.sh
```

must not duplicate:

- source blocks;
- keybindings;
- services;
- symlinks;
- autostart entries.

---

## 5.7 No hidden privilege escalation

The installer itself runs as the normal user.

`sudo` may be used only for explicit package installation.

---

# 6. Upstream Quattro Model

The relevant upstream model is:

```text
omarchy-shell
    │
    ├── shell host
    │
    ├── PluginRegistry
    │
    ├── IPC
    │
    ├── theme singletons
    │
    └── first-party plugins
             │
             └── omarchy.menu
                    └── Menu.qml
```

Quattro plugin entry points are not standalone `ShellRoot`s.

They are components loaded by the host.

Menu-like plugins expose lifecycle methods conceptually equivalent to:

```qml
function open(payloadJson)
function close()
```

The host supplies context to plugins.

This project must reproduce only the subset required by its launcher.

---

# 7. Architecture Options

Three architectures were considered.

---

## Option A — Install full upstream `omarchy-shell`

```text
CachyOS
└── upstream omarchy-shell
```

### Advantages

- closest to upstream;
- minimum code divergence;
- original plugin system;
- original theme system.

### Problems

- brings unrelated bar/services/desktop behavior;
- likely collisions with existing CachyOS components;
- assumes Omarchy runtime layout;
- difficult to support cleanly as launcher-only software.

### Decision

```text
REJECTED for v0.1
```

May be supported later as an optional "full shell mode".

---

## Option B — Standalone Menu.qml only

```text
quickshell -p Menu.qml
```

### Advantages

- conceptually simple.

### Problems

`Menu.qml` expects host-injected state and shared services.

### Decision

```text
REJECTED
```

---

## Option C — Minimal compatibility host

```text
CachyOS
└── coo-shell
     ├── IPC
     ├── Theme
     ├── AppIndex
     ├── CommandIndex
     ├── compatibility services
     └── plugins
          ├── launcher
          └── keybindings
```

### Advantages

- preserves Quattro architecture;
- keeps long-lived process for fast summon;
- does not own the rest of the desktop;
- portable;
- testable;
- can gradually add plugins.

### Decision

```text
SELECTED
```

---

# 8. High-Level Architecture

```text
                        Hyprland
                           │
             ┌─────────────┴─────────────┐
             │                           │
      SUPER + SPACE                SUPER + K
             │                           │
             v                           v
       coo-launcher               coo-keybindings
             │                           │
             └─────────────┬─────────────┘
                           │ IPC
                           v
                  +------------------+
                  |    coo-shell     |
                  |   Quickshell     |
                  +--------+---------+
                           |
          +----------------+----------------+
          |                                 |
          v                                 v
 +------------------+              +------------------+
 | launcher plugin  |              | keybind plugin   |
 | Quattro-inspired |              | searchable list  |
 +--------+---------+              +---------+--------+
          |                                  |
          +---------------+------------------+
                          |
                          v
                +-------------------+
                | shared services   |
                +-------------------+
                | Theme             |
                | AppIndex          |
                | CommandIndex      |
                | Hyprland bindings |
                | Config            |
                +-------------------+
```

---

# 9. Process Model

`coo-shell` should be a long-running user process.

Reason:

- app index remains warm;
- config remains parsed;
- launcher summons quickly;
- avoids Quickshell startup on every hotkey;
- matches the useful part of Quattro's architecture.

Lifecycle:

```text
login
  ↓
coo-shell starts
  ↓
waits for IPC
  ↓
SUPER + SPACE
  ↓
launcher becomes visible
```

If the process is not running:

```text
coo-launcher
```

may start it before retrying the IPC call.

---

# 10. Repository Structure

```text
cachy-omarchy-overlay/
├── SPEC.md
├── README.md
├── LICENSE
│
├── install.sh
├── uninstall.sh
├── doctor.sh
│
├── bin/
│   ├── coo-shell
│   ├── coo-launcher
│   ├── coo-keybindings
│   ├── coo-reload
│   └── coo-generate-keybindings
│
├── shell/
│   ├── shell.qml
│   ├── ipc/
│   │   └── ShellIpc.qml
│   │
│   ├── services/
│   │   ├── Config.qml
│   │   ├── Theme.qml
│   │   ├── AppIndex.qml
│   │   ├── CommandIndex.qml
│   │   ├── HyprlandBindings.qml
│   │   └── Compatibility.qml
│   │
│   ├── components/
│   │   ├── SearchField.qml
│   │   ├── ResultList.qml
│   │   ├── ResultRow.qml
│   │   ├── Icon.qml
│   │   └── Surface.qml
│   │
│   └── plugins/
│       ├── launcher/
│       │   ├── Launcher.qml
│       │   ├── manifest.json
│       │   └── model/
│       │
│       └── keybindings/
│           ├── Keybindings.qml
│           └── manifest.json
│
├── config/
│   ├── config.jsonc
│   ├── commands.jsonc
│   └── theme.jsonc
│
├── hypr/
│   ├── overlay.conf
│   └── bindings.conf
│
├── lib/
│   ├── common.sh
│   ├── env.sh
│   ├── packages.sh
│   ├── backup.sh
│   ├── hyprland.sh
│   ├── quickshell.sh
│   ├── autostart.sh
│   └── uninstall.sh
│
├── systemd/
│   └── coo-shell.service
│
└── tests/
    ├── shell/
    ├── installer/
    ├── fixtures/
    └── test.sh
```

---

# 11. Installed Runtime Layout

Configuration:

```text
~/.config/cachy-omarchy-overlay/
├── config.jsonc
├── commands.jsonc
├── theme.jsonc
├── hypr/
│   ├── overlay.conf
│   └── bindings.conf
└── generated/
    ├── keybindings.json
    └── app-cache.json
```

Program data:

```text
~/.local/share/cachy-omarchy-overlay/
├── shell/
├── bin/
└── VERSION
```

User state:

```text
~/.local/state/cachy-omarchy-overlay/
├── backups/
├── logs/
└── install.json
```

User service:

```text
~/.config/systemd/user/coo-shell.service
```

Optional CLI symlinks:

```text
~/.local/bin/coo-shell
~/.local/bin/coo-launcher
~/.local/bin/coo-keybindings
~/.local/bin/coo-reload
```

---

# 12. Core Runtime Components

## 12.1 `shell.qml`

### Goal

Provide the smallest Quickshell root capable of hosting launcher surfaces.

Responsibilities:

- instantiate core services;
- expose IPC;
- keep launcher plugin loaded or load it cheaply;
- own layer-shell launcher windows;
- route summon/hide/toggle calls.

MUST NOT:

- create a bar;
- create notifications;
- create OSD;
- create lock screen;
- act as polkit agent.

---

## 12.2 `Compatibility.qml`

### Goal

Provide only the small API surface required by adapted upstream components.

Potential compatibility properties:

```qml
property string omarchyPath
property var shell
property var manifest
property var pluginRegistry
```

However the preferred implementation is to progressively eliminate upstream
Omarchy-specific dependencies.

Target:

```text
compatibility layer shrinks over time
```

rather than growing into a full Omarchy shell clone.

---

# 13. Launcher Plugin

## 13.1 Goal

Reproduce the useful behavior and visual language of Quattro's `omarchy.menu`.

Launch:

```text
SUPER + SPACE
```

CLI:

```bash
coo-launcher
```

IPC concept:

```text
coo-shell launcher toggle
```

---

## 13.2 Modes

v0.1 launcher should search at least:

```text
Applications
Commands
```

Possible later modes:

```text
Files
Clipboard
Emoji
Web search
Themes
Settings
```

---

## 13.3 Application Index

Use freedesktop `.desktop` entries.

Search paths include:

```text
/usr/share/applications
~/.local/share/applications
$XDG_DATA_DIRS/*/applications
```

Requirements:

- parse `.desktop` metadata;
- honor `NoDisplay`;
- honor `Hidden`;
- resolve application icon;
- preserve `Exec`;
- strip desktop field codes safely when launching;
- support localized `Name` when feasible;
- refresh on changes.

Normalized model:

```json
{
  "type": "application",
  "id": "org.mozilla.firefox",
  "name": "Firefox",
  "keywords": ["browser", "web"],
  "icon": "firefox",
  "exec": "firefox"
}
```

---

## 13.4 Command Index

Do not copy Omarchy commands that cannot work on CachyOS.

Project commands live in:

```text
~/.config/cachy-omarchy-overlay/commands.jsonc
```

Example:

```jsonc
[
  {
    "name": "Reload Hyprland",
    "keywords": ["hypr", "reload"],
    "action": "hyprctl reload"
  },
  {
    "name": "Open Keybindings",
    "keywords": ["keys", "hotkeys", "shortcuts"],
    "action": "coo-keybindings"
  }
]
```

Optional upstream-inspired entries may be provided only when their target
program is detected.

---

## 13.5 Search Ranking

Minimum ranking signals:

```text
exact name match
prefix match
acronym match
substring match
keyword match
fuzzy match
recent usage (future)
```

Example:

```text
"ff" -> Firefox
"term" -> Ghostty / Kitty / terminal
```

The ranking algorithm should be deterministic.

---

## 13.6 Launcher Actions

Selecting an application:

```text
Quickshell.execDetached(...)
```

or equivalent safe detached process launch.

Selecting a command:

```text
execute configured action
```

Never concatenate untrusted user search text into a shell command.

---

# 14. Launcher UI

## 14.1 Surface

Preferred:

```text
LayerShell surface
keyboard exclusive while open
centered
transparent outer background
rounded content panel
```

## 14.2 Components

```text
Launcher.qml
├── Surface
│   ├── SearchField
│   └── ResultList
│       └── ResultRow
```

## 14.3 Keyboard Controls

Required:

```text
Esc         close
Up          previous
Down        next
Ctrl+P      previous (optional)
Ctrl+N      next (optional)
Enter       execute
Tab         mode/action (future)
```

## 14.4 Mouse

Mouse support is allowed but keyboard interaction is primary.

---

# 15. Theme System

Quattro uses shared shell theme roles.

This project will implement a smaller local theme model.

Configuration:

```text
~/.config/cachy-omarchy-overlay/theme.jsonc
```

Example:

```jsonc
{
  "font": {
    "family": "Inter",
    "mono": "JetBrainsMono Nerd Font",
    "size": 14
  },

  "surface": {
    "background": "#1e1e2e",
    "border": "#45475a",
    "radius": 14
  },

  "text": {
    "primary": "#cdd6f4",
    "muted": "#9399b2"
  },

  "selection": {
    "background": "#313244"
  }
}
```

Future versions may add adapters for:

- Omarchy theme files;
- Matugen;
- pywal;
- CachyOS themes.

---

# 16. Keybinding Cheat Sheet

## 16.1 Goal

```text
SUPER + K
```

opens a Quickshell-native searchable list of current shortcuts.

No Walker dependency.

---

## 16.2 UI

The keybinding viewer should reuse:

```text
Surface
SearchField
ResultList
ResultRow
Theme
```

from the launcher.

This means launcher and keybindings visually match.

---

## 16.3 Data Sources

The viewer combines:

```text
project-managed bindings
+
existing user Hyprland bindings
```

Supported config declarations:

```text
bind
binde
bindl
bindm
bindr
bindd
```

`bindd` descriptions are preferred.

---

## 16.4 Normalized Binding

```json
{
  "mods": ["SUPER"],
  "key": "K",
  "description": "Show keybindings",
  "dispatcher": "exec",
  "argument": "coo-keybindings",
  "source": "overlay",
  "category": "Desktop"
}
```

---

## 16.5 Recursive `source`

Hyprland configs commonly include:

```conf
source = ~/.config/hypr/bindings.conf
```

The parser must:

- resolve `~`;
- resolve relative paths relative to the containing file;
- avoid cycles;
- stop at configurable recursion depth;
- ignore unreadable files with diagnostics.

Suggested maximum depth:

```text
20
```

---

## 16.6 Generator

CLI:

```bash
coo-generate-keybindings
coo-generate-keybindings --format json
coo-generate-keybindings --format tsv
```

Output cache:

```text
~/.config/cachy-omarchy-overlay/generated/keybindings.json
```

The Quickshell service may later parse configs directly.

For v0.1, a small shell/Python generator is acceptable.

---

# 17. Hyprland Integration

The project owns:

```text
~/.config/cachy-omarchy-overlay/hypr/overlay.conf
```

User root config receives only:

```conf
# >>> cachy-omarchy-overlay >>>
source = ~/.config/cachy-omarchy-overlay/hypr/overlay.conf
# <<< cachy-omarchy-overlay <<<
```

Overlay:

```conf
source = ~/.config/cachy-omarchy-overlay/hypr/bindings.conf
```

Initial bindings:

```conf
bindd = SUPER, SPACE, Open launcher, exec, coo-launcher
bindd = SUPER, K, Show keybindings, exec, coo-keybindings
```

Actual syntax must be validated against the installed Hyprland version.

---

# 18. Keybinding Conflict Policy

Before installation, inspect active config.

If:

```text
SUPER + SPACE
```

or:

```text
SUPER + K
```

already exists:

default behavior:

```text
warn + skip conflicting project binding
```

Do NOT silently override.

Example:

```text
Conflict detected

SUPER + SPACE
Existing: exec, walker
Requested: exec, coo-launcher

Skipped.

Use:
  ./install.sh --force-bindings

to replace it.
```

Forced mode may emit:

```conf
unbind = SUPER, SPACE
bindd = SUPER, SPACE, Open launcher, exec, coo-launcher
```

but only in project-owned config.

---

# 19. IPC

## 19.1 Goal

Hotkey execution must be cheap.

Desired path:

```text
coo-launcher
  ↓
IPC request
  ↓
existing coo-shell process
  ↓
toggle launcher
```

The CLI must not start a new full Quickshell process every time.

---

## 19.2 Commands

Public CLI:

```bash
coo-shell ping
coo-shell launcher open
coo-shell launcher close
coo-shell launcher toggle
coo-shell keybindings open
coo-shell keybindings close
coo-shell keybindings toggle
coo-shell reload
```

Thin convenience wrappers:

```bash
coo-launcher
coo-keybindings
```

---

## 19.3 Auto-start Recovery

If:

```text
coo-shell ping
```

fails:

1. start user service;
2. wait for ready signal with bounded retries;
3. retry IPC;
4. report actionable error.

No unbounded wait.

---

# 20. Autostart

Preferred:

```text
systemd --user
```

Service:

```ini
[Unit]
Description=Cachy Omarchy Overlay Shell
After=graphical-session.target

[Service]
ExecStart=%h/.local/bin/coo-shell --daemon
Restart=on-failure
RestartSec=1

[Install]
WantedBy=default.target
```

Exact Quickshell startup command belongs in `coo-shell`, not directly in the
unit.

Alternative fallback:

```text
Hyprland exec-once
```

Systemd user service is preferred because:

- lifecycle is observable;
- restart policy is explicit;
- `doctor.sh` can query it;
- no duplicated `exec-once`.

---

# 21. Installer

## 21.1 CLI

```bash
./install.sh
```

Equivalent:

```bash
./install.sh --all
```

Options:

```text
--all
--launcher
--keybindings
--no-packages
--no-service
--dry-run
--force-bindings
--verbose
--help
```

---

## 21.2 Pipeline

### Phase 0 — Environment

Detect:

```text
CachyOS / Arch family
HOME
XDG paths
Hyprland
current Hyprland config
Quickshell
systemd user
```

---

### Phase 1 — Dependencies

Required:

```text
bash
git
jq
quickshell
hyprctl
```

Potential helper dependency:

```text
ripgrep
```

Quickshell package name must be detected/documented rather than hardcoded
without verification.

Do not assume an AUR helper.

---

### Phase 2 — Backup

Backup every existing user file before mutation.

Store manifest:

```text
~/.local/state/cachy-omarchy-overlay/backups/<timestamp>/manifest.json
```

---

### Phase 3 — Program Files

Copy:

```text
shell/
bin/
```

to:

```text
~/.local/share/cachy-omarchy-overlay/
```

Create CLI symlinks.

---

### Phase 4 — Configuration

Install default configuration only when missing.

Existing project configuration should be preserved across upgrades unless a
migration explicitly modifies it.

---

### Phase 5 — Hyprland

Install project overlay.

Insert/update one managed block in root config.

---

### Phase 6 — Service

Install:

```text
coo-shell.service
```

Then:

```bash
systemctl --user daemon-reload
systemctl --user enable --now coo-shell.service
```

unless `--no-service`.

---

### Phase 7 — Validation

Check:

```text
coo-shell ping
coo-shell launcher open/close
keybinding generator
hyprctl reload
```

---

# 22. `doctor.sh`

Goal:

```text
Why is the Quattro launcher not opening?
```

Checks:

```text
[ ] supported OS family
[ ] Hyprland installed
[ ] Hyprland session detected
[ ] Quickshell installed
[ ] Quickshell version
[ ] coo-shell files
[ ] QML import validity
[ ] systemd user service installed
[ ] systemd user service running
[ ] IPC ping
[ ] launcher plugin loaded
[ ] launcher IPC
[ ] app index
[ ] command index
[ ] theme config
[ ] project Hyprland source block
[ ] SUPER+SPACE conflict
[ ] SUPER+K conflict
[ ] ~/.local/bin PATH
```

Example:

```text
Cachy Omarchy Overlay Doctor

OS               OK    CachyOS
Hyprland          OK
Quickshell         OK
coo-shell service  OK    active
IPC                OK    4ms
Launcher           OK
Applications       OK    162 entries
Commands           OK    8 entries
SUPER+SPACE        WARN  existing Walker binding
SUPER+K            OK

1 warning
```

Exit codes:

```text
0 healthy
1 warnings
2 broken
```

---

# 23. Uninstall

```bash
./uninstall.sh
```

Steps:

1. stop/disable project user service;
2. remove managed Hyprland source block;
3. remove project-owned symlinks;
4. remove project program files;
5. optionally keep user configuration;
6. reload Hyprland.

Default SHOULD preserve:

```text
~/.config/cachy-omarchy-overlay/
```

or ask/flag explicitly.

CLI:

```text
--purge
--restore-backup
--dry-run
```

MUST NOT uninstall Quickshell automatically.

---

# 24. Upstream Source Strategy

This project is inspired by and may adapt code from Omarchy.

The implementation must choose deliberately between:

```text
A. vendor selected upstream code
B. rewrite compatible components
C. hybrid
```

Preferred:

```text
hybrid
```

### Vendor

Good candidates:

- visual component structure;
- search interaction patterns;
- keyboard behavior;
- small self-contained QML components.

### Rewrite

Good candidates:

- Omarchy-specific service access;
- `$OMARCHY_PATH` handling;
- plugin registry;
- command execution tied to Omarchy;
- shell configuration;
- bar integration;
- system services.

---

# 25. Upstream Pinning

Never copy from a moving branch at install time.

Repository development should record:

```text
UPSTREAM_REPO
UPSTREAM_BRANCH
UPSTREAM_COMMIT
UPSTREAM_DATE
```

Example file:

```text
UPSTREAM.md
```

with:

```text
Repository: basecamp/omarchy
Branch: quattro
Commit: <pinned SHA>
Components reviewed:
- shell/plugins/menu/
- shell/services/...
```

Any vendored source must retain required MIT attribution.

---

# 26. Compatibility Boundary

The compatibility layer must explicitly define what API it provides.

Example:

```text
Compatibility API v1

Theme.color(name)
Theme.metric(name)

Shell.close(pluginId)
Shell.exec(command)

AppIndex.query(text)
CommandIndex.query(text)

Config.get(path)
```

Do not implicitly emulate every Omarchy singleton.

If adapted upstream code requires an API not in the boundary:

1. determine if the dependency is essential;
2. rewrite it if trivial;
3. otherwise add a documented compatibility API;
4. add a test.

---

# 27. Security

## 27.1 Commands

Launcher command entries can execute arbitrary user commands by design.

Therefore:

- commands are read only from local user-owned configuration;
- no remote command feed;
- no user search string interpolation into shell snippets;
- dangerous example commands should not be shipped.

---

## 27.2 Plugin Model

v0.1 does NOT load third-party plugins.

Reason:

Quickshell plugins execute as the user and are not sandboxed.

A plugin system may be introduced after v0.1 with explicit security warnings.

---

## 27.3 Installer

Must not use:

```bash
curl ... | sh
```

No automatic execution of remote scripts.

---

# 28. Performance Targets

The goal is subjective responsiveness rather than hard real-time guarantees.

Target after service warm-up:

```text
hotkey -> visible launcher
< 100ms desired
< 200ms acceptable for v0.1
```

Search updates:

```text
no perceptible lag for normal application counts
```

Avoid launching:

```text
find
grep over entire home
```

on every keystroke.

Cache/index where appropriate.

---

# 29. Logging

Runtime:

```text
~/.local/state/cachy-omarchy-overlay/logs/
```

Default logs should be low-volume.

Verbose/debug mode may include:

```text
IPC requests
index refresh
plugin lifecycle
config reload
```

Never log:

- clipboard data;
- search text by default;
- environment secrets.

---

# 30. Reload Model

Config changes:

```text
theme.jsonc
commands.jsonc
```

should ideally reload without restarting the desktop session.

Minimum v0.1:

```bash
coo-reload
```

performs:

```text
reload config
refresh indexes
reload/restart coo-shell if needed
```

Do not require logout.

---

# 31. Testing Strategy

## 31.1 Installer Tests

Test with isolated temporary HOME.

Required:

```text
fresh install
second install
Hyprland source insertion
source update
binding conflict
uninstall
dry-run
backup
```

---

## 31.2 Parser Tests

Hyprland fixtures:

```conf
bind =
bindd =
source =
nested source
relative source
cyclic source
```

---

## 31.3 Launcher Model Tests

Test:

```text
desktop parsing
Hidden
NoDisplay
keyword extraction
exact search
prefix search
acronym search
fuzzy ranking
duplicate apps
```

---

## 31.4 QML Smoke Test

Provide a development command such as:

```bash
./dev/run-shell.sh
```

that starts the QML host from the repository without installation.

It must support an isolated config directory.

---

# 32. Milestones

## Milestone 0 — Upstream Dependency Spike

### Goal

Determine the minimal Quattro menu dependency graph before implementing the
final port.

Tasks:

- inspect `shell/plugins/menu/`;
- list all imports;
- list all referenced shared QML singletons;
- list all shell-injected properties;
- list all external commands;
- list theme dependencies;
- list IPC dependencies;
- classify each dependency:

```text
KEEP
PORT
REWRITE
DROP
```

Output:

```text
docs/QUATTRO_PORT_MAP.md
```

Acceptance:

A developer can explain exactly why upstream `Menu.qml` cannot run alone and
what minimum compatibility surface is needed.

**This milestone must be completed before large QML implementation work.**

---

## Milestone 1 — Minimal Quickshell Host

Implement:

```text
shell.qml
IPC
systemd user service
coo-shell CLI
```

No polished launcher yet.

Acceptance:

```bash
coo-shell ping
```

works.

IPC can open/close a trivial test surface.

---

## Milestone 2 — Launcher Surface

Implement:

```text
Surface
SearchField
ResultList
keyboard navigation
theme
```

with mock data.

Acceptance:

```text
SUPER + SPACE
```

opens a fast searchable window.

---

## Milestone 3 — Application Index

Implement:

```text
.desktop discovery
parsing
icons
application execution
search ranking
```

Acceptance:

Launcher can start installed applications.

---

## Milestone 4 — Quattro Port Alignment

Use `QUATTRO_PORT_MAP.md`.

Port/adapt the relevant upstream UI/behavior.

Acceptance:

The launcher visually and behaviorally resembles Quattro while remaining free
of mandatory Omarchy runtime dependencies.

---

## Milestone 5 — Command Menu

Implement:

```text
commands.jsonc
command search
command execution
```

Do not hard-depend on Omarchy commands.

Acceptance:

Apps and commands coexist in one launcher.

---

## Milestone 6 — Keybinding Viewer

Implement:

```text
Hyprland parser
source recursion
keybinding cache
Quickshell keybinding UI
SUPER + K
```

Acceptance:

Current user's bindings are searchable.

---

## Milestone 7 — Installer Reliability

Implement:

```text
backup
idempotency
conflict detection
doctor
uninstall
dry-run
tests
```

Acceptance:

v0.1 release candidate.

---

# 33. v0.1 Acceptance Criteria

All must pass:

- [ ] Project runs on CachyOS without Omarchy installed.
- [ ] Quickshell is the UI runtime.
- [ ] `coo-shell` is a long-running user process.
- [ ] `coo-shell ping` works.
- [ ] `SUPER + SPACE` opens the launcher.
- [ ] Launcher indexes installed `.desktop` applications.
- [ ] Launcher can execute applications.
- [ ] Launcher supports project command entries.
- [ ] Launcher keyboard navigation works.
- [ ] Launcher can close with Escape.
- [ ] `SUPER + K` opens the keybinding viewer.
- [ ] Existing Hyprland keybindings are discoverable.
- [ ] Existing user Hyprland config is not replaced.
- [ ] Keybinding conflicts are detected.
- [ ] Installer is idempotent.
- [ ] Uninstall removes only project-owned integration.
- [ ] Existing Waybar remains untouched.
- [ ] Existing notification daemon remains untouched.
- [ ] Existing lock screen remains untouched.
- [ ] Omarchy is not a runtime dependency.
- [ ] Walker is not required.

---

# 34. Deferred Features

Not v0.1:

```text
clipboard overlay
emoji picker
power menu
bar
notifications
OSD
lock screen
polkit
weather
battery service
media service
plugin marketplace
automatic upstream sync
```

These may be considered only after the launcher is stable.

---

# 35. v0.2 Ideas

Potential:

```text
SUPER + V     clipboard
SUPER + .     emoji
power menu
recent applications
usage-based ranking
search providers
calculator
web search
file search
theme adapters
```

---

# 36. v0.5 Ideas

Potential:

```text
optional Quattro-style bar
CachyOS theme integration
notification overlay
OSD
multiple plugins
configuration UI
```

---

# 37. v1.0 Vision

A stable framework where CachyOS users can selectively enable Omarchy-inspired
desktop pieces:

```text
CachyOS
├── Quattro launcher       ON
├── keybinding viewer      ON
├── clipboard              optional
├── emoji                  optional
├── bar                    optional
├── notifications          optional
└── lock                   optional
```

No component should require reinstalling the operating system.

---

# 38. Architecture Decisions

## ADR-001 — Quickshell replaces Walker

Decision:

```text
Use Quickshell for the launcher.
```

Reason:

The target UX is Quattro, whose desktop surfaces are Quickshell-native.

---

## ADR-002 — Do not install full omarchy-shell

Decision:

```text
Build a minimal `coo-shell`.
```

Reason:

Avoid ownership conflicts with CachyOS desktop components.

---

## ADR-003 — Long-running host

Decision:

```text
coo-shell remains alive during the session.
```

Reason:

Fast launcher summon and warm indexes.

---

## ADR-004 — Port plugin behavior, not entire shell

Decision:

```text
Adapt only launcher dependencies.
```

Reason:

Keep the project maintainable and independent.

---

## ADR-005 — Local command definitions

Decision:

```text
Use commands.jsonc.
```

Reason:

Omarchy-specific actions may not exist on CachyOS.

---

## ADR-006 — Shared QML components

Decision:

```text
Launcher and keybinding viewer share Surface/Search/Result components.
```

Reason:

Consistent UX and less code.

---

## ADR-007 — Systemd user service

Decision:

```text
Prefer systemd --user for coo-shell.
```

Reason:

Observable and reliable lifecycle management.

---

## ADR-008 — Hyprland source overlay

Decision:

```text
Modify root Hyprland config only by one managed source block.
```

Reason:

Safe install and uninstall.

---

## ADR-009 — Upstream pin

Decision:

```text
Port from a recorded Quattro commit.
```

Reason:

Avoid silently breaking against a moving upstream branch.

---

# 39. AI Implementation Rules

Any coding agent working from this document MUST:

1. Read the entire specification before editing code.
2. Complete Milestone 0 first.
3. Do not begin by copying the whole `omarchy-shell`.
4. Do not install Omarchy.
5. Do not rewrite the user's Hyprland directory.
6. Do not replace Waybar.
7. Do not replace notifications.
8. Do not replace lock screen configuration.
9. Keep user changes reversible.
10. Keep `install.sh` thin.
11. Put reusable installer logic in `lib/`.
12. Use project-owned config paths.
13. Pin any copied upstream source to a commit.
14. Preserve applicable license notices.
15. Add a test for every parser/merge bug.
16. Run tests before claiming a milestone is done.
17. Treat Quickshell APIs as version-dependent.
18. Verify current Quickshell syntax against installed/target version.
19. Never invent missing Omarchy runtime commands on CachyOS.
20. Prefer rewriting a small dependency over importing a large unrelated shell subsystem.

---

# 40. First Agent Prompt — Dependency Map

Use this before implementation:

```text
Read SPEC.md completely.

Implement Milestone 0 only.

Study the current pinned Omarchy `quattro` implementation of `omarchy.menu`.

Produce `docs/QUATTRO_PORT_MAP.md`.

For every QML file needed by the menu:
- list imports,
- list local QML dependencies,
- list shared shell dependencies,
- list injected properties,
- list shell/IPC calls,
- list theme dependencies,
- list external commands,
- classify each dependency as KEEP, PORT, REWRITE, or DROP.

Do not implement the launcher yet.

The main question is:

"What is the smallest Quickshell runtime required to reproduce the
Omarchy Quattro launcher/menu on CachyOS without installing Omarchy?"

Record the exact upstream commit SHA used for the analysis.
```

---

# 41. Second Agent Prompt — Minimal Host

After Milestone 0:

```text
Read SPEC.md and docs/QUATTRO_PORT_MAP.md completely.

Implement Milestone 1 only.

Create the minimum long-running Quickshell host:
- shell.qml
- IPC
- coo-shell CLI
- systemd user service
- trivial test surface

Do not port the Quattro launcher yet.
Do not implement a bar, notifications, OSD, lock screen, or polkit.

Add a development run command that works from the repository without
installing into the real HOME.

Acceptance:
- coo-shell ping works
- a test surface can be opened and closed over IPC
- tests pass
```

---

# 42. Third Agent Prompt — Launcher

After the host works:

```text
Read SPEC.md and docs/QUATTRO_PORT_MAP.md.

Implement Milestones 2 through 4.

Build the launcher surface, application index, and Quattro-aligned UI.

Use the dependency classifications from QUATTRO_PORT_MAP.md.
Do not import unrelated Omarchy shell subsystems.

The result must run with Omarchy completely absent from the machine.

Acceptance:
- SUPER + SPACE opens the launcher
- installed desktop applications are searchable
- keyboard navigation works
- application launch works
- Escape closes the UI
- visual behavior is recognizably Quattro-inspired
```

---

# 43. Fourth Agent Prompt — Keybindings

```text
Read SPEC.md.

Implement Milestones 5 and 6.

Add:
- local command search
- Hyprland keybinding discovery
- recursive `source` parsing
- searchable Quickshell keybinding viewer
- SUPER + K

Do not add clipboard, emoji, bar, notifications, or power menu.

Add fixtures and tests for:
- bind
- bindd
- nested source
- cyclic source
- duplicate keybindings
- conflict detection
```

---

# 44. Definition of Done

v0.1 is done when a CachyOS user can run:

```bash
./install.sh
```

and receive:

```text
CachyOS
+
Hyprland
+
Quickshell coo-shell
```

with:

```text
SUPER + SPACE
    -> Quattro-style launcher

SUPER + K
    -> searchable hotkey dialog
```

while their existing:

```text
bar
notifications
lock screen
Hyprland config
CachyOS packages
```

remain intact.

The core principle is:

> **Port the Quattro launcher experience, not the entire Omarchy desktop.**

# Quattro Menu Port Map (Milestone 0)

Dependency map for the Omarchy Quattro menu plugin, produced before any large
QML implementation work. Milestones 2–4 read the **Verdict** column to decide
what to implement.

Verdict vocabulary (SPEC.md §32):

| Verdict | Meaning for this project |
|---|---|
| KEEP | Used as-is. An external dependency we do not own and do not replace. |
| PORT | Upstream source is copied and adapted, retaining MIT attribution. |
| REWRITE | We write our own equivalent from scratch; upstream code is not copied. |
| DROP | Not carried across in any form. Nothing replaces it. |

---

## 1. Provenance

| Field | Value |
|---|---|
| Upstream repo | `basecamp/omarchy` (https://github.com/basecamp/omarchy) |
| Branch | `quattro` |
| Commit | `b724f7615630d7a7aca76dce070d469f43a3bfec` |
| Vendored at | `vendor/omarchy/` (git-ignored, read-only; see `UPSTREAM.md`) |
| License | MIT — Copyright (c) David Heinemeier Hansson |
| Analysis date | 2026-08-15 |
| Analysis host | CachyOS, Quickshell 0.3.0-2.1 (Arch package), Hyprland session |

Commands used to derive this map (all run from `vendor/omarchy/`):

```bash
wc -l shell/plugins/menu/* shell/Commons/*.qml shell/Ui/{BorderSurface,ConfirmDialog,PointerMoveGate,BorderOverlay}.qml shell/shell.qml
grep -nE '^import ' shell/plugins/menu/Menu.qml
awk '$1=="singleton"{print $2}' shell/Commons/qmldir
awk 'NF==3 && $3 ~ /\.qml$/ {print $1}' shell/Ui/qmldir

# singleton usage, per member
for f in Util Style Color Border; do
  grep -oE "\b${f}\.[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)?" shell/plugins/menu/Menu.qml | sort | uniq -c | sort -rn
  grep -oE "\b${f}\." shell/plugins/menu/Menu.qml | wc -l
done

# qs.Ui components actually instantiated
while read -r c; do
  grep -qE "^[[:space:]]*$c[[:space:]]*\{" shell/plugins/menu/Menu.qml && echo "$c"
done < <(awk 'NF==3 && $3 ~ /\.qml$/ {print $1}' shell/Ui/qmldir)

# host coupling
grep -nE "root\.shell|\bmanifest\b|omarchyPath" shell/plugins/menu/Menu.qml
grep -oE "appLibrary\.[A-Za-z]+" shell/plugins/menu/Menu.qml | sort | uniq -c

# external commands
grep -nE '"bash"|execDetached|omarchy[a-z-]*|powerprofilesctl|pacman|hyprctl|fc-match' \
  shell/plugins/menu/Menu.qml shell/plugins/menu/MenuModel.js shell/plugins/menu/BarWidget.qml shell/Commons/Style.qml

# standalone-load proof (see §2.1)
qs -p shell/plugins/menu/Menu.qml
```

Command existence on this machine was checked with `command -v <name>`; results
are recorded verbatim in §4.

Measured file sizes:

| File | Lines |
|---|---|
| shell/plugins/menu/Menu.qml | 1420 |
| shell/plugins/menu/MenuModel.js | 510 |
| shell/plugins/menu/BarWidget.qml | 24 |
| shell/plugins/menu/manifest.json | 23 |
| shell/Commons/Style.qml | 515 |
| shell/Commons/Color.qml | 254 |
| shell/Commons/Border.qml | 242 |
| shell/Commons/Util.qml | 146 |
| shell/Commons/BorderGeometry.js | 373 |
| shell/Ui/ConfirmDialog.qml | 131 |
| shell/Ui/PointerMoveGate.qml | 54 |
| shell/Ui/BorderOverlay.qml | 54 |
| shell/Ui/BorderSurface.qml | 40 |
| shell/shell.qml | 1031 |
| **Total examined** | **4817** |

---

## 2. Why upstream `Menu.qml` cannot run standalone

`Menu.qml` is not an application. It is a 1420-line `Item` designed to be
instantiated by `shell/shell.qml` inside a running `omarchy-shell` process,
which finishes wiring it up after `Loader.onLoaded`. Five distinct couplings
prevent it from loading or functioning on its own, and each is named concretely
below.

### 2.1 Two module URIs that only resolve from the host's config root

`Menu.qml` lines 1–7 import:

```qml
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "MenuModel.js" as MenuModel
```

`qs.Commons` and `qs.Ui` are **not** Quickshell or Qt modules. They are
directory modules declared by `shell/Commons/qmldir` and `shell/Ui/qmldir`:

```
module qs.Commons
singleton Border 1.0 Border.qml
singleton Color 1.0 Color.qml
singleton Style 1.0 Style.qml
singleton Util 1.0 Util.qml
```

Quickshell maps the `qs.*` namespace onto **the config root directory it was
launched with**. Upstream launches with the config root at
`$OMARCHY_PATH/shell`, so `qs.Commons` resolves to `$OMARCHY_PATH/shell/Commons`
and `qs.Ui` to `$OMARCHY_PATH/shell/Ui`. Launch `Menu.qml` as its own root and
the same URIs point at directories beside `Menu.qml` that do not exist.
Verified on this machine:

```
$ qs -p shell/plugins/menu/Menu.qml
WARN quickshell.qmlscanner: Ignoring unresolvable import
  ".../shell/plugins/menu/Commons" from ".../shell/plugins/menu/Menu.qml"
WARN quickshell.qmlscanner: Ignoring unresolvable import
  ".../shell/plugins/menu/Ui" from ".../shell/plugins/menu/Menu.qml"
ERROR: Failed to load configuration
ERROR:   caused by @Menu.qml[6:1]: module "qs.Ui" is not installed
ERROR:   caused by @Menu.qml[5:1]: module "qs.Commons" is not installed
```

This is a hard load failure at line 5, before a single property is evaluated.

**What "singleton" means for a consumer that tries a relative-path import
instead.** The obvious workaround — replacing `import qs.Commons` with
`import "../../Commons"` — does not work, and its failure mode is the
dangerous kind:

- `Border.qml`, `Color.qml`, `Style.qml` and `Util.qml` each begin with
  `pragma Singleton`. A `pragma Singleton` type is only usable as a singleton
  when a `qmldir` declares it with the `singleton` keyword under a module URI.
  A bare relative-directory import gives the consumer the *component*, not the
  engine-managed instance, so `Style.space(4)` has no object to resolve against.
- Where a relative import does yield something usable, the QML engine treats
  each import path as its own type registration. Two files importing the same
  directory by relative path get **separate instances** with separate state.
  For `Color` and `Style`, whose entire content is loaded asynchronously from
  disk (`FileView` on `colors.toml` / `shell.toml`, `Process` on `hyprctl`),
  a second instance means a second, never-populated copy: every colour reads
  its hardcoded fallback and every metric its default. Nothing throws.

Upstream states this explicitly at `shell/shell.qml:14-17`, and it is the single
most load-bearing sentence in the tree for our own design:

> ```qml
> // Shared service instances. Plugins receive these via property injection
> // rather than re-importing them as singletons — relative-path imports do
> // not share singleton state, which silently leaves consumers with their
> // own empty copies.
> property PluginRegistry pluginRegistry: PluginRegistry { }
> property BarWidgetRegistry barWidgetRegistry: BarWidgetRegistry { }
> property AppLibrary appLibrary: AppLibrary { }
> ```

**Consequence for Milestones 1 and 2:** our shared services (theme, app index,
command runner, config) must be reachable by exactly one of two mechanisms, and
never by relative path:

1. as `pragma Singleton` types declared in a `qmldir` under a real module URI
   that our host puts on the import path (the mechanism `qs.Commons` uses); or
2. as instances created once in our shell root and handed to consumers by
   **property injection** (the mechanism upstream uses for `appLibrary`).

Mixing the two — importing a singleton by relative path anywhere in our tree —
produces a menu whose colours and metrics are silently default and whose app
list is silently empty, with no error to debug.

### 2.2 Three properties the host injects after load

`Menu.qml:12-15`:

```qml
// Injected by omarchy-shell when this plugin is summoned.
property string omarchyPath: Quickshell.env("OMARCHY_PATH")
property var shell: null
property var manifest: null
```

The host assigns all three in `shell/shell.qml:629-631`, duck-typed, inside the
panel `Loader`'s `onLoaded`:

```qml
if ("omarchyPath" in item) item.omarchyPath = shell.omarchyPath
if ("shell" in item) item.shell = shell
if ("manifest" in item) item.manifest = panelEntry.manifest
```

What each is actually worth, measured:

- **`omarchyPath`** — one consumer, `Menu.qml:50`:
  `defaultMenuPath: omarchyPath + "/default/omarchy/omarchy-menu.jsonc"`.
  Its default, `Quickshell.env("OMARCHY_PATH")`, is empty on this machine
  (`OMARCHY_PATH` is unset — confirmed in §4), so the `FileView` at
  `Menu.qml:922` watches `/default/omarchy/omarchy-menu.jsonc`, never loads,
  and `rowsLoaded` stays `false`. The `PanelWindow` at `Menu.qml:1017` is
  `visible: root.opened && root.rowsLoaded`, so even a successfully loaded menu
  would never draw. The file it points at is not even part of our vendored
  sparse checkout (`shell bin LICENSE`), because it lives under `default/`.
- **`shell`** — one consumer, `Menu.qml:80`:
  `readonly property var appLibrary: root.shell ? root.shell.appLibrary : null`.
  The host object itself is never called; `shell` exists purely as a handle to
  the shared `AppLibrary` service. Seven methods and one signal are used:
  `sortedEntries("")`, `entryName(entry)`, `entrySubtext(entry)`,
  `iconSource(icon)`, `launch(appId, label)`, `remove(appId, label)`,
  `refreshIcons()`, and `onAppsChanged` (`Menu.qml:912-917`). With `shell` null,
  `appLibrary` is null: the Apps submenu is empty, app rows have no icons, and
  Enter on an app row does nothing.
- **`manifest`** — declared at line 15 and **read nowhere else in the file**
  (`grep -nE "\bmanifest\b" Menu.qml` returns only line 15). The host injects it
  for uniformity across plugin kinds. It is dead weight for this plugin.

### 2.3 A lifecycle only the host drives

`Menu.qml` has no `Component.onCompleted` that opens anything and no IPC handler
of its own. It is opened entirely from outside, through four host-called
functions:

| Line | Function | Called by |
|---|---|---|
| 21 | `open(payloadJson)` | `shell.qml:548` inside `deliverIfLoaded()`, after `summon()` queues the payload |
| 34 | `close()` | `shell.qml:489` `invokeIfLoaded(id, "close", null)`, from `hide()` |
| 38 | `refresh()` | `shell.qml:1027` `call(id, method, arg)` → `callIfLoaded()` |
| 44 | `ping()` | same |

The host also reads state back: `shell.qml:505` inspects `loader.item.opened` to
implement `isPluginOpen()`, which `toggle()` (`shell.qml:510`) is built on. So
the contract is bidirectional — the plugin must expose `opened` as a property
the host can poll, and setting `opened = false` from inside (`cancel()`,
`applySelected()`, `applyDmenuSelection()`) is how the menu tells the host it
closed itself.

The payload string that reaches `open()` shapes the whole session: `menu` /
`initialMenu` selects the starting route, and `mode: "select" | "input"` turns
the menu into a dmenu replacement with `prompt`, `options`, `selectionFile`,
`doneFile`, `width` and `maxHeight` (`Menu.qml:819-839`). Without a host that
formats that JSON, the dmenu half of the plugin is unreachable.

The transport behind it is Omarchy-specific and equally absent: `bin/omarchy-shell`
requires `$OMARCHY_PATH` to be set and `$OMARCHY_PATH/shell/shell.qml` to exist,
then calls `qs ipc -n -p "$OMARCHY_PATH/shell" call -- "$@"` against the
`IpcHandler { target: "shell" }` at `shell.qml:872`.

### 2.4 A theme surface that reads Omarchy's state directory

`Color.qml:17` resolves every colour through
`~/.local/state/omarchy/current/theme`, reading `colors.toml` and `shell.toml`
from it plus `~/.config/omarchy/shell.toml`. `Style.qml` reads the same
`shell.toml` dictionary for typography and spacing and shells out to
`hyprctl -j getoption decoration:rounding` / `general:gaps_out` and to
`fc-match`. On a machine without Omarchy none of those files exist, so all 60
`Style.` and 7 `Color.menu.*` references in `Menu.qml` fall back to hardcoded
defaults — a functioning but entirely untheme-able menu, wired to a config
format we have no reason to adopt.

### 2.5 External commands that do not exist on CachyOS

`Menu.qml` embeds bash for its two dynamic providers and for the guard batch;
`MenuModel.js` generates a `pacman`-based guard script. Nine `omarchy-*`
commands are referenced across the plugin, and none of them exist on this
machine (§4). They are not fatal — a provider script whose commands are missing
simply yields no rows — but any port that leaves them in ships menu entries
that silently do nothing.

### 2.6 Summary of the minimum needed to make it run

To load at all: a config root that resolves `qs.Commons` and `qs.Ui` (or edited
imports plus replacement singletons/components). To render: a populated theme
source and a readable menu definition file. To open: a host that injects
`shell` (for `appLibrary`), calls `open(payloadJson)`, calls `close()`, and
polls `opened`. Everything else is optional. The concrete API list is §5.

---

## 3. Dependency table

| Dependency | Kind | Used for | Verdict |
|---|---|---|---|
| `Quickshell` | QML module | `Quickshell.env` (2 sites: `OMARCHY_PATH`, `HOME`), `PanelWindow` (line 1017), `Quickshell.execDetached` via `Util` | KEEP |
| `Quickshell.Io` | QML module | `Process` ×3 (881, 899, 976), `SplitParser` ×2, `FileView` ×2 (922, 931). No `IpcHandler` in this file | KEEP |
| `Quickshell.Wayland` | QML module | `WlrLayershell.namespace/layer/keyboardFocus` (1022-1024), `WlrLayer.Overlay`, `WlrKeyboardFocus.Exclusive` | KEEP |
| `QtQuick` | QML module | `Item`, `Rectangle`, `Text`, `Image`, `Column`, `Row`, `ListView`, `ListModel`, `MouseArea`, `Connections`, `Gradient`, `Qt.callLater` | KEEP |
| `qs.Commons` | upstream module URI | Directory module resolving to `<config root>/Commons`; supplies the 4 singletons below. We provide an equivalent module under our own URI, not this one | REWRITE |
| `qs.Ui` | upstream module URI | Directory module resolving to `<config root>/Ui`; 32 components declared, exactly 3 instantiated by `Menu.qml` (rows below). We take the 3, not the module | PORT |
| `"MenuModel.js"` | local JS library | 510 lines, 26 call sites: JSONC strip and parse, item normalization, defaults+user merge, provider and app row merge, route and alias resolution, tree walks, search matching and scoring, row projection, guard script generation | PORT |
| `Style` | upstream singleton (`qs.Commons`) | 60 references over 17 distinct tokens: `space(px)` ×30, `gapsOut` ×7, `cornerRadius`, `spacing.{xs,md,hairline,panelPadding,rowPaddingX,controlPaddingY}`, `font.{menuFamily,caption,bodySmall,body,title,heading,displayLarge,iconLarge}`. Upstream backs these with `shell.toml`, `hyprctl getoption` and `fc-match` | REWRITE |
| `Color` | upstream singleton (`qs.Commons`) | 7 references, all `Color.menu.*`: `background`, `text`, `border`, `scrim`, `selectedBackground`, `selectedText`, `selectedBorder`. Upstream backs these with `~/.local/state/omarchy/current/theme/{colors.toml,shell.toml}` | REWRITE |
| `Util` | upstream singleton (`qs.Commons`) | 12 references over 5 functions: `shellQuote` ×6, `alpha` ×3, `execDetached`, `editsFilter`, `editedFilter`. Pure functions, no Omarchy coupling; ~35 of its 146 lines are used | PORT |
| `Border` | upstream singleton (`qs.Commons`) | 5 references over 4 functions: `surfaceSpec` ×2, `left`, `right`, `none`. Backed by 242 lines plus `BorderGeometry.js` (373 lines) of `shell.toml` border-token parsing, gradients and per-side widths, for what the menu uses as one uniform width and one colour | DROP |
| `BorderSurface` | upstream `qs.Ui` component | 40 lines; the menu card (1055) and every row delegate (1199). Its whole job is turning a `Border` spec into `Rectangle.border` or a `BorderOverlay` ring; dropping `Border` removes its reason to exist | REWRITE |
| `ConfirmDialog` | upstream `qs.Ui` component | 131 lines; the uninstall-app confirmation at 1119, including its `handleKey(event)` two-button keyboard model. Self-contained apart from theme lookups | PORT |
| `PointerMoveGate` | upstream `qs.Ui` component | 54 lines, pure QtQuick, zero dependencies; filters synthetic hover events from delegates moving under a stationary pointer (907, `disarmPointer`, `selectFromPointer`) | PORT |
| `omarchyPath` | injected property | Sole consumer is `defaultMenuPath` (line 50), pointing into `$OMARCHY_PATH/default/omarchy/` | DROP |
| `shell` | injected property | Sole consumer is `root.shell.appLibrary` (line 80). The host object itself is never called | REWRITE |
| `manifest` | injected property | Declared at line 15, read nowhere. Injected by the host for uniformity across plugin kinds | DROP |
| `appLibrary` | injected shared service | Reached through `shell`; 7 methods (`sortedEntries`, `entryName`, `entrySubtext`, `iconSource`, `launch`, `remove`, `refreshIcons`) and the `appsChanged` signal, across 10 lines | REWRITE |
| `open(payloadJson)` | host-called lifecycle | Entry point for every summon; parses the payload into route mode or dmenu mode. Contract must survive the port (SPEC.md §6) | KEEP |
| `close()` | host-called lifecycle | Host-driven hide; delegates to `cancel()`, which also answers a pending dmenu request with a null selection | KEEP |
| `refresh()` | host-called lifecycle | Reloads both JSONC sources; reachable upstream only via `omarchy-shell shell call` | KEEP |
| `ping()` | host-called lifecycle | Liveness probe returning `"ok"` | KEEP |
| `opened` | host-read property | The host polls it (`shell.qml:505`) to implement `isPluginOpen` and therefore `toggle` | KEEP |
| `manifest.json` | plugin metadata file | `id: omarchy.menu`, `kinds: ["menu","bar-widget"]`, `keepLoaded: true`, `entryPoints.menu: Menu.qml`. Consumed by the upstream plugin registry, which v0.1 does not have (SPEC.md §27.2 ships no plugin system) | DROP |
| `BarWidget.qml` | plugin entry point | 24 lines; a bar button that shells out to `omarchy-shell shell toggle` and `xdg-terminal-exec`. We ship no bar | DROP |
| `omarchy-shell` | IPC transport | `bin/omarchy-shell`; requires `$OMARCHY_PATH`, wraps `qs ipc -n -p "$OMARCHY_PATH/shell" call`. Our own launcher CLI replaces it | REWRITE |
| `IpcHandler` | Quickshell type | `shell.qml:872`, `target: "shell"`, exposing `summon`/`hide`/`toggle`/`call`. The mechanism is fine; the target surface is ours to define | KEEP |
| `colors.toml` | theme input | `~/.local/state/omarchy/current/theme/colors.toml`; foundational palette read by `Color.qml` | DROP |
| `shell.toml` | theme input | `~/.local/state/omarchy/current/theme/shell.toml` plus `~/.config/omarchy/shell.toml`; per-surface colour roles, spacing scale, font scale, border tokens | DROP |
| `shell.json` | host config | `$OMARCHY_PATH/config/omarchy/shell.json` and `~/.config/omarchy/shell.json`; plugin enablement and bar layout, read by `shell.qml`, not by the menu | DROP |
| `omarchy-menu.jsonc` | menu definition | `$OMARCHY_PATH/default/omarchy/omarchy-menu.jsonc` merged with `~/.config/omarchy/extensions/omarchy-menu.jsonc`. The authoring format is worth keeping; the file and its Omarchy-specific actions are not | REWRITE |

### 3.1 Verdicts changed from the plan's starter table

| Row | Starter | Final | Why |
|---|---|---|---|
| manifest (injected property) | REWRITE | DROP | `grep -nE "\bmanifest\b" Menu.qml` returns line 15 only — the declaration. Nothing reads it, so there is nothing to rewrite. Our host may still inject it harmlessly, but no milestone needs to build anything for it. |

Everything else in the starter table survived verification. Three "Used for"
descriptions were wrong and are corrected above:

- `Quickshell.Io` was described as supplying `IpcHandler`. `Menu.qml` contains
  no `IpcHandler`; the only one in the tree is `shell.qml:872`. The menu uses
  `Process`, `SplitParser` and `FileView` from that module.
- `Util` was described as providing `decodeBase64`. `Menu.qml` never calls it
  (it calls `shellQuote`, `alpha`, `execDetached`, `editsFilter`,
  `editedFilter`).
- `omarchy-menu` was listed as an external command invoked at `Menu.qml:1022`.
  Line 1022 is `WlrLayershell.namespace: "omarchy-menu"` — a Wayland layer-shell
  namespace string, not a command. `Menu.qml` never invokes `omarchy-menu`. The
  command inventory in §4 reflects the commands actually referenced.

`Border` keeps its DROP verdict, which deserves a note because the singleton is
genuinely referenced 5 times. Dropping it means inlining those 5 call sites:
`Border.surfaceSpec("menu","border",…)` and `("menu","selected-border",…)`
become a plain colour plus width pair; `Border.left`/`Border.right` become the
row's reserved left/right inset (0 unless we grow a selected-row border);
`Border.none()` becomes width 0. That is roughly 10 lines of replacement against
615 lines of upstream border-token machinery whose only input is a `shell.toml`
we are not adopting — exactly the "rewrite a small dependency rather than import
a large unrelated subsystem" trade the project constraints call for.
`BorderSurface` follows it to REWRITE for the same reason: 40 lines that exist
only to consume a `Border` spec, and which pull in `BorderOverlay` (54 lines)
behind them.

---

## 4. External command inventory

Every command the plugin can execute, with its presence on this machine.
Existence was checked with `command -v`; the unedited output is below.
Per SPEC.md §39.19, nothing here is invented: where CachyOS has no analogue, the
verdict is DROP rather than a hypothetical `coo-*` command.

```
$ for c in bash awk pacman hyprctl fc-match powerprofilesctl fc-list \
    xdg-settings xdg-mime resolvectl xdg-terminal-exec omarchy omarchy-shell \
    omarchy-font-current omarchy-font-list omarchy-font-set \
    omarchy-powerprofiles-list omarchy-powerprofiles-set \
    omarchy-channel-current omarchy-default-agent omarchy-default-browser \
    omarchy-default-editor omarchy-default-terminal omarchy-dns omarchy-menu \
    omarchy-cmd-present omarchy-pkg-present; do
    if p=$(command -v "$c" 2>/dev/null); then printf "%-26s %s\n" "$c" "$p"
    else printf "%-26s NOT FOUND\n" "$c"; fi
  done
bash                       /usr/bin/bash
awk                        /usr/bin/awk
pacman                     /usr/bin/pacman
hyprctl                    /usr/bin/hyprctl
fc-match                   /usr/bin/fc-match
powerprofilesctl           /usr/bin/powerprofilesctl
fc-list                    /usr/bin/fc-list
xdg-settings               /usr/bin/xdg-settings
xdg-mime                   /usr/bin/xdg-mime
resolvectl                 /usr/bin/resolvectl
xdg-terminal-exec          NOT FOUND
omarchy                    NOT FOUND
omarchy-shell              NOT FOUND
omarchy-font-current       NOT FOUND
omarchy-font-list          NOT FOUND
omarchy-font-set           NOT FOUND
omarchy-powerprofiles-list NOT FOUND
omarchy-powerprofiles-set  NOT FOUND
omarchy-channel-current    NOT FOUND
omarchy-default-agent      NOT FOUND
omarchy-default-browser    NOT FOUND
omarchy-default-editor     NOT FOUND
omarchy-default-terminal   NOT FOUND
omarchy-dns                NOT FOUND
omarchy-menu               NOT FOUND
omarchy-cmd-present        NOT FOUND
omarchy-pkg-present        NOT FOUND

$ echo "OMARCHY_PATH=[${OMARCHY_PATH:-<unset>}]"
OMARCHY_PATH=[<unset>]

$ powerprofilesctl list
Traceback (most recent call last):
  File "/usr/bin/powerprofilesctl", line 8, in <module>
    from gi.repository import Gio, GLib
ModuleNotFoundError: No module named 'gi'
```

| Command | Exists on CachyOS | Referenced by | Replacement on CachyOS | Verdict |
|---|---|---|---|---|
| `bash` | yes, `/usr/bin/bash` | `Menu.qml:130,132` (dmenu result files), `346` (provider scripts), `972` (guard batch), and `Util.execDetached` (`bash -lc`) | none needed; it is the execution substrate for every action | KEEP |
| `awk` | yes, `/usr/bin/awk` | `MenuModel.js:413` inside the generated guard script, parsing `pacman -Qi` Provides lines | none needed | KEEP |
| `pacman` | yes, `/usr/bin/pacman` | `MenuModel.js:412,418` — `pacman -Qq` and `pacman -Qi` build the installed-package set for `when:` and `checked:` guards | none needed; CachyOS is Arch-based and `pacman -Q` behaves identically | KEEP |
| `hyprctl` | yes, `/usr/bin/hyprctl` | `Style.qml:444,453` — `hyprctl -j getoption decoration:rounding` and `general:gaps_out` | none needed, but the call belongs in our theme layer, not copied from `Style.qml` | REWRITE |
| `fc-match` | yes, `/usr/bin/fc-match` | `Style.qml:469` — `fc-match -f %{family[0]} monospace` resolves the fontconfig alias behind `Style.font.menuFamily` | none needed; same call, our own theme layer | REWRITE |
| `powerprofilesctl` | binary present at `/usr/bin/powerprofilesctl`, but it failed to run here with `ModuleNotFoundError: No module named 'gi'` | `Menu.qml:277` — `powerprofilesctl get` marks the current profile in the power-profiles provider | `powerprofilesctl get` and `powerprofilesctl set <p>` are the upstream-agnostic API and would replace the two `omarchy-powerprofiles-*` wrappers, but only once the `python-gobject` dependency is present. Treat the whole power-profiles provider as optional and hide it when the command fails | REWRITE |
| `xdg-terminal-exec` | no | `BarWidget.qml:20`, right-click on the bar button | none; we ship no bar, so the call site disappears with `BarWidget.qml` | DROP |
| `omarchy-shell` | no | `BarWidget.qml:21` (`omarchy-shell shell toggle omarchy.menu`), and the documented summon path in `Menu.qml:18,845` | our own launcher CLI over `qs ipc call` against our own `IpcHandler` target | REWRITE |
| `omarchy-font-current` | no | `Menu.qml:271`, marks the active font in the fonts provider | `fc-match -f '%{family[0]}' monospace` (present) reports the resolved family, which is the same fact `Style.qml` already reads | REWRITE |
| `omarchy-font-list` | no | `Menu.qml:271`, enumerates installed fonts | `fc-list` is present (`/usr/bin/fc-list`) and enumerates families directly | REWRITE |
| `omarchy-font-set` | no | `Menu.qml:274`, the action each font row runs | Omarchy's font-set rewrites `~/.config/fontconfig/fonts.conf` and restarts its shell. That is a system-configuration behaviour with no CachyOS analogue and is out of scope for a launcher | DROP |
| `omarchy-powerprofiles-list` | no | `Menu.qml:277`, enumerates profiles | `powerprofilesctl list`, subject to the `gi` caveat above | REWRITE |
| `omarchy-powerprofiles-set` | no | `Menu.qml:279`, the action each profile row runs (`omarchy-powerprofiles-set autodetect <p>`) | `powerprofilesctl set <p>`; the `autodetect` argument is Omarchy-internal and has no analogue | REWRITE |
| `omarchy-channel-current` | no | `MenuModel.js:384`, a `GUARD_READERS` entry captured once per guard batch | reports which Omarchy release channel is active. No CachyOS analogue and no meaning outside Omarchy | DROP |
| `omarchy-default-agent` | no | `MenuModel.js:385`, `GUARD_READERS` | no analogue; the concept is Omarchy's default-AI-agent setting | DROP |
| `omarchy-default-browser` | no | `MenuModel.js:386`, `GUARD_READERS` | `xdg-settings get default-web-browser` is present and answers the same question, if we keep browser rows at all | REWRITE |
| `omarchy-default-editor` | no | `MenuModel.js:387`, `GUARD_READERS` | `$EDITOR` / `xdg-mime query default text/plain` is present; only worth wiring if our menu data ships editor rows | REWRITE |
| `omarchy-default-terminal` | no | `MenuModel.js:388`, `GUARD_READERS` | `xdg-terminal-exec` is absent here, and CachyOS has no single canonical default-terminal query. Drop the rows rather than invent one | DROP |
| `omarchy-dns` | no | `MenuModel.js:389`, `GUARD_READERS` | `resolvectl status` is present but reports something structurally different from Omarchy's DNS-provider setting; the menu rows behind it are Omarchy DNS management | DROP |
| `omarchy-cmd-present` | no | `MenuModel.js:421-422`, referenced by `when:` expressions in the menu data | **none required.** The generated guard script defines `omarchy-cmd-present` / `omarchy-cmd-missing` as bash functions inside itself (they wrap `command -v`), so guards using them evaluate correctly on a machine with no `omarchy-*` command installed. Keep the shim, rename it | PORT |
| `omarchy-pkg-present` | no | `MenuModel.js:419-420`, same | same: defined inside the script over the `pacman -Qq`/`-Qi` set, so it works on CachyOS unchanged. Keep the shim, rename it | PORT |
| `omarchy-menu` | no | **not referenced.** Recorded here only to correct the plan's starter note: `Menu.qml:1022` is `WlrLayershell.namespace: "omarchy-menu"`, a layer-shell namespace, not a command | n/a | DROP |

Two findings here matter beyond the table:

1. **The guard mechanism survives the port intact.** The expensive, subtle part
   of `MenuModel.guardScript()` — batching every `when:` and `checked:` into one
   bash run, shadowing the presence helpers with in-script functions, and
   pre-capturing the `GUARD_READERS` values — depends only on `bash`, `awk` and
   `pacman`, all present. Only the six `GUARD_READERS` names are Omarchy-bound,
   and they are a plain list at `MenuModel.js:383-390` that we replace wholesale.
2. **Menu actions are data, not code.** Every other `omarchy-*` command a user
   would meet lives in `omarchy-menu.jsonc`, which is not vendored (our sparse
   checkout is `shell bin LICENSE`; the file is under `default/`). Our menu
   definition is authored fresh, so the port carries no Omarchy command strings
   at all beyond the two providers above.

---

## 5. Minimum compatibility surface

Against SPEC.md §26 Compatibility API v1. Verdict column reads: KEEP = §26's
entry is needed and its shape is adequate; REWRITE = needed but §26's shape must
change; DROP = the ported menu does not need it.

| §26 entry | Needed by the ported menu | Detail | Verdict |
|---|---|---|---|
| `Theme.color(name)` | yes | 11 names: the 7 `menu.*` roles `Menu.qml` reads (`background`, `text`, `border`, `scrim`, `selectedBackground`, `selectedText`, `selectedBorder`) plus `foreground`, `background`, `accent` and `urgent`, which `ConfirmDialog` reads for its destructive button | KEEP |
| `Theme.metric(name)` | yes | 17 tokens, of which 16 are plain lookups: `gapsOut`, `cornerRadius`, `spacing.xs`, `spacing.md`, `spacing.hairline`, `spacing.panelPadding`, `spacing.rowPaddingX`, `spacing.controlPaddingY`, `font.menuFamily`, `font.caption`, `font.bodySmall`, `font.body`, `font.title`, `font.heading`, `font.displayLarge`, `font.iconLarge`, plus a border width for `ConfirmDialog` | KEEP |
| `Shell.close(pluginId)` | partly | `Menu.qml` never calls it — it closes itself by setting `opened = false`, and the host notices by polling `opened` (`shell.qml:505`). The host still needs the inverse direction: a `close()` call into the menu. Keep the entry, and pair it with a readable `opened` | REWRITE |
| `Shell.exec(command)` | yes | 4 sites: `Util.execDetached` for every action row (`Menu.qml:141`) and the two dmenu result writes (`130`, `132`). Fire-and-forget with no output is the correct shape for these | KEEP |
| `AppIndex.query(text)` | yes, but insufficient alone | The Apps submenu needs `sortedEntries("")` plus, per entry, `id`, `icon`, `keywords`, `entryName`, `entrySubtext`; and beyond querying it needs `iconSource(icon)`, `launch(appId,label)`, `remove(appId,label)`, `refreshIcons()` and an `appsChanged` signal | REWRITE |
| `CommandIndex.query(text)` | no | The menu is its own index. Items come from the merged JSONC tree and all matching, scoring and ordering happen inside `MenuModel.js` (`matchesQuery`, `searchScore`, `termInSearchWords`, `descriptionTextMatches`). A separate command index is a launcher concern, not a menu one | DROP |
| `Config.get(path)` | yes | The menu's own configurable inputs are few: the menu definition path, the default font family, and (if we keep it) the user extension path | KEEP |

### 5.1 What the menu needs that §26 does not cover

Six gaps. Each is a documented compatibility API to add per SPEC.md §26's
"otherwise add a documented compatibility API; add a test":

1. **`Theme.space(px)` — a scaling function, not a name.** 30 of the 60 `Style.`
   references are `Style.space(n)` with 20 distinct literals, which upstream
   multiplies by a spacing scale. A `metric(name)` lookup cannot express it.
2. **A capturing command runner.** Three `Process` blocks need something
   `Shell.exec` does not give: streamed stdout (`SplitParser`), an exit code,
   and the ability to be superseded. `providerProc` (`881`) collects provider
   rows; `guardProc` (`976`) collects `<id>:<w|c>:<0|1>` lines and distinguishes
   a nonzero exit from a signal death (`987`) to avoid accepting a half-read
   batch; `resultProc` (`899`) only needs completion. Call it `Shell.run(cmd)`
   with an output signal and an exit signal, distinct from `Shell.exec`.
3. **A watched configuration source.** `Config.get(path)` is a point read. The
   menu uses two `FileView`s with `watchChanges: true` (`922`, `931`) so edits to
   the menu definition apply live, and a `onLoadFailed` path so a missing user
   extension is normal rather than an error. Our config API needs a
   change signal and a tolerated-absence semantic.
4. **`AppIndex` beyond query**, as itemized in the table above: icon resolution,
   launch, uninstall, an icon refresh, and a change signal. Uninstall in
   particular drives real UI (`ConfirmDialog` at `1119`, `Delete` key at `1081`)
   and must either be provided or removed deliberately.
5. **The plugin lifecycle contract itself.** `open(payloadJson)`, `close()`,
   `refresh()`, `ping()`, and a host-readable `opened`, plus the payload schema
   (`menu`/`initialMenu`, `fontFamily`, and the dmenu set `mode`, `prompt`,
   `options`, `selectionFile`, `doneFile`, `width`, `maxHeight`). §26 describes
   services the plugin calls, not the calls the host makes into it.
6. **A surface/border primitive.** Dropping `Border` and rewriting
   `BorderSurface` leaves the menu card and row delegates needing a small,
   explicit contract: colour, radius, uniform border width, and content insets
   (`contentTopInset` and its three siblings are read at `Menu.qml:1141-1144`).

---

## 6. Port budget

Upstream lines examined: 4817. Bucketed by verdict:

| Bucket | Upstream lines | Detail |
|---|---|---|
| PORT (copied and adapted, MIT attribution required) | ~2150 | `Menu.qml` 1420, `MenuModel.js` 510, `ConfirmDialog.qml` 131, `PointerMoveGate.qml` 54, `Util.qml` used subset ~35 |
| REWRITE (upstream replaced by our own code) | ~989 | `Style.qml` 515, `Color.qml` 254, `BorderSurface.qml` 40, and the ~180-line host slice of `shell.qml` (injection at 214-223 and 623-652; `summon`/`hide`/`isPluginOpen`/`toggle`/`deliverIfLoaded`/`invokeIfLoaded`/`callIfLoaded` at 440-579) |
| DROP (not carried in any form) | ~1678 | `Border.qml` 242, `BorderGeometry.js` 373, `BorderOverlay.qml` 54, unused `Util.qml` remainder ~111, `BarWidget.qml` 24, `manifest.json` 23, remaining ~851 lines of `shell.qml` (plugin registry, bar hosting, service loader, config persistence, image-selector IPC) |

Estimated new code to write for the REWRITE bucket: **~575 lines**, roughly
80 for the metric/spacing surface, 90 for the colour surface, 25 for the surface
primitive, 150 for the app index, 200 for the host and its IPC target, and 30
for config and command running.

Estimated edit surface inside the PORT bucket — the lines that must actually
change while adapting: **~90 lines of `Menu.qml`** (60 lines touching
`Style.`/`Color.`/`Border.`, 10 touching `appLibrary`, ~7 for the import block
and injected properties, ~13 for the two provider definitions), and **~10 lines
of `MenuModel.js`** (the `GUARD_READERS` list at 383-390 and the two shim names).
`ConfirmDialog.qml` needs its ~12 theme lookups retargeted; `PointerMoveGate.qml`
needs nothing but a new header.

Sizing conclusion for Milestones 2–4: the menu port is dominated by a single
large file that transplants nearly intact, and the real work is the ~575 lines
of host and compatibility surface underneath it.

---

## 7. Attribution

Upstream is MIT licensed, Copyright (c) David Heinemeier Hansson (see
`vendor/omarchy/LICENSE` and `UPSTREAM.md`). Every file classified **PORT** in
§3 carries upstream code and must retain MIT attribution in the ported file's
header, naming the upstream path and the pinned commit
`b724f7615630d7a7aca76dce070d469f43a3bfec`. Files classified **REWRITE** are
written from scratch against the observations in this document and carry no
upstream copyright, but must not be produced by editing an upstream file down.
Files classified **DROP** or **KEEP** contribute no code to this repository.

---

## 8. Re-verification

`tests/shell/test_port_map.sh` re-derives the import list, the referenced
`qs.Commons` singletons, the instantiated `qs.Ui` components and the injected
properties straight from the pinned tree, and fails when any of them is missing
from §3 or when a row carries an invalid verdict. Bumping the pin in
`UPSTREAM.md` will fail that test until this document is re-verified against the
new tree. The test skips (exit 0, with an explicit message) when
`vendor/omarchy/` is absent, since it is git-ignored by design.

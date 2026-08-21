# Cachy Omarchy Overlay

*[한국어 README](README.ko-KR.md)*

An Arch package overlay that runs the [Omarchy](https://github.com/basecamp/omarchy)
Quattro shell **as upstream ships it** on CachyOS + Hyprland.

It does not reimplement the launcher. It pins the official Omarchy repository to a
specific commit, extracts and packages only the runtime it needs, and patches only
where a patch is unavoidable (SPEC §1).

```text
SUPER + SPACE  →  Omarchy Quattro launcher / menu
SUPER + K      →  Omarchy-style keybinding viewer
```

## Components

Two Arch packages are produced.

| Package | Version | Role |
|---|---|---|
| `cachy-omarchy-shell` | 4.0.0-12 | The pinned Omarchy Quattro shell runtime (Quickshell tree, `omarchy-settings` excluded) |
| `cachy-omarchy-overlay` | 0.9.0-1 | The CachyOS integration layer (wrapper commands, Hyprland bindings, defaults) |

The upstream pin is managed by `upstream.lock` (currently `basecamp/omarchy @ v4.0.0`,
`f0020448`).

Seven public commands are installed into `/usr/bin`:

- `cachy-omarchy-shell` — start the shell (`--run`), talk to it (`--ipc`), restart it manually (`--restart`)
- `cachy-omarchy-launcher` — toggle the launcher (SUPER + SPACE)
- `cachy-omarchy-keybindings` — toggle the keybinding viewer (SUPER + K)
- `cachy-omarchy-bindings` — inject/remove the managed source block in your Hyprland config
- `cachy-omarchy-init` — one-time user setup (never overwrites existing files)
- `cachy-omarchy-doctor` — read-only diagnostics (including theme state)
- `omarchy-theme-set` — apply a theme from the audited upstream helper set

## Session requirement

Choose **Hyprland (uwsm-managed)** at login. The packages conflict with the official
`omarchy` package because both own `/usr/bin/omarchy-*` names.

## Themes

The upstream theme pipeline is used as-is (M9). The first `cachy-omarchy-init` seeds
"Tokyo Night" only when no theme is present.

```bash
omarchy-theme-set "Nord"     # switch — bar and menu update without a shell restart
```

You can also use `Style > Theme` in the launcher menu. Theme state lives where upstream
puts it, `~/.local/state/omarchy/current/theme/`, and a user overlay
(`~/.config/omarchy/themes/<name>/`) is merged over the packaged themes.

## Utility plugins (M10)

Five upstream first-party plugins — clipboard, emojis, image-picker, reminders, and OSD —
are loaded by default per upstream's own rules. M10 closes the gap by packaging the
helpers their QML calls and the runtime dependencies they need (`jq`, `wl-clipboard`,
`wtype`, `wireplumber`, `pipewire-pulse`, `xdg-utils`).

- **Clipboard** — the clipboard entry in the menu, or the `omarchy.clipboard` toggle.
  History is written to the same file upstream uses,
  `~/.local/state/omarchy/clipboard-history.json` (300 entries max, local only), and
  sensitive selections (password-manager hints and the like) are not stored.
  `cachy-omarchy-doctor` reports the path and entry count read-only. Nothing clears the
  history but an explicit user action.
- **Emojis** — the Emoji entry in the menu. Puts the chosen emoji on the clipboard and
  pastes it once into the focused application. Cancelling has no side effects.
- **Image picker** — the upstream image grid used for theme and background selection
  (the same `omarchy-menu-images` path as M9).
- **Reminders** — configured through `omarchy-reminder -i` or the menu. Uses only user
  systemd timers (`omarchy-reminder-*.timer`) and metadata under
  `${XDG_RUNTIME_DIR:-/tmp}/omarchy-reminders/` — no system units, no `/etc`, no root.
- **OSD** — the volume and microphone-mute helpers plus `omarchy-osd` raise the upstream
  `omarchy.osd` panel. Audited helpers are exposed as `/usr/bin/omarchy-*`; they require
  the graphical uwsm session's `OMARCHY_PATH` to run correctly. No XF86 media-key bindings are injected;
  the only reachable paths are the explicit CLI and the menu. (The screen-brightness chain
  is out of scope.)

## Startup model

The shell starts from **Hyprland autostart**, not from a systemd unit — the same model
upstream omarchy uses. `bindings.lua` runs `cachy-omarchy-shell --run` on the
`hyprland.start` event (once per session). There is no automatic restart after a crash;
recover manually with `cachy-omarchy-shell --restart`.

## Build and install

```bash
bin/build-packages           # build both packages + audit (build/*.pkg.tar.zst)
bin/install-packages         # install the build output
cachy-omarchy-init           # one-time: create bindings and user state
```

`cachy-omarchy-init` also configures the lock screen the first time it runs. It
delegates to the upstream `omarchy-apply-lock` helper, which writes
`/etc/pam.d/omarchy-lock-password` and therefore asks for sudo. Without that PAM
service the shell refuses to lock and `omarchy-system-lock` exits 0 having done
nothing, so run `omarchy-apply-lock` yourself if you skip the prompt.
`cachy-omarchy-doctor` reports a missing service as a failure.

Upstream tracking:

```bash
bin/check-upstream           # check upstream for changes against the pin
bin/update-upstream          # refresh the pin + rebuild pipeline
bin/rollback                 # return to the previous pin
```

## Development

```bash
./tests/test.sh              # full suite (each test runs in an isolated sandbox HOME)
./tests/test.sh wrapper      # run a filtered subset
```

Document map:

- `SPEC.md` — the authoritative specification
- `UPSTREAM.md` — upstream pin and tracking policy
- `docs/RUNTIME_STARTUP.md` — measured startup paths and plugin disablement

Milestone design and implementation plans are kept in a private development tree and are
not part of this repository. Where public documents cite a design record, they name the
file only.

## Roadmap

- **v0.1** — runtime packaging + launcher + keybindings + update/rebuild. Done.
- **v0.2 (Milestone 8)** — adopt `omarchy.bar`. Done (`v0.2.0`). The upstream bar ships
  enabled. It does not replace Waybar — running both stacks them rather than overlapping
  them (vertical reservation `36 → 62px`), and we neither stop nor remove Waybar.
- **v0.3 (Milestone 9)** — adopt the upstream theme runtime. Done (`v0.3.0`). Stages
  `themes/` + `default/themed/` + the theme helpers from the same pin, and runs upstream
  `omarchy-theme-set` unpatched through its `/usr/bin` symlink.
  Measurements: `docs/RUNTIME_STARTUP.md` §18.6.
- **v0.4 (Milestone 10)** — adopt the utility plugin helpers and dependencies
  (clipboard, emojis, image-picker, reminders, OSD). Done (`v0.4.0`). Measurements:
  `docs/RUNTIME_STARTUP.md` §19.2.
- **v0.5** — session environment: `OMARCHY_PATH` from the uwsm Hyprland drop-in,
  `/usr/bin/omarchy-*` as a symlink-only view, no PATH manipulation. Done
  (`v0.5.0`). Measurements: `docs/RUNTIME_STARTUP.md` §20.
- **v0.6** — stage menu `style.bar` and session lock/logout/reboot/shutdown
  helpers (`omarchy-bar` plus config/catalog/state/window-close). Factory-reset
  stays off PATH (Omarchy ISO `@factory`). Done (`v0.6.0`).
- **v0.7** — stage audio output switch/tuning templates, display brightness,
  and touchpad/touchscreen guards verbatim. Laptop/monitor-internal stay off
  PATH (need wrappers). Done (`v0.7.0`). Measurements: `docs/RUNTIME_STARTUP.md` §21.1.
- **v0.8** — stage theme install/update/remove, Hyprland toggles, and hardware
  helpers verbatim (`v0.8.0`) — this reversed the v0.7 "need wrappers" call on
  `omarchy-hw-laptop` and the monitor-internal chain; both are staged as of
  this release. The keybindings sheet reads the overlay's own binds
  (`v0.8.1`) and labels them so rows read as names, not commands (`v0.8.2`).
- **Lock coexistence measured** — the last open item in the SPEC §61 acceptance
  checklist closed on 2026-08-20, making it **21/21 measured**. Both directions
  against hyprlock were measured inside a nested, isolated Hyprland.
  Measurements: `docs/RUNTIME_STARTUP.md` §22.
- **v0.9 (dependency closure)** — a scanner walks from real roots (keybindings,
  active-plugin QML, the packaged menu) through the staged upstream helpers and
  fails the build on anything reachable but undeclared or unstaged. Done
  (`v0.9.0`). Promoted ten packages to `depends` and twenty to `optdepends`,
  staged `omarchy-battery-low`, and shimmed `omarchy-menu-keybindings`. Known
  live gaps: `xdg-terminal-exec` is AUR-only, and `omarchy-battery-status` stays
  unstaged, so the Power panel's battery-detail rows stay hidden.

## License

MIT (`LICENSE`). Upstream Omarchy is MIT as well.

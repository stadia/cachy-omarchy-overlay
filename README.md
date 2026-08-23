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
| `cachy-omarchy-shell` | 4.0.0-20 | The pinned Omarchy Quattro shell runtime (Quickshell tree, `omarchy-settings` excluded) |
| `cachy-omarchy-overlay` | 0.12.1-1 | The CachyOS integration layer (wrapper commands, Hyprland bindings, defaults) |

The upstream pin is managed by `upstream.lock` (currently `basecamp/omarchy @ v4.0.0`,
`f0020448`).

Eight public commands are installed into `/usr/bin`:

- `cachy-omarchy-shell` — start the shell (`--run`), talk to it (`--ipc`), restart it manually (`--restart`)
- `cachy-omarchy-launcher` — toggle the launcher (SUPER + SPACE)
- `cachy-omarchy-keybindings` — toggle the keybinding viewer (SUPER + K)
- `cachy-omarchy-bindings` — inject/remove the managed source block in your Hyprland config
- `cachy-omarchy-init` — one-time user setup (never overwrites existing files)
- `cachy-omarchy-doctor` — read-only diagnostics (including theme state)
- `cachy-omarchy-reload` — lock-aware front for `cachy-omarchy-shell --restart`
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

## Weather widget

The bar weather widget and its panel send real requests to **wttr.in** (IP city
lookup and current conditions) and to **Open-Meteo** (`api.open-meteo.com`
forecast and `geocoding-api.open-meteo.com` city search). A saved location is
written only by `omarchy-weather-location --set`, into
`~/.local/state/omarchy/settings/weather.json` (upstream default path). If that
file is absent, every lookup infers the city from the client IP via wttr.in and
does not persist it. To disable the widget, remove `omarchy.weather` from the
bar layout in `~/.config/omarchy/shell.json`. Creating that file does not
deep-merge: package defaults are ignored wholesale, and `cachy-omarchy-doctor`
WARNs on its existence (`docs/RUNTIME_STARTUP.md`, `docs/RC_GAP_INVENTORY.md`).

## Session lifecycle (v0.11)

The idle → screensaver → lock → wake chain is packaged: idle timeout dims the
keyboard backlight (`off`) and locks the screen, an explicit lock request
launches the terminal screensaver, and waking restores the keyboard backlight.
There is no laptop-lid trigger in this product — upstream's lid-switch
keybinding (`default/hypr/bindings/utilities.lua`) is never staged, so closing
the lid does not run `omarchy-hyprland-monitor-clamshell` here. That helper is
still shipped and still reachable, just transitively, through the same
`omarchy-system-wake` call the idle/lock chain already makes. Likewise, only
`omarchy-brightness-keyboard`'s `off`/`restore` subcommands are wired up;
`up`/`down`/`cycle` are upstream media-key (XF86Kbd*) bindings this overlay
does not ship.

Optional: install `ttfx` (AUR) for the idle screensaver and `socat` for its
multi-monitor placement. Without them the screensaver simply does not start;
nothing else is affected. The clamshell/toggle seam that this chain uses only
runs for `hyprland.lua` configs — `hyprland.conf` users are WARNed by
`cachy-omarchy-doctor` if they have toggle files (see `docs/RUNTIME_STARTUP.md`).

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
  live gaps at that cut: `xdg-terminal-exec` is AUR-only, and
  `omarchy-battery-status` was still unstaged, so the Power panel's
  battery-detail rows stayed hidden.
- **v0.10 (visible Quattro completeness)** — staged the nine helpers the
  default bar and panels already call: `omarchy-battery-status`,
  `omarchy-system-stats`, `omarchy-theme-refresh`,
  `omarchy-audio-input-set-default`, `omarchy-audio-sink-availability`,
  `omarchy-bluetooth-power`, `omarchy-bluetooth-device`,
  `omarchy-weather-location`, `omarchy-weather-status`. Power-panel battery
  detail rows and the bar monitor/audio/bluetooth/weather widgets no longer
  exit 127. Remaining live gap: `xdg-terminal-exec` is still AUR-only (direction
  deferred to v0.11).
- **v0.11 (session lifecycle parity)** — closed the idle → screensaver → lock →
  wake chain. Planning expected seven candidates; opening the closure found
  four more with no exception row at all, so the actual ship set is nine:
  `omarchy-cmd-missing`, `omarchy-hw-laptop-closed`, `omarchy-hw-external-monitors`,
  `omarchy-hw-clamshell`, `omarchy-brightness-keyboard`,
  `omarchy-hyprland-monitor-clamshell`, `omarchy-system-wake`,
  `omarchy-screensaver`, `omarchy-launch-screensaver`, plus the three terminal
  screensaver configs. A new `pcall(dofile)` sweep block in
  `overlay/hypr/bindings.lua` opens the `hyprland.lua`-only toggles seam that
  clamshell (and the already-staged `omarchy-hyprland-monitor-internal(-mirror)`)
  needs. `xdg-terminal-exec` stays an AUR optdepend — no fallback adapter.
- **v0.12 (presentation & runtime polish)** — staged `omarchy-bar-text-color`
  (bar text contrast against the background image, `imagemagick` optdepend)
  and the gum presentation layer (`omarchy-restart-gum`, `omarchy-show-logo`,
  `omarchy-show-done`, `omarchy-launch-floating-terminal-with-presentation`),
  which closes three menu rows that previously failed for lacking a launcher:
  hardware-audio restart, passwordless-sudo setup, and custom-DNS setup.
  `cachy-omarchy-shell --restart` (and its `cachy-omarchy-reload` front) now
  refuses while the session is locked instead of racing hyprlock; recovering a
  stranded lock stays out of scope (`docs/RUNTIME_STARTUP.md` §22.4).

## License

MIT (`LICENSE`). Upstream Omarchy is MIT as well.

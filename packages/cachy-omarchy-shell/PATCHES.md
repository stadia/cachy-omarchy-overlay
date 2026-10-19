# Maintained runtime patches

`PKGBUILD` lists these maintained runtime patches as `source=` entries (with
`sha256sums`) and `prepare()` applies them to the pinned source in the order of
its `_patches` array; `bin/update-upstream` therefore finds out whether they still
apply when it builds the new pin. Each patch is a unified diff (as produced by `git diff`, applied with `git apply`)
against the commit pinned by `packages/cachy-omarchy-shell/PKGBUILD:_commit`.

## Plugin watcher cleanup

Patch: `0001-stop-plugin-watcher-on-shell-exit.patch`

Reason: Quickshell 0.3.0 leaves the `inotifywait` child alive when its Process owner exits.
It also installs no `SIGTERM` handler, so it dies at exit 143 with no QML engine teardown and
`Component.onDestruction` never runs on the real exit paths (`omarchy-restart-shell`,
logout). The patch therefore carries two devices: the QML-side `stopLocalPluginWatcher()` for
clean engine teardown, and `setpriv --pdeathsig TERM --` on the watcher command so the kernel
reaps it whichever way the shell dies. Runtime evidence: `tests/runtime/test_reload_watcher_reap.sh`.

Upstream issue: not filed.

Can remove when: Quickshell/upstream guarantees child Process cleanup and this patch no longer applies.

## Polkit cancellation before session lock

Patch: `0002-cancel-polkit-flow-before-session-lock.patch`

Reason: An active Polkit authentication flow can leave the locked session waiting indefinitely.

Upstream issue: not filed; v1.0 acceptance evidence is in `git show v1.0.2:docs/V1_ACCEPTANCE.md` (§polkit).

Can remove when: an upstream fix is verified to cancel an active Polkit flow before the session lock becomes secure.

## Keybindings sheet on a stock CachyOS Hyprland config

Patch: `0003-adapt-menu-keybindings-to-cachy-hyprland.patch`

Reason: upstream's `omarchy-menu-keybindings` assumes an Omarchy Lua config where every bind has a
`description`. A stock CachyOS `hyprland.lua` has none, so upstream shows only two static rows. The
patch records every `hl.bind` from the Lua source (synthesizing a description from the command or
the `hl.dsp.*` expression), joins the source cache to `hyprctl binds` on modmask+key instead of
modmask+description, separates record fields with ASCII 0x1f so command arguments may contain commas,
drops the two hardcoded Omarchy web-app rows, and changes the cache key so records from the unpatched
helper are not reused. The Lua scan itself stays upstream's (`pcall(dofile, config)` with a fake `hl`, standard libraries
not restricted; top-level code of `hyprland.lua` and `bindings.lua` runs with the user's privileges on
every cache miss, `hl.*` side effects are noops), which also follows the managed `pcall(dofile, ...)`
block into `~/.config/cachy-omarchy/hypr/bindings.lua`. A `__lua` row is now dropped only when the source
cache has no bind for its modmask+key (upstream: when it has no description). `lua` is a hard dependency:
without it the helper reports an error and exits 1 instead of showing an empty sheet. A failing scan prints
one line on stderr and its (partial) result is not cached; a menu that cannot be shown (shell not running,
`omarchy-menu-select` missing) also reports and exits 1, while Escape still exits quietly.

Upstream issue: not filed.

Can remove when: upstream's sheet lists description-less binds and joins them without a description.

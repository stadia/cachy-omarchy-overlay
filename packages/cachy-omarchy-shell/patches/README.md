# Maintained runtime patches

`bin/update-upstream` applies these maintained runtime patches to its disposable
candidate source in lexicographic filename order. Each patch is a git-format patch
against the commit pinned by `packages/cachy-omarchy-shell/PKGBUILD:_commit`.

## Plugin watcher cleanup

Patch: `0001-stop-plugin-watcher-on-shell-exit.patch`

Reason: Quickshell 0.3.0 leaves the `inotifywait` child alive when its Process owner exits.
It also installs no `SIGTERM` handler, so it dies at exit 143 with no QML engine teardown and
`Component.onDestruction` never runs on the real exit paths (`cachy-omarchy-shell --restart`,
logout). The patch therefore carries two devices: the QML-side `stopLocalPluginWatcher()` for
clean engine teardown, and `setpriv --pdeathsig TERM --` on the watcher command so the kernel
reaps it whichever way the shell dies. Runtime evidence: `tests/runtime/test_reload_watcher_reap.sh`.

Upstream issue: not filed; local v1.0 acceptance evidence is `docs/V1_ACCEPTANCE.md §polkit`.

Can remove when: Quickshell/upstream guarantees child Process cleanup and this patch no longer applies.

## Polkit cancellation before session lock

Patch: `0002-cancel-polkit-flow-before-session-lock.patch`

Reason: An active Polkit authentication flow can leave the locked session waiting indefinitely.

Upstream issue: not filed; local v1.0 acceptance evidence is `docs/V1_ACCEPTANCE.md §polkit`.

Can remove when: an upstream fix is verified to cancel an active Polkit flow before the session lock becomes secure.

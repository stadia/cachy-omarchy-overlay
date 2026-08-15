import QtQuick
import Quickshell

import "services"

// Regression harness for Config.get() (shell/services/Config.qml). A path
// that runs through a non-object leaf (string/number/bool/null) must
// degrade to the fallback rather than throwing
// "TypeError: Cannot use 'in' operator to search for ... in <primitive>".
//
// tests/shell/test_config_get.sh copies this file to <scratch>/shell.qml and
// the real shell/services/Config.qml to <scratch>/services/Config.qml (so it
// always exercises the live source, never a stale duplicate), then runs
// `qs -p <scratch>` -- Quickshell requires relative-path directory imports
// to stay inside the config folder given to -p, which a fixture living under
// tests/ cannot satisfy directly.
//
// It loads config_get_probe/config.jsonc (path supplied via
// COO_PROBE_CONFIG_ROOT, the same env-var-injection pattern shell.qml uses
// for COO_CONFIG_ROOT), runs a fixed set of get() calls once the fixture is
// loaded, and prints one "ok"/"FAIL" line per case plus a PROBE_DONE
// sentinel. Quickshell 0.3.0 has no receiver for QQmlEngine::exit(), so
// Qt.exit() here is a harmless no-op -- the caller bounds and kills the
// process itself once it has read PROBE_DONE.
ShellRoot {
  id: root

  property bool didRun: false

  property Config cfg: Config {
    configRoot: Quickshell.env("COO_PROBE_CONFIG_ROOT")
    onLoadedChanged: if (loaded && !root.didRun) {
      root.didRun = true
      root.runChecks()
    }
  }

  function check(path, fallback, expected, label) {
    var actual
    var threw = false
    try {
      actual = cfg.get(path, fallback)
    } catch (e) {
      threw = true
      actual = String(e)
    }
    var ok = !threw && String(actual) === String(expected)
    console.log((ok ? "ok" : "FAIL") + ": " + label + " => " + JSON.stringify(actual) + (threw ? " (threw)" : ""))
  }

  function runChecks() {
    check("str.x", "FALLBACK", "FALLBACK", "path through string leaf")
    check("num.x", "FALLBACK", "FALLBACK", "path through number leaf")
    check("boolVal.x", "FALLBACK", "FALLBACK", "path through boolean leaf")
    check("nil.x", "FALLBACK", "FALLBACK", "path through explicit null")
    check("missingTop", "FALLBACK", "FALLBACK", "absent top-level key")
    check("nested.a.missing", "FALLBACK", "FALLBACK", "absent nested key under valid object")
    check("nested.a.b", "FALLBACK", "1", "valid multi-segment path resolves")
    console.log("PROBE_DONE")
    Qt.exit(0)
  }
}

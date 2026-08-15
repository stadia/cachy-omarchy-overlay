import QtQuick
import Quickshell
import Quickshell.Io

import "services"

// The coo-shell root. Long-running host for launcher surfaces only.
// It MUST NOT create a bar, notifications, OSD, lock screen, or polkit
// agent (SPEC 12.1).
ShellRoot {
  id: shell

  // The config root is supplied by the launcher script so dev runs and
  // installed runs can point at different directories.
  readonly property string configRoot: {
    var override = Quickshell.env("COO_CONFIG_ROOT")
    if (override && override.length > 0)
      return override
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    var base = (xdg && xdg.length > 0) ? xdg : Quickshell.env("HOME") + "/.config"
    return base + "/cachy-omarchy-overlay"
  }

  property Config config: Config { configRoot: shell.configRoot }

  IpcHandler {
    target: "shell"

    function ping(): string {
      return "ok"
    }

    function version(): string {
      return String(shell.config.get("version", "unknown"))
    }

    function reload(): string {
      shell.config.reload()
      return "ok"
    }
  }

  Component.onCompleted: console.log("coo-shell: ready, configRoot=" + shell.configRoot)
}

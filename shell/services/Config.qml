import QtQuick
import Quickshell
import Quickshell.Io

// Reads config.jsonc from the project config root. Instantiated once by
// shell.qml and injected into consumers by property, never imported as a
// singleton -- relative-path imports do not share singleton state.
Item {
  id: root

  property string configRoot: ""
  property var data: ({})
  property bool loaded: false

  readonly property string configFile: configRoot + "/config.jsonc"

  function get(path, fallback) {
    var parts = String(path || "").split(".")
    var node = root.data
    for (var i = 0; i < parts.length; i++) {
      if (node === null || node === undefined || !(parts[i] in node))
        return fallback
      node = node[parts[i]]
    }
    return node
  }

  // jsonc allows // comments; strip whole-line comments before parsing.
  // Block comments and trailing comments are not supported yet -- add them
  // with a test when a config file needs them.
  function _parseJsonc(raw) {
    var lines = String(raw || "").split("\n")
    var kept = []
    for (var i = 0; i < lines.length; i++) {
      if (/^\s*\/\//.test(lines[i])) continue
      kept.push(lines[i])
    }
    try {
      return JSON.parse(kept.join("\n"))
    } catch (e) {
      console.warn("coo: failed to parse " + root.configFile + ": " + e)
      return ({})
    }
  }

  function reload() {
    configView.reload()
  }

  FileView {
    id: configView
    path: root.configFile
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      root.data = root._parseJsonc(text())
      root.loaded = true
    }
    onLoadFailed: {
      console.warn("coo: config not readable: " + root.configFile)
      root.data = ({})
      root.loaded = true
    }
  }
}

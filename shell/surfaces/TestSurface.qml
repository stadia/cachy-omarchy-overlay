import QtQuick
import Quickshell
import Quickshell.Wayland

// Milestone 1 throwaway. Proves a LayerShell surface can be shown and hidden
// over IPC with keyboard focus and an Escape handler. Deleted or replaced
// when the real launcher surface lands in Milestone 2.
PanelWindow {
  id: surface

  property var config: null
  signal requestClose()

  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  WlrLayershell.namespace: "coo-test"

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  anchors { top: true; bottom: true; left: true; right: true }

  Component.onCompleted: console.log("coo-shell: test surface ready")

  Rectangle {
    anchors.centerIn: parent
    width: 420
    height: 140
    radius: 14
    color: "#1e1e2e"
    border.color: "#45475a"
    border.width: 1

    Text {
      anchors.centerIn: parent
      color: "#cdd6f4"
      font.pixelSize: 16
      horizontalAlignment: Text.AlignHCenter
      text: "coo-shell test surface\nEsc to close"
    }
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onEscapePressed: surface.requestClose()
  }
}

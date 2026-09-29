import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Multi-monitor aware workspace indicators. Every workspace visible on some
// monitor gets a pip:
//   blue   - the focused workspace, on the bar of the monitor showing it
//   green  - the focused workspace, on the other monitors' bars
//   yellow - the workspace this bar's monitor shows, when it isn't focused
//   white  - a workspace another (unfocused) monitor shows
// A ring around a pip/number means that workspace has a fullscreen window.
// Colors come from the current theme's colors.toml and can be overridden in
// shell.json with focusedColor / focusedElsewhereColor / localColor, or set
// "colorblind": true for a colour-blind-safe palette.
BarWidget {
  id: root
  moduleName: "littleme.multimon-workspaces"

  property var themeColors: ({})

  // Quickshell 0.3.1 leaves each monitor's activeWorkspace stale after a
  // workspace moves between monitors (Hyprland sends focusedmon before
  // moveworkspacev2), so refresh the monitor model once the move lands.
  // Same fix as omacom/omarchy#10190 for omarchy/omarchy#10187.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "moveworkspacev2") Hyprland.refreshMonitors()
    }
  }

  // "colorblind": true swaps the theme's green/yellow (hard to tell apart
  // with red-green colour blindness) for the Okabe-Ito colour-safe palette.
  readonly property bool colorblind: setting("colorblind", false) === true
  readonly property color focusedColor: setting("focusedColor", colorblind ? "#0072B2" : (themeColors.blue || "#7aa2f7"))
  readonly property color focusedElsewhereColor: setting("focusedElsewhereColor", colorblind ? "#56B4E9" : (themeColors.green || "#9ece6a"))
  readonly property color localColor: setting("localColor", colorblind ? "#E69F00" : (themeColors.yellow || "#e0af68"))

  // Output name (e.g. "DP-3") of the screen this bar instance is drawn on.
  // Compared by name, not object: a monitor that reconnects (USB-C dock)
  // gets a new HyprlandMonitor object, which would never match a cached one.
  readonly property string ownMonitorName: {
    var window = root.QsWindow.window
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function loadThemeColors(raw) {
    var colors = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (match) colors[match[1]] = match[2]
    }
    themeColors = colors
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeColors(text())
    onFileChanged: reload()
  }

  // A theme switch can swap the directory behind the path without the file
  // watch noticing; the global palette changing is a reliable signal too.
  Connections {
    target: Color
    function onAccentChanged() { themeColorsFile.reload() }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The monitor currently showing workspace `id`, or null if none is.
  function monitorShowing(id) {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      if (monitors[i].activeWorkspace && monitors[i].activeWorkspace.id === id) return monitors[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property var shownOn: root.monitorShowing(modelData)
        readonly property bool shown: shownOn !== null || focused
        readonly property bool local: shownOn !== null && root.ownMonitorName !== "" && shownOn.name === root.ownMonitorName

        // Pip and ring are drawn as shapes, not a font glyph, so they share an
        // exact pixel-snapped centre at any monitor scale.
        readonly property int pipSize: Math.round(fontSize * 0.78)
        readonly property int ringGap: 2
        readonly property int ringBorder: Math.max(1, Math.round(fontSize / 12))

        bar: root.bar
        text: shown ? "" : (modelData === 10 ? "0" : String(modelData))
        hasVisualContent: true
        foreground: focused ? (local ? root.focusedColor : root.focusedElsewhereColor)
          : local ? root.localColor
          : (root.bar ? root.bar.barForeground : Color.foreground)
        opacity: occupied || shown ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }

        // Pip for workspaces that are on a screen.
        Rectangle {
          visible: parent.shown
          width: parent.pipSize
          height: width
          x: Math.round((parent.width - width) / 2)
          y: Math.round((parent.height - height) / 2)
          radius: width * 0.3
          color: parent.foreground
          Behavior on color { ColorAnimation { duration: 160 } }
        }

        // Ring around the pip/number while the workspace has a fullscreen
        // window (games, videos). Same centre as the pip, 2px gap.
        Rectangle {
          visible: workspace !== null && workspace.hasFullscreen
          width: parent.pipSize + 2 * (parent.ringGap + parent.ringBorder)
          height: width
          x: Math.round((parent.width - parent.pipSize) / 2) - parent.ringGap - parent.ringBorder
          y: Math.round((parent.height - parent.pipSize) / 2) - parent.ringGap - parent.ringBorder
          radius: width * 0.35
          color: "transparent"
          border.width: parent.ringBorder
          border.color: root.bar ? root.bar.barForeground : Color.foreground
        }
      }
    }
  }
}

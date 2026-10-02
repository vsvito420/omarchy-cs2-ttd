import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// CS2 Time-to-Damage widget. tracker/tracker.py (systemd user timer cs2-ttd)
// pulls cs2tracker.gg and writes ~/.local/state/cs2-ttd/widget.json; this widget
// only watches that file. Right click or "Refresh" starts the service now.
Panel {
  id: root
  moduleName: "vsvito.cs2-ttd"
  ipcTarget: "vsvito.cs2-ttd"

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string recordPath: home + "/.local/state/cs2-ttd/widget.json"
  readonly property string icon: "󰆣"

  property var record: null
  property bool busy: false
  property string actionError: ""

  readonly property var last: record && record.last ? record.last : null
  readonly property var first: record && record.first ? record.first : null
  readonly property var delta: record && record.deltaMs !== null && record.deltaMs !== undefined ? record.deltaMs : null
  readonly property var history: record && record.history ? record.history : []

  readonly property string deltaText: {
    if (delta === null) return ""
    if (delta === 0) return "±0"
    return (delta < 0 ? "↓" : "↑") + Math.abs(delta)
  }

  readonly property string barText: {
    if (!last || last.ttd_avg_ms === null || last.ttd_avg_ms === undefined) return "—"
    return last.ttd_avg_ms + "ms" + (delta ? " " + deltaText : "")
  }

  function msText(v) {
    return v === null || v === undefined ? "—" : v + " ms"
  }

  function dateText(iso) {
    if (!iso) return "—"
    var d = new Date(iso)
    if (isNaN(d.getTime())) return "—"
    return Qt.formatDateTime(d, "dd.MM. HH:mm")
  }

  function refresh() {
    if (refreshProc.running) return
    actionError = ""
    busy = true
    refreshProc.running = true
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      root.record = null
    }
  }

  FileView {
    path: root.recordPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  Process {
    id: refreshProc
    command: ["systemctl", "--user", "start", "cs2-ttd.service"]
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) root.actionError = "Refresh failed (journalctl --user -u cs2-ttd)"
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: vertical ? root.icon : root.icon + " " + root.barText
    slotSize: Style.bar.iconSlot * (vertical ? 1 : Math.max(1, (root.barText.length + 2) * 0.42))
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onActivateRequested: root.refresh()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r") root.refresh() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroValue.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.icon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroValue.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Time to Damage"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: {
                if (root.actionError !== "") return root.actionError
                if (root.delta === null) return "NO DATA"
                if (root.delta < 0) return "FASTER " + root.deltaText + " MS"
                if (root.delta > 0) return "SLOWER " + root.deltaText + " MS"
                return "UNCHANGED"
              }
              color: root.actionError !== "" || (root.delta !== null && root.delta > 0) ? Color.urgent : Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroValue
            textFormat: Text.PlainText
            text: root.last ? root.msText(root.last.ttd_avg_ms) : "—"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- Sparkline ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Canvas {
            id: spark
            visible: root.history.length >= 2
            width: parent.width
            height: Style.space(56)
            property var points: root.history
            property color stroke: root.bar.foreground
            onPointsChanged: requestPaint()
            onStrokeChanged: requestPaint()
            onWidthChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var p = points
              if (!p || p.length < 2) return
              var lo = Math.min.apply(null, p), hi = Math.max.apply(null, p)
              var pad = Math.max((hi - lo) * 0.15, 5)
              lo -= pad; hi += pad
              var m = 4
              function x(i) { return m + i / (p.length - 1) * (width - 2 * m) }
              // lower ms = better, so draw faster values higher up
              function y(v) { return m + (v - lo) / (hi - lo) * (height - 2 * m) }
              ctx.strokeStyle = stroke
              ctx.lineWidth = 2
              ctx.lineJoin = "round"
              ctx.beginPath()
              for (var i = 0; i < p.length; i++) {
                if (i === 0) ctx.moveTo(x(i), y(p[i])); else ctx.lineTo(x(i), y(p[i]))
              }
              ctx.stroke()
              ctx.fillStyle = stroke
              ctx.beginPath()
              ctx.arc(x(p.length - 1), y(p[p.length - 1]), 3, 0, 2 * Math.PI)
              ctx.fill()
            }
          }

          InfoLabel {
            text: root.history.length >= 2
              ? "Trend over " + root.history.length + " snapshots · higher = faster"
              : "Trend appears once the value changes"
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair { label: "Start (" + (root.first ? root.dateText(root.first.ts) : "—") + ")"; value: root.first ? root.msText(root.first.ttd_avg_ms) : "—" }
          InfoPair { label: "scope.gg current / previous"; value: root.last ? root.last.ttd_current_ms + " / " + root.last.ttd_previous_ms + " ms" : "—" }
          InfoPair { label: "Fastest"; value: root.last ? root.msText(root.last.ttd_fastest_ms) : "—" }
          InfoPair { label: "Matches (sniper)"; value: root.last ? String(root.last.ttd_matches) : "—" }
          InfoPair { label: "Time to Kill Ø (rifle)"; value: root.last ? root.msText(root.last.ttk_avg_ms) : "—" }
          InfoPair { label: "Leetify reaction"; value: root.last ? root.msText(root.last.leetify_reaction_ms) : "—" }
          InfoPair { label: "Last game"; value: root.last ? root.dateText(root.last.last_game_at) : "—" }
          InfoPair { visible: !!(root.record && root.record.since); label: root.record ? root.record.sinceLabel + " since" : ""; value: root.record ? String(root.record.since) : "" }
        }

        Row {
          id: actions
          width: parent.width
          spacing: Style.space(6)
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: actions.cellWidth
            iconText: "󰑐"
            iconSpinning: root.busy
            text: root.busy ? "Loading" : "Refresh"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.refresh()
          }

          Button {
            width: actions.cellWidth
            iconText: "󰈈"
            text: "Report"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: {
              if (root.record && root.record.report) Quickshell.execDetached(["xdg-open", root.record.report])
              root.close()
            }
          }
        }

        InfoLabel { text: "Checked " + (root.record ? root.dateText(root.record.checkedAt) : "—") }
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    opacity: 0.6
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
  }
}

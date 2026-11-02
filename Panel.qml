import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Proton VPN indicator + panel for NetworkManager WireGuard "pvpn-*" profiles.
// Reads state with one cheap `nmcli` query, woken by `nmcli monitor` lines that
// mention pvpn-. All changes (switch, verify, rollback, boot, notify) are done
// by the bundled `pvpn` CLI, so the bar and the terminal behave identically.
Panel {
  id: root
  moduleName: "allandehn.pvpn"
  ipcTarget: "allandehn.pvpn"
  manageIpc: false

  property var conns: []        // [{ name, active }]
  property string active: ""    // e.g. "pvpn-dk", "" when off
  property string lastError: ""
  property int cursorIndex: 0
  property bool cursorActive: false
  property string pending: ""   // optimistic target: name, "off", or ""
  readonly property bool on: pending !== "" ? pending !== "off" : active !== ""
  readonly property string shown: pending !== "" && pending !== "off" ? pending : active
  readonly property bool connecting: pending !== "" && pending !== "off"
  readonly property string glyphOn: "󰒃"
  readonly property string glyphOff: "󰦞"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Commons.Color.accent) : "transparent"

  readonly property var countries: ({ dk: "Denmark", ee: "Estonia", us: "United States",
    se: "Sweden", no: "Norway", de: "Germany", nl: "Netherlands", ch: "Switzerland",
    fi: "Finland", uk: "United Kingdom", gb: "United Kingdom", fr: "France" })

  function countryOf(name) {
    var cc = String(name).replace(/^pvpn-/, "").toLowerCase()
    var parts = cc.split("-")
    var land = countries[parts[0]] || parts[0].toUpperCase()
    return parts.length > 1 ? land + " (" + parts.slice(1).join(" ") + ")" : land
  }

  function refresh() { if (!query.running) query.running = true }

  // Run the pvpn CLI; names are separate argv elements, never part of a script string.
  function pvpn(args, optimistic) {
    if (action.running) return
    pending = optimistic
    lastError = ""
    action.errText = ""
    action.command = ["sh", "-c", 'p=$(command -v pvpn || printf %s "$HOME/.local/bin/pvpn"); exec "$p" "$@"', "pvpn"].concat(args)
    action.running = true
  }
  function connectTo(name) { pvpn(["up", name], name) }
  function reconnect(name) { pvpn(["reconnect", name], name) }
  function turnOff() { pvpn(["down"], "off") }
  function toggleVpn() {
    if (on) { turnOff(); return }
    var target = lastUsed.text().trim()
    var ok = false
    for (var i = 0; i < conns.length; i++) if (conns[i].name === target) ok = true
    pvpn(["toggle"], ok ? target : (conns.length > 0 ? conns[0].name : ""))
  }
  function pickConn(name) { root.close(); if (name === active) reconnect(name); else connectTo(name) }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  FileView {
    id: lastUsed
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/pvpn/last"
    printErrors: false
  }

  Process {
    id: query
    command: ["nmcli", "-t", "-f", "NAME,TYPE,ACTIVE", "connection", "show"]
    property var found: []
    onStarted: found = []
    stdout: SplitParser {
      onRead: function(line) {
        var p = String(line).split(":")
        if (p.length >= 3 && p[0].indexOf("pvpn-") === 0 && p[1] === "wireguard")
          query.found.push({ name: p[0], active: p[2] === "yes" })
      }
    }
    onExited: {
      var list = query.found.slice().sort(function(a, b) { return a.name < b.name ? -1 : 1 })
      var act = ""
      for (var i = 0; i < list.length; i++) if (list[i].active && act === "") act = list[i].name
      root.conns = list
      root.active = act
      if (root.cursorIndex >= list.length) root.cursorIndex = Math.max(0, list.length - 1)
    }
  }

  Process {
    id: action
    property string errText: ""
    stderr: SplitParser { onRead: function(line) { action.errText += (action.errText ? " " : "") + String(line) } }
    onExited: function(code) {
      // Code 1 = connect failed; the CLI already notified and rolled back.
      if (code > 1) root.lastError = action.errText !== "" ? action.errText : "pvpn failed (exit " + code + ")"
      root.pending = ""
      lastUsed.reload()
      root.refresh()
    }
  }

  // Interfaces are named like their profiles (pvpn-*), so this filter catches
  // profile and device changes, including disconnects.
  Process {
    id: monitor
    command: ["nmcli", "monitor"]
    running: true
    property int backoff: 10000
    stdout: SplitParser { onRead: function(line) { if (String(line).indexOf("pvpn-") !== -1) debounce.restart() } }
    onStarted: stable.restart()
    onExited: { stable.stop(); restartMonitor.interval = backoff; backoff = Math.min(backoff * 2, 300000); restartMonitor.start() }
  }
  Timer { id: stable; interval: 60000; onTriggered: monitor.backoff = 10000 }
  Timer { id: restartMonitor; onTriggered: { monitor.running = true; root.refresh() } }
  Timer { id: debounce; interval: 400; onTriggered: root.refresh() }
  Component.onCompleted: refresh()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function up(): string { if (!root.on) root.toggleVpn(); return "ok" }
    function down(): string { if (root.on) root.turnOff(); return "ok" }
    function status(): string { return root.active !== "" ? root.active : "off" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.on ? root.glyphOn : root.glyphOff
    dimmed: !root.on
    tooltipText: root.opened ? "" : (root.on ? "Proton VPN · " + root.countryOf(root.shown) : "Proton VPN · Off")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleVpn()
      else if (b === Qt.MiddleButton) root.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(body.item ? body.item.implicitHeight : 0, Style.space(480))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (root.conns.length === 0) return
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.cursorIndex = Math.max(0, Math.min(root.conns.length - 1, root.cursorIndex + dy))
      }
      onActivateRequested: if (root.cursorActive && root.cursorIndex < root.conns.length) root.pickConn(root.conns[root.cursorIndex].name)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") root.toggleVpn()
        else if ((t === "r" || t === "R") && root.active !== "") root.reconnect(root.active)
      }

      // Panel contents only exist while it is open.
      Loader {
        id: body
        width: parent.width
        active: root.opened
        sourceComponent: Component {
          Column {
            width: body.width
            spacing: Style.space(12)

            Column {
              width: parent.width
              spacing: Style.space(6)
              PanelHero {
                id: hero
                width: parent.width
                title: "Proton VPN"
                meta: root.connecting ? "Connecting…" : (root.on ? root.countryOf(root.shown) + " · " + root.shown : "Off")
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconComponent: Component { Text { textFormat: Text.PlainText; text: root.on ? root.glyphOn : root.glyphOff; color: root.on ? root.foreground : root.dim; font.family: Style.font.family; font.pixelSize: Math.round(Style.font.display) } }
                trailingControl: Component {
                  ToggleSwitch {
                    id: powerSwitch
                    checked: root.on
                    busy: action.running
                    foreground: hero.foreground
                    onToggled: root.toggleVpn()
                    PanelToolTip { visible: powerSwitch.containsMouse; text: root.on ? "Turn Proton VPN off" : "Turn Proton VPN on"; fontFamily: hero.fontFamily }
                  }
                }
              }
              Text {
                visible: root.lastError !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: root.lastError
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }

            PanelSeparator { foreground: root.foreground }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Text {
                visible: root.conns.length === 0
                width: parent.width
                text: "No pvpn-* WireGuard connections found."
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }

              Repeater {
                model: root.conns
                ConnRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  conn: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component ConnRow: CursorSurface {
    id: row
    property var conn: null
    property int rowIndex: 0
    readonly property string name: conn ? conn.name : ""
    readonly property bool isActive: name !== "" && name === root.shown

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: false
    foreground: root.foreground
    fill: root.selectedFill
    opacity: root.on ? 1.0 : 0.5
    implicitHeight: label.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = row.rowIndex }
      onExited: if (root.cursorIndex === row.rowIndex) root.cursorActive = false
      onClicked: root.pickConn(row.name)
    }

    Text {
      id: label
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.countryOf(row.name)
      color: !root.on ? root.dim : (row.isActive ? Commons.Color.accent : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: row.isActive && root.on
      elide: Text.ElideRight
    }
  }
}

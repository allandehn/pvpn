import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "oklch.js" as Oklch

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
  // Busy state (DC design): phase comes from `pvpn` stdout ("phase <name> [NAME]").
  readonly property bool busy: action.running
  property string phase: ""       // connecting|switching|reconnecting|checking|rollback|disconnecting
  property string phaseTarget: ""
  property string failedTarget: "" // "Couldn't connect to X" line; cleared on the next action
  property bool pulsing: false     // true 300 ms after busy starts, so fast results don't flash
  // No Omarchy reduced-motion setting is known; PVPN_REDUCED_MOTION=1 gives a static 0.6.
  readonly property bool reducedMotion: (Quickshell.env("PVPN_REDUCED_MOTION") || "") === "1"
  property real pulseOpacity: 1.0
  readonly property string busyTip: {
    var c = phaseTarget !== "" ? countryOf(phaseTarget) : (connecting ? countryOf(pending) : "")
    switch (phase) {
      case "switching": return "Switching to " + c + "…"
      case "reconnecting": return "Reconnecting to " + c + "…"
      case "checking": return "Checking " + c + "…"
      case "rollback": return "Switching back to " + c + "…"
      case "disconnecting": return "Disconnecting…"
    }
    return pending === "off" ? "Disconnecting…" : "Connecting to " + c + "…"
  }
  // Shown name, read once from manifest.json "displayName" (falls back to "VPN").
  property string displayName: "VPN"
  FileView {
    path: Qt.resolvedUrl("manifest.json").toString().replace(/^file:\/\//, "")
    onLoaded: { try { root.displayName = JSON.parse(text()).displayName || "VPN" } catch (e) {} }
  }
  // Off icon: md-security (U+F0483) with the strike and knockout gap taken from
  // md-shield_off (U+F099E), combined from the font's outlines (units, y down).
  // Box 834x918 units; the strike overhangs the shield's left edge exactly as in shield_off.
  component ShieldOff: Item {
    id: shieldOff
    property color color: "white"
    width: height * 834 / 918
    height: 16
    Shape {
      id: shieldShape
      anchors.fill: parent
      preferredRendererType: Shape.CurveRenderer
      antialiasing: true
      ShapePath {
        fillColor: shieldOff.color
        strokeWidth: -1
        strokeColor: "transparent"
        fillRule: ShapePath.WindingFill
        scale: Qt.size(shieldOff.width / 834, shieldOff.height / 918)
        PathSvg { path: "M 0 137 84 220.9 V 418 Q 84 531 133 636.5 Q 182 742 268 816.5 Q 354 891 459 918 Q 564 891 650 816.5 Q 657.9 809.6 665.5 802.5 L 607.1 744 Q 542.2 804.7 459 830 V 595.6 L 380 516.5 L 760 896 L 813 844 L 55 84Z M 459 0 195.7 117.9 258.5 180.9 459 92 V 381.9 L 535.8 459 H 750 Q 739.2 547.4 699.2 622.9 L 760.2 684 Q 773.6 661.1 785 636.5 Q 834 531 834 418 V 168Z M 322.4 459 H 168 V 304.8 L 322.4 459Z" }
      }
    }
  }
  Component { id: shieldOffIcon; ShieldOff { height: 15; color: root.foreground } }

  readonly property string glyphOn: "󰒃"
  readonly property string glyphOff: "󰦞"

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  // Binding dependencies stay live; conversion runs on colour changes, not hover/pulse.
  readonly property color dim: Oklch.dim(foreground)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  // Deliberately bypass Style.selectedFillFor: keep the live accent's OKLCH hue.
  readonly property color selectedFill: bar ? Oklch.hover(Commons.Color.accent, foreground) : "transparent"

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
    phase = ""
    phaseTarget = ""
    failedTarget = ""
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
  function pickConn(name) { if (busy) return; root.close(); if (name === active) reconnect(name); else connectTo(name) }

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
    stdout: SplitParser {
      onRead: function(line) {
        var p = String(line).trim().split(" ")
        if (p[0] !== "phase" || p.length < 2) return
        root.phase = p[1]
        root.phaseTarget = p.length > 2 ? p.slice(2).join(" ") : ""
      }
    }
    stderr: SplitParser { onRead: function(line) { action.errText += (action.errText ? " " : "") + String(line) } }
    onExited: function(code) {
      // Code 1 = connect failed; the CLI already notified and rolled back.
      if (code === 1 && root.connecting) root.failedTarget = root.pending
      if (code > 1) root.lastError = action.errText !== "" ? action.errText : "pvpn failed (exit " + code + ")"
      root.pending = ""
      root.phase = ""
      root.phaseTarget = ""
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

  // Pulse: the timer and animation only run while busy; idle costs nothing.
  onBusyChanged: {
    if (busy) { pulseDelay.restart(); return }
    pulseDelay.stop()
    pulsing = false
    if (failedTarget !== "") pulseOpacity = 1.0   // failure: snap back
    else settle.restart()                         // success: settle over 120 ms
  }
  Timer { id: pulseDelay; interval: 300; onTriggered: root.pulsing = true }
  SequentialAnimation {
    running: root.pulsing && !root.reducedMotion
    loops: Animation.Infinite
    NumberAnimation { target: root; property: "pulseOpacity"; from: 1.0; to: 0.4; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "pulseOpacity"; from: 0.4; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
  }
  onPulsingChanged: if (pulsing && reducedMotion) pulseOpacity = 0.6
  NumberAnimation { id: settle; target: root; property: "pulseOpacity"; to: 1.0; duration: 120 }

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

  // The pulse lives on a wrapper: WidgetButton binds its own opacity (dimmed) with a
  // smoothing Behavior, which swallowed the pulse when set on the button itself.
  Item {
    anchors.fill: parent
    opacity: root.pulseOpacity

    BarIconButton {
      id: button
      anchors.fill: parent
      bar: root.bar
      // Off: the same checkered shield, dimmed, with md-shield_off's own strike and gap.
      text: root.on ? root.glyphOn : ""
      iconComponent: root.on ? null : shieldOffIcon
      dimmed: !root.on
      tooltipText: root.opened ? "" : root.busy ? root.busyTip : (root.on ? root.displayName + " · " + root.countryOf(root.shown) : root.displayName + " · Off")
      onPressed: function(b) {
        if (b === Qt.RightButton) root.toggleVpn()
        else if (b === Qt.MiddleButton) root.refresh()
        else root.toggle()
      }
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
      onActivateRequested: if (!root.busy && root.cursorActive && root.cursorIndex < root.conns.length) root.pickConn(root.conns[root.cursorIndex].name)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.busy) return
        if (t === "t" || t === "T") { root.close(); root.toggleVpn() }
        else if ((t === "r" || t === "R") && root.active !== "") { root.close(); root.reconnect(root.active) }
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
                title: root.displayName
                meta: root.busy ? root.busyTip : (root.on ? root.countryOf(root.shown) + " · " + root.shown : "Off")
                foreground: root.foreground
                fontFamily: root.fontFamily
                iconComponent: Component {
                  Item {
                    implicitWidth: root.on ? heroGlyph.implicitWidth : heroOff.width
                    implicitHeight: heroGlyph.implicitHeight
                    opacity: root.on ? 1 : 0.45
                    Text { id: heroGlyph; visible: root.on; textFormat: Text.PlainText; text: root.glyphOn; color: root.foreground; font.family: Style.font.family; font.pixelSize: Math.round(Style.font.display) }
                    // md-security's ink is 918 of 1000 font units tall.
                    ShieldOff { id: heroOff; visible: !root.on; anchors.verticalCenter: parent.verticalCenter; height: Math.round(Style.font.display) * 0.918; color: root.foreground }
                  }
                }
                trailingControl: Component {
                  ToggleSwitch {
                    id: powerSwitch
                    checked: root.on
                    busy: root.busy
                    enabled: !root.busy
                    foreground: hero.foreground
                    onToggled: { root.close(); root.toggleVpn() }
                    PanelToolTip { visible: powerSwitch.containsMouse; text: root.on ? "Turn " + root.displayName + " off" : "Turn " + root.displayName + " on"; fontFamily: hero.fontFamily }
                  }
                }
              }
              Text {
                visible: root.failedTarget !== ""
                width: parent.width
                textFormat: Text.PlainText
                text: "Couldn't connect to " + root.countryOf(root.failedTarget)
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
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
    // Accent shows what's true: the real active profile, not the pending target.
    readonly property bool isActive: name !== "" && name === root.active
    readonly property bool isTarget: root.busy && name !== "" && name === root.pending

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
      id: caption
      visible: row.isTarget
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "Connecting…"
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: label
      anchors.left: parent.left
      anchors.right: row.isTarget ? caption.left : parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      opacity: row.isTarget ? root.pulseOpacity : 1.0
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.countryOf(row.name)
      color: !root.on && !row.isTarget ? root.dim : (row.isActive ? Commons.Color.accent : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: row.isActive && root.on
      elide: Text.ElideRight
    }
  }
}

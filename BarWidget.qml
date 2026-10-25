import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Ui
import qs.Commons

// Bar shield and panel for Proton VPN, in the same quiet style as the Displays
// panel:
//
//   Status      on/off switch, the server, its load and protocol, the exit IP
//   Connect     fastest, Secure Core, P2P, Tor, random; favorite countries;
//               a field that takes a country, a city or a server ID
//   Settings    NetShield and the kill switch
//
// Left click opens the panel, right click connects to `quickConnect` (the
// fastest server unless set) or disconnects. Everything goes through
// bin/pvpn and the official `protonvpn` CLI.
//
// Summon from a keybinding with:  omarchy-shell shell toggle proton-vpn
Panel {
  id: root

  moduleName: "proton-vpn"

  property var svc: null

  function bindService() {
    if (root.svc) return
    var host = root.bar && root.bar.shell ? root.bar.shell : null
    if (!host || typeof host.serviceFor !== "function") return
    root.svc = host.serviceFor("proton-vpn")
  }

  onBarChanged: bindService()

  // The service may mount after the bar, and is rebuilt on plugin hot-reload.
  Timer {
    interval: 250
    repeat: true
    running: !root.svc
    onTriggered: root.bindService()
  }

  readonly property var favorites: {
    var list = root.setting("favorites", ["CH", "NL", "US", "JP"])
    return Array.isArray(list) ? list.map(function(c) { return String(c).toUpperCase() }) : []
  }
  readonly property string quickConnect: String(root.setting("quickConnect", ""))

  readonly property bool installed: root.svc ? root.svc.installed : true
  readonly property bool connected: root.svc ? root.svc.connected : false
  readonly property bool connecting: root.svc ? root.svc.connecting : false
  readonly property bool working: root.svc ? root.svc.busy !== "" : false
  readonly property var details: root.svc ? root.svc.details : ({})
  readonly property var settingsMap: root.details.settings || ({})
  readonly property bool signedIn: root.details.signedIn === true
  // Until the first `details` run comes back, do not claim nobody is signed in.
  readonly property bool knowsAccount: root.details.installed !== undefined
  readonly property string server: root.svc ? root.svc.server : ""
  readonly property string query: search.text.trim()

  readonly property var matches: {
    var q = root.query.toLowerCase()
    if (q === "" || !root.svc) return []
    return root.svc.countries.filter(function(c) {
      return c.name.toLowerCase().indexOf(q) !== -1 || c.code.toLowerCase() === q
    }).slice(0, 6)
  }

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.62)
  readonly property color faint: Util.alpha(fg, 0.38)
  readonly property color solidBackground: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 0.96)
  readonly property string fontFamily: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family

  readonly property string icon: root.connected ? "󰕥" : (root.connecting ? "󰒘" : "󰦞")

  function countryName(code) {
    var list = root.svc ? root.svc.countries : []
    for (var i = 0; i < list.length; i++) if (list[i].code === code) return list[i].name
    return code
  }

  // A server ID (CH#242, CH-NL#1) goes as is, a two-letter code or a known
  // country name as --country, anything else as --city.
  function targetFor(text) {
    var t = String(text).trim()
    if (/^[A-Za-z]{2}(-[A-Za-z]{2})?#\d+$/.test(t)) return { args: [t.toUpperCase()], label: t.toUpperCase() }
    if (/^[A-Za-z]{2}$/.test(t)) return { args: ["--country", t.toUpperCase()], label: root.countryName(t.toUpperCase()) }
    var list = root.svc ? root.svc.countries : []
    for (var i = 0; i < list.length; i++)
      if (list[i].name.toLowerCase() === t.toLowerCase()) return { args: ["--country", list[i].code], label: list[i].name }
    return { args: ["--city", t], label: t }
  }

  function connectTo(args, label) {
    if (!root.svc) return
    search.text = ""
    keyCatcher.forceActiveFocus()
    root.svc.connect(args, label)
  }

  function quickToggle() {
    if (!root.svc) return
    if (!root.installed || (root.knowsAccount && !root.signedIn)) {
      root.open()
      return
    }
    var target = root.quickConnect !== "" ? root.targetFor(root.quickConnect) : { args: [], label: "Fastest server" }
    root.svc.toggle(target.args, target.label)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (!opened || !root.svc) return
    root.svc.refreshDetails()
    root.svc.loadCountries()
    search.text = ""
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.connected
    tooltipText: root.connected ? "Proton VPN: " + root.server
      : (root.connecting ? "Proton VPN: connecting…" : "Proton VPN: off")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.quickToggle()
      else root.toggle()
    }

    SequentialAnimation on opacity {
      running: root.connecting
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutQuad }
      NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutQuad }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(view.implicitHeight, Style.space(760))

    Rectangle {
      anchors.fill: parent
      anchors.margins: -panel.padding
      radius: Style.cornerRadius
      color: root.solidBackground
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: search.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.quickToggle()
      onTextKey: function(text) {
        if (text === "/") search.forceActiveFocus()
        else if (text === "r" && root.svc) root.svc.refreshDetails()
        else if (text === "d" && root.svc && root.connected) root.svc.disconnect()
        else if (text === "f") root.connectTo([], "Fastest server")
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: view.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: view
          width: flick.width
          spacing: Style.space(14)

          // ---------- Title and switch ----------
          Item {
            width: parent.width
            height: Math.max(title.implicitHeight, power.implicitHeight)

            Text {
              id: title
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Proton VPN"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            ToggleSwitch {
              id: power
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: root.installed && root.signedIn
              checked: root.connected
              busy: root.connecting || (root.svc && root.svc.busy === "disconnect")
              foreground: root.fg
              onToggled: root.quickToggle()
            }
          }

          // ---------- Not set up ----------
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: !root.installed || (root.knowsAccount && !root.signedIn)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: !root.installed
                ? "The Proton VPN CLI is not installed. Install it with:\nomarchy pkg add proton-vpn-cli"
                : "Sign in to your Proton account to connect. The CLI asks for your password and, if you use one, your 2FA code."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Button {
              visible: root.installed
              text: "Sign in…"
              iconText: "󰍂"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: {
                if (root.svc) root.svc.signIn()
                root.close()
              }
            }
          }

          // ---------- Status ----------
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.installed && root.signedIn

            Row {
              spacing: Style.space(14)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.icon
                color: root.connected ? Color.accent : root.faint
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: root.connected ? root.server
                    : root.connecting ? "Connecting to " + (root.svc && root.svc.busyLabel !== "" ? root.svc.busyLabel : "Proton VPN") + "…"
                    : "Not protected"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                }

                Text {
                  textFormat: Text.PlainText
                  visible: text !== ""
                  text: {
                    if (!root.connected) return root.details.exit && root.details.exit.ip
                      ? "Your IP " + root.details.exit.ip + " is visible" : ""
                    var bits = []
                    if (root.details.location) bits.push(root.details.location)
                    if (root.details.load) bits.push(root.details.load + "% load")
                    if (root.details.protocol) bits.push(root.details.protocol)
                    return bits.join(" · ")
                  }
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                Text {
                  textFormat: Text.PlainText
                  visible: root.connected && !!root.details.exit && root.details.exit.ip !== ""
                  text: root.details.exit ? "Exit IP " + root.details.exit.ip + " (" + root.details.exit.country + ")" : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Text {
              width: parent.width
              visible: !!root.svc && root.svc.lastError !== ""
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: root.svc ? root.svc.lastError : ""
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Connect ----------
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.installed && root.signedIn

            PanelSeparator { foreground: root.fg }

            PanelSectionHeader {
              text: "CONNECT"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: [
                  { label: "Fastest", icon: "󱐋", args: [] },
                  { label: "Secure Core", icon: "󰒃", args: ["--securecore"] },
                  { label: "P2P", icon: "󰁞", args: ["--p2p"] },
                  { label: "Tor", icon: "󰗹", args: ["--tor"] },
                  { label: "Random", icon: "󰒝", args: ["--random"] }
                ]

                Button {
                  required property var modelData
                  text: modelData.label
                  iconText: modelData.icon
                  bordered: true
                  enabled: !root.working
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.connectTo(modelData.args, modelData.label + " server")
                }
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)
              visible: root.favorites.length > 0

              Repeater {
                model: root.favorites

                Button {
                  required property var modelData
                  readonly property bool here: root.connected && root.server.indexOf(modelData) === 0
                  text: modelData
                  tooltipText: root.countryName(modelData)
                  selected: here
                  bordered: true
                  enabled: !root.working
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.caption
                  onClicked: root.connectTo(["--country", modelData], root.countryName(modelData))
                }
              }
            }

            TextField {
              id: search
              width: parent.width
              placeholderText: "Country, city or server (CH#242)"
              foreground: root.fg
              font.family: root.fontFamily
              enabled: !root.working
              Keys.onReturnPressed: {
                if (root.query === "") return
                if (root.matches.length === 1) root.connectTo(["--country", root.matches[0].code], root.matches[0].name)
                else {
                  var target = root.targetFor(root.query)
                  root.connectTo(target.args, target.label)
                }
              }
              Keys.onEscapePressed: {
                if (text !== "") text = ""
                else keyCatcher.forceActiveFocus()
              }
            }

            Repeater {
              model: root.matches

              Button {
                required property var modelData
                width: parent.width
                leftAlign: true
                text: modelData.name + "   " + modelData.code
                iconText: "󰇧"
                foreground: root.fg
                fontFamily: root.fontFamily
                onClicked: root.connectTo(["--country", modelData.code], modelData.name)
              }
            }
          }

          // ---------- Settings ----------
          Column {
            width: parent.width
            spacing: Style.space(8)
            visible: root.installed && root.signedIn && Object.keys(root.settingsMap).length > 0

            PanelSeparator { foreground: root.fg }

            PanelSectionHeader {
              text: "SETTINGS"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            SettingRow {
              label: "NetShield"
              visible: root.settingsMap["netshield"] !== undefined

              ButtonGroup {
                anchors.right: parent.right
                options: [
                  { value: "off", label: "Off" },
                  { value: "malware-only", label: "Malware", tooltip: "Block malware" },
                  { value: "malware-ads-trackers", label: "+ Ads", tooltip: "Block malware, ads and trackers" }
                ]
                value: String(root.settingsMap["netshield"] || "")
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                focusable: false
                spacing: Style.space(4)
                onChanged: function(value) { if (root.svc) root.svc.setFeature("netshield", value) }
              }
            }

            SettingRow {
              label: "Kill switch"
              visible: root.settingsMap["kill-switch"] !== undefined

              ToggleSwitch {
                anchors.right: parent.right
                checked: String(root.settingsMap["kill-switch"] || "off") !== "off"
                // The CLI only changes it while disconnected.
                interactive: !root.connected && !root.working
                opacity: interactive ? 1 : 0.5
                foreground: root.fg
                onToggled: if (root.svc) root.svc.setFeature("kill-switch", checked ? "off" : "standard")
              }
            }

            Text {
              width: parent.width
              visible: root.connected && root.settingsMap["kill-switch"] !== undefined
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: "Disconnect to change the kill switch."
              color: root.faint
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.signedIn
            textFormat: Text.PlainText
            text: "Signed in as " + root.details.account
            color: root.faint
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // Label on the left, control on the right.
  component SettingRow: Item {
    id: settingRow
    property string label: ""
    default property alias control: slot.data

    width: parent ? parent.width : 0
    height: Math.max(rowLabel.implicitHeight, slot.childrenRect.height)

    Text {
      id: rowLabel
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: settingRow.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Item {
      id: slot
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(settingRow.width * 0.7)
      height: childrenRect.height
    }
  }
}

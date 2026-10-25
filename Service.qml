import QtQuick
import Quickshell
import Quickshell.Io

// The VPN state, mounted once for the shell.
//
// Omarchy builds a bar per monitor; the tunnel state, the slower details from
// the CLI and whatever action is running live here so every bar agrees.
// bin/pvpn does the talking: `state` asks NetworkManager (cheap, run on every
// change `nmcli monitor` reports), `details` asks the Proton CLI and Proton's
// own location endpoint (slow, run when the panel opens or a tunnel changes).
Item {
  id: root
  width: 0
  height: 0
  visible: false

  // Host injection.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string ctl: Qt.resolvedUrl("bin/pvpn").toString().replace(/^file:\/\//, "")
  // Bundled, as a path: icon-theme names vary between themes, and one the
  // notification popup cannot find shows up as a checkerboard.
  readonly property string iconDir: Qt.resolvedUrl("icons").toString().replace(/^file:\/\//, "")
  readonly property string omarchyBin: (root.omarchyPath || Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/bin"

  property var state: ({ installed: true, connected: false, connecting: false, server: "", country: "" })
  property var details: ({})
  property var countries: []
  property bool detailsLoading: false
  property bool loaded: false

  // What is running right now: "", "connect", "disconnect" or "settings".
  property string busy: ""
  property string busyLabel: ""
  property string lastError: ""

  readonly property bool connected: root.state.connected === true
  readonly property bool connecting: root.state.connecting === true || root.busy === "connect"
  readonly property bool installed: root.state.installed !== false
  readonly property bool signedIn: root.details.signedIn === true
  readonly property string server: String(root.state.server || "")

  property bool _announced: false
  property bool _wasConnected: false

  function refresh() {
    if (stateProc.running) {
      stateAgain.restart()
      return
    }
    stateProc.running = true
  }

  function refreshDetails() {
    if (detailsProc.running) return
    root.detailsLoading = true
    detailsProc.running = true
  }

  function loadCountries() {
    if (root.countries.length > 0 || countriesProc.running) return
    countriesProc.running = true
  }

  function run(kind, label, args) {
    if (root.busy !== "") return
    root.busy = kind
    root.busyLabel = label
    root.lastError = ""
    actionProc.command = [root.ctl].concat(args)
    actionProc.running = true
  }

  // `target` is what the CLI takes: [] for the fastest server, ["--country",
  // "CH"], ["--city", "Zurich"], ["CH#242"], ["--securecore"], ...
  function connect(target, label) {
    root.run("connect", label || "Fastest server", ["connect"].concat(target || []))
  }

  function disconnect() {
    root.run("disconnect", "", ["disconnect"])
  }

  function toggle(target, label) {
    if (root.connected || root.connecting) root.disconnect()
    else root.connect(target, label)
  }

  function setFeature(feature, value) {
    root.run("settings", "", ["set", feature, value])
  }

  // Signing in asks for a password (and maybe a 2FA code), so it goes to a
  // terminal rather than through the panel.
  function signIn() {
    Quickshell.execDetached([root.omarchyBin + "/omarchy-launch-floating-terminal-with-presentation", root.ctl + " signin"])
    signinWatch.restart()
  }

  function notify(summary, body, icon) {
    Quickshell.execDetached(["notify-send", "-a", "Proton VPN", "-i", root.iconDir + "/" + icon + ".svg", summary, body || ""])
  }

  function parse(text, fallback) {
    try {
      return JSON.parse(String(text || ""))
    } catch (e) {
      return fallback
    }
  }

  Process {
    id: stateProc
    command: [root.ctl, "state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = root.parse(text, null)
        if (!next) return
        var was = root._wasConnected
        root.state = next
        root.loaded = true
        if (next.connected !== was) {
          root._wasConnected = next.connected === true
          // Not on startup: only a change seen while running is news.
          if (root._announced) {
            if (next.connected) root.notify("Connected", next.server, "connected")
            else root.notify("Disconnected", "Your traffic no longer goes through Proton VPN", "disconnected")
          }
          root.refreshDetails()
        }
        root._announced = true
      }
    }
  }

  Process {
    id: detailsProc
    command: [root.ctl, "details"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = root.parse(text, null)
        if (next) root.details = next
        root.detailsLoading = false
      }
    }
  }

  Process {
    id: countriesProc
    command: [root.ctl, "countries"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = root.parse(text, [])
        if (Array.isArray(next)) root.countries = next
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var result = root.parse(text, { ok: false, message: "No answer from protonvpn" })
        if (!result.ok) root.lastError = result.message || "protonvpn failed"
        var kind = root.busy
        root.busy = ""
        root.busyLabel = ""
        root.refresh()
        if (kind === "settings" || !result.ok) root.refreshDetails()
      }
    }
  }

  // NetworkManager says when anything changes; a burst of lines becomes one
  // `state` run.
  Process {
    id: monitorProc
    command: ["nmcli", "monitor"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { debounce.restart() }
    }
    onRunningChanged: if (!running) remonitor.restart()
  }

  Timer {
    id: debounce
    interval: 400
    onTriggered: root.refresh()
  }

  Timer {
    id: stateAgain
    interval: 300
    onTriggered: root.refresh()
  }

  Timer {
    id: remonitor
    interval: 10000
    onTriggered: monitorProc.running = true
  }

  // Belt and braces, in case a change slips past the monitor.
  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  // After the sign-in terminal opens, look again a few times until it is done.
  Timer {
    id: signinWatch
    property int tries: 0
    interval: 5000
    repeat: true
    onRunningChanged: if (running) tries = 0
    onTriggered: {
      root.refreshDetails()
      tries++
      if (root.signedIn || tries > 24) stop()
    }
  }

  Component.onCompleted: {
    root.refresh()
    root.refreshDetails()
  }
}

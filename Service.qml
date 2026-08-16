import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Model.js" as Model

// Watches windows open and close, and remembers enough about the ones that go
// to bring them back.
//
// The whole design falls out of one fact: Hyprland's closewindow event carries
// nothing but an address, and by the time it arrives the window's process is
// gone with it. Nothing can be read after the fact, so every window is captured
// as it opens and the description is kept until the window closes — at which
// point the description is all that is left of it.
//
// This runs as a service rather than inside the widget so that closing windows
// is still remembered when the widget is not in the bar.
Item {
  id: root

  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/recently-closed.json"
  readonly property string captureScript: Qt.resolvedUrl("scripts/capture-window").toString().replace(/^file:\/\//, "")

  readonly property int limit: 40

  // address -> the captured description, for windows currently open.
  property var live: ({})
  property var closed: []

  // Capturing shells out, so the requests are queued rather than fired at once:
  // opening a session restores a dozen windows in a second and a dozen
  // concurrent processes to describe them is a worse problem than a short wait.
  property var pending: []
  property string capturing: ""

  // A window that has just opened has not started what is inside it yet: a
  // terminal exists before its shell does, so reading it at that instant finds
  // an empty box and records a command with no directory. Waiting a moment
  // costs nothing — a window is not closed in the second after it opened, and
  // if it is, a bare command is the right answer anyway.
  function capture(address, settle) {
    if (address === "" || root.pending.indexOf(address) !== -1) return
    root.pending.push(address)
    if (settle) settleTimer.restart()
    else root.pumpQueue()
  }

  Timer {
    id: settleTimer
    interval: 1500
    onTriggered: root.pumpQueue()
  }

  // Driven by the process actually stopping, not by a flag set beside it.
  // Setting running = true while the previous run's flag has not fallen yet is
  // a no-op, so the queue stalled after its first window — which is why windows
  // that were already open when the shell started were never remembered.
  function pumpQueue() {
    if (captureProc.running || root.pending.length === 0) return
    root.capturing = root.pending.shift()
    captureProc.command = [root.captureScript, root.capturing]
    captureProc.running = true
  }

  function rememberCapture(json) {
    var entry = Model.parseEntry(json)
    if (entry) {
      var next = Object.assign({}, root.live)
      next[entry.address] = entry
      root.live = next
    }
    root.capturing = ""
  }

  // The window is already gone; this is the only moment its description is
  // worth anything.
  function remember(address) {
    var entry = root.live[address]
    if (!entry) return

    // Filtered as it closes rather than as it is shown: a window nobody wants
    // back should not take a slot in a list that only holds a dozen.
    if (Model.isIgnored(entry)) {
      var without = Object.assign({}, root.live)
      delete without[address]
      root.live = without
      return
    }

    var next = Object.assign({}, root.live)
    delete next[address]
    root.live = next

    root.closed = Model.withClosed(root.closed, entry, root.limit, Date.now())
    stateFile.setText(Model.serialize(root.closed))
  }

  // A window's directory moves under it — you open a terminal in home and cd
  // into a project — so the focused window is re-read on a slow timer. Slow,
  // because it is a process spawn, and the only window whose directory changes
  // is the one being typed in.
  Timer {
    interval: 20000
    running: true
    repeat: true
    onTriggered: {
      var focused = Hyprland.activeToplevel
      if (focused && focused.address) root.capture(focused.address)
    }
  }

  Connections {
    target: Hyprland

    function onRawEvent(event) {
      if (event.name === "openwindow") {
        // openwindow>>address,workspace,class,title
        root.capture(Model.normalizeAddress(String(event.data).split(",")[0]), true)
      } else if (event.name === "closewindow") {
        root.remember(Model.normalizeAddress(String(event.data)))
      }
    }
  }

  // One completion handler, not two. Exit and stream-end both fire, and when
  // they raced each other a capture's output was matched against whichever
  // window the queue had moved on to — so windows went missing from the list
  // with nothing to show for it. The stream ends whether or not the script
  // produced anything, so it is the one that decides.
  Process {
    id: captureProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.rememberCapture(text)
    }
    onRunningChanged: if (!running) root.pumpQueue()
  }

  // Windows that were already open when the shell started never raised an
  // openwindow event, and would be invisible to this until they were touched.
  Process {
    id: seedProc
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var addresses = Model.addressesFrom(text)
        for (var i = 0; i < addresses.length; i++) root.capture(addresses[i])
      }
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.closed = Model.parseClosed(text())
    onFileChanged: reload()
  }

  Component.onCompleted: seedProc.running = true
}

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The list of windows you closed, newest first. Clicking one puts it back on
// its workspace, in its directory, running what it ran.
Panel {
  id: root
  moduleName: "io.github.monswiklund.recently-closed"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state")
    + "/omarchy/recently-closed.json"
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int limit: setting("limit", 12)

  property var closed: []
  readonly property var shown: closed.slice(0, limit)

  // What the newest row is one keypress away from, if anything is bound to it.
  property string shortcut: ""

  // Re-read while the panel is open so "now" becomes "1m" under your eyes
  // rather than the moment you reopen the panel.
  property double clock: Date.now()

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.clock = Date.now()
  }

  property bool cursorActive: false
  property int cursorIndex: 0

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  readonly property string here: Hyprland.focusedWorkspace ? String(Hyprland.focusedWorkspace.id) : ""

  // Taken off the list as it is reopened. It is not closed any more, and a row
  // that reopens the same window twice is a row that lies the second time.
  function reopen(index, onto) {
    var entry = root.shown[index]
    if (!entry) return false

    Quickshell.execDetached(["hyprctl", "dispatch", Model.reopenExpr(entry, onto)])

    var next = root.closed.slice()
    next.splice(index, 1)
    root.closed = next
    stateFile.setText(Model.serialize(next))

    root.close()
    return true
  }

  function reopenLatest() {
    return root.reopen(0) ? "ok" : "empty"
  }

  function moveCursor(delta) {
    if (root.shown.length === 0) return
    var next = root.cursorIndex + delta
    root.cursorIndex = next < 0 ? root.shown.length - 1 : (next >= root.shown.length ? 0 : next)
  }

  function forget(index) {
    var next = Model.withoutIndex(root.closed, index)
    if (!next) return
    root.closed = next
    stateFile.setText(Model.serialize(next))
  }

  function clearAll() {
    root.closed = []
    stateFile.setText(Model.serialize([]))
  }

  onOpenedChanged: {
    if (!opened) return
    root.cursorActive = false
    root.cursorIndex = 0
    root.clock = Date.now()
    if (!bindsProc.running) bindsProc.running = true
  }

  Process {
    id: bindsProc
    command: ["hyprctl", "binds", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.shortcut = Model.shortcutFrom(text, "reopen last closed")
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.reopen(root.cursorIndex)
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.xl

        Item {
          width: parent.width
          implicitHeight: sectionHeader.implicitHeight

          PanelSectionHeader {
            id: sectionHeader
            anchors.left: parent.left
            text: "RECENTLY CLOSED"
            foreground: root.barForeground
            fontFamily: root.fontFamily
          }

          // The newest row is one keypress away, so the key belongs beside the
          // list rather than in a README nobody opens.
          Text {
            anchors.right: parent.right
            anchors.baseline: sectionHeader.baseline
            visible: root.shortcut !== "" && root.shown.length > 0
            text: root.shortcut + "  reopens the top"
            color: Qt.darker(root.barForeground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          visible: root.shown.length === 0
          width: parent.width
          text: root.shortcut === ""
            ? "Nothing closed yet. Windows you close land here — bind omarchy-shell recently-closed reopen to undo the last one without looking."
            : "Nothing closed yet. Windows you close land here, ready to come back."
          color: Qt.darker(root.barForeground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        ListView {
          id: list
          width: parent.width
          height: Math.min(contentHeight, Style.space(320))
          spacing: Style.spacing.sm
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          model: root.shown

          currentIndex: root.cursorIndex
          highlightFollowsCurrentItem: true
          preferredHighlightBegin: 0
          preferredHighlightEnd: height
          highlightRangeMode: ListView.ApplyRange

          delegate: ClosedRow {
            required property var modelData
            required property int index
            width: list.width
            height: implicitHeight
            entry: modelData
            rowIndex: index
          }
        }

        PanelSeparator {
          visible: root.shown.length > 0
          foreground: root.barForeground
        }

        CursorSurface {
          visible: root.shown.length > 0
          width: parent.width
          implicitHeight: clearLabel.implicitHeight + Style.spacing.md * 2
          foreground: root.barForeground
          accent: root.bar ? root.bar.urgent : Color.urgent

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.clearAll()
          }

          Text {
            id: clearLabel
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear the list"
            color: Qt.darker(root.barForeground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  component ClosedRow: CursorSurface {
    id: closedRow
    required property var entry
    required property int rowIndex

    implicitHeight: rowBody.implicitHeight + Style.spacing.md * 2
    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.barForeground
    accent: root.bar ? root.bar.foreground : Color.accent

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursorIndex = closedRow.rowIndex }
      onClicked: root.reopen(closedRow.rowIndex)
    }

    Row {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Style.spacing.md
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.spacing.md

      Column {
        width: parent.width - parent.spacing * 3 - ageLabel.implicitWidth - workspaceLabel.implicitWidth - Style.space(26)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.labelGap

        Text {
          width: parent.width
          text: Model.entryLabel(closedRow.entry)
          color: root.barForeground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: text !== ""
          text: {
            var parts = []
            var detail = Model.entryDetail(closedRow.entry, root.home)
            if (detail !== "") parts.push(detail)
            // What a click actually gives back, rather than what the window was.
            var tabs = Model.tabCount(closedRow.entry)
            if (tabs > 1) parts.push(tabs + " tabs")
            return parts.join("  ·  ")
          }
          color: Qt.darker(root.barForeground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: ageLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== ""
        text: Model.ageLabel(closedRow.entry.closedAt, root.clock)
        color: Qt.darker(root.barForeground, 1.9)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // The badge already says which workspace it came from, so it is the
      // honest place to say "not that one, this one".
      CursorSurface {
        id: workspaceLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: closedRow.entry.workspace !== ""
        implicitWidth: workspaceText.implicitWidth + Style.spacing.md
        implicitHeight: workspaceText.implicitHeight + Style.spacing.xs * 2
        foreground: root.barForeground
        accent: root.bar ? root.bar.foreground : Color.accent
        current: closedRow.entry.workspace === root.here

        MouseArea {
          id: badgeMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.cursorIndex = closedRow.rowIndex }
          onClicked: root.reopen(closedRow.rowIndex, root.here)
        }

        PanelToolTip {
          visible: badgeMouse.containsMouse && closedRow.entry.workspace !== root.here
          text: "Open on workspace " + root.here + " instead"
          fontFamily: root.fontFamily
        }

        Text {
          id: workspaceText
          anchors.centerIn: parent
          text: "󰍹 " + closedRow.entry.workspace
          color: Qt.darker(root.barForeground, 1.7)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // Clearing the whole list to be rid of one row is a blunt instrument.
      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        visible: rowMouse.containsMouse || badgeMouse.containsMouse || forgetMouse.containsMouse
        iconText: "󰅖"
        tooltipText: "Forget this one"
        foreground: root.barForeground
        hoverColor: root.bar ? root.bar.urgent : Color.urgent
        fontFamily: root.fontFamily
        onClicked: root.forget(closedRow.rowIndex)

        MouseArea {
          id: forgetMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.NoButton
        }
      }
    }
  }
}

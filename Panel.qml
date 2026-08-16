import QtQuick
import Quickshell
import Quickshell.Io
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

  property bool cursorActive: false
  property int cursorIndex: 0

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  // Taken off the list as it is reopened. It is not closed any more, and a row
  // that reopens the same window twice is a row that lies the second time.
  function reopen(index) {
    var entry = root.shown[index]
    if (!entry) return false

    Quickshell.execDetached(["hyprctl", "dispatch", Model.reopenExpr(entry)])

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

  function clearAll() {
    root.closed = []
    stateFile.setText(Model.serialize([]))
  }

  onOpenedChanged: {
    if (!opened) return
    root.cursorActive = false
    root.cursorIndex = 0
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

        PanelSectionHeader {
          text: "RECENTLY CLOSED"
          foreground: root.barForeground
          fontFamily: root.fontFamily
        }

        Text {
          visible: root.shown.length === 0
          width: parent.width
          text: "Nothing closed yet. Windows you close land here, ready to come back."
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
        width: parent.width - parent.spacing - workspaceLabel.implicitWidth
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
          text: Model.entryDetail(closedRow.entry, root.home)
          color: Qt.darker(root.barForeground, 1.6)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: workspaceLabel
        anchors.verticalCenter: parent.verticalCenter
        visible: closedRow.entry.workspace !== ""
        text: "󰍹 " + closedRow.entry.workspace
        color: Qt.darker(root.barForeground, 1.7)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

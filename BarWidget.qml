import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry point. The tracking lives in Service.qml so that windows are still
// remembered when this widget is not in the bar; this only shows the result.
BarWidget {
  id: root
  moduleName: "io.github.monswiklund.recently-closed"

  readonly property string icon: setting("icon", "󰕌")

  // The icon looks the same whether or not there is anything to undo, so a dot
  // says there is. A dot rather than a count: a number in a bar is noise, and
  // the answer you want at a glance is "yes" or "no", not "eleven".
  readonly property bool hasClosed: panelLoader.item ? panelLoader.item.shown.length > 0 : false

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function reopenLatest() { return panelLoader.item ? panelLoader.item.reopenLatest() : "unavailable" }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "recently-closed"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }

    // The whole point, on a keybinding: undo the last close without looking.
    function reopen(): string { return root.reopenLatest() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    fontSize: Style.font.icon
    tooltipText: "Recently closed"
    onPressed: function (b) { if (b === Qt.LeftButton) root.togglePanel() }

    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: Style.space(3)
      anchors.topMargin: Style.space(4)
      width: Style.space(4)
      height: width
      radius: width / 2
      visible: root.hasClosed && !root.opened
      color: root.bar ? root.bar.foreground : Color.foreground
      opacity: 0.7
    }
  }
}

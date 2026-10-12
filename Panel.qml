import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "org.tenseventyseven.acer-wmi-ext"
  ipcTarget: "org.tenseventyseven.acer-wmi-ext"
  manageIpc: false

  property bool helperReady: false
  property bool driverPresent: false
  property int healthMode: -2
  property int calibrationMode: -2
  property int systemControlMode: -2
  property int usbChargeMode: -2
  property int usbChargeLimit: -2
  property bool usbChargeSupported: false
  property var profiles: []
  property string activeProfile: ""
  property string lastError: ""
  property bool confirmingCalibration: false
  property bool cursorActive: false
  property int cursorIndex: -1
  property int confirmationIndex: 0

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dimForeground: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var actions: buildActions()
  readonly property var profileActions: actionsFor("profile")
  readonly property var driverActions: actionsFor("driver")
  readonly property var healthActions: actionsFor("health")
  readonly property string pluginDirectory: decodeURIComponent(
    Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  )
  readonly property var calibrationActions: actionsFor("calibration")
  readonly property var usbActions: actionsFor("usb")
  readonly property var usbLimitActions: actionsFor("usb-limit")

  function applyStatus(raw) {
    var status = Model.parseStatus(raw)
    driverPresent = status.driverPresent
    healthMode = status.healthMode
    calibrationMode = status.calibrationMode
    systemControlMode = status.systemControlMode
    usbChargeMode = status.usbChargeMode
    usbChargeLimit = status.usbChargeLimit
    usbChargeSupported = status.usbChargeSupported
  }

  function applyProfiles(raw) {
    var result = Model.parseProfiles(raw)
    profiles = result.profiles
    activeProfile = result.activeProfile
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function buildActions() {
    var result = []

    if (helperReady && !driverPresent) {
      result.push({
        id: "driver:load",
        kind: "driver",
        label: "Load driver",
        active: false
      })
    }

    if (driverPresent && systemControlMode >= 1 && systemControlMode <= 3) {
      for (var i = 0; i < profiles.length; i++) {
        var profile = String(profiles[i])
        result.push({
          id: "profile:" + profile,
          kind: "profile",
          value: profile,
          label: Model.profileLabel(profile),
          active: activeProfile === profile
        })
      }
    }

    if (Model.isSupported(healthMode)) {
      result.push({
        id: "health",
        kind: "health",
        value: healthMode === 1 ? 0 : 1,
        label: calibrationMode === 1
          ? "Battery health limit locked during calibration"
          : (calibrationMode === -2
            ? "Battery health control unavailable"
            : (healthMode === 1 ? "Disable 80% battery charge limit" : "Enable 80% battery charge limit")),
        active: healthMode === 1,
        enabled: calibrationMode !== 1 && calibrationMode !== -2
      })
    }

    if (Model.isSupported(calibrationMode)) {
      result.push({
        id: "calibration",
        kind: "calibration",
        value: calibrationMode === 1 ? 0 : 1,
        label: calibrationMode === 1 ? "Stop battery calibration" : "Start battery calibration…",
        active: calibrationMode === 1
      })
    }

    if (usbChargeSupported && Model.isSupported(usbChargeMode)) {
      result.push({
        id: "usb",
        kind: "usb",
        value: usbChargeMode === 1 ? 0 : 1,
        label: usbChargeMode === 1 ? "Disable USB charging" : "Enable USB charging (30% limit)",
        active: usbChargeMode === 1
      })

      if (usbChargeMode === 1) {
        var limits = [10, 20, 30]
        for (var j = 0; j < limits.length; j++) {
          result.push({
            id: "usb-limit:" + limits[j],
            kind: "usb-limit",
            value: limits[j],
            label: "USB charge limit: " + limits[j] + "%",
            active: usbChargeLimit === limits[j]
          })
        }
      }
    }

    return result
  }

  function actionsFor(kind) {
    var result = []
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].kind === kind) result.push(actions[i])
    }
    return result
  }

  function actionIndex(actionId) {
    for (var i = 0; i < actions.length; i++) {
      if (actions[i].id === actionId) return i
    }
    return -1
  }

  function performAction(action) {
    if (!action || action.enabled === false) return
    lastError = ""

    if (action.kind === "driver") {
      if (driverPresent || !helperReady || driverInstallerProc.running) return
      driverInstallerProc.command = Model.driverInstallerCommand(pluginDirectory)
      driverInstallerProc.running = true
      return
    }

    if (action.kind === "profile") {
      if (profileSetProc.running) return
      profileSetProc.command = ["omarchy-powerprofiles-set", "autodetect", action.value]
      profileSetProc.running = true
      return
    }

    if (action.kind === "calibration" && action.value === 1) {
      confirmingCalibration = true
      confirmationIndex = 1
      return
    }

    var operation = ""
    if (action.kind === "health") operation = "health-mode"
    else if (action.kind === "calibration") operation = "calibration-mode"
    else if (action.kind === "usb") operation = "usb-charge-mode"
    else if (action.kind === "usb-limit") operation = "usb-charge-limit"

    if (operation !== "") runPrivilegedAction(operation, action.value)
  }

  function runPrivilegedAction(operation, value) {
    if (actionProc.running) return
    lastError = ""
    actionProc.command = ["pkexec", "/usr/local/bin/acer-wmi-ext-omarchy", "set", operation, String(value)]
    actionProc.running = true
  }

  function finishPrivilegedAction(exitCode) {
    if (exitCode !== 0) {
      var detail = String(actionStderr.text || "").trim()
      lastError = detail !== "" ? detail : "The request was cancelled or could not be completed."
    }
    refresh()
  }

  function finishProfileAction(exitCode) {
    if (exitCode !== 0) {
      var detail = String(profileStderr.text || "").trim()
      lastError = detail !== "" ? detail : "Could not change the power profile."
    }
    refresh()
  }

  function confirmCalibration() {
    confirmingCalibration = false
    runPrivilegedAction("calibration-mode", 1)
  }

  function moveCursor(dx, dy) {
    if (confirmingCalibration) {
      confirmationIndex = Math.max(0, Math.min(1, confirmationIndex + (dx !== 0 ? dx : dy)))
      cursorActive = true
      return
    }

    if (actions.length === 0) return
    var delta = dx !== 0 ? dx : dy
    cursorIndex = cursorActive ? Math.max(0, Math.min(actions.length - 1, cursorIndex + delta)) : 0
    cursorActive = true
  }

  function activateCursor() {
    if (confirmingCalibration) {
      if (confirmationIndex === 0) confirmCalibration()
      else confirmingCalibration = false
      return
    }
    if (!cursorActive && actions.length > 0) cursorIndex = 0
    if (cursorIndex >= 0 && cursorIndex < actions.length) performAction(actions[cursorIndex])
  }

  function fanProfileText() {
    return Model.fanModeLabel(systemControlMode)
  }

  onOpenedChanged: {
    if (opened) {
      confirmingCalibration = false
      cursorActive = false
      cursorIndex = -1
      refresh()
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: "org.tenseventyseven.acer-wmi-ext"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  Process {
    id: statusProc
    command: ["acer-wmi-ext-omarchy", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root.helperReady = exitCode === 0
      if (exitCode !== 0) {
        var detail = String(statusStderr.text || "").trim()
        root.lastError = detail !== "" ? detail : "The Acer control helper is not installed."
      }
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyProfiles(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.profiles = []
    }
  }

  Process {
    id: profileSetProc
    stderr: StdioCollector { id: profileStderr; waitForEnd: true }
    onExited: function(exitCode) { root.finishProfileAction(exitCode) }
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) { root.finishPrivilegedAction(exitCode) }
  }

  Process {
    id: driverInstallerProc
    onExited: function(exitCode) { root.refresh() }
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "A"
    active: root.opened
    tooltipText: "Acer WMI controls"
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(Math.min(flickable.contentHeight, Style.space(560)), Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: flickable
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight

        Column {
          id: content
          width: flickable.width
          spacing: Style.space(12)

          Column {
            width: parent.width
            spacing: Style.space(3)
            Text {
              text: "Acer WMI Ext"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.driverPresent
                ? "Fan profile: " + root.fanProfileText()
                : "Hardware driver status"
              color: root.dimForeground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
              width: parent.width
            }
          }

          Text {
            visible: !root.helperReady
            text: "Install the control helper by running ./scripts/install-helper.sh from the plugin folder."
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            width: parent.width
          }

          Text {
            visible: root.helperReady && !root.driverPresent
            text: "acer-wmi-ext is not loaded. Open a terminal to build and load it for this boot?"
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            width: parent.width
          }

          Button {
            visible: root.driverActions.length > 0
            width: parent.width
            text: "Load driver"
            foreground: root.foreground
            fontFamily: root.fontFamily
            hasCursor: root.cursorActive && root.cursorIndex === root.actionIndex("driver:load")
            enabled: !driverInstallerProc.running
            onClicked: root.performAction(root.driverActions[0])
            onHovered: function(isHovered) {
              if (isHovered) {
                root.cursorActive = true
                root.cursorIndex = root.actionIndex("driver:load")
              }
            }
          }

          Text {
            visible: root.helperReady && root.driverPresent && root.actions.length === 0
            text: "No controls are exposed by this laptop or power-profile setup."
            color: root.dimForeground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            width: parent.width
          }

          Column {
            visible: root.profileActions.length > 0
            width: parent.width
            spacing: Style.space(6)
            PanelSectionHeader {
              text: "FAN PROFILE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.profileActions
              Button {
                required property var modelData
                width: parent.width
                text: Model.profileLabel(modelData.value)
                foreground: root.foreground
                fontFamily: root.fontFamily
                active: modelData.active
                hasCursor: root.cursorActive && root.cursorIndex === root.actionIndex(modelData.id)
                enabled: !actionProc.running && !profileSetProc.running
                onClicked: root.performAction(modelData)
                onHovered: function(isHovered) {
                  if (isHovered) {
                    root.cursorActive = true
                    root.cursorIndex = root.actionIndex(modelData.id)
                  }
                }
              }
            }
          }

          Column {
            visible: root.healthActions.length > 0
            width: parent.width
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "BATTERY HEALTH"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.healthActions
              Button {
                required property var modelData
                width: parent.width
                text: modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
                active: modelData.active
                hasCursor: root.cursorActive && root.cursorIndex === root.actionIndex(modelData.id)
                enabled: modelData.enabled !== false && !actionProc.running && !profileSetProc.running
                onClicked: root.performAction(modelData)
                onHovered: function(isHovered) {
                  if (isHovered) {
                    root.cursorActive = true
                    root.cursorIndex = root.actionIndex(modelData.id)
                  }
                }
              }
            }
          }

          Column {
            visible: root.calibrationActions.length > 0
            width: parent.width
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "BATTERY CALIBRATION"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.calibrationActions
              Button {
                required property var modelData
                width: parent.width
                text: modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
                active: modelData.active
                hasCursor: root.cursorActive && root.cursorIndex === root.actionIndex(modelData.id)
                enabled: !actionProc.running && !profileSetProc.running
                onClicked: root.performAction(modelData)
                onHovered: function(isHovered) {
                  if (isHovered) {
                    root.cursorActive = true
                    root.cursorIndex = root.actionIndex(modelData.id)
                  }
                }
              }
            }
          }

          Column {
            visible: root.usbActions.length > 0
            width: parent.width
            spacing: Style.space(6)
            PanelSeparator { foreground: root.foreground }
            PanelSectionHeader {
              text: "USB CHARGING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            Repeater {
              model: root.usbActions
              Button {
                required property var modelData
                width: parent.width
                text: modelData.label
                foreground: root.foreground
                fontFamily: root.fontFamily
                active: modelData.active
                hasCursor: root.cursorActive && root.cursorIndex === root.actionIndex(modelData.id)
                enabled: !actionProc.running && !profileSetProc.running
                onClicked: root.performAction(modelData)
                onHovered: function(isHovered) {
                  if (isHovered) {
                    root.cursorActive = true
                    root.cursorIndex = root.actionIndex(modelData.id)
                  }
                }
              }
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.usbLimitActions
                Button {
                  required property var modelData
                  width: (parent.width - parent.spacing * 2) / 3
                  text: String(modelData.value) + "%"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  active: modelData.active
                  hasCursor: root.cursorActive && root.cursorIndex === root.actionIndex(modelData.id)
                  enabled: !actionProc.running && !profileSetProc.running
                  onClicked: root.performAction(modelData)
                  onHovered: function(isHovered) {
                    if (isHovered) {
                      root.cursorActive = true
                      root.cursorIndex = root.actionIndex(modelData.id)
                    }
                  }
                }
              }
            }
          }

          Column {
            visible: root.confirmingCalibration
            width: parent.width
            spacing: Style.space(8)
            PanelSeparator { foreground: root.foreground }
            Text {
              width: parent.width
              text: "Starting calibration disables the 80% battery health limit. The cycle can take hours and will charge to 100%, discharge, then recharge. Connect AC power and leave the laptop unused. The driver does not detect completion; disable calibration manually when the cycle finishes."
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }
            Row {
              width: parent.width
              spacing: Style.space(6)
              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Start calibration"
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.confirmationIndex === 0
                enabled: !actionProc.running
                onClicked: root.confirmCalibration()
                onHovered: function(isHovered) { if (isHovered) { root.cursorActive = true; root.confirmationIndex = 0 } }
              }
              Button {
                width: (parent.width - parent.spacing) / 2
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                hasCursor: root.cursorActive && root.confirmationIndex === 1
                onClicked: root.confirmingCalibration = false
                onHovered: function(isHovered) { if (isHovered) { root.cursorActive = true; root.confirmationIndex = 1 } }
              }
            }
          }

          Text {
            visible: root.lastError !== ""
            text: root.lastError
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            width: parent.width
          }
        }
      }
    }
  }
}

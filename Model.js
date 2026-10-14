function parseStatus(raw) {
  var result = {
    driverPresent: false,
    healthMode: -2,
    calibrationMode: -2,
    systemControlMode: -2,
    usbChargeMode: -2,
    usbChargeLimit: -2,
    usbChargeSupported: false
  }
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var separator = lines[i].indexOf("=")
    if (separator <= 0) continue

    var key = lines[i].substring(0, separator).trim()
    var value = lines[i].substring(separator + 1).trim()
    if (key === "driver_present") result.driverPresent = value === "1"
    else if (key === "health_mode") result.healthMode = parseInteger(value, -2)
    else if (key === "calibration_mode") result.calibrationMode = parseInteger(value, -2)
    else if (key === "system_control_mode") result.systemControlMode = parseInteger(value, -2)
    else if (key === "usb_charge_mode") result.usbChargeMode = parseInteger(value, -2)
    else if (key === "usb_charge_limit") result.usbChargeLimit = parseInteger(value, -2)
    else if (key === "usb_charge_supported") result.usbChargeSupported = value === "1"
  }

  return result
}

function parseInteger(value, fallback) {
  var parsed = parseInt(value, 10)
  return isNaN(parsed) ? fallback : parsed
}

function parseProfiles(raw) {
  var result = { profiles: [], activeProfile: "" }
  var allowed = ["power-saver", "balanced", "performance"]
  var lines = String(raw || "").split("\n")

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    var name = parts[0].trim()
    if (allowed.indexOf(name) === -1 || result.profiles.indexOf(name) !== -1) continue
    result.profiles.push(name)
    if (parts[1] === "1") result.activeProfile = name
  }

  return result
}

function isSupported(value) {
  return value === 0 || value === 1
}

function driverIconOpacity(driverPresent) {
  return driverPresent ? 1 : 0.45
}

function profileLabel(name) {
  if (name === "power-saver") return "Quiet"
  if (name === "balanced") return "Balanced"
  if (name === "performance") return "Performance"
  return String(name || "Unknown")
}

function fanModeLabel(mode) {
  if (mode === 1) return "Balanced"
  if (mode === 2) return "Quiet"
  if (mode === 3) return "Performance"
  return "Unavailable"
}

function driverInstallerCommand(pluginDirectory) {
  return [
    "xdg-terminal-exec",
    "--hold",
    "--dir=" + pluginDirectory,
    "--",
    "./scripts/install-driver.sh"
  ]
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    parseProfiles: parseProfiles,
    isSupported: isSupported,
    driverIconOpacity: driverIconOpacity,
    profileLabel: profileLabel,
    fanModeLabel: fanModeLabel,
    driverInstallerCommand: driverInstallerCommand
  }
}

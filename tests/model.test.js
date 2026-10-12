const assert = require("node:assert/strict")
const Model = require("../Model.js")

const status = Model.parseStatus([
  "driver_present=1",
  "health_mode=1",
  "calibration_mode=0",
  "system_control_mode=2",
  "usb_charge_mode=1",
  "usb_charge_limit=30",
  "usb_charge_supported=1"
].join("\n"))

assert.equal(status.driverPresent, true)
assert.equal(status.healthMode, 1)
assert.equal(status.calibrationMode, 0)
assert.equal(status.systemControlMode, 2)
assert.equal(status.usbChargeMode, 1)
assert.equal(status.usbChargeLimit, 30)
assert.equal(status.usbChargeSupported, true)

const unavailable = Model.parseStatus("driver_present=0\nhealth_mode=-1\n")
assert.equal(unavailable.driverPresent, false)
assert.equal(unavailable.healthMode, -1)
assert.equal(unavailable.calibrationMode, -2)
assert.equal(Model.isSupported(0), true)
assert.equal(Model.isSupported(1), true)
assert.equal(Model.isSupported(-1), false)

const profiles = Model.parseProfiles("performance\t0\nbalanced\t1\npower-saver\t0\nunknown\t0\n")
assert.deepEqual(profiles.profiles, ["performance", "balanced", "power-saver"])
assert.equal(profiles.activeProfile, "balanced")
assert.equal(Model.profileLabel("power-saver"), "Quiet")
assert.equal(Model.fanModeLabel(3), "Performance")
assert.equal(Model.fanModeLabel(-1), "Unavailable")

assert.equal(typeof Model.driverInstallerCommand, "function")
assert.deepEqual(Model.driverInstallerCommand("/plugin folder"), [
  "xdg-terminal-exec",
  "--hold",
  "--dir=/plugin folder",
  "--",
  "./scripts/install-driver.sh"
])

console.log("Model tests passed")

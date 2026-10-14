const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const panel = fs.readFileSync(path.join(__dirname, "../Panel.qml"), "utf8")
const markStart = panel.indexOf("  Item {\n    id: mark\n")
const markEnd = panel.indexOf("\n  }\n\n  KeyboardPanel", markStart)
assert.notEqual(markStart, -1)
assert.notEqual(markEnd, -1)
assert.match(panel.slice(markStart, markEnd), /anchors\.centerIn: parent/)
assert.doesNotMatch(panel.slice(markStart, markEnd), /anchors\.horizontalCenterOffset/)

assert.match(panel, /text: ""\s+keepSpace: true\s+hasVisualContent: true/)

assert.match(panel, /readonly property real openPanelIndicatorWidth: markSize/)

console.log("Layout tests passed")

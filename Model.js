.pragma library

// Pure logic for Recently Closed: parsing what the capture script produced,
// keeping the list of closed windows, and building the Lua that brings one
// back. No QML types here, so every rule is testable with plain node — see
// scripts/test-model.

// Hyprland reports a window's address two ways: `hyprctl clients` writes
// "0x55…" and the event socket writes "55…" for the same window. Everything
// here speaks the prefixed form, so the bare one is converted on the way in —
// otherwise a close event never finds what its own open event stored.
function normalizeAddress(value) {
  var address = String(value || "").trim()
  if (address === "") return ""
  return address.indexOf("0x") === 0 ? address : "0x" + address
}

function parseEntry(json) {
  var entry
  try {
    entry = JSON.parse(String(json || "").trim())
  } catch (e) {
    return null
  }
  if (!entry || typeof entry !== "object") return null

  var cmd = String(entry.cmd || "").trim()
  var address = normalizeAddress(entry.address)
  if (cmd === "" || address === "") return null

  return {
    address: address,
    cmd: cmd,
    "class": String(entry["class"] || ""),
    title: String(entry.title || ""),
    workspace: entry.workspace === undefined || entry.workspace === null ? "" : String(entry.workspace),
    floating: entry.floating === true,
    at: String(entry.at || ""),
    size: String(entry.size || "")
  }
}

function addressesFrom(json) {
  var list
  try {
    list = JSON.parse(json || "[]")
  } catch (e) {
    return []
  }
  if (!Array.isArray(list)) return []

  var addresses = []
  for (var i = 0; i < list.length; i++) {
    var address = normalizeAddress((list[i] && list[i].address) || "")
    if (address !== "") addresses.push(address)
  }
  return addresses
}

// --------------------------------------------------------------- ignored
//
// Some windows are not closed so much as finished. The screensaver dismisses
// itself the moment you touch the keyboard, and offering to bring it back is
// offering to blank your screen — the one thing you just told it not to do.
//
// Kept deliberately short. Omarchy's other own windows — btop, a terminal, the
// about box — are windows you might genuinely want back, so only what closes
// itself belongs here.
function ignoredClasses() {
  return ["org.omarchy.screensaver"]
}

function isIgnored(entry) {
  var name = String((entry && entry["class"]) || "").toLowerCase()
  if (name === "") return false

  var ignored = ignoredClasses()
  for (var i = 0; i < ignored.length; i++)
    if (name === ignored[i].toLowerCase()) return true
  return false
}

// ------------------------------------------------------------------ list
//
// Newest first, capped, and never two rows for the same thing. Closing four
// terminals in the same directory should offer that directory once — the list
// is for getting something back, not for counting how often you lost it.
//
// "The same thing" cannot be the command alone. A browser runs every window in
// one process, so two windows share a command down to the character and only
// their titles tell them apart; without the title in the identity, closing one
// window collapses onto the one still open and the list claims you closed
// something you did not.
function sameThing(a, b) {
  return a.cmd === b.cmd
    && String(a.workspace) === String(b.workspace)
    && String(a.title || "") === String(b.title || "")
}

function withClosed(list, entry, limit) {
  var next = [{
    cmd: entry.cmd,
    "class": entry["class"],
    title: entry.title,
    workspace: entry.workspace,
    floating: entry.floating,
    at: entry.at,
    size: entry.size,
    closedAt: entry.closedAt || 0
  }]

  for (var i = 0; i < list.length; i++) {
    if (sameThing(list[i], entry)) continue
    next.push(list[i])
    if (next.length >= limit) break
  }
  return next
}

function parseClosed(text) {
  var data
  try {
    data = JSON.parse(String(text || "").trim() || "[]")
  } catch (e) {
    return []
  }
  if (!Array.isArray(data)) return []

  var out = []
  for (var i = 0; i < data.length; i++) {
    var row = data[i]
    if (!row || typeof row !== "object") continue
    if (String(row.cmd || "").trim() === "") continue
    out.push({
      cmd: String(row.cmd),
      "class": String(row["class"] || ""),
      title: String(row.title || ""),
      workspace: row.workspace === undefined || row.workspace === null ? "" : String(row.workspace),
      floating: row.floating === true,
      at: String(row.at || ""),
      size: String(row.size || "")
    })
  }
  return out
}

function serialize(list) {
  return JSON.stringify(list, null, 2) + "\n"
}

// -------------------------------------------------------------- reopening

function luaString(value) {
  return '"' + String(value)
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n") + '"'
}

// Back where it was, and without dragging the screen there. A floating window
// arrives already placed; a tiled one takes its place from the layout, because
// no dispatcher rebuilds a split tree.
// `onto` overrides where it lands. A closed window usually wants to come back
// where it was, but not always: after you have moved on, the workspace you are
// standing in is the one you meant.
function reopenExpr(entry, onto) {
  var workspace = onto === undefined || onto === null || String(onto) === ""
    ? entry.workspace
    : String(onto)

  var rules = []
  if (workspace !== "" && Number(workspace) > 0)
    rules.push("workspace = " + luaString(workspace + " silent"))

  if (entry.floating) {
    rules.push("float = true")
    if (entry.size) rules.push("size = " + luaString(entry.size.replace(/,/g, " ")))
    if (entry.at) rules.push("move = " + luaString(entry.at.replace(/,/g, " ")))
  }

  if (rules.length === 0) return "hl.dsp.exec_cmd(" + luaString(entry.cmd) + ")"
  return "hl.dsp.exec_cmd(" + luaString(entry.cmd) + ", { " + rules.join(", ") + " })"
}

// --------------------------------------------------------------- labels

// A path said the way a person says it. Two trailing components is right for a
// project buried deep — "sportson/service-system" — but wrong just under home,
// where it surfaces the username and reads like a filesystem root rather than a
// folder you chose. Anything inside home keeps the tilde it deserves.
function shortenPath(dir, home) {
  var path = String(dir || "").replace(/\/+$/, "")
  if (path === "") return ""
  if (home && path === home) return "~"

  if (home && path.indexOf(home + "/") === 0) {
    var relative = path.slice(home.length + 1)
    if (relative.split("/").length <= 2) return "~/" + relative
  }

  var parts = path.split("/")
  return parts.length <= 2 ? parts.join("/") : parts.slice(-2).join("/")
}

// What the window was, said the way you would say it. The command a terminal
// ran names the window better than the terminal does.
function entryLabel(entry) {
  var exec = String(entry.cmd).match(/\s-e\s+(.+)$/)
  if (exec) return exec[1]
  return String(entry.cmd).split(/\s+/)[0].split("/").pop()
}

function entryDetail(entry, home) {
  var match = String(entry.cmd).match(/--(?:working-directory|directory|cwd)[= ](\S+)/)
  if (!match) return entry.title || ""

  var dir = match[1].replace(/\\ /g, " ")
  if (home && dir === home) return "~"
  return shortenPath(dir, home)
}

# Recently Closed

Reopen a window you just closed — back on its workspace, in its directory,
running what it was running. An Omarchy Quattro bar widget.

## Requirements

| Needed for | What |
|---|---|
| Everything | Omarchy **Quattro** — the shell plugin system does not exist before it |
| Capturing | `hyprctl` and `jq`, both already on an Omarchy install |
| Browser tabs | `python3`; without it browsers come back empty |

No other dependencies, nothing is downloaded at runtime, and nothing runs with
`sudo`. The plugin writes one file of its own,
`~/.local/state/omarchy/recently-closed.json`, and edits nothing else you own.

Terminal support is a small table: **ghostty, foot and alacritty** are verified.
An unrecognised terminal is still remembered, it just comes back without its
directory rather than with flags that would break it.

## Install

```sh
omarchy plugin add https://github.com/monswiklund/omarchy-recently-closed.git --enable
```

It lands on the left of the bar. Somewhere else:

```sh
omarchy plugin enable io.github.monswiklund.recently-closed --section right
```

How many windows it remembers — 3 to 40, 12 by default — and the bar icon are
widget settings, edited where every other widget's are.

Installed by hand instead:

```sh
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.monswiklund.recently-closed
```

## How it can possibly know

Hyprland's close event carries nothing but an address:

```
openwindow>>563fe6dc84a0,3,com.mitchellh.ghostty,Ghostty
closewindow>>563fe6dc84a0
```

By the time that arrives the window's process is gone, and `/proc` has nothing
left to read. So nothing is worked out after the fact. A service watches windows
**open**, describes each one while it is alive, and keeps the description until
the window closes — at which point the description is all that is left of it.

Three things that description gets right, each of which took a bug to find:

- **A window is not itself yet when it opens.** A terminal exists before the
  shell inside it does, so reading at that instant finds an empty box and
  records a command with no directory. Capture waits a moment first.
- **Only a terminal has a session inside it.** Every other app has child
  processes too — Electron keeps a pile — and treating those as "what the window
  was running" turns Spotify into a command line full of zygote helpers.
- **Hyprland names a window two ways.** The event socket writes `563f…` and
  `hyprctl clients` writes `0x563f…`. Everything here speaks the prefixed form,
  because a close event that cannot find what its own open event stored fails
  silently and leaves the list mysteriously empty.

A window's directory moves under it — you open a terminal in home and `cd` into
a project — so the focused window is re-read every 20 seconds. Slow on purpose:
it is a process spawn, and the only window whose directory changes is the one
being typed in.

## The list

**The screensaver is not in it.** Some windows are not closed so much as
finished: the screensaver dismisses itself the moment you touch the keyboard,
and offering to bring it back is offering to blank the screen you just
unblanked. Omarchy's other own windows — btop, a terminal, the about box — are
windows you might genuinely want back, so the ignore list stays one line long.

Newest first, one row per window closed. Two terminals closed in the same
directory are two rows, because they were two windows and getting one back does
not give you the other — a rule here once collapsed them and the second was lost
for good.

Nothing needs deduplicating: a window closes once, and a row is removed as it
reopens, so closing and reopening the same thing never accumulates.

A row is removed as it reopens. It is not closed any more, and a row that
reopens the same window twice lies the second time.

| | |
|---|---|
| Reopen where it was | Click a row, or `↑`/`↓` and `Enter` |
| Reopen **here** | Click the workspace badge on the row |
| Forget everything | "Clear the list" |
| How many to keep | Widget setting, 3 to 40, default 12 |

A closed window usually wants to come back where it was, but not always: after
you have moved on, the workspace you are standing in is the one you meant. The
badge already says which workspace the window came from, so it is the honest
place to say *not that one, this one* — and it is the only way to rescue a
window closed on a scratchpad, which otherwise comes back nowhere in particular.

Tiled windows come back on their workspace and take their place from the
layout; floating ones come back placed, because position and size are rules
Hyprland accepts on the exec itself. A window closed on a special workspace — a
scratchpad — comes back without one.

## From a keybinding

Undoing the last close without looking is the point:

```sh
omarchy-shell recently-closed reopen    # ok / empty
omarchy-shell recently-closed toggle    # the panel
```

In `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + T", "Reopen last closed window",
  hl.dsp.exec_cmd("omarchy-shell recently-closed reopen"))
```

## Browser windows come back whole

A browser keeps no URL on its command line, so a window rebuilt from `/proc`
alone comes back empty. It does write its session to disk, and that file says
which tabs belong to which window — so every tab returns, in order, in one
window.

`scripts/browser-tabs` reads Chromium's SNSS session format directly: a header
followed by length-prefixed commands, of which two matter — one binds a tab to a
window, the other carries a tab's URL and title. Anything unrecognised is
skipped by its own length, so a version that adds commands still parses.

The window is found by its title, which is the title of the tab you were looking
at. Several windows can share a title — three tabs on the same site — so the
most recently touched one wins, since the session writes the newest last.

Chromium, Chrome, Brave, Edge and Vivaldi share this format. Firefox does not
and comes back empty.

## What it cannot bring back

**An editor's file.** It returns to whatever it opens by default. Claude Code is
the exception, and only because it can be told to continue the conversation for
a directory.

**A window whose command cannot be run again.** Some apps are started by a
launcher that does not survive in `/proc`, and single-instance apps hand off to
an instance that may not open a window at all.

## Development

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" Service.qml BarWidget.qml Panel.qml
scripts/test-model      # addresses, the list, reopen rules, labels
scripts/test-wiring     # every root.x() the QML calls exists
scripts/capture-window <address>   # what one live window would be remembered as
```

Saving any file under `~/.config/omarchy/plugins/` hot-reloads the plugin;
`omarchy-restart-shell` is what actually picks up changes to the service.

## Remove

```sh
omarchy plugin remove io.github.monswiklund.recently-closed
```

## License

MIT

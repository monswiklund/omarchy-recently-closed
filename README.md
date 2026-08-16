# Recently Closed

Reopen a window you just closed — back on its workspace, in its directory,
running what it was running. An Omarchy Quattro bar widget.

## Requirements

| Needed for | What |
|---|---|
| Everything | Omarchy **Quattro** — the shell plugin system does not exist before it |
| Capturing | `hyprctl` and `jq`, both already on an Omarchy install |

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

Newest first, and the same window is never listed twice — closing four
terminals in the same directory offers that directory once. The list is for
getting something back, not for counting how often you lost it.

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

## What it cannot bring back

**The contents of the window, only the window.** A browser returns to its own
session restore, not the tabs you had. An editor returns to the file it opens by
default. Claude Code is the exception, and only because it can be told to
continue the conversation for a directory.

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

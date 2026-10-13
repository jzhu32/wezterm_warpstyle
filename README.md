# WezTerm, Warp style

A [WezTerm](https://wezterm.org) setup for macOS that looks and behaves like
[Warp](https://www.warp.dev): the dark theme, a prompt made of chips for the
environment, folder and git branch, a command line you edit like a text
editor, and tabs that tell you when something needs you.

It is two files. `wezterm.lua` is the look and the keyboard shortcuts.
`shell.zsh` is the zsh side: the prompt and the editing. It is only loaded
inside WezTerm, so every other terminal stays exactly as it was.

## Set it up on a Mac

By hand, in any terminal you already have. No agent, no account, nothing to
answer. You need [Homebrew](https://brew.sh) first; then two lines:

```sh
git clone https://github.com/jzhu32/wezterm_warpstyle.git ~/Developer/Tools/WezTerm
~/Developer/Tools/WezTerm/install.sh
```

Quit WezTerm and open it again. That is all.

If the folder is already there, you are updating rather than installing:

```sh
cd ~/Developer/Tools/WezTerm && git pull && ./install.sh
```

A few things worth knowing:

- The installer is safe to run again at any time, and only adds what is
  missing.
- `./install.sh --no-brew` skips Homebrew, for when WezTerm and the tools are
  already installed and you only want the config.
- An open WezTerm picks up `wezterm.lua` the moment it changes. `shell.zsh`
  applies to new tabs; a tab you already have takes it after
  `source ~/.config/wezterm/shell.zsh`.
- The folder can live anywhere; `~/Developer/Tools/WezTerm` is only where it is
  kept on the first Mac.

If you would rather have Claude Code or Codex do it, there is a prompt for
that in [Ask an agent instead](#ask-an-agent-instead).

### What the installer does

1. Installs what is missing with Homebrew: WezTerm, the Hack Nerd Font,
   `zsh-autosuggestions`, `zsh-syntax-highlighting`, `fzf` and `zoxide`.
   Nothing you already have is upgraded.
2. Links `wezterm.lua` and `shell.zsh` into `~/.config/wezterm`. Files that
   were already there are kept with `.before-warpstyle` added to their names.
3. Adds one line to `~/.zshrc` that loads `shell.zsh` inside WezTerm. Your
   original is saved as `~/.zshrc.before-wezterm-setup`.
4. If Claude Code is installed, sets `"preferredNotifChannel": "terminal_bell"`
   in `~/.claude/settings.json` so it can signal the terminal. Your original
   is saved as `settings.json.before-wezterm-bell`.

Two things are optional. Without them the feature that uses them does nothing:

- [Zed](https://zed.dev), for opening file paths you Cmd+click. Another editor
  works too: change `editor` at the top of `wezterm.lua`.
- [Claude Code](https://claude.com/claude-code), for turning a description
  into a command.

## Keeping two Macs the same

The config files in `~/.config/wezterm` are links into this folder, so this
folder is the one place to change things.

- **Get the latest on a Mac:** `git pull` in this folder. An open WezTerm
  picks up `wezterm.lua` straight away; `shell.zsh` applies to new tabs.
- **Send a change from a Mac:** `git add -A && git commit -m "what changed" && git push`.

## Ask an agent instead

Paste this into Claude Code or Codex on the other Mac. It installs the setup
if it is not there and updates it if it is, and it is deliberately told not to
touch your history or push anything:

```text
Install or update my Warp-style WezTerm config on this Mac.

The repo is https://github.com/jzhu32/wezterm_warpstyle.git and it belongs at
~/Developer/Tools/WezTerm.

- If that folder already exists, run `git pull --ff-only` in it. If there are
  local changes, or the pull is not a fast-forward, stop and show me the
  output: do not stash, reset, rebase, commit or push anything, ever.
- If it does not exist, clone it there.
- Then run ./install.sh in that folder. It is safe to re-run. Pass --no-brew
  only if Homebrew is missing and WezTerm is already installed.
- Check it worked: `ls -l ~/.config/wezterm` should show wezterm.lua and
  shell.zsh as links into the repo, and
  `wezterm --config-file ~/Developer/Tools/WezTerm/wezterm.lua show-keys | grep "Key Table: select_all"`
  should print a line.
- Then tell me, in a few lines: which commits the pull brought in
  (`git log --oneline`), anything the installer said it kept or changed, and
  that I need to quit WezTerm and open it again, plus run
  `source ~/.config/wezterm/shell.zsh` in any tab that is already open.
```

This saves no work over the two lines above; it is only here for when you
would rather not type them. The agent is doing the same `git pull` and
`./install.sh`, so read its plan before you let it go.

## What you get

### Typing a command

| Keys | What happens |
|---|---|
| Option+Left / Right, Cmd+Left / Right | Move by word; move to the line's start or end. |
| Shift+arrows | Select text. Add Option to go by word, Cmd to go to the line's start or end. |
| Backspace, or just type | Deletes or replaces what is selected. |
| Cmd+A | Select everything. |
| Cmd+Shift+Up / Down | Select everything above or below the cursor. |
| Cmd+C, Cmd+X, Cmd+V | Copy, cut, paste. |
| Cmd+Z, Cmd+Shift+Z | Undo, redo. |
| Cmd+Backspace | Delete to the start of the line. Repeat to climb through lines. |
| Shift+Enter, Option+Enter | New line without running the command. |
| Drag with the mouse, then Backspace | Deletes that text, if it appears only once in the command. |
| Triple click | Selects a whole command, or everything a command printed. |
| Up / Down | Earlier commands that start with what you have typed. |

### Finding things

| Keys | What happens |
|---|---|
| Cmd+Shift+G, or click the folder chip | A list of the folders here. Enter goes to one, Tab looks inside it, Esc closes. |
| Cmd+O | Pick a git project and open it in a new tab. |
| Cmd+Shift+O | The same, and start Claude Code there with a shell beside it. |
| Ctrl+R | Search your command history. |
| Ctrl+T | Find a file and put its path on the line. |
| `z part-of-a-name` | Jump to a folder you have been in before. |
| `# what you want`, then Enter | Asks Claude for the command and puts it on the line. It is never run for you. |
| Cmd+click | Opens a link, or a file path in your editor at the right line. |

### Tabs and splits

| Keys | What happens |
|---|---|
| Cmd+T | New tab. |
| Cmd+1 to Cmd+8 | Go to that tab. Cmd+9 goes to the last one, whatever its number. |
| Cmd+Shift+[ / ], or Ctrl+Tab | The tab before or after this one. |
| Cmd+Shift+R, or Cmd+P and "Rename tab" | Name the tab yourself. An empty name goes back to the automatic one. |
| Ctrl+Shift+Left / Right | Move the tab. |
| Cmd+D, Cmd+Shift+D | Split to the right, split downwards. |
| Cmd+Option+4 | Turn the pane you are in into a grid of four. |
| Cmd+Option+arrows | Move between splits. Cmd+Ctrl+arrows resizes them. |
| Cmd+Shift+Enter | Make one split fill the tab, and back. |
| Cmd+W, or Cmd+P and "Close this split" | Close the split you are in. Closing the last split closes the tab. Splits have no close button of their own: WezTerm draws none, and the config cannot add one. |

Tabs share the bar evenly. Each shows its last two folders and git branch
while the shell is waiting, or the running program's own title. A tab is
tinted amber, and you get a notification, when Claude Code finishes or asks
something while you are elsewhere, or when a command that ran longer than 30
seconds ends. The tabs you had open come back the next time WezTerm starts.

A new tab or split opens with a short list of shortcuts, then its first prompt,
at the top of the window. The list scrolls away as you work, and the prompt
moves down as commands print until it reaches the bottom and stays there. Splitting,
resizing or closing a split leaves each prompt, and the output above it, on
the rows they were on. A folder name too long for a narrow split is cut short
from the left instead of running onto a second row.

### Commands and their output

| Keys | What happens |
|---|---|
| Cmd+Up / Down | Jump from one command to the next in the scrollback. |
| Cmd+End, Cmd+Home | Jump back down to the prompt after scrolling up, or to the very top. On a laptop End and Home are Fn+Right and Fn+Left. |
| Right-click | Jump back down to the prompt, like Cmd+End. On a trackpad that is a click with two fingers. Programs that use the mouse themselves keep their own right-click. |
| Cmd+Shift+C | Copy what the last command printed. |
| Cmd+K | Clear the screen. |
| Cmd+F | Search what is on screen and in the scrollback. Esc closes it. |
| Cmd+P | Command palette. |
| Cmd+, | Open `wezterm.lua`. |

### The window

| Keys | What happens |
|---|---|
| Cmd+= / Cmd+- / Cmd+0 | Bigger text, smaller, back to the size set in `wezterm.lua`. |
| Cmd+N | New window. |
| Cmd+R | Reload `wezterm.lua`. Saving the file does this on its own. |
| Cmd+H, Cmd+M, Cmd+Q | Hide, minimise, quit. |
| The green button; Esc to come back | Full screen, in a space of its own. No key does this on purpose: Option+Enter used to, and full screen takes away the window's edges and buttons, which looks exactly like a window that has stopped being resizable. |

### Inside Claude Code and Codex

These programs have their own input box, which a terminal cannot highlight.
Cmd+A, Cmd+Shift+Up or Cmd+Shift+Down therefore only remember the selection
for a few seconds, and the tab bar says so. Backspace then deletes it; any
other key cancels. Cmd+Z undoes, one step at a time.

## Changing things

The settings worth changing are in the `settings` table at the top of
`wezterm.lua`: font and size, opacity, theme, cursor thickness, tab width, the
editor for Cmd+click, the folders Cmd+O searches, whether tabs are reopened,
whether a new tab opens with the list of shortcuts, and whether there is a
scroll bar. Saving the file applies it immediately.

Three Warp themes are included: Dark, Phenomenon and Light. The light one is
used when macOS is in light mode.

WezTerm has no preferences window; this table is the preferences. For a
see-through background, the two lines to change are:

- `opacity` — how solid the window is. `1.0` lets nothing through, `0.80` is
  what it ships with, and much below that the wallpaper starts to fight the
  text.
- `blur` — how much the desktop behind it is blurred. `40` is the default and
  `0` turns the blur off, leaving plain transparency.

Both take effect the moment you save, so you can nudge a value and watch the
window change.

## What it cannot do

- Tabs down the side. WezTerm only draws them along the top.
- A settings window. There is no preferences dialog anywhere in WezTerm; the
  `settings` table in `wezterm.lua` is where every knob lives, and Cmd+, opens
  it.
- A close button on a split, or renaming a tab by right-clicking it. WezTerm
  does not hand tab-bar or split clicks to the config, so both live on keys and
  the command palette instead.
- Keep the line you type in view while you scroll back, as Warp does. A
  terminal pane scrolls as one piece and the prompt is its last lines. Typing
  anything, Cmd+End or a right-click brings you straight back to it.
- A "jump to bottom" button that appears when you scroll up. WezTerm cannot
  draw over a pane, and does not tell the config that a pane is scrolled back.
  A right-click anywhere in the pane does the same job.
- Clicking to place the cursor inside a command. Use the arrow keys.
- Warp's AI agent and its visual blocks.

## Good to know

- **The prompt runs git in whatever folder you are in**, to show the branch
  and the count of changed files. A repository can tell git to run programs
  of its own (a file watcher, content filters, hooks), which matters for a
  folder unpacked from a download. Every git call in `shell.zsh` switches
  those off, including fetches and all content filters (git-lfs too). A file
  that goes through a filter therefore counts as changed when it has only
  been touched. If git cannot confirm the filters are off, or cannot read the
  repository's settings, the branch is shown without a count.
- **`# what you want` sends only the words you typed** to Claude, which runs
  in an empty folder without tools. The suggestion is put on the line as
  text; you decide whether to run it.

## Taking it off

1. Delete the line near the end of `~/.zshrc` that mentions `wezterm/shell.zsh`.
2. Delete `~/.config/wezterm` and `~/.cache/wezterm-warp`.
3. Optionally remove `"preferredNotifChannel"` from `~/.claude/settings.json`,
   and uninstall the Homebrew packages listed in `Brewfile`.

## Checking a change

```sh
python3 tests/run.py
```

This drives a real zsh through every editing feature, runs the logic in
`wezterm.lua` against a stand-in for WezTerm, and starts WezTerm's own engine
with no window to check that splits and resizes leave the prompt and your
output where they were. It needs Neovim for the `wezterm.lua` part, only as a Lua interpreter
(`brew install neovim`). Your history, clipboard, open windows and Claude Code
are not touched.

`wezterm show-keys` exits successfully even when it rejects a config, so to
check that WezTerm accepts `wezterm.lua`, look for one of its own bindings:

```sh
wezterm --config-file wezterm.lua show-keys | grep "Key Table: select_all"
```

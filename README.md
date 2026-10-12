# WezTerm, Warp style

A [WezTerm](https://wezterm.org) setup for macOS that looks and behaves like
[Warp](https://www.warp.dev): the dark theme, a prompt made of chips for the
environment, folder and git branch, a command line you edit like a text
editor, and tabs that tell you when something needs you.

It is two files. `wezterm.lua` is the look and the keyboard shortcuts.
`shell.zsh` is the zsh side: the prompt and the editing. It is only loaded
inside WezTerm, so every other terminal stays exactly as it was.

## Set it up on a Mac

You need [Homebrew](https://brew.sh). Then:

```sh
git clone https://github.com/jzhu32/wezterm_warpstyle.git ~/Developer/Tools/WezTerm
~/Developer/Tools/WezTerm/install.sh
```

Quit WezTerm and open it again. That is all.

The folder can live anywhere; `~/Developer/Tools/WezTerm` is only where it is
kept on the first Mac. The installer is safe to run again at any time.

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

## What you get

### Typing a command

| Keys | What happens |
|---|---|
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
| Cmd+T, Cmd+1 to Cmd+9 | New tab, go to a tab. |
| Cmd+Shift+R, or Cmd+P and "Rename tab" | Name the tab yourself. An empty name goes back to the automatic one. |
| Ctrl+Shift+Left / Right | Move the tab. |
| Cmd+D, Cmd+Shift+D | Split to the right, split downwards. |
| Cmd+Option+4 | Turn the pane you are in into a grid of four. |
| Cmd+Option+arrows | Move between splits. Cmd+Ctrl+arrows resizes them. |
| Cmd+Shift+Enter | Make one split fill the tab, and back. |
| Cmd+W | Close the split you are in. Closing the last split closes the tab. Splits have no close button of their own. |

Tabs share the bar evenly. Each shows its last two folders and git branch
while the shell is waiting, or the running program's own title. A tab is
tinted amber, and you get a notification, when Claude Code finishes or asks
something while you are elsewhere, or when a command that ran longer than 30
seconds ends. The tabs you had open come back the next time WezTerm starts.

### Commands and their output

| Keys | What happens |
|---|---|
| Cmd+Up / Down | Jump from one command to the next in the scrollback. |
| Cmd+Shift+C | Copy what the last command printed. |
| Cmd+K | Clear the screen. |
| Cmd+P | Command palette. |
| Cmd+, | Open `wezterm.lua`. |

### Inside Claude Code and Codex

These programs have their own input box, which a terminal cannot highlight.
Cmd+A, Cmd+Shift+Up or Cmd+Shift+Down therefore only remember the selection
for a few seconds, and the tab bar says so. Backspace then deletes it; any
other key cancels. Cmd+Z undoes, one step at a time.

## Changing things

The settings worth changing are in the `settings` table at the top of
`wezterm.lua`: font and size, opacity, theme, cursor thickness, tab width, the
editor for Cmd+click, the folders Cmd+O searches, and whether tabs are
reopened. Saving the file applies it immediately.

Three Warp themes are included: Dark, Phenomenon and Light. The light one is
used when macOS is in light mode.

## What it cannot do

- Tabs down the side. WezTerm only draws them along the top.
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

This drives a real zsh through every editing feature and runs the logic in
`wezterm.lua` against a stand-in for WezTerm. It needs Neovim for the second
part, only as a Lua interpreter (`brew install neovim`). Your history,
clipboard and Claude Code are not touched.

`wezterm show-keys` exits successfully even when it rejects a config, so to
check that WezTerm accepts `wezterm.lua`, look for one of its own bindings:

```sh
wezterm --config-file wezterm.lua show-keys | grep "Key Table: select_all"
```

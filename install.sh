#!/bin/zsh
# Sets up the Warp-style WezTerm on this Mac. Safe to run again at any time.
#
#   ./install.sh            install everything
#   ./install.sh --no-brew  skip Homebrew (the apps and tools are already there)

set -e
repo=${0:A:h}
config=$HOME/.config/wezterm

say() { print -P "%F{cyan}==>%f $1" }

# ---- Apps, font and shell tools ---------------------------------------------

if [[ $1 != --no-brew ]]; then
  if ! command -v brew >/dev/null; then
    print "Homebrew is needed first. Install it from https://brew.sh, then run this again."
    exit 1
  fi
  say "Installing WezTerm, the font and the shell tools with Homebrew"
  # --no-upgrade: only add what is missing, never replace an app you are using.
  brew bundle --file=$repo/Brewfile --no-upgrade
fi

# ---- Config files -----------------------------------------------------------

# The two files stay in this folder and are linked into place, so `git pull`
# here updates the terminal.
say "Linking the config into $config"
mkdir -p $config $HOME/.cache/wezterm-warp
chmod 700 $HOME/.cache/wezterm-warp
for file in wezterm.lua shell.zsh; do
  if [[ -e $config/$file && ! -L $config/$file ]]; then
    mv $config/$file $config/$file.before-warpstyle
    print "    kept your old $file as $file.before-warpstyle"
  fi
  ln -sfn $repo/$file $config/$file
done

# ---- zsh --------------------------------------------------------------------

# One line, and only inside WezTerm: other terminals are left exactly as they are.
if ! grep -qF 'wezterm/shell.zsh' $HOME/.zshrc 2>/dev/null; then
  say "Adding one line to ~/.zshrc"
  [[ -f $HOME/.zshrc ]] && cp $HOME/.zshrc $HOME/.zshrc.before-wezterm-setup
  cat >> $HOME/.zshrc <<'EOF'

# WezTerm only: Warp-like prompt and command-line editing. Delete this line to undo.
if [[ $TERM_PROGRAM == WezTerm && -r ~/.config/wezterm/shell.zsh ]]; then source ~/.config/wezterm/shell.zsh; fi
EOF
fi

# ---- Claude Code ------------------------------------------------------------

# Claude Code only sends desktop notifications in a few terminals. Ringing the
# terminal bell instead lets WezTerm mark the tab and notify you.
settings=$HOME/.claude/settings.json
if [[ -f $settings ]] && ! grep -q preferredNotifChannel $settings; then
  say "Telling Claude Code to ring the bell when it needs you"
  cp $settings $settings.before-wezterm-bell
  /usr/bin/python3 - $settings <<'EOF'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    settings = json.load(f)
settings = {"preferredNotifChannel": "terminal_bell", **settings}
with open(path, "w", encoding="utf-8") as f:
    json.dump(settings, f, indent=2, ensure_ascii=False)
    f.write("\n")
EOF
fi

say "Done. Quit WezTerm and open it again to see everything."

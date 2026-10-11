# Warp-like command line for zsh inside WezTerm.
#
# Loaded from ~/.zshrc only when the terminal is WezTerm. It is the other half
# of wezterm.lua: that file turns the Cmd shortcuts into the escape sequences
# bound at the bottom of this one.

[[ -o zle ]] || return 0
autoload -Uz add-zsh-hook add-zle-hook-widget vcs_info
zmodload zsh/datetime

# ---- WezTerm integration ----------------------------------------------------

# Marks each prompt and its output so Cmd+Up/Down can jump between commands.
# Its per-prompt user vars are skipped: they fork several processes and only
# the ones set below are used.
WEZTERM_SHELL_SKIP_USER_VARS=1
_wz_integration=/Applications/WezTerm.app/Contents/Resources/wezterm.sh
[[ -r $_wz_integration ]] && source $_wz_integration

# What wezterm.lua needs to know about this shell. WEZ_ZLE says whether zsh is
# waiting at a prompt, so Cmd+A/C/X/Z are sent to the command line and never to
# a program running inside the shell. WEZ_CMD names that program and
# WEZ_BRANCH the git branch, both for the tab title.
_wz_set_var() { printf '\033]1337;SetUserVar=%s=%s\007' $1 "$(print -rn -- $2 | base64)" }
_wz_at_prompt() {
  printf '\033]1337;SetUserVar=WEZ_ZLE=MQ==\007'  # "1"
  print -rn -- $'\e]0;'${(V)${(%):-%~}}$'\a'
}
_wz_in_command() {
  _wz_started=$EPOCHREALTIME
  printf '\033]1337;SetUserVar=WEZ_ZLE=MA==\007'  # "0"
  local -a typed=( ${(z)1} )
  _wz_set_var WEZ_CMD ${typed[1]:t}
  # The tab shows the command until the program sets a title of its own.
  print -rn -- $'\e]0;'${(V)${1%%$'\n'*}[1,80]}$'\a'
}
add-zsh-hook precmd _wz_at_prompt
add-zsh-hook preexec _wz_in_command

# wezterm.lua drops mouse-selected text here for _wz_adopt-selection.
_wz_state=$HOME/.cache/wezterm-warp
[[ -d $_wz_state ]] || mkdir -m 700 -p $_wz_state

# ---- Prompt -----------------------------------------------------------------

# Warp's input area: a rule, then chips for the environment, folder and git
# branch, then an empty line to type on. Once a command is entered the chips
# collapse into one dim line, so the scrollback stays compact.
setopt prompt_subst
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:*' max-exports 2
zstyle ':vcs_info:git:*' formats '%b' '%R'
zstyle ':vcs_info:git:*' actionformats '%b|%a' '%R'

# The prompt reads these when it is drawn, so a folder or branch name is only
# ever shown, never run as code. % is doubled in them for the same reason.
_wz_p_env= _wz_p_branch= _wz_p_changes= _wz_p_took=

# The folder chip is a link: wezterm.lua opens the folder list when it is clicked.
_wz_link_folder=$'%{\e]8;;wezwarp:folder\e\\%}'
_wz_link_end=$'%{\e]8;;\e\\%}'

# $1 = text color, $2 = text
_wz_chip() { _wz_chips+=$'%F{236}\ue0b6%K{236}%F{'$1$'}%B '$2$' %b%k%F{236}\ue0b4%f ' }

# Counting changed files means running git in whatever folder you are in, and
# a repository's own settings can tell git to run programs: a file watcher,
# content filters, hooks, fetches. A folder unpacked from a download must not
# get to do that from a prompt, so those are all switched off here, and a
# repository that defines its own filters is not counted at all.
_wz_git() {
  GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 command git \
    -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@" 2>/dev/null
}

# Count changed files, but give up on a repository where that is slow.
typeset -gA _wz_slow_repos
_wz_count_changes() {
  local root=$vcs_info_msg_1_
  (( $+_wz_slow_repos[$root] )) && return 1
  local -F started=$EPOCHREALTIME
  local own_filters=$'\n'$(_wz_git config --show-scope --get-regexp '^filter\.')
  [[ $own_filters == *$'\n'(local|worktree)$'\t'* ]] && return 1
  local -a changed=( ${(f)"$(_wz_git status --porcelain --ignore-submodules=all --no-renames)"} )
  _wz_p_changes=$#changed
  (( EPOCHREALTIME - started > 0.2 )) && _wz_slow_repos[$root]=1
  return 0
}

# One column short of the window: zsh miscounts a prompt line that is full.
_wz_rule='%F{238}${(l:COLUMNS-1::─:):-}%f'
_wz_mark_prompt=$'%{\e]133;P;k=i\a%}'
_wz_mark_input=$'%{\e]133;B\a%}'
_wz_prompt_compact=$_wz_mark_prompt$_wz_rule$'\n''%F{244}${_wz_p_env:+$_wz_p_env }%~${_wz_p_branch:+ git:($_wz_p_branch)}%f'$'\n'$_wz_mark_input

# How long the last command ran, shown once it is worth knowing. A long one
# also rings the bell, which wezterm.lua turns into a mark on the tab and a
# notification if you have moved on to something else.
_wz_took() {
  _wz_p_took=
  (( $+_wz_started )) || return 0
  local -F elapsed=$(( EPOCHREALTIME - _wz_started ))
  local -i seconds=$elapsed
  unset _wz_started
  if (( seconds >= 60 )); then
    _wz_p_took="$(( seconds / 60 ))m $(( seconds % 60 ))s"
  elif (( seconds >= 2 )); then
    printf -v _wz_p_took '%.1fs' $elapsed
  fi
  (( seconds >= 30 )) && print -n '\a'
}

_wz_prompt_precmd() {
  _wz_took
  vcs_info
  _wz_p_env=${${CONDA_DEFAULT_ENV:-${VIRTUAL_ENV:t}}//\%/%%}
  _wz_p_branch=${vcs_info_msg_0_//\%/%%}
  [[ $vcs_info_msg_0_ == ${_wz_sent_branch-} ]] || _wz_set_var WEZ_BRANCH "${_wz_sent_branch::=$vcs_info_msg_0_}"

  # A red mark when the last command failed; 130 is only Ctrl+C.
  _wz_chips=
  _wz_chip 9 '✘ %?'
  local failed=$_wz_chips
  _wz_chips=
  [[ -n $_wz_p_env ]] && _wz_chip 15 $'\uf489  ${_wz_p_env}'
  _wz_chip 15 $_wz_link_folder$'\uf413  %~'$_wz_link_end
  if [[ -n $_wz_p_branch ]]; then
    _wz_chip 10 $'\uf418  ${_wz_p_branch}'
    _wz_count_changes && _wz_chip 250 '± ${_wz_p_changes}'
  fi
  PROMPT=$_wz_mark_prompt$_wz_rule$'\n''%(130?..%(?..'$failed'))'$_wz_chips'%F{244}${_wz_p_took:+took $_wz_p_took}%f'$'\n\n'$_wz_mark_input
}

# Blank line between commands, like the spacing between Warp's blocks.
_wz_gap() { (( _wz_prompts++ )) && print }
add-zsh-hook precmd _wz_prompt_precmd
add-zsh-hook precmd _wz_gap

_wz_collapse_prompt() {
  [[ $CONTEXT == start ]] || return 0
  PROMPT=$_wz_prompt_compact
  zle .reset-prompt
}
add-zle-hook-widget line-finish _wz_collapse_prompt

# ---- Editor-style editing ---------------------------------------------------

WORDCHARS=${WORDCHARS//\/}                # Option+arrows stop at each / in a path
zle_highlight=(region:bg=4,fg=0 paste:none)

_wz_delete_region() {
  local -i lo=$(( MARK < CURSOR ? MARK : CURSOR )) hi=$(( MARK > CURSOR ? MARK : CURSOR ))
  BUFFER=${BUFFER[1,lo]}${BUFFER[hi+1,-1]}
  CURSOR=$lo
  REGION_ACTIVE=0
}

# Shift+arrows start or extend a selection.
_wz_select() { (( REGION_ACTIVE )) || zle .set-mark-command; zle .$1 }
for _wz_seq _wz_widget in \
    '^[[1;2D' backward-char      '^[[1;2C' forward-char \
    '^[[1;2A' up-line            '^[[1;2B' down-line \
    '^[[1;4D' backward-word      '^[[1;4C' emacs-forward-word \
    '^[[1;2H' beginning-of-line  '^[[1;2F' end-of-line; do
  eval "_wz_select_$_wz_widget() { _wz_select $_wz_widget }"
  zle -N _wz_select_$_wz_widget
  bindkey $_wz_seq _wz_select_$_wz_widget
done

# Moving without Shift drops the selection.
for _wz_widget in backward-char forward-char backward-word emacs-forward-word \
    beginning-of-line end-of-line; do
  eval "_wz_$_wz_widget() { REGION_ACTIVE=0; zle .$_wz_widget }"
  zle -N $_wz_widget _wz_$_wz_widget
done

# Deleting removes the selection if there is one.
for _wz_widget in backward-delete-char delete-char backward-kill-word backward-kill-line; do
  eval "_wz_$_wz_widget() { if (( REGION_ACTIVE )); then _wz_delete_region; else zle .$_wz_widget; fi }"
  zle -N $_wz_widget _wz_$_wz_widget
done

# Typing or pasting replaces the selection.
_wz_self-insert()     { (( REGION_ACTIVE )) && _wz_delete_region; zle .self-insert }
_wz_bracketed-paste() { (( REGION_ACTIVE )) && _wz_delete_region; zle .bracketed-paste }
_wz_newline()         { (( REGION_ACTIVE )) && _wz_delete_region; LBUFFER+=$'\n' }
zle -N self-insert _wz_self-insert
zle -N bracketed-paste _wz_bracketed-paste
zle -N _wz_newline

_wz_clip() { pbcopy }
_wz_select-all() { MARK=0; CURSOR=$#BUFFER; REGION_ACTIVE=1 }
_wz_copy() {
  (( REGION_ACTIVE )) || return 0
  local -i lo=$(( MARK < CURSOR ? MARK : CURSOR )) hi=$(( MARK > CURSOR ? MARK : CURSOR ))
  print -rn -- ${BUFFER[lo+1,hi]} | _wz_clip
}
_wz_cut() { (( REGION_ACTIVE )) || return 0; _wz_copy; _wz_delete_region }

# Text dragged over with the mouse is only highlighted by the terminal; zsh
# knows nothing about it. wezterm.lua passes that text along on mouse-up, and
# if it appears exactly once in the command it becomes a real selection, so
# Backspace, typing and Cmd+X act on it. Anywhere else it is left alone.
# Spacing is compared loosely because the terminal drops spaces at line ends.
_wz_adopt-selection() {
  emulate -L zsh -o extendedglob
  local file=$_wz_state/selection-$WEZTERM_PANE text
  [[ -s $file ]] || return 0
  text=$(<$file)
  : >| $file
  local -a words=( ${=text} )
  (( $#words )) || return 0
  local pattern=${(j.[[:space:]]##.)${(b)words}}
  local before_first=${BUFFER%%${~pattern}*} before_last=${BUFFER%${~pattern}*}
  (( $#before_first < $#BUFFER && $#before_first == $#before_last )) || return 0
  local found=${(M)${BUFFER[$#before_first+1,-1]}#${~pattern}}
  MARK=$#before_first
  CURSOR=$(( MARK + $#found ))
  REGION_ACTIVE=1
}

# Cmd+Shift+Up/Down select from the cursor to the very start or end, which in
# a command of several lines is everything above or below.
_wz_select-to-start() { (( REGION_ACTIVE )) || zle .set-mark-command; CURSOR=0 }
_wz_select-to-end()   { (( REGION_ACTIVE )) || zle .set-mark-command; CURSOR=$#BUFFER }

# Up/Down search history for commands starting with what is already typed.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
_wz_up()   { REGION_ACTIVE=0; zle up-line-or-beginning-search }
_wz_down() { REGION_ACTIVE=0; zle down-line-or-beginning-search }

for _wz_widget in select-all copy cut adopt-selection select-to-start select-to-end up down; do
  zle -N _wz_$_wz_widget
done

for _wz_seq _wz_widget in \
    '^[[H'    beginning-of-line   '^[OH' beginning-of-line \
    '^[[F'    end-of-line         '^[OF' end-of-line \
    '^[[A'    _wz_up              '^[OA' _wz_up \
    '^[[B'    _wz_down            '^[OB' _wz_down \
    '^[f'     emacs-forward-word  '^[[3~' delete-char \
    '^U'      backward-kill-line  '^[^M' _wz_newline \
    '^[[990~' _wz_select-all      '^[[991~' _wz_copy \
    '^[[992~' _wz_cut             '^[[993~' redo \
    '^[[994~' _wz_adopt-selection '^[[995~' _wz_select-to-start \
    '^[[996~' _wz_select-to-end; do
  bindkey $_wz_seq $_wz_widget
done

# Tab opens a menu that the arrow keys move through.
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'

# ---- Asking for a command ----------------------------------------------------

# A line that starts with "# " is a request in plain words, as in Warp. Enter
# sends it to Claude and puts the suggested command on the line to check and
# run; nothing is ever run for you. The request goes into history, so Up
# brings it back.
#
# Only the words you typed are sent. Claude runs in an empty folder of its
# own, without tools, so nothing in the folder you are in (its name, a
# CLAUDE.md, project settings) can steer the suggestion.
_wz_ask_prompt="You turn a request into one shell command for zsh on macOS. Reply with the command only, on one line, with no explanation and no code fences. Join several steps with &&. If no shell command can do it, reply with one short line starting with '# '."

_wz_ask() {
  (( $+commands[claude] )) || { zle -M "Claude Code is not installed, so there is nothing to ask."; return 1 }
  local request=${BUFFER#\#} answer
  zle -R "Asking Claude for a command… (Ctrl+C stops)"
  [[ -d $_wz_state/ask ]] || mkdir -m 700 -p $_wz_state/ask
  answer=$(cd -q $_wz_state/ask && command claude -p --model haiku --tools "" --no-session-persistence \
    --setting-sources "" --strict-mcp-config --disable-slash-commands --system-prompt $_wz_ask_prompt \
    "Request:$request" </dev/null 2>/dev/null)
  answer=${${answer#\`\`\`*$'\n'}%$'\n'\`\`\`}
  # It is text to read before running: no invisible or control characters.
  answer=${answer//[^[:print:]$'\n']/}
  if [[ -z ${answer//[[:space:]]} ]]; then
    zle -M "No suggestion came back. Is Claude Code signed in?"
    return 1
  fi
  print -s -- $BUFFER
  BUFFER=$answer
  CURSOR=$#BUFFER
  REGION_ACTIVE=0
  zle -R
}

_wz_accept-line() {
  if [[ $CONTEXT == start && $BUFFER == '# '?* ]]; then
    _wz_ask
  else
    zle .accept-line
  fi
}
zle -N accept-line _wz_accept-line

# ---- Finding things ---------------------------------------------------------

# Ctrl+R searches command history and Ctrl+T finds a file to put on the line.
if (( $+commands[fzf] )); then
  : ${FZF_DEFAULT_OPTS:='--height=45% --layout=reverse --border=rounded --info=inline'}
  export FZF_DEFAULT_OPTS
  source <(fzf --zsh)
fi

# `z part-of-a-name` jumps to a folder you have been in before.
(( $+commands[zoxide] )) && eval "$(zoxide init zsh)"

# ---- Changing folder --------------------------------------------------------

# Cmd+Shift+G, or a click on the folder chip, lists the folders here the way
# Warp's folder chip does. Enter goes to the highlighted one, Tab looks inside
# it without leaving the list, Esc closes. What you had typed is kept.
_wz_pick-folder() {
  (( $+commands[fzf] )) || { zle -M "The folder list needs fzf (brew install fzf)."; return 1 }
  local dir=$PWD picked name
  local -a lines
  while true; do
    lines=( $'..\t↑  .. (Parent folder)' )
    for name in $dir/*(N-/:t); do
      lines+=( $name$'\t  '$name )
    done
    picked=$(print -rl -- $lines | fzf --delimiter=$'\t' --with-nth=2 --no-multi \
      --ghost='Search folders…' --border-label=" ${dir/#$HOME/~} " \
      --header='enter: go there · tab: look inside · esc: close' \
      --bind='enter:print(go)+accept,tab:print(look)+accept')
    # Esc, or Enter with nothing matching
    [[ $picked == *$'\n'* ]] || { zle reset-prompt; return 0 }
    name=${${picked#*$'\n'}%%$'\t'*}
    if [[ $name == .. ]]; then dir=${dir:h}; else dir=${dir%/}/$name; fi
    [[ $picked == go$'\n'* ]] && break
  done
  zle push-line
  BUFFER="cd -- ${(q-)dir}"
  zle accept-line
}
zle -N _wz_pick-folder
bindkey '^[[997~' _wz_pick-folder

# ---- Suggestions and syntax colors ------------------------------------------

_wz_share=${HOMEBREW_PREFIX:-/opt/homebrew}/share

# Grey rather than the default "bright black", which Warp's themes make nearly
# the same color as the background.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
if [[ -r $_wz_share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source $_wz_share/zsh-autosuggestions/zsh-autosuggestions.zsh
  ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(_wz_up _wz_down)
fi

# Has to come after every widget above is defined.
if [[ -r $_wz_share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source $_wz_share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
  ZSH_HIGHLIGHT_STYLES[comment]='fg=244'
  for _wz_style in command builtin alias function precommand; do
    ZSH_HIGHLIGHT_STYLES[$_wz_style]='fg=green,bold'
  done
fi

unset _wz_seq _wz_widget _wz_style _wz_integration _wz_share

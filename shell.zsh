# Warp-like command line for zsh inside WezTerm.
#
# Loaded from ~/.zshrc only when the terminal is WezTerm. It is the other half
# of wezterm.lua: that file turns the Cmd shortcuts into the escape sequences
# bound at the bottom of this one.

[[ -o zle ]] || return 0
autoload -Uz add-zsh-hook add-zle-hook-widget
zmodload zsh/datetime

# ---- WezTerm integration ----------------------------------------------------

# Marks each prompt and its output so Cmd+Up/Down can jump between commands.
# Its per-prompt user vars are skipped: they fork several processes and only
# the ones set below are used.
WEZTERM_SHELL_SKIP_USER_VARS=1
_wz_integration=/Applications/WezTerm.app/Contents/Resources/wezterm.sh
# Not a second time when ~/.zshrc is sourced again: it would add its hooks twice.
[[ -r $_wz_integration ]] && (( ! $+functions[__wezterm_semantic_precmd] )) && source $_wz_integration

# What wezterm.lua needs to know about this shell. WEZ_ZLE says whether zsh is
# waiting at a prompt, so Cmd+A/C/X/Z are sent to the command line and never to
# a program running inside the shell. WEZ_CMD names that program and
# WEZ_BRANCH the git branch, both for the tab title.
_wz_set_var() { printf '\033]1337;SetUserVar=%s=%s\007' $1 "$(print -rn -- $2 | base64)" }
_wz_at_prompt() {
  printf '\033]1337;SetUserVar=WEZ_ZLE=MQ==\007'  # "1"
  # A program that quits without tidying up after itself - an ssh session that
  # drops is the usual one - leaves mouse reporting switched on, and from then
  # on every mouse move and scroll types its coordinates onto the command line.
  # Nothing waiting at a prompt wants those, so switch reporting off each time.
  printf '\033[?1000l\033[?1002l\033[?1003l\033[?1006l\033[?1015l'
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

# The prompt reads these when it is drawn, so a folder or branch name is only
# ever shown, never run as code. % is doubled in them for the same reason.
_wz_p_env= _wz_p_branch= _wz_p_changes= _wz_p_took=

# The folder chip is a link: wezterm.lua opens the folder list when it is clicked.
_wz_link_folder=$'%{\e]8;;wezwarp:folder\e\\%}'
_wz_link_end=$'%{\e]8;;\e\\%}'

# $1 = text color, $2 = text
_wz_chip() { _wz_chips+=$'%F{236}\ue0b6%K{236}%F{'$1$'}%B '$2$' %b%k%F{236}\ue0b4%f ' }

# The prompt runs git in whatever folder you are in, and a repository's own
# settings can tell git to run programs: a file watcher, content filters,
# hooks, or a fetch through a made-up transport. A folder unpacked from a
# download must not get to do any of that from a prompt. So every git call
# here goes through _wz_git, which switches those off no matter what the
# repository says, and stays quiet; callers go by its exit status.
_wz_git() {
  GIT_OPTIONAL_LOCKS=0 GIT_NO_LAZY_FETCH=1 GIT_TERMINAL_PROMPT=0 command git \
    -c core.fsmonitor=false -c core.hooksPath=/dev/null -c credential.helper= \
    -c protocol.allow=never -c protocol.ext.allow=never -c protocol.file.allow=never \
    -c protocol.git.allow=never -c protocol.ssh.allow=never \
    -c protocol.http.allow=never -c protocol.https.allow=never "$@" 2>/dev/null
}

# The branch (or the commit, when no branch is checked out) and the top folder
# of the repository; fails outside one.
_wz_git_info() {
  _wz_branch=
  _wz_root=$(_wz_git rev-parse --show-toplevel) && [[ -n $_wz_root ]] || { _wz_root=; return 1 }
  _wz_branch=$(_wz_git symbolic-ref --short -q HEAD) || _wz_branch=$(_wz_git rev-parse --short HEAD) || _wz_branch=
}

# Content filters (git-lfs is the usual one) are programs git runs on files
# while it looks for changes, and they cannot be switched off with one
# setting. Whichever settings file defines one, it acts on what the repository
# says, so the prompt never runs any of them: for its own calls each filter is
# replaced by "none", and nothing is counted unless git confirms that took.
# The price: a file that goes through a filter counts as changed when it has
# only been touched.

# The filter programs in effect, as key/value pairs in the caller's
# `effective`. $@ is the git to ask. Fails when git cannot say.
_wz_read_filters() {
  local listing record
  listing=$("$@" config -z --get-regexp '^filter\..*\.(clean|process|smudge)$')
  case $? in (0|1) ;; (*) return 1 ;; esac
  effective=()
  for record in ${(0)listing}; do
    # "key<newline>value"; a later record for the same key is the one in effect.
    effective+=( "${record%%$'\n'*}" "${record#*$'\n'}" )
  done
}

# git with every filter in the caller's `drivers` replaced by "none". It
# exports variables, so only call it inside $( ).
_wz_git_unfiltered() {
  local -i n=0
  local driver part
  for driver in $drivers; do
    for part in clean process smudge; do
      export "GIT_CONFIG_KEY_$n=filter.$driver.$part" "GIT_CONFIG_VALUE_$n="
      (( n += 1 ))
    done
    export "GIT_CONFIG_KEY_$n=filter.$driver.required" "GIT_CONFIG_VALUE_$n=false"
    (( n += 1 ))
  done
  export GIT_CONFIG_COUNT=$n
  _wz_git "$@"
}

# Count changed files, unless the repository is slow or git cannot be kept
# from running its filters. No count is shown then; the branch still is.
typeset -gA _wz_slow_repos
_wz_count_changes() {
  (( $+_wz_slow_repos[$_wz_root] )) && return 1
  local -F started=$EPOCHREALTIME
  local -A effective
  local -a drivers
  local key value listing

  _wz_read_filters _wz_git || return 1
  for key value in "${(@kv)effective}"; do
    [[ -n $value ]] && drivers+=( "${${key#filter.}%.*}" )
  done
  drivers=( "${(@u)drivers}" )
  if (( $#drivers )); then
    (( $#drivers <= 40 )) || return 1
    _wz_read_filters _wz_git_unfiltered || return 1
    for key value in "${(@kv)effective}"; do
      [[ -z $value ]] || return 1
    done
  fi

  listing=$(_wz_git_unfiltered status --porcelain --ignore-submodules=all --no-renames) || return 1
  local -a changed=( ${(f)listing} )
  _wz_p_changes=$#changed
  (( EPOCHREALTIME - started > 0.2 )) && _wz_slow_repos[$_wz_root]=1
  return 0
}

# The rule is a row of struck-through spaces rather than of ─ characters. When a
# pane gets narrower WezTerm wraps text onto more rows but leaves a row of
# spaces alone, so a rule made of them stays one row and the prompt keeps its
# height; made of ─ it folded onto a second row at every split. It goes inside
# %{ %} so that zsh counts it as taking no room either: zsh assumes anything
# longer than the window has been wrapped. One column short of the window, as
# zsh miscounts a prompt line that is full.
_wz_rule=$'%F{238}%{\e[9m${(l:COLUMNS-1:: :):-}\e[29m%}%f'
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
  _wz_git_info
  _wz_p_env=${${CONDA_DEFAULT_ENV:-${VIRTUAL_ENV:t}}//\%/%%}
  _wz_p_branch=${_wz_branch//\%/%%}
  [[ $_wz_branch == ${_wz_sent_branch-} ]] || _wz_set_var WEZ_BRANCH "${_wz_sent_branch::=$_wz_branch}"

  # A red mark when the last command failed; 130 is only Ctrl+C.
  _wz_chips=
  _wz_chip 9 '✘ %?'
  local failed=$_wz_chips
  _wz_chips=
  [[ -n $_wz_p_env ]] && _wz_chip 15 $'\uf489  ${_wz_p_env}'
  # The folder is the chip that gives way when they do not all fit: it keeps
  # its end, which is where you are. $_wz_p_rest is the room the others need.
  _wz_chip 15 $_wz_link_folder$'\uf413  %(l.%$(( COLUMNS - _wz_p_rest > 12 ? COLUMNS - _wz_p_rest : 12 ))<…<%~%<<.)'$_wz_link_end
  if [[ -n $_wz_p_branch ]]; then
    _wz_chip 10 $'\uf418  ${_wz_p_branch}'
    _wz_count_changes && _wz_chip 250 '± ${_wz_p_changes}'
  fi
  # 8 columns go around each chip's text, and the red mark may yet join them.
  _wz_p_rest=$(( 20 + ${#_wz_p_took} + (${#_wz_p_env} ? ${#_wz_p_env} + 8 : 0)
    + (${#_wz_p_branch} ? ${#_wz_p_branch} + ${#_wz_p_changes} + 16 : 0) ))
  # The chips never run onto a second row: whatever still does not fit is cut
  # off. A prompt that changed height with the width of the window would be
  # redrawn in the wrong place by zsh, which has no idea the terminal rewraps.
  PROMPT=$_wz_mark_prompt$_wz_rule$'\n''%-2>…>%(130?..%(?..'$failed'))'$_wz_chips'%F{244}${_wz_p_took:+took $_wz_p_took}%f%<<%b%k%f'$_wz_link_end$'\n\n'$_wz_mark_input
}

# An empty row above every prompt, like the spacing between Warp's blocks. The
# first prompt has one too, and so has a cleared screen: when WezTerm and zsh
# between them redraw the prompt a row too high (see _wz_resized), this is the
# row it lands on, rather than on the last line of output.
_wz_gap() { print }
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
  if [[ $CONTEXT == start && -z ${BUFFER//[[:space:]]} ]]; then
    # Enter with nothing typed: bring the chips up to date where they are,
    # instead of leaving an empty block behind as a plain shell would.
    BUFFER=
    _wz_prompt_precmd
    zle .reset-prompt
  elif [[ $CONTEXT == start && $BUFFER == '# '?* ]]; then
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

# ---- A new pane --------------------------------------------------------------

# Warp opens a new session with a few shortcuts above the first prompt, so that
# an empty window is not just empty. This prints the same kind of note in the
# first shell of a pane: not when this file is loaded again, and not in a shell
# started from that one. It is ordinary output, so it scrolls away as you work
# and Cmd+K removes it. `welcome = false` in wezterm.lua turns it off.
_wz_welcome() {
  local keys text
  local -a notes=(
    '#'     'ask Claude for the command'
    '⌘ O'   'open a project'
    '⇧ ⌘ O' 'open it with Claude Code'
    '⌘ D'   'split right, Shift for down'
    '⌘ P'   'all commands'
  )
  print -P '\n %B%F{15}  New terminal session%f%b'
  # One chip to a shortcut, drawn as the prompt's chips are, with their right
  # edges in line. Each has an empty row above it: chips on neighbouring rows
  # run into one another.
  for keys text in $notes; do
    print -P -- $'\n'"${(l:6-$#keys:: :):-}"$'%F{236}%K{236}%F{252} '$keys$' %k%F{236}%f  %F{244}'$text'%f'
  done
}

# Not in a pane too small for it: it would wrap, or leave no room to work in.
if [[ ${WEZ_WELCOMED-none} != ${WEZTERM_PANE-} ]]; then
  export WEZ_WELCOMED=${WEZTERM_PANE-}
  [[ ${WEZ_WELCOME-1} != 0 ]] && (( COLUMNS >= 44 && LINES >= 28 )) && _wz_welcome
fi

# ---- Changes of size ---------------------------------------------------------

# A new shell starts at the top of the window, as in any terminal. The prompt
# moves down as commands print, and stays at the bottom once the screen is full.

# WezTerm rewraps text when a pane changes width, and in doing so moves a
# cursor that is in the first column up onto the row above: it takes it for one
# that has just wrapped off the end of that row. A command line with nothing
# typed on it is exactly that. zsh redraws the prompt from wherever the cursor
# is, so it draws it one row too high, on the empty row _wz_gap left. A pane
# that has just been split then sits a row out of place, and a second change of
# width would put the prompt over the last line of output. zsh has redrawn by
# the time a trap runs, so the prompt is drawn once more, a row lower: a
# cursor-down slipped in ahead of it does that.
_wz_resized() {
  [[ $CONTEXT == start && ( -z $LBUFFER || $LBUFFER == *$'\n' ) ]] || return 0
  local prompt=$PROMPT
  PROMPT=$'%{\e[B%}'$PROMPT
  zle .reset-prompt
  zle -R
  PROMPT=$prompt
}
zle -N _wz_resized

_wz_columns=$COLUMNS
TRAPWINCH() {
  local -i was=$_wz_columns
  _wz_columns=$COLUMNS
  # Only if zle was waiting for a key when it happened. A widget that is still
  # running, such as an open list, hears of it here only when it ends, and by
  # then it has redrawn the prompt itself.
  zle && (( was != COLUMNS && $#funcstack == 1 )) && zle _wz_resized
  return 0
}

# Ctrl+L, which is also what Cmd+K sends. zsh redraws the prompt on the first
# row of the cleared screen; one row is added above it, so that the empty row
# every prompt has is there as well.
_wz_clear() {
  zle .clear-screen
  zle -R
  printf '\e7\e[H\e[L\e8\e[B'
}
zle -N clear-screen _wz_clear

unset _wz_seq _wz_widget _wz_style _wz_integration _wz_share

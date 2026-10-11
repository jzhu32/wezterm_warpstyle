"""Checks shell.zsh by driving a real zsh in a pseudo-terminal.

    python3 tests/test_shell.py                # shell.zsh on its own
    python3 tests/test_shell.py --with-zshrc   # on top of your own ~/.zshrc

History, the clipboard and zoxide's data go to a throwaway folder, and a
stand-in replaces Claude Code, so nothing of yours is touched or spent.
"""
import os, pty, select, shutil, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WITH_ZSHRC = "--with-zshrc" in sys.argv
HOME = os.path.realpath(tempfile.mkdtemp(prefix="wezterm-warp-test-"))  # startup folder: .zshrc, state, clipboard
REAL_HOME = os.path.expanduser("~") if WITH_ZSHRC else HOME
BREW = "/opt/homebrew" if os.path.isdir("/opt/homebrew") else "/usr/local"
PANE = "99907"
SEL = os.path.join(REAL_HOME, ".cache/wezterm-warp/selection-" + PANE)

with open(os.path.join(HOME, ".zshrc"), "w") as f:
    f.write("source ~/.zshrc\n" if WITH_ZSHRC else "source '%s/shell.zsh'\n" % REPO)
    f.write(r"""
_wz_clip() { cat > $ZDOTDIR/clip }
_dbg() { print -rn -- "${BUFFER}|${CURSOR}|${MARK}|${REGION_ACTIVE}" > $ZDOTDIR/state }
zle -N _dbg; bindkey '^Xq' _dbg
_where() { print -rn -- $PWD > $ZDOTDIR/where }; zle -N _where; bindkey '^Xw' _where
_dump() { { bindkey '^R'; bindkey '^T'; whence -w z; } > $ZDOTDIR/dump 2>&1 }
HISTFILE=$ZDOTDIR/hist; HISTSIZE=100; SAVEHIST=100
fc -p $ZDOTDIR/hist
print -s 'git status --short'
print -s 'echo history-entry'
print -s 'git log --oneline'
path=($ZDOTDIR/bin $path)
""")
os.makedirs(os.path.join(HOME, "bin"))
with open(os.path.join(HOME, "bin", "claude"), "w") as f:
    f.write(r"""#!/bin/sh
# Stand-in for Claude Code: records how it was called and answers with a fixed command.
printf '%s\n' "$@" > "$ZDOTDIR/claude-args"
pwd -P > "$ZDOTDIR/claude-cwd"
case "$*" in *"nothing useful"*) exit 0;; esac
printf 'du -sh * | sort -h\n'
""")
os.chmod(os.path.join(HOME, "bin", "claude"), 0o755)

ENV = {
    "HOME": REAL_HOME, "ZDOTDIR": HOME, "TERM": "xterm-256color", "TERM_PROGRAM": "WezTerm",
    "WEZTERM_PANE": PANE, "PATH": BREW + "/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOMEBREW_PREFIX": BREW,
    "LANG": "en_US.UTF-8", "_ZO_DATA_DIR": os.path.join(HOME, "zo"),
}
pid, fd = pty.fork()
if pid == 0:
    os.chdir(REAL_HOME)
    os.execve("/bin/zsh", ["zsh", "-i"], ENV)

out = bytearray()
def drain(wait):
    end = time.time() + wait
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: out.extend(os.read(fd, 65536))
            except OSError: return

def send(s, wait=0.25):
    os.write(fd, s.encode()); drain(wait)

def state():
    p = os.path.join(HOME, "state")
    if os.path.exists(p): os.remove(p)
    send("\x18q", 0.3)
    buf, cur, mark, active = open(p).read().rsplit("|", 3)
    return buf, int(cur), int(mark), int(active)

def clip():
    return open(os.path.join(HOME, "clip")).read()

def reset():
    send("\x03", 0.35)

SL, SR = "\x1b[1;2D", "\x1b[1;2C"          # shift+left/right
SWL, SWR = "\x1b[1;4D", "\x1b[1;4C"        # shift+option+left/right
SHOME, SEND = "\x1b[1;2H", "\x1b[1;2F"
LEFT, RIGHT, UP, DOWN = "\x1b[D", "\x1b[C", "\x1b[A", "\x1b[B"
HOME_K, END_K = "\x1b[H", "\x1b[F"
ALL, COPY, CUT, REDO, ADOPT = "\x1b[990~", "\x1b[991~", "\x1b[992~", "\x1b[993~", "\x1b[994~"
BS, DEL, UNDO = "\x7f", "\x1b[3~", "\x1f"

results = []
def check(name, got, want):
    ok = got == want
    results.append(ok)
    print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else f"\n        got  {got!r}\n        want {want!r}"))

drain(3.0)
startup = bytes(out)

send("echo hello world"); send(SL * 5)
check("shift+left x5 selects 'world'", state(), ("echo hello world", 11, 16, 1))
send(BS)
s = state()
check("backspace deletes the selection", (s[0], s[1], s[3]), ("echo hello ", 11, 0))
reset()

send("echo hello world"); send(SWL); send("X")
check("typing replaces a word selection", state()[0], "echo hello X")
reset()

send("echo hello world"); send(SL * 3); send(LEFT)
check("plain left drops the selection", state()[3], 0)
check("  ...and text is untouched", state()[0], "echo hello world")
reset()

send("echo hello world"); send(ALL)
check("cmd+a selects everything", state(), ("echo hello world", 16, 0, 1))
send(COPY)
check("cmd+c copies it", clip(), "echo hello world")
check("  ...and keeps the selection", state()[3], 1)
send(CUT)
check("cmd+x empties the line", state()[0], "")
check("  ...into the clipboard", clip(), "echo hello world")
send(UNDO)
check("cmd+z brings it back", state()[0], "echo hello world")
send(REDO)
check("cmd+shift+z redoes", state()[0], "")
reset()

send("echo hello world"); send(SWL); send("\x1b[200~PASTED\x1b[201~")
check("paste replaces the selection", state()[0], "echo hello PASTED")
reset()

send("echo hello world"); send(HOME_K); send(SEND); send(DEL)
check("home, shift+end, delete clears the line", state()[0], "")
reset()

send("cp /usr/local/bin/tool dest"); send(SWL); send(SWL)
check("shift+option+left stops inside a path", state()[:2], ("cp /usr/local/bin/tool dest", 18))
reset()

send("git commit -m fix")
open(SEL, "w").write("commit")
send(ADOPT)
check("mouse selection is adopted", state(), ("git commit -m fix", 10, 4, 1))
send(BS)
check("  ...and backspace removes it", state()[0], "git  -m fix")
reset()

send("echo aa bb aa")
open(SEL, "w").write("aa")
send(ADOPT)
check("ambiguous mouse selection is ignored", state()[3], 0)
reset()

send("echo one")
open(SEL, "w").write("not in the command")
send(ADOPT); send(BS)
check("selection from output leaves the command alone", state()[0], "echo on")
reset()

send("echo [x] *"); send(ALL); send(SL * 0)
open(SEL, "w").write("[x] *")
send(LEFT); send(ADOPT)
check("glob characters are matched literally", state(), ("echo [x] *", 10, 5, 1))
reset()

send("echo a"); send("\x1b\r"); send("echo b")
check("shift+enter adds a line", state()[0], "echo a\necho b")
reset()

send("echo hello world"); send("\x15")
check("cmd+backspace deletes to line start", state()[0], "")
reset()

send("git"); send(UP)
check("up searches history by prefix", state()[0], "git log --oneline")
reset()
send("git"); send(UP); send(UP)
check("  ...and again", state()[0], "git status --short")
reset()
send("git"); send(UP); send(UP); send(DOWN)
check("  ...and down goes back", state()[0], "git log --oneline")
reset()


TO_START, TO_END = "\x1b[995~", "\x1b[996~"
NL = "\x1b\r"

send("echo one"); send(NL); send("echo two  "); send(NL); send("echo three")
open(SEL, "w").write("one\necho two\necho")      # as the terminal reports it: no trailing spaces
send(ADOPT)
check("mouse selection across lines is adopted", state(), ("echo one\necho two  \necho three", 24, 5, 1))
send(BS)
check("  ...and backspace removes all of it", state()[0], "echo  three")
reset()

send("echo a#b ^c ~d (e|f) <1-2>")
open(SEL, "w").write("a#b ^c ~d (e|f) <1-2>")
send(ADOPT)
check("pattern characters in a selection are literal", state()[1:], (26, 5, 1))
reset()

send("line one"); send(NL); send("line two"); send(NL); send("line three"); send(LEFT * 5)
send(TO_START)
check("cmd+shift+up selects everything above", state()[1:], (0, 23, 1))
send(BS)
check("  ...and backspace deletes it", state()[0], "three")
reset()

send("line one"); send(NL); send("line two"); send(HOME_K); send(UP); send(TO_END); send(BS)
check("cmd+shift+down then backspace deletes everything below", state()[0], "")
reset()

send("line one"); send(NL); send("line two"); send(NL); send("line three"); send(ALL); send(BS)
check("cmd+a then backspace clears several lines", state()[0], "")
reset()

send("line one"); send(NL); send("line two"); send("\x15"); send("\x15"); send("\x15")
check("repeated cmd+backspace climbs up through lines", state()[0], "")
reset()

# A folder whose name looks like code and like a prompt escape must only be shown.
trap = os.path.join(HOME, "trap $(touch PWNED) %F{red}`touch PWNED2`")
os.makedirs(trap, exist_ok=True)
for f in ("PWNED", "PWNED2"):
    if os.path.exists(os.path.join(trap, f)): os.remove(os.path.join(trap, f))
before = len(out)
send("cd '" + trap + "'\r", 0.8)
send("true\r", 0.8)
check("a hostile folder name is not executed", [f for f in ("PWNED", "PWNED2") if os.path.exists(os.path.join(trap, f))], [])
check("  ...and is shown literally", b"$(touch PWNED) %F{red}`touch PWNED2`" in bytes(out[before:]), True)
send("cd\r", 0.6)

before = len(out)
send("false\r", 0.8)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("failed command shows a red mark with its status", "✘ 1" in shown, True)
check("prompt has the folder chip", "  ~" in shown, True)
check("entered command collapses to the compact header", "\x1b[38;5;244m" in shown and "~" in shown, True)
check("prompt and input are marked for the terminal", "\x1b]133;P;k=i\x07" in shown and "\x1b]133;B\x07" in shown, True)
check("tab title is set to the command while it runs", "\x1b]0;false\x07" in shown, True)
check("program name is reported for the tab", "SetUserVar=WEZ_CMD=ZmFsc2U=" in shown, True)


send("# how big is each folder here\r", 1.2)
check("a line starting with # asks for a command instead of running", state()[0], "du -sh * | sort -h")
args = open(os.path.join(HOME, "claude-args")).read()
check("  ...as a one-off question with no tools", "-p\n" in args and "--tools\n\n" in args and "--no-session-persistence" in args, True)
check("  ...sending only the words typed, never the folder", "Request: how big is each folder here" in args and HOME not in args and "folder:" not in args, True)
check("  ...and running Claude in an empty folder of its own", open(os.path.join(HOME, "claude-cwd")).read().strip(), os.path.realpath(os.path.join(REAL_HOME, ".cache/wezterm-warp/ask")))
reset()
send(UP)
check("  ...and Up brings the request back", state()[0], "# how big is each folder here")
reset()
send("# nothing useful\r", 1.2)
check("no suggestion leaves the request on the line", state()[0], "# nothing useful")
reset()
send("#notaquestion"); 
check("a # without a space is left alone until Enter", state()[0], "#notaquestion")
reset()

before = len(out)
send("sleep 2.1\r", 3.0)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a command that took a while says how long", "took 2." in shown, True)
check("  ...without ringing the bell", "\x07took" in shown or shown.count("\x07") > shown.count("\x1b]"), False)
before = len(out)
send("_wz_started=$(( EPOCHREALTIME - 95 ))\r", 1.0)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a long command shows minutes", "took 1m 35s" in shown, True)
bells = [i for i, c in enumerate(shown) if c == "\x07" and "\x1b]" not in shown[max(0, i - 400):i].rsplit("\x07", 1)[-1]]
check("  ...and rings the bell for the tab", len(bells) >= 1, True)
before = len(out)
send("true\r", 0.8)
check("a quick command says nothing about time", "took" in bytes(out[before:]).decode("utf-8", "replace"), False)

send("_dump\r", 0.8)
dump = open(os.path.join(HOME, "dump")).read()
check("ctrl+r is fuzzy history search", "fzf-history-widget" in dump, True)
check("ctrl+t is the file finder", "fzf-file-widget" in dump, True)
check("z jumps to folders", "z: function" in dump, True)


PICK, TAB, ESC = "\x1b[997~", "\t", "\x1b"
def where():
    w = os.path.join(HOME, "where")
    if os.path.exists(w): os.remove(w)
    send("\x18w", 0.3)
    return open(w).read()
nav = os.path.realpath(os.path.join(HOME, "nav"))
for sub in ("alpha", "beta/inner", "gamma with space"):
    os.makedirs(os.path.join(nav, sub), exist_ok=True)
send("cd '" + nav + "'\r", 0.8)
send("echo keep"); send(PICK, 1.2); send("bet", 0.5); send("\r", 1.2)
check("folder list: Enter goes into the highlighted folder", where(), nav + "/beta")
check("  ...and what was typed is still there", state()[0], "echo keep")
reset()
send(PICK, 1.2); send("\r", 1.2)
check("folder list: the first entry is the parent folder", where(), nav)
send(PICK, 1.2); send("bet", 0.5); send(TAB, 1.0); send("inn", 0.5); send("\r", 1.2)
check("folder list: Tab looks inside, Enter then goes two levels down", where(), nav + "/beta/inner")
send("cd '" + nav + "'\r", 0.8)
send(PICK, 1.2); send("space", 0.5); send("\r", 1.2)
check("folder list: names with spaces work", where(), nav + "/gamma with space")
send(PICK, 1.2); send(ESC, 1.0)
check("folder list: Esc changes nothing", where(), nav + "/gamma with space")
send(PICK, 1.2); send("zzzz", 0.5); send("\r", 1.0)
check("folder list: Enter with no match changes nothing", where(), nav + "/gamma with space")
before = len(out)
send("cd\r", 0.8)
check("folder chip is a link the terminal can click", "\x1b]8;;wezwarp:folder\x1b\\" in bytes(out[before:]).decode("utf-8", "replace"), True)


# A repository from somewhere else must not get the prompt to run its programs.
import subprocess
evil = os.path.realpath(os.path.join(HOME, "evil-repo"))
os.makedirs(evil)
git_env = dict(os.environ, HOME=HOME, GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.com",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.com")
def git(*args, **kw):
    return subprocess.run(["git", "-C", evil] + list(args), env=git_env, capture_output=True, text=True, **kw)
git("init", "-q", "-b", "main")
open(os.path.join(evil, "file.txt"), "w").write("one\n")
git("add", "-A"); git("commit", "-q", "-m", "start")
open(os.path.join(evil, "file.txt"), "w").write("two\n")
ran = lambda: sorted(f for f in os.listdir(evil) if f.startswith("RAN-"))

git("config", "core.fsmonitor", "sh -c 'touch RAN-watcher' #")
git("status")
check("(this test is real: plain git would run the repository's file watcher)", ran(), ["RAN-watcher"])
os.remove(os.path.join(evil, "RAN-watcher"))
before = len(out)
send("cd '" + evil + "'\r", 1.2); send("true\r", 1.0)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a repository's file watcher is not run by the prompt", ran(), [])
check("  ...and its changes are still counted", "\u00b1 1" in shown, True)

git("config", "--unset", "core.fsmonitor")
git("config", "filter.x.clean", "sh -c 'touch RAN-filter; cat'")
open(os.path.join(evil, ".gitattributes"), "w").write("*.txt filter=x\n")
open(os.path.join(evil, "file.txt"), "w").write("three\n")
git("status")
check("(and plain git would run the repository's content filter)", ran(), ["RAN-filter"])
os.remove(os.path.join(evil, "RAN-filter"))
open(os.path.join(evil, "file.txt"), "w").write("four\n")
before = len(out)
send("true\r", 1.0)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a repository's content filter is not run by the prompt", ran(), [])
check("  ...such a repository shows its branch but no change count", "main" in shown and "±" not in shown, True)

# The same filter, hidden in a file the repository's settings pull in.
git("config", "--unset", "filter.x.clean")
open(os.path.join(evil, ".git", "extra"), "w").write("[filter \"x\"]\n\tclean = \"sh -c 'touch RAN-hidden-filter; cat'\"\n")
git("config", "include.path", "extra")
open(os.path.join(evil, "file.txt"), "w").write("five\n")
git("status")
check("(plain git would run a filter hidden in an included file)", ran(), ["RAN-hidden-filter"])
for f in ran(): os.remove(os.path.join(evil, f))
open(os.path.join(evil, "file.txt"), "w").write("six\n")
before = len(out)
send("true\r", 1.0)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a filter hidden in an included file is not run either", ran() == [] and "±" not in shown, True)
git("config", "--unset", "include.path")
open(os.path.join(evil, ".gitattributes"), "w").write("")

# A fetch through a made-up transport, triggered by an object that is missing.
head = git("rev-parse", "HEAD").stdout.strip()
tree = git("rev-parse", "HEAD^{tree}").stdout.strip()
git("config", "extensions.partialClone", "origin")
git("config", "remote.origin.promisor", "true")
git("config", "remote.origin.url", "ext::sh -c 'touch RAN-fetch' %S")
os.remove(os.path.join(evil, ".git", "objects", tree[:2], tree[2:]))
git("status")
real_fetch = ran() == ["RAN-fetch"]
for f in ran(): os.remove(os.path.join(evil, f))
before = len(out)
send("true\r", 1.2)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a repository cannot make the prompt fetch through its own program" + ("" if real_fetch else " (plain git did not either on this version)"), ran(), [])
check("  ...and the prompt still shows the branch", "main" in shown, True)

# Settings git cannot read at all: no count, nothing run, prompt intact.
open(os.path.join(evil, ".git", "config"), "a").write("\n[this is not valid\n")
before = len(out)
send("true\r", 1.0)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("unreadable repository settings mean no count rather than a guess", "±" not in shown and "" in shown and ran() == [], True)
send("cd\r", 0.6)

# A new repository with no commits yet still shows its branch.
fresh = os.path.realpath(os.path.join(HOME, "fresh-repo"))
os.makedirs(fresh)
subprocess.run(["git", "-C", fresh, "init", "-q", "-b", "trunk"], env=git_env, capture_output=True)
before = len(out)
send("cd '" + fresh + "'\r", 1.2)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("a repository with no commits yet shows its branch and a count", "trunk" in shown and "± 0" in shown, True)
send("cd\r", 0.6)


# Enter with nothing typed must not leave an empty block in the scrollback.
reset()
prompts = lambda: bytes(out).count(b"\x1b]133;A")
before, started = len(out), prompts()
send("\r", 0.8); send("   \r", 0.8)
shown = bytes(out[before:]).decode("utf-8", "replace")
check("Enter on an empty line starts no new block", prompts() - started, 0)
check("  ...the chips are redrawn where they were", "\ue0b6" in shown and "\uf413" in shown, True)
check("  ...the line stays empty and usable", state()[0], "")
send("echo after-empty\r", 0.8)
check("  ...and the next command runs normally", b"after-empty\r\n" in bytes(out[before:]), True)

# Sourcing the setup again in the same shell must not double anything up.
before = len(out)
send("source '" + os.path.join(REPO, "shell.zsh") + "'\r", 2.0)
started = prompts()
send("true\r", 1.0)
check("sourcing the setup twice still gives one prompt per command", prompts() - started, 1)
send("echo hello world"); send(SL * 5); send(BS)
check("  ...and editing still works", state()[0], "echo hello ")
reset()

send("echo hi\r", 0.6)
tail = bytes(out)
check("prompt marks emitted (OSC 133)", b"\x1b]133;A" in startup, True)
check("at-prompt signal emitted", b"SetUserVar=WEZ_ZLE=MQ==" in startup, True)
check("in-command signal emitted", b"SetUserVar=WEZ_ZLE=MA==" in tail, True)
bad = [w for w in (b"command not found", b"no such", b"parse error", b"bad ", b"unknown", b"not an identifier", b"permission denied") if w in startup.lower()]
check("no errors while loading", bad, [])

send("exit\r", 0.3)
print(f"\n{sum(results)}/{len(results)} passed")
if "-v" in sys.argv:
    print(repr(startup[-600:]))
shutil.rmtree(HOME, ignore_errors=True)
sys.exit(0 if all(results) else 1)

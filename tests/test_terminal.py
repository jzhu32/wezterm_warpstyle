"""Checks the things that depend on WezTerm itself, in a real WezTerm.

    python3 tests/test_terminal.py

A split or a resize must leave the prompt on the rows it was on, with the
output above it untouched. Whether it does is decided by what WezTerm does to
the text and the cursor when a pane changes size, and a stand-in terminal
cannot tell you that. So this starts WezTerm's own engine without a window
(wezterm-mux-server), runs zsh with shell.zsh in it, splits and resizes panes
the way you would, and reads back what each one holds.

It has its own socket, home folder and history, so nothing of yours is touched.
"""
import atexit, collections, json, os, re, shutil, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHELL_ZSH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "shell.zsh")
APP = "/Applications/WezTerm.app/Contents/MacOS"
BREW = "/opt/homebrew" if os.path.isdir("/opt/homebrew") else "/usr/local"

def find(name):
    return shutil.which(name) or next((p for p in [os.path.join(APP, name)] if os.path.exists(p)), None)

WEZTERM, SERVER = find("wezterm"), find("wezterm-mux-server")
if not (WEZTERM and SERVER):
    print("Skipped: these need WezTerm itself (wezterm and wezterm-mux-server).")
    sys.exit(0)

# Kept short on purpose: the path of a unix socket may be at most 104 bytes.
# The real path, so that zsh's idea of the folder it is in matches $HOME.
ROOT = os.path.realpath(tempfile.mkdtemp(prefix="wzt-"))
HOME, SOCK = os.path.join(ROOT, "home"), os.path.join(ROOT, "s")
os.makedirs(HOME)
ROWS, COLS = 40, 120

with open(os.path.join(HOME, ".zshrc"), "w") as f:
    f.write("source '%s'\n" % SHELL_ZSH)
with open(os.path.join(ROOT, "wezterm.lua"), "w") as f:
    f.write("""
local wezterm = require("wezterm")
local config = wezterm.config_builder()
config.unix_domains = { { name = "unix", socket_path = "%s" } }
config.initial_rows, config.initial_cols = %d, %d
config.default_prog = { "/bin/zsh", "-i" }
config.default_cwd = "%s"
return config
""" % (SOCK, ROWS, COLS, HOME))

ENV = {
    "HOME": HOME, "ZDOTDIR": HOME, "PATH": BREW + "/bin:/usr/bin:/bin:/usr/sbin:/sbin", "HOMEBREW_PREFIX": BREW,
    "LANG": "en_US.UTF-8", "_ZO_DATA_DIR": os.path.join(ROOT, "zo"), "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
}
server = subprocess.Popen([SERVER, "--config-file", os.path.join(ROOT, "wezterm.lua")], env=ENV,
                          stdout=subprocess.DEVNULL, stderr=open(os.path.join(ROOT, "server.log"), "w"))

@atexit.register
def stop():
    server.terminate()
    try: server.wait(5)
    except subprocess.TimeoutExpired: server.kill()
    shutil.rmtree(ROOT, ignore_errors=True)

def cli(*args):
    return subprocess.run([WEZTERM, "-n", "cli", "--no-auto-start", *map(str, args)], capture_output=True, text=True,
                          env=dict(ENV, WEZTERM_UNIX_SOCKET=SOCK), timeout=30).stdout

Look = collections.namedtuple("Look", "rows cols cursor above screen")

def look(pane):
    """What a pane holds: its size, the cursor's row, the rows that have scrolled off the top, and the screen."""
    info = next((p for p in json.loads(cli("list", "--format", "json") or "[]") if p["pane_id"] == pane), None)
    if not info:
        return None
    rows = info["size"]["rows"]
    lines = cli("get-text", "--pane-id", pane, "--start-line", -5000, "--end-line", rows - 1).split("\n")[:-1]
    return Look(rows, info["size"]["cols"], info["cursor_y"], lines[:-rows], lines[-rows:])

def settled(pane, ready=lambda s: True, wait=10.0):
    """The pane once it has stopped changing and `ready` holds; whatever it shows if that never comes."""
    end, last, same = time.time() + wait, None, 0
    while time.time() < end:
        now = look(pane)
        same = same + 1 if now is not None and now == last else 0
        if same >= 2 and ready(now):
            return now
        last = now
        time.sleep(0.1)
    return last

FOLDER = ""  # the icon on the folder chip: marks the row of chips
def chips(s):
    found = [i for i, line in enumerate(s.screen) if FOLDER in line]
    return found[-1] if found else None

def where(s, text):
    return [i for i, line in enumerate(s.screen) if text in line]

def place(s):
    """The rows the prompt is on: (the chips, the line you type)."""
    return (chips(s), s.cursor)

# A prompt is an empty row, the rule, the chips, an empty row, the line you type.
# TOP is one on an empty screen; FRESH is the first one in a new pane, under
# the eight rows of shortcuts it opens with.
TOP, FRESH = (2, 4), (10, 12)
NOTE = "New terminal session"
def bottom(s): return (s.rows - 3, s.rows - 1)
def whole(s):
    """True if the prompt is in one piece: the line you type two rows under the chips, one row of chips."""
    return chips(s) is not None and s.cursor - chips(s) == 2
at_prompt = lambda s: chips(s) is not None
def shows(text): return lambda s: at_prompt(s) and bool(where(s, text))
def sized(rows=None, cols=None): return lambda s: at_prompt(s) and rows in (None, s.rows) and cols in (None, s.cols)

def send(pane, text):
    cli("send-text", "--pane-id", pane, "--no-paste", text)

def run(pane, command, marker=None):
    send(pane, command + "\n")
    # The marker shows twice once the command has run: where it was typed, and where it printed.
    return settled(pane, lambda s: at_prompt(s) and len(where(s, marker or command)) >= (2 if marker else 1))

def split(pane, side):
    new = int(cli("split-pane", "--pane-id", pane, "--" + side).strip())
    return new

def close(pane):
    cli("kill-pane", "--pane-id", pane)

results = []
def check(name, got, want):
    ok = got == want
    results.append(ok)
    print(("PASS  " if ok else "FAIL  ") + name + ("" if ok else f"\n        got  {got!r}\n        want {want!r}"), flush=True)

# The server opens one window with zsh in it when it starts.
main = None
for _ in range(150):
    listed = cli("list", "--format", "json")
    if listed.strip().startswith("["):
        main = json.loads(listed)[0]["pane_id"]
        break
    time.sleep(0.1)
if main is None:
    print("FAIL  WezTerm's engine did not start\n" + open(os.path.join(ROOT, "server.log")).read())
    sys.exit(1)

# ---- A new shell ---------------------------------------------------------------

s = settled(main, at_prompt)
check("a new shell opens with its list of shortcuts at the top of the window", (where(s, NOTE), where(s, "all commands")), ([1], [7]))
check("  ...a title, an empty row, then one shortcut to a row", [i for i in range(8) if s.screen[i].strip()], [1, 3, 4, 5, 6, 7])
check("  ...and the chips all end in the same column, beside what they do", sorted({line.index("\ue0b4") for line in s.screen[3:8]}), [9])
check("  ...the first prompt under it, after an empty row", (place(s), s.screen[chips(s) - 2].strip()), (FRESH, ""))
check("  ...and nothing above the screen", len(s.above), 0)
check("the rule is a row of spaces, which WezTerm does not wrap", s.screen[chips(s) - 1].strip(), "")

s = run(main, "echo first-output", "first-output")
check("after a command the prompt has moved down, under its output", (where(s, "first-output")[-1], whole(s)), (chips(s) - 3, True))
check("  ...and still nothing is above the screen", len(s.above), 0)
home = place(s)

# ---- Side by side -------------------------------------------------------------

right = split(main, "right")
r = settled(right, at_prompt)
s = settled(main, sized(cols=COLS - r.cols - 1))
check("splitting to the right leaves the first pane's prompt on the rows it was on", place(s), home)
check("  ...with its output still right above it, and only once", (where(s, "first-output")[-1], len(where(s, "first-output"))), (chips(s) - 3, 2))
check("  ...and the new pane starts at the top, with the shortcuts", (place(r), where(r, NOTE)), (FRESH, [1]))
check("  ...with nothing above either screen", (len(s.above), len(r.above)), (0, 0))

places = []
for direction, amount in (("Left", 14), ("Right", 30), ("Left", 9), ("Right", 2), ("Left", 9)):
    before = look(main).cols
    cli("adjust-pane-size", "--pane-id", main, "--amount", amount, direction)
    s = settled(main, lambda s: at_prompt(s) and s.cols != before)
    r = settled(right, at_prompt)
    places += [place(s), place(r)]
check("dragging the divider back and forth never moves either prompt", places, [home, FRESH] * 5)
check("  ...or the output above the first", (where(s, "first-output")[-1], len(where(s, "first-output"))), (chips(s) - 3, 2))

send(main, "echo half-typed")
settled(main, shows("half-typed"))
before = look(main).cols
cli("adjust-pane-size", "--pane-id", main, "--amount", 11, "Left")
s = settled(main, lambda s: s.cols != before)
check("with a command half typed, a change of width leaves it where it is", (s.screen[s.cursor].strip(), place(s)), ("echo half-typed", home))
send(main, "\x15")

close(right)
s = settled(main, sized(cols=COLS))
check("closing the split leaves the prompt on the same rows", place(s), home)
check("  ...with the output still right above it", (where(s, "first-output")[-1], len(where(s, "first-output"))), (chips(s) - 3, 2))

# ---- One above the other ------------------------------------------------------

below = split(main, "bottom")
b = settled(below, at_prompt)
s = settled(main, sized(rows=ROWS - b.rows - 1))
check("splitting downwards leaves the first pane's prompt whole, right under its output", (whole(s), where(s, "first-output")[-1]), (True, chips(s) - 3))
check("  ...and the new pane, half the height, still has room for the shortcuts", (place(b), len(b.above)), (FRESH, 0))
short = int(cli("split-pane", "--pane-id", below, "--bottom", "--cells", 9).strip())
t = settled(short, at_prompt)
check("  ...but a pane too short for them opens without", (t.rows, where(t, NOTE), place(t)), (9, [], TOP))
close(short)
settled(below, sized(rows=b.rows))
s = run(main, "echo second-output", "second-output")
close(below)
s = settled(main, sized(rows=ROWS))
# The half-height pane had filled up and begun to scroll; with its full height
# back, what scrolled off returns and the prompt is under its output as before.
check("closing the lower pane leaves the prompt right under its output", (whole(s), where(s, "second-output")[-1]), (True, chips(s) - 3))
check("  ...with both outputs back on the screen, and nothing above it", (len(where(s, "first-output")), len(where(s, "second-output")), len(s.above)), (2, 2, 0))

# ---- Typing ahead -------------------------------------------------------------

send(main, "sleep 1; echo slow-done\n")
time.sleep(0.3)
send(main, "echo typed-early\n")
s = settled(main, lambda s: at_prompt(s) and len(where(s, "typed-early")) >= 3, wait=15)
check("a command typed while another runs is run afterwards, untouched", where(s, "slow-done")[-1] < where(s, "typed-early")[-1], True)
check("  ...and leaves nothing on the line", s.screen[s.cursor].strip(), "")

# ---- A full screen ------------------------------------------------------------

s = run(main, "seq 1 300", "300")
numbers = [line.strip() for line in s.above + s.screen]
check("output longer than the screen is all still there to scroll back to", [n for n in range(1, 301) if str(n) not in numbers], [])
check("  ...and the prompt is on the last rows", place(s), bottom(s))

right = split(main, "right")
r = settled(right, at_prompt)
s = settled(main, sized(cols=COLS - r.cols - 1))
check("with a screen full of output, a split leaves the prompt on the last rows", place(s), bottom(s))
check("  ...and the last line of output right above it", s.screen[chips(s) - 3].strip(), "300")
close(right)
s = settled(main, sized(cols=COLS))
numbers = [line.strip() for line in s.above + s.screen]
check("  ...and nothing is lost when it is closed again", ([n for n in range(1, 301) if str(n) not in numbers], place(s), s.screen[chips(s) - 3].strip()), ([], bottom(s), "300"))

# ---- Clearing -----------------------------------------------------------------

send(main, "clear\n")
s = settled(main, lambda s: at_prompt(s) and not where(s, "300"))
check("`clear` starts again at the top", place(s), TOP)
check("  ...with nothing else on the screen: the shortcuts are shown once", [l for l in s.screen[:chips(s) - 1] if l.strip()], [])

run(main, "echo to-be-cleared", "to-be-cleared")
send(main, "\x0c")
s = settled(main, lambda s: at_prompt(s) and not where(s, "to-be-cleared"))
check("Ctrl+L, which is what Cmd+K sends, does the same", place(s), TOP)
right = split(main, "right")
r = settled(right, at_prompt)
s = settled(main, sized(cols=COLS - r.cols - 1))
check("  ...and a split straight afterwards leaves it there", (place(s), place(r)), (TOP, FRESH))
close(right)
settled(main, sized(cols=COLS))

narrow = int(cli("split-pane", "--pane-id", main, "--right", "--cells", 36).strip())
n = settled(narrow, at_prompt)
check("a pane too narrow for the shortcuts opens without them", (n.cols, where(n, NOTE), place(n)), (36, [], TOP))
close(narrow)
settled(main, sized(cols=COLS))

send(main, "echo one\x1b\recho two\x1b\recho three")
settled(main, shows("echo three"))
send(main, "\x1b[A")
send(main, "\x0c")
s = settled(main, lambda s: at_prompt(s) and s.cursor == 5)
check("Ctrl+L with three lines typed keeps all three under the prompt", ([l.strip() for l in s.screen[4:7]], chips(s), s.cursor), (["echo one", "echo two", "echo three"], 2, 5))
send(main, "\x03")
settled(main, lambda s: at_prompt(s) and s.screen[s.cursor].strip() == "")

# ---- Shells that do not start on an empty screen ------------------------------

s = run(main, "echo keep-me", "keep-me")
send(main, "source $ZDOTDIR/.zshrc\n")
s = settled(main, lambda s: at_prompt(s) and len(where(s, "source")) >= 1 and s.screen[s.cursor].strip() == "")
check("loading shell.zsh again leaves what is on the screen where it is", (len(where(s, "keep-me")), whole(s)), (2, True))
check("  ...and does not show the shortcuts a second time", where(s, NOTE), [])
send(main, "zsh -i\n")
s = settled(main, lambda s: at_prompt(s) and len(where(s, "zsh -i")) >= 1 and s.screen[s.cursor].strip() == "")
check("so does a shell started inside this one", (len(where(s, "keep-me")), whole(s), where(s, NOTE)), (2, True, []))
send(main, "exit\n")
settled(main, lambda s: at_prompt(s) and len(where(s, "exit")) >= 1 and s.screen[s.cursor].strip() == "")

# ---- A folder too long for the pane -------------------------------------------

# The chips give way rather than run onto a second row. A prompt whose height
# changed with the width of the pane would be redrawn in the wrong place.
deep = os.path.join(HOME, "a-project-with-a-long-name", "packages", "web-frontend", "src", "components", "navigation")
os.makedirs(deep)
send(main, "clear\n")
settled(main, lambda s: at_prompt(s) and not where(s, "keep-me"))
send(main, "cd " + deep + "\n")
settled(main, lambda s: at_prompt(s) and bool(where(s, "navigation")) and s.screen[s.cursor].strip() == "")
s = run(main, "echo deep-output", "deep-output")
check("a long folder name still leaves the chips on one row", (whole(s), s.screen[chips(s)].rstrip().endswith("navigation ")), (True, True))
right = split(main, "right")
r = settled(right, at_prompt)
s = settled(main, sized(cols=COLS - r.cols - 1))
check("  ...in half the width it is cut short instead of wrapping", (whole(s), "…" in s.screen[chips(s)], len(s.screen[chips(s)].rstrip()) < s.cols), (True, True, True))
check("  ...in the new pane too", (place(r), "…" in r.screen[chips(r)]), (FRESH, True))
check("  ...and the output above is still there, once", len(where(s, "deep-output")), 2)
close(right)
s = settled(main, sized(cols=COLS))
check("  ...and widening again loses nothing", (whole(s), len(where(s, "deep-output")), len(s.above)), (True, 2, 0))
send(main, "cd\n")
settled(main, lambda s: at_prompt(s) and s.screen[chips(s)].rstrip().endswith("~ ") and s.screen[s.cursor].strip() == "")

# ---- Lists drawn under the prompt ---------------------------------------------

if os.path.exists(os.path.join(BREW, "bin", "fzf")):
    send(main, "clear\n")
    settled(main, lambda s: at_prompt(s) and not where(s, "deep-output"))
    s = run(main, "echo keep-me", "keep-me")
    home = place(s)
    send(main, "\x12")
    s = settled(main, lambda s: bool(where(s, "╭")))
    check("the history list opens under the prompt without moving it", (bool(where(s, "╭")), chips(s)), (True, home[0]))
    send(main, "\x1b")
    s = settled(main, lambda s: at_prompt(s) and not where(s, "╭"))
    check("  ...and closing it leaves everything where it was", (place(s), len(where(s, "keep-me")), len(s.above)), (home, 2, 0))
else:
    print("Skipped: the history list needs fzf.")

print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)

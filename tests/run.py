"""Runs every check for this setup.

    python3 tests/run.py                # the usual run
    python3 tests/run.py --with-zshrc   # shell checks on top of your own ~/.zshrc

Needs WezTerm and the Homebrew tools from the Brewfile. The config checks also
need Neovim, used only as a Lua interpreter (brew install neovim).
"""
import pathlib, shutil, subprocess, sys, tempfile

tests = pathlib.Path(__file__).resolve().parent
ok = True

print("== shell.zsh", flush=True)
ok &= subprocess.call([sys.executable, str(tests / "test_shell.py")] + sys.argv[1:]) == 0

print("\n== wezterm.lua", flush=True)
nvim = shutil.which("nvim")
if nvim:
    with tempfile.TemporaryDirectory(prefix="wezterm-warp-test-") as home:
        result = subprocess.run([nvim, "-l", str(tests / "test_config.lua"), str(tests.parent / "wezterm.lua"), home],
                                capture_output=True, text=True)
        print(result.stdout + result.stderr, end="")
        ok &= result.returncode == 0
else:
    print("Skipped: these need Neovim as a Lua interpreter (brew install neovim).")

sys.exit(0 if ok else 1)

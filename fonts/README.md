# CLI tab logos

`WezTermAgentIcons.ttf` contains six monochrome brand marks missing from
Hack Nerd Font: Gemini, Qwen, Meta (for Muse Code), DeepSeek, Ollama and
OpenCode. Claude, OpenAI and GitHub Copilot use the existing Nerd Font glyphs.
The logos inherit readable colors from each window's theme.

The original SVGs in `source/` come from
[Lobe Icons](https://github.com/lobehub/lobe-icons/tree/ea434b96e75813517b377825e01c0df61dee8836/packages/static-svg/icons)
at revision `ea434b96e75813517b377825e01c0df61dee8836`, under the included
[MIT license](source/LICENSE). Their outlines are scaled to fit one terminal
cell. Brand marks identify their respective tools and providers.

`install.sh` links this directory into WezTerm's config. WezTerm reads the font
directly, so other apps and system fonts are unaffected. Installation uses the
committed font; rebuilding it is optional:

```sh
python3 -m venv /tmp/wezterm-font-build
/tmp/wezterm-font-build/bin/pip install fonttools==4.61.1
/tmp/wezterm-font-build/bin/python fonts/build.py
```

Codepoints U+100001 through U+100006 follow the order above and avoid Nerd
Fonts' private-use ranges. Keep them in sync with `agent_icons` in `wezterm.lua`.

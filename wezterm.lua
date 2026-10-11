-- WezTerm set up to look and behave like Warp.
--
-- The things most worth changing are in `settings` just below; saving this
-- file applies them straight away. shell.zsh, next to this file, is the other
-- half: it makes the zsh command line edit like a text editor.

local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

local settings = {
  font = "Hack Nerd Font", -- Warp's default font is Hack
  font_size = 16.0, -- Warp's 13pt at 125% zoom
  line_height = 1.1,
  opacity = 0.93, -- 1.0 is solid
  blur = 40,
  dark_theme = "Warp Dark", -- or "Warp Phenomenon"
  light_theme = "Warp Light",
  cursor_thickness = "2pt",
  tab_font_size = 16.0,
  tab_width = 40, -- the widest a tab gets, in characters
  editor = "/opt/homebrew/bin/zed", -- opens the file paths you Cmd+click
  project_folders = { "~/Developer", "~/Worktrees" }, -- where Cmd+O looks for projects
  restore_tabs = true, -- reopen last time's tabs when WezTerm starts
  attention_sound = false, -- also play a sound when a tab needs you
}

-- ---- Look -------------------------------------------------------------------

-- Colors copied from Warp's bundled themes.
local themes = {
  ["Warp Phenomenon"] = {
    bg = "#121212",
    fg = "#FAF9F6",
    accent = "#2E5D9E",
    cursor = "#19AAD8", -- the accent is too dark to find on this background
    selection = "#2E5D9E",
    chrome = "#121212",
    tab = "#2A2A2A",
    edge = "#2A2A2A",
    hover = "#1C1C1C",
    tint = "#3D2E00",
    muted = "#8C8C8C",
    ansi = { "#121212", "#D22D1E", "#1CA05A", "#E5A01A", "#3780E9", "#BF409D", "#799C92", "#FAF9F6" },
    -- Warp lightens colors that are too close to the background; WezTerm does
    -- not, so bright black is a readable grey here instead of Warp's #292929.
    brights = { "#6E6E6E", "#AE756F", "#789B88", "#BD9F65", "#6F839F", "#A57899", "#BFC5C3", "#FFFFFF" },
  },
  ["Warp Dark"] = {
    bg = "#050505",
    fg = "#FFFFFF",
    accent = "#19AAD8",
    selection = "#0D4759",
    chrome = "#050505",
    tab = "#1F1F1F",
    edge = "#1F1F1F",
    hover = "#141414",
    tint = "#3D2E00",
    muted = "#8E8E8E",
    ansi = { "#616161", "#FF8272", "#B4FA72", "#FEFDC2", "#A5D5FE", "#FF8FFD", "#D0D1FE", "#F1F1F1" },
    brights = { "#8E8E8E", "#FFC4BD", "#D6FCB9", "#FEFDD5", "#C1E3FE", "#FFB1FE", "#E5E6FE", "#FEFFFF" },
  },
  ["Warp Light"] = {
    bg = "#FFFFFF",
    fg = "#111111",
    accent = "#00C2FF",
    selection = "#B3EDFF",
    chrome = "#F0F0F0",
    tab = "#FFFFFF",
    edge = "#DDDDDD",
    hover = "#F7F7F7",
    tint = "#FFF1CC",
    muted = "#6B6B6B",
    ansi = { "#212121", "#C30771", "#10A778", "#A89C14", "#008EC4", "#523C79", "#20A5BA", "#E0E0E0" },
    brights = { "#212121", "#FB007A", "#5FD7AF", "#F3E430", "#20BBFC", "#6855DE", "#4FB8CC", "#F1F1F1" },
  },
}

config.color_schemes = {}
for name, t in pairs(themes) do
  config.color_schemes[name] = {
    background = t.bg,
    foreground = t.fg,
    cursor_bg = t.cursor or t.accent,
    cursor_border = t.cursor or t.accent,
    cursor_fg = t.bg,
    selection_bg = t.selection,
    selection_fg = t.fg,
    split = t.muted,
    scrollbar_thumb = t.muted,
    ansi = t.ansi,
    brights = t.brights,
    tab_bar = {
      inactive_tab_edge = t.edge,
      active_tab = { bg_color = t.tab, fg_color = t.fg },
      inactive_tab = { bg_color = t.chrome, fg_color = t.muted },
      inactive_tab_hover = { bg_color = t.hover, fg_color = t.fg },
      new_tab = { bg_color = t.chrome, fg_color = t.muted },
      new_tab_hover = { bg_color = t.hover, fg_color = t.fg },
    },
  }
end

-- Follow the system light/dark setting, as Warp does. WezTerm re-reads this
-- file when the system appearance changes.
local function system_is_dark()
  -- wezterm.gui is missing when the command-line tool reads this file
  return not wezterm.gui or wezterm.gui.get_appearance():find("Dark") ~= nil
end

local theme_name = system_is_dark() and settings.dark_theme or settings.light_theme
local theme = themes[theme_name] or themes["Warp Phenomenon"]

config.color_scheme = theme_name
config.font = wezterm.font_with_fallback({ settings.font, "Menlo" })
config.font_size = settings.font_size
config.line_height = settings.line_height
config.window_background_opacity = settings.opacity
config.macos_window_background_blur = settings.blur
config.default_cursor_style = "BlinkingBar"
config.cursor_thickness = settings.cursor_thickness
config.cursor_blink_rate = 600
-- Blink fully on and off; WezTerm's default fade leaves the cursor dim half the time.
config.cursor_blink_ease_in = "Constant"
config.cursor_blink_ease_out = "Constant"
config.window_padding = { left = "2cell", right = "2cell", top = "0.5cell", bottom = "0.5cell" }
config.inactive_pane_hsb = { saturation = 0.9, brightness = 0.7 }
config.initial_cols = 120
config.initial_rows = 34
config.scrollback_lines = 20000
config.audible_bell = "Disabled"
-- Cmd+Plus/Minus changes the text size, not the size of the window.
config.adjust_window_size_when_changing_font_size = false

-- Tabs sit in the title bar next to the window buttons.
config.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
config.window_frame = {
  font = wezterm.font_with_fallback({ settings.font, "Menlo" }),
  font_size = settings.tab_font_size,
  active_titlebar_bg = theme.chrome,
  inactive_titlebar_bg = theme.chrome,
}
config.tab_max_width = 48
config.command_palette_bg_color = theme.tab
config.command_palette_fg_color = theme.fg
config.command_palette_font_size = 15.0

local shells = { zsh = true, bash = true, fish = true, sh = true }

-- Tabs that rang the bell while you were looking elsewhere (see Attention).
local attention_color = "#FFB000"
local function attention_key(pane_id)
  return "attention_" .. tostring(pane_id)
end

local function basename(path)
  return path:gsub("/+$", ""):match("([^/]+)$") or path
end

-- The name of the program at a path. Claude Code installs itself as
-- .../claude/versions/<number>, where the name is the folder two levels up.
local function program_name(path)
  path = path or ""
  local name = basename(path)
  if name:match("^%d+%.%d") then
    return path:match("([^/]+)/versions/[^/]+$") or name
  end
  return name
end

local function folder(pane)
  local cwd = pane.current_working_dir
  if not cwd then
    return ""
  end
  local path = type(cwd) == "userdata" and cwd.file_path or tostring(cwd)
  local home = wezterm.home_dir
  if path == home or path == home .. "/" then
    return "~"
  elseif path:sub(1, #home + 1) == home .. "/" then
    return "~" .. path:sub(#home + 1):gsub("/+$", "")
  end
  return path
end

-- Tabs show only the last two folders of a path; the prompt has all of it.
local function short_folder(pane)
  local path = folder(pane)
  local parent, last = path:match("([^/]+)/([^/]+)$")
  if not parent or parent == "~" or path == "/" .. parent .. "/" .. last then
    return path -- "~", "~/Desktop", "/usr/local"
  end
  return parent .. "/" .. last
end

-- Shorten text to a width, keeping the end of a path or the start of a title.
local function keep_end(text, width)
  if wezterm.column_width(text) <= width then
    return text
  end
  return "…" .. wezterm.truncate_left(text, width - 1)
end

local function keep_start(text, width)
  if wezterm.column_width(text) <= width then
    return text
  end
  return wezterm.truncate_right(text, width - 1) .. "…"
end

-- What a tab is called, as Warp's tab list has it: a name you gave it, else
-- the folder and git branch while its shell is waiting, else the running
-- program's own title. Returns an icon, the name and the branch.
local function tab_label(tab_title, pane, room)
  local vars = pane.user_vars or {}
  local program = program_name(pane.foreground_process_name)
  local waiting = vars.WEZ_ZLE == "1" or (vars.WEZ_ZLE == nil and (program == "" or shells[program]))
  if tab_title ~= "" then
    return "", keep_start(tab_title, room)
  elseif waiting then
    -- The folder comes first; the branch gets whatever room is left.
    local name = short_folder(pane)
    local branch = vars.WEZ_BRANCH ~= "" and vars.WEZ_BRANCH or nil
    local left = room - 2 - wezterm.column_width(name) - 4
    branch = branch and left >= 6 and keep_start(branch, left) or nil
    local taken = 2 + (branch and wezterm.column_width(branch) + 4 or 0)
    return "\u{f413}", keep_end(name, room - taken), branch
  end
  -- Until a program names itself the title is just its file name.
  local title = pane.title
  if title == "" or title == basename(pane.foreground_process_name or "") then
    title = program
  end
  -- Claude Code starts its title with a status symbol; plain names get an icon.
  if title:byte(1) and title:byte(1) < 128 then
    return "\u{f489}", keep_start(title, room - 2)
  end
  return "", keep_start(title, room)
end

-- How wide each tab is, in characters. The tabs share the bar evenly, like
-- browser tabs, and stop growing at settings.tab_width.
local function tab_width(tab_count, panes)
  local columns = 0
  for _, pane in ipairs(panes or {}) do
    columns = math.max(columns, (pane.left or 0) + (pane.width or 0))
  end
  if columns == 0 then
    return settings.tab_width
  end
  -- Panes are measured in terminal characters, the bar in tab-text ones; the
  -- 4 is the padding either side of the terminal.
  columns = math.floor((columns + 4) * settings.font_size / settings.tab_font_size)
  -- One extra share is left for the window buttons and the + button, and 4
  -- characters of each share are the tab's own padding and close button.
  local share = math.floor(columns / (tab_count + 1)) - 4
  return math.max(6, math.min(settings.tab_width, share))
end

-- Every tab is the same width: name on the left, shortcut on the right. The
-- tab in front gets color; one that rang the bell is tinted until you look.
wezterm.on("format-tab-title", function(tab, tabs, panes, _, _, max_width)
  local pane = tab.active_pane
  local width = math.min(tab_width(tabs and #tabs or 1, panes), max_width)
  local shortcut = (tab.tab_index < 9 and width >= 16) and ("⌘" .. tab.tab_index + 1) or ""

  local needs_you = false
  if not tab.is_active then
    for _, other in ipairs(tab.panes or { pane }) do
      needs_you = needs_you or wezterm.GLOBAL[attention_key(other.pane_id)] == true
    end
  end
  local dot = needs_you and "● " or ""

  -- 2 before the name, 1 after the shortcut, 2 between them at the least.
  local room = width - 3 - wezterm.column_width(dot) - (shortcut ~= "" and wezterm.column_width(shortcut) + 2 or 0)
  local icon, label, branch = tab_label(tab.tab_title, pane, math.max(room, 4))
  icon = icon ~= "" and (icon .. " ") or ""
  branch = branch and ("  \u{f418} " .. branch) or ""
  local used = 2 + wezterm.column_width(dot .. icon .. label .. branch) + wezterm.column_width(shortcut) + 1
  local gap = string.rep(" ", math.max(width - used, shortcut ~= "" and 2 or 0))

  local function colored(color, text)
    return { Foreground = { Color = color } }, { Text = text }, "ResetAttributes"
  end
  local function add(items, ...)
    for _, item in ipairs({ ... }) do
      table.insert(items, item)
    end
  end

  -- The first character sets the color of the whole tab.
  local items = {}
  if needs_you then
    add(items, { Background = { Color = theme.tint } }, { Foreground = { Color = theme.fg } })
  end
  add(items, { Text = "  " }, "ResetAttributes")
  if needs_you then
    add(items, colored(attention_color, dot))
  end
  if tab.is_active then
    add(items, colored(theme.cursor or theme.accent, icon))
    add(items, { Text = label })
    add(items, colored(theme.brights[3], branch))
    add(items, { Text = gap })
    add(items, colored(theme.muted, shortcut))
  else
    add(items, { Text = icon .. label .. branch .. gap .. shortcut })
  end
  add(items, { Text = " " })
  return items
end)

-- ---- Feel -------------------------------------------------------------------

-- Escape sequences bound in shell.zsh.
local shell = {
  select_all = "\x1b[990~",
  copy = "\x1b[991~",
  cut = "\x1b[992~",
  redo = "\x1b[993~",
  adopt_selection = "\x1b[994~",
  select_to_start = "\x1b[995~",
  select_to_end = "\x1b[996~",
  pick_folder = "\x1b[997~",
  undo = "\x1f",
}

-- True while zsh is waiting at a prompt; shell.zsh keeps this up to date.
local function at_prompt(pane)
  return pane:get_user_vars().WEZ_ZLE == "1"
end

-- Claude Code and Codex have a text input of their own that understands the
-- same few editing keys.
local agents = { claude = true, codex = true }

local function agent_running(pane)
  local vars = pane:get_user_vars()
  if vars.WEZ_ZLE == "0" and agents[vars.WEZ_CMD] then
    return true
  end
  return agents[program_name(pane:get_foreground_process_name())] or false
end

-- Send a sequence to the command line, and do nothing inside other programs.
local function to_shell(sequence)
  return wezterm.action_callback(function(window, pane)
    if at_prompt(pane) then
      window:perform_action(act.SendString(sequence), pane)
    end
  end)
end

-- The same, but also for the input of Claude Code and Codex.
local function to_input(sequence)
  return wezterm.action_callback(function(window, pane)
    if at_prompt(pane) or agent_running(pane) then
      window:perform_action(act.SendString(sequence), pane)
    end
  end)
end

-- Selecting everything, or everything above or below the cursor. zsh shows a
-- real selection. Claude Code and Codex cannot, so there the selection is only
-- remembered for a few seconds: Backspace then deletes that text by repeating
-- their "delete to line start" and "delete to line end" keys, and any other
-- key forgets it. The tab bar says so while it lasts.
local delete_above = ("\x15"):rep(15)
local delete_below = ("\x0b"):rep(15)
local pending = {
  select_all = { hint = "Everything selected", keys = delete_below .. delete_above },
  select_above = { hint = "Everything above the cursor selected", keys = delete_above .. delete_above },
  select_below = { hint = "Everything below the cursor selected", keys = delete_below .. delete_below },
}

-- Each of those keys removes one row of text. Claude Code takes a long run of
-- them arriving at once for a paste and ignores it, so they go in short bursts.
local function delete_in_agent(keys)
  return wezterm.action_callback(function(window, pane)
    for _ = 1, 14 do
      window:perform_action(act.SendString(keys), pane)
      wezterm.sleep_ms(20)
    end
  end)
end

config.key_tables = {}
for name, selection in pairs(pending) do
  config.key_tables[name] = {
    { key = "Backspace", action = delete_in_agent(selection.keys) },
    { key = "Delete", action = delete_in_agent(selection.keys) },
    { key = "Escape", action = act.PopKeyTable },
  }
end

local function select_text(shell_sequence, name)
  return wezterm.action_callback(function(window, pane)
    if at_prompt(pane) then
      window:perform_action(act.SendString(shell_sequence), pane)
    elseif agent_running(pane) then
      local table = { name = name, one_shot = true, timeout_milliseconds = 6000 }
      window:perform_action(act.ActivateKeyTable(table), pane)
    end
  end)
end

-- "file", "folder" or nil
local function kind(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local _, _, code = file:read(1)
  file:close()
  return code == 21 and "folder" or "file" -- 21: it is a directory
end

local function pane_folder(pane)
  local cwd = pane:get_current_working_dir()
  if not cwd then
    return wezterm.home_dir
  end
  return type(cwd) == "userdata" and cwd.file_path or tostring(cwd)
end

-- ---- Attention --------------------------------------------------------------

-- A bell from a tab you are not looking at puts a dot on that tab and raises a
-- notification. Claude Code rings it when it finishes or needs an answer
-- (preferredNotifChannel in its settings); shell.zsh rings it when a long
-- command ends. Looking at the tab clears the dot.
wezterm.on("bell", function(window, pane)
  local active = window:active_pane()
  if window:is_focused() and active and active:pane_id() == pane:pane_id() then
    return
  end
  wezterm.GLOBAL[attention_key(pane:pane_id())] = true

  local vars = pane:get_user_vars()
  local message
  if vars.WEZ_ZLE == "1" then
    message = (vars.WEZ_CMD or "A command") .. " finished"
  else
    local title = pane:get_title()
    message = (title ~= "" and title or "A tab") .. " needs you"
  end
  window:toast_notification("WezTerm", message, nil, 5000)
  if settings.attention_sound then
    wezterm.background_child_process({ "afplay", "/System/Library/Sounds/Glass.aiff" })
  end
end)

-- ---- Reopening tabs ---------------------------------------------------------

-- The folder of every tab and split is written down as it changes and opened
-- again the next time WezTerm starts. Programs are not restarted: in a tab
-- that was running Claude Code, `claude --continue` picks it up again.
local session_path = wezterm.home_dir .. "/.cache/wezterm-warp/session.json"

local function save_session()
  local now = os.time()
  if now - (wezterm.GLOBAL.session_checked or 0) < 5 then
    return
  end
  wezterm.GLOBAL.session_checked = now

  local windows = {}
  for _, mux_window in ipairs(wezterm.mux.all_windows()) do
    if mux_window:get_workspace() == wezterm.mux.get_active_workspace() then
      local tabs = {}
      for _, info in ipairs(mux_window:tabs_with_info()) do
        local folders = {}
        for _, pane in ipairs(info.tab:panes()) do
          table.insert(folders, pane_folder(pane))
        end
        table.insert(tabs, { folders = folders, active = info.is_active })
      end
      table.insert(windows, tabs)
    end
  end

  local encoded = wezterm.json_encode(windows)
  if encoded ~= wezterm.GLOBAL.session_saved then
    local file = io.open(session_path, "w")
    if file then
      file:write(encoded)
      file:close()
      wezterm.GLOBAL.session_saved = encoded
    end
  end
end

wezterm.on("gui-startup", function(cmd)
  -- Started to run something specific: leave it alone.
  if not settings.restore_tabs or cmd then
    return
  end
  local file = io.open(session_path, "r")
  if not file then
    return
  end
  local ok, windows = pcall(wezterm.json_parse, file:read("a"))
  file:close()
  if not ok or type(windows) ~= "table" then
    return
  end
  -- A second WezTerm next to one that is already open starts empty.
  local _, running = wezterm.run_child_process({ "/usr/bin/pgrep", "-x", "wezterm-gui" })
  if running and select(2, running:gsub("%d+", "")) > 1 then
    return
  end

  for _, tabs in ipairs(windows) do
    local window, active
    for index, saved in ipairs(tabs) do
      if index > 20 or type(saved) ~= "table" then
        break
      end
      local folders = {}
      for _, path in ipairs(saved.folders or {}) do
        table.insert(folders, kind(path) == "folder" and path or wezterm.home_dir)
      end
      local first = folders[1] or wezterm.home_dir
      local tab, pane
      if window then
        tab, pane = window:spawn_tab({ cwd = first })
      else
        tab, pane, window = wezterm.mux.spawn_window({ cwd = first })
      end
      for split = 2, #folders do
        pane = pane:split({ direction = "Right", cwd = folders[split] })
      end
      if saved.active then
        active = tab
      end
    end
    if active then
      active:activate()
    end
  end
end)

wezterm.on("update-status", function(window)
  local selection = pending[window:active_key_table()]
  local hint = ""
  if selection then
    hint = wezterm.format({
      { Foreground = { Color = theme.cursor or theme.accent } },
      { Text = selection.hint .. " · ⌫ deletes · esc cancels   " },
    })
  end
  window:set_right_status(hint)

  local active = window:active_pane()
  if active and window:is_focused() and wezterm.GLOBAL[attention_key(active:pane_id())] then
    wezterm.GLOBAL[attention_key(active:pane_id())] = false
  end
  if settings.restore_tabs then
    save_session()
  end
end)

-- ---- Projects ---------------------------------------------------------------

-- Cmd+O lists every git project in settings.project_folders and opens the one
-- you pick in a new tab. Cmd+Shift+O also starts Claude Code there, with a
-- shell beside it.
local function projects()
  local home = wezterm.home_dir
  local found, seen = {}, {}
  for _, root in ipairs(settings.project_folders) do
    if root:sub(1, 1) == "~" then
      root = home .. root:sub(2)
    end
    for _, depth in ipairs({ "/*/.git", "/*/*/.git" }) do
      for _, git in ipairs(wezterm.glob(root .. depth)) do
        local dir = git:sub(1, -6)
        if not seen[dir] then
          seen[dir] = true
          local label = dir:sub(1, #home) == home and ("~" .. dir:sub(#home + 1)) or dir
          table.insert(found, { id = dir, label = label })
        end
      end
    end
  end
  table.sort(found, function(a, b)
    return a.label < b.label
  end)
  return found
end

local function open_project(with_claude)
  return wezterm.action_callback(function(window, pane)
    local picker = act.InputSelector({
      title = with_claude and "Open a project with Claude Code" or "Open a project",
      choices = projects(),
      fuzzy = true,
      action = wezterm.action_callback(function(picked_window, _, dir)
        if not dir then
          return
        end
        local _, new_pane = picked_window:mux_window():spawn_tab({ cwd = dir })
        if with_claude then
          picked_window:perform_action(act.SendString("claude\r"), new_pane)
          new_pane:split({ direction = "Right", size = 0.4, cwd = dir })
          new_pane:activate()
        end
      end),
    })
    window:perform_action(picker, pane)
  end)
end

-- ---- Tabs -------------------------------------------------------------------

-- Cmd+Shift+R gives the tab a name of your own; an empty name goes back to
-- the automatic one.
local rename_tab = act.PromptInputLine({
  description = "Name this tab (leave empty for the automatic name)",
  action = wezterm.action_callback(function(window, _, name)
    if name then
      window:active_tab():set_title(name)
    end
  end),
})

-- Cmd+Option+4 turns the pane you are in into a grid of four, each a shell
-- in the same folder. Cmd+D and Cmd+Shift+D split one at a time.
local four_panes = wezterm.action_callback(function(_, pane)
  local cwd = pane_folder(pane)
  local right = pane:split({ direction = "Right", size = 0.5, cwd = cwd })
  pane:split({ direction = "Bottom", size = 0.5, cwd = cwd })
  right:split({ direction = "Bottom", size = 0.5, cwd = cwd })
  pane:activate()
end)

-- ---- Links ------------------------------------------------------------------

-- Cmd+click opens web links as usual, and file paths in settings.editor at the
-- line given after the name (src/main.swift:12). Folders open in Finder.
config.hyperlink_rules = wezterm.default_hyperlink_rules()
table.insert(config.hyperlink_rules, {
  regex = [[(?<![\w/:~.@-])(?:~/|\.{1,2}/|/)?(?:[\w.@+-]+/)+[\w.@+-]*[\w@+-](?::\d+){0,2}]],
  format = "open-path:$0",
})
-- A bare file name with a line number, as compilers print it.
table.insert(config.hyperlink_rules, {
  regex = [[(?<![\w/:~.@-])[\w@+-][\w.@+-]*\.[A-Za-z]\w*:\d+(?::\d+)?]],
  format = "open-path:$0",
})

wezterm.on("open-uri", function(window, pane, uri)
  -- A plain click only works on the prompt's own chips; see open_link below.
  local plain = wezterm.GLOBAL.click == "plain" and os.time() - (wezterm.GLOBAL.click_at or 0) <= 1
  wezterm.GLOBAL.click = "none"
  if uri == "wezwarp:folder" then
    if at_prompt(pane) then
      window:perform_action(act.SendString(shell.pick_folder), pane)
    end
    return false
  elseif plain then
    return false
  end

  local target = uri:match("^open%-path:(.+)$")
  if not target then
    return -- web links and everything else open the usual way
  end
  local path, position = target:match("^(.-)(:%d+:?%d*)$")
  path, position = path or target, position or ""
  if path:sub(1, 2) == "~/" then
    path = wezterm.home_dir .. path:sub(2)
  elseif path:sub(1, 1) ~= "/" then
    path = pane_folder(pane):gsub("/+$", "") .. "/" .. path
  end

  local what = kind(path)
  if what == "folder" then
    wezterm.background_child_process({ "open", path })
  elseif what == "file" and kind(settings.editor) then
    wezterm.background_child_process({ settings.editor, path .. position })
  elseif what == "file" then
    wezterm.background_child_process({ "open", "-t", path })
  end
  return false
end)

-- Cmd+C copies text highlighted with the mouse, or else the selection made
-- with Shift+arrows in the command line.
local copy = wezterm.action_callback(function(window, pane)
  if window:get_selection_text_for_pane(pane) ~= "" then
    window:perform_action(act.CopyTo("Clipboard"), pane)
  elseif at_prompt(pane) then
    window:perform_action(act.SendString(shell.copy), pane)
  end
end)

local copy_last_output = wezterm.action_callback(function(window, pane)
  local zones = pane:get_semantic_zones("Output")
  local last = zones[#zones]
  if last then
    window:copy_to_clipboard(pane:get_text_from_semantic_zone(last), "Clipboard")
  end
end)

-- Hand text dragged over with the mouse to zsh, which turns it into a real
-- selection if it is part of the command being typed (see shell.zsh).
local adopt_selection = wezterm.action_callback(function(window, pane)
  if not at_prompt(pane) then
    return
  end
  local text = window:get_selection_text_for_pane(pane)
  if text == "" or #text > 20000 then
    return
  end
  local path = wezterm.home_dir .. "/.cache/wezterm-warp/selection-" .. pane:pane_id()
  local file = io.open(path, "w")
  if not file then
    return
  end
  file:write(text)
  file:close()
  window:perform_action(act.SendString(shell.adopt_selection), pane)
end)

local open_settings = wezterm.action_callback(function()
  wezterm.background_child_process({ "open", "-t", wezterm.config_file })
end)

config.keys = {
  -- Editing the command line
  { key = "a", mods = "CMD", action = select_text(shell.select_all, "select_all") },
  { key = "UpArrow", mods = "CMD|SHIFT", action = select_text(shell.select_to_start, "select_above") },
  { key = "DownArrow", mods = "CMD|SHIFT", action = select_text(shell.select_to_end, "select_below") },
  { key = "c", mods = "CMD", action = copy },
  { key = "x", mods = "CMD", action = to_shell(shell.cut) },
  { key = "z", mods = "CMD", action = to_input(shell.undo) },
  { key = "z", mods = "CMD|SHIFT", action = to_shell(shell.redo) },
  { key = "LeftArrow", mods = "CMD", action = act.SendKey({ key = "Home" }) },
  { key = "RightArrow", mods = "CMD", action = act.SendKey({ key = "End" }) },
  { key = "LeftArrow", mods = "CMD|SHIFT", action = act.SendString("\x1b[1;2H") },
  { key = "RightArrow", mods = "CMD|SHIFT", action = act.SendString("\x1b[1;2F") },
  { key = "LeftArrow", mods = "OPT", action = act.SendString("\x1bb") },
  { key = "RightArrow", mods = "OPT", action = act.SendString("\x1bf") },
  { key = "LeftArrow", mods = "OPT|SHIFT", action = act.SendString("\x1b[1;4D") },
  { key = "RightArrow", mods = "OPT|SHIFT", action = act.SendString("\x1b[1;4C") },
  { key = "Backspace", mods = "CMD", action = act.SendString("\x15") },
  { key = "Enter", mods = "SHIFT", action = act.SendString("\x1b\r") },

  -- Panes
  { key = "d", mods = "CMD", action = act.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
  { key = "d", mods = "CMD|SHIFT", action = act.SplitVertical({ domain = "CurrentPaneDomain" }) },
  { key = "w", mods = "CMD", action = act.CloseCurrentPane({ confirm = true }) },
  { key = "Enter", mods = "CMD|SHIFT", action = act.TogglePaneZoomState },
  { key = "4", mods = "CMD|OPT", action = four_panes },
  { key = "LeftArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Left") },
  { key = "RightArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Right") },
  { key = "UpArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Up") },
  { key = "DownArrow", mods = "CMD|OPT", action = act.ActivatePaneDirection("Down") },
  { key = "LeftArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Left", 3 }) },
  { key = "RightArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Right", 3 }) },
  { key = "UpArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Up", 3 }) },
  { key = "DownArrow", mods = "CMD|CTRL", action = act.AdjustPaneSize({ "Down", 3 }) },

  -- Commands and their output
  { key = "p", mods = "CMD", action = act.ActivateCommandPalette },
  { key = "p", mods = "CMD|SHIFT", action = act.ActivateCommandPalette },
  { key = "UpArrow", mods = "CMD", action = act.ScrollToPrompt(-1) },
  { key = "DownArrow", mods = "CMD", action = act.ScrollToPrompt(1) },
  { key = "c", mods = "CMD|SHIFT", action = copy_last_output },
  {
    key = "k",
    mods = "CMD",
    action = act.Multiple({
      act.ClearScrollback("ScrollbackAndViewport"),
      act.SendKey({ key = "L", mods = "CTRL" }),
    }),
  },
  { key = ",", mods = "CMD", action = open_settings },
  { key = "o", mods = "CMD", action = open_project(false) },
  { key = "o", mods = "CMD|SHIFT", action = open_project(true) },
  { key = "g", mods = "CMD|SHIFT", action = to_shell(shell.pick_folder) },

  -- Tabs
  { key = "r", mods = "CMD|SHIFT", action = rename_tab },
  { key = "LeftArrow", mods = "CTRL|SHIFT", action = act.MoveTabRelative(-1) },
  { key = "RightArrow", mods = "CTRL|SHIFT", action = act.MoveTabRelative(1) },
}

-- A plain click selects, followed by the hand-off to zsh; the only thing it
-- opens is a chip in the prompt (the folder chip lists folders). Cmd+click
-- opens whatever is under the pointer, also in programs that take over the
-- mouse such as Claude Code. A triple click selects a whole command or
-- everything it printed, like clicking a block in Warp.
local selection_target = "ClipboardAndPrimarySelection"

-- The open-uri handler above needs to know which kind of click it was.
local function open_link(click)
  return wezterm.action_callback(function(window, pane)
    if click == "plain" and window:get_selection_text_for_pane(pane) ~= "" then
      return -- the end of a drag, not a click
    end
    wezterm.GLOBAL.click = click
    wezterm.GLOBAL.click_at = os.time()
    window:perform_action(act.OpenLinkAtMouseCursor, pane)
  end)
end

local function on_release(streak)
  local actions = { act.CompleteSelection(selection_target), adopt_selection }
  if streak == 1 then
    table.insert(actions, open_link("plain"))
  end
  return {
    event = { Up = { streak = streak, button = "Left" } },
    mods = "NONE",
    action = act.Multiple(actions),
  }
end

config.mouse_bindings = {
  on_release(1),
  on_release(2),
  on_release(3),
  {
    event = { Down = { streak = 3, button = "Left" } },
    mods = "NONE",
    action = act.SelectTextAtMouseCursor("SemanticZone"),
  },
  {
    event = { Drag = { streak = 3, button = "Left" } },
    mods = "NONE",
    action = act.ExtendSelectionToMouseCursor("SemanticZone"),
  },
}
for _, captured in ipairs({ false, true }) do
  table.insert(config.mouse_bindings, {
    event = { Down = { streak = 1, button = "Left" } },
    mods = "CMD",
    mouse_reporting = captured,
    action = act.Nop,
  })
  table.insert(config.mouse_bindings, {
    event = { Up = { streak = 1, button = "Left" } },
    mods = "CMD",
    mouse_reporting = captured,
    action = open_link("cmd"),
  })
end

return config

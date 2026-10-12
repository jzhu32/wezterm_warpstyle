-- Runs wezterm.lua against a stand-in for the wezterm module so the callbacks
-- (which WezTerm only runs on a real key press or click) can be exercised.
--
--   nvim -l tests/test_config.lua wezterm.lua <an empty scratch folder>
--
-- Neovim is only used as a Lua interpreter here; tests/run.py does this for you.
local config_path, fake_home = arg[1], arg[2]
os.execute('mkdir -p "' .. fake_home .. '/.cache/wezterm-warp"')

-- What Cmd+click on a file should run: the editor from settings if this Mac
-- has it, otherwise the default text editor.
local zed = "/opt/homebrew/bin/zed"
local has_zed = io.open(zed) ~= nil
local function in_editor(path, position)
  return has_zed and (zed .. " " .. path .. position) or ("open -t " .. path)
end
local results = {}
local function check(name, got, want)
  local ok = got == want
  results[#results + 1] = ok
  print((ok and "PASS  " or "FAIL  ") .. name .. (ok and "" or ("\n        got  " .. tostring(got) .. "\n        want " .. tostring(want))))
end

local function chars(text)
  local list = {}
  for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do list[#list + 1] = c end
  return list
end

local function flatten(items)
  if type(items) == "string" then return items end
  local text = ""
  for _, item in ipairs(items) do
    if type(item) == "table" and item.Text then text = text .. item.Text end
  end
  return text
end

-- Stand-ins for the parts of WezTerm the newer features talk to.
local GLOBAL, globbed, pgrep_output, mux = {}, {}, "100\n", { windows = {}, calls = {} }
local decoded = {}
local function encode(v)
  if type(v) ~= "table" then
    return type(v) == "string" and ('"' .. v .. '"') or tostring(v)
  end
  local parts = {}
  if #v > 0 or next(v) == nil then
    for _, x in ipairs(v) do parts[#parts + 1] = encode(x) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. k .. '":' .. encode(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function mux_pane(name)
  local p = { name = name }
  function p:split(opts)
    mux.calls[#mux.calls + 1] = "split " .. name .. " -> " .. opts.cwd
    return mux_pane(name .. "+")
  end
  function p:activate() mux.calls[#mux.calls + 1] = "focus " .. name end
  return p
end
local function mux_tab(name)
  local tab = {}
  function tab:activate() mux.calls[#mux.calls + 1] = "activate " .. name end
  return tab
end
local function mux_window_stub()
  local w = { count = 1 }
  function w:spawn_tab(opts)
    self.count = self.count + 1
    mux.calls[#mux.calls + 1] = "tab " .. opts.cwd
    return mux_tab("tab" .. self.count), mux_pane("pane" .. self.count), self
  end
  return w
end

local function load_config(appearance)
  local events, spawned = {}, {}
  local action = setmetatable({}, {
    __index = function(_, name)
      return setmetatable({ name = name }, { __call = function(_, a) return { name = name, arg = a } end })
    end,
  })
  package.loaded.wezterm = {
    action = action,
    home_dir = fake_home,
    config_file = "/tmp/wezterm.lua",
    gui = { get_appearance = function() return appearance end },
    config_builder = function() return {} end,
    font_with_fallback = function(f) return f end,
    on = function(name, fn) events[name] = fn end,
    action_callback = function(fn) return { name = "callback", run = fn } end,
    background_child_process = function(cmd) spawned[#spawned + 1] = table.concat(cmd, " ") end,
    column_width = function(text) return #chars(text) end,
    truncate_right = function(text, n) return table.concat(chars(text), "", 1, math.min(n, #chars(text))) end,
    truncate_left = function(text, n) local c = chars(text); return table.concat(c, "", math.max(#c - n + 1, 1), #c) end,
    format = flatten,
    sleep_ms = function(ms) slept = (slept or 0) + ms end,
    GLOBAL = GLOBAL,
    glob = function(pattern) return globbed[pattern] or {} end,
    default_hyperlink_rules = function() return {} end,
    json_encode = function(v) local text = encode(v); decoded[text] = v; return text end,
    json_parse = function(text) if decoded[text] == nil then error("bad json") end return decoded[text] end,
    run_child_process = function() return true, pgrep_output, "" end,
    mux = {
      all_windows = function() return mux.windows end,
      get_active_workspace = function() return "default" end,
      spawn_window = function(opts)
        mux.calls[#mux.calls + 1] = "window " .. opts.cwd
        return mux_tab("tab1"), mux_pane("pane1"), mux_window_stub()
      end,
    },
  }
  return dofile(config_path), events, spawned
end

local function window(selection, key_table, opts)
  opts = opts or {}
  local w = { sent = {}, clipboard = nil, status = nil, toasts = {} }
  function w:is_focused() return opts.focused ~= false end
  function w:active_pane() return opts.active end
  function w:toast_notification(_, message) self.toasts[#self.toasts + 1] = message end
  function w:mux_window() return opts.mux_window end
  function w:get_selection_text_for_pane() return selection end
  function w:perform_action(a)
    local arg = a.arg
    if type(arg) == "table" then arg = arg.name end
    self.sent[#self.sent + 1] = a.name .. ":" .. tostring(arg)
  end
  function w:copy_to_clipboard(text) self.clipboard = text end
  function w:active_key_table() return key_table end
  function w:set_right_status(text) self.status = text end
  return w
end
local function pane(zle, opts)
  opts = opts or {}
  local p = {}
  function p:get_user_vars() return { WEZ_ZLE = zle, WEZ_CMD = opts.cmd, WEZ_BRANCH = opts.branch } end
  function p:get_foreground_process_name() return opts.process or "/bin/zsh" end
  function p:pane_id() return opts.id or 42 end
  function p:get_title() return opts.title or "" end
  function p:get_current_working_dir() return opts.cwd end
  function p:get_semantic_zones() return opts.zones or {} end
  function p:get_text_from_semantic_zone(z) return z.text end
  return p
end
local function key(config, k, mods)
  for _, b in ipairs(config.keys) do
    if b.key == k and b.mods == mods then return b.action end
  end
end
local function table_key(config, name, k)
  for _, b in ipairs(config.key_tables[name]) do
    if b.key == k then return b.action end
  end
end

local CLAUDE = "/Users/x/.local/share/claude/versions/2.1.296"

local config, events, spawned = load_config("Dark")
check("dark system picks Warp Dark", config.color_scheme, "Warp Dark")
check("  ...with its background", config.color_schemes["Warp Dark"].background, "#050505")
check("  ...and Warp's cyan cursor", config.color_schemes["Warp Dark"].cursor_bg, "#19AAD8")
check("Phenomenon gets a visible cursor too", config.color_schemes["Warp Phenomenon"].cursor_bg, "#19AAD8")
check("cursor is thickened", config.cursor_thickness, "2pt")
check("tab text matches the terminal text size", config.window_frame.font_size, 16.0)
check("full screen is the macOS one, with its own space and Esc to leave", config.native_macos_fullscreen_mode, true)
check("light system picks Warp Light", (load_config("Light")).color_scheme, "Warp Light")
config, events, spawned = load_config("Dark")

local w = window(""); key(config, "a", "CMD").run(w, pane("1"))
check("cmd+a at the prompt reaches zsh", w.sent[1], "SendString:\27[990~")
w = window(""); key(config, "a", "CMD").run(w, pane("0", { process = "/opt/homebrew/bin/nvim", cmd = "nvim" }))
check("cmd+a inside another program does nothing", #w.sent, 0)
w = window(""); key(config, "a", "CMD").run(w, pane(nil, { process = CLAUDE }))
check("cmd+a inside Claude Code arms select-all", w.sent[1], "ActivateKeyTable:select_all")
w = window(""); key(config, "a", "CMD").run(w, pane("0", { process = "/opt/homebrew/bin/node", cmd = "codex" }))
check("cmd+a inside Codex (known from the shell) arms select-all", w.sent[1], "ActivateKeyTable:select_all")
w = window(""); key(config, "a", "CMD").run(w, pane("1", { process = "/bin/zsh", cmd = "codex" }))
check("  ...but back at the prompt it goes to zsh", w.sent[1], "SendString:\27[990~")

local function burst(name, k)
  local win = window("")
  table_key(config, name, k).run(win, pane(nil, { process = CLAUDE }))
  return win.sent
end
local sent = burst("select_all", "Backspace")
check("select-all + backspace sends 14 short bursts", #sent, 14)
check("  ...each deleting below then above", sent[1], "SendString:" .. ("\11"):rep(15) .. ("\21"):rep(15))
check("  ...none long enough to be taken for a paste", #sent[14] - #"SendString:" <= 60, true)
check("  ...with a pause between them", slept, 14 * 20)
check("  ...forward delete does the same", burst("select_all", "Delete")[1], sent[1])
check("  ...escape only cancels", table_key(config, "select_all", "Escape").name, "PopKeyTable")
check("select-above + backspace deletes only above", burst("select_above", "Backspace")[1], "SendString:" .. ("\21"):rep(30))
check("select-below + backspace deletes only below", burst("select_below", "Backspace")[1], "SendString:" .. ("\11"):rep(30))

w = window(""); key(config, "UpArrow", "CMD|SHIFT").run(w, pane("1"))
check("cmd+shift+up at the prompt selects to the start", w.sent[1], "SendString:\27[995~")
w = window(""); key(config, "UpArrow", "CMD|SHIFT").run(w, pane(nil, { process = CLAUDE }))
check("cmd+shift+up inside Claude Code arms select-above", w.sent[1], "ActivateKeyTable:select_above")
w = window(""); key(config, "DownArrow", "CMD|SHIFT").run(w, pane("1"))
check("cmd+shift+down at the prompt selects to the end", w.sent[1], "SendString:\27[996~")

-- Option+Enter is WezTerm's own full-screen toggle until this config takes it.
-- Full screen removes the window's edges and buttons, so the window can no
-- longer be resized, and the key is far too easy to hit while typing.
local newline = key(config, "Enter", "OPT")
check("opt+enter is a new line, not WezTerm's full-screen toggle",
  newline and (newline.name .. ":" .. tostring(newline.arg)), "SendString:\27\r")
check("  ...the same one shift+enter sends", (key(config, "Enter", "SHIFT") or {}).arg, "\27\r")

w = window(""); key(config, "z", "CMD").run(w, pane(nil, { process = CLAUDE }))
check("cmd+z inside Claude Code undoes", w.sent[1], "SendString:\31")
w = window(""); key(config, "z", "CMD").run(w, pane("0", { process = "/opt/homebrew/bin/nvim", cmd = "nvim" }))
check("cmd+z inside another program does nothing", #w.sent, 0)
w = window(""); key(config, "x", "CMD").run(w, pane(nil))
check("cmd+x with no shell integration does nothing", #w.sent, 0)

w = window("", "select_all"); events["update-status"](w)
check("tab bar says when everything is selected", w.status, "Everything selected · ⌫ deletes · esc cancels   ")
w = window("", nil); events["update-status"](w)
check("  ...and is empty otherwise", w.status, "")

w = window("picked with mouse"); key(config, "c", "CMD").run(w, pane("1"))
check("cmd+c prefers the mouse selection", w.sent[1], "CopyTo:Clipboard")
w = window(""); key(config, "c", "CMD").run(w, pane("1"))
check("cmd+c falls back to the command-line selection", w.sent[1], "SendString:\27[991~")

w = window(""); key(config, "c", "CMD|SHIFT").run(w, pane("1", { zones = { { text = "old" }, { text = "latest output" } } }))
check("cmd+shift+c copies the last output", w.clipboard, "latest output")

key(config, ",", "CMD").run(window(""), pane("1"))
check("cmd+, opens the config file", spawned[1], "open -t /tmp/wezterm.lua")

local adopt = config.mouse_bindings[1].action.arg[2]
local sel = fake_home .. "/.cache/wezterm-warp/selection-42"
os.remove(sel)
w = window("commit"); adopt.run(w, pane("1"))
local f = io.open(sel); local written = f and f:read("a"); if f then f:close() end
check("mouse-up hands the selection to zsh", written, "commit")
check("  ...and tells it to look", w.sent[1], "SendString:\27[994~")
os.remove(sel)
w = window("commit"); adopt.run(w, pane("0"))
check("mouse-up inside a program hands over nothing", io.open(sel), nil)
w = window("two\nlines"); adopt.run(w, pane("1"))
f = io.open(sel); written = f and f:read("a"); if f then f:close() end
check("selections of several lines are handed over too", written, "two\nlines")
os.remove(sel)
w = window(""); adopt.run(w, pane("1"))
check("a plain click hands over nothing", #w.sent, 0)

local title = events["format-tab-title"]
-- A window 116 characters wide plus padding, holding `count` tabs.
local function tab_items(index, active, p, count)
  local all = {}
  for i = 1, count or 2 do all[i] = {} end
  return title({ tab_title = p.tab_title or "", tab_index = index, is_active = active, active_pane = p },
    all, { { left = 0, width = 58 }, { left = 58, width = 58 } }, nil, nil, 48)
end
local function tab(index, active, p, count)
  return flatten(tab_items(index, active, p, count))
end
local function squeeze(text) return (text:gsub("  +", "  ")) end
local url = newproxy(true); getmetatable(url).__index = { file_path = fake_home .. "/Developer/Swift/Meldrun" }
local root = newproxy(true); getmetatable(root).__index = { file_path = fake_home }
local shell_tab = { current_working_dir = url, foreground_process_name = "/bin/zsh", title = "~/Developer/Swift/Meldrun", user_vars = { WEZ_ZLE = "1", WEZ_BRANCH = "main" } }
local home_tab = { current_working_dir = root, foreground_process_name = "/bin/zsh", title = "~", user_vars = { WEZ_ZLE = "1", WEZ_BRANCH = "" } }
local claude_tab = { current_working_dir = root, foreground_process_name = CLAUDE, title = "✳ Fix the login bug", user_vars = { WEZ_ZLE = "0", WEZ_CMD = "claude" } }

check("tab: at the prompt shows folder, branch and shortcut", squeeze(tab(0, true, shell_tab)), "  \u{f413} Swift/Meldrun  \u{f418} main  ⌘1 ")
check("tab: home folder shows ~", squeeze(tab(1, false, home_tab)), "  \u{f413} ~  ⌘2 ")
check("tab: a running program shows its own title", squeeze(tab(0, true, claude_tab)), "  ✳ Fix the login bug  ⌘1 ")
check("tab: Claude Code without a title is not shown as a version number",
  squeeze(tab(0, true, { current_working_dir = root, foreground_process_name = CLAUDE, title = "2.1.296", user_vars = {} })), "  \u{f489} claude  ⌘1 ")
check("tab: a plain program gets a terminal icon",
  squeeze(tab(0, true, { current_working_dir = root, foreground_process_name = "/opt/homebrew/bin/npm", title = "npm run dev", user_vars = { WEZ_ZLE = "0" } })), "  \u{f489} npm run dev  ⌘1 ")
check("tab: a shell started before this setup still shows its folder",
  squeeze(tab(2, true, { current_working_dir = url, foreground_process_name = "/bin/zsh", title = "zsh", user_vars = {} })), "  \u{f413} Swift/Meldrun  ⌘3 ")
check("tab: a name you set wins", squeeze(tab(0, true, { tab_title = "mine", foreground_process_name = "/bin/zsh", title = "zsh", user_vars = {} })), "  mine  ⌘1 ")

local widths = {}
for _, p in ipairs({ shell_tab, home_tab, claude_tab }) do widths[#widths + 1] = #chars(tab(0, false, p)) end
check("tabs: all the same width, whatever they say", table.concat(widths, " "), "36 36 36")
check("  ...with the shortcut at the right edge", tab(1, false, home_tab):sub(-5), "⌘2 ")
check("  ...sharing the bar when there are many", #chars(tab(0, false, shell_tab, 5)), 16)
check("  ...and never wider than the limit", #chars(tab(0, true, shell_tab, 1)), 40)
local crowded = tab(0, false, shell_tab, 9)
check("  ...a crowded bar drops the shortcut and branch but keeps the folder", crowded:find("⌘") == nil and crowded:find("un") ~= nil and #chars(crowded) <= 8, true)
local long = newproxy(true); getmetatable(long).__index = { file_path = fake_home .. "/Developer/a-very-long-folder-name/and-another-long-one/project" }
local long_tab = { current_working_dir = long, foreground_process_name = "/bin/zsh", title = "", user_vars = { WEZ_ZLE = "1", WEZ_BRANCH = "feat/architecture-completion-20261010" } }
check("tab: a long path shows its last two folders", squeeze(tab(0, true, long_tab, 1)), "  \u{f413} and-another-long-one/project  ⌘1 ")
local shown = tab(0, true, long_tab, 5)
check("  ...and is cut from the left when the tab is narrow", #chars(shown) == 16 and shown:find("…[^ ]*ject") ~= nil, true)
check("tab: a long branch takes only the room that is left",
  squeeze(tab(0, true, { current_working_dir = url, foreground_process_name = "/bin/zsh", title = "", user_vars = { WEZ_ZLE = "1", WEZ_BRANCH = "feat/architecture-completion-20261010" } }, 1)),
  "  \u{f413} Swift/Meldrun  \u{f418} feat/architec…  ⌘1 ")
check("tab: folders near the top of the disk are shown whole",
  squeeze(tab(0, false, { current_working_dir = dir_at and dir_at("/usr/local") or (function() local u = newproxy(true); getmetatable(u).__index = { file_path = "/usr/local" }; return u end)(), foreground_process_name = "/bin/zsh", title = "", user_vars = { WEZ_ZLE = "1" } })),
  "  \u{f413} /usr/local  ⌘1 ")
check("tab: tenth tab has no shortcut", squeeze(tab(9, true, home_tab)), "  \u{f413} ~  ")

local function colors_of(items)
  local found = {}
  for _, item in ipairs(items) do
    if type(item) == "table" and item.Foreground then found[#found + 1] = item.Foreground.Color end
    if type(item) == "table" and item.Background then found[#found + 1] = "bg " .. item.Background.Color end
  end
  return table.concat(found, " ")
end
check("the tab in front is colored: icon, branch, shortcut", colors_of(tab_items(0, true, shell_tab)), "#19AAD8 #D6FCB9 #8E8E8E")
check("the other tabs are left plain", colors_of(tab_items(0, false, shell_tab)), "")

-- WezTerm drops the whole title and falls back to "3: name" if one item is not
-- a FormatItem it knows, so check the shape of every one rather than the text.
local function badly_shaped(items)
  local allowed = { Text = true, Foreground = true, Background = true, Attribute = true }
  for _, item in ipairs(items) do
    if item ~= "ResetAttributes" then
      if type(item) ~= "table" then return tostring(item) end
      for k in pairs(item) do
        if not allowed[k] then return k end
      end
    end
  end
  return ""
end
for _, case in ipairs({ { 0, true, shell_tab }, { 1, false, shell_tab }, { 0, true, claude_tab } }) do
  check("every tab title item is one WezTerm knows (" .. tostring(case[2]) .. ")",
    badly_shaped(tab_items(case[1], case[2], case[3])), "")
end
local bar = config.color_schemes["Warp Dark"].tab_bar
check("the tab in front has a lighter background than the bar",
  bar.active_tab.bg_color ~= bar.inactive_tab.bg_color and bar.active_tab.bg_color, "#2E2E2E")
tab_items(0, true, shell_tab)
w = window("", nil); events["update-status"](w)
check("the status line names the tab you are in", w.status, "⌘1 Swift/Meldrun   ")

-- ---- attention ---------------------------------------------------------------
local claude_pane = pane("0", { id = 7, title = "✳ Fix the login bug", process = CLAUDE })
local other_pane = pane("1", { id = 8 })
w = window("", nil, { active = other_pane })
events["bell"](w, claude_pane)
check("bell from a tab you are not on marks it", GLOBAL.attention_7, true)
check("  ...and raises a notification naming it", w.toasts[1], "✳ Fix the login bug needs you")
local flagged = { pane_id = 7, foreground_process_name = CLAUDE, title = "✳ Fix the login bug", user_vars = { WEZ_ZLE = "0" } }
check("  ...and its tab gets a dot", squeeze(tab(1, false, flagged)), "  ● ✳ Fix the login bug  ⌘2 ")
check("  ...and only a dot, so it never outshines the tab you are in", colors_of(tab_items(1, false, flagged)), "#FFB000")
check("  ...with items WezTerm knows", badly_shaped(tab_items(1, false, flagged)), "")
check("  ...but not while it is the tab in front", squeeze(tab(1, true, flagged)), "  ✳ Fix the login bug  ⌘2 ")
w = window("", nil, { active = claude_pane })
events["update-status"](w)
check("looking at the tab clears the dot", GLOBAL.attention_7, false)
w = window("", nil, { active = claude_pane })
events["bell"](w, claude_pane)
check("bell from the tab you are looking at does nothing", #w.toasts == 0 and GLOBAL.attention_7 == false, true)
w = window("", nil, { active = claude_pane, focused = false })
events["bell"](w, claude_pane)
check("  ...unless WezTerm itself is in the background", w.toasts[1], "✳ Fix the login bug needs you")
w = window("", nil, { active = other_pane })
events["bell"](w, pane("1", { id = 9, cmd = "npm" }))
check("a long command ending says which one", w.toasts[1], "npm finished")

-- ---- reopening tabs ------------------------------------------------------------
os.execute('mkdir -p "' .. fake_home .. '/proj/a" "' .. fake_home .. '/proj/b"')
local function dir(path) local u = newproxy(true); getmetatable(u).__index = { file_path = path }; return u end
local function saved_tab(folders, active)
  local panes = {}
  for i, f in ipairs(folders) do panes[i] = pane("1", { cwd = dir(f) }) end
  return { tab = { panes = function() return panes end }, is_active = active }
end
mux.windows = { {
  get_workspace = function() return "default" end,
  tabs_with_info = function() return {
    saved_tab({ fake_home .. "/proj/a" }, false),
    saved_tab({ fake_home .. "/proj/b", fake_home .. "/proj/a" }, true),
    saved_tab({ fake_home .. "/gone" }, false),
  } end,
}, { get_workspace = function() return "hidden" end, tabs_with_info = function() error("other workspaces are not saved") end } }
local session = fake_home .. "/.cache/wezterm-warp/session.json"
os.remove(session)
GLOBAL.session_checked = nil
events["update-status"](window("", nil, { active = other_pane }))
f = io.open(session); written = f and f:read("a"); if f then f:close() end
check("open tabs and their folders are written down", written ~= nil and written:find('"folders":%["' .. fake_home:gsub("%-", "%%-") .. '/proj/b","') ~= nil, true)

mux.calls = {}
events["gui-startup"](nil)
check("starting WezTerm reopens them", table.concat(mux.calls, " | "),
  "window " .. fake_home .. "/proj/a | tab " .. fake_home .. "/proj/b | split pane2 -> " .. fake_home .. "/proj/a | tab " .. fake_home .. " | activate tab2")
mux.calls = {}
events["gui-startup"]({ args = { "htop" } })
check("  ...but not when started to run something", #mux.calls, 0)
pgrep_output = "100\n200\n"
events["gui-startup"](nil)
check("  ...and not next to a WezTerm that is already open", #mux.calls, 0)
pgrep_output = "100\n"
f = io.open(session, "w"); f:write("{not json"); f:close()
events["gui-startup"](nil)
check("  ...and a damaged file is ignored", #mux.calls, 0)
os.remove(session)

-- ---- projects --------------------------------------------------------------------
globbed[fake_home .. "/Developer/*/*/.git"] = { fake_home .. "/Developer/Swift/Meldrun/.git" }
globbed[fake_home .. "/Worktrees/*/*/.git"] = { fake_home .. "/Worktrees/Meldrun/path3/.git", fake_home .. "/Worktrees/Meldrun/path1/.git" }
w = window(""); key(config, "o", "CMD").run(w, pane("1"))
check("cmd+o opens the project picker", w.sent[1], "InputSelector:nil")
config, events, spawned = load_config("Dark")
local picker
local picking = window("")
function picking:perform_action(a) picker = a.arg end
key(config, "o", "CMD|SHIFT").run(picking, pane("1"))
local labels = {}
for i, choice in ipairs(picker.choices) do labels[i] = choice.label end
check("  ...listing every git project, sorted", table.concat(labels, " "), "~/Developer/Swift/Meldrun ~/Worktrees/Meldrun/path1 ~/Worktrees/Meldrun/path3")
mux.calls = {}
w = window("", nil, { mux_window = mux_window_stub() })
picker.action.run(w, nil, fake_home .. "/Worktrees/Meldrun/path3")
check("cmd+shift+o opens the folder, starts Claude Code, adds a shell beside it",
  table.concat(mux.calls, " | ") .. " | " .. tostring(w.sent[1]),
  "tab " .. fake_home .. "/Worktrees/Meldrun/path3 | split pane2 -> " .. fake_home .. "/Worktrees/Meldrun/path3 | focus pane2 | SendString:claude\r")
mux.calls = {}
picker.action.run(w, nil, nil)
check("  ...and escaping the picker opens nothing", #mux.calls, 0)

-- ---- links -------------------------------------------------------------------------
f = io.open(fake_home .. "/proj/a/main.swift", "w"); f:write("x"); f:close()
f = io.open(fake_home .. "/zed", "w"); f:write("x"); f:close()
local here = pane("1", { cwd = dir(fake_home .. "/proj") })
local function clicked(uri)
  local before = #spawned
  local result = events["open-uri"](nil, here, uri)
  return tostring(result) .. " " .. tostring(spawned[#spawned > before and #spawned or 0])
end
check("cmd+click on a relative path opens it in the editor at that line",
  clicked("open-path:a/main.swift:12:3"), "false " .. in_editor(fake_home .. "/proj/a/main.swift", ":12:3"))
check("  ...a ~ path too", clicked("open-path:~/proj/a/main.swift"), "false " .. in_editor(fake_home .. "/proj/a/main.swift", ""))
check("  ...a folder opens in Finder", clicked("open-path:" .. fake_home .. "/proj/a"), "false open " .. fake_home .. "/proj/a")
check("  ...text that is not a real file does nothing", clicked("open-path:10/10/2026"), "false nil")
check("  ...web links are left to open normally", clicked("https://example.com/a/b"), "nil nil")

-- ---- folder list -------------------------------------------------------------------
w = window(""); key(config, "g", "CMD|SHIFT").run(w, pane("1"))
check("cmd+shift+g asks zsh for the folder list", w.sent[1], "SendString:\27[997~")
w = window(""); key(config, "g", "CMD|SHIFT").run(w, pane("0", { process = CLAUDE }))
check("  ...and does nothing inside a program", #w.sent, 0)

local release = config.mouse_bindings[1].action.arg[3]
w = window(""); release.run(w, pane("1"))
check("a plain click looks for a link under the pointer", w.sent[1], "OpenLinkAtMouseCursor:nil")
w = window("dragged text"); release.run(w, pane("1"))
check("  ...but not at the end of a drag", #w.sent, 0)
check("double and triple clicks never open links", #config.mouse_bindings[2].action.arg, 2)

w = window(""); release.run(w, pane("1"))
w = window("")
check("a plain click on the folder chip opens the folder list",
  tostring(events["open-uri"](w, pane("1"), "wezwarp:folder")) .. " " .. tostring(w.sent[1]), "false SendString:\27[997~")
w = window(""); release.run(w, pane("1"))
check("a plain click on a web link opens nothing", tostring(events["open-uri"](w, here, "https://example.com/a/b")), "false")
w = window(""); release.run(w, pane("1"))
local before_plain = #spawned
events["open-uri"](w, here, "open-path:a/main.swift:12:3")
check("a plain click on a file path opens nothing", #spawned, before_plain)

local cmd_click
for _, binding in ipairs(config.mouse_bindings) do
  if binding.mods == "CMD" and binding.event.Up then cmd_click = binding.action end
end
w = window(""); cmd_click.run(w, pane("1"))
check("cmd+click still opens a web link the normal way", tostring((events["open-uri"](w, here, "https://example.com/a/b"))), "nil")
w = window(""); cmd_click.run(w, pane("1"))
check("cmd+click still opens a file path in the editor", clicked("open-path:a/main.swift:12:3"), "false " .. in_editor(fake_home .. "/proj/a/main.swift", ":12:3"))
w = window("")
check("the folder chip does nothing while a program is running",
  tostring(events["open-uri"](w, pane("0", { process = CLAUDE }), "wezwarp:folder")) .. " " .. #w.sent, "false 0")

-- ---- renaming and moving tabs ----------------------------------------------------------
check("the pop-up tab list is gone", key(config, "t", "CMD|SHIFT"), nil)
local named
local rename = key(config, "r", "CMD|SHIFT")
rename.arg.action.run({ active_tab = function() return { set_title = function(_, name) named = name end } end }, nil, "Meldrun UI")
check("cmd+shift+r names the tab", rename.name .. " " .. tostring(named), "PromptInputLine Meldrun UI")
named = "unchanged"
rename.arg.action.run({ active_tab = function() error("should not be asked") end }, nil, nil)
check("  ...and Esc leaves the name alone", named, "unchanged")
check("ctrl+shift+arrows move the tab", key(config, "LeftArrow", "CTRL|SHIFT").arg .. " " .. key(config, "RightArrow", "CTRL|SHIFT").arg, "-1 1")

-- ---- a grid of four ------------------------------------------------------------------
mux.calls = {}
local grid = mux_pane("main")
function grid:get_current_working_dir() return dir(fake_home .. "/proj") end
key(config, "4", "CMD|OPT").run(window(""), grid)
check("cmd+option+4 makes four panes in the same folder and stays in the first", table.concat(mux.calls, " | "),
  "split main -> " .. fake_home .. "/proj | split main -> " .. fake_home .. "/proj | split main+ -> " .. fake_home .. "/proj | focus main")

local passed = 0
for _, ok in ipairs(results) do passed = passed + (ok and 1 or 0) end
print(("\n%d/%d passed"):format(passed, #results))
os.exit(passed == #results and 0 or 1)

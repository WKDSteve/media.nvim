-- TESTS/sheets/_helpers.lua -- what every media.nvim test sheet needs in its child editor. Not a sheet
-- (`testing.sheet` only reads *.sheet.lua); a sheet's first step runs it with `dofile`, the child's cwd is
-- the project root. The directory is in the spec's @cache-inputs, so a change here re-runs the sheets.
--
-- The plugin runs for real on a three second test video that ffmpeg makes in a temp directory. What would
-- leave the editor is replaced: the picture viewer (`media.ui.show_image`) and the external player
-- (`media.play`) record their argument instead of opening a program.

vim.o.swapfile = false
vim.opt.shortmess:append("I")

_G.notes = {}
_G.warnings = {}
vim.notify = function(msg, level)
  _G.notes[#_G.notes + 1] = tostring(msg)
  if (level or vim.log.levels.INFO) >= vim.log.levels.WARN then
    _G.warnings[#_G.warnings + 1] = tostring(msg)
  end
end

---Whether a notification so far holds `text` (plain).
---@param text string
---@return boolean
function _G.noted(text)
  for _, n in ipairs(_G.notes) do
    if n:find(text, 1, true) then return true end
  end
  return false
end

---Forget the notifications and what the stubs recorded.
function _G.forget()
  _G.notes = {}
  _G.shown, _G.played = nil, nil
end

---The text of every floating window, joined.
---@return string
function _G.floattext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then
      local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false)
      out[#out + 1] = table.concat(lines, "\n")
    end
  end
  return table.concat(out, "\n")
end

---Make the test video, set the plugin up and open the video as the current buffer's name.
function _G.boot()
  _G.dir = vim.fn.tempname()
  vim.fn.mkdir(_G.dir, "p")
  _G.video = _G.dir .. "/clip.mp4"
  local made = vim
    .system({
      "ffmpeg",
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "testsrc=duration=3:size=320x240:rate=10",
      "-f",
      "lavfi",
      "-i",
      "sine=frequency=440:duration=3",
      "-shortest",
      "-pix_fmt",
      "yuv420p",
      _G.video,
    })
    :wait()
  assert(made.code == 0, "ffmpeg could not make the test video: " .. tostring(made.stderr))

  vim.env.XDG_CACHE_HOME = _G.dir .. "/cache"
  require("media").setup({})
  local ui = require("media.ui")
  _G.real_show_image = _G.real_show_image or ui.show_image
  ui.show_image = function(png)
    _G.shown = png
  end
  local media = require("media")
  media.play = function(path)
    _G.played = path
    return true
  end
  vim.cmd("edit " .. vim.fn.fnameescape(_G.video))
end

---A three second video without a sound track, beside the test video of `boot()`.
---@return string path
function _G.make_silent_video()
  local path = _G.dir .. "/silent.mp4"
  local made = vim
    .system({
      "ffmpeg",
      "-v",
      "error",
      "-f",
      "lavfi",
      "-i",
      "testsrc=duration=3:size=320x240:rate=10",
      "-an",
      "-pix_fmt",
      "yuv420p",
      path,
    })
    :wait()
  assert(made.code == 0, "ffmpeg could not make the silent video: " .. tostring(made.stderr))
  return path
end

---Replace the run of the registered whisper_cpp engine with a stand-in that records what it was asked
---(`_G.heard`: `{ wav, lang, task }` per run) and answers at once; `false` puts the real engine back.
---@param on? boolean
function _G.whisper_stand_in(on)
  local engine = require("media.engines.whisper_cpp")
  _G.real_whisper = _G.real_whisper
    or { available = engine.available, ready = engine.ready, transcribe = engine.transcribe }
  if on == false then
    for name, fn in pairs(_G.real_whisper) do
      engine[name] = fn
    end
    return
  end
  _G.heard = {}
  engine.available = function()
    return true
  end
  engine.ready = function()
    return true, nil
  end
  engine.transcribe = function(wav, opts, callback)
    _G.heard[#_G.heard + 1] = { wav = wav, lang = opts and opts.lang, task = opts and opts.task }
    vim.schedule(function()
      callback({
        engine = "whisper_cpp",
        model = "stand-in",
        lang = opts and opts.lang or "en",
        segments = { { s = 0, e = 1, text = "Hello from the stand-in" } },
        text = "Hello from the stand-in",
      }, nil)
    end)
    return { cancel = function() end }
  end
end

---The sidecar transcript of the test video.
---@return string
function _G.sidecar()
  return table.concat(vim.fn.readfile(_G.video .. ".transcript.md"), "\n")
end

---The text of every window's buffer, joined.
---@return string
function _G.buftext()
  local out = {}
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    out[#out + 1] =
      table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), "\n")
  end
  return table.concat(out, "\n")
end

---Close every other window (a transcript in a buffer or a float has the focus) and edit the test video again.
function _G.back_to_video()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative ~= "" then pcall(vim.api.nvim_win_close, w, true) end
  end
  vim.cmd("silent! only!")
  vim.cmd("edit! " .. vim.fn.fnameescape(_G.video))
end

---Width and height of a PNG, read from its IHDR chunk (bytes 17-24, big-endian).
---@param path string
---@return integer[] { width, height }
function _G.png_size(path)
  local f = assert(io.open(path, "rb"))
  local head = f:read(24)
  f:close()
  assert(head and #head == 24 and head:sub(2, 4) == "PNG", "not a PNG: " .. path)
  local function u32(at)
    local a, b, c, d = head:byte(at, at + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return { u32(17), u32(21) }
end

-- ── the sheets in the real own tree of filetree.nvim ─────────────────────────────────────────────────
-- media.nvim on a media node of the tree: the transcript badge and the three actions (transcribe, play,
-- contact sheet), from the context menu with the mouse and from the keys a config can give them.

local M = {}

---filetree.nvim and ui.nvim on the runtimepath; false when one is not to be found. For `requires`.
---TESTS/minimal_init.lua looked them up ($<NAME>_DIR, .deps/<name>, ../<name>, the lazy.nvim directory) and
---left what it found in `vim.g.media_sheets_deps`.
---@return boolean
function M.add_deps()
  local found = vim.g.media_sheets_deps or {}
  for _, name in ipairs({ "ui.nvim", "filetree.nvim" }) do
    local dir = found[name]
    if type(dir) ~= "string" or vim.fn.isdirectory(dir .. "/lua") ~= 1 then return false end
  end
  for _, name in ipairs({ "ui.nvim", "filetree.nvim" }) do
    vim.opt.rtp:append(found[name])
  end
  return true
end

---`got == want`, or an error that says what came instead (the failure line of the sheet shows it).
---@param got any
---@param want any
---@return boolean
function _G.eq(got, want)
  if not vim.deep_equal(got, want) then
    error(("got %s, wanted %s"):format(vim.inspect(got), vim.inspect(want)), 0)
  end
  return true
end

---@param path string
---@return boolean
function _G.exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

---A project `recordings` below the temp directory (`_G.rec`), images.nvim absent, media.nvim with a key per
---tree action (`gmt`, `gmp`, `gms`) and the own tree of filetree.nvim open on it, the cursor in README.md.
---The recordings are a few bytes each (nothing here decodes them) unless `video` is set: then
---`talks/standup.mp4` is a real three second video that ffmpeg makes, for the contact sheet.
---`talks/retro.mp4` has a transcript next to it, `talks/standup.mp4` and `audio/jingle.mp3` have none.
---@param opts? { video?: boolean, player?: string }  `player`: the `player` of the config (a sheet lists it as a fake).
function _G.tree_boot(opts)
  opts = opts or {}
  vim.o.hidden = true
  vim.o.laststatus = 0
  vim.o.ruler = false
  vim.o.showcmd = false
  vim.g.have_nerd_font = false

  local base = vim.fn.tempname()
  vim.fn.mkdir(base .. "/recordings", "p")
  -- spelled the way the editor reports it: a runner's temp may be a link or a short name
  _G.rec = vim.fs.normalize(assert(vim.uv.fs_realpath(base .. "/recordings")))
  for _, rel in ipairs({
    "README.md",
    "talks/retro.mp4",
    "talks/retro.mp4.transcript.md",
    "talks/standup.mp4",
    "audio/jingle.mp3",
  }) do
    local path = _G.rec .. "/" .. rel
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ rel:match("%.md$") and "# text" or "x" }, path)
  end
  if opts.video then
    local made = vim
      .system({
        "ffmpeg",
        "-y",
        "-v",
        "error",
        "-f",
        "lavfi",
        "-i",
        "testsrc=duration=3:size=320x240:rate=10",
        "-pix_fmt",
        "yuv420p",
        _G.rec .. "/talks/standup.mp4",
      })
      :wait()
    assert(made.code == 0, "ffmpeg could not make the test video: " .. tostring(made.stderr))
  end

  vim.env.XDG_CACHE_HOME = base .. "/cache"
  vim.cmd("cd " .. vim.fn.fnameescape(_G.rec))
  vim.cmd("edit " .. vim.fn.fnameescape(_G.rec .. "/README.md"))

  require("media").setup({
    keymaps = false,
    player = opts.player,
    tree = { keys = { transcribe = "gmt", play = "gmp", sheet = "gms" } },
  })
  -- media.nvim speaks through the toasts of lib.nvim, which never reach `vim.notify`: note what it says here
  local notifier = require("media.util.notify")
  local levels = { warn = vim.log.levels.WARN, error = vim.log.levels.ERROR }
  for _, name in ipairs({ "notify", "info", "warn", "error" }) do
    local real = notifier[name]
    if type(real) == "function" then
      notifier[name] = function(message, level, ...)
        _G.notes[#_G.notes + 1] = tostring(message)
        local at = name == "notify" and (type(level) == "number" and level or vim.log.levels.INFO)
          or levels[name]
          or vim.log.levels.INFO
        if at >= vim.log.levels.WARN then _G.warnings[#_G.warnings + 1] = tostring(message) end
        return real(message, level, ...)
      end
    end
  end
  -- the picture viewer: a headless child has no terminal that draws one
  require("media.ui").show_image = function(png)
    _G.shown = png
  end
  require("filetree").setup({
    adapter = "native",
    deps_popup = false,
    native = { width = 40 },
    features = {
      tree_toggle = { enabled = true },
      session = { enabled = false }, -- writes into the data directory
      close_on_open = { enabled = false },
    },
  })
  require("ui.contextmenu").setup({ renderer = "kit" })
  _G.adapter = require("filetree").adapter()
  _G.adapter.open_cwd()
end

---Every process the editor starts from here on is noted in `_G.spawned` (its argv) and started all the same.
function _G.watch_spawns()
  _G.spawned = {}
  local real = vim.system
  vim.system = function(argv, ...)
    _G.spawned[#_G.spawned + 1] = vim.deepcopy(argv)
    return real(argv, ...)
  end
end

---The first noted process whose program is `name` (its basename, without `.exe`), as one string; "" without one.
---@param name string
---@return string
function _G.spawn_of(name)
  for _, argv in ipairs(_G.spawned or {}) do
    local program = vim.fs.basename((tostring(argv[1]):gsub("\\", "/"))):gsub("%.exe$", "")
    if program == name then return table.concat(argv, " ") end
  end
  return ""
end

---An engine that answers at once, in place of whisper: the transcript is written by media.nvim itself, so the
---file and the badge that follow are the real ones. `_G.transcribed` lists the files it was asked for.
---@param ok? boolean  false: no engine is installed
function _G.engine_stand_in(ok)
  local text = require("media.hub.text")
  _G.transcribed = {}
  text.tool = function()
    if ok == false then
      return {
        ok = false,
        tool = "whisper.cpp",
        reason = "no engine is installed",
        fix = "install one",
      }
    end
    return { ok = true, tool = "stand-in" }
  end
  text.run = function(path, _, callback)
    _G.transcribed[#_G.transcribed + 1] = vim.fs.normalize(path)
    vim.schedule(function()
      callback({
        kind = "video",
        text = "Hello from the stand-in",
        tool = "stand-in",
        transcript = {
          engine = "whisper_cpp",
          lang = "en",
          segments = { { s = 0, e = 1, text = "Hello from the stand-in" } },
          text = "Hello from the stand-in",
        },
      }, nil)
    end)
  end
end

---The calls of the stand-in `program` (`fakes` of the sheet), as testing.fake_programs recorded them.
---@param program string
---@return { program: string, argv: string[], cwd: string }[]
function _G.calls(program)
  return require("testing.fake_programs").read(vim.env.TESTING_FAKES, program)
end

---The first line of the current buffer that holds `text` (plain), or "".
---@param text string
---@return string
function _G.line_with(text)
  for _, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(text, 1, true) then return line end
  end
  return ""
end

---The calls of the system opener stand-ins (`fakes = { "explorer", "xdg-open", "open" }`), in that order.
---@return { program: string, argv: string[], cwd: string }[]
function _G.opened()
  local out = {}
  for _, program in ipairs({ "explorer", "xdg-open", "open" }) do
    vim.list_extend(out, _G.calls(program))
  end
  return out
end

---On Windows lib.nvim's open_default starts `explorer.exe`, which a `.cmd` stand-in cannot catch; strip the `.exe`
---before its detached run, so the stand-in `explorer` is started instead (as markdown.nvim's opener sheets do;
---testing.nvim task fakes-unter-windows-exe-namen-explorer-exe-rundll32-exe-und). Elsewhere nothing changes.
function _G.opener_bare_name()
  if vim.fn.has("win32") == 0 then return end
  local run = require("lib.nvim.cross.run")
  local detached = run.run_detached
  run.run_detached = function(argv, opts)
    argv[1] = argv[1]:gsub("%.exe$", "")
    return detached(argv, opts)
  end
end

---Focus the tree window.
function _G.tree()
  if not _G.adapter.is_open() then _G.adapter.open_cwd() end
  vim.api.nvim_set_current_win(_G.adapter.get_winid())
end

---The line of `rel` (below the project) in the tree, or nil.
---@param rel string
---@return integer|nil
function _G.line_of(rel)
  return _G.adapter.get_node_line(_G.rec .. "/" .. rel)
end

---Press `keys` as typed (mappings apply).
---@param keys string
function _G.press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---Put the cursor of the tree on `rel`, opening the folders above it the way a person does: the cursor on the
---folder, then <CR>.
---@param rel string
function _G.on(rel)
  _G.tree()
  local win = _G.adapter.get_winid()
  local path
  for _, part in ipairs(vim.split(rel, "/", { plain = true })) do
    local parent = path
    path = path and (path .. "/" .. part) or part
    -- entering the tree may draw it anew: a line that is not there yet gets a moment
    vim.wait(3000, function()
      return _G.line_of(path) ~= nil or (parent ~= nil and _G.line_of(parent) ~= nil)
    end, 20)
    if not _G.line_of(path) then
      local line =
        assert(parent and _G.line_of(parent), "the tree does not show " .. tostring(parent))
      vim.api.nvim_win_set_cursor(win, { line, 0 })
      _G.press("<CR>")
      vim.wait(3000, function()
        return _G.line_of(path) ~= nil
      end, 20)
    end
  end
  local line = assert(_G.line_of(rel), "the tree does not show " .. rel)
  vim.api.nvim_win_set_cursor(win, { line, 0 })
  vim.cmd("doautocmd CursorMoved")
end

---The screen row of `rel` as the tree window shows it, "" when it does not. The badges are virtual text the
---tree places while it draws: only the screen has them.
---@param rel string
---@return string
function _G.row(rel)
  local line = _G.line_of(rel)
  if not line then return "" end
  local win = _G.adapter.get_winid()
  local pos = vim.fn.screenpos(win, line, 1)
  if pos.row == 0 then return "" end
  vim.cmd("redraw")
  local first = vim.api.nvim_win_get_position(win)[2]
  local cells = {}
  for col = first + 1, first + vim.api.nvim_win_get_width(win) do
    cells[#cells + 1] = vim.fn.screenstring(pos.row, col)
  end
  return (table.concat(cells):gsub("%s+$", ""))
end

---Whether the row of `rel` shows `text`.
---@param rel string
---@param text string
---@return boolean
function _G.row_has(rel, text)
  return _G.row(rel):find(text, 1, true) ~= nil
end

local clicks = 0

---A right click on the row of `rel`, as the mouse does it (0-based screen cells).
---@param rel string
function _G.right_click(rel)
  local win = _G.adapter.get_winid()
  local pos = vim.fn.screenpos(win, assert(_G.line_of(rel), "the tree does not show " .. rel), 1)
  -- Never the cell of the click before: two clicks on one cell within 'mousetime' are a double click
  -- (<2-RightMouse>), which opens no menu.
  clicks = clicks + 1
  local col = pos.col + 3 + clicks % 2
  vim.api.nvim_input_mouse("right", "press", "", 0, pos.row - 1, col)
  vim.api.nvim_input_mouse("right", "release", "", 0, pos.row - 1, col)
end

---The floating windows: `{ win, lines }` each.
---@return { win: integer, lines: string[] }[]
function _G.floats()
  local out = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      out[#out + 1] = {
        win = win,
        lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false),
      }
    end
  end
  return out
end

---Put the cursor of the open menu on the entry that holds `label`; false when no float has it.
---@param label string
---@return boolean
function _G.menu_on(label)
  for _, float in ipairs(_G.floats()) do
    for i, text in ipairs(float.lines) do
      if text:find(label, 1, true) then
        vim.api.nvim_set_current_win(float.win)
        vim.api.nvim_win_set_cursor(float.win, { i, 0 })
        return true
      end
    end
  end
  return false
end

---Close every floating window (a menu left open, a toast).
function _G.close_floats()
  for _, float in ipairs(_G.floats()) do
    pcall(vim.api.nvim_win_close, float.win, true)
  end
end

return M

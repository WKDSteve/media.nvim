-- TESTS/tree_drive.lua -- media.nvim in the real own tree of filetree.nvim: the transcript badge next to
-- a media file, what the preview key of the tree shows on a video and an audio node, the actions on a
-- media node by their keys, and the scan that follows the root of the tree.
--
-- Not a spec of the suite (no `_spec` in the name): filetree.nvim is no dependency of media.nvim, and the
-- state of a sibling checkout must not decide about this suite. A hand run, on filetree.nvim's bench
-- `TESTS/native_drive.lua`, which sets up the editor and quits it:
--
--   FILETREE_NVIM_DIR=<checkout> nvim --clean --headless -u NONE -l TESTS/tree_drive.lua
--
-- Nothing here needs ffmpeg, a player or a terminal that draws pictures: the two renderers
-- (`core.frame`, `core.waveform`) are replaced by recorders that answer with a PNG path, `images.show`
-- (what the tree hands a picture to) by one that notes the path, and `vim.system` by a counter that has
-- to stay at zero. The question is whether the tree reaches media.nvim with the node and shows what it
-- answers, not what ffmpeg draws (that is the suite's and the hand probe's).

---@diagnostic disable: need-check-nil, duplicate-set-field

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"):gsub("\\", "/")
local plugin = vim.fs.dirname(here)
vim.opt.rtp:prepend(plugin)

local filetree = (vim.env.FILETREE_NVIM_DIR or ""):gsub("\\", "/")
if filetree == "" or not vim.uv.fs_stat(filetree .. "/TESTS/native_drive.lua") then
  io.stdout:write("  n/a  $FILETREE_NVIM_DIR names no filetree.nvim: nothing was run\n")
  vim.cmd("cq")
  return
end
-- the bench looks for lib.nvim and ui.nvim next to filetree.nvim, or where these name them
for _, dep in ipairs({ "lib.nvim", "ui.nvim" }) do
  local var = dep:upper():gsub("%.", "_") .. "_DIR"
  local sibling = vim.fs.dirname(plugin) .. "/" .. dep
  if (vim.env[var] or "") == "" and vim.uv.fs_stat(sibling .. "/lua") then
    vim.env[var] = sibling
  end
end
-- nothing of the person's own setup: the caches go to a temp folder
local scratch = vim.fn.tempname():gsub("\\", "/")
vim.fn.mkdir(scratch, "p")
for _, var in ipairs({ "XDG_STATE_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME" }) do
  vim.env[var] = scratch
end

local calls = {}
local spawned = 0
local has_ffmpeg = true
local real_system = vim.system

local T = dofile(filetree .. "/TESTS/native_drive.lua")({
  name = "tree_drive (media.nvim)",
  files = {
    "README.md",
    "talks/retro.mp4",
    "talks/retro.mp4.transcript.md",
    "talks/standup.mp4",
    "audio/jingle.mp3",
    "lua/init.lua",
  },
  features = { preview = { enabled = true, cursor_debounce_ms = 10 } },
  before_setup = function(T)
    -- what the tree hands a picture to
    package.loaded["images"] = {
      show = function(path)
        calls[#calls + 1] = "show " .. tostring(path)
        return true
      end,
    }
    require("media").setup({
      keymaps = false,
      tree = { keys = { transcribe = "gmt", play = "gmp", sheet = "gms" } },
    })
    require("media.core.bin").find = function(name)
      if name == "ffmpeg" and not has_ffmpeg then return nil end
      return name
    end
    require("media.core.frame").frame = function(path, _, callback)
      calls[#calls + 1] = "frame " .. T.norm(path)
      vim.schedule(function()
        callback("/cache/frame.png", nil)
      end)
    end
    require("media.core.probe").probe = function(path, callback)
      calls[#calls + 1] = "probe " .. T.norm(path)
      vim.schedule(function()
        callback({ path = path, container = "mp4", duration = 61, has_video = true }, nil)
      end)
    end
    require("media.core.waveform").waveform = function(path, _, callback)
      calls[#calls + 1] = "waveform " .. T.norm(path)
      vim.schedule(function()
        callback("/cache/wave.png", nil)
      end)
    end
    for _, mod in ipairs({ "media.core.play", "media.core.player" }) do
      for name, fn in pairs(require(mod)) do
        if type(fn) == "function" and (name == "play" or name == "start") then
          require(mod)[name] = function()
            calls[#calls + 1] = "player"
          end
        end
      end
    end
  end,
})

local dir = T.dir
---The calls since `from`, the paths relative to the project.
local function called(from)
  local out = {}
  for i = from, #calls do
    out[#out + 1] = (calls[i]:gsub(vim.pesc(dir .. "/"), ""))
  end
  return out
end
local function has(name, text, needle)
  T.ok(
    name .. "  -- " .. vim.inspect(text),
    type(text) == "string" and text:find(needle, 1, true) ~= nil
  )
end
---Everything a float or a notification shows right now, as one string.
local function visible(from)
  local out = {}
  for _, float in ipairs(T.floats()) do
    out[#out + 1] = table.concat(float.lines, "\n")
  end
  for i = from, #T.notes do
    out[#out + 1] = tostring(T.notes[i].msg or T.notes[i][1] or vim.inspect(T.notes[i]))
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    out[#out + 1] =
      table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
  end
  return table.concat(out, "\n")
end

-- ── the transcript badge ─────────────────────────────────────────────────────
T.on("talks/retro.mp4")
T.ok(
  "a video with a transcript next to it gets the badge, once the background scan ended",
  T.wait(function()
    return T.drawn("talks/retro.mp4").text:find("transcript", 1, true) ~= nil
  end, 5000)
)
T.eq("the video without one has none", T.drawn("talks/standup.mp4").text, "")
T.eq("nor has the transcript itself", T.drawn("talks/retro.mp4.transcript.md").text, "")
T.eq("a folder shows nothing", T.drawn("talks").text, "")

-- a transcript media.nvim writes shows up without a scan
local wrote = require("media.output").deliver(dir .. "/audio/jingle.mp3", {
  engine = "whisper_cpp",
  lang = "en",
  segments = { { s = 0, e = 1, text = "Hello" } },
  text = "Hello",
}, "sidecar")
T.eq("media.nvim writes a transcript for the audio file", wrote, true)
T.on("audio/jingle.mp3")
T.ok(
  "... and the badge is there",
  T.wait(function()
    return T.drawn("audio/jingle.mp3").text:find("transcript", 1, true) ~= nil
  end, 5000)
)

-- ── the preview key on a media node ──────────────────────────────────────────
vim.system = function(...)
  spawned = spawned + 1
  return real_system(...)
end

local mark = T.mark()
local from = #calls + 1
T.on("talks/standup.mp4")
T.feed("<Tab>")
T.wait(function()
  return #calls >= from + 1
end)
T.eq(
  "<Tab> on a video asks media.nvim for a still and shows the picture",
  called(from),
  { "frame talks/standup.mp4", "show /cache/frame.png" }
)

-- the preview follows the cursor: what ffprobe says about the next file, and no render for it
T.on("README.md")
T.feed("<Tab>")
T.settle(200)
from = #calls + 1
T.on("talks/retro.mp4")
T.ok(
  "moving onto a media file with a preview shown asks media.nvim",
  T.wait(function()
    return #calls >= from
  end, 3000)
)
T.settle(200)
T.eq("... for the record of the file, not for a picture", called(from), { "probe talks/retro.mp4" })
T.ok(
  "... which the preview shows",
  T.wait(function()
    return visible(#T.notes + 1):find("duration", 1, true) ~= nil
  end, 3000)
)
require("filetree.features.ui.preview").close()
T.close_floats()

from = #calls + 1
T.on("audio/jingle.mp3")
T.feed("<Tab>")
T.wait(function()
  return #calls >= from + 1
end)
T.eq(
  "<Tab> on an audio file shows its waveform",
  called(from),
  { "waveform audio/jingle.mp3", "show /cache/wave.png" }
)
T.eq("neither says anything at warning level", T.loud(mark), {})
T.close_floats()

-- without ffmpeg: one line that says what is missing, and no picture
has_ffmpeg = false
mark = T.mark()
local notes_from = #T.notes + 1
from = #calls + 1
T.on("talks/standup.mp4")
T.feed("<Tab>")
T.ok(
  "without ffmpeg the preview says so",
  T.wait(function()
    return visible(notes_from):find("ffmpeg not found", 1, true) ~= nil
  end, 3000)
)
has("... in the words of media.nvim", visible(notes_from), "media.nvim: ffmpeg not found")
T.eq("... and asks no renderer", called(from), {})
T.eq("... without a warning", T.loud(mark), {})
has_ffmpeg = true
T.close_floats()

-- a file that is no media file is none of media.nvim's business
from = #calls + 1
T.on("README.md")
T.feed("<Tab>")
T.settle(200)
T.eq("<Tab> on another file reaches no renderer", called(from), {})
T.feed("<Tab>")
T.close_floats()

T.eq("no process was started for any of it", spawned, 0)
local players = vim.tbl_filter(function(call)
  return call == "player"
end, calls)
T.eq("and no player", #players, 0)

vim.system = real_system

-- ── the actions on a media node ──────────────────────────────────────────────
-- The keys are the ones this run configured (`tree.keys`). Stand-ins for the player, the renderer of
-- the contact sheet and the engines; the sidecar is written by media.nvim itself, so the badge that
-- follows is the real one.
if type(require("lib.nvim.tree.registry").action) ~= "function" then
  T.na("this lib.nvim has no actions at its registry: the actions of media.nvim are not there")
else
  local text = require("media.hub.text")
  ---@type table
  local engine = { ok = true, tool = "stand-in" }
  require("media.core.play").play = function(path)
    calls[#calls + 1] = "play " .. T.norm(path)
    return true
  end
  require("media.core.sheet").sheet = function(path, _, callback)
    calls[#calls + 1] = "sheet " .. T.norm(path)
    vim.schedule(function()
      callback("/cache/sheet.png", nil)
    end)
  end
  text.tool = function()
    return engine
  end
  text.run = function(path, _, callback)
    calls[#calls + 1] = "transcribe " .. T.norm(path)
    vim.schedule(function()
      callback({
        kind = "video",
        text = "Hello",
        tool = "stand-in",
        transcript = {
          engine = "whisper_cpp",
          lang = "en",
          segments = { { s = 0, e = 1, text = "Hello" } },
          text = "Hello",
        },
      }, nil)
    end)
  end

  -- no preview that follows the cursor from here on: it would ask for the record of every node
  require("filetree.features.ui.preview").close()
  T.close_floats()
  from = #calls + 1
  T.on("talks/standup.mp4")
  T.eq("the video has no transcript yet", T.drawn("talks/standup.mp4").text, "")
  T.feed("gmp")
  T.wait(function()
    return #calls >= from
  end)
  T.eq("the play key hands the video to the player", called(from), { "play talks/standup.mp4" })

  from = #calls + 1
  T.feed("gms")
  T.wait(function()
    return #calls >= from + 1
  end)
  T.eq(
    "the sheet key renders the contact sheet and shows it",
    called(from),
    { "sheet talks/standup.mp4", "show /cache/sheet.png" }
  )
  T.close_floats()

  from = #calls + 1
  T.on("talks/standup.mp4")
  T.feed("gmt")
  T.ok(
    "the transcribe key writes the transcript next to the video",
    T.wait(function()
      return T.exists("talks/standup.mp4.transcript.md")
    end, 5000)
  )
  T.eq("... with one run of the engine", called(from), { "transcribe talks/standup.mp4" })
  T.ok(
    "... and the badge follows",
    T.wait(function()
      return T.drawn("talks/standup.mp4").text:find("transcript", 1, true) ~= nil
    end, 5000)
  )

  -- an audio file has no contact sheet: the key is not media.nvim's there
  from = #calls + 1
  T.on("audio/jingle.mp3")
  T.feed("gms")
  T.settle(200)
  T.eq("the sheet key on an audio file renders nothing", called(from), {})
  T.feed("gmp")
  T.wait(function()
    return #calls >= from
  end)
  T.eq("... the play key plays it", called(from), { "play audio/jingle.mp3" })

  -- a file that is no media file
  from = #calls + 1
  T.on("README.md")
  T.feed("gmp")
  T.feed("gmt")
  T.settle(200)
  T.eq("on another file none of the keys reaches media.nvim", called(from), {})

  -- without an engine: the reason, and no run
  engine =
    { ok = false, tool = "whisper.cpp", reason = "no engine is installed", fix = "install one" }
  from = #calls + 1
  -- media.nvim speaks through lib.nvim's toasts, which the bench does not read
  local said = {}
  local notifier = require("media.util.notify")
  local real_notify = notifier.notify
  notifier.notify = function(message, ...)
    said[#said + 1] = tostring(message)
    return real_notify(message, ...)
  end
  T.on("talks/retro.mp4")
  T.feed("gmt")
  T.ok(
    "without an engine the transcribe key says what is missing",
    T.wait(function()
      return table.concat(said, " "):find("no engine is installed", 1, true) ~= nil
    end, 3000)
  )
  T.eq("... and starts nothing", called(from), {})
  notifier.notify = real_notify
  T.close_floats()
end

-- ── the scan follows the root of the tree ────────────────────────────────────
local native = require("filetree.native")
if type(native.roots) ~= "function" then
  T.na(
    "this filetree.nvim does not say which roots its trees show: the scan stays at the working directory"
  )
else
  local elsewhere = T.norm(vim.fn.tempname())
  vim.fn.mkdir(elsewhere, "p")
  for _, name in ipairs({ "clip.mp4", "clip.mp4.transcript.md" }) do
    local fd = assert(io.open(elsewhere .. "/" .. name, "w"))
    fd:write("x")
    fd:close()
  end
  local decorator = require("lib.nvim.tree.registry").get("decorator", "transcript")
  T.tree()
  T.ok(
    "the tree moves to a folder outside the working directory",
    native.current():set_root(elsewhere)
  )
  T.ok(
    "... which it shows",
    T.wait(function()
      return T.adapter.get_node_line(elsewhere .. "/clip.mp4") ~= nil
    end, 3000)
  )
  T.ok(
    "... and the video there gets its badge",
    T.wait(function()
      return decorator.get(elsewhere .. "/clip.mp4") ~= nil
    end, 5000)
  )
  T.eq(
    "what lay below the root it left is forgotten",
    decorator.get(dir .. "/talks/retro.mp4"),
    nil
  )
  native.current():set_root(dir)
  T.ok(
    "back at the project its badges are back",
    T.wait(function()
      return decorator.get(dir .. "/talks/retro.mp4") ~= nil
    end, 5000)
  )
  vim.fn.delete(elsewhere, "rf")
end

T.eq("no dialog nobody expected", T.unanswered, 0)
require("media.integrations.tree").unregister()
vim.fn.delete(scratch, "rf")
T.finish()

-- TESTS/tree_drive.lua -- media.nvim in the real own tree of filetree.nvim: the transcript badge next to
-- a media file, and what the preview key of the tree shows on a video and an audio node.
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
  features = { preview = { enabled = true } },
  before_setup = function(T)
    -- what the tree hands a picture to
    package.loaded["images"] = {
      show = function(path)
        calls[#calls + 1] = "show " .. tostring(path)
        return true
      end,
    }
    require("media").setup({ keymaps = false })
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
T.eq("no dialog nobody expected", T.unanswered, 0)
require("media.integrations.tree").unregister()
vim.fn.delete(scratch, "rf")
T.finish()

---@module 'media.integrations.tree'
---@brief In a tree view: a badge on media files that have a transcript, and a still as their preview.
---@description
--- Two entries at `lib.nvim.tree.registry`, read by a tree that knows the
--- registry (the own tree of filetree.nvim):
---
--- **The decorator `transcript`.** A badge next to a video or audio file whose
--- sidecar `<file>.transcript.md` exists; another highlight when the file
--- changed after the sidecar was written. Its `get` is a table lookup. The table
--- is filled by a scan of the working directory that runs in the background
--- (`media.hub.transcripts`), and only while a tree listens:
---  - when the first tree subscribes
---  - after a file operation of a tree (`User FiletreeChanged`,
---    `User FileopsChanged`) and after `:cd` (`DirChanged`), a moment later and
---    once for however many of them came together
---  - on demand: `require("media.integrations.tree").rescan()`
---
--- A transcript media.nvim itself wrote (`User MediaTranscriptWritten`) costs no
--- scan: that one file is looked at.
---
--- The home folder and the top of a drive are not scanned (`too_wide`): they are
--- no project.
---
--- **The previewer `media`.** For a video node one still (`media.core.frame`),
--- for an audio node its waveform (`media.core.waveform`): a PNG in the cache of
--- media.nvim, handed to the tree's preview as the picture to show. Rendering
--- runs in the background and a player is never started. Without ffmpeg the
--- answer is one line that says so. While the preview follows the cursor
--- (`ctx.trigger == "cursor"`) nothing is rendered: the answer is what ffprobe
--- says about the file, as lines.
---
--- Soft in both directions. The registry is lib.nvim's: without a tree that reads
--- it the entries are never looked at, without a lib.nvim that has the registry
--- nothing is registered, and a registry without previewers gets the decorator
--- alone.

local M = {}

M.NAME = "transcript"
M.PREVIEWER = "media"

---How long after the last change a scan starts, in milliseconds.
M.DEBOUNCE_MS = 400

---What the tree's preview is told about a node, in one of three shapes.
---@class Media.Tree.Preview
---@field image? string  A picture to show in place of the file.
---@field lines? string[]  What is known about the file, while the preview follows the cursor.
---@field title? string  A line about the file (size, duration, codec), when it is known.
---@field note? string   One line instead of a picture: what is missing.

local AUGROUP = "media.tree.transcripts"

---@type fun()|nil
local unregister_decorator = nil
---@type fun()|nil
local unregister_previewer = nil
---@type table<string, table>  path -> badge
local badges = {}
---@type table<integer, fun(keys?: string[])>
local listeners = {}
local next_listener = 0
---@type fun()|nil  cancels the running scan
local cancel_scan = nil
---@type uv.uv_timer_t|nil
local timer = nil
local badge_text = "transcript"
---@type Media.Hub.Transcripts.Result|nil
local last = nil

---@param status Media.Hub.Transcripts.Status
---@return table
local function badge(status)
  return {
    text = badge_text,
    hl = status == "stale" and "DiagnosticWarn" or "DiagnosticOk",
    status = status,
    count = 1,
  }
end

---@param keys? string[]
local function tell(keys)
  for _, emit in pairs(listeners) do
    pcall(emit, keys)
  end
end

---Take the result of a scan: replace the table and name the keys that changed.
---@param result Media.Hub.Transcripts.Result
local function adopt(result)
  last = result
  local changed = {}
  for path, old in pairs(badges) do
    if result.transcripts[path] ~= old.status then changed[#changed + 1] = path end
  end
  local fresh = {}
  for path, status in pairs(result.transcripts) do
    if not badges[path] then changed[#changed + 1] = path end
    fresh[path] = badge(status)
  end
  badges = fresh
  if #changed > 0 then
    table.sort(changed)
    tell(changed)
  end
end

---Whether `root` is no project but a place everything lies below: the home folder, or the top of a
---drive. Walking it would read tens of thousands of entries after every file operation.
---@param root string
---@return boolean
function M.too_wide(root)
  local norm = require("media.hub.transcripts").norm
  root = norm(root)
  if root == "/" or root:match("^%a:/?$") then return true end
  local home = vim.uv.os_homedir()
  return home ~= nil and norm(home):lower() == root:lower()
end

---Scan the working directory again, in the background. Without a listening tree nothing happens
---unless `force` is set (a caller that wants the table for itself).
---@param force? boolean
function M.rescan(force)
  if not force and next(listeners) == nil then return end
  if cancel_scan then cancel_scan() end
  cancel_scan = nil
  local root = vim.fn.getcwd()
  if M.too_wide(root) then
    adopt({ root = root, transcripts = {}, partial = true, entries = 0 })
    return
  end
  cancel_scan = require("media.hub.transcripts").scan(root, function(result)
    cancel_scan = nil
    adopt(result)
  end)
end

---Look at one media file again (its transcript was written or removed), without a scan. A file
---outside what the last scan covered gets its badge all the same: the tree only asks for what it shows.
---@param path string
function M.refresh(path)
  if type(path) ~= "string" or path == "" or next(listeners) == nil then return end
  local transcripts = require("media.hub.transcripts")
  path = transcripts.norm(path)
  local status = transcripts.status(path)
  local old = badges[path]
  if (old and old.status) == status then return end
  badges[path] = status and badge(status) or nil
  if last then last.transcripts[path] = status end
  tell({ path })
  -- A scan that is on its way may have read the folder before the file changed, and its answer
  -- replaces the table: look once more when it is through.
  if cancel_scan then M.rescan_soon() end
end

---`rescan` after `DEBOUNCE_MS` without another call.
function M.rescan_soon()
  if not timer then timer = vim.uv.new_timer() end
  if not timer then
    M.rescan()
    return
  end
  timer:stop()
  timer:start(
    M.DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      M.rescan()
    end)
  )
end

local function start_listening()
  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "FiletreeChanged", "FileopsChanged" },
    callback = M.rescan_soon,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MediaTranscriptWritten",
    callback = function(args)
      local data = args.data
      if type(data) == "table" then M.refresh(data.path) end
    end,
  })
  vim.api.nvim_create_autocmd("DirChanged", { group = group, callback = M.rescan_soon })
end

local function stop_listening()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
  if cancel_scan then
    cancel_scan()
    cancel_scan = nil
  end
end

---What the last scan found, or nil before the first one ended (for `:checkhealth` and the specs).
---@return Media.Hub.Transcripts.Result|nil
function M.last_scan()
  return last
end

-- ── the preview ──────────────────────────────────────────────────────────────

---Whether the previewer takes a node: a path with an extension media.nvim claims. Asked on every
---cursor move, so it reads the name and nothing else.
---@param node { path?: string }|nil
---@return boolean
function M.previews(node)
  return type(node) == "table" and require("media.formats").is_media(node.path)
end

---The preview of a media node: a still of a video, the waveform of an audio file. Returns at once;
---`done` is called exactly once, on the main loop, unless the returned function was called before.
---
---With `ctx.trigger == "cursor"` (the preview follows the cursor from node to node) the answer is the
---record of the file as lines (`media.ui.describe`): a tree shows no picture per line it passes, and
---a still rendered for each of them would be work for a title.
---@param node { path?: string }
---@param ctx { trigger?: string }|nil  What the tree says about its preview.
---@param done fun(result: Media.Tree.Preview)
---@return fun() cancel
function M.preview(node, ctx, done)
  local cancelled = false
  ---@type Media.Render.Handle|nil  the render the answer waits for
  local running = nil
  local path = node.path
  ---@param result Media.Tree.Preview
  local function answer(result)
    if cancelled then return end
    cancelled = true
    done(result)
  end
  -- A node the cursor left: the answer is dropped, and so is a render that still waits for a slot
  -- (moving down a folder of recordings must not queue a waveform for each of them).
  local function cancel()
    cancelled = true
    if running then running.cancel() end
  end

  if type(path) ~= "string" or not M.previews(node) then
    vim.schedule(function()
      answer({ note = "media.nvim: not a media file" })
    end)
    return cancel
  end
  ---One line out of whatever a tool printed.
  ---@param err string|nil
  ---@return string
  local function one_line(err)
    return "media.nvim: " .. (tostring(err or "nothing to show"):gsub("%s*\n.*", ""))
  end

  if type(ctx) == "table" and ctx.trigger == "cursor" then
    require("media.core.probe").probe(path, function(record, err)
      if not record then
        answer({ note = one_line(err) })
        return
      end
      local ui = require("media.ui")
      local title = ui.summary(record)
      answer({ lines = ui.describe(record), title = title ~= "" and title or nil })
    end)
    return cancel
  end

  if not require("media.core.bin").find("ffmpeg") then
    vim.schedule(function()
      answer({ note = "media.nvim: ffmpeg not found (install it, or set `bin.ffmpeg`)" })
    end)
    return cancel
  end

  local formats = require("media.formats")

  ---@param png string|nil
  ---@param err string|nil
  local function finish(png, err)
    if not png then
      answer({ note = one_line(err) })
      return
    end
    -- known by now: both renderers probe before they render
    local probe = require("media.core.probe").cached(path)
    local title = probe and require("media.ui").summary(probe) or nil
    answer({ image = png, title = title ~= "" and title or nil })
  end

  local function waveform()
    running = require("media.core.waveform").waveform(path, nil, finish)
  end

  if formats.is_audio(path) then
    waveform()
  else
    local frame = require("media.core.frame")
    running = frame.frame(path, nil, function(png, err)
      -- a container that usually holds a film and here holds sound only
      if not png and not cancelled and err == frame.NO_PICTURE then
        waveform()
        return
      end
      finish(png, err)
    end)
  end
  return cancel
end

-- ── registering ──────────────────────────────────────────────────────────────

---Register the decorator and, where the registry takes one, the previewer. Without
---`lib.nvim.tree.registry` (an older lib.nvim) nothing happens.
---@param opts? Media.Opts.Tree  `badge`: the text of the badge; `preview = false`: the decorator alone.
---@return boolean registered
function M.register(opts)
  local ok, registry = pcall(require, "lib.nvim.tree.registry")
  if not ok or type(registry.decorator) ~= "function" then return false end
  M.unregister()
  opts = type(opts) == "table" and opts or {}
  badge_text = type(opts.badge) == "string" and opts.badge ~= "" and opts.badge or "transcript"
  unregister_decorator = registry.decorator({
    name = M.NAME,
    key = "path",
    slot = "badge",
    priority = 20,
    roll_up = false,
    severity = { "stale", "ok" },
    get = function(path)
      return badges[path]
    end,
    all = function()
      return badges
    end,
    subscribe = function(emit)
      next_listener = next_listener + 1
      local id = next_listener
      local first = next(listeners) == nil
      listeners[id] = emit
      if first then
        start_listening()
        M.rescan()
      end
      return function()
        listeners[id] = nil
        if next(listeners) == nil then stop_listening() end
      end
    end,
  })
  if opts.preview ~= false and type(registry.previewer) == "function" then
    unregister_previewer = registry.previewer({
      name = M.PREVIEWER,
      match = M.previews,
      preview = M.preview,
    })
  end
  return true
end

---Take both entries out again and stop everything behind them.
function M.unregister()
  if unregister_decorator then
    unregister_decorator()
    unregister_decorator = nil
  end
  if unregister_previewer then
    unregister_previewer()
    unregister_previewer = nil
  end
  listeners = {}
  stop_listening()
  badges = {}
  last = nil
end

return M

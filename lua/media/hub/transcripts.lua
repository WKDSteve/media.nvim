---@module 'media.hub.transcripts'
---@brief Which media files below a folder have a transcript next to them.
---@description
--- The dashboard answers the same question for one scan it shows and throws
--- away (`media.hub.scan`); this is the form a tree view needs: a table by
--- path, filled without holding the editor up, that a decorator can read while
--- it draws.
---
--- **A transcript is the sidecar** `<file>.transcript.md`
--- (`media.output.sidecar`), next to a file whose extension `media.formats`
--- claims. The JSON an engine run leaves in the cache directory is not one: it
--- is keyed by engine, model and language, so "is there one for this file" has
--- no single answer there, and nothing a reader can open.
---
--- **The walk reads folders with the synchronous calls, in slices**: after
--- `SLICE_MS` it yields to the main loop, so a large project costs many short
--- stops and no long one. Only a folder that holds a sidecar costs more than
--- its listing (two `fs_stat` per sidecar, for the age rule of
--- `media.hub.scan.status`).
---
--- **A walk that was cut short still names what it saw.** A badge here is
--- positive evidence (the sidecar was found), unlike a list of what is missing.

local M = {}

local uv = vim.uv or vim.loop

local SUFFIX = ".transcript.md"

---How long one slice of a background scan may take, in milliseconds.
M.SLICE_MS = 8

---@alias Media.Hub.Transcripts.Status "ok"|"stale"

---@class Media.Hub.Transcripts.Result
---@field root string
---@field transcripts table<string, Media.Hub.Transcripts.Status>  By path of the media file (`/`, drive letter upper case).
---@field partial boolean   The walk stopped at `hub.max_entries`.
---@field entries integer   Directory entries the walk looked at.

---One spelling for a path, the one a tree view uses for its keys: `/`-separated, the drive letter in
---upper case, no trailing slash.
---@param path string
---@return string
function M.norm(path)
  path = path:gsub("\\", "/")
  path = path:gsub("^(%a):", function(drive)
    return drive:upper() .. ":"
  end)
  if #path > 1 and path:sub(-1) == "/" and not path:match("^%a:/$") then path = path:sub(1, -2) end
  return path
end

---The media file a sidecar name belongs to, or nil when `name` is no transcript of one.
---@param name string
---@return string|nil
function M.source_name(name)
  if #name <= #SUFFIX or name:sub(-#SUFFIX) ~= SUFFIX then return nil end
  local source = name:sub(1, -#SUFFIX - 1)
  if not require("media.formats").is_media(source) then return nil end
  return source
end

---The state of the transcript of one media file, from the disk: nil without a sidecar, `"stale"` when
---the file changed after the sidecar was written (the rule of `media.hub.scan.status`).
---@param path string
---@return Media.Hub.Transcripts.Status|nil
function M.status(path)
  local side = uv.fs_stat(path .. SUFFIX)
  if not side or side.type ~= "file" then return nil end
  local source = uv.fs_stat(path)
  if not source then return nil end
  local written = side.mtime and side.mtime.sec or 0
  local changed = source.mtime and source.mtime.sec or 0
  return changed > written and "stale" or "ok"
end

---@return table<string, true> skip
---@return integer max_entries
local function limits()
  local hub = require("media.config").get().hub or {}
  local skip = { [".git"] = true, node_modules = true }
  for _, name in ipairs(type(hub.exclude) == "table" and hub.exclude or {}) do
    if type(name) == "string" then skip[name] = true end
  end
  local max = type(hub.max_entries) == "number" and hub.max_entries > 0 and hub.max_entries or 20000
  return skip, max
end

---The scan as a coroutine body: `pause()` is called between folders and may yield.
---@param root string
---@param pause fun()
---@return Media.Hub.Transcripts.Result
local function run(root, pause)
  root = M.norm(root)
  local skip, max_entries = limits()
  local found, entries, partial = {}, 0, false
  local queue, head = { root }, 1
  while queue[head] do
    local dir = queue[head]
    head = head + 1
    local handle = uv.fs_scandir(dir)
    ---@type table<string, true>  the files of this folder
    local files = {}
    ---@type string[]  the media files of this folder a sidecar names
    local sources = {}
    while handle do
      local name, kind = uv.fs_scandir_next(handle)
      if not name then break end
      entries = entries + 1
      if entries > max_entries then
        partial = true
        break
      end
      if kind == "directory" then
        -- a link to a folder is not followed: it may point back up
        if not skip[name] then queue[#queue + 1] = dir .. "/" .. name end
      elseif kind == "file" or kind == "link" then
        files[name] = true
        local source = M.source_name(name)
        if source then sources[#sources + 1] = source end
      end
    end
    -- what a cut listing already showed is still true
    for _, source in ipairs(sources) do
      if files[source] then
        local path = dir .. "/" .. source
        local status = M.status(path)
        if status then found[path] = status end
      end
    end
    if partial then break end
    pause()
  end
  return { root = root, transcripts = found, partial = partial, entries = entries }
end

---Scan `root` in one go (specs, and a caller that waits anyway).
---@param root string
---@return Media.Hub.Transcripts.Result
function M.scan_sync(root)
  return run(root, function() end)
end

---Scan `root` in the background: slices of `SLICE_MS` on the main loop, `on_done(result)` at the end.
---The returned function cancels the scan (`on_done` is then never called).
---@param root string
---@param on_done fun(result: Media.Hub.Transcripts.Result)
---@return fun() cancel
function M.scan(root, on_done)
  local cancelled = false
  local started = uv.hrtime()
  local co = coroutine.create(function()
    return run(root, function()
      if (uv.hrtime() - started) / 1e6 >= M.SLICE_MS then coroutine.yield() end
    end)
  end)
  local function step()
    if cancelled then return end
    started = uv.hrtime()
    local ok, result = coroutine.resume(co)
    -- a scan that failed names nothing; the reader keeps what it had
    if not ok then return end
    if coroutine.status(co) == "dead" then
      on_done(result)
    else
      vim.schedule(step)
    end
  end
  vim.schedule(step)
  return function()
    cancelled = true
  end
end

return M

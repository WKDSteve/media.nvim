---@module 'media.integrations.tree'
---@brief In a tree view: a badge on media files that have a transcript, and a still as their preview.
---@description
--- Entries at `lib.nvim.tree.registry`, read by a tree that knows the
--- registry (the own tree of filetree.nvim):
---
--- **The decorator `transcript`.** A badge next to a video or audio file whose
--- sidecar `<file>.transcript.md` exists; another highlight when the file
--- changed after the sidecar was written. Its `get` is a table lookup. The table
--- is filled by scans that run in the background (`media.hub.transcripts`), one
--- per root a listening tree shows, and only while a tree listens:
---  - a root is scanned when a tree first shows it: the tree says which roots
---    there are (`ctx.roots()`, the second argument of `subscribe`) and when
---    they change (`User FiletreeRoots`). The other roots are left alone then,
---    and what was found below a root no tree shows any more is forgotten
---  - every root again after a file operation of a tree (`User FiletreeChanged`,
---    `User FileopsChanged`), a moment later and once for however many of them
---    came together
---  - the folders the tree's watcher reports (`User FiletreeFsChanged`, `data.dirs`): no scan, the
---    media files of just those folders are looked at again, so a transcript another program writes
---    or deletes shows at once
---  - on demand: `require("media.integrations.tree").rescan()`
---
--- A tree that hands no context (a filetree.nvim before `FiletreeRoots`) stands
--- for the working directory, scanned again after `:cd` (`DirChanged`).
---
--- The badges are keyed by the path below the root in the spelling the tree
--- names it: a root behind a link is scanned through the link, as the tree
--- shows it.
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
--- **Three actions** on a media node, in the menu of the tree and on a key where
--- one is configured (`tree.keys`):
---
---   media.transcribe  the dashboard's "Transcribe → sidecar"; with several
---                     nodes marked every media file among them, one after
---                     another under one progress handle
---   media.play        `:Media play <node>`
---   media.sheet       `:Media sheet <node>`, on a video
---
--- Playing and the contact sheet are no batch: with several nodes marked they
--- run on the first and say so. An action whose tool is missing (no engine, no
--- ffmpeg) says which one and starts nothing.
---
--- Soft in both directions. The registry is lib.nvim's: without a tree that reads
--- it the entries are never looked at, without a lib.nvim that has the registry
--- nothing is registered, and a registry without previewers or actions gets what
--- it takes.

local M = {}

M.NAME = "transcript"
M.PREVIEWER = "media"
M.TRANSCRIBE = "media.transcribe"
M.PLAY = "media.play"
M.SHEET = "media.sheet"

---How long after the last change a scan starts, in milliseconds.
M.DEBOUNCE_MS = 400

---What the tree's preview is told about a node, in one of three shapes.
---@class Media.Tree.Preview
---@field image? string  A picture to show in place of the file.
---@field lines? string[]  What is known about the file, while the preview follows the cursor.
---@field title? string  A line about the file (size, duration, codec), when it is known.
---@field note? string   One line instead of a picture: what is missing.

local AUGROUP = "media.tree.transcripts"

---One tree that listens: what it wants to be told, and where it says which roots the trees show.
---@class Media.Tree.Listener
---@field emit fun(keys?: string[])
---@field ctx? { roots?: fun(): string[] }  What `subscribe` was handed next to `emit`; nil with a tree that hands none.

---The scan of one root.
---@class Media.Tree.Scan
---@field cancel? fun()  Set while the scan runs.
---@field token? table  Names the run whose answer is waited for.
---@field result? Media.Hub.Transcripts.Result  What the last finished scan of this root found.

---@type fun()|nil
local unregister_decorator = nil
---@type fun()|nil
local unregister_previewer = nil
---@type (fun())[]
local unregister_actions = {}
---@type table<string, table>  path -> badge
local badges = {}
---@type table<integer, Media.Tree.Listener>
local listeners = {}
local next_listener = 0
---@type table<string, Media.Tree.Scan>  by root, in the spelling the tree named it
local scans = {}
---@type table<string, Media.Hub.Transcripts.Status>  files looked at one by one that no finished scan covers
local loose = {}
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
  for _, listener in pairs(listeners) do
    pcall(listener.emit, keys)
  end
end

---Whether `path` lies below `root` (both in the spelling of `norm`).
---@param path string
---@param root string
---@return boolean
local function below(path, root)
  local prefix = root:sub(-1) == "/" and root or root .. "/"
  return path:sub(1, #prefix) == prefix
end

---Put the table together again from what the scans found and what was looked at file by file, and
---name the keys that changed.
local function rebuild()
  ---@type table<string, Media.Hub.Transcripts.Status>
  local found = {}
  for path, status in pairs(loose) do
    found[path] = status
  end
  for _, scan in pairs(scans) do
    for path, status in pairs(scan.result and scan.result.transcripts or {}) do
      -- two roots, one below the other, both saw the file: "stale" is the one that says more
      if found[path] ~= "stale" then found[path] = status end
    end
  end
  local changed = {}
  for path, old in pairs(badges) do
    if found[path] ~= old.status then changed[#changed + 1] = path end
  end
  local fresh = {}
  for path, status in pairs(found) do
    if not badges[path] then changed[#changed + 1] = path end
    fresh[path] = badge(status)
  end
  badges = fresh
  if #changed > 0 then
    table.sort(changed)
    tell(changed)
  end
end

---Take the result of the scan of `root`.
---@param root string
---@param result Media.Hub.Transcripts.Result
local function adopt(root, result)
  local scan = scans[root]
  if not scan then return end
  scan.cancel = nil
  scan.result = result
  last = result
  -- what was looked at file by file below this root is the scan's to say from now on
  for path in pairs(loose) do
    if below(path, root) then loose[path] = nil end
  end
  rebuild()
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

---The folders to scan: the roots the listening trees show (`ctx.roots()`), each once and sorted. A
---tree that hands no context (an older filetree.nvim) stands for the working directory, and so does
---nobody listening at all (a caller that forces a scan).
---@return string[] roots
---@return boolean cwd  Whether the working directory is among them because somebody could not say.
function M.roots()
  local norm = require("media.hub.transcripts").norm
  local seen, out = {}, {}
  ---@param root any
  local function add(root)
    if type(root) ~= "string" or root == "" then return end
    root = norm(root)
    if seen[root] then return end
    seen[root] = true
    out[#out + 1] = root
  end
  local cwd = next(listeners) == nil
  for _, listener in pairs(listeners) do
    local ask = type(listener.ctx) == "table" and listener.ctx.roots or nil
    local ok, roots = false, nil
    if type(ask) == "function" then
      ok, roots = pcall(ask)
    end
    if ok and type(roots) == "table" then
      for _, root in ipairs(roots) do
        add(root)
      end
    else
      cwd = true
    end
  end
  if cwd then add(vim.fn.getcwd()) end
  table.sort(out)
  return out, cwd
end

---Start the scan of `root`, in place of one that is still on its way there.
---@param root string
local function start(root)
  local scan = scans[root] or {}
  scans[root] = scan
  if scan.cancel then scan.cancel() end
  scan.cancel = nil
  scan.token = nil
  if M.too_wide(root) then
    adopt(root, { root = root, transcripts = {}, partial = true, entries = 0 })
    return
  end
  -- a stand-in may answer before it returns, and one that was replaced may answer all the same
  local token = {}
  scan.token = token
  local cancel = require("media.hub.transcripts").scan(root, function(result)
    if scans[root] ~= scan or scan.token ~= token then return end
    scan.token = nil
    adopt(root, result)
  end)
  if scan.token == token then scan.cancel = cancel end
end

---Give up the scans of roots no tree shows any more. Returns whether one went.
---@param wanted string[]
---@return boolean
local function drop_unwanted(wanted)
  local keep, dropped = {}, false
  for _, root in ipairs(wanted) do
    keep[root] = true
  end
  for root, scan in pairs(scans) do
    if not keep[root] then
      if scan.cancel then scan.cancel() end
      scans[root] = nil
      dropped = true
    end
  end
  return dropped
end

---Scan every root again, in the background (see `roots`). Without a listening tree nothing happens
---unless `force` is set (a caller that wants the table for itself).
---@param force? boolean
function M.rescan(force)
  if not force and next(listeners) == nil then return end
  local wanted = M.roots()
  local dropped = drop_unwanted(wanted)
  for _, root in ipairs(wanted) do
    start(root)
  end
  if dropped then rebuild() end
end

---Follow the roots of the trees: scan a root that is new, forget one that is gone, and leave the
---others alone (`User FiletreeRoots`, and a tree that comes or goes).
function M.sync()
  if next(listeners) == nil then return end
  local wanted = M.roots()
  local dropped = drop_unwanted(wanted)
  for _, root in ipairs(wanted) do
    if not scans[root] then start(root) end
  end
  if dropped then rebuild() end
end

---Look at one media file again (its transcript was written or removed), without a scan. A file
---outside what the scans cover gets its badge all the same: the tree only asks for what it shows.
---@param path string
function M.refresh(path)
  if type(path) ~= "string" or path == "" or next(listeners) == nil then return end
  local transcripts = require("media.hub.transcripts")
  path = transcripts.norm(path)
  local status = transcripts.status(path)
  local old = badges[path]
  if (old and old.status) == status then return end
  local covered, running = false, false
  for root, scan in pairs(scans) do
    if scan.cancel then running = true end
    if scan.result and below(path, root) then
      scan.result.transcripts[path] = status
      covered = true
    end
  end
  loose[path] = not covered and status or nil
  badges[path] = status and badge(status) or nil
  tell({ path })
  -- A scan that is on its way may have read the folder before the file changed, and its answer
  -- replaces what it found there before: look once more when it is through.
  if running then M.rescan_soon() end
end

---At most this many entries of one folder are looked at when the watcher reports it.
M.MAX_DIR_ENTRIES = 5000

---Look at the media files of the folders the tree's watcher reported (`User FiletreeFsChanged`)
---again, one by one through `refresh`: a transcript another program wrote or deleted shows without a
---scan of the roots. A folder that is gone or cannot be read is skipped.
---@param dirs any  `data.dirs` of the event: a list of folders
function M.refresh_dirs(dirs)
  if type(dirs) ~= "table" or next(listeners) == nil then return end
  local is_media = require("media.formats").is_media
  for _, dir in ipairs(dirs) do
    if type(dir) == "string" and dir ~= "" then
      local handle = vim.uv.fs_scandir(dir)
      local seen = 0
      while handle and seen < M.MAX_DIR_ENTRIES do
        local name, kind = vim.uv.fs_scandir_next(handle)
        if not name then break end
        seen = seen + 1
        if (kind == "file" or kind == "link") and is_media(name) then
          M.refresh(dir .. "/" .. name)
        end
      end
    end
  end
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
    pattern = "FiletreeFsChanged",
    callback = function(args)
      local data = args.data
      if type(data) == "table" then M.refresh_dirs(data.dirs) end
    end,
  })
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "MediaTranscriptWritten",
    callback = function(args)
      local data = args.data
      if type(data) == "table" then M.refresh(data.path) end
    end,
  })
  -- a tree was made, rooted elsewhere or given up
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "FiletreeRoots",
    callback = function()
      M.sync()
    end,
  })
  -- the working directory is a root only for a tree that cannot say which one it shows
  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      local _, cwd = M.roots()
      if cwd then M.rescan_soon() end
    end,
  })
end

local function stop_listening()
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  if timer then
    timer:stop()
    if not timer:is_closing() then timer:close() end
    timer = nil
  end
  for _, scan in pairs(scans) do
    if scan.cancel then scan.cancel() end
  end
  scans = {}
end

---What the last scan that ended found, or with `root` what the scan of that root found; nil before
---it ended (for `:checkhealth` and the specs).
---@param root? string
---@return Media.Hub.Transcripts.Result|nil
function M.last_scan(root)
  if root == nil then return last end
  local scan = scans[require("media.hub.transcripts").norm(root)]
  return scan and scan.result or nil
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

-- ── the actions ──────────────────────────────────────────────────────────────

---@param message string
---@param level? integer
local function say(message, level)
  require("media.util.notify").notify(message, level)
end

---The files among `nodes` that `accepts` takes, each once and in the order of the nodes. A tree
---checks an action against the node under the cursor and hands over the whole selection, so what
---does not belong is left out here.
---@param nodes table[]|nil
---@param accepts fun(path: string): boolean
---@return string[]
local function files_of(nodes, accepts)
  local out, seen = {}, {}
  for _, node in ipairs(type(nodes) == "table" and nodes or {}) do
    local path = type(node) == "table" and node.path or nil
    if
      type(path) == "string"
      and path ~= ""
      and node.kind ~= "dir"
      and not seen[path]
      and accepts(path)
    then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  return out
end

---The one file an action that is no batch runs on: the first. Playing twelve recordings is twelve
---players, so with several marked the person is told which one it is.
---@param paths string[]
---@param verb string  "playing" | "rendering the contact sheet of"
---@return string|nil
local function first_of(paths, verb)
  if #paths > 1 then
    say(
      ("%d files are marked; %s the first only: %s"):format(#paths, verb, paths[1]),
      vim.log.levels.WARN
    )
  end
  return paths[1]
end

---Transcribe media files, each into the sidecar next to it (`<file>.transcript.md`), one after
---another under one progress handle. It is the dashboard's "Transcribe → sidecar" with the files
---chosen in the tree: without an engine nothing starts, and the reason is said the way the
---dashboard says it. The badge of each file follows through `User MediaTranscriptWritten`.
---@param paths string|string[]
---@return boolean started
function M.transcribe(paths)
  if type(paths) == "string" then paths = { paths } end
  local kinds = require("media.hub.kinds")
  local formats = require("media.formats")
  ---@type Media.Hub.Entry[]
  local entries = {}
  for _, path in ipairs(type(paths) == "table" and paths or {}) do
    if type(path) == "string" and formats.is_media(path) then
      entries[#entries + 1] = {
        path = path,
        name = vim.fn.fnamemodify(path, ":t"),
        kind = kinds.of(path),
        status = "missing",
      }
    end
  end
  if #entries == 0 then return false end

  local actions = require("media.hub.actions")
  ---@type Media.Hub.Action|nil
  local action
  -- audio and video share one table
  for _, candidate in ipairs(actions.list("audio")) do
    if candidate.id == "transcribe_sidecar" then action = candidate end
  end
  if not action or not actions.batchable(action) then return false end
  -- the worst answer counts: twelve files are not ready because the first one is
  ---@type Media.Hub.Tool
  local tool = { ok = true, tool = "" }
  for _, entry in ipairs(entries) do
    local one = actions.availability(action, entry.kind)
    if not one.ok then
      tool = one
      break
    end
  end
  require("media.hub.dashboard").pick(entries, action, tool, nil)
  return tool.ok == true
end

---Hand a media file to a player: what `:Media play <path>` does.
---@param path string
function M.play(path)
  require("media.bindings.usrcmds").run("play", path)
end

---Show the contact sheet of a video: what `:Media sheet <path>` does. Without ffmpeg nothing is
---started and one line says what is missing.
---@param path string
---@return boolean started
function M.sheet(path)
  if not require("media.core.bin").find("ffmpeg") then
    say("ffmpeg not found (install it, or set `bin.ffmpeg`)", vim.log.levels.WARN)
    return false
  end
  require("media.bindings.usrcmds").run("sheet", path)
  return true
end

---What the tree is told about the three actions: the name, the line a menu shows, where it applies
---and what it does with the selection.
---@return table[]
local function action_specs()
  local formats = require("media.formats")
  ---@param node { path?: string }
  local function on_media(node)
    return formats.is_media(node.path)
  end
  ---@param node { path?: string }
  local function on_video(node)
    return formats.is_video(node.path)
  end
  return {
    {
      id = "transcribe",
      name = M.TRANSCRIBE,
      desc = "Transcribe this recording into a file next to it (media.nvim)",
      when = on_media,
      -- writes `<file>.transcript.md`
      mutates = true,
      run = function(nodes)
        M.transcribe(files_of(nodes, formats.is_media))
      end,
    },
    {
      id = "play",
      name = M.PLAY,
      desc = "Play this recording in a player (media.nvim)",
      when = on_media,
      mutates = false,
      run = function(nodes)
        local path = first_of(files_of(nodes, formats.is_media), "playing")
        if path then M.play(path) end
      end,
    },
    {
      id = "sheet",
      name = M.SHEET,
      desc = "Show the contact sheet of this video (media.nvim)",
      when = on_video,
      mutates = false,
      run = function(nodes)
        local path = first_of(files_of(nodes, formats.is_video), "rendering the contact sheet of")
        if path then M.sheet(path) end
      end,
    },
  }
end

-- ── registering ──────────────────────────────────────────────────────────────

---Register the decorator and, where the registry takes them, the previewer and the actions. Without
---`lib.nvim.tree.registry` (an older lib.nvim) nothing happens.
---@param opts? Media.Opts.Tree  `badge`: the text of the badge; `preview = false`: no previewer; `actions = false`: no actions; `keys`: a key per action.
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
    -- `ctx` (filetree.nvim hands it since `User FiletreeRoots` exists): where to ask for the roots
    subscribe = function(emit, ctx)
      next_listener = next_listener + 1
      local id = next_listener
      local first = next(listeners) == nil
      listeners[id] = { emit = emit, ctx = type(ctx) == "table" and ctx or nil }
      if first then start_listening() end
      M.sync()
      return function()
        listeners[id] = nil
        if next(listeners) == nil then
          stop_listening()
        else
          M.sync()
        end
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
  if opts.actions ~= false and type(registry.action) == "function" then
    local keys = type(opts.keys) == "table" and opts.keys or {}
    for _, spec in ipairs(action_specs()) do
      local key = keys[spec.id]
      unregister_actions[#unregister_actions + 1] = registry.action({
        name = spec.name,
        desc = spec.desc,
        -- a key only where one is configured: the actions are in the menu of the tree
        key = (type(key) == "string" or type(key) == "table") and key or nil,
        needs = { "file" },
        when = spec.when,
        mutates = spec.mutates,
        run = spec.run,
      })
    end
  end
  return true
end

---Take the entries out again and stop everything behind them.
function M.unregister()
  for _, remove in ipairs(unregister_actions) do
    remove()
  end
  unregister_actions = {}
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
  loose = {}
  last = nil
end

return M

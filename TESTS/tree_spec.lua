-- media.integrations.tree and media.hub.transcripts: the `transcript` decorator a tree view reads, the
-- background scan behind it, and the preview of a media node.
--
-- The scan gets a real folder in `tempname()`: "stale" is a relationship of two timestamps, and a
-- stubbed fs_stat would only show that the stub was written the way the code reads it. The preview
-- gets stand-ins for everything that needs a program: `bin.find`, `frame.frame` and
-- `waveform.waveform` are replaced by recorders, and `vim.system` and the two ways to start a player
-- by counters that have to stay at zero.
---@diagnostic disable: need-check-nil, missing-fields, param-type-mismatch, duplicate-set-field

---@param H table
return function(H)
  local uv = vim.uv or vim.loop
  local transcripts = require("media.hub.transcripts")
  local tree = require("media.integrations.tree")
  local registry = require("lib.nvim.tree.registry")

  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root, "p")
  -- The folder as the editor names it once it is the working directory: on macOS the temp folder
  -- lies behind a link (/var -> /private/var), and the scan starts from `getcwd()`.
  root = transcripts.norm(uv.fs_realpath(root) or root)
  for _, dir in ipairs({ "talks", "node_modules/pkg", ".git", "skipme" }) do
    vim.fn.mkdir(root .. "/" .. dir, "p")
  end

  ---@param rel string
  ---@param when integer|nil  # mtime to force, in seconds
  local function write(rel, when)
    local fd = assert(io.open(root .. "/" .. rel, "w"))
    fd:write("x")
    fd:close()
    if when then uv.fs_utime(root .. "/" .. rel, when, when) end
  end

  ---The found transcripts as sorted "rel status" lines.
  ---@param found table<string, string>
  ---@return string
  local function rels(found)
    local out = {}
    for path, status in pairs(found) do
      out[#out + 1] = path:sub(#root + 2) .. " " .. status
    end
    table.sort(out)
    return table.concat(out, "\n")
  end

  ---@type string|nil, string|nil  a second project, and a link to it
  local other, link = nil, nil
  local cwd = vim.fn.getcwd()
  local debounce = tree.DEBOUNCE_MS
  local config = require("media.config")
  local bin = require("media.core.bin")
  local frame = require("media.core.frame")
  local waveform = require("media.core.waveform")
  local probe = require("media.core.probe")
  local play = require("media.core.play")
  local player = require("media.core.player")
  local real = {
    find = bin.find,
    frame = frame.frame,
    waveform = waveform.waveform,
    cached = probe.cached,
    probe = probe.probe,
    play = play.play,
    player_start = player.start,
    system = vim.system,
    scan = transcripts.scan,
    scan_sync = transcripts.scan_sync,
    previewer = registry.previewer,
  }

  local ok, err = pcall(function()
    local now = os.time()
    write("talks/standup.mp4", now - 1000)
    write("talks/retro.mp4", now - 1000)
    write("talks/retro.mp4.transcript.md", now - 500) -- newer than the source: ok
    write("talks/keynote.mp4", now - 100)
    write("talks/keynote.mp4.transcript.md", now - 900) -- older: stale
    write("notes.m4a", now - 1000)
    write("notes.m4a.transcript.md", now - 500)
    write("gone.mp4.transcript.md", now - 500) -- the media file is not there
    write("readme.md.transcript.md", now - 500) -- no media file by its name
    write("readme.md", now - 1000)
    write("node_modules/pkg/a.mp4", now - 1000)
    write("node_modules/pkg/a.mp4.transcript.md", now - 500)
    write(".git/b.mp4", now - 1000)
    write(".git/b.mp4.transcript.md", now - 500)
    write("skipme/c.mp4", now - 1000)
    write("skipme/c.mp4.transcript.md", now - 500)

    -- ── the index ───────────────────────────────────────────────────────────
    H.eq(transcripts.source_name("talk.mp4.transcript.md"), "talk.mp4")
    H.eq(transcripts.source_name("talk.MP3.transcript.md"), "talk.MP3", "the extension in any case")
    H.eq(transcripts.source_name("notes.md.transcript.md"), nil, "a sidecar of no media file")
    H.eq(transcripts.source_name("talk.mp4"), nil)
    H.eq(transcripts.source_name(".transcript.md"), nil)
    H.eq(transcripts.norm("c:\\a\\b\\"), "C:/a/b", "the spelling a tree uses for its keys")

    config.setup({ keymaps = false, tree = false, hub = { exclude = { "skipme" } } })
    local result = transcripts.scan_sync(root)
    H.eq(
      rels(result.transcripts),
      "notes.m4a ok\ntalks/keynote.mp4 stale\ntalks/retro.mp4 ok",
      "the media files with a sidecar; nothing below .git, node_modules or an excluded folder"
    )
    H.eq(result.partial, false)
    H.eq(result.root, root)
    H.eq(transcripts.status(root .. "/talks/retro.mp4"), "ok")
    H.eq(transcripts.status(root .. "/talks/keynote.mp4"), "stale", "the file changed after it")
    H.eq(transcripts.status(root .. "/talks/standup.mp4"), nil, "no sidecar")
    H.eq(transcripts.status(root .. "/gone.mp4"), nil, "a sidecar without its file")

    -- a walk that was cut short keeps what it saw: a found sidecar is still a found sidecar
    config.setup({
      keymaps = false,
      tree = false,
      hub = { exclude = { "skipme" }, max_entries = 3 },
    })
    local cut = transcripts.scan_sync(root)
    H.eq(cut.partial, true)
    H.ok(cut.entries <= 4, "the walk stops at hub.max_entries")
    config.setup({ keymaps = false, tree = false, hub = { exclude = { "skipme" } } })

    -- in the background: the answer comes later, and a cancelled scan never answers
    local async, cancelled_answer = nil, false
    transcripts.scan(root, function(r)
      async = r
    end)
    H.eq(async, nil, "scan() returns before it has read anything")
    local cancel = transcripts.scan(root, function()
      cancelled_answer = true
    end)
    cancel()
    H.ok(
      vim.wait(5000, function()
        return async ~= nil
      end, 5),
      "the background scan ends"
    )
    H.eq(rels(async.transcripts), rels(result.transcripts), "with the answer of the scan in one go")
    vim.wait(50)
    H.falsy(cancelled_answer, "a cancelled scan never calls back")

    -- ── the decorator ───────────────────────────────────────────────────────
    H.ok(tree.too_wide(uv.os_homedir()), "the home folder is no project")
    H.ok(tree.too_wide("C:\\") and tree.too_wide("/"), "nor is the top of a drive")
    H.falsy(tree.too_wide(root))

    vim.api.nvim_set_current_dir(root)
    tree.DEBOUNCE_MS = 10
    local scans = 0
    transcripts.scan = function(...)
      scans = scans + 1
      return real.scan(...)
    end

    H.eq(tree.register(), true)
    local entry = registry.get("decorator", "transcript")
    H.ok(entry, "the decorator is at lib.nvim's registry")
    H.eq(entry.key, "path")
    H.eq(entry.slot, "badge")
    H.eq(entry.get(root .. "/talks/retro.mp4"), nil, "registering scans nothing")
    H.eq(scans, 0)
    H.eq(tree.last_scan(), nil)
    tree.rescan()
    H.eq(scans, 0, "without a listening tree a rescan does nothing")

    local emitted = {}
    local unsubscribe = entry.subscribe(function(keys)
      emitted[#emitted + 1] = keys
    end)
    H.eq(scans, 1, "the first tree that subscribes starts the scan")
    H.ok(
      vim.wait(5000, function()
        return tree.last_scan() ~= nil
      end, 5),
      "the scan of the working directory ends"
    )
    H.eq(
      table.concat(emitted[1] or {}, "\n"),
      table.concat({
        root .. "/notes.m4a",
        root .. "/talks/keynote.mp4",
        root .. "/talks/retro.mp4",
      }, "\n"),
      "the tree is told which paths to draw again"
    )

    -- `get` is a table lookup: no call into the file layer while the tree draws
    local touched = 0
    local fs_stat, fs_scandir = uv.fs_stat, uv.fs_scandir
    uv.fs_stat = function(...)
      touched = touched + 1
      return fs_stat(...)
    end
    uv.fs_scandir = function(...)
      touched = touched + 1
      return fs_scandir(...)
    end
    local fresh = entry.get(root .. "/talks/retro.mp4")
    local stale = entry.get(root .. "/talks/keynote.mp4")
    local none = entry.get(root .. "/talks/standup.mp4")
    local every = entry.all()
    uv.fs_stat, uv.fs_scandir = fs_stat, fs_scandir
    H.eq(touched, 0, "get() and all() read no file and no folder")
    H.eq(fresh.text, "transcript")
    H.eq(fresh.status, "ok")
    H.eq(stale.status, "stale")
    H.ok(fresh.hl ~= stale.hl, "a transcript older than its file looks different")
    H.eq(none, nil, "a media file without a transcript has no badge")
    H.eq(every[root .. "/notes.m4a"].status, "ok")

    -- a transcript media.nvim wrote: that one file is looked at, no scan
    local output = require("media.output")
    local wrote = output.deliver(root .. "/talks/standup.mp4", {
      engine = "whisper_cpp",
      lang = "en",
      segments = { { s = 0, e = 1, text = "Hello" } },
      text = "Hello",
    }, "sidecar")
    H.eq(wrote, true)
    H.eq(entry.get(root .. "/talks/standup.mp4").status, "ok", "the badge is there at once")
    H.eq(emitted[#emitted][1], root .. "/talks/standup.mp4", "and the tree is told about that path")
    H.eq(#emitted[#emitted], 1)
    H.eq(scans, 1, "without another scan")
    local told = #emitted
    tree.refresh(root .. "/talks/standup.mp4")
    H.eq(#emitted, told, "nothing changed, nothing is said")

    -- a file operation of a tree: one scan a moment later, for however many came together
    uv.fs_unlink(root .. "/talks/retro.mp4.transcript.md")
    vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeChanged", modeline = false })
    vim.api.nvim_exec_autocmds("User", { pattern = "FileopsChanged", modeline = false })
    H.ok(
      vim.wait(5000, function()
        return entry.get(root .. "/talks/retro.mp4") == nil
      end, 5),
      "a removed transcript takes the badge away"
    )
    H.eq(scans, 2, "two events, one scan")
    H.eq(emitted[#emitted][1], root .. "/talks/retro.mp4")

    -- the last tree that leaves takes the autocommands along
    unsubscribe()
    H.eq(pcall(vim.api.nvim_get_autocmds, { group = "media.tree.transcripts" }), false)
    vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeChanged", modeline = false })
    vim.wait(60)
    H.eq(scans, 2, "nobody listens, nothing is scanned")

    -- the text of the badge is an option
    tree.register({ badge = "txt" })
    entry = registry.get("decorator", "transcript")
    local leave = entry.subscribe(function() end)
    vim.wait(5000, function()
      return tree.last_scan() ~= nil
    end, 5)
    H.eq(entry.get(root .. "/notes.m4a").text, "txt")

    -- A transcript written while a scan is on its way: that scan may have read the folder before,
    -- and its answer replaces the table. So another scan follows it.
    local asked, pending = 0, nil
    transcripts.scan = function(_, on_done)
      asked = asked + 1
      pending = on_done
      return function() end
    end
    tree.rescan()
    H.eq(asked, 1, "a scan is on its way")
    write("talks/late.mp4", now - 1000)
    write("talks/late.mp4.transcript.md", now - 500)
    tree.refresh(root .. "/talks/late.mp4")
    H.eq(entry.get(root .. "/talks/late.mp4").status, "ok")
    -- the answer of the scan that had read `talks` before the file was there
    local before = real.scan_sync(root)
    before.transcripts[root .. "/talks/late.mp4"] = nil
    pending(before)
    H.ok(
      vim.wait(2000, function()
        return asked == 2
      end, 5),
      "the scan that was on its way is followed by another"
    )
    pending(real.scan_sync(root))
    H.eq(entry.get(root .. "/talks/late.mp4").status, "ok", "which finds the transcript")
    leave()
    tree.unregister()
    H.eq(registry.get("decorator", "transcript"), nil, "unregister() takes the entry out")
    H.eq(tree.last_scan(), nil)

    -- ── the roots of the trees ──────────────────────────────────────────────
    -- A tree says which roots it shows (`ctx.roots()`), and the scan follows them: the working
    -- directory (still `root`) is not looked at unless a tree shows it.
    local scanned = {}
    transcripts.scan = function(dir, ...)
      scanned[#scanned + 1] = dir
      return real.scan(dir, ...)
    end
    write("talks/retro.mp4.transcript.md", now - 500)
    other = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(other .. "/clips", "p")
    for _, name in ipairs({ "clips/demo.mp4", "clips/demo.mp4.transcript.md" }) do
      local fd = assert(io.open(other .. "/" .. name, "w"))
      fd:write("x")
      fd:close()
    end
    other = transcripts.norm(other)
    local showing = { other }
    local ctx = {
      roots = function()
        return showing
      end,
    }
    local function roots_changed()
      vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeRoots", modeline = false })
    end
    ---@param dir string
    local function scan_ended(dir)
      return vim.wait(5000, function()
        return tree.last_scan(dir) ~= nil
      end, 5)
    end

    H.eq(tree.register(), true)
    entry = registry.get("decorator", "transcript")
    local named = {}
    local quit = entry.subscribe(function(keys)
      for _, key in ipairs(keys or {}) do
        named[#named + 1] = key
      end
    end, ctx)
    H.eq(
      table.concat(scanned, "\n"),
      other,
      "the root of the tree is scanned, not the working directory"
    )
    H.ok(scan_ended(other), "the scan of the root ends")
    H.eq(
      entry.get(other .. "/clips/demo.mp4").status,
      "ok",
      "a tree rooted outside the working directory shows the badge"
    )
    H.eq(entry.get(root .. "/notes.m4a"), nil, "what no tree shows has none")
    H.eq(table.concat(tree.roots(), "\n"), other)

    -- another root comes: that one is scanned, the first one is left alone
    showing = { other, root }
    roots_changed()
    H.eq(#scanned, 2, "one scan for the root that is new")
    H.eq(scanned[2], root)
    H.ok(scan_ended(root))
    H.eq(entry.get(root .. "/notes.m4a").status, "ok")
    H.eq(entry.get(other .. "/clips/demo.mp4").status, "ok", "the badges of the first root stay")
    roots_changed()
    H.eq(#scanned, 2, "the same roots again: nothing is scanned")

    -- with trees that say their roots the working directory is nobody's business
    vim.api.nvim_exec_autocmds("DirChanged", { pattern = "global", modeline = false })
    vim.wait(60)
    H.eq(#scanned, 2, ":cd scans nothing")

    -- a file operation: every root once
    vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeChanged", modeline = false })
    H.ok(
      vim.wait(2000, function()
        return #scanned == 4
      end, 5),
      "a file operation scans both roots again"
    )
    H.ok(vim.wait(5000, function()
      return tree.last_scan(root) ~= nil and tree.last_scan(other) ~= nil
    end, 5))

    -- a root no tree shows any more: its badges go, without a scan
    named = {}
    showing = { root }
    roots_changed()
    H.eq(
      entry.get(other .. "/clips/demo.mp4"),
      nil,
      "the badges of a root that is gone are forgotten"
    )
    H.eq(table.concat(named, "\n"), other .. "/clips/demo.mp4", "and the tree is told")
    H.eq(tree.last_scan(other), nil)
    H.eq(#scanned, 4)

    -- the home folder as a root stays unscanned
    showing = { root, uv.os_homedir() }
    roots_changed()
    H.eq(#scanned, 4, "the home folder is not walked")
    H.eq(tree.last_scan(uv.os_homedir()).partial, true)

    -- A root behind a link: scanned through the link, the badges in the spelling the tree shows.
    link = transcripts.norm(vim.fs.normalize(vim.fn.tempname()))
    local linked = uv.fs_symlink(other, link, { dir = true, junction = true })
    if linked then
      showing = { link }
      roots_changed()
      H.ok(scan_ended(link), "the scan through the link ends")
      H.eq(entry.get(link .. "/clips/demo.mp4").status, "ok", "the badge by the name the tree uses")
      H.eq(entry.get(other .. "/clips/demo.mp4"), nil, "not by the name the link resolves to")
    end

    -- a second tree that hands no context (an older filetree.nvim) stands for the working directory
    showing = { other }
    roots_changed()
    local before_old = #scanned
    local quit_old = entry.subscribe(function() end)
    H.eq(#scanned, before_old + 1, "the tree without a context adds one scan")
    H.eq(scanned[#scanned], root, "of the working directory")
    local both = { other, root }
    table.sort(both)
    H.eq(table.concat(tree.roots(), "\n"), table.concat(both, "\n"), "next to the other root")
    vim.api.nvim_exec_autocmds("DirChanged", { pattern = "global", modeline = false })
    H.ok(
      vim.wait(2000, function()
        return #scanned == before_old + 3
      end, 5),
      "and :cd scans again while it listens"
    )
    quit_old()
    H.eq(tree.last_scan(root), nil, "it leaves: the working directory is no root any more")
    quit()
    tree.unregister()

    -- a context that raises or answers nonsense is a tree that cannot say: the working directory
    tree.register()
    entry = registry.get("decorator", "transcript")
    scanned = {}
    quit = entry.subscribe(function() end, {
      roots = function()
        error("no roots today")
      end,
    })
    H.eq(table.concat(scanned, "\n"), root)
    quit()
    tree.unregister()
    transcripts.scan = real.scan

    -- ── setup() ─────────────────────────────────────────────────────────────
    local _, problems = config.validate({ tree = "yes" })
    H.eq(problems[1], "tree must be boolean or table, got string")
    _, problems = config.validate({ tree = { badge = 3, preview = "no" } })
    H.eq(#problems, 2, "the two keys of the table are typed")
    require("media").setup({ keymaps = false })
    H.ok(registry.get("decorator", "transcript"), "setup() registers the decorator by default")
    require("media").setup({ keymaps = false, tree = false })
    H.eq(registry.get("decorator", "transcript"), nil, "tree = false registers nothing")

    -- ── the preview ─────────────────────────────────────────────────────────
    H.eq(tree.previews({ path = "/v/talk.mp4" }), true)
    H.eq(tree.previews({ path = "/v/song.MP3" }), true)
    H.eq(tree.previews({ path = "/v/notes.txt" }), false)
    H.eq(tree.previews({ path = "/v/talk.mp4.transcript.md" }), false)
    H.eq(tree.previews({ id = "group" }), false, "a node without a path")
    H.eq(tree.previews(nil), false)

    local calls, spawned, played = {}, 0, 0
    local has_ffmpeg = true
    ---@type table<string, { png?: string, err?: string, hold?: boolean }>
    local renders = {}
    bin.find = function(name)
      if name == "ffmpeg" and not has_ffmpeg then return nil end
      return name
    end
    local dropped = {}
    ---@param kind string
    local function renderer(kind)
      return function(path, _, callback)
        calls[#calls + 1] = kind .. " " .. path
        local answer = renders[kind] or {}
        -- `hold`: a render that is still at work
        if not answer.hold then
          vim.schedule(function()
            callback(answer.png, answer.err)
          end)
        end
        return {
          cancel = function()
            dropped[#dropped + 1] = kind
          end,
        }
      end
    end
    frame.frame = renderer("frame")
    waveform.waveform = renderer("waveform")
    probe.cached = function()
      return nil
    end
    play.play = function()
      played = played + 1
    end
    player.start = function()
      played = played + 1
    end
    vim.system = function()
      spawned = spawned + 1
      error("the preview must not start a process in this spec")
    end

    ---Ask for the preview of `path` and wait for the answer.
    ---@param path string
    ---@return table|nil answer
    ---@return boolean returned_first
    local function preview(path)
      local answer
      tree.preview({ path = path }, { mode = "float" }, function(got)
        answer = got
      end)
      local returned_first = answer == nil
      vim.wait(2000, function()
        return answer ~= nil
      end, 5)
      return answer, returned_first
    end

    renders.frame = { png = "/cache/frame.png" }
    renders.waveform = { png = "/cache/wave.png" }
    local shown, early = preview("/v/talk.mp4")
    H.eq(early, true, "preview() returns before the still is there")
    H.eq(shown.image, "/cache/frame.png", "a video shows one still")
    H.eq(shown.note, nil)
    H.eq(table.concat(calls, "\n"), "frame /v/talk.mp4")

    calls = {}
    shown = preview("/v/song.mp3")
    H.eq(shown.image, "/cache/wave.png", "an audio file shows its waveform")
    H.eq(table.concat(calls, "\n"), "waveform /v/song.mp3")

    -- a container that usually holds a film and here holds sound only
    calls = {}
    renders.frame = { err = frame.NO_PICTURE }
    shown = preview("/v/podcast.mkv")
    H.eq(shown.image, "/cache/wave.png")
    H.eq(table.concat(calls, "\n"), "frame /v/podcast.mkv\nwaveform /v/podcast.mkv")

    -- what is known about the file goes along as a title
    renders.frame = { png = "/cache/frame.png" }
    probe.cached = function()
      return { width = 1920, height = 1080, duration = 61, video_codec = "h264" }
    end
    shown = preview("/v/talk.mp4")
    H.eq(shown.title, "1920x1080 · 1:01 · h264")
    probe.cached = function()
      return nil
    end

    -- a render that failed is one line, whatever ffmpeg printed
    renders.frame = { err = "Invalid data found when processing input\nmore\nand more" }
    shown = preview("/v/broken.mp4")
    H.eq(shown.image, nil)
    H.eq(shown.note, "media.nvim: Invalid data found when processing input")

    -- without ffmpeg the preview says what is missing, and asks no renderer
    calls = {}
    has_ffmpeg = false
    shown = preview("/v/talk.mp4")
    H.match(shown.note, "ffmpeg not found", "one line that names the program")
    H.falsy(shown.note:find("\n", 1, true))
    H.eq(#calls, 0)
    has_ffmpeg = true

    -- While the preview follows the cursor nothing is rendered: the record of the file, as lines.
    calls = {}
    local record = {
      path = "/v/talk.mp4",
      container = "mp4",
      duration = 61,
      has_video = true,
      video_codec = "h264",
      width = 1920,
      height = 1080,
    }
    probe.probe = function(path, callback)
      calls[#calls + 1] = "probe " .. path
      vim.schedule(function()
        if path == "/v/broken.mp4" then
          callback(nil, "ffprobe not found\nand more")
        else
          callback(record, nil)
        end
      end)
    end
    local following
    tree.preview({ path = "/v/talk.mp4" }, { mode = "float", trigger = "cursor" }, function(got)
      following = got
    end)
    vim.wait(2000, function()
      return following ~= nil
    end, 5)
    H.eq(table.concat(calls, "\n"), "probe /v/talk.mp4", "ffprobe is asked, no renderer")
    H.eq(following.image, nil, "no picture for a node the cursor only passes")
    H.eq(following.lines[1], "talk.mp4")
    H.ok(table.concat(following.lines, "\n"):find("1920x1080", 1, true), "the record of the file")
    H.eq(following.title, "1920x1080 · 1:01 · h264")
    following = nil
    tree.preview({ path = "/v/broken.mp4" }, { trigger = "cursor" }, function(got)
      following = got
    end)
    vim.wait(2000, function()
      return following ~= nil
    end, 5)
    H.eq(following.note, "media.nvim: ffprobe not found", "what is missing, in one line")
    probe.probe = real.probe

    -- a node the cursor left: the answer is dropped
    renders.frame = { png = "/cache/frame.png" }
    local late = false
    local drop = tree.preview({ path = "/v/talk.mp4" }, nil, function()
      late = true
    end)
    H.eq(#dropped, 0)
    drop()
    vim.wait(60)
    H.falsy(late, "after cancel() done is never called")
    H.eq(table.concat(dropped, " "), "frame", "and the render it waited for is given up")
    renders.frame = { err = frame.NO_PICTURE }
    renders.waveform = { hold = true }
    dropped = {}
    calls = {}
    drop = tree.preview({ path = "/v/podcast.mkv" }, nil, function()
      late = true
    end)
    vim.wait(60, function()
      return #calls > 0 and calls[#calls]:find("waveform", 1, true) ~= nil
    end, 5)
    drop()
    H.eq(dropped[#dropped], "waveform", "the render that is running now, not the first one")
    vim.wait(60)
    H.falsy(late)

    H.eq(spawned, 0, "no process was started")
    H.eq(played, 0, "and no player")

    -- ── the previewer at the registry ───────────────────────────────────────
    -- A registry that takes previewers gets one; an older one gets the decorator alone.
    local given, removed = nil, 0
    registry.previewer = function(spec)
      given = spec
      return function()
        removed = removed + 1
      end
    end
    H.eq(tree.register(), true)
    H.eq(given.name, "media")
    H.eq(given.match, tree.previews)
    H.eq(given.preview, tree.preview)
    tree.unregister()
    H.eq(removed, 1, "unregister() takes the previewer out as well")

    given = nil
    tree.register({ preview = false })
    H.eq(given, nil, "preview = false: the decorator alone")
    H.ok(registry.get("decorator", "transcript"))
    tree.unregister()

    registry.previewer = nil
    H.eq(tree.register(), true, "a registry without previewers still takes the decorator")
    H.ok(registry.get("decorator", "transcript"))
    tree.unregister()
  end)

  bin.find = real.find
  frame.frame = real.frame
  waveform.waveform = real.waveform
  probe.cached = real.cached
  probe.probe = real.probe
  play.play = real.play
  player.start = real.player_start
  vim.system = real.system
  transcripts.scan = real.scan
  registry.previewer = real.previewer
  tree.DEBOUNCE_MS = debounce
  tree.unregister()
  vim.api.nvim_set_current_dir(cwd)
  vim.fn.delete(root, "rf")
  -- the link itself, never what lies behind it
  if link then
    pcall(uv.fs_unlink, link)
    pcall(uv.fs_rmdir, link)
  end
  if other then vim.fn.delete(other, "rf") end
  if not ok then error(err, 0) end
end

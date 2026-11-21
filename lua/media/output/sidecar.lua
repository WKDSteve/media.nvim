---@module 'media.output.sidecar'
---@brief `<file>.transcript.md` — the sidecar convention this ecosystem's
---OCR already established, generalised to any transcript.
---@description
--- Same shape as `images.ocr`'s consumer, `case/ocr.lua`: the suffix is
--- appended to the *full* file name, not swapped for the extension, so
--- `talk.mp4` and `talk.mov` do not collide and a grep hit explains itself —
--- every `*.md`-walking tool picks it up with no changes of its own.
---
--- **Staleness is by mtime, not existence.** A source video edited after its
--- sidecar was written is stale — the same rule `case/ocr.is_stale` applies,
--- for the same reason: a transcript describing an older cut of the file is
--- worse than none once it disagrees with what is actually there.

local M = {}

local SUFFIX = ".transcript.md"

---@param path string
---@return string
function M.path(path)
  return path .. SUFFIX
end

---@param path string
---@return boolean
function M.is_stale(path)
  local uv = vim.uv or vim.loop
  local sidecar = uv.fs_stat(M.path(path))
  if not sidecar then return true end
  local source = uv.fs_stat(path)
  if not source then return false end
  return (source.mtime and source.mtime.sec or 0) > (sidecar.mtime and sidecar.mtime.sec or 0)
end

--- `[HH:MM:SS]` -- the time mark of a segment's start, whole seconds. The shape
--- `:Case log merge` (casedesk) reads a Markdown transcript by, so the spoken
--- sentences land between the log entries at the time they were said.
---@param seconds number|nil
---@return string
function M.mark(seconds)
  local total = math.floor(math.max(0, tonumber(seconds) or 0))
  return ("[%02d:%02d:%02d]"):format(
    math.floor(total / 3600),
    math.floor(total / 60) % 60,
    total % 60
  )
end

--- The body of the sidecar: one line per segment, `[HH:MM:SS] text`. A segment
--- without text is left out; a transcript without any segment keeps its flat
--- text, which is all there is.
---@param transcript Media.Transcript
---@return string
local function body(transcript)
  local segments = require("media.core.segments")
  local lines = {}
  for _, cue in ipairs(segments.cues(transcript.segments)) do
    lines[#lines + 1] = M.mark(cue.s) .. " " .. cue.text:gsub("\n", " ")
  end
  if #lines == 0 then return segments.to_text(transcript.segments or {}) end
  return table.concat(lines, "\n")
end

--- The sidecar document for one transcript.
---
--- Pure, and public, for the same reason `sidecar_content` in `case/ocr.lua`
--- is worth keeping separate from the write: the shape is assertable without
--- touching disk.
---@param path string
---@param transcript Media.Transcript
---@return string
function M.content(path, transcript)
  local name = vim.fn.fnamemodify(path, ":t")
  local by = transcript.model and (transcript.engine .. " (" .. transcript.model .. ")")
    or transcript.engine

  return table.concat({
    ("# Transcript — %s"):format(name),
    "",
    ("> Machine-transcribed with %s on %s. Recognition errors are possible —"):format(
      by,
      os.date("%Y-%m-%d")
    ),
    "> correct this file rather than the source; nothing regenerates it unless",
    "> the media file itself changes.",
    "",
    body(transcript),
    "",
  }, "\n")
end

---@param path string
---@param transcript Media.Transcript
---@return boolean ok
---@return string|nil err
function M.write(path, transcript)
  local sidecar_path = M.path(path)
  local fd, err = io.open(sidecar_path, "w")
  if not fd then return false, err or ("could not open " .. sidecar_path) end
  local wok, werr = fd:write(M.content(path, transcript))
  local cok, cerr = fd:close()
  if not wok then return false, werr or ("could not write " .. sidecar_path) end
  if not cok then return false, cerr or ("could not close " .. sidecar_path) end
  return true, nil
end

return M

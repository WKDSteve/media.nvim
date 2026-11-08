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
vim.notify = function(msg)
  _G.notes[#_G.notes + 1] = tostring(msg)
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

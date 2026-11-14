-- The handle `frame`, `waveform` and `spectrogram` return: after `cancel()` the callback is not called,
-- and a render that waits for a slot is given back to the queue (`media.core.cache.ensure`'s handle).
--
-- Nothing is rendered: `bin.find`, `probe.probe` and `cache.ensure` are stand-ins that answer when the
-- spec tells them to, so these are assertions about who is told what, and when.
---@diagnostic disable: need-check-nil, missing-fields, duplicate-set-field, param-type-mismatch

---@param H table
return function(H)
  local bin = require("media.core.bin")
  local probe = require("media.core.probe")
  local cache = require("media.core.cache")
  local frame = require("media.core.frame")
  local waveform = require("media.core.waveform")
  local real = { find = bin.find, probe = probe.probe, ensure = cache.ensure, file = cache.file }

  local has_ffmpeg = true
  ---@type fun(record: table|nil, err: string|nil)|nil
  local answer_probe = nil
  local ensured, given_up = 0, 0
  ---@type fun(png: string|nil, err: string|nil)|nil
  local answer_render = nil

  bin.find = function(name)
    if not has_ffmpeg then return nil end
    return name
  end
  probe.probe = function(_, callback)
    answer_probe = callback
  end
  cache.file = function()
    return "/cache/out.png", nil
  end
  cache.ensure = function(_, _, callback)
    ensured = ensured + 1
    answer_render = callback
    return {
      cancel = function()
        given_up = given_up + 1
      end,
    }
  end

  local ok, err = pcall(function()
    local record = { has_video = true, has_audio = true, duration = 60 }

    for _, case in ipairs({
      { name = "frame", ask = frame.frame },
      { name = "waveform", ask = waveform.waveform },
      { name = "spectrogram", ask = waveform.spectrogram },
    }) do
      local name = case.name
      ---@type table[]
      local got = {}
      local function callback(png, e)
        got[#got + 1] = { png = png, err = e }
      end

      -- the plain way: the answer of the render reaches the caller
      ensured, given_up = 0, 0
      local handle = case.ask("/v/a.mkv", nil, callback)
      H.eq(type(handle.cancel), "function", name .. " returns a handle")
      answer_probe(record, nil)
      H.eq(ensured, 1, name .. " asks the cache for the render")
      answer_render("/cache/out.png", nil)
      H.eq(#got, 1)
      H.eq(got[1].png, "/cache/out.png")

      -- given up while the render waits: the queue is told, the caller hears nothing
      got = {}
      ensured, given_up = 0, 0
      handle = case.ask("/v/a.mkv", nil, callback)
      answer_probe(record, nil)
      handle.cancel()
      H.eq(given_up, 1, name .. ": cancel() gives the waiting render back")
      H.eq(#got, 0)

      -- given up before the probe answered: nothing is asked of the cache at all
      ensured, given_up = 0, 0
      handle = case.ask("/v/a.mkv", nil, callback)
      handle.cancel()
      answer_probe(record, nil)
      H.eq(ensured, 0, name .. ": a cancelled request starts no render")
      H.eq(#got, 0, name .. ": and calls nobody back")

      -- without ffmpeg the answer is the usual one line, unless nobody waits for it any more
      has_ffmpeg = false
      case.ask("/v/a.mkv", nil, callback)
      vim.wait(200, function()
        return #got > 0
      end, 5)
      H.eq(#got, 1)
      H.match(got[1].err, "ffmpeg not found", name)
      got = {}
      handle = case.ask("/v/a.mkv", nil, callback)
      handle.cancel()
      vim.wait(40)
      H.eq(#got, 0, name .. ": cancelled, the missing program is nobody's news")
      has_ffmpeg = true
    end

    -- the one failure with a next step has a name a caller can compare against
    local said = nil
    frame.frame("/v/sound-only.mkv", nil, function(_, e)
      said = e
    end)
    answer_probe({ has_video = false, has_cover = false, has_audio = true }, nil)
    H.eq(said, frame.NO_PICTURE)
    H.eq(type(frame.NO_PICTURE), "string")
  end)

  bin.find = real.find
  probe.probe = real.probe
  cache.ensure = real.ensure
  cache.file = real.file
  if not ok then error(err, 0) end
end

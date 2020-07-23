-- waveviz
-- view audio file waveforms
-- just one channel right now
--
-- K1: alt
-- K2: center window on cursor
--  alt: toggle recording
-- K3: center cursor in window
--  alt: toggle playback
-- E1: zoom
--  alt: scale amplitude
-- E2: move transport
--  alt: preserve level
-- E3: move cursor
--  alt: playback rate
--
-- call save_buffer(fname)
-- to save buffer contents

loopsize = 0
winstart = 0
winend = 0
winsize = 0
cursor = 1
scale = 20

local recording = false
local playing = false
local interval = 0
local samples = {}

local held_keys = {}
local screen_dirty = true

function update_content()
  softcut.render_buffer(
     1, winstart, winend - winstart, 128,
     function(ch, start, i, s)
       cursor = util.clamp(cursor, 1, #s)
       samples = s
       interval = i
       screen_dirty = true
     end)
end

function delta_zoom(d)
  if d > 0 then
    winsize = math.max(winsize / 2, 1 / 48000)
  elseif d < 0 then
    winsize = math.min(winsize * 2, loopsize)
  end
  local center_sec = winstart + util.round(#samples / 2) * interval
  winstart = util.clamp(center_sec - winsize / 2, 0, loopsize - winsize / 2)
  winend = util.clamp(center_sec + winsize / 2, winsize / 2, loopsize)
  update_content()
end

function delta_window(d)
  if winsize > 0 then
    local delta = d * winsize * 0.1
    winstart = util.clamp(winstart + delta, 0, loopsize - winsize)
    winend = util.clamp(winend + delta, winsize, loopsize)
    winsize = winend - winstart

    update_content()
  end
end

function delta_cursor(d)
  cursor = util.clamp(cursor + d, 1, #samples)
  screen_dirty = true
end

function center_cursor()
  local range = winend - winstart
  local cursor_sec = winstart + (cursor - 1) * interval
  cursor = util.round(#samples / 2)
  winstart = util.clamp(cursor_sec - range / 2, 0, loopsize)
  winend = util.clamp(cursor_sec + range / 2, 0, loopsize)
  winsize = winend - winstart
  update_content()
end

function delta_scale(d)
  scale = util.clamp(scale + d, 1, 128)
  screen_dirty = true
end

function load_sample(f)
  if f == '-' then
    return
  end
  print('load ' .. f)
  local chs, frames, rate = audio.file_info(f)

  -- include fadeout time
  params:set('loopsize', frames / rate)
  winstart = 0
  winend = loopsize
  winsize = winend - winstart
  print('sample is ' .. frames / rate .. ' seconds')

  softcut.buffer_clear()
  softcut.buffer_read_mono(f, 0, 0, -1, 1, 1)
  softcut.loop_end(1, loopsize)
  update_content()
end

function save_buffer(f)
  local fname = paths.audio .. 'waveviz-' .. f .. '.wav'
  softcut.buffer_write_mono(fname, 0, loopsize, 1)
  print('wrote to ' .. fname)
end

phase = 0
function phase_poll(v, p)
  phase = p
  screen_dirty = true
  if recording then
    update_content()
  end
end

function init()
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, 1)
  softcut.event_phase(phase_poll)
  softcut.phase_quant(1, 1 / 15)
  softcut.loop(1, 1)
  softcut.rate(1, 1)
  softcut.position(1, 0)

  audio.level_adc_cut(1)
  softcut.level_input_cut(1, 1, 1.0)
  softcut.pre_level(1, 1)
  softcut.rec_level(1, 0)
  softcut.rec(1, 1)

  params:add_file('sample', 'sample')
  params:set_action('sample', function (f) load_sample(f) end)

  params:add_option('playing', 'playing', {'off', 'on'}, 1)
  params:set_action('playing', function (v)
    print('playing: ' .. v)
    if v == 2 then
      playing = true
      softcut.poll_start_phase()
      softcut.loop_start(1, 0)
      softcut.loop_end(1, loopsize)
      softcut.play(1, 1)
    else
      playing = false
      softcut.play(1, 0)
      softcut.poll_stop_phase()
    end
    screen_dirty = true
  end)

  params:add_option('recording', 'recording', {'off', 'on'}, 1)
  params:set_action('recording', function (v)
    print('recording: ' .. v)
    if v == 2 then
      recording = true
      softcut.pre_level(1, params:get('preserve'))
      softcut.rec_level(1, 1)
    else
      recording = false
      softcut.pre_level(1, 1)
      softcut.rec_level(1, 0)
    end
    screen_dirty = true
  end)

  params:add{
    type='number',
    id='loopsize',
    min=0,
    max=softcut.BUFFER_SIZE,
    action=function(v)
      loopsize = v
    end
  }
  params:add{
     type='number',
     id='rate',
     min=-2,
     max=2,
     default=1,
     action=function(v)
       print('rate:', v)
       softcut.rate(1, v)
       screen_dirty = true
     end
  }
  params:add{
    type='number',
    id='preserve',
    min=0,
    max=1,
    default=1,
    action=function(v)
      softcut.pre_level(1, v)
      screen_dirty = true
    end,
  }

  redraw_timer = metro.init()
  redraw_timer.time = 1 / 15
  redraw_timer.event = function()
    if screen_dirty then
      screen_dirty = false
      redraw()
    end
  end
  redraw_timer:start()
end

function key(n, z)
  held_keys[n] = z == 1

  if z == 1 then
    if n == 2 then
      if held_keys[1] then
        params:set('recording', recording and 1 or 2)
      else
        center_cursor()
      end
    elseif n == 3 then
      if held_keys[1] then
        params:set('playing', playing and 1 or 2)
      else
        cursor = 64
        screen_dirty = true
      end
    end
  end
end

function enc(n, d)
  if n == 1 then
    if held_keys[1] then
      delta_scale(d)
    else
      delta_zoom(d)
    end
  elseif n == 2 then
    if held_keys[1] then
      params:delta('preserve', d * 0.1)
    else
      delta_window(d)
    end
  elseif n == 3 then
    if held_keys[1] then
      params:delta('rate', d * 0.1)
    else
      delta_cursor(d)
    end
  end
end

function redraw()
  screen.clear()

  local x = 0
  local y = 0

  -- scale and window captions
  screen.level(1)
  y = y + 8
  screen.move(x, y)
  screen.text('1.0=' .. string.format('%d', scale) .. 'px')

  x = x + 48
  screen.move(x, y)
  screen.text(string.format('%.5f - %.5f', winstart, winend))

  if #samples > 0 then
    x = 0

    -- waveform + select cursor
    screen.level(4)
    local cursor_sec = winstart + (cursor - 1) * interval
    if #samples < 128 then
      local width = 128 / #samples
      for i,s in ipairs(samples) do
        local height = util.round(32 - s * scale)
        screen.pixel(util.round(i * width), height)
        screen.fill()
      end

      local cursor_pos = util.round(cursor * width) + 1
      screen.move(cursor_pos, 12)
      screen.level(15)
      screen.line_rel(0, 40)
      screen.stroke()

      screen.move(cursor_pos, 48)
      screen.text(string.format('%d', math.floor(winstart * 48000) + cursor - 1))

      screen.move(cursor_pos, 56)
      screen.text(string.format('%.5f', cursor_sec))
    else
      for i,s in ipairs(samples) do
        local height = util.round(math.abs(s) * scale)
        screen.move(x, 32 - height)
        screen.line_rel(0, 2 * height)
        screen.stroke()
        x = x + 1
      end

      screen.move(cursor, 12)
      screen.level(15)
      screen.line_rel(0, 40)
      screen.stroke()

      screen.move(cursor, 56)
      screen.text(string.format('%.5f', cursor_sec))
    end

    -- playhead
    if phase >= winstart and phase <= winend and winend - winstart > 0 then
      local playhead_pos = 1 + util.round(128 * (phase - winstart) / (winend - winstart))

      screen.move(playhead_pos, 12)
      screen.level(6)
      screen.line_rel(0, 40)
      screen.stroke()

      screen.move(playhead_pos, 14)
      screen.text(string.format('%.5f', phase))
    end

    -- sample and value captions
    screen.level(1)

    x = 0
    y = 64
    screen.move(x, y)
    screen.level(1)
    screen.text('t=' .. cursor .. '/' .. #samples)

    if playing then
      local rate = params:get('rate')
      screen.aa(1)
      if rate > 0 then
        screen.level(util.round(15 * rate / 2))
        screen.move(46, 57)
        screen.line_rel(6, 3)
        screen.line_rel(-6, 3)
        screen.close()
        screen.fill()
      elseif rate < 0 then
        screen.level(util.round(15 * -rate / 2))
        screen.move(52, 57)
        screen.line_rel(-6, 3)
        screen.line_rel(6, 3)
        screen.close()
        screen.fill()
      end
      screen.aa(0)
    end

    if recording then
      screen.aa(1)
      screen.circle(60, 60, 3)
      screen.level(15)
      screen.level(util.round(15 * params:get('preserve')))
      screen.fill()
      screen.circle(60, 60, 3)
      screen.level(15)
      screen.stroke()
      screen.aa(0)
    end

    x = 70
    screen.move(x, y)
    screen.level(1)
    screen.text('x[t]=' .. string.format('%.5f', samples[cursor]))
  end

  screen.update()
end

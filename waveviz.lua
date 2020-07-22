-- waveviz
-- view audio file waveforms
-- just one channel right now
--
-- K1: alt
-- K2: center window on cursor
-- K3: center cursor in window
--  alt: copy buffer to cursor
-- E1: zoom
--  alt: scale amplitude
-- E2: move transport
-- E3: move cursor
--
-- call save_buffer(fname)
-- to save buffer contents

clipsize = 0
winstart = 0
winend = 0
winsize = 0
cursor = 1
scale = 20

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
    winsize = math.min(winsize * 2, clipsize)
  end
  local center_sec = winstart + util.round(#samples / 2) * interval
  winstart = util.clamp(center_sec - winsize / 2, 0, clipsize - winsize / 2)
  winend = util.clamp(center_sec + winsize / 2, winsize / 2, clipsize)
  update_content()
end

function delta_window(d)
  if winsize > 0 then
    local delta = d * winsize * 0.1
    winstart = util.clamp(winstart + delta, 0, clipsize - winsize)
    winend = util.clamp(winend + delta, winsize, clipsize)
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
  winstart = util.clamp(cursor_sec - range / 2, 0, clipsize)
  winend = util.clamp(cursor_sec + range / 2, 0, clipsize)
  winsize = winend - winstart
  update_content()
end

function delta_scale(d)
  scale = util.clamp(scale + d, 1, 128)
  screen_dirty = true
end

function double_buffer()
  local cursor_sec = winstart + (cursor - 1) * interval
  softcut.buffer_copy_mono(1, 1, 0, cursor_sec, clipsize, 0.1, 1, 1)
  print('copy ' .. clipsize .. ' to ' .. cursor_sec)
  clipsize = cursor_sec + clipsize
  softcut.loop_end(1, clipsize)
  update_content()
end

function load_sample(f)
  if f == '-' then
    return
  end
  print('load ' .. f)
  local chs, frames, rate = audio.file_info(f)

  -- include fadeout time
  clipsize = frames / rate
  winstart = 0
  winend = clipsize
  winsize = winend - winstart
  print('sample is ' .. frames / rate .. ' seconds')

  softcut.buffer_clear()
  softcut.buffer_read_mono(f, 0, 0, -1, 1, 1)
  softcut.loop_end(1, clipsize)
  update_content()
end

function save_buffer(f)
  local fname = paths.audio .. 'waveviz-' .. f .. '.wav'
  softcut.buffer_write_mono(fname, 0, clipsize, 1)
  print('wrote to ' .. fname)
end

phase = 0
function phase_poll(v, p)
  phase = p
  screen_dirty = true
end

function init()
  params:add_file('sample', 'sample')
  params:set_action('sample', function (f) load_sample(f) end)

  params:add_option('playing', 'playing', {'off', 'on'}, 1)
  params:set_action('playing', function (v)
    print('playing: ' .. v)
    if v == 2 then
      softcut.enable(1, 1)
      softcut.buffer(1, 1)
      softcut.level(1, 1)
      softcut.event_phase(phase_poll)
      softcut.phase_quant(1, 1 / 15)
      softcut.poll_start_phase()
      softcut.loop(1, 1)
      softcut.loop_start(1, 0)
      softcut.loop_end(1, clipsize)
      softcut.rate(1, 1)
      softcut.position(1, 0)
      softcut.play(1, 1)
    else
      softcut.play(1, 0)
      softcut.poll_stop_phase()
    end
  end)

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
      center_cursor()
    elseif n == 3 then
      if held_keys[1] then
        double_buffer()
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
    delta_window(d)
  elseif n == 3 then
    delta_cursor(d)
  end
end

function redraw()
  screen.clear()

  local x = 0
  local y = 0

  screen.level(1)
  y = y + 8
  screen.move(x, y)
  screen.text('1.0=' .. string.format('%d', scale) .. 'px')

  x = x + 48
  screen.move(x, y)
  screen.text(string.format('%.5f - %.5f', winstart, winend))

  if #samples > 0 then
    x = 0
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

    if phase >= winstart and phase <= winend and winend - winstart > 0 then
      local playhead_pos = 1 + util.round(128 * (phase - winstart) / (winend - winstart))

      screen.move(playhead_pos, 12)
      screen.level(6)
      screen.line_rel(0, 40)
      screen.stroke()

      screen.move(playhead_pos, 14)
      screen.text(string.format('%.5f', phase))
    end

    screen.level(1)

    x = 0
    y = 64
    screen.move(x, y)
    screen.text('t = ' .. cursor .. ' / ' .. #samples)

    x = 64
    screen.move(x, y)
    screen.text('x[t] = ' .. string.format('%.5f', samples[cursor]))
  end

  screen.update()
end

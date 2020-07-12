-- waveviz
-- view audio file waveforms
-- just one channel right now
--
-- E1: zoom
--  with K1 held: scale drawn amplitude
-- E2: move transport
-- E3: move cursor
-- K2: center transport on cursor
-- K3: center cursor in window

local clipsize = 0
local winstart = 0
local winend = 0
local cursor = 1
local interval = 0
local samples = {}
local scale = 20
local held_keys = {}

function update_content()
  softcut.render_buffer(
     1, winstart, winend - winstart, 128,
     function(ch, start, i, s)
       cursor = util.clamp(cursor, 1, #s)
       samples = s
       interval = i
       redraw()
     end)
end

function delta_zoom(d)
  local range = winend - winstart
  if d > 0 then
    range = range / 2
  elseif d < 0 then
    range = range * 2
  end
  local center_sec = winstart + util.round(#samples / 2) * interval
  winstart = util.clamp(center_sec - range / 2, 0, clipsize)
  winend = util.clamp(center_sec + range / 2, 0, clipsize)
  update_content()
end

function delta_window(d)
  local range = winend - winstart
  if range > 0 then
    winstart = util.clamp(winstart + d * range * 0.1, 0, clipsize)
    winend = util.clamp(winend + d * range * 0.1, 0, clipsize)
    update_content()
  end
end

function delta_cursor(d)
  cursor = util.clamp(cursor + d, 1, #samples)
  redraw()
end

function center_cursor()
  local range = winend - winstart
  local cursor_sec = winstart + (cursor - 1) * interval
  cursor = util.round(#samples / 2)
  winstart = util.clamp(cursor_sec - range / 2, 0, clipsize)
  winend = util.clamp(cursor_sec + range / 2, 0, clipsize)
  update_content()
end

function delta_scale(d)
  scale = util.clamp(scale + d, 1, 128)
  redraw()
end

function double_buffer()
  print('double!')
  softcut.buffer_copy_mono(1, 1, 0, clipsize, clipsize)
  clipsize = clipsize * 2
  update_content()
end

function load_sample(f)
  if f == '-' then
    return
  end
  print('load ' .. f)
  local chs, frames, rate = audio.file_info(f)
  clipsize = frames / rate
  winstart = 0
  winend = clipsize
  print('sample is ' .. clipsize .. ' seconds')

  softcut.buffer_read_mono(f, 0, 0, -1, 1, 1)
  update_content()
end

function init()
  params:add_file('sample', 'sample')
  params:set_action('sample', function (f) load_sample(f) end)

  redraw()
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
        redraw()
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
  screen.text('1.0=' .. string.format('%d', 2 * scale) .. 'px')

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

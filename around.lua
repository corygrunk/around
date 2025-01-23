--- around
--- loops of loops
--
-- K1 alt functions
-- K2 rec/overdub
-- K3 clear
-- E1 select loop
-- selected main loop:
-- E2 adjust start position
-- E3 adjust length
-- Alt + E2 adjust fx level
-- Alt + E3 adjust main loop level
-- selected micro loops:
-- E2 move selected loop
-- E3 adjust size of selected loop
-- Alt + E1 adjust LFO (amount)
-- Alt + E2 change rate of selected loop
-- Alt + E3 change level of selected loop

Tab = require('tabutil')
lfo = require('lfo')

lfo_shapes = {"sine", "tri", "up", "down", "random"}
lfos = {}
lfo_amounts = {0.15, 0.0, 0.0}
manual_moving = {false, false, false}  -- One for each micro loop
loop_centers = {0,0,0}  -- One for each micro loop

sc = softcut
level = 1.0
fade_time = 0.1
pre_level = 0.2
rate = 1.0

fx_fade_time = 0 -- this controls how quickly the fx level fades in after recording/clearing
clearing = false

default_loop_length = 15
length = {default_loop_length, default_loop_length, default_loop_length, default_loop_length}
start = {1,1,1,1}

voice_rates = {1.0, 1.5, 1.5, -2.0}  -- Default rates for each voice
voice_levels = {1.0, 0.3, 0.4, 0.4}  -- Default levels for each voice
active_voice = 1  -- Start with main loop selected

fx_level = 1.0  -- Start at full level

alt_mode = false

rec_msg = ''
recording = false
overdub = false
buffer_is_clear = true

position = {0,0,0,0} -- initialize position to avoid nil


-- Buffer save/load functions
function save_buffer_to_file(pset_number)
  -- Get script name from the current file path
  local script_name = string.match(debug.getinfo(1).source, "^@.+/(.+)%.lua$")
  -- Create script folder in audio directory if it doesn't exist
  local audio_dir = "/home/we/dust/audio/" .. script_name .. "/"
  os.execute("mkdir -p " .. audio_dir)
  print("Created directory:", audio_dir)
  
  -- Generate filename based on pset number
  local filename = audio_dir .. "loop_" .. string.format("%02d", pset_number) .. ".wav"
  
  -- Save from position 0 to ensure we get the full buffer
  sc.buffer_write_stereo(filename, 0, params:get("buffer_length"))
  print("Saving loop to:", filename, "length:", params:get("buffer_length"))
end

function load_buffer_from_file(pset_number)
  -- Get script name from the current file path
  local script_name = string.match(debug.getinfo(1).source, "^@.+/(.+)%.lua$")
  local filename = "/home/we/dust/audio/" .. script_name .. "/loop_" .. string.format("%02d", pset_number) .. ".wav"
  print("Loading from:", filename)
  
  -- Check if file exists
  local file = io.open(filename, "r")
  if file then
    file:close()
    print("Loading loop from:", filename)

    -- First, stop all voices and clear buffer
    for i = 1, 4 do
      sc.play(i, 0)
      sc.rec(i, 0)
    end
    sc.buffer_clear()
    
    -- Reset states
    buffer_is_clear = true
    recording = false
    overdub = false
    
    -- Load the buffer file starting at position 0
    sc.buffer_read_stereo(filename, 0, 0, -1)
    
    -- Wait a bit for the buffer to load, then initialize everything
    clock.run(function()
      -- Give the buffer time to load
      clock.sleep(0.2)
      
      -- Reset start position to 1 and get length from params
      start[1] = 1
      length[1] = params:get("buffer_length")
      
      -- Reset buffer state
      buffer_is_clear = false
      
      -- Calculate micro loop lengths based on main loop length
      length[2] = length[1] / 16
      length[3] = length[1] / 4
      length[4] = length[1] / 2
      
      -- Initialize all voice parameters
      for i = 1, 4 do
        -- Set start positions
        if i == 1 then
          start[i] = 1
        elseif i == 2 then
          start[i] = start[1]
        elseif i == 3 then
          start[i] = start[1] + (length[1] * 0.25)
        elseif i == 4 then
          start[i] = start[1] + (length[1] / 2)
        end
        
        -- Initialize softcut voice
        sc.enable(i, 1)
        sc.buffer(i, 1)
        sc.level_input_cut(i, 1, 1.0)
        sc.phase_quant(i, 0.01)
        sc.loop(i, 1)
        sc.loop_start(i, start[i])
        sc.loop_end(i, start[i] + length[i])
        sc.position(i, start[i])
        
        -- Set voice-specific parameters
        if i == 1 then
          sc.rate(i, 1.0)
          sc.level(i, params:get("voice_1_level"))
        else
          sc.rate(i, params:get("voice_" .. i .. "_rate"))
          sc.level(i, params:get("voice_" .. i .. "_level") * params:get("fx_level"))
        end
        
        -- Start playing
        sc.play(i, 1)
      end
      
      -- Update loop centers
      loop_centers[1] = start[2]
      loop_centers[2] = start[3]
      loop_centers[3] = start[4]
      
      -- Update display
      update_content(1, start[1], start[1] + length[1], 128)
      screen_dirty = true
    end)
  else
    print("File not found:", filename)
  end
end

-- Modified pset callback functions
function init_pset()
  params.action_write = function(filename, name, number)
    print("Writing pset", number)
    save_buffer_to_file(number)
  end
  
  params.action_read = function(filename, name, number)
    print("Reading pset", number)
    load_buffer_from_file(number)
  end
  
  params.action_delete = function(filename, name, number)
    -- Get script name from the current file path
    local script_name = string.match(debug.getinfo(1).source, "^@.+/(.+)%.lua$")
    -- Delete associated buffer file
    local buffer_file = "/home/we/dust/audio/" .. script_name .. "/loop_" .. string.format("%02d", number) .. ".wav"
    print("Deleting file:", buffer_file)
    os.execute("rm -f " .. buffer_file)
  end
end




function init()
  -- Main Loop/Buffer Settings
  params:add_separator("Main Loop Settings")

  params:add{
      type = "control",
      id = "buffer_length",
      name = "Buffer Length",
      controlspec = controlspec.new(0.01, 30.0, 'lin', 0.01, default_loop_length, 's'),
      action = function(value)
          length[1] = value
          if not buffer_is_clear then
              sc.loop_end(1, start[1] + value)
              -- Update microloop lengths proportionally
              length[2] = value / 16
              length[3] = value / 4
              length[4] = value / 2
              -- Update loop endpoints for microloops
              for i = 2, 4 do
                  sc.loop_end(i, start[i] + length[i])
              end
          end
      end
  }

  params:add{
      type = "control",
      id = "main_loop_start",
      name = "Main Loop Start",
      controlspec = controlspec.new(1, 30, 'lin', 0.01, start[1]),
      action = function(value)
          start[1] = value
          if not buffer_is_clear then
              sc.loop_start(1, value)
          end
      end
  }

  -- Microloop Positions
  params:add_separator("Microloop Positions")
  for i = 2, 4 do
      params:add{
          type = "control",
          id = "loop_" .. i .. "_start",
          name = "Loop " .. i .. " Start",
          controlspec = controlspec.new(1, 30, 'lin', 0.01, start[i]),
          action = function(value)
              start[i] = value
              if not buffer_is_clear then
                  sc.loop_start(i, value)
                  sc.loop_end(i, value + length[i])
              end
          end
      }
  end

  -- LFO Settings
  params:add_separator("LFO Settings")
  for i = 1, 3 do
      params:add{
          type = "option",
          id = "lfo_" .. i .. "_shape",
          name = "LFO " .. i .. " Shape",
          options = lfo_shapes,
          default = 1,
          action = function(value)
              if lfos[i] then
                  manual_moving[i] = false
                  local current_center = loop_centers[i]
                  
                  if lfos[i].stop then lfos[i]:stop() end
                  
                  lfos[i] = lfo:add{
                      shape = lfo_shapes[value],
                      min = 0,
                      max = 1,
                      depth = 1,
                      mode = 'free',
                      period = params:get("lfo_" .. i .. "_period"),
                      action = function(scaled, raw)
                          if not recording and not buffer_is_clear then
                              local voice = i + 1
                              if not manual_moving[i] then
                                  local main_loop_length = length[1]
                                  local max_range = main_loop_length / 2
                                  local movement = max_range * params:get("lfo_" .. i .. "_amount") * scaled
                                  
                                  local center_pos = current_center or (start[1] + (length[1] / 2))
                                  
                                  local new_pos = util.clamp(
                                      center_pos + movement,
                                      start[1],
                                      start[1] + length[1] - length[voice]
                                  )
                                  start[voice] = new_pos
                                  sc.loop_start(voice, new_pos)
                                  sc.loop_end(voice, new_pos + length[voice])
                              end
                          end
                      end
                  }
                  
                  lfos[i]:start()
              end
          end
      }

      params:add{
          type = "control",
          id = "lfo_" .. i .. "_period",
          name = "LFO " .. i .. " Period",
          controlspec = controlspec.new(0.1, 10.0, 'lin', 0.1, 2.0, 's'),
          action = function(value)
              if lfos[i] then
                  lfos[i]:set('period', value)
              end
          end
      }

      params:add{
          type = "control",
          id = "lfo_" .. i .. "_amount",
          name = "LFO " .. i .. " Amount",
          controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.15),
          action = function(value)
              lfo_amounts[i] = value
          end
      }
  end

  -- Voice Settings
  params:add_separator("Voice Settings")
  
  -- Main voice level
  params:add{
      type = "control",
      id = "voice_1_level",
      name = "Main Voice Level",
      controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
      action = function(value)
          voice_levels[1] = value
          sc.level(1, value)
      end
  }

  -- Microloop voice settings
  for i = 2, 4 do
      params:add{
          type = "control",
          id = "voice_" .. i .. "_rate",
          name = "Voice " .. i .. " Rate",
          controlspec = controlspec.new(-2.0, 2.0, 'lin', 0.01, voice_rates[i]),
          action = function(value)
              voice_rates[i] = value
              if not buffer_is_clear then
                  sc.rate(i, value)
              end
          end
      }

      params:add{
          type = "control",
          id = "voice_" .. i .. "_level",
          name = "Voice " .. i .. " Level",
          controlspec = controlspec.new(0, 1, 'lin', 0.01, voice_levels[i]),
          action = function(value)
              voice_levels[i] = value
              if not buffer_is_clear then
                  sc.level(i, value * fx_level)
              end
          end
      }
  end

  params:add_separator("Pan Settings")
  
  -- Default pan positions: left, center, right for the three micro-loops
  params:add{
    type = "control",
    id = "voice_2_pan",
    name = "Micro Loop 1 Pan",
    controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, -0.7),  -- Default to left
    action = function(value)
      if not buffer_is_clear then
        sc.pan(2, value)
      end
    end
  }
  
  params:add{
    type = "control",
    id = "voice_3_pan",
    name = "Micro Loop 2 Pan",
    controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.0),  -- Default to center
    action = function(value)
      if not buffer_is_clear then
        sc.pan(3, value)
      end
    end
  }
  
  params:add{
    type = "control",
    id = "voice_4_pan",
    name = "Micro Loop 3 Pan",
    controlspec = controlspec.new(-1.0, 1.0, 'lin', 0.01, 0.7),  -- Default to right
    action = function(value)
      if not buffer_is_clear then
        sc.pan(4, value)
      end
    end
  }


  -- Recording Settings
  params:add_separator("Recording Settings")
  
  params:add{
    type = "control",
    id = "fx_fade_in_time",
    name = "FX Fade Time (s)",
    controlspec = controlspec.new(0, 5, 'lin', 0.1, 1.0, 's'),
    action = function(value)
        fx_fade_time = value
    end
}

    params:add{
      type = "control",
      id = "fx_level",
      name = "FX Level",
      controlspec = controlspec.new(0, 1, 'lin', 0.01, 1.0),
      action = function(value)
          fx_level = value
          if not buffer_is_clear then
              for i = 2, 4 do
                  sc.level(i, voice_levels[i] * value)
              end
          end
      end
  }

  params:add{
      type = "control",
      id = "pre_level",
      name = "Pre Level",
      controlspec = controlspec.new(0, 1, 'lin', 0.01, 0.2, ''),
      action = function(value)
          pre_level = value
          for i = 1, 4 do
              sc.pre_level(i, value)
          end
      end
  }
  
  params:add{
      type = "control",
      id = "fade_time",
      name = "Fade Time",
      controlspec = controlspec.new(0.0, 1.0, 'lin', 0.01, 0.1, 's'),
      action = function(value)
          fade_time = value
          for i = 1, 4 do
              sc.fade_time(i, value)
          end
      end
  }

  -- Initialize softcut
  sc.buffer_clear()
  audio.level_cut(0.6)
  audio.level_adc_cut(1)

  for i = 1, 4 do
    sc.level_input_cut(i, 1, 1.0)
    sc.rec(i, 0)
    sc.rec_level(i, 1)
    sc.pre_level(i, 0.2)
    sc.enable(i,1)
    sc.buffer(i,1)
    sc.level(i,1.0)
    sc.loop(i,1)
    sc.loop_start(i,start[i])
    sc.loop_end(i,length[i])
    sc.position(i,1)
    sc.rate(i,rate)
    sc.play(i,0)
    sc.fade_time(i,fade_time)
    sc.rate_slew_time(i,0)
    sc.recpre_slew_time(i,0)
    sc.phase_quant(i, 0.01)  -- Set phase tracking for all voices
  end

  for i = 2, 4 do
    sc.pan(i, params:get("voice_" .. i .. "_pan"))
  end

  -- Initialize LFOs for each micro loop
  for i = 1, 3 do
    lfos[i] = lfo:add{
      shape = 'sine',
      min = 0,  -- Change from 0 to -1 for bilateral modulation
      max = 1,   -- Change from 20 to 1 for normalized range
      depth = 1,  -- Change from 0.5 to 1 for full modulation depth
      mode = 'free',
      period = 2,
      action = function(scaled, raw)
        if not recording and not buffer_is_clear then
          local voice = i + 1
          if not manual_moving[i] then
            local main_loop_length = length[1]
            local max_range = main_loop_length / 2
            local movement = max_range * lfo_amounts[i] * scaled
            
            -- Use the saved center position, or calculate it if not set
            local center_pos = loop_centers[i]
            if center_pos == 0 then  -- If not set yet
              center_pos = start[1] + (length[1] / 2)
              loop_centers[i] = center_pos
            end
            
            local new_pos = util.clamp(
              center_pos + movement,
              start[1],
              start[1] + length[1] - length[voice]
            )
            start[voice] = new_pos
            sc.loop_start(voice, new_pos)
            sc.loop_end(voice, new_pos + length[voice])
          end
        end
      end
    }
  end

  -- Start all LFOs
  for i = 1, 3 do
    lfos[i]:start()
  end

  sc.event_phase(update_positions)
  sc.poll_start_phase()
  softcut.event_render(on_render)

  init_pset()

  clock.run(redraw_clock)
  screen_dirty = true
end



function update_positions(i,pos)
  position[i] = pos  -- Only update the position for the voice that called this
  -- Check if we're recording and have reached the end of the loop (only for voice 1)
  if i == 1 and recording and position[1] >= (length[1] - 1) then
    recording = false
    sc.rec(1,0)
    sc.loop_end(1,1 + length[1])
    update_content(1,1,1 + length[1],128)
    rec_msg = ''
  end
  screen_dirty = true
end

function start_addl_playheads()
  -- LOOP 2 (first micro loop - 1/16th size at start, 1.5x rate)
  sc.rate(2, voice_rates[2])
  sc.level(2, voice_levels[2] * fx_level)  -- Apply fx_level
  start[2] = start[1]
  length[2] = length[1] / 16
  sc.loop_start(2, start[2])
  sc.loop_end(2, start[2] + length[2])
  sc.position(2, start[2])
  sc.play(2, 1)
  
  -- LOOP 3 (second micro loop - 1/4 size at 1/4 point, 1.5x rate)
  sc.rate(3, voice_rates[3])
  sc.level(3, voice_levels[3] * fx_level)  -- Apply fx_level
  start[3] = start[1] + (length[1] * 0.25)
  length[3] = length[1] / 4
  sc.loop_start(3, start[3])
  sc.loop_end(3, start[3] + length[3])
  sc.position(3, start[3])
  sc.play(3, 1)
  
  -- LOOP 4 (third micro loop - 1/2 size at halfway point, -2x rate)
  sc.rate(4, voice_rates[4])
  sc.level(4, voice_levels[4] * fx_level)  -- Apply fx_level
  start[4] = start[1] + (length[1] / 2)
  length[4] = length[1] / 2
  sc.loop_start(4, start[4])
  sc.loop_end(4, start[4] + length[4])
  sc.position(4, start[4])
  sc.play(4, 1)
  
  -- Initialize loop centers
  loop_centers[1] = start[2]
  loop_centers[2] = start[3]
  loop_centers[3] = start[4]

  screen_dirty = true
end


-- fade in
function start_fx_fade_in()
  local start_level = 0
  local target_level = params:get("fx_level")
  local fade_duration = params:get("fx_fade_in_time")
  
  -- Set initial level to 0
  fx_level = start_level
  for i = 2, 4 do
    sc.level(i, voice_levels[i] * start_level)
  end
  
  clock.run(function()
    local steps = 30 -- number of steps for smooth fade
    local step_time = fade_duration / steps
    local level_increment = (target_level - start_level) / steps
    
    for i = 1, steps do
      clock.sleep(step_time)
      fx_level = start_level + (level_increment * i)
      -- Update all micro-loop levels
      for v = 2, 4 do
        sc.level(v, voice_levels[v] * fx_level)
      end
    end
    
    -- Ensure we end exactly at target level
    fx_level = target_level
    for v = 2, 4 do
      sc.level(v, voice_levels[v] * fx_level)
    end
  end)
end


-- fade out
function start_fx_fade_out()
  local start_level = fx_level
  local main_start_level = voice_levels[1]
  local target_level = 0
  local fade_duration = params:get("fx_fade_in_time")
  
  clock.run(function()
    local steps = 30
    local step_time = fade_duration / steps
    local level_increment = (target_level - start_level) / steps
    local main_level_increment = (target_level - main_start_level) / steps
    
    for i = 1, steps do
      clock.sleep(step_time)
      -- Fade microloops
      fx_level = start_level + (level_increment * i)
      for v = 2, 4 do
        sc.level(v, voice_levels[v] * fx_level)
      end
      -- Fade main loop
      local new_main_level = main_start_level + (main_level_increment * i)
      sc.level(1, new_main_level)
    end
    
    -- Ensure we end at silence
    fx_level = target_level
    for v = 1, 4 do
      sc.level(v, 0)
    end
  end)
end

-- LFO helper functions
function set_lfo_shape(lfo_index, shape)
  if lfos[lfo_index] then
    lfos[lfo_index]:set('shape', shape)
  end
end

function set_lfo_period(lfo_index, period)
  if lfos[lfo_index] then
    lfos[lfo_index]:set('period', period)
  end
end

-- WAVEFORMS
local interval = 0
waveform_samples = {}
scale = 30

function on_render(ch, start, i, s)
  waveform_samples = s
  interval = i
  screen_dirty = true
end

function update_content(buffer,winstart,winend,samples)
  softcut.render_buffer(buffer, winstart, winend - winstart, 128)
end

function key(n,z)
  if n == 1 then
    alt_mode = (z == 1)
  elseif n == 2 and z == 1 then
    if recording then
      recording = false
      sc.rec(1,0)
      length[1] = position[1] - start[1]
      params:set("buffer_length", length[1])
      sc.loop_end(1,start[1] + length[1])
      sc.loop_start(1,start[1])
      sc.position(1,start[1])
      update_content(1,start[1],start[1] + length[1],128)
      start_addl_playheads()
      active_voice = 1
      rec_msg = ''
      start_fx_fade_in()
    elseif overdub then
      overdub = false
      sc.rec(1,0)
      rec_msg = ''
    elseif buffer_is_clear then
      recording = true
      local current_pos = position[1]
      sc.position(1, current_pos)
      sc.rec(1,1)
      sc.play(1,1)
      rec_msg = 'rec'
      buffer_is_clear = false
    else
      overdub = true
      local current_pos = position[1]
      sc.position(1, current_pos)
      sc.rec(1,1)
      rec_msg = 'dub'
    end
  elseif n == 3 and z == 1 then
    if not buffer_is_clear then
      start_fx_fade_out()
      clearing = true
      rec_msg = ''
      if overdub then
        overdub = false
        sc.rec(1,0)
      end
      
      clock.run(function()
        -- Wait for fade to complete
        clock.sleep(params:get("fx_fade_in_time"))
        -- Stop all voices after fade
        for i = 1, 4 do
          sc.play(i, 0)
        end
        -- Clear buffer and reset state
        for i = 1, 4 do
          start[i] = 1
          length[i] = default_loop_length
          position[i] = 0
          sc.buffer_clear_channel(1)
          sc.loop_start(i,start[i])
          sc.loop_end(i,length[i])
          sc.position(i,start[i])
          sc.rec(i,0)
        end
        position = {0,0,0,0}
        recording = false
        overdub = false
        buffer_is_clear = true
        clearing = false
        update_content(1,1,default_loop_length,128)
      end)
    end
  end
  screen_dirty = true
end

function enc(n,d)
  if n == 1 then
      if not alt_mode then
          active_voice = active_voice or 1
          active_voice = util.clamp(active_voice + d, 1, 4)
      else
          -- Alt + E1 controls LFO amount (only for micro loops)
          local voice = active_voice or 1
          if voice > 1 then
              local lfo_index = voice - 1
              local new_amount = util.clamp(lfo_amounts[lfo_index] + d/100, 0, 1)
              lfo_amounts[lfo_index] = new_amount
              params:set("lfo_" .. lfo_index .. "_amount", new_amount)
          end
      end
  elseif n == 2 then
      local voice = active_voice or 1
      if voice == 1 then
          if not alt_mode then
              -- Main loop start point control
              local new_start = util.clamp(start[1] + d/20, 1, start[1] + length[1] - 1)
              start[1] = new_start
              params:set("main_loop_start", new_start)
              sc.loop_start(1, new_start)
              update_content(1, new_start, new_start + length[1], 128)
          else
              -- Alt + E2 controls fx level
              local new_fx_level = util.clamp(fx_level + d/10, 0, 1)
              fx_level = new_fx_level
              params:set("fx_level", new_fx_level)
              -- Update all micro-loop levels
              for i = 2, 4 do
                  sc.level(i, voice_levels[i] * new_fx_level)
              end
          end
      else
          if alt_mode then
              -- Alt + E2 controls rate (only for micro loops)
              local new_rate = util.clamp(voice_rates[voice] + d/50, -2, 2)
              voice_rates[voice] = new_rate
              params:set("voice_" .. voice .. "_rate", new_rate)
              sc.rate(voice, new_rate)
          else
              -- Normal mode: Move micro loop position
              local lfo_index = voice - 1
              manual_moving[lfo_index] = true
              
              -- Calculate min and max positions for the micro loop
              local min_pos = start[1]  -- Can't go before main loop start
              local max_pos = start[1] + length[1] - length[voice]  -- Can't go past main loop end minus micro loop length
              
              -- Move the micro loop
              local new_pos = util.clamp(start[voice] + d/20, min_pos, max_pos)
              start[voice] = new_pos
              params:set("loop_" .. voice .. "_start", new_pos)
              sc.loop_start(voice, new_pos)
              sc.loop_end(voice, new_pos + length[voice])
              
              -- Update center position after a delay
              local function update_center()
                  clock.sleep(0.5)
                  loop_centers[lfo_index] = new_pos
                  manual_moving[lfo_index] = false
              end
              clock.run(update_center)
          end
      end
  elseif n == 3 then
      local voice = active_voice or 1
      if voice == 1 then
          if alt_mode then
              -- Alt + E3 controls main voice level
              local new_level = util.clamp(voice_levels[1] + d/50, 0, 1)
              voice_levels[1] = new_level
              params:set("voice_1_level", new_level)
              sc.level(1, new_level)
          else
              -- Main loop length control
              local min_length = 1
              local new_length = util.clamp(length[1] + d/20, min_length, 30)
              length[1] = new_length
              params:set("buffer_length", new_length)
              sc.loop_end(1, start[1] + new_length)
              update_content(1, start[1], start[1] + new_length, 128)
          end
      else
          if alt_mode then
              -- Alt + E3 controls level for individual micro loops
              local new_level = util.clamp(voice_levels[voice] + d/10, 0, 1)
              voice_levels[voice] = new_level
              params:set("voice_" .. voice .. "_level", new_level)
              sc.level(voice, new_level * fx_level)  -- Apply the fx_level when setting individual level
          else
              -- Normal mode: Adjust micro loop size
              local min_length = 0.01
              local max_length = length[1] / 2
              local new_length = util.clamp(length[voice] + d/50, min_length, max_length)
              
              if start[voice] + new_length > start[1] + length[1] then
                  start[voice] = (start[1] + length[1]) - new_length
              end
              
              length[voice] = new_length
              sc.loop_start(voice, start[voice])
              sc.loop_end(voice, start[voice] + new_length)
          end
      end
  end
  screen_dirty = true
end

function redraw()
  screen.clear()

  if recording or overdub then
    update_content(1,start[1],start[1] + length[1],128)
  end

  -- waveform
  screen.move(62,10)
  screen.level(4)
  local x_pos = 0
  for i,s in ipairs(waveform_samples) do
    local height = util.round(math.abs(s) * (scale*level))
    screen.move(util.linlin(0,128,10,120,x_pos), 35 - height)
    screen.line_rel(0, 2 * height)
    screen.stroke()
    x_pos = x_pos + 1
  end

  -- playheads
  for i = 1, 4 do -- main loop plus 3 micro loops
    -- Only show first playhead if still recording or buffer is clear
    if buffer_is_clear or recording then
      if i == 1 then 
        screen.level(15)
        screen.move(util.linlin(start[i], start[i] + length[i], 10, 120, position[i]), 18)
        screen.line_rel(0, 35)
        screen.stroke()
      end
    -- Show all playheads after recording is complete
    else
      if i == 1 then 
        screen.level(15)
      elseif i == active_voice then
        screen.level(15)  -- Highlight active loop
      else 
        screen.level(2)
      end
      
      local pos = position[i]
      -- Calculate loop points for display
      local loop_start = start[i]
      local loop_end = start[i] + length[i]
      
      if i > 1 then
        -- Calculate the relative position within the shorter loop
        local relative_pos = pos - loop_start
        local loop_length = length[i]
        relative_pos = relative_pos % loop_length
        pos = loop_start + relative_pos
        
        -- Calculate the screen position based on the actual loop region
        local region_width = 110 * (length[i] / length[1])  -- Scale width based on loop length ratio
        local region_start = 10 + (110 * ((start[i] - start[1]) / length[1]))  -- Position based on start point
        screen_pos = region_start + (relative_pos / loop_length * region_width)
      else
        screen_pos = util.linlin(loop_start, loop_end, 10, 120, pos)
      end

      screen.move(screen_pos, 18)
      screen.line_rel(0, 35)
      screen.stroke()

      -- Draw loop region indicators for loops
      if i > 1 then
        -- Calculate region position and width
        local region_start = 10 + (110 * ((start[i] - start[1]) / length[1]))
        local region_width = 110 * (length[i] / length[1])
        
        if i == active_voice then
          screen.level(15)
          -- Draw full height lines for selected loop
          screen.move(region_start, 18)
          screen.line_rel(0, 35)
          screen.move(region_start + region_width, 18)
          screen.line_rel(0, 35)
          screen.stroke()
        else
          -- Draw small markers for unselected loops
          screen.level(1)
          screen.move(region_start, 16)
          screen.line_rel(0, 2)
          screen.move(region_start + region_width, 16)
          screen.line_rel(0, 2)
          screen.stroke()
        end
      end
    end
  end

  -- start marker
  screen.level(15)
  screen.move(10,30)
  screen.line_rel(0, 10)
  screen.stroke()

  -- end marker
  screen.level(15)
  screen.move(120,30)
  screen.line_rel(0, 10)
  screen.stroke()

  -- Display info for selected loop
  if not buffer_is_clear and not recording then
    if active_voice == 1 then
      screen.move(10,10)
      if clearing then
        screen.level(6)
        screen.text('fading away...')
      else
        screen.level(15)
        screen.text('k3 to clear')
      end
      
      if alt_mode then
        screen.level(15)
      else
        screen.level(2)
      end
      
      if alt_mode then
        -- Show level
        screen.move(10,60)
        screen.text(string.format('fx lvl %.1f', fx_level))

        -- Show micro-loop fx level
        screen.move(120,60)
        screen.text_right(string.format('main lvl %.1f', voice_levels[1]))
      end
    else
      screen.move(10,10)
      screen.text('loop ' .. active_voice - 1)
      
      if alt_mode then
        screen.level(15)
        -- Show LFO info
        local lfo_index = active_voice - 1
        screen.move(5,60)
        screen.text(string.format('lfo %.2f', lfo_amounts[lfo_index]))

        -- Show rate and level
        screen.move(64, 60)
        screen.text_center(string.format('rt %.2f', voice_rates[active_voice]))

        screen.move(120,60)
        screen.text_right(string.format('lvl %.2f', voice_levels[active_voice]))
      end
    end
  elseif recording then
    screen.move(10,10)
    screen.text('k2 again to loop')
  else
    screen.move(10,10)
    screen.text('k2 to rec')
  end

  -- rec message
  if not alt_mode then
    screen.level(6)
    screen.move(10,60)
    screen.text(rec_msg)
  end

  screen.update()
end

function redraw_clock()
  while true do
    clock.sleep(1/30)
      if screen_dirty then
        redraw()
        screen_dirty = false
      end
    end
end




-- UTILITY TO RESTART SCRIPT FROM MAIDEN
function r()
norns.script.load(norns.state.script)
end

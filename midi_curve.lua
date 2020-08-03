ardour {
  ["type"]    = "dsp",
  name        = "MIDI Velocity Curve",
  category    = "Utility",
  license     = "MIT",
  author      = "Ardour Lua Task Force",
  description = [[Midi Filter for Velocity Curve.]]
}

-- The number of remapping pairs to allow. Increasing this (at least in theory)
-- decreases performace, so it's set fairly low as a default. The user can
-- increase this if they have a need to.
N_REMAPINGS = 10

OFF_NOTE = -1

function dsp_ioconfig ()
  return { { midi_in = 1, midi_out = 1, audio_in = 0, audio_out = 0}, }
end

function dsp_params ()
	local map_scalepoints = {}
    map_scalepoints["None"] = OFF_NOTE
    for note=0,127 do
        local name = ARDOUR.ParameterDescriptor.midi_note_name(note)
        map_scalepoints[string.format("%03d (%s)", note, name)] = note
    end

    local map_params = {}

    local cur_note = 1
    i = 1
    for mapnum = 1,N_REMAPINGS do
	    local alternating = ((mapnum % 2) and "#" or "")
	    map_params[i] = {
		["type"] = "input",
		name = alternating .. "Note" .. tostring(cur_note),
		min = -1,
		max = 127,
		default = OFF_NOTE,
		integer = true,
		enum = true,
		scalepoints = map_scalepoints
	    }
	    i = i + 1
	    map_params[i] = {
		["type"] = "input",
		name = "Note" .. tostring(cur_note).."-Curve",
		min = 0,
		max = 2,
		default = 0,
		enum = true, scalepoints =
			{
				["Linear"]    = 0,
				["Logarithmic"]  = 1,
				["Exponential"] = 2,
			}
	    }
	    i = i + 1
	    map_params[i] = {
		["type"] = "input",
		name = "Note" .. tostring(cur_note).."-Slope",
		min = 0.001,
		max = 10,
		default = 1,
		unit=""
	    }
	    i = i + 1
	    cur_note = cur_note + 1
    end

    return map_params
end

function dsp_run (_, _, n_samples)
  local cnt = 1;
  function tx_midi (time, data)
    midiout[cnt] = {}
    midiout[cnt]["time"] = time;
    midiout[cnt]["data"] = data;
    cnt = cnt + 1;
  end

  function check_limits(v)
    if v < 1 then
        v = 1
      elseif v > 127 then
          v = 127
      end
      return math.floor (v)
  end

  function linear_curve(v, slope)
      return check_limits ( slope*v )
  end

  function log_curve (v, slope)
      return check_limits ( 127*math.log(slope*v)/math.log(slope*127) )
  end

  function exp_curve (v, slope)
      return check_limits ( 127*(math.exp(slope*v/127)-1)/(math.exp(slope)-1) )
  end
  
  function map_velocity (n, v)
    local ctrl = CtrlPorts:array ()

    for i=1,N_REMAPINGS*3,3 do
        if (ctrl[i] == n) then
	    local slope = ctrl[i+2]
            if ctrl[i+1] == 1 then
	      v = log_curve (v, slope)
	    elseif ctrl[i+1] == 2 then
	      v = exp_curve (v, slope)
	    else
	      v = linear_curve (v, slope)
	    end
	    break
        end
    end

    return v
  end

  -- for each incoming midi event
  for _,b in pairs (midiin) do
    local t = b["time"] -- t = [ 1 .. n_samples ]
    local d = b["data"] -- get midi-event bytes
    local event_type
    if #d == 0 then event_type = -1 else event_type = d[1] >> 4 end
    if (#d == 3 and event_type == 9) then -- note on
      d[3] = map_velocity (d[2], d[3])
      tx_midi (t, d)
    else -- pass thru all other events unmodified
      tx_midi (t, d)
    end
  end
end

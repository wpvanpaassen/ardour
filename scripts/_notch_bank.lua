ardour {
	["type"]    = "dsp",
	name        = "Notch Bank",
	category    = "Example",
	license     = "MIT",
	author      = "Ardour Lua Task Force",
	description = [[An Example Filter Plugin]]
}

-------------------------------------------------------------------
-- this is a quick/dirty example filter: no de-click, no de-zipper,
-- no latency reporting,...
-------------------------------------------------------------------

-- configuration
local max_stages = 100

-- plugin i/o ports
function dsp_ioconfig ()
	return
	{
		-- allow any number of I/O as long as port-count matches
		{ audio_in = -1, audio_out = -1},
	}
end

-- plugin control ports
function dsp_params ()
	return
	{
		{ ["type"] = "input", name = "Base Freq", min = 10, max = 1000, default = 100, unit="Hz", logarithmic = true },
		{ ["type"] = "input", name = "Quality", min = 1.0, max = 100.0, default = 8.0, logarithmic = true },
		{ ["type"] = "input", name = "Stages", min = 1.0, max = max_stages, default = 8.0, integer = true },
	}
end


-- plugin instance state
local filters = {} -- the biquad filter instances
local chn = 0 -- configured channel count
local sample_rate = 0 -- configured sample-rate

-- cached control ports (keep track of changed)
local freq = 0
local qual = 0


-- dsp_init is called once when instantiating the plugin
function dsp_init (rate)
	-- remember the sample-rate
	sample_rate = rate
end

-- dsp_configure is called every time when the channel-count
-- changes, and at least once at the beginning.
function dsp_configure (ins, outs)
	assert (ins:n_audio () == outs:n_audio ())

	-- remember audio-channels
	chn = ins:n_audio ()

	-- set up filter instances for all channels
	for c = 1, chn do
		filters[c] = {}
		for i = 1, max_stages do
			filters[c][i] = ARDOUR.DSP.Biquad (sample_rate)
		end
	end
end


-- the actual process function, called every cycle
-- ins, outs are audio-data arrays
--   http://manual.ardour.org/lua-scripting/class_reference/#C:FloatArray
-- n_samples are the number of samples to process
function dsp_run (ins, outs, n_samples)
	-- make sure input and output count matches...
	assert (#ins == #outs)
	-- ...and matches the configured number of channels
	assert (#ins == chn)

	local ctrl = CtrlPorts:array() -- get control parameters as array
	-- ctrl[1] ..  corresponds to the parameters given in in dsp_params()

	-- test if the plugin-parameters have changed
	if freq ~= ctrl[1] or qual ~= ctrl[2] then
		-- remember current settings
		freq = ctrl[1]
		qual = ctrl[2]
		-- re-compute the filter coefficients for all filters
		for c = 1, chn do -- for each channel
			for i = 1, max_stages do -- and for each filter stage
				-- the parameters are    type,  frequency,  quality(bandwidth),  gain
				-- see http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR:DSP:Biquad
				-- for a list of available types, see
				-- http://manual.ardour.org/lua-scripting/class_reference/#ARDOUR.DSP.Biquad.Type
				filters[c][i]:compute (ARDOUR.DSP.BiquadType.Notch, freq * i, qual * i, 0)
			end
		end
	end

	-- limit the number of process stages
	local limit = math.floor (sample_rate / ( 2 * freq )) -- at most up to SR / 2
	local stages = math.floor (ctrl['3']) -- current user-set parameter
	if stages < 1 then stages = 1 end -- at least one stage...
	if stages > max_stages then stages = max_stages end
	if stages > limit then stages = limit end

	-- process all channels
	for c = 1, chn do
		-- when not processing in-place, copy the data from input to output first
		if not ins[c]:sameinstance (outs[c]) then
			ARDOUR.DSP.copy_vector (outs[c], ins[c], n_samples)
		end

		-- run all stages, in-place on the output buffer
		for i = 1, stages do
			filters[c][i]:run (outs[c], n_samples)
		end
	end
end

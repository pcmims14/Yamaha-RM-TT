-- Yamaha RM-TT, Pierce Mims (Vivo Technologies), 10 2026
-- Protocol: RM Series Remote Control Protocol Specifications 3.0.0 (TCP 49280, lines end with LF)

--*** Plugin information ***
--[[ #include "info.lua" ]]

--*** Constants ***

MAX_MICS = 16

-- Choice lists used by more than one parameter
LEVEL_CHOICES = { "Off", "Low", "Medium", "High" }
EQ_TYPE_CHOICES = { "PEQ", "LS 6dB", "LS 12dB", "HS 6dB", "HS 12dB", "HPF", "LPF" } -- LS and HS are low and high shelf, per octave

-- The cards of per mic settings. Each one is switched on by a Yes/No property and drawn on one page.
--   option   the property that has to be Yes for the card to exist
--   columns  the headings over the card's cells; a parameter fills one cell per sub-address
SECTIONS = {
  { id = "Processing", title = "Audio Processing", option = "Audio Processing", page = "Microphone", columns = { "" } },
  { id = "Directivity", title = "Directivity", option = "Directivity", page = "Microphone", columns = { "Beam 1", "Beam 2", "Beam 3", "Beam 4" } },
  { id = "Output", title = "Dante Output", option = "Output Controls", page = "Microphone", columns = { "Output 1", "Output 2" } },
  { id = "Led", title = "LED", option = "LED Controls", page = "Microphone", columns = { "Unmuted", "Muted" } },
  { id = "Meters", title = "Meters", option = "Meters", page = "Microphone", columns = { "Ch 1", "Ch 2" } },
  { id = "Eq", title = "Output EQ", option = "Output EQ", page = "EQ", columns = { "Band 1", "Band 2", "Band 3", "Band 4", "Band 5", "Band 6" } },
}

-- Every parameter the RM-TT exposes, apart from the system mute which the plugin handles itself.
--   id       the control is named this
--   address  the parameter address in the protocol
--   kind     "list"    a choice; the raw value is the position in choices, counted from 0
--            "toggle"  0 or 1 (invert = true when 0 means on)
--            "number"  raw value = control value * scale
--            "level"   a fader in 0.01 dB steps, with -32768 as minus infinity
--            "color"   #RRGGBB, sent as three parameters: address/R, address/G and address/B
--            "meter"   a level meter, one byte per channel
--   cells    how many sub-addresses it has (default 1)
--   axis     which sub-address the cells count along, "x" or "y"; fixed is the value of the other one
--   span     a single cell drawn across the whole card
PARAMS = {
  { section = "Processing", id = "MicGain", label = "Mic Gain", address = "RM:DSPTOP/MicGaintype", kind = "list", choices = { "0 dB", "+7 dB", "+14 dB", "+21 dB" } },
  { section = "Processing", id = "EchoCancel", label = "Echo Cancellation", address = "RM:Mic_Dsp/Aectype", kind = "list", choices = LEVEL_CHOICES },
  { section = "Processing", id = "NoiseReduction", label = "Noise Reduction", address = "RM:Mic_Dsp/Nrtype", kind = "list", choices = LEVEL_CHOICES },
  { section = "Processing", id = "Dereverb", label = "Dereverberation", address = "RM:Mic_Dsp/Derevtype", kind = "list", choices = LEVEL_CHOICES },
  { section = "Processing", id = "Agc", label = "AGC", address = "RM:Mic_Agc/Agctype", kind = "list", choices = { "Off", "Soft", "Hard" } },
  { section = "Processing", id = "AgcSpeed", label = "AGC Speed", address = "RM:Mic_Agc/AgcSpeed", kind = "list", choices = { "Slow", "Fast" } },
  { section = "Processing", id = "Automix", label = "Automix", address = "RM:Automix/Mixtype", kind = "list", choices = { "1 Ch Gating", "2 Ch Gain Sharing", "4 Ch Gain Sharing", "All Mix" } },

  { section = "Directivity", id = "DirectivityMode", label = "Pattern", address = "RM:Mic_Direcctl/Mode", kind = "list", span = true,
    choices = { "Auto Voice Tracking", "Omnidirectional", "Cardioid", "Supercardioid", "Hypercardioid", "Toroid", "Bidirectional" } },
  { section = "Directivity", id = "BeamOn", label = "Beam On", address = "RM:Mic_Direcctl/Ch/On", kind = "toggle", cells = 4, axis = "x" },
  { section = "Directivity", id = "BeamAngle", label = "Angle", address = "RM:Mic_Direcctl/Ch/Angle", kind = "number", unit = "Integer", min = -180, max = 180, scale = 1, cells = 4, axis = "x" },

  { section = "Output", id = "OutputOn", label = "Fader On", address = "RM:NeOut_Fader/Ch/On", kind = "toggle", cells = 2, axis = "x" },
  { section = "Output", id = "OutputLevel", label = "Level", address = "RM:NeOut_Fader/Ch/Level", kind = "level", cells = 2, axis = "x" },
  { section = "Output", id = "OutputMute", label = "Mute", address = "RM:NeOut_Mute/Ch/On", kind = "toggle", invert = true, legend = "Mute", alert = true, cells = 2, axis = "x" },
  { section = "Output", id = "OutputMuteLink", label = "Follow Mic Mute", address = "RM:MicMute/Link/Enable", kind = "toggle", cells = 2, axis = "x" },
  { section = "Output", id = "OutputPatch", label = "Source", address = "RM:DanteOut_Patch/Output/Input", kind = "list", choices = { "Off", "Output 1", "Output 2" }, cells = 2, axis = "x" },
  { section = "Output", id = "OutputMode", label = "Output 2 Processing", address = "RM:DSPTOP/Output2Mode", kind = "list", choices = { "Linear Processing", "Low Latency" }, span = true },

  { section = "Led", id = "LedBrightness", label = "Brightness", address = "RM:Led/Brightness", kind = "list", choices = { "High", "Medium", "Low", "Off" }, span = true },
  { section = "Led", id = "LedPattern", label = "Pattern", address = "RM:Led/Config/Pattern", kind = "list", choices = { "Unlit", "Lit", "1 Flash", "2 Flashes" }, cells = 2, axis = "x" },
  { section = "Led", id = "LedRingColor", label = "Ring Color", address = "RM:Led/Config/Color", kind = "color", cells = 2, axis = "x", fixed = 0 },
  { section = "Led", id = "LedIconColor", label = "Mic Icon Color", address = "RM:Led/Config/Color", kind = "color", cells = 2, axis = "x", fixed = 1 },

  { section = "Meters", id = "MeterAecRef", label = "AEC Reference", address = "RM:AecRefPort", kind = "meter", cells = 2 },
  { section = "Meters", id = "MeterOutput", label = "Output", address = "RM:OutputPort", kind = "meter", cells = 2 },

  { section = "Eq", id = "EqOn", label = "EQ On", address = "RM:NeOut_EQ/Ch/On/On", kind = "toggle" },
  { section = "Eq", id = "EqBypass", label = "Bypass", address = "RM:NeOut_EQ/Ch/Band/Bypass", kind = "toggle", legend = "Bypass", alert = true, cells = 6, axis = "y" },
  { section = "Eq", id = "EqType", label = "Type", address = "RM:NeOut_EQ/Ch/Band/Type", kind = "list", choices = EQ_TYPE_CHOICES, cells = 6, axis = "y" },
  { section = "Eq", id = "EqFrequency", label = "Frequency", address = "RM:NeOut_EQ/Ch/Band/Frequency", kind = "number", unit = "Hz", min = 20, max = 20000, scale = 10, cells = 6, axis = "y" },
  { section = "Eq", id = "EqGain", label = "Gain", address = "RM:NeOut_EQ/Ch/Band/Gain", kind = "number", unit = "dB", min = -18, max = 18, scale = 100, cells = 6, axis = "y" },
  { section = "Eq", id = "EqQ", label = "Q", address = "RM:NeOut_EQ/Ch/Band/Q", kind = "number", unit = "Float", min = 0.1, max = 16, scale = 1000, cells = 6, axis = "y" },
}

-- The clock settings, which the protocol reads and writes as events: RM:Get<event> and RM:Set<event>
--   kind   "text" is sent as typed, "toggle" is sent as Enable or Disable
--   cells  the event name is followed by the cell number (NtpServer1 to NtpServer4)
--   hint   an example of what to type, shown beside the box
CLOCK_FIELDS = {
  { id = "TimeZone", label = "Time Zone (0 to 32)", event = "TimeZone", kind = "text" },
  { id = "DstEnable", label = "Daylight Saving", event = "DstEnable", kind = "toggle" },
  { id = "DstStart", label = "DST Start", event = "DstStartTime", kind = "text", hint = "month=3,week=2,day=0,hour=2" },
  { id = "DstEnd", label = "DST End", event = "DstEndTime", kind = "text", hint = "month=11,week=1,day=0,hour=2" },
  { id = "NtpEnable", label = "NTP", event = "NtpEnable", kind = "toggle" },
  { id = "NtpServer", label = "NTP Server", event = "NtpServer", kind = "text", cells = 4 },
}

--*** Reserved functions ***

-- Define the color of the plugin object in the design
function GetColor(props)
  return { 59, 123, 167 }
end

-- The name that will initially display when dragged into a design
function GetPrettyName(props)
  return "Yamaha RM-TT, version " .. PluginInfo.Version
end

-- Define User configurable Properties of the plugin
function GetProperties()
  local props = {}
  --[[ #include "properties.lua" ]]
  return props
end

-- Optional function to update available properties when properties are altered by the user
function RectifyProperties(props)
  --[[ #include "rectify_properties.lua" ]]
  return props
end

-- Optional function used if plugin has multiple pages
function GetPages(props)
  local pages = {}
  --[[ #include "pages.lua" ]]
  return pages
end

-- Defines the Controls used within the plugin
function GetControls(props)
  local ctrls = {}
  --[[ #include "controls.lua" ]]
  return ctrls
end

-- Layout of controls and graphics for the plugin UI to display
function GetControlLayout(props)
  local layout = {}
  local graphics = {}
  --[[ #include "layout.lua" ]]
  return layout, graphics
end

-- Optional function to define components used within the plugin
function GetComponents(props)
  local components = {}
  --[[ #include "components.lua" ]]
  return components
end

-- Optional function to define pins on the plugin that are not connected to a Control
function GetPins(props)
  local pins = {}
  --[[ #include "pins.lua" ]]
  return pins
end

-- Optional function to define wiring of components used within the plugin
function GetWiring(props)
  local wiring = {}
  --[[ #include "wiring.lua" ]]
  return wiring
end

--*** Design time helper functions ***

-- The cards that exist for the current properties, each with the list of its parameters
function BuildSections(props)
  local list = {}
  for _, section in ipairs(SECTIONS) do
    if props[section.option].Value then
      local entry = { id = section.id, title = section.title, page = section.page, columns = section.columns, params = {} }
      for _, param in ipairs(PARAMS) do
        if param.section == section.id then
          table.insert(entry.params, param)
        end
      end -- for params
      table.insert(list, entry)
    end
  end -- for sections
  return list
end

-- True when the Tools page has something on it
function HasTools(props)
  return props["Clock Settings"].Value or props["Command Line"].Value
end

-- True when any page works on one selected mic, so the mic select buttons are needed
function HasDetail(props)
  return #BuildSections(props) > 0 or HasTools(props)
end

-- The pages, in display order. Control and Setup always exist; the rest depend on the properties.
function GetPageNames(props)
  local names = { "Control" }
  local seen = {}
  for _, section in ipairs(BuildSections(props)) do
    if not seen[section.page] then
      seen[section.page] = true
      table.insert(names, section.page)
    end
  end -- for sections
  if HasTools(props) then
    table.insert(names, "Tools")
  end
  table.insert(names, "Setup")
  return names
end

-- A control with Count 1 is not an array, so always make at least two; the spare is never laid out
function ForceArray(count)
  if count > 1 then
    return count
  end
  return 2
end

--*** Runtime ***
if Controls then
  --[[ #include "runtime.lua" ]]
end

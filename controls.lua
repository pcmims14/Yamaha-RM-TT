local varNumMics = props["Number of Microphones"].Value
local varMicCount = ForceArray(varNumMics)
local tblSections = BuildSections(props)

--*** Control page: group mute ***
table.insert(ctrls, {
  Name = "MuteAll",
  ControlType = "Button",
  ButtonType = "Trigger",
  PinStyle = "Input",
  UserPin = true,
})
table.insert(ctrls, {
  Name = "UnmuteAll",
  ControlType = "Button",
  ButtonType = "Trigger",
  PinStyle = "Input",
  UserPin = true,
})
-- on while every mic is muted; pressing it mutes or unmutes them all
table.insert(ctrls, {
  Name = "GroupMute",
  ControlType = "Button",
  ButtonType = "Toggle",
  PinStyle = "Both",
  UserPin = true,
})
table.insert(ctrls, {
  Name = "SystemHealthy",
  ControlType = "Indicator",
  IndicatorType = "Led",
  PinStyle = "Output",
  UserPin = true,
})
table.insert(ctrls, {
  Name = "AnyMicFault",
  ControlType = "Indicator",
  IndicatorType = "Led",
  PinStyle = "Output",
  UserPin = true,
})
table.insert(ctrls, {
  Name = "GroupStatus",
  ControlType = "Indicator",
  IndicatorType = "Text",
  PinStyle = "Output",
  UserPin = true,
})

--*** Control page: one row per mic ***
table.insert(ctrls, {
  Name = "MicMute",
  ControlType = "Button",
  ButtonType = "Toggle",
  Count = varMicCount,
  PinStyle = "Both",
  UserPin = true,
})
for _, name in ipairs({ "MicMuted", "MicOnline", "MicFault" }) do
  table.insert(ctrls, {
    Name = name,
    ControlType = "Indicator",
    IndicatorType = "Led",
    Count = varMicCount,
    PinStyle = "Output",
    UserPin = true,
  })
end -- for mic LEDs
table.insert(ctrls, {
  Name = "MicStatus",
  ControlType = "Indicator",
  IndicatorType = "Text",
  Count = varMicCount,
  PinStyle = "Output",
  UserPin = true,
})
table.insert(ctrls, {
  Name = "Identify",
  ControlType = "Button",
  ButtonType = "Trigger",
  Count = varMicCount,
  PinStyle = "Input",
  UserPin = true,
})

--*** Setup page ***
table.insert(ctrls, {
  Name = "IPAddress",
  ControlType = "Text",
  Count = varMicCount,
  PinStyle = "None",
  UserPin = false,
})
-- read from each mic once it is connected
for _, name in ipairs({ "DeviceName", "ProductName", "DeviceFirmware", "SerialNumber", "DeviceId" }) do
  table.insert(ctrls, {
    Name = name,
    ControlType = "Indicator",
    IndicatorType = "Text",
    Count = varMicCount,
    PinStyle = "Output",
    UserPin = true,
  })
end -- for device information
table.insert(ctrls, {
  Name = "Status",
  ControlType = "Indicator",
  IndicatorType = "Status",
  PinStyle = "Output",
  UserPin = true,
})

--*** Mic select: the pages below work on one mic at a time ***
if HasDetail(props) then
  table.insert(ctrls, {
    Name = "MicSelect",
    ControlType = "Button",
    ButtonType = "Toggle",
    Count = varMicCount,
    PinStyle = "Both",
    UserPin = true,
  })
  -- on: a change is sent to every mic, not only the selected one
  table.insert(ctrls, {
    Name = "ApplyToAll",
    ControlType = "Button",
    ButtonType = "Toggle",
    PinStyle = "Both",
    UserPin = true,
  })
  table.insert(ctrls, {
    Name = "SelectedName",
    ControlType = "Indicator",
    IndicatorType = "Text",
    PinStyle = "Output",
    UserPin = true,
  })
end -- if mic select

--*** Microphone and EQ pages: one control per parameter, built from PARAMS ***
for _, section in ipairs(tblSections) do
  for _, param in ipairs(section.params) do
    local tblCtrl = {
      Name = param.id,
      Count = param.cells or 1,
      PinStyle = "Both",
      UserPin = true,
    }
    if param.kind == "toggle" then
      tblCtrl.ControlType = "Button"
      tblCtrl.ButtonType = "Toggle"
    elseif param.kind == "number" then
      tblCtrl.ControlType = "Knob"
      tblCtrl.ControlUnit = param.unit
      tblCtrl.Min = param.min
      tblCtrl.Max = param.max
    elseif param.kind == "level" then
      tblCtrl.ControlType = "Knob"
      tblCtrl.ControlUnit = "dB"
      tblCtrl.Min = -100 -- the bottom of the knob is sent as minus infinity
      tblCtrl.Max = 10
    elseif param.kind == "meter" then
      tblCtrl.ControlType = "Indicator"
      tblCtrl.IndicatorType = "Meter"
      tblCtrl.PinStyle = "Output"
    else -- list and color are both typed or picked as text
      tblCtrl.ControlType = "Text"
    end
    table.insert(ctrls, tblCtrl)

    if param.kind == "color" then
      -- a patch of the color beside the box it is typed in
      table.insert(ctrls, {
        Name = param.id .. "Swatch",
        ControlType = "Indicator",
        IndicatorType = "Led",
        Count = param.cells or 1,
        PinStyle = "None",
        UserPin = false,
      })
    end
  end -- for params
end -- for sections

--*** Tools page ***
if props["Clock Settings"].Value then
  for _, field in ipairs(CLOCK_FIELDS) do
    local tblCtrl = {
      Name = field.id,
      Count = field.cells or 1,
      PinStyle = "Both",
      UserPin = true,
    }
    if field.kind == "toggle" then
      tblCtrl.ControlType = "Button"
      tblCtrl.ButtonType = "Toggle"
    else
      tblCtrl.ControlType = "Text"
    end
    table.insert(ctrls, tblCtrl)
  end -- for clock fields
  table.insert(ctrls, {
    Name = "ClockRead",
    ControlType = "Button",
    ButtonType = "Trigger",
    PinStyle = "Input",
    UserPin = true,
  })
end -- if clock

if props["Command Line"].Value then
  table.insert(ctrls, {
    Name = "Command",
    ControlType = "Text",
    PinStyle = "Both",
    UserPin = true,
  })
  -- the selected mic's answer to the command
  table.insert(ctrls, {
    Name = "Response",
    ControlType = "Indicator",
    IndicatorType = "Text",
    PinStyle = "Output",
    UserPin = true,
  })
  table.insert(ctrls, {
    Name = "ListParameters",
    ControlType = "Button",
    ButtonType = "Trigger",
    PinStyle = "None",
    UserPin = false,
  })
end -- if command line

--*** Control aliases ***
MuteAll = Controls.MuteAll
UnmuteAll = Controls.UnmuteAll
GroupMute = Controls.GroupMute
SystemHealthy = Controls.SystemHealthy
AnyMicFault = Controls.AnyMicFault
GroupStatus = Controls.GroupStatus
MicMute = Controls.MicMute
MicMuted = Controls.MicMuted
MicOnline = Controls.MicOnline
MicFault = Controls.MicFault
MicStatus = Controls.MicStatus
Identify = Controls.Identify
IPAddress = Controls.IPAddress
Status = Controls.Status
MicSelect = Controls.MicSelect           -- the select controls are nil when no page works on one mic
ApplyToAll = Controls.ApplyToAll
SelectedName = Controls.SelectedName
ClockRead = Controls.ClockRead           -- nil when Clock Settings is off
Command = Controls.Command               -- the command line controls are nil when Command Line is off
Response = Controls.Response
ListParameters = Controls.ListParameters

--*** Variables ***
NumMics = Properties["Number of Microphones"].Value
ButtonMode = Properties["Mic Mute Button"].Value
HeartbeatSeconds = Properties["Heartbeat Seconds"].Value
IdentifySeconds = Properties["Identify Seconds"].Value
ClockOn = Properties["Clock Settings"].Value
Sections = BuildSections(Properties)     -- the cards that exist for these properties
Mics = {}           -- slot -> everything known about that mic, including its socket
Selected = 1        -- the mic the Microphone, EQ and Tools pages are showing
Lookup = {}         -- parameter address -> the PARAMS entries that use it
MeterLookup = {}    -- meter address -> its PARAMS entry
TickCount = 0
QueueRunning = false
LastStatus = ""
DebugTx = false
DebugRx = false
DebugFunction = false

--*** Objects ***
TickTimer = Timer.New()   -- once a second: start up polling, heartbeat, mute retries, meter renewal
QueueTimer = Timer.New()  -- feeds queued commands to the mics a few at a time

--*** Constants ***
PORT = 49280
MUTE_ADDRESS = "RM:MicMute/All"
RETRY_SECONDS = 2         -- how often an unconfirmed mute is sent again
MAX_RETRIES = 5           -- after this many the mic is marked as a fault
REAPPLY_DELAY = 0.5       -- seconds after a mic comes back before its mute state is put back
QUEUE_SECONDS = 0.05
QUEUE_BURST = 4           -- commands sent to each mic per queue tick
KEEPALIVE_FACTOR = 3      -- either end drops the connection after this many missed heartbeats
HEARTBEAT = "devstatus runmode" -- a heartbeat the mic has to answer, so a dead link is noticed
METER_INTERVAL_MS = 100
METER_RENEW_SECONDS = 5   -- a mic stops sending meters 10 seconds after it was asked
METER_FLOOR = -126        -- dBFS for a meter byte of 00
LEVEL_OFF_RAW = -32768    -- a fader at minus infinity
LEVEL_OFF_DB = -100       -- the bottom of the level knob, which stands for minus infinity
COLOR_CHANNELS = { "R", "G", "B" }
DEVICE_INFO = {           -- devinfo item -> the control that shows it
  devicename = "DeviceName",
  productname = "ProductName",
  version = "DeviceFirmware",
  serialno = "SerialNumber",
  deviceid = "DeviceId",
}
StatusState = { OK = 0, COMPROMISED = 1, FAULT = 2, NOTPRESENT = 3, MISSING = 4, INITIALIZING = 5 }

--*** Functions ***

-- Set the debug flags from the Debug Print property
function SetupDebugPrint()
  local mode = Properties["Debug Print"].Value
  DebugTx = mode == "Tx/Rx" or mode == "All"
  DebugRx = DebugTx
  DebugFunction = mode == "Function Calls" or mode == "All"
end

-- Plugin status. Every change is printed, whatever the debug setting.
function ReportStatus(state, msg)
  local text = state .. ": " .. msg
  if text ~= LastStatus then
    print("Status " .. text)
    LastStatus = text
  end
  Status.Value = StatusState[state]
  Status.String = msg
end

-- Remove spaces from both ends of typed text
function Trim(text)
  local trimmed = tostring(text):gsub("^%s+", "")
  trimmed = trimmed:gsub("%s+$", "")
  return trimmed
end

-- Text made safe to send inside double quotes
function Escape(text)
  local escaped = tostring(text):gsub('[\\"]', "\\%0")
  return escaped
end

-- The name a value is stored under: its address and both sub-addresses
function Key(address, x, y)
  return address .. " " .. x .. " " .. y
end

--*** Sending ***

-- Send one line to a mic now. quiet keeps it out of the debug window.
function Write(mic, line, quiet)
  if not mic.connected then
    return false
  end
  mic.socket:Write(line .. "\n")
  if DebugTx and not quiet then
    print("[Mic " .. mic.index .. "] Tx: " .. line)
  end
  return true
end

-- Send one line to a mic when its turn comes, so a burst of commands does not flood it
function Enqueue(mic, line)
  if not mic.ready then
    return
  end
  table.insert(mic.queue, line)
  if not QueueRunning then
    QueueRunning = true
    QueueTimer:Start(QUEUE_SECONDS)
  end
end

-- Send the next few queued lines to every mic; stop the timer once every queue is empty
function DrainQueues()
  local waiting = false
  for _, mic in ipairs(Mics) do
    for _ = 1, QUEUE_BURST do
      local line = table.remove(mic.queue, 1)
      if line == nil then
        break
      end
      Write(mic, line)
    end -- for burst
    if #mic.queue > 0 then
      waiting = true
    end
  end -- for mics
  if not waiting then
    QueueTimer:Stop()
    QueueRunning = false
  end
end

-- The mics a change on the Microphone, EQ or Tools page goes to
function Targets()
  local list = {}
  if ApplyToAll.Boolean then
    for _, mic in ipairs(Mics) do
      if mic.ready then
        table.insert(list, mic)
      end
    end -- for mics
  elseif Mics[Selected].ready then
    table.insert(list, Mics[Selected])
  end
  return list
end

--*** Parameters: PARAMS entry <-> control <-> protocol value ***

-- The control for one cell of a parameter (suffix picks a companion control, such as "Swatch")
function CellControl(param, cell, suffix)
  local control = Controls[param.id .. (suffix or "")]
  if (param.cells or 1) > 1 then
    return control[cell]
  end
  return control
end

-- The sub-addresses of one cell of a parameter
function SubAddress(param, cell)
  if (param.cells or 1) == 1 then
    return 0, 0
  end
  if param.axis == "y" then
    return param.fixed or 0, cell - 1
  end
  return cell - 1, param.fixed or 0
end

-- The cell of a parameter that a pair of sub-addresses belongs to, or nil when it is not this parameter's
function CellFor(param, x, y)
  local cells = param.cells or 1
  if cells == 1 then
    if x == 0 and y == 0 then
      return 1
    end
    return nil
  end
  local along = x
  local other = y
  if param.axis == "y" then
    along = y
    other = x
  end
  if other ~= (param.fixed or 0) or along >= cells then
    return nil
  end
  return along + 1
end

-- Index every parameter that exists for these properties by its protocol address
function BuildLookup()
  for _, section in ipairs(Sections) do
    for _, param in ipairs(section.params) do
      if param.kind == "meter" then
        MeterLookup[param.address] = param
      elseif param.kind == "color" then
        for _, channel in ipairs(COLOR_CHANNELS) do
          local address = param.address .. "/" .. channel
          Lookup[address] = Lookup[address] or {}
          table.insert(Lookup[address], param)
        end -- for channels
      else
        Lookup[param.address] = Lookup[param.address] or {}
        table.insert(Lookup[param.address], param)
      end
    end -- for params
  end -- for sections
end

-- Run a function for every cell of every parameter that is not a meter
function ForEachCell(func)
  for _, section in ipairs(Sections) do
    for _, param in ipairs(section.params) do
      if param.kind ~= "meter" then
        for cell = 1, param.cells or 1 do
          func(param, cell)
        end -- for cells
      end
    end -- for params
  end -- for sections
end

-- Three color values from typed text such as #FF8000, or nil when it is not a color
function ParseColor(text)
  local r, g, b = Trim(text):match("^#?(%x%x)(%x%x)(%x%x)$")
  if r == nil then
    return nil
  end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

-- Show the selected mic's value for one cell of a parameter
function ShowParam(param, cell)
  local values = Mics[Selected].values
  local control = CellControl(param, cell)
  local x, y = SubAddress(param, cell)

  if param.kind == "color" then
    local swatch = CellControl(param, cell, "Swatch")
    local r = values[Key(param.address .. "/R", x, y)]
    local g = values[Key(param.address .. "/G", x, y)]
    local b = values[Key(param.address .. "/B", x, y)]
    if r == nil and g == nil and b == nil then
      control.String = ""
      swatch.Boolean = false
      return
    end
    local hex = string.format("#%02X%02X%02X", r or 0, g or 0, b or 0)
    control.String = hex
    swatch.Color = hex
    swatch.Boolean = true
    return
  end

  local raw = values[Key(param.address, x, y)]
  if raw == nil then
    -- nothing known yet: a choice goes blank and a toggle goes off; a number keeps what it had
    if param.kind == "list" then
      control.String = ""
    elseif param.kind == "toggle" then
      control.Boolean = false
    end
    return
  end
  if param.kind == "list" then
    control.String = param.choices[raw + 1] or tostring(raw)
  elseif param.kind == "toggle" then
    control.Boolean = (raw == 1) ~= (param.invert == true)
  elseif param.kind == "level" then
    control.Value = math.max(raw / 100, LEVEL_OFF_DB)
  else
    control.Value = raw / param.scale
  end
end

-- Show every value the plugin holds for the selected mic
function ShowAll()
  ForEachCell(ShowParam)
end

-- The protocol value for what a control is showing, or nil when it is not a valid choice
function RawFromControl(param, control)
  if param.kind == "list" then
    for i, choice in ipairs(param.choices) do
      if choice == control.String then
        return i - 1
      end
    end -- for choices
    return nil
  elseif param.kind == "toggle" then
    local on = control.Boolean
    if param.invert then
      on = not on
    end
    return on and 1 or 0
  elseif param.kind == "level" then
    if control.Value <= LEVEL_OFF_DB then
      return LEVEL_OFF_RAW
    end
    return math.floor(control.Value * 100 + 0.5)
  end
  return math.floor(control.Value * param.scale + 0.5)
end

-- A control was changed by hand: send it. The mic's reply is what updates the display.
function SendParam(param, cell)
  if DebugFunction then
    print("SendParam " .. param.id .. " " .. cell)
  end
  local control = CellControl(param, cell)
  local x, y = SubAddress(param, cell)
  local lines = {}
  if param.kind == "color" then
    local r, g, b = ParseColor(control.String)
    if r ~= nil then
      local colors = { R = r, G = g, B = b }
      for _, channel in ipairs(COLOR_CHANNELS) do
        table.insert(lines, "set " .. param.address .. "/" .. channel .. " " .. x .. " " .. y .. " " .. colors[channel])
      end -- for channels
    end
  else
    local raw = RawFromControl(param, control)
    if raw ~= nil then
      table.insert(lines, "set " .. param.address .. " " .. x .. " " .. y .. " " .. raw)
    end
  end

  for _, mic in ipairs(Targets()) do
    for _, line in ipairs(lines) do
      Enqueue(mic, line)
    end -- for lines
  end -- for targets
  if #lines == 0 or not Mics[Selected].ready then
    -- nothing went to the mic on show, so put back what it last reported
    ShowParam(param, cell)
  end
end

-- Ask a mic for every parameter the plugin shows
function SyncMic(mic)
  if DebugFunction then
    print("SyncMic " .. mic.index)
  end
  ForEachCell(function(param, cell)
    local x, y = SubAddress(param, cell)
    if param.kind == "color" then
      for _, channel in ipairs(COLOR_CHANNELS) do
        Enqueue(mic, "get " .. param.address .. "/" .. channel .. " " .. x .. " " .. y)
      end -- for channels
    else
      Enqueue(mic, "get " .. param.address .. " " .. x .. " " .. y)
    end
  end)
end

-- Grey out the selected mic's controls while it cannot be reached
function SetDetailEnabled()
  local disabled = not Mics[Selected].ready
  ForEachCell(function(param, cell)
    CellControl(param, cell).IsDisabled = disabled
  end)
  if ClockOn then
    for _, field in ipairs(CLOCK_FIELDS) do
      for cell = 1, field.cells or 1 do
        ClockControl(field, cell).IsDisabled = disabled
      end -- for cells
    end -- for clock fields
  end
end

--*** Meters: only the selected mic is asked for them ***

function StartMeters()
  local mic = Mics[Selected]
  for address, _ in pairs(MeterLookup) do
    Enqueue(mic, "mtrstart " .. address .. " " .. METER_INTERVAL_MS)
  end -- for meters
end

function StopMeters(mic)
  for address, _ in pairs(MeterLookup) do
    Enqueue(mic, "mtrstop " .. address)
  end -- for meters
end

function ClearMeters()
  for _, param in pairs(MeterLookup) do
    for cell = 1, param.cells do
      CellControl(param, cell).Value = METER_FLOOR
    end -- for cells
  end -- for meters
end

-- NOTIFY mtr <address> [type] hh hh ... : one hex byte per channel, 00 = -126 dBFS, 1 dB a step
function ParseMeter(mic, args)
  if mic.index ~= Selected then
    return
  end
  local address, bytes = args:match("^(%S+)%s*(.*)$")
  local param = MeterLookup[address]
  if param == nil then
    return
  end
  local cell = 0
  for token in bytes:gmatch("%S+") do
    if token:match("^%x%x$") then
      cell = cell + 1
      if cell <= param.cells then
        CellControl(param, cell).Value = tonumber(token, 16) + METER_FLOOR
      end
    end
  end -- for bytes
end

--*** Clock: time zone, daylight saving and NTP, which the protocol carries as events ***

function ClockControl(field, cell)
  if (field.cells or 1) > 1 then
    return Controls[field.id][cell]
  end
  return Controls[field.id]
end

-- The event name for one cell of a clock field: NtpServer has a number on the end, the rest do not
function ClockEvent(field, cell)
  if (field.cells or 1) > 1 then
    return field.event .. cell
  end
  return field.event
end

function ShowClock(field, cell)
  local value = Mics[Selected].clock[ClockEvent(field, cell)] or ""
  local control = ClockControl(field, cell)
  if field.kind == "toggle" then
    control.Boolean = value:lower() == "enable"
  else
    control.String = value
  end
end

function ShowClockAll()
  for _, field in ipairs(CLOCK_FIELDS) do
    for cell = 1, field.cells or 1 do
      ShowClock(field, cell)
    end -- for cells
  end -- for clock fields
end

function SendClock(field, cell)
  local control = ClockControl(field, cell)
  local value = Trim(control.String)
  if field.kind == "toggle" then
    value = control.Boolean and "Enable" or "Disable"
  end
  for _, mic in ipairs(Targets()) do
    Enqueue(mic, "event RM:Set" .. ClockEvent(field, cell) .. ' "' .. Escape(value) .. '"')
  end -- for targets
end

-- Ask the selected mic for every clock setting
function ReadClock()
  for _, field in ipairs(CLOCK_FIELDS) do
    for cell = 1, field.cells or 1 do
      Enqueue(Mics[Selected], "event RM:Get" .. ClockEvent(field, cell) .. ' ""')
    end -- for cells
  end -- for clock fields
end

--*** Mute: what Q-SYS wants (desired) against what each mic reports (actual) ***

-- Send a mic the mute state it should be in
function SendMute(mic)
  if mic.desired == nil or not mic.ready then
    return false
  end
  return Write(mic, "set " .. MUTE_ADDRESS .. " 0 0 " .. (mic.desired and 1 or 0))
end

function SetMicMute(mic, muted)
  if DebugFunction then
    print("SetMicMute " .. mic.index .. " " .. tostring(muted))
  end
  mic.desired = muted
  mic.retries = 0
  mic.muteFailed = false
  SendMute(mic)
  UpdateHealth()
end

-- Mute or unmute every mic. source is a mic that is already in that state, when there is one.
function SetGroupMute(muted, source)
  if DebugFunction then
    print("SetGroupMute " .. tostring(muted))
  end
  for _, mic in ipairs(Mics) do
    mic.desired = muted
    mic.retries = 0
    mic.muteFailed = false
    if mic ~= source then
      SendMute(mic)
    end
  end -- for mics
  UpdateHealth()
end

-- A mic reported its mute state. external is true when the mic changed it without being asked by this plugin.
function MuteReported(mic, muted, external)
  mic.actual = muted
  if mic.desired == nil then
    -- nothing has been commanded yet, so take the mic as it is
    mic.desired = muted
  elseif external and muted ~= mic.desired then
    if ButtonMode == "Mutes All Microphones" then
      SetGroupMute(muted, mic)
    elseif ButtonMode == "Mutes That Microphone" then
      mic.desired = muted
    else
      -- Q-SYS wins: put the mic back
      mic.retries = 0
      SendMute(mic)
    end
  end
  if mic.actual == mic.desired then
    mic.retries = 0
    mic.muteFailed = false
  end
  UpdateHealth()
end

-- Send the mute again to any mic that has not confirmed it, and give up after MAX_RETRIES
function RetryMutes()
  local changed = false
  for _, mic in ipairs(Mics) do
    if mic.ready and mic.desired ~= nil and mic.actual ~= mic.desired then
      if mic.retries < MAX_RETRIES then
        mic.retries = mic.retries + 1
        SendMute(mic)
        Write(mic, "get " .. MUTE_ADDRESS .. " 0 0")
      elseif not mic.muteFailed then
        mic.muteFailed = true
        changed = true
        print("[Mic " .. mic.index .. "] Mute not confirmed after " .. MAX_RETRIES .. " retries")
      end
    end
  end -- for mics
  if changed then
    UpdateHealth()
  end
end

--*** Status ***

-- One mic's status in words, and whether it counts as a fault
function MicState(mic)
  if mic.ip == "" then
    return "No IP address", true
  elseif mic.badAddress then
    return "Bad address", true
  elseif not mic.connected then
    return "Offline", true
  elseif mic.updating then
    return "Updating firmware", true
  elseif not mic.ready then
    return "Starting", true
  elseif mic.muteFailed then
    return "Mute not confirmed", true
  elseif mic.alertLevel == "fault" or mic.alertLevel == "error" then
    return "Alert: " .. (mic.alert ~= "" and mic.alert or mic.alertLevel), true
  elseif mic.alertLevel == "warning" then
    return "Warning: " .. (mic.alert ~= "" and mic.alert or "see the mic"), false
  elseif mic.product ~= "" and mic.product ~= "RM-TT" then
    return "OK, but this is a " .. mic.product, false
  end
  return "OK", false
end

-- Refresh every LED and status line from what is known about the mics
function UpdateHealth()
  local configured = 0
  local online = 0
  local faults = 0
  local muted = 0
  local firstFault = ""
  for i, mic in ipairs(Mics) do
    local text, fault = MicState(mic)
    local showMuted = mic.actual == true
    if mic.desired ~= nil then
      showMuted = mic.desired
    end
    MicStatus[i].String = text
    MicOnline[i].Boolean = mic.ready
    MicFault[i].Boolean = fault
    MicMuted[i].Boolean = mic.actual == true
    MicMute[i].Boolean = showMuted
    if mic.ip ~= "" then
      configured = configured + 1
    end
    if mic.ready then
      online = online + 1
    end
    if showMuted then
      muted = muted + 1
    end
    if fault then
      faults = faults + 1
      if firstFault == "" then
        firstFault = "Mic " .. i .. ": " .. text
      end
    end
  end -- for mics

  SystemHealthy.Boolean = faults == 0
  AnyMicFault.Boolean = faults > 0
  GroupMute.Boolean = muted == NumMics
  if muted == NumMics then
    GroupStatus.String = "All microphones muted"
  elseif muted == 0 then
    GroupStatus.String = "All microphones unmuted"
  else
    GroupStatus.String = muted .. " of " .. NumMics .. " microphones muted"
  end

  if configured == 0 then
    ReportStatus("INITIALIZING", "Type each mic's IP address on the Setup page")
  elseif faults == 0 then
    ReportStatus("OK", online .. " of " .. NumMics .. " microphones online")
  elseif online == 0 then
    ReportStatus("FAULT", "No microphones online")
  else
    local more = ""
    if faults > 1 then
      more = " (and " .. (faults - 1) .. " more)"
    end
    ReportStatus("COMPROMISED", firstFault .. more)
  end
end

-- The line that says which mic the Microphone, EQ and Tools pages are showing
function ShowSelectedName()
  local mic = Mics[Selected]
  local name = Controls.DeviceName[Selected].String
  local text = "Mic " .. Selected
  if name ~= "" then
    text = text .. ": " .. name
  end
  if mic.ip ~= "" then
    text = text .. " (" .. mic.ip .. ")"
  end
  SelectedName.String = text
end

-- Put everything known about the selected mic on the Microphone, EQ and Tools pages
function ShowSelected()
  ShowSelectedName()
  ShowAll()
  ClearMeters()
  if ClockOn then
    ShowClockAll()
  end
  SetDetailEnabled()
end

function SelectMic(index)
  if DebugFunction then
    print("SelectMic " .. index)
  end
  if index ~= Selected then
    StopMeters(Mics[Selected])
  end
  Selected = index
  for k = 1, NumMics do
    MicSelect[k].Boolean = k == index
  end -- for mics
  if Response then
    Response.String = ""
  end
  ShowSelected()
  if Mics[index].ready then
    SyncMic(Mics[index])
    StartMeters()
  end
end

--*** Connection ***

function NewMic(index)
  local mic = {
    index = index,
    ip = "",
    socket = TcpSocket.New(),
    connected = false,  -- the socket is open
    ready = false,      -- the mic has answered that it is in normal run mode
    updating = false,   -- the mic says it is updating its firmware
    desired = nil,      -- the mute state Q-SYS wants; nil until something has set it
    actual = nil,       -- the mute state the mic last reported
    retries = 0,
    muteFailed = false,
    values = {},        -- Key(address, x, y) -> raw value
    clock = {},         -- event name -> text
    queue = {},
    product = "",
    alert = "",
    alertLevel = "none",
    listing = false,    -- List Parameters was pressed, so print what comes back
    lastRx = 0,         -- TickCount when the mic last sent anything
    pings = 0,          -- heartbeats sent that have not been answered yet
    awaitVerb = nil,    -- the first word of a typed command whose answer has not arrived yet
    badAddress = false, -- the socket would not take the typed address
  }
  mic.socket.ReadTimeout = 0
  mic.socket.WriteTimeout = 0
  mic.socket.ReconnectTimeout = 5
  mic.socket.EventHandler = function(socket, event, err)
    SocketEvent(mic, event, err)
  end
  return mic
end

-- Forget everything a mic told us; called whenever its connection is lost
function MicOffline(mic)
  mic.connected = false
  mic.ready = false
  mic.updating = false
  mic.actual = nil
  mic.values = {}
  mic.clock = {}
  mic.queue = {}
  mic.alert = ""
  mic.alertLevel = "none"
  mic.listing = false
  mic.pings = 0
  mic.awaitVerb = nil
  if MicSelect and mic.index == Selected then
    ShowSelected()
  end
  UpdateHealth()
end

-- Connect a mic to the address typed on the Setup page
function Connect(mic)
  local ip = Trim(IPAddress[mic.index].String)
  if DebugFunction then
    print("Connect " .. mic.index .. " " .. ip)
  end
  if mic.ip ~= "" then
    mic.socket:Disconnect()
  end
  mic.ip = ip
  mic.badAddress = false
  mic.product = ""
  for _, name in pairs(DEVICE_INFO) do
    Controls[name][mic.index].String = ""
  end -- for device information
  MicOffline(mic)
  OpenSocket(mic)
end

-- Start connecting. A refused address must not stop the other mics from being set up.
function OpenSocket(mic)
  mic.badAddress = false
  if mic.ip == "" then
    return
  end
  local ok, err = pcall(mic.socket.Connect, mic.socket, mic.ip, PORT)
  if not ok then
    print("[Mic " .. mic.index .. "] Cannot connect to " .. mic.ip .. ": " .. tostring(err))
    mic.badAddress = true
    UpdateHealth()
  end
end

-- The mic has sent nothing for too long. A mic that loses power or network never closes the
-- connection, so the socket would wait indefinitely: drop it and start again.
function Reconnect(mic)
  print("[Mic " .. mic.index .. "] No reply for " .. HeartbeatSeconds * KEEPALIVE_FACTOR .. " seconds, reconnecting")
  mic.socket:Disconnect()
  MicOffline(mic)
  OpenSocket(mic)
end

-- The mic answered that it is running normally, so it will now take commands
function MicReady(mic)
  print("[Mic " .. mic.index .. "] Ready")
  mic.ready = true
  mic.updating = false
  Write(mic, "scpmode keepalive " .. HeartbeatSeconds * KEEPALIVE_FACTOR * 1000)
  Enqueue(mic, "get " .. MUTE_ADDRESS .. " 0 0")
  Enqueue(mic, "devstatus error")
  for item, _ in pairs(DEVICE_INFO) do
    Enqueue(mic, "devinfo " .. item)
  end -- for device information
  SyncMic(mic)

  -- after a power cut or a network drop, put the mic back in the state the room was left in
  if mic.desired ~= nil then
    Timer.CallAfter(function()
      if mic.ready and mic.actual ~= mic.desired then
        SendMute(mic)
      end
    end, REAPPLY_DELAY)
  end

  if MicSelect and mic.index == Selected then
    SetDetailEnabled()
    StartMeters()
  end
  UpdateHealth()
end

function SocketEvent(mic, event, err)
  if event == TcpSocket.Events.Connected then
    print("[Mic " .. mic.index .. "] Connected to " .. mic.ip)
    mic.connected = true
    mic.lastRx = TickCount
    -- the mic may still be starting: ask until it says it is in normal run mode (see Tick)
    Write(mic, "devstatus runmode")
    UpdateHealth()
  elseif event == TcpSocket.Events.Data then
    mic.lastRx = TickCount
    while true do
      local line = mic.socket:ReadLine(TcpSocket.EOL.Any)
      if line == nil then
        break
      end
      ParseLine(mic, line)
    end
  else
    -- Closed, Error, Timeout and Reconnect all mean the mic cannot be reached right now
    if mic.connected or DebugRx then
      print("[Mic " .. mic.index .. "] " .. tostring(event) .. " " .. tostring(err or ""))
    end
    MicOffline(mic)
  end
end

--*** Parsing ***

-- OK|OKm|NOTIFY set|get <address> <x> <y> <value> ["text"]
function ParseValue(mic, head, args)
  local address, x, y, value = args:match("^(%S+)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)")
  if address == nil then
    return
  end
  x = tonumber(x)
  y = tonumber(y)
  value = tonumber(value)
  if address == MUTE_ADDRESS then
    MuteReported(mic, value == 1, head == "NOTIFY")
    return
  end
  mic.values[Key(address, x, y)] = value
  if MicSelect and mic.index == Selected and Lookup[address] then
    for _, param in ipairs(Lookup[address]) do
      local cell = CellFor(param, x, y)
      if cell then
        ShowParam(param, cell)
      end
    end -- for params at this address
  end
end

-- devstatus runmode "normal"|"update"   or   devstatus error "none"|"warning"|"error"|"fault"
function ParseDevStatus(mic, args)
  local item, value = args:match('^(%S+)%s+"(.-)"')
  if item == "runmode" then
    if value == "normal" then
      if not mic.ready then
        MicReady(mic)
      end
    else
      mic.ready = false
      mic.updating = value == "update"
      mic.queue = {}
      UpdateHealth()
    end
  elseif item == "error" then
    mic.alertLevel = value
    if value == "none" then
      mic.alert = ""
    end
    UpdateHealth()
  end
end

-- devinfo <item> "value"
function ParseDevInfo(mic, args)
  local item, value = args:match('^(%S+)%s+"(.-)"')
  local name = DEVICE_INFO[item]
  if name == nil then
    return
  end
  Controls[name][mic.index].String = value
  if item == "productname" then
    mic.product = value
    UpdateHealth()
  end
  if MicSelect and mic.index == Selected and item == "devicename" then
    ShowSelectedName()
  end
end

-- event <id> "data": alerts, firmware updates, and the replies to the clock settings
function ParseEvent(mic, args)
  local id = args:match("^(%S+)") or ""
  local data = args:match('"(.*)"') or ""
  local lower = id:lower()
  if lower == "rm:alert" then
    -- "01:SYSTEM ERROR,fault"
    mic.alert = data:match("^(.*),%a+%s*$") or data
    mic.alertLevel = (data:match(",(%a+)%s*$") or "error"):lower()
    print("[Mic " .. mic.index .. "] Alert " .. data)
    UpdateHealth()
  elseif lower == "rm:firmwareupdatestarted" then
    print("[Mic " .. mic.index .. "] Firmware update started")
    mic.updating = true
    UpdateHealth()
  elseif lower == "rm:firmwareupdatefinished" then
    print("[Mic " .. mic.index .. "] Firmware update finished: " .. data)
    mic.updating = false
    UpdateHealth()
  elseif ClockOn then
    local name = id:match("^RM:[GS]et(%w+)$")
    if name == nil then
      return
    end
    mic.clock[name] = data
    if mic.index == Selected then
      for _, field in ipairs(CLOCK_FIELDS) do
        for cell = 1, field.cells or 1 do
          if ClockEvent(field, cell) == name then
            ShowClock(field, cell)
          end
        end -- for cells
      end -- for clock fields
    end
  end
end

-- prmnum <n> or mtrnum <n>: after List Parameters, ask for each entry in turn
function ParseCount(mic, verb, args)
  if not mic.listing then
    return
  end
  local count = tonumber(args:match("^(%d+)")) or 0
  local query = "prminfo "
  if verb == "mtrnum" then
    query = "mtrinfo "
  end
  print("[Mic " .. mic.index .. "] " .. verb .. " " .. count)
  for i = 0, count - 1 do
    Enqueue(mic, query .. i)
  end -- for entries
end

-- One line from a mic: <OK|OKm|NOTIFY|ERROR> <command> <the rest>
function ParseLine(mic, line)
  local head, verb, args = line:match("^(%S+)%s+(%S+)%s*(.*)$")
  if head == nil then
    return
  end
  if head == "NOTIFY" and verb == "mtr" then
    ParseMeter(mic, args)
    return
  end
  -- the answer to a heartbeat is handled like any other, but kept out of the debug window
  local quiet = false
  if mic.pings > 0 and verb == "devstatus" and args:match("^runmode") then
    mic.pings = mic.pings - 1
    quiet = true
  end
  if DebugRx and not quiet then
    print("[Mic " .. mic.index .. "] Rx: " .. line)
  end
  -- the Response box takes the answer to what was typed in Command, not the plugin's own traffic
  if mic.awaitVerb and head ~= "NOTIFY" and (verb == mic.awaitVerb or head == "ERROR") then
    mic.awaitVerb = nil
    if mic.index == Selected then
      Response.String = line
    end
  end
  if head == "ERROR" then
    -- always worth seeing: the mic refused something
    if not DebugRx then
      print("[Mic " .. mic.index .. "] " .. line)
    end
    if verb == "set" and MicSelect and mic.index == Selected then
      -- the page may now show a value the mic did not take, so read them back
      SyncMic(mic)
    end
  elseif verb == "set" or verb == "get" then
    ParseValue(mic, head, args)
  elseif verb == "devstatus" then
    ParseDevStatus(mic, args)
  elseif verb == "devinfo" then
    ParseDevInfo(mic, args)
  elseif verb == "event" then
    ParseEvent(mic, args)
  elseif verb == "prmnum" or verb == "mtrnum" then
    ParseCount(mic, verb, args)
  elseif (verb == "prminfo" or verb == "mtrinfo") and mic.listing and not DebugRx then
    print("[Mic " .. mic.index .. "] " .. line)
  end
end

--*** Timers ***

-- Once a second
function Tick()
  TickCount = TickCount + 1
  for _, mic in ipairs(Mics) do
    if not mic.connected and mic.ip ~= "" and mic.socket.IsConnected then
      -- a late Closed from an old connection can arrive after the new one opened: the socket is the truth
      mic.connected = true
      mic.lastRx = TickCount
    end
    if mic.connected and TickCount - mic.lastRx >= HeartbeatSeconds * KEEPALIVE_FACTOR then
      Reconnect(mic)
    elseif mic.connected and not mic.ready then
      Write(mic, "devstatus runmode")
    elseif mic.ready and TickCount % HeartbeatSeconds == 0 then
      mic.pings = mic.pings + 1
      Write(mic, HEARTBEAT, true)
    end
  end -- for mics
  if TickCount % RETRY_SECONDS == 0 then
    RetryMutes()
  end
  if MicSelect and TickCount % METER_RENEW_SECONDS == 0 then
    StartMeters()
  end
end

function Initialization()
  SetupDebugPrint()
  print("Yamaha RM-TT plugin version " .. PluginInfo.Version)
  BuildLookup()
  for i = 1, NumMics do
    Mics[i] = NewMic(i)
  end -- for mics

  -- the drop down lists take their choices from PARAMS
  ForEachCell(function(param, cell)
    if param.kind == "list" then
      CellControl(param, cell).Choices = param.choices
    end
  end)

  if MicSelect then
    SelectMic(1)
  end
  for i = 1, NumMics do
    Connect(Mics[i])
  end -- for mics
  TickTimer:Start(1)
end

--*** EventHandlers ***
TickTimer.EventHandler = Tick
QueueTimer.EventHandler = DrainQueues

MuteAll.EventHandler = function()
  SetGroupMute(true)
end

UnmuteAll.EventHandler = function()
  SetGroupMute(false)
end

GroupMute.EventHandler = function(ctl)
  SetGroupMute(ctl.Boolean)
end

for i = 1, NumMics do
  MicMute[i].EventHandler = function(ctl)
    SetMicMute(Mics[i], ctl.Boolean)
  end

  Identify[i].EventHandler = function()
    Write(Mics[i], "identify " .. IdentifySeconds)
  end

  IPAddress[i].EventHandler = function()
    Connect(Mics[i])
  end

  if MicSelect then
    -- pressing the selected mic again keeps it selected
    MicSelect[i].EventHandler = function()
      SelectMic(i)
    end
  end
end -- for mics

ForEachCell(function(param, cell)
  CellControl(param, cell).EventHandler = function()
    SendParam(param, cell)
  end
end)

if ClockOn then
  for _, field in ipairs(CLOCK_FIELDS) do
    for cell = 1, field.cells or 1 do
      ClockControl(field, cell).EventHandler = function()
        SendClock(field, cell)
      end
    end -- for cells
  end -- for clock fields
  ClockRead.EventHandler = ReadClock
end

if Command then
  -- anything the protocol allows, sent as typed
  Command.EventHandler = function()
    local text = Trim(Command.String)
    local sent = false
    if text == "" then
      return
    end
    Response.String = ""
    for i, mic in ipairs(Mics) do
      if mic.connected and (i == Selected or ApplyToAll.Boolean) then
        mic.awaitVerb = text:match("^%S+") -- the answer starts OK or ERROR, then this word
        Write(mic, text)
        sent = true
      end
    end -- for mics
    if not sent then
      Response.String = "Not connected"
    end
  end

  ListParameters.EventHandler = function()
    local mic = Mics[Selected]
    if not mic.ready then
      print("[Mic " .. mic.index .. "] Not connected")
      return
    end
    mic.listing = true
    Enqueue(mic, "prmnum")
    Enqueue(mic, "mtrnum")
  end
end

--*** Initialization ***
Initialization()

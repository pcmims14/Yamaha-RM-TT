-- Test harness for the compiled YamahaRMTT.qplug: runs the design-time functions for several
-- property sets, checks every layout key is a real control, then runs the runtime against mocked
-- Q-SYS objects and simulated RM-TT mics. QPLUG is set by the Python runner.

local failures = 0
local function check(ok, msg)
  if not ok then
    failures = failures + 1
    print("FAIL: " .. msg)
  end
end

local function loadPlugin(env)
  local chunk, err = loadfile(QPLUG, "t", env)
  if not chunk then error(err) end
  chunk()
end

local function newEnv()
  local env = {}
  setmetatable(env, { __index = _G })
  return env
end

local ALL_ON = {
  ["Audio Processing"] = true, ["Directivity"] = true, ["Output Controls"] = true, ["Output EQ"] = true,
  ["LED Controls"] = true, ["Meters"] = true, ["Clock Settings"] = true, ["Command Line"] = true,
}
local ALL_OFF = {}
for name, _ in pairs(ALL_ON) do ALL_OFF[name] = false end

local function with(base, extra)
  local merged = {}
  for k, v in pairs(base) do merged[k] = v end
  for k, v in pairs(extra or {}) do merged[k] = v end
  return merged
end

--*** Design time ***
local function designProps(env, overrides)
  local props = {}
  for _, p in ipairs(env.GetProperties()) do
    props[p.Name] = { Value = p.Value, IsHidden = false }
  end
  props.plugin_show_debug = { Value = false }
  props.page_index = { Value = 1 }
  for name, value in pairs(overrides) do
    check(props[name] ~= nil, "unknown property in test: " .. name)
    props[name].Value = value
  end
  return env.RectifyProperties(props)
end

-- the mic select card is drawn on every page that works on one mic
local function isShared(key)
  return key:match("^MicSelect %d+$") or key == "ApplyToAll" or key == "SelectedName"
end

local function checkDesign(label, overrides)
  local env = newEnv()
  loadPlugin(env)
  local props = designProps(env, overrides)

  local valid = {}
  local counts = {}
  for _, c in ipairs(env.GetControls(props)) do
    check(counts[c.Name] == nil, label .. ": duplicate control " .. c.Name)
    check(c.Name:match("^%u[%w]*$") ~= nil, label .. ": control name not PascalCase: " .. c.Name)
    check(c.ControlType ~= nil, label .. ": no ControlType for " .. c.Name)
    local count = c.Count or 1
    counts[c.Name] = count
    if count > 1 then
      for i = 1, count do valid[c.Name .. " " .. i] = true end
    else
      valid[c.Name] = true
    end
  end

  local laidOut = {}
  local total = 0
  local pages = env.GetPages(props)
  for page, _ in ipairs(pages) do
    props.page_index.Value = page
    local layout, graphics = env.GetControlLayout(props)
    check(type(graphics) == "table" and #graphics > 0, label .. ": graphics missing on page " .. page)
    local right = 0
    for _, g in ipairs(graphics) do
      check(g.Type and g.Position and g.Size, label .. ": incomplete graphic on page " .. page)
      if g.Type == "GroupBox" then right = math.max(right, g.Position[1] + g.Size[1]) end
    end
    local boxes = {}
    for key, item in pairs(layout) do
      total = total + 1
      check(valid[key], label .. ": layout key is not a control: " .. key)
      check(not laidOut[key] or isShared(key), label .. ": control laid out on two pages: " .. key)
      laidOut[key] = true
      check(item.Position and item.Size and item.Style, label .. ": incomplete layout for " .. key)
      check(item.Position[1] >= 0 and item.Position[2] >= 0 and item.Size[1] > 0 and item.Size[2] > 0,
        label .. ": bad geometry for " .. key)
      check(item.Position[1] + item.Size[1] <= right, label .. ": page " .. page .. " control outside its card: " .. key)
      table.insert(boxes, { key = key, x = item.Position[1], y = item.Position[2], w = item.Size[1], h = item.Size[2] })
    end
    for a = 1, #boxes do
      for b = a + 1, #boxes do
        local p, q = boxes[a], boxes[b]
        local apart = p.x + p.w <= q.x or q.x + q.w <= p.x or p.y + p.h <= q.y or q.y + q.h <= p.y
        check(apart, label .. ": page " .. page .. " overlap: " .. p.key .. " and " .. q.key)
      end
    end
  end

  -- every control should be drawn somewhere; a forced spare is the only exception
  local mics = props["Number of Microphones"].Value
  for name, count in pairs(counts) do
    if count == 1 then
      check(laidOut[name], label .. ": control never laid out: " .. name)
    else
      local expect = count
      if count == 2 and mics == 1 and (name:match("^Mic") or name == "Identify" or name == "IPAddress"
          or name == "DeviceName" or name == "ProductName" or name == "DeviceFirmware"
          or name == "SerialNumber" or name == "DeviceId") then
        expect = 1
      end
      for i = 1, expect do
        check(laidOut[name .. " " .. i], label .. ": control never laid out: " .. name .. " " .. i)
      end
    end
  end
  print(string.format("design ok  %-28s %d pages, %3d controls laid out", label, #pages, total))
  return counts, pages
end

local _, defaultPages = checkDesign("defaults", {})
check(#defaultPages == 4, "defaults give Control, Microphone, Tools and Setup")
checkDesign("1 mic", { ["Number of Microphones"] = 1 })
checkDesign("16 mics", { ["Number of Microphones"] = 16 })
local everything, allPages = checkDesign("everything on, 16 mics", with(ALL_ON, { ["Number of Microphones"] = 16 }))
check(#allPages == 5, "everything on gives five pages")
check(everything.EqGain == 6 and everything.BeamAngle == 4 and everything.NtpServer == 4, "arrays sized from PARAMS")
local nothing, minPages = checkDesign("everything off", ALL_OFF)
check(#minPages == 2, "everything off leaves Control and Setup")
check(nothing.MicSelect == nil and nothing.MicGain == nil and nothing.Command == nil, "everything off adds no detail controls")
checkDesign("EQ only", with(ALL_OFF, { ["Output EQ"] = true }))
checkDesign("one card only", with(ALL_OFF, { ["LED Controls"] = true }))
checkDesign("clock only", with(ALL_OFF, { ["Clock Settings"] = true, ["Number of Microphones"] = 9 }))

--*** Runtime ***
local MUTE = "RM:MicMute/All"

-- a simulated mic: answers the protocol the way the specification describes
local function newDevice(name)
  local dev = { name = name, values = {}, log = {}, heartbeats = 0, runmode = "normal", ignoreMute = false, socket = nil }
  function dev:reply(line)
    table.insert(self.socket.rx, line)
    self.socket.EventHandler(self.socket, "DATA")
  end
  function dev:sent(pattern)
    local n = 0
    for _, line in ipairs(self.log) do
      if line:find(pattern, 1, true) then n = n + 1 end
    end
    return n
  end
  function dev:line(line)
    if self.silent then return end        -- powered off without closing the connection
    if line == "" then
      self.heartbeats = self.heartbeats + 1
      return
    end
    table.insert(self.log, line)
    local verb, rest = line:match("^(%S+)%s*(.*)$")
    if verb == "devstatus" and rest == "runmode" then
      if self.runmode then self:reply('OK devstatus runmode "' .. self.runmode .. '"') end
    elseif verb == "devstatus" then
      self:reply('OK devstatus error "none"')
    elseif verb == "devinfo" then
      local info = { devicename = self.name, productname = "RM-TT", version = "3.0.1", serialno = "SN" .. self.name, deviceid = "001" }
      self:reply("OK devinfo " .. rest .. ' "' .. (info[rest] or "") .. '"')
    elseif verb == "get" then
      self:reply("OK get " .. rest .. " " .. (self.values[rest] or 0))
    elseif verb == "set" then
      local key, value = rest:match("^(%S+ %-?%d+ %-?%d+) (%-?%d+)$")
      if key:find(MUTE, 1, true) and self.ignoreMute then return end
      if self.refuse and key:find(self.refuse, 1, true) then
        self:reply("ERROR set InvalidArgument")
        return
      end
      self.values[key] = tonumber(value)
      self:reply("OK set " .. rest .. ' "x"')
    elseif verb == "event" then
      local id = rest:match("^(%S+)")
      if id == "RM:GetTimeZone" then self:reply('OK event RM:GetTimeZone "5"')
      elseif id == "RM:GetNtpServer2" then self:reply('OK event RM:GetNtpServer2 "pool.ntp.org"')
      elseif id == "RM:GetDstEnable" then self:reply('OK event RM:GetDstEnable "Enable"') end
    elseif verb == "prmnum" then
      self:reply("OK prmnum 2")
    elseif verb == "mtrnum" then
      self:reply("OK mtrnum 1")
    else
      self:reply("OK " .. line)
    end
  end
  -- the mic changes something by itself, such as its mute button being pressed
  function dev:notify(key, value)
    self.values[key] = value
    self:reply("NOTIFY set " .. key .. " " .. value .. ' "x"')
  end
  function dev:drop()
    local socket = self.socket
    self.socket = nil
    socket.device = nil
    socket.EventHandler(socket, "CLOSED", "connection lost")
  end
  return dev
end

local function runtimeEnv(overrides, network)
  local env = newEnv()
  loadPlugin(env)
  local props = designProps(env, overrides)

  local function newControl(default)
    return { String = default or "", Boolean = false, Value = 0, IsDisabled = false, Color = "", Choices = {} }
  end
  local controls = {}
  for _, c in ipairs(env.GetControls(props)) do
    local count = c.Count or 1
    if count > 1 then
      controls[c.Name] = {}
      for i = 1, count do controls[c.Name][i] = newControl() end
    else
      controls[c.Name] = newControl()
    end
  end

  local pending = {}
  local sockets = {}
  env.Controls = controls
  env.Properties = props
  env.TcpSocket = {
    Events = { Connected = "CONNECTED", Data = "DATA", Closed = "CLOSED", Error = "ERROR", Timeout = "TIMEOUT", Reconnect = "RECONNECT" },
    EOL = { Any = "ANY" },
    New = function()
      local socket = { rx = {} }
      function socket:Connect(ip, port)
        check(port == 49280, "connects on port 49280")
        if ip == "not an address" then error("bad address") end
        self.ip = ip
        self:attach()
      end
      -- what the real socket does by itself when the mic is reachable
      function socket:attach()
        local dev = network[self.ip]
        if dev and dev.socket == nil then
          dev.socket = self
          self.device = dev
          self.EventHandler(self, "CONNECTED")
        end
      end
      function socket:Disconnect()
        if self.device then
          self.device.socket = nil
          self.device = nil
        end
      end
      function socket:Write(data)
        local dev = self.device
        if dev == nil then return end
        for line in data:gmatch("([^\n]*)\n") do dev:line(line) end
      end
      function socket:ReadLine()
        return table.remove(self.rx, 1)
      end
      table.insert(sockets, socket)
      return socket
    end,
  }
  env.Timer = {
    CallAfter = function(fn) table.insert(pending, fn) end,
    New = function()
      return { Start = function(self) self.running = true end, Stop = function(self) self.running = false end }
    end,
  }
  env.print = function() end            -- keep the runtime quiet; failures are reported by check()

  -- let queued commands and delayed calls run until nothing is waiting
  local function settle()
    local busy = true
    while busy do
      busy = false
      while env.QueueRunning do
        env.QueueTimer.EventHandler()
        busy = true
      end
      if #pending > 0 then
        local run = pending
        pending = {}
        for _, fn in ipairs(run) do fn() end
        busy = true
      end
    end
  end
  local function tick(seconds)
    for _ = 1, seconds do
      env.TickTimer.EventHandler()
      settle()
    end
  end
  return env, controls, settle, tick, sockets
end

local function press(control, state)
  control.Boolean = state
  if control.EventHandler then control.EventHandler(control) end
end

local function edit(control, text)
  control.String = text
  if control.EventHandler then control.EventHandler(control) end
end

local function turn(control, value)
  control.Value = value
  if control.EventHandler then control.EventHandler(control) end
end

do
  -- two mics on the network, three configured: the third never answers
  local a, b = newDevice("TableA"), newDevice("TableB")
  local network = { ["10.10.0.61"] = a, ["10.10.0.62"] = b }
  local env, c, settle, tick, sockets = runtimeEnv(with(ALL_ON, { ["Number of Microphones"] = 3 }), network)
  loadPlugin(env)
  settle()

  check(c.Status.Value == 5, "status is initializing before any IP is typed, got " .. c.Status.Value)
  check(c.MicStatus[1].String == "No IP address", "mic 1 status before setup: " .. c.MicStatus[1].String)
  check(c.MicGain.IsDisabled == true, "detail controls are greyed out while the mic is offline")
  check(#c.MicGain.Choices == 4 and c.EqType[3].Choices[1] == "PEQ", "drop down lists are filled from PARAMS")

  a.values["RM:Mic_Direcctl/Ch/Angle 2 0"] = 180
  a.values["RM:Led/Config/Color/R 1 0"] = 255
  a.values["RM:NeOut_Mute/Ch/On 0 0"] = 1
  a.values["RM:NeOut_Mute/Ch/On 1 0"] = 0
  a.values["RM:NeOut_Fader/Ch/Level 0 0"] = -650
  a.values["RM:NeOut_Fader/Ch/Level 1 0"] = -32768
  a.values["RM:NeOut_EQ/Ch/Band/Frequency 0 4"] = 31500
  a.values["RM:NeOut_EQ/Ch/Band/Q 0 4"] = 700
  edit(c.IPAddress[1], " 10.10.0.61 ")
  edit(c.IPAddress[2], "10.10.0.62")
  edit(c.IPAddress[3], "10.10.0.63")
  settle()

  check(a:sent("scpmode keepalive 30000") == 1, "keepalive is three heartbeats")
  check(c.MicOnline[1].Boolean and c.MicOnline[2].Boolean and not c.MicOnline[3].Boolean, "two mics online")
  check(c.DeviceName[1].String == "TableA" and c.ProductName[2].String == "RM-TT" and c.DeviceFirmware[1].String == "3.0.1", "device information read")
  check(c.SerialNumber[2].String == "SNTableB" and c.DeviceId[1].String == "001", "serial number and unit id read")
  check(c.MicStatus[1].String == "OK" and c.MicStatus[3].String == "Offline", "mic status: " .. c.MicStatus[1].String .. " / " .. c.MicStatus[3].String)
  check(c.Status.Value == 1 and c.Status.String == "Mic 3: Offline", "compromised with one mic missing: " .. c.Status.String)
  check(c.AnyMicFault.Boolean and not c.SystemHealthy.Boolean, "health LEDs with one mic missing")
  check(c.SelectedName.String == "Mic 1: TableA (10.10.0.61)", "selected name: " .. c.SelectedName.String)
  check(c.MicGain.IsDisabled == false, "detail controls enabled once the mic is ready")

  -- the selected mic's values are shown
  check(c.MicGain.String == "0 dB", "mic gain shown: " .. c.MicGain.String)
  check(c.BeamAngle[3].Value == 180 and c.BeamAngle[1].Value == 0, "beam 3 angle shown")
  check(c.LedRingColor[2].String == "#FF0000" and c.LedRingColorSwatch[2].Color == "#FF0000", "muted ring color shown: " .. c.LedRingColor[2].String)
  check(c.LedIconColor[2].String == "#000000", "icon color is a separate parameter")
  check(c.OutputMute[1].Boolean == false and c.OutputMute[2].Boolean == true, "output mute is inverted: 0 means muted")
  check(c.OutputLevel[1].Value == -6.5 and c.OutputLevel[2].Value == -100, "output levels shown, minus infinity at the bottom")
  check(c.EqFrequency[5].Value == 3150 and c.EqQ[5].Value == 0.7, "EQ band 5 shown: " .. c.EqFrequency[5].Value)

  -- changing a control sends the right value to the selected mic only
  edit(c.MicGain, "+14 dB")
  turn(c.BeamAngle[2], -90)
  press(c.OutputMute[1], true)
  turn(c.OutputLevel[1], -100)
  turn(c.EqGain[6], 4.5)
  turn(c.EqFrequency[1], 80)
  edit(c.LedRingColor[1], "00ff80")
  edit(c.LedIconColor[2], "#FF8000")
  settle()
  check(a.values["RM:DSPTOP/MicGaintype 0 0"] == 2, "mic gain sent")
  check(a.values["RM:Mic_Direcctl/Ch/Angle 1 0"] == -90, "beam 2 angle sent")
  check(a.values["RM:NeOut_Mute/Ch/On 0 0"] == 0, "output 1 mute sent inverted")
  check(a.values["RM:NeOut_Fader/Ch/Level 0 0"] == -32768, "bottom of the level knob is minus infinity")
  check(a.values["RM:NeOut_EQ/Ch/Band/Gain 0 5"] == 450, "EQ band 6 gain sent")
  check(a.values["RM:NeOut_EQ/Ch/Band/Frequency 0 0"] == 800, "EQ band 1 frequency sent")
  check(a.values["RM:Led/Config/Color/G 0 0"] == 255 and a.values["RM:Led/Config/Color/B 0 0"] == 128, "ring color sent as three values")
  check(a.values["RM:Led/Config/Color/R 1 1"] == 255 and a.values["RM:Led/Config/Color/G 1 1"] == 128, "icon color uses y = 1")
  check(c.LedRingColor[1].String == "#00FF80", "typed color tidied: " .. c.LedRingColor[1].String)
  check(b.values["RM:DSPTOP/MicGaintype 0 0"] == nil, "the other mic is left alone")

  -- something that is not a color or a choice is put back
  edit(c.LedRingColor[1], "purple")
  check(c.LedRingColor[1].String == "#00FF80", "bad color put back")
  edit(c.MicGain, "loud")
  check(c.MicGain.String == "+14 dB", "bad choice put back")

  -- a change made at the mic appears on the page
  a:notify("RM:Mic_Dsp/Nrtype 0 0", 3)
  check(c.NoiseReduction.String == "High", "noise reduction follows the mic")
  b:notify("RM:Mic_Dsp/Nrtype 0 0", 1)
  check(c.NoiseReduction.String == "High", "another mic's change does not show on this one")

  -- apply to all
  press(c.ApplyToAll, true)
  edit(c.EchoCancel, "Low")
  settle()
  check(a.values["RM:Mic_Dsp/Aectype 0 0"] == 1 and b.values["RM:Mic_Dsp/Aectype 0 0"] == 1, "apply to all reaches both mics")
  press(c.ApplyToAll, false)

  -- meters: only from the selected mic
  check(a:sent("mtrstart RM:OutputPort 100") >= 1 and b:sent("mtrstart") == 0, "meters asked of the selected mic only")
  a:reply("NOTIFY mtr RM:OutputPort level 7e 42")
  check(c.MeterOutput[1].Value == 0 and c.MeterOutput[2].Value == -60, "meter bytes are dBFS: " .. c.MeterOutput[2].Value)
  a:reply("NOTIFY mtr RM:AecRefPort 00 10 20 30")
  check(c.MeterAecRef[2].Value == -110, "meter without a type word, extra channels ignored")
  local before = a:sent("mtrstart RM:OutputPort")
  tick(5)
  check(a:sent("mtrstart RM:OutputPort") == before + 1, "meters renewed every five seconds")

  -- select the second mic
  press(c.MicSelect[2], true)
  settle()
  check(c.MicSelect[2].Boolean and not c.MicSelect[1].Boolean, "mic 2 selected")
  check(a:sent("mtrstop RM:OutputPort") == 1, "meters stopped on the mic that was left")
  check(c.NoiseReduction.String == "Low" and c.MeterOutput[1].Value == -126, "page shows mic 2, meters cleared")
  press(c.MicSelect[2], false)
  check(c.MicSelect[2].Boolean, "the selected mic stays selected when pressed again")

  -- clock and command line
  press(c.ClockRead, true)
  settle()
  check(c.TimeZone.String == "5" and c.NtpServer[2].String == "pool.ntp.org" and c.DstEnable.Boolean, "clock read from the mic")
  edit(c.NtpServer[1], 'time "a"')
  press(c.NtpEnable, true)
  settle()
  check(b:sent('event RM:SetNtpServer1 "time \\"a\\""') == 1, "NTP server sent, quotes escaped")
  check(b:sent('event RM:SetNtpEnable "Enable"') == 1, "NTP enable sent")
  edit(c.Command, "devinfo category")
  check(b:sent("devinfo category") == 1 and c.Response.String == 'OK devinfo category ""', "command line: " .. c.Response.String)
  press(c.ListParameters, true)
  settle()
  check(b:sent("prminfo 0") == 1 and b:sent("prminfo 1") == 1 and b:sent("prminfo 2") == 0 and b:sent("mtrinfo 0") == 1, "list parameters walks the mic's list")

  -- identify
  press(c.Identify[1], true)
  check(a:sent("identify 10") == 1, "identify for the property's seconds")

  --*** Group mute ***
  check(not c.GroupMute.Boolean and c.GroupStatus.String == "All microphones unmuted", "unmuted at start: " .. c.GroupStatus.String)
  press(c.MuteAll, true)
  settle()
  check(a.values[MUTE .. " 0 0"] == 1 and b.values[MUTE .. " 0 0"] == 1, "mute all reaches both mics")
  check(c.MicMuted[1].Boolean and c.MicMuted[2].Boolean and not c.MicMuted[3].Boolean, "muted LEDs follow the mics' replies")
  check(c.GroupMute.Boolean and c.MicMute[3].Boolean, "group shows muted, including the offline mic's intent")
  check(c.GroupStatus.String == "All microphones muted", "group status: " .. c.GroupStatus.String)

  -- someone presses the mute button on mic 1: every mic follows
  a:notify(MUTE .. " 0 0", 0)
  settle()
  check(b.values[MUTE .. " 0 0"] == 0, "mic button unmutes the other mic")
  check(not c.GroupMute.Boolean and not c.MicMute[2].Boolean, "group shows unmuted after the mic button")

  -- one mic on its own
  press(c.MicMute[2], true)
  settle()
  check(b.values[MUTE .. " 0 0"] == 1 and a.values[MUTE .. " 0 0"] == 0, "single mic mute")
  check(c.GroupStatus.String == "1 of 3 microphones muted", "mixed group status: " .. c.GroupStatus.String)

  -- a mic that loses power comes back in the state the room was left in
  press(c.GroupMute, true)
  settle()
  a:drop()
  check(not c.MicOnline[1].Boolean and c.MicStatus[1].String == "Offline", "dropped mic shows offline")
  a.values[MUTE .. " 0 0"] = 0            -- it reboots unmuted
  a.runmode = nil                         -- and does not answer while it starts
  sockets[1]:attach()
  settle()
  check(c.MicStatus[1].String == "Starting", "mic that has not answered run mode: " .. c.MicStatus[1].String)
  a.runmode = "normal"
  tick(1)
  check(c.MicOnline[1].Boolean and a.values[MUTE .. " 0 0"] == 1, "mute put back after the mic returns")
  check(c.MicMuted[1].Boolean and c.DeviceName[1].String == "TableA", "mic 1 back and confirmed")

  -- a mic that will not take the mute is retried, then marked as a fault
  b.ignoreMute = true
  press(c.UnmuteAll, true)
  settle()
  check(c.MicMuted[2].Boolean and not c.MicMute[2].Boolean, "mic 2 still muted, but asked to unmute")
  local sentBefore = b:sent("set " .. MUTE)
  tick(9)
  check(b:sent("set " .. MUTE) == sentBefore + 4 and not c.MicFault[2].Boolean, "four retries in nine seconds, no fault yet")
  tick(4)
  check(b:sent("set " .. MUTE) == sentBefore + 5, "five retries, then no more")
  check(c.MicFault[2].Boolean and c.MicStatus[2].String == "Mute not confirmed", "fault after the retries: " .. c.MicStatus[2].String)
  b.ignoreMute = false
  press(c.UnmuteAll, true)
  settle()
  check(not c.MicFault[2].Boolean and not c.MicMuted[2].Boolean, "fault clears when the mute is confirmed")

  -- alerts and firmware updates
  a:reply('NOTIFY event RM:Alert "01:SYSTEM ERROR,fault"')
  check(c.MicFault[1].Boolean and c.MicStatus[1].String == "Alert: 01:SYSTEM ERROR", "alert shown: " .. c.MicStatus[1].String)
  a:reply('NOTIFY devstatus error "none"')
  check(not c.MicFault[1].Boolean and c.MicStatus[1].String == "OK", "alert cleared")
  a.runmode = "update"
  a:reply('NOTIFY devstatus runmode "update"')
  check(c.MicStatus[1].String == "Updating firmware" and not c.MicOnline[1].Boolean, "update mode: " .. c.MicStatus[1].String)
  tick(2)
  check(c.MicStatus[1].String == "Updating firmware", "still updating while the mic says so")
  a.runmode = "normal"
  tick(1)
  check(c.MicOnline[1].Boolean and c.MicStatus[1].String == "OK", "back to normal after the update")

  -- heartbeat: one the mic has to answer. The Response box keeps the answer to what was typed,
  -- whatever else the plugin sends (mic 2 is the one selected).
  edit(c.Command, "devinfo category")
  local beats = b:sent("devstatus runmode")
  tick(20)
  check(b:sent("devstatus runmode") == beats + 2, "heartbeat every ten seconds")
  check(c.Response.String == 'OK devinfo category ""', "response box keeps the typed command's answer: " .. c.Response.String)

  -- a change the mic refuses is read back, so the page does not show something the mic does not have
  b.refuse = "RM:Mic_Dsp/Nrtype"
  edit(c.NoiseReduction, "High")
  settle()
  check(c.NoiseReduction.String == "Low", "refused change put back: " .. c.NoiseReduction.String)
  b.refuse = nil

  -- a mic that loses power without closing the connection is noticed and reconnected
  a.silent = true
  network["10.10.0.61"] = nil
  tick(5)
  check(c.MicOnline[1].Boolean, "a quiet mic is not dropped straight away")
  tick(40)
  check(not c.MicOnline[1].Boolean and c.MicStatus[1].String == "Offline", "silent mic marked offline: " .. c.MicStatus[1].String)
  check(a.socket == nil and not c.SystemHealthy.Boolean, "its connection was dropped")
  a.silent = false
  network["10.10.0.61"] = a
  sockets[1]:attach()
  settle()
  check(c.MicOnline[1].Boolean and c.MicStatus[1].String == "OK", "and it comes back: " .. c.MicStatus[1].String)
  tick(60)
  check(c.MicOnline[1].Boolean and c.MicOnline[2].Boolean, "mics that answer their heartbeats stay online")

  -- all three online
  network["10.10.0.63"] = newDevice("TableC")
  network["10.10.0.63"].values[MUTE .. " 0 0"] = 1 -- it starts muted; the room is unmuted
  sockets[3]:attach()
  settle()
  check(c.Status.Value == 0 and c.Status.String == "3 of 3 microphones online", "all online: " .. c.Status.String)
  check(c.SystemHealthy.Boolean and not c.AnyMicFault.Boolean, "healthy with every mic online")
  check(network["10.10.0.63"].values[MUTE .. " 0 0"] == 0, "a mic that joins late is given the group state")

  -- an address the socket will not take is reported, and does not disturb the other mics
  edit(c.IPAddress[3], "not an address")
  check(c.MicStatus[3].String == "Bad address" and c.MicFault[3].Boolean, "bad address: " .. c.MicStatus[3].String)
  check(c.MicOnline[1].Boolean and c.MicOnline[2].Boolean, "other mics unaffected by a bad address")
  edit(c.IPAddress[3], "10.10.0.63")
  settle()
  check(c.MicStatus[3].String == "OK", "corrected address connects: " .. c.MicStatus[3].String)

  -- clearing an address disconnects
  edit(c.IPAddress[3], "")
  check(c.MicStatus[3].String == "No IP address" and network["10.10.0.63"].socket == nil, "blank address disconnects")
end

do
  -- the other two mic button modes, with everything optional switched off
  local function modeEnv(mode)
    local a, b = newDevice("A"), newDevice("B")
    local env, c, settle, tick = runtimeEnv(with(ALL_OFF, { ["Mic Mute Button"] = mode }), { ["1.1.1.1"] = a, ["1.1.1.2"] = b })
    loadPlugin(env)
    edit(c.IPAddress[1], "1.1.1.1")
    edit(c.IPAddress[2], "1.1.1.2")
    settle()
    press(c.MuteAll, true)
    settle()
    return a, b, c, settle, tick
  end

  local a, b, c, settle = modeEnv("Mutes That Microphone")
  check(c.Status.Value == 0 and c.MicSelect == nil, "runs with every optional page off")
  a:notify(MUTE .. " 0 0", 0)
  settle()
  check(b.values[MUTE .. " 0 0"] == 1 and not c.MicMute[1].Boolean and c.MicMute[2].Boolean, "That Microphone: only that mic changes")

  a, b, c, settle = modeEnv("Overridden by Q-SYS")
  a:notify(MUTE .. " 0 0", 0)
  settle()
  check(a.values[MUTE .. " 0 0"] == 1 and c.MicMute[1].Boolean and c.MicMuted[1].Boolean, "Overridden: the mic is put back")
end

if failures == 0 then
  print("ALL TESTS PASSED")
else
  print(failures .. " FAILURE(S)")
  error("tests failed")
end

table.insert(props, {
  Name = "Number of Microphones",
  Type = "integer",
  Min = 1,
  Max = MAX_MICS,
  Value = 2,
})
table.insert(props, {
  Name = "Mic Mute Button",
  Type = "enum",
  -- what happens when someone presses the mute button on a mic
  Choices = { "Mutes All Microphones", "Mutes That Microphone", "Overridden by Q-SYS" },
  Value = "Mutes All Microphones",
})
table.insert(props, {
  Name = "Audio Processing",
  Type = "boolean",
  Value = true, -- mic gain, echo cancellation, noise reduction, dereverberation, AGC, automix
})
table.insert(props, {
  Name = "Directivity",
  Type = "boolean",
  Value = true, -- pickup pattern and the four beams
})
table.insert(props, {
  Name = "Output Controls",
  Type = "boolean",
  Value = false, -- Dante output faders, mutes and routing
})
table.insert(props, {
  Name = "Output EQ",
  Type = "boolean",
  Value = false, -- six band EQ, on its own page
})
table.insert(props, {
  Name = "LED Controls",
  Type = "boolean",
  Value = true, -- brightness, and the pattern and color for muted and unmuted
})
table.insert(props, {
  Name = "Meters",
  Type = "boolean",
  Value = true,
})
table.insert(props, {
  Name = "Clock Settings",
  Type = "boolean",
  Value = false, -- time zone, daylight saving and NTP
})
table.insert(props, {
  Name = "Command Line",
  Type = "boolean",
  Value = true, -- a box to send any protocol command, and a button to list the mic's parameters
})
table.insert(props, {
  Name = "Heartbeat Seconds",
  Type = "integer",
  Min = 5,
  Max = 60,
  Value = 10,
})
table.insert(props, {
  Name = "Identify Seconds",
  Type = "integer",
  Min = 1,
  Max = 60,
  Value = 10,
})
table.insert(props, {
  Name = "Debug Print",
  Type = "enum",
  Choices = { "None", "Tx/Rx", "Function Calls", "All" },
  Value = "None",
})

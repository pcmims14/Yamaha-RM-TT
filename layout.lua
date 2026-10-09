local tblPages = GetPageNames(props)
local currentPage = tblPages[props["page_index"].Value] or tblPages[1]
local varNumMics = props["Number of Microphones"].Value
local tblSections = BuildSections(props)
local varW = 1
local varH = 2

--*** Palette: Vivo navy and blue on pale cards ***
local tblNavy = { 32, 67, 91 }
local tblBlue = { 59, 123, 167 }
local tblRed = { 208, 62, 56 }
local tblGreen = { 52, 168, 83 }
local tblAmber = { 224, 150, 32 }
local tblWhite = { 255, 255, 255 }
local tblCard = { 246, 248, 250 }
local tblLine = { 204, 212, 219 }
local tblText = { 45, 55, 65 }
local tblSoft = { 110, 122, 132 }
local tblOff = { 150, 160, 168 }
local tblPale = { 190, 210, 225 }

--*** Primitives shared by every page ***
local varXi = 10                        -- page origin
local varYi = 10
local varHeaderH = 38                   -- the navy title bar
local varGap = 10                       -- between cards
local varPad = 10                       -- card edge to its content
local varTitleH = 26                    -- room for a card title
local varRowH = 20                      -- a row of controls
local varRowStep = 24                   -- row height plus gap
local varColGap = 6                     -- between columns
local varTop = varYi + varHeaderH + varGap -- where the first card starts

--*** Drawing helpers ***

-- The navy title bar across the top of a page
local function drawHeader(varWidth)
  table.insert(graphics, {
    Type = "GroupBox",
    Fill = tblNavy,
    StrokeColor = tblNavy,
    StrokeWidth = 1,
    CornerRadius = 8,
    Position = { varXi, varYi },
    Size = { varWidth, varHeaderH },
  })
  table.insert(graphics, {
    Type = "Label",
    Text = "Yamaha RM-TT",
    FontSize = 16,
    IsBold = true,
    HTextAlign = "Left",
    Color = tblWhite,
    Position = { varXi + 14, varYi },
    Size = { varWidth // 2, varHeaderH },
  })
  table.insert(graphics, {
    Type = "Label",
    Text = currentPage,
    FontSize = 11,
    HTextAlign = "Right",
    Color = tblPale,
    Position = { varXi + varWidth // 2, varYi },
    Size = { varWidth - varWidth // 2 - 14, varHeaderH },
  })
end

-- A titled card
local function drawCard(title, varX, varY, varCardW, varCardH)
  table.insert(graphics, {
    Type = "GroupBox",
    Text = title,
    FontSize = 12,
    IsBold = true,
    HTextAlign = "Left",
    Color = tblNavy,
    Fill = tblCard,
    StrokeColor = tblLine,
    StrokeWidth = 1,
    CornerRadius = 8,
    Position = { varX, varY },
    Size = { varCardW, varCardH },
  })
end

-- One row of text
local function drawLabel(text, varX, varY, varLabelW, align, tblColor)
  table.insert(graphics, {
    Type = "Label",
    Text = text,
    FontSize = 11,
    HTextAlign = align or "Left",
    Color = tblColor or tblText,
    Position = { varX, varY },
    Size = { varLabelW, varRowH },
  })
end

-- A text box, or with style "ComboBox" a drop down list
local function drawText(name, prettyName, varX, varY, varTextW, varTextH, style, align)
  layout[name] = {
    PrettyName = prettyName,
    Style = style or "Text",
    Color = tblWhite,
    TextColor = tblText,
    StrokeColor = tblLine,
    StrokeWidth = 1,
    CornerRadius = 3,
    FontSize = 11,
    HTextAlign = align or "Center",
    WordWrap = varTextH > varRowH,
    Position = { varX, varY },
    Size = { varTextW, varTextH },
  }
end

-- A button. A toggle is grey when off and the given color when on; a trigger is always the given color.
local function drawButton(name, prettyName, legend, buttonStyle, varX, varY, varBtnW, varBtnH, tblColor)
  local tblRest = tblOff
  if buttonStyle == "Trigger" then
    tblRest = tblColor
  end
  layout[name] = {
    PrettyName = prettyName,
    Style = "Button",
    ButtonStyle = buttonStyle,
    ButtonVisualStyle = "Flat",
    Legend = legend,
    Color = tblColor,
    OffColor = tblRest,
    UnlinkOffColor = true,
    TextColor = tblWhite,
    FontSize = 11,
    CornerRadius = 4,
    Margin = 1,
    Position = { varX, varY },
    Size = { varBtnW, varBtnH },
  }
end

-- An LED centered in a cell
local function drawLed(name, prettyName, varX, varY, varCellW, tblColor)
  layout[name] = {
    PrettyName = prettyName,
    Style = "Led",
    Color = tblColor,
    Margin = 3,
    Position = { varX + (varCellW - varRowH) // 2, varY },
    Size = { varRowH, varRowH },
  }
end

-- The width of a table: its columns plus the gaps between them
local function tableWidth(tblCols)
  local varTotal = varColGap * (#tblCols - 1)
  for _, col in ipairs(tblCols) do
    varTotal = varTotal + col.w
  end
  return varTotal
end

-- A card holding one row per mic. cellFunc(k, col, x, y) draws one cell. Returns the card height.
local function drawMicTable(title, tblCols, varY, cellFunc)
  local varCardW = varPad * 2 + tableWidth(tblCols)
  local varCardH = varTitleH + varRowStep * (varNumMics + 1) - (varRowStep - varRowH) + varPad
  drawCard(title, varXi, varY, varCardW, varCardH)
  local varX = varXi + varPad
  for _, col in ipairs(tblCols) do
    drawLabel(col.title, varX, varY + varTitleH, col.w, "Center", tblSoft)
    for k = 1, varNumMics do
      cellFunc(k, col, varX, varY + varTitleH + varRowStep * k)
    end -- for mics
    varX = varX + col.w + varColGap
  end -- for columns
  return varCardH
end

-- The mic select card used by every page that works on one mic. Returns the card height.
local function drawSelector(varY, varCardW)
  local tblBtn = { 40, 24 }
  local varBtnGap = 4
  local varPerRow = (varCardW - varPad * 2 + varBtnGap) // (tblBtn[varW] + varBtnGap)
  local varRows = (varNumMics + varPerRow - 1) // varPerRow
  local varLineY = varY + varTitleH + (tblBtn[varH] + varBtnGap) * varRows + 2
  local varCardH = varLineY - varY + varRowH + varPad
  local tblApply = { 110, varRowH }
  local varShowing = 60
  drawCard("Microphone", varXi, varY, varCardW, varCardH)
  for k = 1, varNumMics do
    local varCol = (k - 1) % varPerRow
    local varRow = (k - 1) // varPerRow
    drawButton("MicSelect " .. k, "Select~Microphone " .. k, tostring(k), "Toggle",
      varXi + varPad + (tblBtn[varW] + varBtnGap) * varCol, varY + varTitleH + (tblBtn[varH] + varBtnGap) * varRow,
      tblBtn[varW], tblBtn[varH], tblBlue)
  end -- for mics
  drawLabel("Showing", varXi + varPad, varLineY, varShowing, "Left", tblSoft)
  drawText("SelectedName", "Select~Showing", varXi + varPad + varShowing, varLineY,
    varCardW - varPad * 2 - varShowing - tblApply[varW] - varColGap, varRowH, "Text", "Left")
  drawButton("ApplyToAll", "Select~Apply To All", "Apply To All", "Toggle",
    varXi + varCardW - varPad - tblApply[varW], varLineY, tblApply[varW], tblApply[varH], tblAmber)
  return varCardH
end

if currentPage == "Control" then
  --*** Primitives ***
  local tblBig = { 112, 34 }            -- the group mute buttons
  local tblLedLabel = { 96, varRowH }
  local tblCols = {
    { id = "Number", title = "#", w = 26 },
    { id = "Name", title = "Name", w = 190 },
    { id = "Mute", title = "Mute", w = 72 },
    { id = "Muted", title = "Muted", w = 50 },
    { id = "Online", title = "Online", w = 50 },
    { id = "Fault", title = "Fault", w = 50 },
    { id = "Status", title = "Status", w = 200 },
    { id = "Identify", title = "", w = 72 },
  }

  --*** Derived ***
  local varPageW = varPad * 2 + tableWidth(tblCols)
  local varGroupH = varTitleH + tblBig[varH] + varColGap + varRowH + varPad
  local varBtnY = varTop + varTitleH
  local varBtnX = varXi + varPad
  local varLedY = varBtnY + (tblBig[varH] - varRowH) // 2
  local varLedText = 2                  -- LED to its label
  local varLedStep = varRowH + varLedText + tblLedLabel[varW] + varColGap
  local varLedX = varXi + varPageW - varPad - varLedStep * 2 + varColGap

  drawHeader(varPageW)

  --*** Group mute ***
  drawCard("All Microphones", varXi, varTop, varPageW, varGroupH)
  drawButton("MuteAll", "Group~Mute All", "Mute All", "Trigger", varBtnX, varBtnY, tblBig[varW], tblBig[varH], tblRed)
  drawButton("UnmuteAll", "Group~Unmute All", "Unmute All", "Trigger", varBtnX + tblBig[varW] + varColGap, varBtnY, tblBig[varW], tblBig[varH], tblBlue)
  drawButton("GroupMute", "Group~Mute", "Muted", "Toggle", varBtnX + (tblBig[varW] + varColGap) * 2, varBtnY, tblBig[varW], tblBig[varH], tblRed)
  drawLed("SystemHealthy", "Group~System Healthy", varLedX, varLedY, varRowH, tblGreen)
  drawLabel("System Healthy", varLedX + varRowH + varLedText, varLedY, tblLedLabel[varW])
  drawLed("AnyMicFault", "Group~Any Mic Fault", varLedX + varLedStep, varLedY, varRowH, tblRed)
  drawLabel("Mic Fault", varLedX + varLedStep + varRowH + varLedText, varLedY, tblLedLabel[varW])
  drawText("GroupStatus", "Group~Status", varBtnX, varBtnY + tblBig[varH] + varColGap, varPageW - varPad * 2, varRowH, "Text", "Left")

  --*** One row per mic ***
  drawMicTable("Microphones", tblCols, varTop + varGroupH + varGap, function(k, col, varX, varY)
    local varPretty = "Microphone " .. k .. "~"
    if col.id == "Number" then
      drawLabel(tostring(k), varX, varY, col.w, "Center", tblSoft)
    elseif col.id == "Name" then
      drawText("DeviceName " .. k, varPretty .. "Name", varX, varY, col.w, varRowH, "Text", "Left")
    elseif col.id == "Mute" then
      drawButton("MicMute " .. k, varPretty .. "Mute", "Mute", "Toggle", varX, varY, col.w, varRowH, tblRed)
    elseif col.id == "Muted" then
      drawLed("MicMuted " .. k, varPretty .. "Muted", varX, varY, col.w, tblRed)
    elseif col.id == "Online" then
      drawLed("MicOnline " .. k, varPretty .. "Online", varX, varY, col.w, tblGreen)
    elseif col.id == "Fault" then
      drawLed("MicFault " .. k, varPretty .. "Fault", varX, varY, col.w, tblRed)
    elseif col.id == "Status" then
      drawText("MicStatus " .. k, varPretty .. "Status", varX, varY, col.w, varRowH, "Text", "Left")
    elseif col.id == "Identify" then
      drawButton("Identify " .. k, varPretty .. "Identify", "Identify", "Trigger", varX, varY, col.w, varRowH, tblBlue)
    end
  end)

elseif currentPage == "Setup" then
  --*** Primitives ***
  local varStatusH = 32
  local tblCols = {
    { id = "Number", title = "#", w = 26 },
    { id = "IPAddress", title = "IP Address", pretty = "IP Address", w = 120 },
    { id = "ProductName", title = "Model", pretty = "Model", w = 80 },
    { id = "DeviceFirmware", title = "Firmware", pretty = "Firmware", w = 80 },
    { id = "SerialNumber", title = "Serial Number", pretty = "Serial Number", w = 120 },
    { id = "DeviceId", title = "Unit ID", pretty = "Unit ID", w = 60 },
  }

  --*** Derived ***
  local varPageW = varPad * 2 + tableWidth(tblCols)
  local varStatusCardH = varTitleH + varStatusH + varPad

  drawHeader(varPageW)

  --*** Where each mic is, and what it says it is ***
  local varTableH = drawMicTable("Microphones", tblCols, varTop, function(k, col, varX, varY)
    if col.id == "Number" then
      drawLabel(tostring(k), varX, varY, col.w, "Center", tblSoft)
    else
      drawText(col.id .. " " .. k, "Microphone " .. k .. "~" .. col.pretty, varX, varY, col.w, varRowH)
    end
  end)

  --*** Plugin status ***
  local varStatusY = varTop + varTableH + varGap
  drawCard("Plugin Status", varXi, varStatusY, varPageW, varStatusCardH)
  layout["Status"] = {
    PrettyName = "Status",
    Style = "Text",
    FontSize = 12,
    Position = { varXi + varPad, varStatusY + varTitleH },
    Size = { varPageW - varPad * 2, varStatusH },
  }
  drawLabel("Remote control uses TCP port 49280. A mic accepts up to eight controllers at once.",
    varXi + varPad, varStatusY + varStatusCardH + varColGap, varPageW - varPad * 2, "Left", tblSoft)

elseif currentPage == "Tools" then
  --*** Primitives ***
  local tblLabel = { 130, varRowH }
  local varContentW = 456
  local tblShort = { 90, varRowH }      -- a toggle, or a short number
  local tblRead = { 130, varRowH }
  local varResponseH = varRowH * 2 + 4

  --*** Derived ***
  local varPageW = varPad * 2 + tblLabel[varW] + varContentW
  local varX1 = varXi + varPad
  local varX2 = varX1 + tblLabel[varW]
  local varY = varTop

  drawHeader(varPageW)
  varY = varY + drawSelector(varY, varPageW) + varGap

  --*** Clock: time zone, daylight saving and NTP ***
  if props["Clock Settings"].Value then
    local varRows = 1 -- the Read button
    for _, field in ipairs(CLOCK_FIELDS) do
      varRows = varRows + (field.cells or 1)
    end
    local varCardH = varTitleH + varRowStep * varRows - (varRowStep - varRowH) + varPad
    drawCard("Clock", varXi, varY, varPageW, varCardH)
    local varRowY = varY + varTitleH
    for _, field in ipairs(CLOCK_FIELDS) do
      local varCells = field.cells or 1
      for c = 1, varCells do
        local varName = field.id
        local varText = field.label
        if varCells > 1 then
          varName = field.id .. " " .. c
          varText = field.label .. " " .. c
        end
        drawLabel(varText, varX1, varRowY, tblLabel[varW])
        if field.kind == "toggle" then
          drawButton(varName, "Clock~" .. varText, "Enabled", "Toggle", varX2, varRowY, tblShort[varW], tblShort[varH], tblBlue)
        elseif field.hint then
          -- room for an example of what to type beside the box
          drawText(varName, "Clock~" .. varText, varX2, varRowY, varContentW // 2, varRowH, "Text", "Left")
          drawLabel(field.hint, varX2 + varContentW // 2 + varColGap, varRowY, varContentW // 2 - varColGap, "Left", tblSoft)
        elseif varCells > 1 then
          drawText(varName, "Clock~" .. varText, varX2, varRowY, varContentW, varRowH, "Text", "Left")
        else
          drawText(varName, "Clock~" .. varText, varX2, varRowY, tblShort[varW], varRowH)
        end
        varRowY = varRowY + varRowStep
      end -- for cells
    end -- for clock fields
    drawButton("ClockRead", "Clock~Read From Mic", "Read From Mic", "Trigger", varX2, varRowY, tblRead[varW], tblRead[varH], tblBlue)
    varY = varY + varCardH + varGap
  end -- if clock

  --*** Command line: send anything the protocol allows ***
  if props["Command Line"].Value then
    local varCardH = varTitleH + varRowStep * 2 + varResponseH + varPad
    drawCard("Command Line", varXi, varY, varPageW, varCardH)
    local varRowY = varY + varTitleH
    drawLabel("Command", varX1, varRowY, tblLabel[varW])
    drawText("Command", "Command Line~Command", varX2, varRowY, varContentW, varRowH, "Text", "Left")
    varRowY = varRowY + varRowStep
    drawLabel("Response", varX1, varRowY, tblLabel[varW])
    drawText("Response", "Command Line~Response", varX2, varRowY, varContentW, varResponseH, "Text", "Left")
    varRowY = varRowY + varResponseH + (varRowStep - varRowH)
    drawButton("ListParameters", "Command Line~List Parameters", "List Parameters", "Trigger", varX2, varRowY, tblRead[varW], tblRead[varH], tblBlue)
    drawLabel("Prints the mic's own parameter and meter list to the debug window.",
      varX2 + tblRead[varW] + varColGap, varRowY, varContentW - tblRead[varW] - varColGap, "Left", tblSoft)
  end -- if command line

else
  --*** Microphone and EQ pages: the cards of the selected mic's settings, built from PARAMS ***

  --*** Primitives ***
  local tblLabel = { 130, varRowH }
  local varCellStep = 76                -- one cell plus its gap
  local varMinCells = 4                 -- a card is never narrower than this many cells

  --*** Derived ***
  local tblPageSections = {}
  local varMaxCells = varMinCells
  for _, section in ipairs(tblSections) do
    if section.page == currentPage then
      table.insert(tblPageSections, section)
      if #section.columns > varMaxCells then
        varMaxCells = #section.columns
      end
    end
  end -- for sections
  local varContentW = varCellStep * varMaxCells
  local varCardW = varPad * 2 + tblLabel[varW] + varContentW
  local varFlowCols = 1
  if #tblPageSections > 1 then
    varFlowCols = 2
  end
  local varPageW = varCardW * varFlowCols + varGap * (varFlowCols - 1)

  drawHeader(varPageW)
  local varFlowTop = varTop + drawSelector(varTop, varPageW) + varGap

  -- The height of one card: a title, the column headings if it has any, and a row per parameter
  local function sectionHeight(section)
    local varRows = #section.params
    if #section.columns > 1 then
      varRows = varRows + 1
    end
    return varTitleH + varRowStep * varRows - (varRowStep - varRowH) + varPad
  end

  -- One card: a label down the left, then each parameter's cells under the column headings
  local function drawSection(section, varX, varY)
    local varNumCols = #section.columns
    local varStep = varContentW // varNumCols
    local varX1 = varX + varPad
    local varX2 = varX1 + tblLabel[varW]
    local varRowY = varY + varTitleH - varRowStep
    local varHeadings = varNumCols > 1    -- the column headings are still to be drawn
    drawCard(section.title, varX, varY, varCardW, sectionHeight(section))

    for _, param in ipairs(section.params) do
      local varCells = param.cells or 1
      varRowY = varRowY + varRowStep
      if varHeadings and (varCells > 1 or not param.span) then
        -- the headings sit straight above the first row that uses the columns
        for c = 1, varNumCols do
          drawLabel(section.columns[c], varX2 + varStep * (c - 1), varRowY, varStep - varColGap, "Center", tblSoft)
        end -- for column headings
        varHeadings = false
        varRowY = varRowY + varRowStep
      end
      drawLabel(param.label, varX1, varRowY, tblLabel[varW] - varColGap)
      for c = 1, varCells do
        local varName = param.id
        local varPretty = section.title .. "~" .. param.label
        if varCells > 1 then
          varName = param.id .. " " .. c
          varPretty = varPretty .. " " .. section.columns[c]
        end
        local varCellX = varX2 + varStep * (c - 1)
        local varCellW = varStep - varColGap
        if param.span then
          varCellW = varContentW - varColGap
        end

        if param.kind == "toggle" then
          local tblColor = tblBlue
          if param.alert then
            tblColor = tblRed
          end
          drawButton(varName, varPretty, param.legend or "On", "Toggle", varCellX, varRowY, varCellW, varRowH, tblColor)
        elseif param.kind == "list" then
          drawText(varName, varPretty, varCellX, varRowY, varCellW, varRowH, "ComboBox")
        elseif param.kind == "meter" then
          layout[varName] = {
            PrettyName = varPretty,
            Style = "Meter",
            MeterStyle = "Level",
            ShowTextbox = false,
            Position = { varCellX, varRowY + 2 },
            Size = { varCellW, varRowH - 4 },
          }
        elseif param.kind == "color" then
          -- the typed color, then a patch of it
          drawText(varName, varPretty, varCellX, varRowY, varCellW - varRowH - 2, varRowH)
          layout[param.id .. "Swatch " .. c] = {
            PrettyName = varPretty .. " Swatch",
            Style = "Led",
            Margin = 2,
            Position = { varCellX + varCellW - varRowH, varRowY },
            Size = { varRowH, varRowH },
          }
        else -- number and level: a knob shown as a box to type in
          drawText(varName, varPretty, varCellX, varRowY, varCellW, varRowH)
        end
      end -- for cells
    end -- for params
  end

  --*** Flow: each card goes under the shorter column ***
  local tblColumnY = {}
  for c = 1, varFlowCols do
    tblColumnY[c] = varFlowTop
  end
  for _, section in ipairs(tblPageSections) do
    local varColumn = 1
    for c = 2, varFlowCols do
      if tblColumnY[c] < tblColumnY[varColumn] then
        varColumn = c
      end
    end
    drawSection(section, varXi + (varCardW + varGap) * (varColumn - 1), tblColumnY[varColumn])
    tblColumnY[varColumn] = tblColumnY[varColumn] + sectionHeight(section) + varGap
  end -- for sections
end -- if page

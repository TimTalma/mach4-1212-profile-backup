--=============================================================================
-- File:        ATC_ToolTracking.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Populate and control ATC tools page rows and actions.
--=============================================================================

local ATC_Config = require("ATC_Config")
local ATC_Pockets = require("ATC_Pockets")
local ATC_Load = require("ATC_Load")
local ATC_Unload = require("ATC_Unload")
local ATC_Runtime = require("ATC_Runtime")

local ATC_ToolTracking = {}

--=============================================================================
-- Constants
--=============================================================================
local DISPLAY_ROWS = 9
local PAGE_ONE_START = 1
local PAGE_TWO_START = 10
local TOOLTABLE_PATH = "C:\\Mach4Hobby\\Profiles\\1212\\ToolTables\\tooltable.tls"
local EMPTY_TOOL_NUMBER = 0
local EMPTY_HEIGHT_TEXT = "-0.0000"
local EMPTY_DESC_TEXT = "(Empty)"
local PROFILE_SECTION_PERSISTENT_DROS = "PersistentDROs"
local CTRL_GAGE_X = "droGageX"
local CTRL_GAGE_Y = "droGageY"
local KEY_GAGE_BLOCK_TOOL = "droGageBlockT"
local CTRL_GAGE_BLOCK_TOOL_PRIMARY = "droGageBlockT"
local CTRL_GAGE_BLOCK_TOOL_MIRROR = "droGageBlockT(1)"

--=============================================================================
-- Private state
--=============================================================================
local m_firstVisiblePocket = PAGE_ONE_START
local m_missingControlLogged = {}

--=============================================================================
-- Helpers
--=============================================================================

--=========================================================================
-- Function: Log
-- Purpose:  Write status/history messages for tools page actions.
--=========================================================================
local function Log(msg)
    ATC_Runtime.Log("ATC_TOOLS: " .. tostring(msg))
end

--=========================================================================
-- Function: GetRowControlName
-- Purpose:  Build one row control name from prefix and row index.
--=========================================================================
local function GetRowControlName(prefix, rowIndex)
    return tostring(prefix) .. tostring(rowIndex)
end

--=========================================================================
-- Function: GetControlWindow
-- Purpose:  Return wx window handle for named control.
--=========================================================================
local function GetControlWindow(controlName)
    return wx.wxFindWindowByName(controlName)
end

--=========================================================================
-- Function: LogMissingControlOnce
-- Purpose:  Log missing control warning only once per control name.
--=========================================================================
local function LogMissingControlOnce(controlName)
    if m_missingControlLogged[controlName] == true then
        return
    end
    m_missingControlLogged[controlName] = true
    Log("Control not found: " .. tostring(controlName))
end

--=========================================================================
-- Function: SetControlText
-- Purpose:  Set control text using screen API.
--=========================================================================
local function SetControlText(controlName, textValue)
    local value = tostring(textValue or "")
    local prop = (string.sub(tostring(controlName), 1, 4) == "lbl_") and "Label" or "Value"

    if type(scr) ~= "table" or type(scr.SetProperty) ~= "function" then
        return false
    end

    local ok = pcall(function()
        scr.SetProperty(controlName, prop, value)
    end)

    return ok
end

--=========================================================================
-- Function: GetControlText
-- Purpose:  Read control text using scr API with wx fallback.
--=========================================================================
local function GetControlText(controlName)
    if type(scr) == "table" and type(scr.GetProperty) == "function" then
        local ok, value = pcall(function()
            return scr.GetProperty(controlName, "Value")
        end)
        if ok and value ~= nil then
            return tostring(value)
        end
    end

    local wnd = GetControlWindow(controlName)
    if wnd == nil then
        LogMissingControlOnce(controlName)
        return nil
    end

    local ok, value = pcall(function()
        if wnd.GetValue ~= nil then
            return wnd:GetValue()
        end
        if wnd.GetLabel ~= nil then
            return wnd:GetLabel()
        end
        return nil
    end)

    if ok and value ~= nil then
        return tostring(value)
    end

    return nil
end

--=========================================================================
-- Function: SetButtonEnabled
-- Purpose:  Enable or disable a row button by control name.
--=========================================================================
local function SetButtonEnabled(controlName, isEnabled)
    local wnd = GetControlWindow(controlName)
    if wnd == nil then
        LogMissingControlOnce(controlName)
        return false
    end
    local ok = pcall(function()
        wnd:Enable(isEnabled == true)
    end)
    return ok
end

--=========================================================================
-- Function: FormatHeight
-- Purpose:  Convert numeric length to display string with four decimals.
--=========================================================================
local function FormatHeight(lengthValue)
    local n = tonumber(lengthValue)
    if n == nil then
        return EMPTY_HEIGHT_TEXT
    end
    return string.format("%.4f", n)
end

--=========================================================================
-- Function: FormatCoordinate
-- Purpose:  Convert numeric coordinate value to four-decimal DRO text.
--=========================================================================
local function FormatCoordinate(value)
    local n = tonumber(value)
    if n == nil then
        return "0.0000"
    end
    return string.format("%.4f", n)
end

--=========================================================================
-- Function: ReadProfileString
-- Purpose:  Read one string value from the active Mach4 profile.
--=========================================================================
local function ReadProfileString(sectionName, keyName, defaultValue)
    local inst = ATC_Runtime.GetInstance()
    local fallback = tostring(defaultValue or "")

    local ok, value = pcall(function()
        return mc.mcProfileGetString(inst, tostring(sectionName), tostring(keyName), fallback)
    end)

    if ok and value ~= nil then
        return tostring(value)
    end

    return fallback
end

--=========================================================================
-- Function: WriteProfileString
-- Purpose:  Persist one string value into the active Mach4 profile.
--=========================================================================
local function WriteProfileString(sectionName, keyName, valueText)
    local inst = ATC_Runtime.GetInstance()
    local value = tostring(valueText or "")

    local ok = pcall(function()
        mc.mcProfileWriteString(inst, tostring(sectionName), tostring(keyName), value)
    end)

    return ok
end

--=========================================================================
-- Function: LoadToolSetterLocationControl
-- Purpose:  Load one persisted tool-setter coordinate into its DRO.
--=========================================================================
local function LoadToolSetterLocationControl(controlName)
    local savedText = ReadProfileString(PROFILE_SECTION_PERSISTENT_DROS, controlName, "0.0000")
    SetControlText(controlName, FormatCoordinate(savedText))
end

--=========================================================================
-- Function: SaveToolSetterLocationControl
-- Purpose:  Validate, persist, and normalize one tool-setter coordinate.
--=========================================================================
local function SaveToolSetterLocationControl(controlName, newValue)
    local numericValue = tonumber(newValue)
    if numericValue == nil then
        local currentText = GetControlText(controlName)
        SetControlText(controlName, FormatCoordinate(currentText))
        Log("Ignored invalid tool setter value for " .. tostring(controlName))
        return false
    end

    local formatted = FormatCoordinate(numericValue)
    SetControlText(controlName, formatted)

    if not WriteProfileString(PROFILE_SECTION_PERSISTENT_DROS, controlName, formatted) then
        Log("Failed to persist tool setter value for " .. tostring(controlName))
        return false
    end

    return true
end

--=========================================================================
-- Function: SetToolSetterHeightDisplays
-- Purpose:  Push one saved tool-setter height value to both screen DROs.
--=========================================================================
local function SetToolSetterHeightDisplays(value)
    local formatted = FormatCoordinate(value)
    SetControlText(CTRL_GAGE_BLOCK_TOOL_PRIMARY, formatted)
    SetControlText(CTRL_GAGE_BLOCK_TOOL_MIRROR, formatted)
    return formatted
end

--=========================================================================
-- Function: LoadToolSetterHeightDisplays
-- Purpose:  Load persisted tool-setter height and mirror it on both screens.
--=========================================================================
local function LoadToolSetterHeightDisplays()
    local savedText = ReadProfileString(PROFILE_SECTION_PERSISTENT_DROS, KEY_GAGE_BLOCK_TOOL, "0.0000")
    SetToolSetterHeightDisplays(savedText)
end

--=========================================================================
-- Function: SaveToolSetterHeight
-- Purpose:  Validate, persist, and mirror the shared tool-setter height.
--=========================================================================
local function SaveToolSetterHeight(newValue)
    local numericValue = tonumber(newValue)
    if numericValue == nil then
        local currentText = GetControlText(CTRL_GAGE_BLOCK_TOOL_PRIMARY)
        if currentText == nil then
            currentText = GetControlText(CTRL_GAGE_BLOCK_TOOL_MIRROR)
        end
        SetToolSetterHeightDisplays(currentText)
        Log("Ignored invalid tool setter height value.")
        return false
    end

    local formatted = SetToolSetterHeightDisplays(numericValue)
    if not WriteProfileString(PROFILE_SECTION_PERSISTENT_DROS, KEY_GAGE_BLOCK_TOOL, formatted) then
        Log("Failed to persist tool setter height value.")
        return false
    end

    return true
end

--=========================================================================
-- Function: ParseToolTableTls
-- Purpose:  Read tool heights/descriptions from tooltable.tls file.
--=========================================================================
local function ParseToolTableTls()
    local tools = {}
    local file = io.open(TOOLTABLE_PATH, "r")
    if file == nil then
        Log("Unable to open tool table: " .. TOOLTABLE_PATH)
        return tools
    end

    local currentTool = nil
    for rawLine in file:lines() do
        local line = tostring(rawLine or "")
        local toolNumText = line:match("^%[Tool(%d+)%]$")
        if toolNumText ~= nil then
            currentTool = tonumber(toolNumText)
            if currentTool ~= nil then
                tools[currentTool] = tools[currentTool] or {}
            end
        elseif currentTool ~= nil then
            local key, value = line:match("^([%a_]+)%=(.*)$")
            if key == "Length" then
                tools[currentTool].Length = tonumber(value)
            elseif key == "Desc" then
                tools[currentTool].Desc = tostring(value or "")
            end
        end
    end

    file:close()
    return tools
end

--=========================================================================
-- Function: GetDisplayToolNumber
-- Purpose:  Map stored pocket tool value to display value for UI row.
--=========================================================================
local function GetDisplayToolNumber(storedTool)
    local t = tonumber(storedTool)
    if t == nil or t <= 0 then
        return EMPTY_TOOL_NUMBER
    end
    return math.floor(t + 0.5)
end

--=========================================================================
-- Function: GetPocketToolNumber
-- Purpose:  Read one pocket's assigned tool for tools page display.
--=========================================================================
local function GetPocketToolNumber(pocketId)
    local p = ATC_Pockets.GetPocketData(pocketId)
    if type(p) ~= "table" then
        return EMPTY_TOOL_NUMBER
    end
    return GetDisplayToolNumber(p.tool)
end

--=========================================================================
-- Function: NormalizeRowToolInput
-- Purpose:  Parse entered tool number text into non-negative integer.
--=========================================================================
local function NormalizeRowToolInput(rawText)
    local n = tonumber(rawText)
    if n == nil then
        return EMPTY_TOOL_NUMBER
    end
    n = math.floor(n + 0.5)
    if n < 0 then
        n = EMPTY_TOOL_NUMBER
    end
    return n
end

--=========================================================================
-- Function: StorePocketToolAssignment
-- Purpose:  Persist entered tool number assignment to pocket data file.
--=========================================================================
local function StorePocketToolAssignment(pocketId, displayToolNumber)
    local storeValue = ATC_Config.Pockets.UnassignedTool
    local toolValue = tonumber(displayToolNumber) or EMPTY_TOOL_NUMBER
    if toolValue > 0 then
        storeValue = toolValue
    end

    ATC_Pockets.LoadPockets(false)

    if toolValue > 0 then
        local pocketCount = ATC_Pockets.GetPocketCount()
        for id = 1, pocketCount do
            local p = ATC_Pockets.GetPocketData(id)
            if type(p) == "table" then
                local existing = tonumber(p.tool) or ATC_Config.Pockets.UnassignedTool
                if existing == toolValue and id ~= pocketId then
                    ATC_Pockets.SetPocketTool(id, ATC_Config.Pockets.UnassignedTool)
                end
            end
        end
    end

    ATC_Pockets.SetPocketTool(pocketId, storeValue)
end

--=========================================================================
-- Function: UpdateRowButtons
-- Purpose:  Apply button enable rules for a row tool/spindle state.
--=========================================================================
local function UpdateRowButtons(rowIndex, toolNumber, currentTool, pocketTaught)
    local getName = GetRowControlName("btn_GetTool_", rowIndex)
    local returnName = GetRowControlName("btn_ReturnTool_", rowIndex)
    local setHeightName = GetRowControlName("btn_SetHeight_", rowIndex)

    local hasTool = (tonumber(toolNumber) or 0) > 0
    local isCurrent = hasTool and ((tonumber(currentTool) or 0) == (tonumber(toolNumber) or -1))

    if pocketTaught ~= true then
        SetButtonEnabled(getName, false)
        SetButtonEnabled(returnName, false)
        SetButtonEnabled(setHeightName, false)
        return
    end

    local enableGet = hasTool
    local enableReturn = false
    local enableSetHeight = hasTool

    if isCurrent then
        enableGet = false
        enableReturn = true
    end

    if not hasTool then
        enableGet = false
        enableReturn = false
        enableSetHeight = false
    end

    SetButtonEnabled(getName, enableGet)
    SetButtonEnabled(returnName, enableReturn)
    SetButtonEnabled(setHeightName, enableSetHeight)
end

--=========================================================================
-- Function: PopulateRow
-- Purpose:  Populate one visible row from pocket assignment and tool data.
--=========================================================================
local function PopulateRow(rowIndex, pocketId, toolsByNumber, currentTool)
    local pocketLabelName = GetRowControlName("lbl_PocketNumber_", rowIndex)
    local toolDroName = GetRowControlName("dro_ToolNumber_", rowIndex)
    local heightLabelName = GetRowControlName("lbl_Height_", rowIndex)
    local descTextName = GetRowControlName("txt_Description_", rowIndex)

    local pocket = ATC_Pockets.GetPocketData(pocketId)
    local pocketTaught = false
    local toolNum = EMPTY_TOOL_NUMBER

    if type(pocket) == "table" then
        pocketTaught = (pocket.taught == true)
        toolNum = GetDisplayToolNumber(pocket.tool)
    end

    local heightText = EMPTY_HEIGHT_TEXT
    local descText = EMPTY_DESC_TEXT

    if toolNum > 0 then
        local toolData = toolsByNumber[toolNum]
        if type(toolData) == "table" then
            heightText = FormatHeight(toolData.Length)
            local d = tostring(toolData.Desc or "")
            if d ~= "" then
                descText = d
            end
        else
            heightText = FormatHeight(nil)
            descText = "(Missing Tool Data)"
        end
    end

    SetControlText(pocketLabelName, tostring(pocketId))
    SetControlText(toolDroName, tostring(toolNum))
    SetControlText(heightLabelName, heightText)
    SetControlText(descTextName, descText)

    UpdateRowButtons(rowIndex, toolNum, currentTool, pocketTaught)
end

--=========================================================================
-- Function: RefreshRows
-- Purpose:  Redraw all visible rows for the current pocket page window.
--=========================================================================
local function RefreshRows()
    ATC_Pockets.LoadPockets(false)
    local toolsByNumber = ParseToolTableTls()
    local inst = ATC_Runtime.GetInstance()
    local currentTool = mc.mcToolGetCurrent(inst)

    for row = 1, DISPLAY_ROWS do
        local pocketId = m_firstVisiblePocket + (row - 1)
        PopulateRow(row, pocketId, toolsByNumber, currentTool)
    end
end

--=============================================================================
-- Public API
--=============================================================================

--=========================================================================
-- Function: ATC_ToolTracking.InitializePage
-- Purpose:  Initialize tools page state and populate visible rows.
--=========================================================================
function ATC_ToolTracking.InitializePage()
    if m_firstVisiblePocket ~= PAGE_ONE_START and m_firstVisiblePocket ~= PAGE_TWO_START then
        m_firstVisiblePocket = PAGE_ONE_START
    end
    LoadToolSetterLocationControl(CTRL_GAGE_X)
    LoadToolSetterLocationControl(CTRL_GAGE_Y)
    LoadToolSetterHeightDisplays()
    RefreshRows()
end

--=========================================================================
-- Function: ATC_ToolTracking.RefreshPage
-- Purpose:  Refresh currently visible tools page rows.
--=========================================================================
function ATC_ToolTracking.RefreshPage()
    RefreshRows()
end

--=========================================================================
-- Function: ATC_ToolTracking.ShowPocketsUp
-- Purpose:  Display pocket rows 1-9 on the tools page.
--=========================================================================
function ATC_ToolTracking.ShowPocketsUp()
    m_firstVisiblePocket = PAGE_ONE_START
    RefreshRows()
end

--=========================================================================
-- Function: ATC_ToolTracking.ShowPocketsDown
-- Purpose:  Display pocket rows 10-18 on the tools page.
--=========================================================================
function ATC_ToolTracking.ShowPocketsDown()
    m_firstVisiblePocket = PAGE_TWO_START
    RefreshRows()
end

--=========================================================================
-- Function: ATC_ToolTracking.TogglePocketPage
-- Purpose:  Toggle between pockets 1-9 and 10-18.
--=========================================================================
function ATC_ToolTracking.TogglePocketPage()
    if m_firstVisiblePocket == PAGE_ONE_START then
        m_firstVisiblePocket = PAGE_TWO_START
    else
        m_firstVisiblePocket = PAGE_ONE_START
    end
    RefreshRows()
end

--=========================================================================
-- Function: ATC_ToolTracking.OnToolNumberEnter
-- Purpose:  Save entered row tool number to assigned pocket and refresh.
--=========================================================================
function ATC_ToolTracking.OnToolNumberEnter(rowIndex, newValue)
    local row = tonumber(rowIndex)
    if row == nil or row < 1 or row > DISPLAY_ROWS then
        Log("Invalid row index for tool entry: " .. tostring(rowIndex))
        return
    end

    local pocketId = m_firstVisiblePocket + (row - 1)
    local rawText = tostring(newValue or "")
    local enteredTool = NormalizeRowToolInput(rawText)

    local pocketData = ATC_Pockets.GetPocketData(pocketId)
    local previousTool = EMPTY_TOOL_NUMBER
    if type(pocketData) == "table" then
        previousTool = GetDisplayToolNumber(pocketData.tool)
    end

    local inst = ATC_Runtime.GetInstance()
    local currentTool = mc.mcToolGetCurrent(inst)
    if type(currentTool) ~= "number" then
        currentTool = 0
    end

    if currentTool > 0 and previousTool == currentTool and enteredTool ~= previousTool then
        wx.wxMessageBox(
            string.format(
                "Warning: You changed the pocket assignment for the tool currently loaded in the spindle (T%d).",
                currentTool
            )
        )
        Log(string.format(
            "Warning shown: spindle tool T%d was renumbered from pocket %d to T%d.",
            currentTool,
            pocketId,
            enteredTool
        ))
    end

    StorePocketToolAssignment(pocketId, enteredTool)
    RefreshRows()
end

--=========================================================================
-- Function: ATC_ToolTracking.GetRowPocketAndTool
-- Purpose:  Return resolved pocket and tool numbers for one visible row.
--=========================================================================
function ATC_ToolTracking.GetRowPocketAndTool(rowIndex)
    local row = tonumber(rowIndex)
    if row == nil or row < 1 or row > DISPLAY_ROWS then
        return nil, nil
    end
    local pocketId = m_firstVisiblePocket + (row - 1)
    local toolNum = GetPocketToolNumber(pocketId)
    return pocketId, toolNum
end

--=========================================================================
-- Function: ATC_ToolTracking.OnGetTool
-- Purpose:  Return current spindle tool when needed, then load row tool.
--=========================================================================
function ATC_ToolTracking.OnGetTool(rowIndex)
    local pocketId, toolNum = ATC_ToolTracking.GetRowPocketAndTool(rowIndex)
    
    local pocket = ATC_Pockets.GetPocketData(pocketId)
    if type(pocket) ~= "table" or pocket.taught ~= true then
        Log("GetTool ignored: pocket is not taught.")
        RefreshRows()
        return false
    end

    if toolNum == nil or toolNum <= 0 then
        Log("GetTool ignored: row has no tool assignment.")
        RefreshRows()
        return false
    end

    local ok = ATC_Load.LoadTool(toolNum)
    RefreshRows()
    return ok == true
end

--=========================================================================
-- Function: ATC_ToolTracking.OnReturnTool
-- Purpose:  Return current spindle tool to its assigned pocket.
--=========================================================================
function ATC_ToolTracking.OnReturnTool(rowIndex)
    local _, rowTool = ATC_ToolTracking.GetRowPocketAndTool(rowIndex)
    local inst = ATC_Runtime.GetInstance()
    local currentTool = tonumber(mc.mcToolGetCurrent(inst)) or 0

    if currentTool <= 0 then
        Log("ReturnTool ignored: spindle is empty.")
        RefreshRows()
        return false
    end

    if rowTool ~= currentTool then
        Log(string.format(
            "ReturnTool ignored: row tool T%d does not match spindle tool T%d.",
            tonumber(rowTool) or 0,
            currentTool
        ))
        RefreshRows()
        return false
    end

    local ok = ATC_Unload.UnloadTool()
    RefreshRows()
    return ok == true
end

--=========================================================================
-- Function: ATC_ToolTracking.OnSetHeight
-- Purpose:  Placeholder handler for row set-height action.
--=========================================================================
function ATC_ToolTracking.OnSetHeight(rowIndex)
    Log("SetHeight not implemented yet for row " .. tostring(rowIndex))
    return false
end

--=========================================================================
-- Function: ATC_ToolTracking.OnGageXEnter
-- Purpose:  Save the tool setter center X coordinate when Enter is pressed.
--=========================================================================
function ATC_ToolTracking.OnGageXEnter(newValue)
    return SaveToolSetterLocationControl(CTRL_GAGE_X, newValue)
end

--=========================================================================
-- Function: ATC_ToolTracking.OnGageYEnter
-- Purpose:  Save the tool setter center Y coordinate when Enter is pressed.
--=========================================================================
function ATC_ToolTracking.OnGageYEnter(newValue)
    return SaveToolSetterLocationControl(CTRL_GAGE_Y, newValue)
end

--=========================================================================
-- Function: ATC_ToolTracking.OnGageBlockToolEnter
-- Purpose:  Save shared tool-setter height from either screen's DRO.
--=========================================================================
function ATC_ToolTracking.OnGageBlockToolEnter(newValue)
    return SaveToolSetterHeight(newValue)
end

--=========================================================================
-- Function: RunToolSetterMeasurementRoutine
-- Purpose:  Retract from first contact, perform three slow probe touches,
--           and return the averaged machine-Z strike height.
--=========================================================================
local function RunToolSetterMeasurementRoutine(inst, firstStrikeZ)
    local measureFeedIpm = 5.0
    local retractDistance = 0.125
    local probeTravel = 0.2500
    local passCount = 3
    local strikeSum = 0.0

    for pass = 1, passCount do
        local startZ, startErr = ATC_Runtime.GetMachineZ(inst)
        if startZ == nil then
            return false, nil, startErr
        end

        local retractZ = startZ + retractDistance
        local ok, err = ATC_Runtime.ExecGcodeWait(
            inst,
            string.format("G53 G0 Z%.4f", retractZ)
        )
        if not ok then
            return false, nil, err
        end

        ok, err = ATC_Runtime.ExecGcodeWait(
            inst,
            string.format("G91 G31 Z-%.4f F%.1f\nG90", probeTravel, measureFeedIpm)
        )
        if not ok then
            return false, nil, err
        end

        local probeStruck = mc.mcCntlProbeGetStrikeStatus(inst)
        if probeStruck ~= 1 then
            return false, nil, string.format(
                "Measurement pass %d did not trigger within %.4f in.",
                pass,
                probeTravel
            )
        end

        local strikeZ, strikeErr = ATC_Runtime.GetMachineZ(inst)
        if strikeZ == nil then
            return false, nil, strikeErr
        end

        strikeSum = strikeSum + strikeZ

        Log(string.format(
            "Measurement pass %d: startZ=%.4f retractZ=%.4f probeTravel=%.4f feed=%.1f strikeZ=%.4f firstSeekZ=%.4f",
            pass,
            startZ,
            retractZ,
            probeTravel,
            measureFeedIpm,
            strikeZ,
            firstStrikeZ
        ))
    end

    local averageStrikeZ = strikeSum / passCount

    Log(string.format(
        "Measurement complete: passCount=%d measureFeed=%.1f retractDistance=%.4f probeTravel=%.4f firstSeekZ=%.4f avgStrikeZ=%.4f",
        passCount,
        measureFeedIpm,
        retractDistance,
        probeTravel,
        firstStrikeZ,
        averageStrikeZ
    ))

    return true, averageStrikeZ, nil
end

--=========================================================================
-- Function: ApplyMeasuredToolHeight
-- Purpose:  Convert averaged strike height into tool length data and store
--           it in the Mach4 tool table for the current tool.
--=========================================================================
local function ApplyMeasuredToolHeight(currentTool, averageStrikeZ)
    local toolNum = tonumber(currentTool)
    local strikeZ = tonumber(averageStrikeZ)
    local gageBlockRef = tonumber(ReadProfileString(PROFILE_SECTION_PERSISTENT_DROS, KEY_GAGE_BLOCK_TOOL, "0.0000"))

    if toolNum == nil or toolNum <= 0 then
        return false, "Current tool number is invalid."
    end

    if strikeZ == nil then
        return false, "Average strike Z is invalid."
    end

    if gageBlockRef == nil then
        return false, "Tool setter reference height is invalid."
    end

    local measuredLength = strikeZ + gageBlockRef

    local rc = mc.mcToolSetData(
        ATC_Runtime.GetInstance(),
        mc.MTOOL_MILL_HEIGHT,
        toolNum,
        measuredLength
    )
    if rc ~= mc.MERROR_NOERROR then
        return false, "Failed to write tool height. rc=" .. tostring(rc)
    end

    Log(string.format(
        "Applied tool height: tool=%d averageStrikeZ=%.4f gageBlockRef=%.4f measuredLength=%.4f",
        toolNum,
        strikeZ,
        gageBlockRef,
        measuredLength
    ))

    return true, measuredLength
end

--=========================================================================
-- Function: ATC_ToolTracking.OnSetToolHeightOffset
-- Purpose:  Record the tool height of the currently loaded tool.
--=========================================================================
function ATC_ToolTracking.OnSetToolHeightOffset()
    local inst = ATC_Runtime.GetInstance()

    local currentTool, toolErr = ATC_Runtime.GetCurrentToolNumber(inst)
    if currentTool == nil then
        return ATC_Runtime.NotifyFailure("Set tool height offset", toolErr)
    end

    if currentTool <= 0 then
        return ATC_Runtime.NotifyFailure("Set tool height offset", "No tool is currently loaded.")
    end

    Log("Setting tool height for tool: " .. tostring(currentTool))

    local ok, err = ATC_Runtime.MoveToSafeZ(inst)
    if not ok then
        return ATC_Runtime.NotifyFailure("Set tool height offset", err)
    end

    local gageX = tonumber(ReadProfileString(PROFILE_SECTION_PERSISTENT_DROS, CTRL_GAGE_X, "0.0000"))
    local gageY = tonumber(ReadProfileString(PROFILE_SECTION_PERSISTENT_DROS, CTRL_GAGE_Y, "0.0000"))

    if gageX == nil or gageY == nil then
        return ATC_Runtime.NotifyFailure("Set tool height offset", "Tool setter X/Y is not valid.")
    end

    local approachX = gageX + (tonumber(ATC_Config.Motion.PocketClearanceOffsetX) or 0.0)

    ok, err = ATC_Runtime.ExecGcodeWait(
        inst,
        string.format(
            "G53 G0 F%.1f X%.4f Y%.4f\nG53 G0 X%.4f Y%.4f",
            tonumber(ATC_Config.Motion.XYApproachFeedIpm) or 500.0,
            approachX,
            gageY,
            gageX,
            gageY
        )
    )
    if not ok then
        return ATC_Runtime.NotifyFailure("Set tool height offset", err)
    end

    Log(string.format(
        "Tool height offset routine moved over tool setter at X%.4f Y%.4f.",
        gageX,
        gageY
    ))

    local fastProbeTravel = 4.0000
    local fastProbeFeedIpm = 50.0

    ok, err = ATC_Runtime.ExecGcodeWait(
        inst,
        string.format("G91 G31 Z-%.4f F%.1f\nG90", fastProbeTravel, fastProbeFeedIpm)
    )
    if not ok then
        return ATC_Runtime.NotifyFailure("Set tool height offset", err)
    end

    local probeStruck = mc.mcCntlProbeGetStrikeStatus(inst)
    if probeStruck ~= 1 then
        return ATC_Runtime.NotifyFailure(
            "Set tool height offset",
            string.format("Tool setter did not trigger within %.4f inches at %.1f IPM.", fastProbeTravel, fastProbeFeedIpm)
        )
    end

    local firstStrikeZ, zErr = ATC_Runtime.GetMachineZ(inst)
    if firstStrikeZ == nil then
        return ATC_Runtime.NotifyFailure("Set tool height offset", zErr)
    end

    Log(string.format(
        "Fast seek hit tool setter: tool=%d fastProbeTravel=%.4f fastFeed=%.1f firstStrikeZ=%.4f",
        currentTool,
        fastProbeTravel,
        fastProbeFeedIpm,
        firstStrikeZ
    ))

    local measured, averageStrikeZ, measureErr = RunToolSetterMeasurementRoutine(inst, firstStrikeZ)
    if not measured then
        return ATC_Runtime.NotifyFailure("Set tool height offset", measureErr)
    end

    local applied, measuredLengthOrErr = ApplyMeasuredToolHeight(currentTool, averageStrikeZ)
    if not applied then
        return ATC_Runtime.NotifyFailure("Set tool height offset", measuredLengthOrErr)
    end

    -- NEW: return to safe position (mirrors post-load behaviour)
    ok, err = ATC_Runtime.MoveToSafeZ(inst)
    if not ok then
        return ATC_Runtime.NotifyFailure("Set tool height offset", err)
    end

    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 X%.4f", approachX))
    if not ok then
        return ATC_Runtime.NotifyFailure("Set tool height offset", err)
    end

    Log(string.format(
        "Tool height offset complete: tool=%d firstStrikeZ=%.4f averageStrikeZ=%.4f storedLength=%.4f",
        currentTool,
        firstStrikeZ,
        averageStrikeZ,
        measuredLengthOrErr
    ))

    return true
end

--=========================================================================
-- Function: ATC_ToolTracking.OnSetToolSetterHeight
-- Purpose:  Backward-compatible wrapper for existing screen button scripts.
--=========================================================================
function ATC_ToolTracking.OnSetToolSetterHeight()
    return ATC_ToolTracking.OnSetToolHeightOffset()
end

_G.ATC_ToolTracking = ATC_ToolTracking
return ATC_ToolTracking

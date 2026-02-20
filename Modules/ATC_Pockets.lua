--=============================================================================
-- File:        ATC_Pockets.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     ATC pocket teach/save/load and UI sync.
--=============================================================================

local ATC_Config = require("ATC_Config")

local ATC_Pockets = {}

--=============================================================================
-- Constants
--=============================================================================
local POCKET_COUNT = ATC_Config.Pockets.Count
local SENTINEL_UNTAUGHT_POS = ATC_Config.Pockets.UntaughtPosition
local SENTINEL_NO_TOOL = ATC_Config.Pockets.UnassignedTool
local JSON_FULL_PATH = ATC_Config.Pockets.JsonPath

local AXIS_X = 0
local AXIS_Y = 1
local AXIS_Z = 2

local CTRL_POCKET_ID = "dro_PocketId"
local CTRL_POCKET_X = "dro_PocketX"
local CTRL_POCKET_Y = "dro_PocketY"
local CTRL_POCKET_Z = "dro_PocketZ"
local CTRL_LED_TAUGHT = "led_PocketTaught"

local AXIS_DISPLAY_FORMAT = "%.4f"

--=============================================================================
-- Private state
--=============================================================================
local m_inst = nil
local m_initialized = false
local m_pockets = nil
local m_currentPocket = 1
local m_missingUiLog = {}

--=============================================================================
-- Helpers
--=============================================================================

--=========================================================================
-- Function: ClampInt
-- Purpose:  Clamp integer-like value to [minValue, maxValue].
--=========================================================================
local function ClampInt(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

--=========================================================================
-- Function: RoundNearestInt
-- Purpose:  Round number to nearest integer.
--=========================================================================
local function RoundNearestInt(value)
    return math.floor(value + 0.5)
end

--=========================================================================
-- Function: GetInstance
-- Purpose:  Cache and return active Mach4 instance.
--=========================================================================
local function GetInstance()
    if m_inst == nil then
        m_inst = mc.mcGetInstance()
    end
    return m_inst
end

--=========================================================================
-- Function: LogMessage
-- Purpose:  Post message to Mach4 status/history.
--=========================================================================
local function LogMessage(message)
    mc.mcCntlSetLastError(GetInstance(), tostring(message))
end

--=========================================================================
-- Function: CreateDefaultPocket
-- Purpose:  Build one default pocket record.
--=========================================================================
local function CreateDefaultPocket()
    return {
        x = SENTINEL_UNTAUGHT_POS,
        y = SENTINEL_UNTAUGHT_POS,
        z = SENTINEL_UNTAUGHT_POS,
        taught = false,
        tool = SENTINEL_NO_TOOL
    }
end

--=========================================================================
-- Function: EnsurePocketTable
-- Purpose:  Allocate default pocket table once.
--=========================================================================
local function EnsurePocketTable()
    if m_pockets ~= nil then
        return
    end

    m_pockets = {}
    for i = 1, POCKET_COUNT do
        m_pockets[i] = CreateDefaultPocket()
    end
end

--=========================================================================
-- Function: ResetPocketTableToDefaults
-- Purpose:  Reset all pockets to default sentinels.
--=========================================================================
local function ResetPocketTableToDefaults()
    EnsurePocketTable()
    for i = 1, POCKET_COUNT do
        local p = m_pockets[i]
        p.x = SENTINEL_UNTAUGHT_POS
        p.y = SENTINEL_UNTAUGHT_POS
        p.z = SENTINEL_UNTAUGHT_POS
        p.taught = false
        p.tool = SENTINEL_NO_TOOL
    end
end

--=========================================================================
-- Function: SetDroValue
-- Purpose:  Write a DRO Value property using screen API.
--=========================================================================
local function SetDroValue(controlName, valueText)
    local ok = pcall(function()
        scr.SetProperty(controlName, "Value", tostring(valueText))
    end)
    if not ok then
        LogMessage("ATC_Pockets: failed to set DRO Value for " .. tostring(controlName))
    end
end

--=========================================================================
-- Function: GetDroValue
-- Purpose:  Read a DRO Value property using screen API.
--=========================================================================
local function GetDroValue(controlName)
    local ok, value = pcall(function()
        return scr.GetProperty(controlName, "Value")
    end)
    if ok and value ~= nil then
        return tostring(value)
    end
    return nil
end

--=========================================================================
-- Function: SetTaughtLed
-- Purpose:  Update taught LED state.
--=========================================================================
local function SetTaughtLed(isTaught)
    local ok = pcall(function()
        scr.SetProperty(CTRL_LED_TAUGHT, "Value", (isTaught and "1" or "0"))
    end)
    if not ok then
        LogMessage("ATC_Pockets: failed to set LED '" .. tostring(CTRL_LED_TAUGHT) .. "'")
    end
end

--=========================================================================
-- Function: FormatAxisValue
-- Purpose:  Convert numeric value to DRO display string.
--=========================================================================
local function FormatAxisValue(value)
    local n = tonumber(value)
    if n == nil then
        return tostring(SENTINEL_UNTAUGHT_POS)
    end
    return string.format(AXIS_DISPLAY_FORMAT, n)
end

--=========================================================================
-- Function: SetPocketIdDro
-- Purpose:  Write pocket ID DRO.
--=========================================================================
local function SetPocketIdDro(pocketId)
    SetDroValue(CTRL_POCKET_ID, tostring(pocketId))
end

--=========================================================================
-- Function: ReadPocketIdDro
-- Purpose:  Parse and clamp pocket ID from DRO.
--=========================================================================
local function ReadPocketIdDro()
    local raw = GetDroValue(CTRL_POCKET_ID)
    local n = tonumber(raw)
    if n == nil then
        return nil
    end
    n = RoundNearestInt(n)
    return ClampInt(n, 1, POCKET_COUNT)
end

--=========================================================================
-- Function: RefreshPocketUI
-- Purpose:  Push current pocket to DROs and taught LED.
--=========================================================================
local function RefreshPocketUI(writePocketId)
    EnsurePocketTable()
    m_currentPocket = ClampInt(m_currentPocket, 1, POCKET_COUNT)

    local p = m_pockets[m_currentPocket]

    if writePocketId == true then
        SetPocketIdDro(m_currentPocket)
    end

    SetDroValue(CTRL_POCKET_X, FormatAxisValue(p.x))
    SetDroValue(CTRL_POCKET_Y, FormatAxisValue(p.y))
    SetDroValue(CTRL_POCKET_Z, FormatAxisValue(p.z))
    SetTaughtLed(p.taught)
end

--=========================================================================
-- Function: GetAxisMachinePosSafe
-- Purpose:  Read machine coordinate robustly.
--=========================================================================
local function GetAxisMachinePosSafe(axisId)
    local pos = mc.mcAxisGetMachinePos(GetInstance(), axisId)
    pos = tonumber(pos)
    if pos == nil then
        return SENTINEL_UNTAUGHT_POS
    end
    return pos
end

--=========================================================================
-- Function: GetCurrentToolNumber
-- Purpose:  Get active tool number from Mach4.
--=========================================================================
local function GetCurrentToolNumber()
    local tool = mc.mcToolGetCurrent(GetInstance())
    tool = tonumber(tool)
    if tool == nil then
        return SENTINEL_NO_TOOL
    end
    return RoundNearestInt(tool)
end

--=========================================================================
-- Function: SelectPocketForTool
-- Purpose:  Set current pocket to the one assigned to toolNum.
--=========================================================================
local function SelectPocketForTool(toolNum)
    if toolNum == nil or toolNum == SENTINEL_NO_TOOL then
        return false
    end

    for pocketIndex = 1, POCKET_COUNT do
        local p = m_pockets[pocketIndex]
        if tonumber(p.tool) == tonumber(toolNum) then
            m_currentPocket = pocketIndex
            return true
        end
    end

    return false
end

--=========================================================================
-- Function: EncodeJson
-- Purpose:  Serialize pocket table to deterministic JSON.
--=========================================================================
local function EncodeJson()
    EnsurePocketTable()

    local lines = {}
    table.insert(lines, "{")
    table.insert(lines, string.format('  "pocketCount": %d,', POCKET_COUNT))
    table.insert(lines, '  "pockets": [')

    for i = 1, POCKET_COUNT do
        local p = m_pockets[i]
        local taught = p.taught and "true" or "false"
        local suffix = (i < POCKET_COUNT) and "," or ""

        table.insert(lines, string.format(
            '    {"id":%d,"x":%.6f,"y":%.6f,"z":%.6f,"taught":%s,"tool":%d}%s',
            i,
            tonumber(p.x) or SENTINEL_UNTAUGHT_POS,
            tonumber(p.y) or SENTINEL_UNTAUGHT_POS,
            tonumber(p.z) or SENTINEL_UNTAUGHT_POS,
            taught,
            tonumber(p.tool) or SENTINEL_NO_TOOL,
            suffix
        ))
    end

    table.insert(lines, "  ]")
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

--=========================================================================
-- Function: DecodeJson
-- Purpose:  Parse pocket table from JSON text.
--=========================================================================
local function DecodeJson(jsonText)
    EnsurePocketTable()
    if type(jsonText) ~= "string" or jsonText == "" then
        return false
    end

    ResetPocketTableToDefaults()

    local pocketsBlob = jsonText:match('%"pockets%"%s*:%s*%[(.*)%]')
    if type(pocketsBlob) ~= "string" then
        return false
    end

    local foundAny = false

    for pocketObject in pocketsBlob:gmatch("{(.-)}") do
        local id = tonumber(pocketObject:match('%"id%"%s*:%s*(%-?%d+)'))
        if id ~= nil and id >= 1 and id <= POCKET_COUNT then
            local x = tonumber(pocketObject:match('%"x%"%s*:%s*([%-+]?%d+%.?%d*[eE]?[%-+]?%d*)'))
            local y = tonumber(pocketObject:match('%"y%"%s*:%s*([%-+]?%d+%.?%d*[eE]?[%-+]?%d*)'))
            local z = tonumber(pocketObject:match('%"z%"%s*:%s*([%-+]?%d+%.?%d*[eE]?[%-+]?%d*)'))
            local tool = tonumber(pocketObject:match('%"tool%"%s*:%s*(%-?%d+)'))
            local taughtRaw = pocketObject:match('%"taught%"%s*:%s*(%a+)')

            if taughtRaw ~= nil then
                taughtRaw = string.lower(taughtRaw)
            end

            local p = m_pockets[id]
            p.x = x or SENTINEL_UNTAUGHT_POS
            p.y = y or SENTINEL_UNTAUGHT_POS
            p.z = z or SENTINEL_UNTAUGHT_POS
            p.taught = (taughtRaw == "true")
            p.tool = tool or SENTINEL_NO_TOOL
            foundAny = true
        end
    end

    return foundAny
end

--=========================================================================
-- Function: SaveToDisk
-- Purpose:  Save pocket table to JSON file.
--=========================================================================
local function SaveToDisk()
    local f = io.open(JSON_FULL_PATH, "w")
    if f == nil then
        LogMessage("ATC: ERROR saving pockets JSON: " .. tostring(JSON_FULL_PATH))
        return false
    end

    f:write(EncodeJson())
    f:close()
    LogMessage("ATC: Pocket data saved to " .. tostring(JSON_FULL_PATH))
    return true
end

--=========================================================================
-- Function: LoadFromDisk
-- Purpose:  Load pocket table from JSON file, create defaults if missing.
--=========================================================================
local function LoadFromDisk()
    local f = io.open(JSON_FULL_PATH, "r")
    if f == nil then
        ResetPocketTableToDefaults()
        SaveToDisk()
        LogMessage("ATC: Pocket JSON not found. Created defaults.")
        return true
    end

    local jsonText = f:read("*a")
    f:close()

    if DecodeJson(jsonText) then
        LogMessage("ATC: Pocket data loaded from " .. tostring(JSON_FULL_PATH))
        return true
    end

    ResetPocketTableToDefaults()
    SaveToDisk()
    LogMessage("ATC: Pocket JSON invalid. Replaced with defaults.")
    return false
end

--=============================================================================
-- Public API
--=============================================================================

--=========================================================================
-- Function: ATC_Pockets.Init
-- Purpose:  Initialize module and optionally refresh UI.
--=========================================================================
function ATC_Pockets.Init(refreshUi)
    GetInstance()
    EnsurePocketTable()

    if not m_initialized then
        LoadFromDisk()
        SelectPocketForTool(GetCurrentToolNumber())
        m_initialized = true
    end

    if refreshUi ~= false then
        RefreshPocketUI(true)
    end
end

--=========================================================================
-- Function: ATC_Pockets.PocketPlus
-- Purpose:  Select next pocket and refresh UI.
--=========================================================================
function ATC_Pockets.PocketPlus()
    ATC_Pockets.Init()
    m_currentPocket = ClampInt(m_currentPocket + 1, 1, POCKET_COUNT)
    RefreshPocketUI(true)
end

--=========================================================================
-- Function: ATC_Pockets.PocketMinus
-- Purpose:  Select previous pocket and refresh UI.
--=========================================================================
function ATC_Pockets.PocketMinus()
    ATC_Pockets.Init()
    m_currentPocket = ClampInt(m_currentPocket - 1, 1, POCKET_COUNT)
    RefreshPocketUI(true)
end

--=========================================================================
-- Function: ATC_Pockets.SetCurrentPocketFromText
-- Purpose:  Update current pocket from DRO text.
--=========================================================================
function ATC_Pockets.SetCurrentPocketFromText()
    ATC_Pockets.Init()

    local id = ReadPocketIdDro()
    if id == nil then
        return
    end

    if id ~= m_currentPocket then
        m_currentPocket = id
        RefreshPocketUI(false)
    end
end

--=========================================================================
-- Function: ATC_Pockets.SetCurrentPocket
-- Purpose:  Set current pocket from explicit value or DRO.
--=========================================================================
function ATC_Pockets.SetCurrentPocket(pocketId)
    ATC_Pockets.Init()

    if pocketId ~= nil then
        local id = tonumber(pocketId) or 1
        id = ClampInt(RoundNearestInt(id), 1, POCKET_COUNT)
        m_currentPocket = id
        RefreshPocketUI(true)
        return
    end

    ATC_Pockets.SetCurrentPocketFromText()
end

--=========================================================================
-- Function: ATC_Pockets.CapturePocket
-- Purpose:  Capture machine X/Y/Z into selected pocket and save.
-- Notes:    Tool assignment is preserved for existing pockets.
--=========================================================================
function ATC_Pockets.CapturePocket()
    ATC_Pockets.Init()

    local p = m_pockets[m_currentPocket]
    p.x = GetAxisMachinePosSafe(AXIS_X)
    p.y = GetAxisMachinePosSafe(AXIS_Y)
    p.z = GetAxisMachinePosSafe(AXIS_Z)
    p.taught = true

    if p.tool == nil then
        p.tool = SENTINEL_NO_TOOL
    end

    mc.mcCntlSetLastError(m_inst, string.format("ATC CAPTURE X=%.4f Y=%.4f Z=%.4f", p.x, p.y, p.z))

    SaveToDisk()
    RefreshPocketUI(true)
end

--=========================================================================
-- Function: ATC_Pockets.ClearPocket
-- Purpose:  Clear selected pocket to sentinels and save.
--=========================================================================
function ATC_Pockets.ClearPocket()
    ATC_Pockets.Init()

    local p = m_pockets[m_currentPocket]
    p.x = SENTINEL_UNTAUGHT_POS
    p.y = SENTINEL_UNTAUGHT_POS
    p.z = SENTINEL_UNTAUGHT_POS
    p.taught = false
    p.tool = SENTINEL_NO_TOOL

    SaveToDisk()
    RefreshPocketUI(true)
end

--=========================================================================
-- Function: ATC_Pockets.SetPocketTool
-- Purpose:  Assign a tool number to a pocket and save.
--=========================================================================
function ATC_Pockets.SetPocketTool(pocketId, toolNum)
    ATC_Pockets.Init()

    local id = tonumber(pocketId)
    if id == nil then
        id = m_currentPocket
    end

    id = ClampInt(RoundNearestInt(id), 1, POCKET_COUNT)

    local t = tonumber(toolNum)
    if t == nil then
        t = SENTINEL_NO_TOOL
    else
        t = RoundNearestInt(t)
    end

    m_pockets[id].tool = t
    SaveToDisk()

    if id == m_currentPocket then
        RefreshPocketUI(true)
    end

    return true
end

--=========================================================================
-- Function: ATC_Pockets.SavePockets
-- Purpose:  Save all pockets to JSON.
--=========================================================================
function ATC_Pockets.SavePockets()
    ATC_Pockets.Init()
    SaveToDisk()
    RefreshPocketUI(true)
end

--=========================================================================
-- Function: ATC_Pockets.LoadPockets
-- Purpose:  Reload pockets from JSON and optionally refresh UI.
--=========================================================================
function ATC_Pockets.LoadPockets(refreshUi)
    GetInstance()
    EnsurePocketTable()
    LoadFromDisk()
    SelectPocketForTool(GetCurrentToolNumber())
    m_initialized = true

    if refreshUi ~= false then
        RefreshPocketUI(true)
    end
end

--=========================================================================
-- Function: ATC_Pockets.GetCurrentPocketId
-- Purpose:  Return current selected pocket ID.
--=========================================================================
function ATC_Pockets.GetCurrentPocketId()
    ATC_Pockets.Init(false)
    return m_currentPocket
end

--=========================================================================
-- Function: ATC_Pockets.GetPocketData
-- Purpose:  Return a copy of one pocket record by pocket ID.
--=========================================================================
function ATC_Pockets.GetPocketData(pocketId)
    ATC_Pockets.Init(false)

    local id = tonumber(pocketId) or m_currentPocket
    id = ClampInt(RoundNearestInt(id), 1, POCKET_COUNT)

    local p = m_pockets[id]
    return {
        id = id,
        x = tonumber(p.x) or SENTINEL_UNTAUGHT_POS,
        y = tonumber(p.y) or SENTINEL_UNTAUGHT_POS,
        z = tonumber(p.z) or SENTINEL_UNTAUGHT_POS,
        taught = (p.taught == true),
        tool = tonumber(p.tool) or SENTINEL_NO_TOOL
    }
end

--=========================================================================
-- Function: ATC_Pockets.GetCurrentPocketData
-- Purpose:  Return copy of current pocket record.
--=========================================================================
function ATC_Pockets.GetCurrentPocketData()
    return ATC_Pockets.GetPocketData(m_currentPocket)
end

--=========================================================================
-- Function: ATC_Pockets.GetPocketCount
-- Purpose:  Return configured pocket count.
--=========================================================================
function ATC_Pockets.GetPocketCount()
    return POCKET_COUNT
end

--=========================================================================
-- Function: ATC_Pockets.FindPocketByTool
-- Purpose:  Return pocket data copy for tool number, or nil.
--=========================================================================
function ATC_Pockets.FindPocketByTool(toolNum)
    ATC_Pockets.Init(false)

    local t = tonumber(toolNum)
    if t == nil or t <= 0 then
        return nil
    end

    for i = 1, POCKET_COUNT do
        if tonumber(m_pockets[i].tool) == t then
            return ATC_Pockets.GetPocketData(i)
        end
    end

    return nil
end

_G.ATC_Pockets = ATC_Pockets
return ATC_Pockets

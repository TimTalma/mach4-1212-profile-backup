--=============================================================================
-- File:        ATC_Pockets.lua
-- Purpose:     Pocket teach/save/load logic for ATC development
-- Author:      Tim / ChatGPT
--
-- Overview:
--   This module manages pocket positions (X/Y/Z) and a taught boolean per pocket.
--   Pocket data is persisted to JSON on disk. The UI is updated by writing Mach4
--   Pound Variables (not by calling wx control SetValue/GetValue), because Mach4
--   DRO widgets are not guaranteed to expose wx SetValue/GetValue methods.
--
-- Why Pound Vars:
--   Your Mach4 environment has shown:
--     - mc.mcGetCurrentScreen() is not available
--     - DRO controls returned by wx.wxFindWindowByName() do not consistently
--       implement GetValue()/SetValue()
--   The Scripting Manual shows mc.mcCntlGetPoundVar()/mc.mcCntlSetPoundVar()
--   as supported, and Screen Editor can bind DROs to Pound Vars.
--
-- Requirements implemented:
--   - Pocket JSON file persistence
--   - If pocket cleared/never saved: x,y,z = -1 and taught=false
--   - taught boolean per pocket
--   - led_PocketTaught ON when taught=true for current pocket
--   - Pocket +/- changes current pocket and updates displayed values
--   - Save Pocket Data writes immediately to JSON
--   - Load Pocket Data reloads JSON into memory and refreshes UI
--
--=============================================================================

local ATC_Pockets = {}

--=============================================================================
-- Constants
--=============================================================================

-- Pocket count for development
-- Use:
--   Number of pockets maintained in memory and stored to JSON.
-- Derivation:
--   You currently have 2 pockets during development. Final system will be 16–18.
local POCKET_COUNT = 2

-- Sentinel position for "not taught" pockets
-- Use:
--   Values recorded when pocket is cleared or has never been saved.
-- Derivation:
--   You specified that cleared/unsaved pockets must store -1.
local SENTINEL_UNTAUGHT_POS = -1

-- JSON storage path (development)
-- Use:
--   File location for saving/loading pocket data.
-- Derivation:
--   Your current logs show C:\Mach4Hobby as the Mach4 base folder.
--   Later you want: C:\Mach4Hobby\Profiles\1212
--   For now, we keep the working path, and we’ll move it once everything is solid.
local JSON_FULL_PATH = "C:\\Mach4Hobby\\ATC_Pockets.json"

-- Pound Vars used to drive UI DRO display (bind your DROs to these in Screen Editor)
-- Use:
--   We update these Pound Vars so the UI DRO widgets can display pocket values
--   without requiring wx SetValue/GetValue.
-- Derivation:
--   Chosen as a small contiguous block to simplify binding. If you already use
--   these Pound Vars for something else, tell me and we’ll move the range.
local PV_POCKET_ID   = 5500
local PV_POCKET_X    = 5501
local PV_POCKET_Y    = 5502
local PV_POCKET_Z    = 5503
local PV_POCKET_TAUGHT = 5504

-- LED control name from your screen
local LED_POCKET_TAUGHT_NAME = "led_PocketTaught"

--=============================================================================
-- Private state
--=============================================================================
local m_inst = nil
local m_pockets = nil            -- array [1..POCKET_COUNT] of {x,y,z,taught}
local m_currentPocket = 1

--=============================================================================
-- Helpers
--=============================================================================

local function ClampInt(v, minV, maxV)
    if v < minV then return minV end
    if v > maxV then return maxV end
    return v
end

local function EnsurePockets()
    if m_pockets ~= nil then
        return
    end

    m_pockets = {}
    for i = 1, POCKET_COUNT do
        m_pockets[i] =
        {
            x = SENTINEL_UNTAUGHT_POS,
            y = SENTINEL_UNTAUGHT_POS,
            z = SENTINEL_UNTAUGHT_POS,
            taught = false
        }
    end
end

--=============================================================================
-- UI update via Pound Vars (Mach4-native)
--=============================================================================

local function SetPoundVar(varNum, value)
    -- mcCntlSetPoundVar is referenced in the Mach4 scripting examples alongside
    -- mcCntlGetPoundVar. This avoids dependence on wx widget methods.
    mc.mcCntlSetPoundVar(m_inst, varNum, tonumber(value) or 0)
end

local function RefreshPocketUI()
    EnsurePockets()
    m_currentPocket = ClampInt(m_currentPocket, 1, POCKET_COUNT)

    local p = m_pockets[m_currentPocket]

    -- Update Pound Vars (bind DROs to these)
    SetPoundVar(PV_POCKET_ID, m_currentPocket)
    SetPoundVar(PV_POCKET_X, p.x)
    SetPoundVar(PV_POCKET_Y, p.y)
    SetPoundVar(PV_POCKET_Z, p.z)
    SetPoundVar(PV_POCKET_TAUGHT, p.taught and 1 or 0)

    -- Also try to set the taught LED directly (optional convenience).
    -- If the LED widget doesn’t support SetValue, this will simply do nothing.
    local wnd = wx.wxFindWindowByName(LED_POCKET_TAUGHT_NAME)
    if wnd ~= nil and wnd.SetValue ~= nil then
        wnd:SetValue(p.taught and 1 or 0)
    end
end

--=============================================================================
-- JSON encode/decode (simple + deterministic)
--=============================================================================

local function EncodeJson()
    EnsurePockets()

    local lines = {}
    table.insert(lines, "{")
    table.insert(lines, string.format('  "pocketCount": %d,', POCKET_COUNT))
    table.insert(lines, '  "pockets": [')

    for i = 1, POCKET_COUNT do
        local p = m_pockets[i]
        local taughtStr = p.taught and "true" or "false"
        local comma = (i < POCKET_COUNT) and "," or ""
        table.insert(lines,
            string.format('    {"id":%d,"x":%.6f,"y":%.6f,"z":%.6f,"taught":%s}%s',
                i, p.x, p.y, p.z, taughtStr, comma))
    end

    table.insert(lines, "  ]")
    table.insert(lines, "}")
    return table.concat(lines, "\n")
end

local function DecodeJson(json)
    EnsurePockets()

    if not json or json == "" then
        return false
    end

    -- Reset defaults first
    for i = 1, POCKET_COUNT do
        local p = m_pockets[i]
        p.x = SENTINEL_UNTAUGHT_POS
        p.y = SENTINEL_UNTAUGHT_POS
        p.z = SENTINEL_UNTAUGHT_POS
        p.taught = false
    end

    local foundAny = false

    -- Extract each pocket object
    for obj in json:gmatch("{%s*\"id\"%s*:%s*%d+.-}") do
        local id = tonumber(obj:match('\"id\"%s*:%s*(%d+)'))
        if id ~= nil and id >= 1 and id <= POCKET_COUNT then
            local x  = tonumber(obj:match('\"x\"%s*:%s*([%-%d%.]+)'))
            local y  = tonumber(obj:match('\"y\"%s*:%s*([%-%d%.]+)'))
            local z  = tonumber(obj:match('\"z\"%s*:%s*([%-%d%.]+)'))
            local taughtRaw = obj:match('\"taught\"%s*:%s*(%a+)')

            local p = m_pockets[id]
            if x ~= nil then p.x = x end
            if y ~= nil then p.y = y end
            if z ~= nil then p.z = z end
            p.taught = (taughtRaw == "true")

            foundAny = true
        end
    end

    return foundAny
end

local function SaveToDisk()
    local f = io.open(JSON_FULL_PATH, "w")
    if not f then
        mc.mcCntlSetLastError(m_inst, "ATC: ERROR saving pockets JSON: " .. tostring(JSON_FULL_PATH))
        return false
    end

    f:write(EncodeJson())
    f:close()

    mc.mcCntlSetLastError(m_inst, "ATC: Pocket data saved to " .. tostring(JSON_FULL_PATH))
    return true
end

local function LoadFromDisk()
    local f = io.open(JSON_FULL_PATH, "r")
    if not f then
        mc.mcCntlSetLastError(m_inst, "ATC: Pocket JSON not found — creating defaults.")
        EnsurePockets()
        SaveToDisk()
        return true
    end

    local json = f:read("*a")
    f:close()

    local ok = DecodeJson(json)
    if ok then
        mc.mcCntlSetLastError(m_inst, "ATC: Pocket data loaded from " .. tostring(JSON_FULL_PATH))
        return true
    end

    mc.mcCntlSetLastError(m_inst, "ATC: Pocket JSON invalid — using defaults.")
    EnsurePockets()
    SaveToDisk()
    return false
end

--=============================================================================
-- Public API
--=============================================================================

function ATC_Pockets.Init()
    m_inst = mc.mcGetInstance()
    EnsurePockets()
    LoadFromDisk()
    RefreshPocketUI()
end

function ATC_Pockets.PocketPlus()
    ATC_Pockets.Init()
    m_currentPocket = ClampInt(m_currentPocket + 1, 1, POCKET_COUNT)
    RefreshPocketUI()
end

function ATC_Pockets.PocketMinus()
    ATC_Pockets.Init()
    m_currentPocket = ClampInt(m_currentPocket - 1, 1, POCKET_COUNT)
    RefreshPocketUI()
end

-- Set current pocket from external event (e.g., DRO On Modify script)
function ATC_Pockets.SetCurrentPocket(pocketId)
    ATC_Pockets.Init()

    local id = tonumber(pocketId) or 1
    id = math.floor(id + 0.5)
    m_currentPocket = ClampInt(id, 1, POCKET_COUNT)

    RefreshPocketUI()
end

function ATC_Pockets.CapturePocket()
    ATC_Pockets.Init()

    -- Read machine coordinates directly (no DRO reads)
    local x = mc.mcAxisGetMachinePos(m_inst, 0)
    local y = mc.mcAxisGetMachinePos(m_inst, 1)
    local z = mc.mcAxisGetMachinePos(m_inst, 2)

    local p = m_pockets[m_currentPocket]
    p.x = x
    p.y = y
    p.z = z
    p.taught = true

    SaveToDisk()
    RefreshPocketUI()
end

function ATC_Pockets.ClearPocket()
    ATC_Pockets.Init()

    local p = m_pockets[m_currentPocket]
    p.x = SENTINEL_UNTAUGHT_POS
    p.y = SENTINEL_UNTAUGHT_POS
    p.z = SENTINEL_UNTAUGHT_POS
    p.taught = false

    SaveToDisk()
    RefreshPocketUI()
end

function ATC_Pockets.SavePockets()
    ATC_Pockets.Init()
    SaveToDisk()
    RefreshPocketUI()
end

function ATC_Pockets.LoadPockets()
    ATC_Pockets.Init()
    LoadFromDisk()
    RefreshPocketUI()
end

return ATC_Pockets

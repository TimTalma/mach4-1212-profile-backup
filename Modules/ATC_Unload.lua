--=============================================================================
-- File:        ATC_Unload.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Automatic tool unload sequence (module scope).
--=============================================================================

local ATC_Pockets = require("ATC_Pockets")
local ATC_ToolMap = require("ATC_ToolMap")
local ATC_Runtime = require("ATC_Runtime")
local ATC_Manual = require("ATC_ManualControls")
local ATC_Config = require("ATC_Config")

local ATC_Unload = {}

--=============================================================================
-- Constants
--=============================================================================
local AXIS_X = 0
local AXIS_Y = 1
local AXIS_Z = 2

local UNLOAD_APPROACH_OFFSET_X = ATC_Config.Motion.PocketClearanceOffsetX
local XY_APPROACH_FEED_IPM = ATC_Config.Motion.XYApproachFeedIpm
local SAFE_Z_MACHINE = ATC_Config.Motion.SafeZMachine
local POCKET_Z_APPROACH_CLEARANCE = ATC_Config.Motion.PocketZApproachClearance
local DRAWBAR_OPEN_WAIT_MS = ATC_Config.Timing.DrawbarOpenWaitMs

--=============================================================================
-- Helpers
--=============================================================================

--=========================================================================
-- Function: Log
-- Purpose:  Write unload-scoped log message.
--=========================================================================
local function Log(msg)
    ATC_Runtime.Log("ATC_UNLOAD: " .. tostring(msg))
end

--=========================================================================
-- Function: CanUnloadTool
-- Purpose:  Validate whether automatic unload can run safely.
--=========================================================================
local function CanUnloadTool(inst, pocket, currentTool)
    if not ATC_Runtime.IsAxisHomed(inst, AXIS_X) or
       not ATC_Runtime.IsAxisHomed(inst, AXIS_Y) or
       not ATC_Runtime.IsAxisHomed(inst, AXIS_Z) then
        return false, "X/Y/Z must be homed before unload."
    end

    local tool = tonumber(currentTool) or 0
    if tool <= 0 then
        return false, "No active tool in spindle."
    end

    if type(pocket) ~= "table" then
        return false, "Current tool has no assigned pocket."
    end

    if pocket.taught ~= true then
        return false, "Assigned pocket " .. tostring(pocket.id) .. " is not taught."
    end

    local pTool = tonumber(pocket.tool) or ATC_Config.Pockets.UnassignedTool
    if pTool ~= tool then
        return false, string.format(
            "Current tool T%d does not match assigned pocket %d (T%d).",
            tool,
            tonumber(pocket.id) or -1,
            pTool
        )
    end

    local x = tonumber(pocket.x)
    local y = tonumber(pocket.y)
    local z = tonumber(pocket.z)
    if x == nil or y == nil or z == nil then
        return false, "Assigned pocket coordinates are invalid."
    end

    return true, nil
end

--=========================================================================
-- Function: MoveOverSelectedPocket
-- Purpose:  Execute unload motion path at selected/assigned pocket.
--=========================================================================
local function MoveOverSelectedPocket(inst, pocketData)
    local p = pocketData

    local x = tonumber(p.x)
    local y = tonumber(p.y)
    local z = tonumber(p.z)

    local ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", SAFE_Z_MACHINE))
    if not ok then
        return false, err
    end

    local preX = x + UNLOAD_APPROACH_OFFSET_X
    local xyCmd = string.format(
        "G53 G1 F%.1f X%.4f Y%.4f\nG53 G1 X%.4f Y%.4f",
        XY_APPROACH_FEED_IPM, preX, y, x, y
    )
    ok, err = ATC_Runtime.ExecGcodeWait(inst, xyCmd)
    if not ok then
        return false, err
    end

    local zApproach = z + POCKET_Z_APPROACH_CLEARANCE
    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", zApproach))
    if not ok then
        return false, err
    end

    ATC_Manual.DrawbarOpenEnable()
    wx.wxMilliSleep(DRAWBAR_OPEN_WAIT_MS)

    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", SAFE_Z_MACHINE))
    if not ok then
        return false, err
    end

    return true, nil
end

--=============================================================================
-- Public API
--=============================================================================

--=========================================================================
-- Function: ATC_Unload.UnloadTool
-- Purpose:  Entry point for complete unload sequence with sanity checks.
--=========================================================================
function ATC_Unload.UnloadTool()
    local inst = ATC_Runtime.GetInstance()
    ATC_Pockets.LoadPockets()

    local currentTool, curErr = ATC_Runtime.GetCurrentToolNumber(inst)
    if currentTool == nil then
        return ATC_Runtime.NotifyFailure("ATC_UNLOAD", curErr)
    end

    local pocket, mapErr = ATC_ToolMap.GetPocketForTool(currentTool, false)
    if pocket == nil then
        return ATC_Runtime.NotifyFailure("ATC_UNLOAD", mapErr)
    end

    local ok, reason = CanUnloadTool(inst, pocket, currentTool)
    if not ok then
        return ATC_Runtime.NotifyFailure("ATC_UNLOAD", reason)
    end

    Log(string.format("Unloading current tool T%d to pocket %d.", currentTool, tonumber(pocket.id) or -1))

    local moved, moveErr = MoveOverSelectedPocket(inst, pocket)
    if not moved then
        return ATC_Runtime.NotifyFailure("ATC_UNLOAD", moveErr or "Failed during move-to-pocket stage.")
    end

    local clearOk, clearErr = ATC_Runtime.SetCurrentTool(inst, 0)
    if not clearOk then
        return ATC_Runtime.NotifyFailure("ATC_UNLOAD", clearErr)
    end

    Log("Unload complete. Current tool set to T0.")
    return true
end

_G.ATC_Unload = ATC_Unload
return ATC_Unload

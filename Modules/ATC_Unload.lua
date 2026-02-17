--=============================================================================
-- File:        ATC_Unload.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Automatic tool unload sequence (module scope).
--
-- Description:
--   - First-step implementation for Unload Tool button.
--   - Stops spindle, raises Z to machine-safe top, then moves over selected
--     pocket using a negative X pre-approach, and ends above pocket center.
--=============================================================================

local ATC_Pockets = require("ATC_Pockets")
local ATC_Manual = require("ATC_ManualControls")
local ATC_Config = require("ATC_Config")

local ATC_Unload = {}

--=============================================================================
-- Constants
--=============================================================================

-- Axis IDs for Mach4 APIs.
local AXIS_X = 0
local AXIS_Y = 1
local AXIS_Z = 2

-- Approach offset before pocket center move.
-- Requirement: move 2.0 inches in X negative direction first.
local UNLOAD_APPROACH_OFFSET_X = ATC_Config.Motion.PocketClearanceOffsetX

-- feedrate for approaching
local XY_APPROACH_FEED_IPM = 500.0

-- Machine-coordinate safe Z for travel.
local SAFE_Z_MACHINE = ATC_Config.Motion.SafeZMachine

-- Z clearance above taught pocket Z before full insert.
local POCKET_Z_APPROACH_CLEARANCE = ATC_Config.Motion.PocketZApproachClearance

-- Drawbar open settle time before retract.
local DRAWBAR_OPEN_WAIT_MS = 250

--=============================================================================
-- Helpers
--=============================================================================

--=========================================================================
-- Function: GetInstance
-- Purpose:  Return active Mach4 instance handle.
--=========================================================================
local function GetInstance()
    return mc.mcGetInstance()
end

--=========================================================================
-- Function: Log
-- Purpose:  Post a status/history message to Mach4.
--=========================================================================
local function Log(msg)
    mc.mcCntlSetLastError(GetInstance(), tostring(msg))
end

--=========================================================================
-- Function: IsAxisHomed
-- Purpose:  Return true when axis is homed and API call succeeds.
--=========================================================================
local function IsAxisHomed(inst, axisId)
    local homed, rc = mc.mcAxisIsHomed(inst, axisId)
    return (rc == mc.MERROR_NOERROR and homed == 1)
end

--=========================================================================
-- Function: WaitForIdle
-- Purpose:  Wait for controller to reach IDLE state.
--=========================================================================
local function WaitForIdle(inst, timeoutMs)
    local waited = 0
    while waited < timeoutMs do
        local st, rc = mc.mcCntlGetState(inst)
        if rc == mc.MERROR_NOERROR and st == mc.MC_STATE_IDLE then
            return true
        end
        wx.wxMilliSleep(20)
        waited = waited + 20
    end
    return false
end

--=========================================================================
-- Function: ExecGcodeWait
-- Purpose:  Execute one G-code command and return success/failure.
-- Returns:  ok (bool), reason (string|nil)
--=========================================================================
local function ExecGcodeWait(inst, gcode)
    if not WaitForIdle(inst, 3000) then
        return false, "Controller not idle before command: " .. tostring(gcode)
    end

    local rc = mc.mcCntlGcodeExecuteWait(inst, gcode)
    if rc ~= mc.MERROR_NOERROR then
        return false, "G-code failed rc=" .. tostring(rc) .. " cmd=" .. tostring(gcode)
    end
    return true, nil
end

--=========================================================================
-- Function: NotifyFailure
-- Purpose:  Show error, then recover machine to idle state.
--=========================================================================
local function NotifyFailure(reason)
    local inst = GetInstance()
    local msg = "ATC_LOAD ERROR: " .. tostring(reason)   -- use ATC_UNLOAD in unload module
    Log(msg)
    wx.wxMessageBox(msg)

    -- Force stop now (no “wait and retry” behavior).
    mc.mcCntlFeedHold(inst)
    mc.mcCntlCycleStop(inst)

    -- Safe outputs off immediately.
    ATC_Manual.Reset()

    return false
end

--=========================================================================
-- Function: CanUnloadTool
-- Purpose:  Validate whether automatic unload can run safely.
-- Returns:  ok (bool), reason (string|nil), currentTool (number|nil)
--=========================================================================
local function CanUnloadTool(inst, pocket)
    if not IsAxisHomed(inst, AXIS_X) or not IsAxisHomed(inst, AXIS_Y) or not IsAxisHomed(inst, AXIS_Z) then
        return false, "X/Y/Z must be homed before unload."
    end

    local currentTool, rcTool = mc.mcToolGetCurrent(inst)
    if rcTool ~= mc.MERROR_NOERROR then
        return false, "Failed to read current tool. rc=" .. tostring(rcTool)
    end

    currentTool = tonumber(currentTool) or 0
    if currentTool <= 0 then
        return false, "No active tool in spindle."
    end

    if pocket == nil then
        return false, "No pocket selected."
    end

    if pocket.taught ~= true then
        return false, "Selected pocket is not taught."
    end

    local pocketTool = tonumber(pocket.tool) or -1
    if pocketTool <= 0 then
        return false, "Selected pocket has no assigned tool."
    end

    if pocketTool ~= currentTool then
        return false, string.format(
            "Current tool T%d does not match selected pocket %d assignment (T%d).",
            currentTool, tonumber(pocket.id) or -1, pocketTool
        )
    end

    return true, nil, currentTool
end

--=========================================================================
-- Function: ATC_Unload.MoveOverSelectedPocket
-- Purpose:  First-step unload path to move over selected pocket and stop.
-- Notes:
--   - This function assumes higher-level sanity checks are done by caller.
--   - It performs only the motion sequence and command-level error checks.
--=========================================================================
local function MoveOverSelectedPocket(pocketData)
    local inst = GetInstance()
    local p = pocketData or ATC_Pockets.GetCurrentPocketData()

    if type(p) ~= "table" then
        return false, "No pocket data provided."
    end

    local x = tonumber(p.x)
    local y = tonumber(p.y)
    local z = tonumber(p.z)
    if x == nil or y == nil or z == nil then
        return false, "Pocket X/Y/Z is invalid."
    end

    local ok, err = ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", SAFE_Z_MACHINE))
    if not ok then
        return false, err
    end

    local preX = x + UNLOAD_APPROACH_OFFSET_X
    local xyCmd = string.format(
        "G53 G1 F%.1f X%.4f Y%.4f\nG53 G1 X%.4f Y%.4f",
        XY_APPROACH_FEED_IPM, preX, y, x, y
    )
    local ok, err = ExecGcodeWait(inst, xyCmd)
    if not ok then
        return false, err
    end

    local zApproach = z + POCKET_Z_APPROACH_CLEARANCE
    local ok, err = ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", zApproach))
    if not ok then
        return false, err
    end

    ATC_Manual.DrawbarOpenEnable()
    wx.wxMilliSleep(DRAWBAR_OPEN_WAIT_MS)

    local ok, err = ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", SAFE_Z_MACHINE))
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
    local inst = GetInstance()
    local pocket = ATC_Pockets.GetCurrentPocketData()

    local ok, reason, currentTool = CanUnloadTool(inst, pocket)
    if not ok then
        return NotifyFailure(reason)
    end

    -- move over selected pocket.
    local moved, moveErr = MoveOverSelectedPocket(pocket)
    if not moved then
        return NotifyFailure(moveErr or "Failed during move-to-pocket stage.")
    end

    return true
end

_G.ATC_Unload = ATC_Unload
return ATC_Unload

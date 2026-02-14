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
local UNLOAD_APPROACH_OFFSET_X = -2.0

-- Machine-coordinate safe Z for travel.
-- Set this to your machine top safe Z in machine coordinates.
local SAFE_Z_MACHINE = 0.0

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
-- Function: ExecGcodeWait
-- Purpose:  Execute one G-code command and return success/failure.
--=========================================================================
local function ExecGcodeWait(inst, gcode)
    local rc = mc.mcCntlGcodeExecuteWait(inst, gcode)
    if rc ~= mc.MERROR_NOERROR then
        Log("ATC_UNLOAD ERROR: G-code failed rc=" .. tostring(rc) .. " cmd=" .. tostring(gcode))
        return false
    end
    return true
end

--=========================================================================
-- Function: ValidatePocketForUnload
-- Purpose:  Validate selected pocket record before motion.
--=========================================================================
local function ValidatePocketForUnload(p)
    if p == nil then
        return false, "No pocket selected."
    end

    if p.taught ~= true then
        return false, "Selected pocket is not taught."
    end

    if p.x == nil or p.y == nil or p.z == nil then
        return false, "Selected pocket has invalid coordinates."
    end

    return true, nil
end

--=============================================================================
-- Public API
--=============================================================================

--=========================================================================
-- Function: ATC_Unload.MoveOverSelectedPocket
-- Purpose:  First-step unload path to move over selected pocket and stop.
-- Sequence:
--   1) Verify X/Y/Z homed.
--   2) Stop spindle.
--   3) Move Z to SAFE_Z_MACHINE in machine coordinates.
--   4) Move XY to (pocketX + UNLOAD_APPROACH_OFFSET_X, pocketY).
--   5) Move XY to (pocketX, pocketY).
--=========================================================================
function ATC_Unload.MoveOverSelectedPocket()
    local inst = GetInstance()

    if not IsAxisHomed(inst, AXIS_X) or not IsAxisHomed(inst, AXIS_Y) or not IsAxisHomed(inst, AXIS_Z) then
        Log("ATC_UNLOAD ERROR: X/Y/Z must be homed before unload move.")
        return false
    end

    local p = ATC_Pockets.GetCurrentPocketData()
    local ok, reason = ValidatePocketForUnload(p)
    if not ok then
        Log("ATC_UNLOAD ERROR: " .. tostring(reason))
        return false
    end

    if not ExecGcodeWait(inst, "M5") then
        return false
    end

    if not ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", SAFE_Z_MACHINE)) then
        return false
    end

    local preX = tonumber(p.x) + UNLOAD_APPROACH_OFFSET_X
    local preY = tonumber(p.y)
    if not ExecGcodeWait(inst, string.format("G53 G0 X%.4f Y%.4f", preX, preY)) then
        return false
    end

    if not ExecGcodeWait(inst, string.format("G53 G0 X%.4f Y%.4f", tonumber(p.x), tonumber(p.y))) then
        return false
    end

    Log(string.format("ATC_UNLOAD: Positioned over pocket %d at X=%.4f Y=%.4f (Z safe %.4f).", p.id, p.x, p.y, SAFE_Z_MACHINE))
    return true
end

_G.ATC_Unload = ATC_Unload
return ATC_Unload

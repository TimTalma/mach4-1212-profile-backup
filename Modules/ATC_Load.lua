--=============================================================================
-- File:        ATC_Load.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Automatic tool load sequence (module scope).
--=============================================================================

local ATC_IO = require("ATC_IO")
local ATC_Pockets = require("ATC_Pockets")
local ATC_Unload  = require("ATC_Unload")
local ATC_ToolMap = require("ATC_ToolMap")
local ATC_Runtime = require("ATC_Runtime")
local ATC_Config = require("ATC_Config")
local ATC_Manual = require("ATC_ManualControls")

local ATC_Load = {}

--=============================================================================
-- Constants
--=============================================================================
local LOAD_Z_BLOWOFF_CLEARANCE = ATC_Config.Motion.LoadZBlowoffClearance
local POCKET_Z_APPROACH_CLEARANCE = ATC_Config.Motion.PocketZApproachClearance
local UNLOAD_APPROACH_OFFSET_X = ATC_Config.Motion.PocketClearanceOffsetX
local DRAWBAR_CLOSE_HOLD_MS = ATC_Config.Timing.DrawbarCloseHoldMs
local LOAD_Z_SYNC_FEED_IPM  = ATC_Config.Motion.LoadZSyncFeedIpm
local LOAD_Z_CAPTURE_OFFSET = ATC_Config.Motion.LoadZCaptureOffset
local LOAD_APPROACH_FEED_IPM = ATC_Config.Motion.LoadApproachFeedIpm
local TOOL_SEAT_RETRY_LIFT = ATC_Config.Motion.ToolSeatRetryLift
local TOOL_SEAT_INPUT_SETTLE_MS = ATC_Config.Timing.ToolSeatSettleMs

--=============================================================================
-- Helpers
--=============================================================================

--=========================================================================
-- Function: Log
-- Purpose:  Write load-scoped log message.
--=========================================================================
local function Log(msg)
    ATC_Runtime.Log("ATC_LOAD: " .. tostring(msg))
end

--=========================================================================
-- Function: IsToolSeated
-- Purpose:  Read tool seated input with short settle delay.
--=========================================================================
local function IsToolSeated()
    wx.wxMilliSleep(TOOL_SEAT_INPUT_SETTLE_MS)
    return ATC_IO.GetInputState("ToolSeated")
end

--=========================================================================
-- Function: CloseDrawbarAndLowerToCaptureZ
-- Purpose:  Lower to capture Z while drawbar close is energized.
--=========================================================================
local function CloseDrawbarAndLowerToCaptureZ(inst, pocketZ)
    local zTarget = tonumber(pocketZ) + LOAD_Z_CAPTURE_OFFSET

    ATC_Manual.DrawbarCloseEnable()

    local ok, err = ATC_Runtime.ExecGcodeWait(
        inst,
        string.format("G53 G1 F%.1f Z%.4f", LOAD_Z_SYNC_FEED_IPM, zTarget)
    )
    if not ok then
        ATC_Manual.DrawbarCloseDisable()
        return false, err
    end

    ok, err = ATC_Runtime.ExecGcodeWait(
        inst,
        string.format("G04 P%.3f", DRAWBAR_CLOSE_HOLD_MS / 1000.0)
    )
    if not ok then
        ATC_Manual.DrawbarCloseDisable()
        return false, err
    end

    ATC_Manual.DrawbarCloseDisable()
    return true, nil
end

--=========================================================================
-- Function: EnsureToolSeatedOrRecover
-- Purpose:  Verify tool seated, retry once, then prompt operator.
--=========================================================================
local function EnsureToolSeatedOrRecover(inst, pocketZ)
    local seated, seatErr = IsToolSeated()
    if seatErr ~= nil then
        return false, seatErr
    end

    if seated then
        return true, nil
    end

    Log("Tool not seated. Retrying load once.")

    ATC_Manual.DrawbarOpenEnable()

    local curZ, zErr = ATC_Runtime.GetMachineZ(inst)
    if curZ == nil then
        return false, zErr
    end

    local ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G1 F100.0 Z%.4f", curZ + TOOL_SEAT_RETRY_LIFT))
    if not ok then
        return false, err
    end

    ok, err = CloseDrawbarAndLowerToCaptureZ(inst, pocketZ)
    if not ok then
        return false, err
    end

    seated, seatErr = IsToolSeated()
    if seatErr ~= nil then
        return false, seatErr
    end

    if seated then
        Log("Tool seated on retry.")
        return true, nil
    end

    wx.wxMessageBox("Tool did not seat. Manually seat the tool, then press OK.")

    ATC_Manual.DrawbarCloseEnable()
    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G04 P%.3f", DRAWBAR_CLOSE_HOLD_MS / 1000.0))
    ATC_Manual.DrawbarCloseDisable()
    if not ok then
        return false, err
    end

    return true, nil
end

--=========================================================================
-- Function: ExecuteToolPickupSequence
-- Purpose:  Execute complete pocket pickup motion/IO sequence.
--=========================================================================
local function ExecuteToolPickupSequence(inst, pocket)
    local x = tonumber(pocket.x)
    local y = tonumber(pocket.y)
    local z = tonumber(pocket.z)

    if x == nil or y == nil or z == nil then
        return false, "Requested pocket X/Y/Z is invalid."
    end

    local ok, err = ATC_Runtime.MoveToSafeZ(inst)
    if not ok then
        return false, err
    end

    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 X%.4f Y%.4f", x, y))
    if not ok then
        return false, err
    end

    local zApproach = z + LOAD_Z_BLOWOFF_CLEARANCE
    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", zApproach))
    if not ok then
        return false, err
    end

    ATC_Manual.BlowOffEnable()

    zApproach = z + POCKET_Z_APPROACH_CLEARANCE
    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G1 F%.1f Z%.4f", LOAD_APPROACH_FEED_IPM, zApproach))
    ATC_Manual.BlowOffDisable()
    if not ok then
        return false, err
    end

    ok, err = CloseDrawbarAndLowerToCaptureZ(inst, z)
    if not ok then
        return false, err
    end

    ok, err = EnsureToolSeatedOrRecover(inst, z)
    if not ok then
        return false, err
    end

    ok, err = ATC_Runtime.MoveToSafeZ(inst)
    if not ok then
        return false, err
    end

    local approachX = x + UNLOAD_APPROACH_OFFSET_X
    ok, err = ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 X%.4f", approachX))
    if not ok then
        return false, err
    end

    Log(string.format(
        "Tool pickup sequence complete at pocket %d X=%.4f Y=%.4f Z=%.4f (%.3f above tool Z).",
        tonumber(pocket.id) or -1,
        x,
        y,
        zApproach,
        POCKET_Z_APPROACH_CLEARANCE
    ))

    return true, nil
end

--=============================================================================
-- Public API
--=============================================================================

--=========================================================================
-- Function: ATC_Load.LoadTool
-- Purpose:  Unload current tool, then load requested tool.
--=========================================================================
function ATC_Load.LoadTool(requestedToolNum)
    local inst = ATC_Runtime.GetInstance()
    local requestedTool = tonumber(requestedToolNum)

    if requestedTool == nil or requestedTool <= 0 then
        return ATC_Runtime.NotifyFailure("ATC_LOAD", "Requested tool number is invalid.")
    end

    ATC_Pockets.LoadPockets(false)

    local pocket, mapErr = ATC_ToolMap.GetPocketForTool(requestedTool, false)
    if pocket == nil then
        return ATC_Runtime.NotifyFailure("ATC_LOAD", mapErr)
    end

    local valid, validErr = ATC_ToolMap.ValidatePocketForTool(requestedTool, pocket)
    if not valid then
        return ATC_Runtime.NotifyFailure("ATC_LOAD", validErr)
    end

    local currentTool, curErr = ATC_Runtime.GetCurrentToolNumber(inst)
    if currentTool == nil then
        return ATC_Runtime.NotifyFailure("ATC_LOAD", curErr)
    end

    Log(string.format("Request T%d. Current tool T%d.", requestedTool, currentTool))

    if currentTool == requestedTool then
        local ok, err = ATC_Runtime.MoveToSafeZ(inst)
        if not ok then
            return ATC_Runtime.NotifyFailure("ATC_LOAD", err)
        end

        Log(string.format("T%d already loaded. Raised to safe Z and continuing.", requestedTool))
        return true
    end

    if currentTool > 0 then
        Log(string.format("Unloading current tool T%d.", currentTool))
        if not ATC_Unload.UnloadTool() then
            return false
        end
    end

    Log(string.format("Loading requested tool T%d from pocket %d.", requestedTool, tonumber(pocket.id) or -1))

    local moved, moveErr = ExecuteToolPickupSequence(inst, pocket)
    if not moved then
        return ATC_Runtime.NotifyFailure("ATC_LOAD", moveErr or "Failed moving over requested tool pocket.")
    end

    local okSet, setErr = ATC_Runtime.SetCurrentTool(inst, requestedTool)
    if not okSet then
        return ATC_Runtime.NotifyFailure("ATC_LOAD", setErr)
    end

    Log(string.format("Tool load complete. Current tool set to T%d.", requestedTool))
    return true
end

_G.ATC_Load = ATC_Load
return ATC_Load

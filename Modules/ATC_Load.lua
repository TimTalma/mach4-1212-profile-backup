--=============================================================================
-- File:        ATC_Load.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Automatic tool load sequence (module scope).
--
-- Description:
--   - Entry point accepts requested tool number.
--   - If requested tool already loaded: raise to safe Z and return success.
--   - Otherwise unload current tool, then move over requested tool pocket.
--   - First-step implementation stops above requested pocket (no pickup yet).
--=============================================================================
local ATC_IO = require("ATC_IO")
local ATC_Pockets = require("ATC_Pockets")
local ATC_Unload  = require("ATC_Unload")
local ATC_Config = require("ATC_Config")
local ATC_Manual = require("ATC_ManualControls")

local ATC_Load = {}

--=============================================================================
-- Constants
--=============================================================================
-- The height where the blowoff will turn on
local LOAD_Z_BLOWOFF_CLEARANCE = 1.0

-- Z clearance above taught pocket Z before full insert.
local POCKET_Z_APPROACH_CLEARANCE = ATC_Config.Motion.PocketZApproachClearance

local UNLOAD_APPROACH_OFFSET_X = ATC_Config.Motion.PocketClearanceOffsetX

-- Drawbar close energize duration (tune as needed).
local DRAWBAR_CLOSE_HOLD_MS = 1000

-- Feed rate at which to move down to tool-capture Z (tune as needed).
local LOAD_Z_SYNC_FEED_IPM  = 200

-- Target Z relative to taught pocket Z for tool capture.
-- Example: 0.000 means exact taught Z.
local LOAD_Z_CAPTURE_OFFSET = 0.000

-- safe height to move Z axis to, in machine coordinates
local SAFE_Z_MACHINE = ATC_Config.Motion.SafeZMachine

-- define the axis we need to wait for
local AXIS_Z = 2

-- Tool-seat retry behavior
local TOOL_SEAT_RETRY_LIFT = 0.5
local TOOL_SEAT_INPUT_SETTLE_MS = 100

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

    -- Only stop if not already idle.
    local state, rc = mc.mcCntlGetState(inst)
    if state ~= mc.MC_STATE_IDLE then
        mc.mcCntlFeedHold(inst)
        mc.mcCntlCycleStop(inst)
    end

    -- Safe outputs off immediately.
    ATC_Manual.Reset()

    return false
end

--=========================================================================
-- Function: GetCurrentToolNumber
-- Purpose:  Read current loaded tool number from Mach4.
--=========================================================================
local function GetCurrentToolNumber(inst)
    local tool, rc = mc.mcToolGetCurrent(inst)
    if rc ~= mc.MERROR_NOERROR then
        return nil, "Failed to read current tool. rc=" .. tostring(rc)
    end
    return tonumber(tool) or 0, nil
end

--=========================================================================
-- Function: MoveToSafeZ
-- Purpose:  Move to machine safe Z.
--=========================================================================
local function MoveToSafeZ(inst)
    return ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", SAFE_Z_MACHINE))
end

--=========================================================================
-- Function: SetCurrentTool
-- Purpose:  Update Mach4 current tool after successful load.
--=========================================================================
local function SetCurrentTool(inst, toolNum)
    local rc = mc.mcToolSetCurrent(inst, toolNum)
    if rc ~= mc.MERROR_NOERROR then
        return false, "Failed to set current tool T" .. tostring(toolNum) .. " rc=" .. tostring(rc)
    end
    return true, nil
end

--=========================================================================
-- Function: CloseDrawbarAndLowerToCaptureZ
-- Purpose:  Lower to capture Z while drawbar close is energized, using
--           Mach-managed waits for motion and timing.
--=========================================================================
local function CloseDrawbarAndLowerToCaptureZ(inst, pocketZ)
    local zTarget = tonumber(pocketZ) + LOAD_Z_CAPTURE_OFFSET

    ATC_Manual.DrawbarCloseEnable()

    local ok, err = ExecGcodeWait(
        inst,
        string.format("G53 G1 F%.1f Z%.4f", LOAD_Z_SYNC_FEED_IPM, zTarget)
    )
    if not ok then
        ATC_Manual.DrawbarCloseDisable()
        return false, err
    end

    ok, err = ExecGcodeWait(
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
-- Function: GetMachineZ
-- Purpose:  Read current machine Z position.
--=========================================================================
local function GetMachineZ(inst)
    local z, rc = mc.mcAxisGetMachinePos(inst, AXIS_Z)
    if rc ~= mc.MERROR_NOERROR then
        return nil, "Failed to read machine Z. rc=" .. tostring(rc)
    end

    z = tonumber(z)
    if z == nil then
        return nil, "Machine Z read was not numeric."
    end

    return z, nil
end

--=========================================================================
-- Function: IsToolSeated
-- Purpose:  Read tool seated input with a short settle delay.
--=========================================================================
local function IsToolSeated()
    wx.wxMilliSleep(TOOL_SEAT_INPUT_SETTLE_MS)
    return ATC_IO.GetInput("ToolSeated") == true
end

--=========================================================================
-- Function: EnsureToolSeatedOrRecover
-- Purpose:  Verify tool seated after drawbar close, retry once, then manual prompt.
--=========================================================================
local function EnsureToolSeatedOrRecover(inst, pocketZ)
    -- First check after normal close.
    if IsToolSeated() then
        return true, nil
    end

    Log("ATC_LOAD: Tool not seated. Retrying load once.")

    -- Open drawbar, lift 0.5, then retry close/lower.
    ATC_Manual.DrawbarOpenEnable()

    local curZ, zErr = GetMachineZ(inst)
    if curZ == nil then
        return false, zErr
    end

    local ok, err = ExecGcodeWait(inst, string.format("G53 G1 F100.0 Z%.4f", curZ + TOOL_SEAT_RETRY_LIFT))
    if not ok then
        return false, err
    end

    ok, err = CloseDrawbarAndLowerToCaptureZ(inst, pocketZ)
    if not ok then
        return false, err
    end

    if IsToolSeated() then
        Log("ATC_LOAD: Tool seated on retry.")
        return true, nil
    end

    -- Second failure: operator intervention.
    wx.wxMessageBox("Tool did not seat. Manually seat the tool, then press OK.")

    -- Power drawbar close for 1 second, then continue cycle.
    ATC_Manual.DrawbarCloseEnable()
    ok, err = ExecGcodeWait(inst, string.format("G04 P%.3f", DRAWBAR_CLOSE_HOLD_MS / 1000.0))
    ATC_Manual.DrawbarCloseDisable()
    if not ok then
        return false, err
    end

    return true, nil
end

--=========================================================================
-- Function: ExecuteToolPickupSequence
-- Purpose:  Execute complete pocket pickup motion/IO sequence for a tool.
-- Inputs:
--   inst   (number) - Mach4 instance handle.
--   pocket (table)  - Pocket data with id/x/y/z/taught/tool.
-- Behavior:
--   - Moves to safe Z, applies X approach offset, moves to pocket XY.
--   - Lowers to blowoff clearance, enables blowoff, lowers to pickup clearance.
--   - Disables blowoff, closes drawbar while lowering to capture Z.
--   - Retracts to safe Z.
-- Returns:
--   true, nil on success
--   false, reason on failure
--=========================================================================
local function ExecuteToolPickupSequence(inst, pocket)

    if type(pocket) ~= "table" then
        return false, "Requested tool has no assigned pocket."
    end

    local x = tonumber(pocket.x)
    local y = tonumber(pocket.y)
    local z = tonumber(pocket.z)
    if x == nil or y == nil or z == nil then
        return false, "Requested pocket X/Y/Z is invalid."
    end

    if pocket.taught ~= true then
        return false, string.format("Requested tool pocket %d is not taught.", tonumber(pocket.id) or -1)
    end

    local ok, err = MoveToSafeZ(inst)
    if not ok then
        return false, err
    end

    local ok, err = ExecGcodeWait(inst, string.format("G53 G0 X%.4f Y%.4f", x, y))
    if not ok then
        return false, err
    end

    local zApproach = z + LOAD_Z_BLOWOFF_CLEARANCE
    local ok, err = ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", zApproach))
    if not ok then
        return false, err
    end

    ATC_Manual.BlowOffEnable()

    zApproach = z + POCKET_Z_APPROACH_CLEARANCE
    local ok, err = ExecGcodeWait(inst, string.format("G53 G1 F100 Z%.4f", zApproach))
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

    ok, err = MoveToSafeZ(inst)
    if not ok then
        return false, err
    end

    local approachX = x + UNLOAD_APPROACH_OFFSET_X   -- offset is negative
    ok, err = ExecGcodeWait(inst, string.format("G53 G0 X%.4f", approachX))
    if not ok then
        return false, err
    end

    Log(string.format(
        "ATC_LOAD: Tool pickup sequence complete at pocket %d X=%.4f Y=%.4f Z=%.4f (%.3f above tool Z).",
        tonumber(pocket.id) or -1, x, y, zApproach, POCKET_Z_APPROACH_CLEARANCE
    ))

    return true, nil
end

--=============================================================================
-- Public API
--=============================================================================

--=========================================================================
-- Function: ATC_Load.LoadTool
-- Purpose:  Unload current tool, then begin load sequence for requested tool.
-- Input:    requestedToolNum (number)
--=========================================================================
function ATC_Load.LoadTool(requestedToolNum)
    local inst = GetInstance()
    local requestedTool = tonumber(requestedToolNum)

    if requestedTool == nil or requestedTool <= 0 then
        return NotifyFailure("Requested tool number is invalid.")
    end

    ATC_Pockets.LoadPockets()

    -- Find and validate requested pocket first (before unloading current tool).
    local pocket = ATC_Pockets.FindPocketByTool(requestedTool)
    if pocket == nil then
        return NotifyFailure("Requested tool T" .. tostring(requestedTool) .. " is not assigned to any pocket.")
    end
    if pocket.taught ~= true then
        return NotifyFailure("Requested tool pocket " .. tostring(pocket.id) .. " is not taught.")
    end

    local currentTool, curErr = GetCurrentToolNumber(inst)
    if currentTool == nil then
        return NotifyFailure(curErr)
    end

    Log(string.format("ATC_LOAD: Request T%d. Current tool T%d.", requestedTool, currentTool))

    -- If requested tool already loaded: just move to safe Z and continue.
    if currentTool == requestedTool then
        local ok, err = MoveToSafeZ(inst)
        if not ok then
            return NotifyFailure(err)
        end
        Log(string.format("ATC_LOAD: T%d already loaded. Raised to safe Z and continuing.", requestedTool))
        return true
    end

    -- Only unload after request is confirmed valid.
    if currentTool > 0 then
        Log(string.format("ATC_LOAD: Unloading current tool T%d.", currentTool))
        if not ATC_Unload.UnloadTool() then
            return false -- avoid double-popup/double-reset
        end
    end

    Log(string.format("ATC_LOAD: Loading requested tool T%d from pocket %d.", requestedTool, tonumber(pocket.id) or -1))

    local moved, moveErr = ExecuteToolPickupSequence(inst, pocket)
    if not moved then
        return NotifyFailure(moveErr or "Failed moving over requested tool pocket.")
    end

    local okSet, setErr = SetCurrentTool(inst, requestedTool)
    if not okSet then
        return NotifyFailure(setErr)
    end

    Log(string.format("ATC_LOAD: Tool load complete. Current tool set to T%d.", requestedTool))

    return true
end

_G.ATC_Load = ATC_Load
return ATC_Load


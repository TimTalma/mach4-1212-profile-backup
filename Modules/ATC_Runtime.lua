--=============================================================================
-- File:        ATC_Runtime.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Shared runtime helpers for ATC load/unload modules.
--=============================================================================

local ATC_Config = require("ATC_Config")
local ATC_Manual = require("ATC_ManualControls")

local ATC_Runtime = {}

--=========================================================================
-- Function: ATC_Runtime.GetInstance
-- Purpose:  Return active Mach4 instance handle.
--=========================================================================
function ATC_Runtime.GetInstance()
    return mc.mcGetInstance()
end

--=========================================================================
-- Function: ATC_Runtime.Log
-- Purpose:  Post a status/history message to Mach4.
--=========================================================================
function ATC_Runtime.Log(msg)
    mc.mcCntlSetLastError(ATC_Runtime.GetInstance(), tostring(msg))
end

--=========================================================================
-- Function: ATC_Runtime.IsAxisHomed
-- Purpose:  Return true when axis is homed and API call succeeds.
--=========================================================================
function ATC_Runtime.IsAxisHomed(inst, axisId)
    local homed, rc = mc.mcAxisIsHomed(inst, axisId)
    return (rc == mc.MERROR_NOERROR and homed == 1)
end

--=========================================================================
-- Function: ATC_Runtime.GetCurrentToolNumber
-- Purpose:  Read current loaded tool number from Mach4.
--=========================================================================
function ATC_Runtime.GetCurrentToolNumber(inst)
    local tool, rc = mc.mcToolGetCurrent(inst)
    if rc ~= mc.MERROR_NOERROR then
        return nil, "Failed to read current tool. rc=" .. tostring(rc)
    end
    return tonumber(tool) or 0, nil
end

--=========================================================================
-- Function: ATC_Runtime.SetCurrentTool
-- Purpose:  Update Mach4 current tool number.
--=========================================================================
function ATC_Runtime.SetCurrentTool(inst, toolNum)
    local rc = mc.mcToolSetCurrent(inst, toolNum)
    if rc ~= mc.MERROR_NOERROR then
        return false, "Failed to set current tool T" .. tostring(toolNum) .. " rc=" .. tostring(rc)
    end
    return true, nil
end

--=========================================================================
-- Function: ATC_Runtime.GetMachineZ
-- Purpose:  Read current machine Z position.
--=========================================================================
function ATC_Runtime.GetMachineZ(inst)
    local z, rc = mc.mcAxisGetMachinePos(inst, 2)
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
-- Function: ATC_Runtime.ExecGcodeWait
-- Purpose:  Execute one G-code command and return success/failure.
--=========================================================================
function ATC_Runtime.ExecGcodeWait(inst, gcode)
    if type(gcode) ~= "string" or gcode == "" then
        return false, "G-code command is empty."
    end

    local rc = mc.mcCntlGcodeExecuteWait(inst, gcode)
    if rc ~= mc.MERROR_NOERROR then
        return false, "G-code failed rc=" .. tostring(rc) .. " cmd=" .. tostring(gcode)
    end

    return true, nil
end

--=========================================================================
-- Function: ATC_Runtime.MoveToSafeZ
-- Purpose:  Move Z to configured machine-safe height.
--=========================================================================
function ATC_Runtime.MoveToSafeZ(inst)
    return ATC_Runtime.ExecGcodeWait(inst, string.format("G53 G0 Z%.4f", ATC_Config.Motion.SafeZMachine))
end

--=========================================================================
-- Function: ATC_Runtime.AbortToIdle
-- Purpose:  Stop active cycle and force safe outputs OFF.
--=========================================================================
function ATC_Runtime.AbortToIdle(inst)
    local state, rc = mc.mcCntlGetState(inst)
    if rc == mc.MERROR_NOERROR and state ~= mc.MC_STATE_IDLE then
        mc.mcCntlFeedHold(inst)
        mc.mcCntlCycleStop(inst)
    end

    ATC_Manual.Reset()
end

--=========================================================================
-- Function: ATC_Runtime.NotifyFailure
-- Purpose:  Log and display fault, then force safe idle recovery.
--=========================================================================
function ATC_Runtime.NotifyFailure(prefix, reason)
    local inst = ATC_Runtime.GetInstance()
    local msg = tostring(prefix) .. " ERROR: " .. tostring(reason)

    ATC_Runtime.Log(msg)
    wx.wxMessageBox(msg)
    ATC_Runtime.AbortToIdle(inst)

    return false
end

_G.ATC_Runtime = ATC_Runtime
return ATC_Runtime

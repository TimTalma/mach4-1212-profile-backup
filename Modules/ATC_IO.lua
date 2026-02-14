--=============================================================================
-- File:        ATC_IO.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Mach4 I/O abstraction layer for ATC-related signals.
--
-- Description:
--   - Centralizes all Mach4 signal access (outputs + inputs).
--   - Converts Mach "Output N / Input N" numbering to Lua enums.
--   - Posts messages to Mach4 status + history using mcCntlSetLastError().
--=============================================================================

local ATC_Config = require("ATC_Config")

local ATC_IO = {}

--=========================================================================
-- Internal helpers
--=========================================================================

local function GetInst()
    return mc.mcGetInstance()
end

local function OutputEnumFromNumber(outputNumber)
    if outputNumber == nil or outputNumber < 0 then
        return nil
    end
    return mc.OSIG_OUTPUT0 + outputNumber
end

local function InputEnumFromNumber(inputNumber)
    if inputNumber == nil or inputNumber < 0 then
        return nil
    end
    return mc.ISIG_INPUT0 + inputNumber
end

local function GetSignalHandle(sigEnum, signalLabel)
    local inst = GetInst()
    local hSig, rc = mc.mcSignalGetHandle(inst, sigEnum)

    if rc ~= mc.MERROR_NOERROR or hSig == nil or hSig == 0 then
        ATC_IO.Post(
            "ATC_IO ERROR: mcSignalGetHandle failed for " ..
            tostring(signalLabel) ..
            " enum=" .. tostring(sigEnum) ..
            " rc=" .. tostring(rc) ..
            " hSig=" .. tostring(hSig)
        )
        return nil, rc
    end

    return hSig, rc
end


--=========================================================================
-- Function: ATC_IO.Post
-- Purpose:  Write a message to Mach4 status line and message history.
--=========================================================================
function ATC_IO.Post(msg)
    local inst = GetInst()
    mc.mcCntlSetLastError(inst, tostring(msg))
end

--=========================================================================
-- Function: ATC_IO.SetOutputByNumber
-- Purpose:  Set a Mach4 output ON or OFF by output number.
-- Inputs:
--   outputNumber (number) - Mach Output number
--   isOn         (bool)   - true = ON, false = OFF
--=========================================================================
function ATC_IO.SetOutputByNumber(outputNumber, isOn)
    local sigEnum = OutputEnumFromNumber(outputNumber)
    if sigEnum == nil then
        ATC_IO.Post("ATC_IO ERROR: Invalid output number.")
        return false
    end

    local hSig = GetSignalHandle(sigEnum, "Output #" .. tostring(outputNumber))
    if hSig == nil then
        return false
    end

    local desired = (isOn == true) and 1 or 0
    local rcSet = mc.mcSignalSetState(hSig, desired)
    if rcSet ~= mc.MERROR_NOERROR then
        ATC_IO.Post(
            "ATC_IO ERROR: mcSignalSetState failed for Output #" ..
            tostring(outputNumber) .. " rc=" .. tostring(rcSet)
        )
        return false
    end

    local after, rcGet = mc.mcSignalGetState(hSig)
    if rcGet ~= mc.MERROR_NOERROR then
        ATC_IO.Post(
            "ATC_IO ERROR: mcSignalGetState failed for Output #" ..
            tostring(outputNumber) .. " rc=" .. tostring(rcGet)
        )
        return false
    end

    ATC_IO.Post(
        "ATC_IO: Output #" .. tostring(outputNumber) ..
        " set=" .. tostring(desired) ..
        " readback=" .. tostring(after)
    )

    return (after == desired)
end

--=========================================================================
-- Function: ATC_IO.GetOutputByNumber
-- Purpose:  Read the current state of a Mach4 output.
--=========================================================================
function ATC_IO.GetOutputByNumber(outputNumber)
    local sigEnum = OutputEnumFromNumber(outputNumber)
    if sigEnum == nil then
        return false
    end

    local hSig = GetSignalHandle(sigEnum, "Output #" .. tostring(outputNumber))
    if hSig == nil then
        return false
    end

    local state, rc = mc.mcSignalGetState(hSig)
    if rc ~= mc.MERROR_NOERROR then
        ATC_IO.Post(
            "ATC_IO ERROR: mcSignalGetState failed for Output #" ..
            tostring(outputNumber) .. " rc=" .. tostring(rc)
        )
        return false
    end

    return (state == 1)
end

--=========================================================================
-- Function: ATC_IO.GetInputByNumber
-- Purpose:  Read the current state of a Mach4 input.
--=========================================================================
function ATC_IO.GetInputByNumber(inputNumber)
    local sigEnum = InputEnumFromNumber(inputNumber)
    if sigEnum == nil then
        return false
    end

    local hSig = GetSignalHandle(sigEnum, "Input #" .. tostring(inputNumber))
    if hSig == nil then
        return false
    end

    local state, rc = mc.mcSignalGetState(hSig)
    if rc ~= mc.MERROR_NOERROR then
        ATC_IO.Post(
            "ATC_IO ERROR: mcSignalGetState failed for Input #" ..
            tostring(inputNumber) .. " rc=" .. tostring(rc)
        )
        return false
    end

    return (state == 1)
end

--=========================================================================
-- Function: ATC_IO.SetOutput
-- Purpose:  Set an output using a logical ATC output name.
--=========================================================================
function ATC_IO.SetOutput(name, isOn)
    local outNum = ATC_Config.Outputs[name]
    if outNum == nil then
        ATC_IO.Post("ATC_IO ERROR: Unknown output name: " .. tostring(name))
        return false
    end
    return ATC_IO.SetOutputByNumber(outNum, isOn)
end

--=========================================================================
-- Function: ATC_IO.GetOutput
-- Purpose:  Read an output using a logical ATC output name.
--=========================================================================
function ATC_IO.GetOutput(name)
    local outNum = ATC_Config.Outputs[name]
    if outNum == nil then
        return false
    end
    return ATC_IO.GetOutputByNumber(outNum)
end

--=========================================================================
-- Function: ATC_IO.GetInput
-- Purpose:  Read an input using a logical ATC input name.
--=========================================================================
function ATC_IO.GetInput(name)
    local inNum = ATC_Config.Inputs[name]
    if inNum == nil then
        return false
    end
    return ATC_IO.GetInputByNumber(inNum)
end

--=========================================================================
-- Function: ATC_IO.PulseOutput
-- Purpose:  Turn an output ON for a fixed duration, then OFF.
--=========================================================================
function ATC_IO.PulseOutput(name, pulseMs)
    local ms = pulseMs or ATC_Config.Timing.BlowOffPulseMs

    if not ATC_IO.SetOutput(name, true) then
        return false
    end

    wx.wxMilliSleep(ms)
    ATC_IO.SetOutput(name, false)
    return true
end

--=========================================================================
-- Function: ATC_IO.WaitForInput
-- Purpose:  Wait until an input reaches a desired state or times out.
--=========================================================================
function ATC_IO.WaitForInput(name, desiredState, timeoutMs)
    local timeout = timeoutMs or ATC_Config.Timing.DefaultTimeoutMs
    local startTime = wx.wxGetUTCTimeMillis():GetValue()

    while true do
        if ATC_IO.GetInput(name) == (desiredState == true) then
            return true
        end

        local now = wx.wxGetUTCTimeMillis():GetValue()
        if (now - startTime) >= timeout then
            ATC_IO.Post(
                "ATC_IO TIMEOUT: Input '" .. tostring(name) ..
                "' did not become " .. tostring(desiredState)
            )
            return false
        end

        wx.wxMilliSleep(10)
    end
end

_G.ATC_IO = ATC_IO
return ATC_IO


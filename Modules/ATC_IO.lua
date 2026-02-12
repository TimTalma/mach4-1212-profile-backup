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

local function GetSignalHandle(sigEnum)
    local inst = GetInst()
    return mc.mcSignalGetHandle(inst, sigEnum)
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

    local hSig = GetSignalHandle(sigEnum)
    if hSig == 0 then
        ATC_IO.Post("ATC_IO ERROR: No handle for Output #" .. tostring(outputNumber))
        return false
    end

    mc.mcSignalSetState(hSig, (isOn == true) and 1 or 0)

    -- Readback for verification
    local after = mc.mcSignalGetState(hSig)
    ATC_IO.Post(
        "ATC_IO: Output #" .. tostring(outputNumber) ..
        " set=" .. tostring((isOn == true) and 1 or 0) ..
        " readback=" .. tostring(after)
    )

    return true
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

    local hSig = GetSignalHandle(sigEnum)
    if hSig == 0 then
        return false
    end

    return (mc.mcSignalGetState(hSig) == 1)
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

    local hSig = GetSignalHandle(sigEnum)
    if hSig == 0 then
        return false
    end

    return (mc.mcSignalGetState(hSig) == 1)
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

    wxMilliSleep(ms)
    ATC_IO.SetOutput(name, false)
    return true
end

--=========================================================================
-- Function: ATC_IO.WaitForInput
-- Purpose:  Wait until an input reaches a desired state or times out.
--=========================================================================
function ATC_IO.WaitForInput(name, desiredState, timeoutMs)
    local timeout = timeoutMs or ATC_Config.Timing.DefaultTimeoutMs
    local startTime = wxGetUTCTimeMillis():GetValue()

    while true do
        if ATC_IO.GetInput(name) == (desiredState == true) then
            return true
        end

        local now = wxGetUTCTimeMillis():GetValue()
        if (now - startTime) >= timeout then
            ATC_IO.Post(
                "ATC_IO TIMEOUT: Input '" .. tostring(name) ..
                "' did not become " .. tostring(desiredState)
            )
            return false
        end

        wxMilliSleep(10)
    end
end

_G.ATC_IO = ATC_IO
return ATC_IO
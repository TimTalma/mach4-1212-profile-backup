--=============================================================================
-- File:        ATC_IO.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Mach4 I/O abstraction layer for ATC-related signals.
--=============================================================================

local ATC_Config = require("ATC_Config")

local ATC_IO = {}

--=========================================================================
-- Internal helpers
--=========================================================================

--=========================================================================
-- Function: GetInst
-- Purpose:  Return active Mach4 instance.
--=========================================================================
local function GetInst()
    return mc.mcGetInstance()
end

--=========================================================================
-- Function: OutputEnumFromNumber
-- Purpose:  Convert output number to Mach signal enum.
--=========================================================================
local function OutputEnumFromNumber(outputNumber)
    if outputNumber == nil or outputNumber < 0 then
        return nil
    end
    return mc.OSIG_OUTPUT0 + outputNumber
end

--=========================================================================
-- Function: InputEnumFromNumber
-- Purpose:  Convert input number to Mach signal enum.
--=========================================================================
local function InputEnumFromNumber(inputNumber)
    if inputNumber == nil or inputNumber < 0 then
        return nil
    end
    return mc.ISIG_INPUT0 + inputNumber
end

--=========================================================================
-- Function: GetSignalHandle
-- Purpose:  Return signal handle for enum.
--=========================================================================
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
-- Function: ReadSignalState
-- Purpose:  Read signal state and propagate API errors.
--=========================================================================
local function ReadSignalState(sigEnum, signalLabel)
    local hSig = GetSignalHandle(sigEnum, signalLabel)
    if hSig == nil then
        return nil, "Failed to get signal handle for " .. tostring(signalLabel)
    end

    local state, rc = mc.mcSignalGetState(hSig)
    if rc ~= mc.MERROR_NOERROR then
        local err = "mcSignalGetState failed for " .. tostring(signalLabel) .. " rc=" .. tostring(rc)
        ATC_IO.Post("ATC_IO ERROR: " .. err)
        return nil, err
    end

    return (state == 1), nil
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
-- Function: ATC_IO.GetOutputByNumberState
-- Purpose:  Read output state with error detail.
--=========================================================================
function ATC_IO.GetOutputByNumberState(outputNumber)
    local sigEnum = OutputEnumFromNumber(outputNumber)
    if sigEnum == nil then
        return nil, "Invalid output number."
    end

    return ReadSignalState(sigEnum, "Output #" .. tostring(outputNumber))
end

--=========================================================================
-- Function: ATC_IO.GetOutputByNumber
-- Purpose:  Read output state as boolean (legacy-compatible).
--=========================================================================
function ATC_IO.GetOutputByNumber(outputNumber)
    local state = ATC_IO.GetOutputByNumberState(outputNumber)
    return (state == true)
end

--=========================================================================
-- Function: ATC_IO.GetInputByNumberState
-- Purpose:  Read input state with error detail.
--=========================================================================
function ATC_IO.GetInputByNumberState(inputNumber)
    local sigEnum = InputEnumFromNumber(inputNumber)
    if sigEnum == nil then
        return nil, "Invalid input number."
    end

    return ReadSignalState(sigEnum, "Input #" .. tostring(inputNumber))
end

--=========================================================================
-- Function: ATC_IO.GetInputByNumber
-- Purpose:  Read input state as boolean (legacy-compatible).
--=========================================================================
function ATC_IO.GetInputByNumber(inputNumber)
    local state = ATC_IO.GetInputByNumberState(inputNumber)
    return (state == true)
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
-- Function: ATC_IO.GetOutputState
-- Purpose:  Read output state by logical name with error detail.
--=========================================================================
function ATC_IO.GetOutputState(name)
    local outNum = ATC_Config.Outputs[name]
    if outNum == nil then
        return nil, "Unknown output name: " .. tostring(name)
    end

    return ATC_IO.GetOutputByNumberState(outNum)
end

--=========================================================================
-- Function: ATC_IO.GetOutput
-- Purpose:  Read output state by logical name.
--=========================================================================
function ATC_IO.GetOutput(name)
    local state = ATC_IO.GetOutputState(name)
    return (state == true)
end

--=========================================================================
-- Function: ATC_IO.GetInputState
-- Purpose:  Read input state by logical name with error detail.
--=========================================================================
function ATC_IO.GetInputState(name)
    local inNum = ATC_Config.Inputs[name]
    if inNum == nil then
        return nil, "Unknown input name: " .. tostring(name)
    end

    return ATC_IO.GetInputByNumberState(inNum)
end

--=========================================================================
-- Function: ATC_IO.GetInput
-- Purpose:  Read input state by logical name.
--=========================================================================
function ATC_IO.GetInput(name)
    local state = ATC_IO.GetInputState(name)
    return (state == true)
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
-- Purpose:  Wait until an input reaches desired state or timeout.
--=========================================================================
function ATC_IO.WaitForInput(name, desiredState, timeoutMs)
    local timeout = timeoutMs or ATC_Config.Timing.DefaultTimeoutMs
    local startTime = wx.wxGetUTCTimeMillis():GetValue()

    while true do
        local state, err = ATC_IO.GetInputState(name)
        if err ~= nil then
            return false
        end

        if state == (desiredState == true) then
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

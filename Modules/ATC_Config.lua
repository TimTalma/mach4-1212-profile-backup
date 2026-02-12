--=============================================================================
-- File:        ATC_Config.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Single source for ATC signal mapping and timing.
-- Notes:
--
--=============================================================================

local ATC_Config = {}

--=========================================================================
-- I/O Mapping 
--=========================================================================
ATC_Config.Outputs =
{
    DrawbarClose     = 1,
    DrawbarOpen      = 2,
    DustCollectorOff = 3,   
    DustCollectorOn  = 4,  
    BlowOff          = 5,
}

ATC_Config.Inputs =
{
    ToolSeated       = 15,
}

--=========================================================================
-- Timing Defaults (ms)
--=========================================================================
ATC_Config.Timing =
{
    BlowOffPulseMs   = 250,
    DefaultTimeoutMs = 3000,
}

--=========================================================================
-- Safe-off list
--   - When Reset() is called, these outputs will be forced OFF (state=0).
--=========================================================================
ATC_Config.SafeOffOutputs =
{
    "DrawbarClose",
    "DrawbarOpen",
    "DustCollectorOff",
    "DustCollectorOn",
    "BlowOff",
}

_G.ATC_Config = ATC_Config
return ATC_Config
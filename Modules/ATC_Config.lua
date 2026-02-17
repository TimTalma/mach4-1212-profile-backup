--=============================================================================
-- File:        ATC_Config.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Single source for ATC mapping, timing, and motion constants.
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
    BlowOffPulseMs      = 250,
    DefaultTimeoutMs    = 3000,
    GcodeIdleTimeoutMs  = 3000,
    DrawbarCloseHoldMs  = 1000,
    DrawbarOpenWaitMs   = 250,
    ToolSeatSettleMs    = 100,
}

--=========================================================================
-- Motion Constants
--=========================================================================
ATC_Config.Motion =
{
    SafeZMachine             = 0.0000,
    PocketClearanceOffsetX   = -2.0,
    PocketZApproachClearance = 0.14,
    LoadZBlowoffClearance    = 1.0,
    LoadZCaptureOffset       = 0.000,
    LoadZSyncFeedIpm         = 200.0,
    LoadApproachFeedIpm      = 100.0,
    XYApproachFeedIpm        = 500.0,
    ToolSeatRetryLift        = 0.5,
}

--=========================================================================
-- Pocket Storage
--=========================================================================
ATC_Config.Pockets =
{
    Count            = 3,
    UntaughtPosition = -1,
    UnassignedTool   = -1,
    JsonPath         = "C:\\Mach4Hobby\\Profiles\\1212\\ATC_Pockets.json",
}

--=========================================================================
-- Safe-off list
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

--=============================================================================
-- File:        ATC_ManualControls.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Manual ATC control functions for screen buttons.
--
-- Description:
--   - Uses explicit Enable / Disable naming.
--   - Enable  = energize output
--   - Disable = de-energize output
--   - Intended for momentary button behavior (Down / Up).
--=============================================================================

local ATC_Config = require("ATC_Config")
local ATC_IO     = require("ATC_IO")

local ATC_Manual = {}

--=========================================================================
-- Function: ATC_Manual.Reset
-- Purpose:  Force all configured ATC outputs to OFF.
--=========================================================================
function ATC_Manual.Reset()
    for _, name in ipairs(ATC_Config.SafeOffOutputs) do
        ATC_IO.SetOutput(name, false)
    end
    ATC_IO.Post("ATC: Reset complete (outputs forced OFF).")
end

--=========================================================================
-- DRAWBAR – OPEN
--=========================================================================

-- Function: ATC_Manual.DrawbarOpenEnable
-- Purpose:  Energize drawbar OPEN output.
function ATC_Manual.DrawbarOpenEnable()
    ATC_IO.SetOutput("DrawbarClose", false)
    ATC_IO.SetOutput("DrawbarOpen",  true)
    ATC_IO.Post("ATC: Drawbar Open ENABLED.")
end

-- Function: ATC_Manual.DrawbarOpenDisable
-- Purpose:  De-energize drawbar OPEN output.
function ATC_Manual.DrawbarOpenDisable()
    ATC_IO.SetOutput("DrawbarOpen", false)
    ATC_IO.Post("ATC: Drawbar Open DISABLED.")
end

--=========================================================================
-- DRAWBAR – CLOSE
--=========================================================================

-- Function: ATC_Manual.DrawbarCloseEnable
-- Purpose:  Energize drawbar CLOSE output.
function ATC_Manual.DrawbarCloseEnable()
    ATC_IO.SetOutput("DrawbarOpen",  false)
    ATC_IO.SetOutput("DrawbarClose", true)
    ATC_IO.Post("ATC: Drawbar Close ENABLED.")
end

-- Function: ATC_Manual.DrawbarCloseDisable
-- Purpose:  De-energize drawbar CLOSE output.
function ATC_Manual.DrawbarCloseDisable()
    ATC_IO.SetOutput("DrawbarClose", false)
    ATC_IO.Post("ATC: Drawbar Close DISABLED.")
end

--=========================================================================
-- DUST COLLECTOR – ON 
--=========================================================================

-- Function: ATC_Manual.DustCollectorOnEnable
-- Purpose:  Energize dust collector ON output.
function ATC_Manual.DustCollectorOnEnable()
    ATC_IO.SetOutput("DustCollectorOff", false)
    ATC_IO.SetOutput("DustCollectorOn",  true)
    ATC_IO.Post("ATC: Dust Collector ON ENABLED.")
end

-- Function: ATC_Manual.DustCollectorOnDisable
-- Purpose:  De-energize dust collector ON output.
function ATC_Manual.DustCollectorOnDisable()
    ATC_IO.SetOutput("DustCollectorOn", false)
    ATC_IO.Post("ATC: Dust Collector ON DISABLED.")
end

--=========================================================================
-- DUST COLLECTOR – OFF 
--=========================================================================

-- Function: ATC_Manual.DustCollectorOffEnable
-- Purpose:  Energize dust collector OFF output.
function ATC_Manual.DustCollectorOffEnable()
    ATC_IO.SetOutput("DustCollectorOn",  false)
    ATC_IO.SetOutput("DustCollectorOff", true)
    ATC_IO.Post("ATC: Dust Collector OFF ENABLED.")
end

-- Function: ATC_Manual.DustCollectorOffDisable
-- Purpose:  De-energize dust collector OFF output.
function ATC_Manual.DustCollectorOffDisable()
    ATC_IO.SetOutput("DustCollectorOff", false)
    ATC_IO.Post("ATC: Dust Collector OFF DISABLED.")
end

--=========================================================================
-- BLOW OFF
--=========================================================================

-- Function: ATC_Manual.BlowOffEnable
-- Purpose:  Energize blow-off air output.
function ATC_Manual.BlowOffEnable()
    ATC_IO.SetOutput("BlowOff", true)
    ATC_IO.Post("ATC: BlowOff ENABLED.")
end

-- Function: ATC_Manual.BlowOffDisable
-- Purpose:  De-energize blow-off air output.
function ATC_Manual.BlowOffDisable()
    ATC_IO.SetOutput("BlowOff", false)
    ATC_IO.Post("ATC: BlowOff DISABLED.")
end

_G.ATC_Manual = ATC_Manual
return ATC_Manual
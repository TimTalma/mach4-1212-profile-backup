--=============================================================================
-- File:        ATC_UI.lua
-- Purpose:     ATC UI gating helpers
--=============================================================================

local ATC_UI = {}

function ATC_UI.UpdateTeachingButtons()
    local inst = mc.mcGetInstance()
    local homed =
        mc.mcAxisIsHomed(inst, 0) == 1 and
        mc.mcAxisIsHomed(inst, 1) == 1 and
        mc.mcAxisIsHomed(inst, 2) == 1

    local buttons =
    {
        "btn_CapturePocket",
        "btn_SavePockets",
        "btn_ClearPocket"
    }

    for _, name in ipairs(buttons) do
        local wnd = wx.wxFindWindowByName(name)
        if wnd ~= nil then
            wnd:Enable(homed)
        end
		if wnd == nil then
			mc.mcCntlSetLastError(inst, "ATC_UI: control not found: " .. tostring(name))
		end
    end
end

_G.ATC_UI = ATC_UI
return ATC_UI

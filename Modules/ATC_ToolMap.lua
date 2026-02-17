--=============================================================================
-- File:        ATC_ToolMap.lua
-- Location:    C:\Mach4Hobby\Profiles\1212\Modules
-- Purpose:     Tool-to-pocket mapping helpers.
--=============================================================================

local ATC_Pockets = require("ATC_Pockets")
local ATC_Config = require("ATC_Config")

local ATC_ToolMap = {}

--=========================================================================
-- Function: ATC_ToolMap.GetPocketForTool
-- Purpose:  Return pocket data assigned to a tool number.
--=========================================================================
function ATC_ToolMap.GetPocketForTool(toolNum, reload)
    local t = tonumber(toolNum)
    if t == nil or t <= 0 then
        return nil, "Tool number is invalid."
    end

    if reload == true then
        ATC_Pockets.LoadPockets()
    else
        ATC_Pockets.Init()
    end

    local pocket = ATC_Pockets.FindPocketByTool(t)
    if type(pocket) ~= "table" then
        return nil, "Tool T" .. tostring(t) .. " is not assigned to any pocket."
    end

    return pocket, nil
end

--=========================================================================
-- Function: ATC_ToolMap.GetToolForPocket
-- Purpose:  Return tool number assigned to a pocket number.
--=========================================================================
function ATC_ToolMap.GetToolForPocket(pocketId)
    ATC_Pockets.Init()
    local p = ATC_Pockets.GetPocketData(pocketId)

    if type(p) ~= "table" then
        return ATC_Config.Pockets.UnassignedTool
    end

    return tonumber(p.tool) or ATC_Config.Pockets.UnassignedTool
end

--=========================================================================
-- Function: ATC_ToolMap.ValidatePocketForTool
-- Purpose:  Validate that a pocket is usable for a given tool.
--=========================================================================
function ATC_ToolMap.ValidatePocketForTool(toolNum, pocket)
    local t = tonumber(toolNum)
    if t == nil or t <= 0 then
        return false, "Tool number is invalid."
    end

    if type(pocket) ~= "table" then
        return false, "No pocket assigned to requested tool."
    end

    if pocket.taught ~= true then
        return false, "Pocket " .. tostring(pocket.id) .. " is not taught."
    end

    local pTool = tonumber(pocket.tool) or ATC_Config.Pockets.UnassignedTool
    if pTool ~= t then
        return false, "Pocket " .. tostring(pocket.id) .. " is not assigned to T" .. tostring(t) .. "."
    end

    return true, nil
end

_G.ATC_ToolMap = ATC_ToolMap
return ATC_ToolMap

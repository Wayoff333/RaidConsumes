--[[
RaidConsumes - Minimap.lua

Library-free minimap button, positioned by angle around the minimap edge
and draggable, same approach as most pre-LibDBIcon vanilla addons (and
consistent with WarlockCursePower not pulling in external libs).
--]]

local button = CreateFrame("Button", "RaidConsumesMinimapButton", Minimap)
button:SetWidth(31)
button:SetHeight(31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")

local overlay = button:CreateTexture(nil, "OVERLAY")
overlay:SetWidth(53)
overlay:SetHeight(53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetWidth(20)
icon:SetHeight(20)
-- Generic consumable-ish icon (flask). Swap for an octopus-themed custom
-- icon path if OctoWoW ships one.
icon:SetTexture("Interface\\Icons\\INV_Potion_93")
icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6)

button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local function GetAngle(cx, cy)
    return math.atan2(cy, cx)
end

local function UpdatePosition(angle)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    if RaidConsumesDB then
        RaidConsumesDB.minimapAngle = angle
    end
end

button:SetScript("OnDragStart", function()
    button:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = GetAngle(px - mx, py - my)
        UpdatePosition(angle)
    end)
end)

button:SetScript("OnDragStop", function()
    button:SetScript("OnUpdate", nil)
end)

button:SetScript("OnClick", function()
    RaidConsumes_ToggleWindow()
end)

button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("RaidConsumes")
    GameTooltip:AddLine("Click to open the raid consumable check.", 1, 1, 1)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

function RaidConsumes_InitMinimapButton()
    local angle = (RaidConsumesDB and RaidConsumesDB.minimapAngle) or (math.pi * 0.9)
    UpdatePosition(angle)
end

--[[
RaidConsumes - History.lua

A third window: how many times each raider has actually POPPED each
consumable, tallied over time (persisted in RaidConsumesDB.usageHistory).

Counted on the not-had -> has transition between scans (see Scan.lua),
not on every scan while a buff is still active -- so re-clicking Check
Raid five times during one still-active flask counts as one use, not
five. This is inherently an on-demand-scan approximation: if someone
pops something in the gap between two scans and it wears off before you
scan again, that use is never seen. Good enough for "who's actually
using their consumables over time," not a combat-log-accurate audit.
--]]

local HISTORY_ROW_HEIGHT = 18
local NUM_HISTORY_ROWS = 16
local HISTORY_WIDTH = 380

local history = CreateFrame("Frame", "RaidConsumesHistoryFrame", UIParent)
history:SetWidth(HISTORY_WIDTH)
history:SetHeight(460)
history:SetFrameStrata("DIALOG")
history:SetClampedToScreen(true)
-- Solid black fill instead of the stock stone/parchment dialog texture
-- (which has its own baked-in translucency) -- same treatment as the
-- main window and Settings in UI.lua, so this window matches them and
-- actually reads as opaque instead of blending with the game world.
history:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
history:SetBackdropColor(0, 0, 0, 1)
history:SetMovable(true)
history:EnableMouse(true)
history:RegisterForDrag("LeftButton")
history:SetScript("OnDragStart", function() this:StartMoving() end)
history:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
history:Hide()

local historyTitle = history:CreateFontString(nil, "OVERLAY", "GameFontNormal")
historyTitle:SetPoint("TOP", history, "TOP", 0, -14)
historyTitle:SetText("Consumable History")

local historyCloseBtn = CreateFrame("Button", nil, history, "UIPanelCloseButton")
historyCloseBtn:SetPoint("TOPRIGHT", history, "TOPRIGHT", -4, -4)
historyCloseBtn:SetScript("OnClick", function() history:Hide() end)

local historyHint = history:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
historyHint:SetPoint("TOP", history, "TOP", 0, -34)
historyHint:SetWidth(HISTORY_WIDTH - 32)
historyHint:SetText("How many times each raider has actually popped each required consumable, tallied since tracking started.")

-- v2.6.3: dropped the "Missed" view (logged once when someone joined your
-- raid/party missing something) -- it was based on presence edge-detection
-- alone (who's newly in your group on THIS scan vs the last one), which
-- turned out to not reliably reflect who actually showed up unprepared.
-- Usage (what people have actually popped, tallied over time) is the
-- accurate one and is now the only view.
StaticPopupDialogs["RAIDCONSUMES_CLEAR_HISTORY"] = {
    text = "Clear ALL RaidConsumes %s history? This can't be undone.",
    button1 = "Clear",
    button2 = "Cancel",
    OnAccept = function()
        RaidConsumesDB.usageHistory = {}
        RaidConsumes_LastHitsByPlayer = {}
        RaidConsumes_RefreshHistory()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

local historyControlBar = CreateFrame("Frame", nil, history)
historyControlBar:SetPoint("TOP", historyHint, "BOTTOM", 0, -6)
historyControlBar:SetWidth(120 + 4 + 80)
historyControlBar:SetHeight(20)

local clearBtn = CreateFrame("Button", "RaidConsumesHistoryClearButton", historyControlBar, "UIPanelButtonTemplate")
clearBtn:SetWidth(120)
clearBtn:SetHeight(20)
clearBtn:SetPoint("LEFT", historyControlBar, "LEFT", 0, 0)
clearBtn:SetText("Clear All History")
clearBtn:SetScript("OnClick", function()
    StaticPopup_Show("RAIDCONSUMES_CLEAR_HISTORY", "usage")
end)

local exportBtn = CreateFrame("Button", "RaidConsumesHistoryExportButton", historyControlBar, "UIPanelButtonTemplate")
exportBtn:SetWidth(80)
exportBtn:SetHeight(20)
exportBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
exportBtn:SetText("Export")
exportBtn:SetScript("OnClick", function()
    RaidConsumes_ShowExport()
end)

local historyHeader = history:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
historyHeader:SetPoint("TOP", historyControlBar, "BOTTOM", 0, -10)
historyHeader:SetWidth(HISTORY_WIDTH - 32)
historyHeader:SetJustifyH("LEFT")
historyHeader:SetText("Player                Item                                    Count")

local historyScroll = CreateFrame("ScrollFrame", "RaidConsumesHistoryScrollFrame", history, "FauxScrollFrameTemplate")
historyScroll:SetPoint("TOP", historyHeader, "BOTTOM", -10, -4)
historyScroll:SetWidth(HISTORY_WIDTH - 40)
historyScroll:SetHeight(NUM_HISTORY_ROWS * HISTORY_ROW_HEIGHT)
historyScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(HISTORY_ROW_HEIGHT, function() RaidConsumes_RefreshHistory() end)
end)

-- Rows are parented to `history` (the top-level window), not to
-- `historyScroll` -- same fix as the main window's roster rows and the
-- Settings window's checklist rows (see the comment on that in UI.lua):
-- on this client, something else draws on top of that exact strip of the
-- window at normal DIALOG strata, so rows parented to an inner scroll
-- frame never actually render even though the game reports them as
-- shown/sized/positioned correctly. This is almost certainly why History
-- has shown nothing at all -- the data was there, the rows just never
-- drew. Bumping to TOOLTIP strata, one above everything else in this
-- addon, fixes it. Positioning still anchors off historyScroll (layout
-- only) so rows line up under it and the scrollbar offset math is
-- untouched.
local historyRows = {}
for i = 1, NUM_HISTORY_ROWS do
    local row = CreateFrame("Frame", "RaidConsumesHistoryRow" .. i, history)
    row:SetWidth(HISTORY_WIDTH - 40)
    row:SetHeight(HISTORY_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", historyScroll, "TOPLEFT", 0, -(i - 1) * HISTORY_ROW_HEIGHT)
    row:SetFrameStrata("TOOLTIP")
    row:SetFrameLevel(historyScroll:GetFrameLevel() + 1)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.nameText:SetWidth(90)
    row.nameText:SetJustifyH("LEFT")

    row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.itemText:SetPoint("TOPLEFT", row, "TOPLEFT", 94, 0)
    row.itemText:SetWidth(HISTORY_WIDTH - 40 - 94 - 40)
    row.itemText:SetJustifyH("LEFT")

    row.countText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.countText:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.countText:SetWidth(36)
    row.countText:SetJustifyH("RIGHT")

    row:Hide()
    historyRows[i] = row
end

local noHistoryText = history:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
noHistoryText:SetPoint("TOP", historyScroll, "TOP", 0, -20)
noHistoryText:SetText("No usage recorded yet -- click Check Raid a few times over a raid to build history.")
noHistoryText:Hide()

-- Pure data step: every (player, item, count>0) triple currently on
-- record, sorted by player name, then by count (highest first), then by
-- item label. Independently testable, same pattern as
-- RaidConsumes_ComputeDisplayRows in UI.lua.
function RaidConsumes_GetHistoryRows()
    local source = RaidConsumesDB and RaidConsumesDB.usageHistory
    local rows = {}
    for name, items in pairs(source or {}) do
        for itemKey, count in pairs(items) do
            if count and count > 0 then
                local item = RaidConsumes_ItemByKey[itemKey]
                -- The shared weapon-enchant bucket (see Data.lua) isn't a
                -- real entry in RaidConsumes_Items, so it needs its own
                -- friendly label instead of falling back to the raw
                -- "__weaponEnchant" key.
                local label
                if item then
                    label = item.label
                elseif itemKey == RaidConsumes_WEAPON_ENCHANT_HISTORY_KEY then
                    label = "Weapon Enchant (oil/stone)"
                else
                    label = itemKey
                end
                table.insert(rows, {
                    name = name,
                    class = RaidConsumesDB.usageHistoryClass and RaidConsumesDB.usageHistoryClass[name],
                    itemKey = itemKey,
                    label = label,
                    count = count,
                })
            end
        end
    end
    table.sort(rows, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if a.count ~= b.count then return a.count > b.count end
        return a.label < b.label
    end)
    return rows
end

function RaidConsumes_RefreshHistory()
    local rows = RaidConsumes_GetHistoryRows()
    local total = table.getn(rows)

    if total == 0 then
        noHistoryText:Show()
    else
        noHistoryText:Hide()
    end

    FauxScrollFrame_Update(historyScroll, total, NUM_HISTORY_ROWS, HISTORY_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(historyScroll)

    for i = 1, NUM_HISTORY_ROWS do
        local idx = i + offset
        local data = rows[idx]
        local row = historyRows[i]
        if data then
            local classColor = RAID_CLASS_COLORS and data.class and RAID_CLASS_COLORS[data.class]
            if classColor then
                row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
            else
                row.nameText:SetTextColor(1, 1, 1)
            end
            row.nameText:SetText(data.name)
            row.itemText:SetText(data.label)
            row.countText:SetText(tostring(data.count))
            row:Show()
        else
            row:Hide()
        end
    end
end

-- Wraps a CSV field in quotes (doubling any embedded quotes) only if it
-- actually needs it -- item labels/names are plain text in practice, but
-- this keeps the export correct even if one ever contains a comma.
local function CsvField(s)
    s = tostring(s or "")
    if string.find(s, "[,\"\n]") then
        s = "\"" .. string.gsub(s, "\"", "\"\"") .. "\""
    end
    return s
end

-- Pure text-building step (no frame access, independently testable): every
-- history row as one CSV blob -- a header row, then one
-- "Player,Item,Count" line per (player, item) pair, sorted exactly like
-- the History window itself.
function RaidConsumes_BuildHistoryExportText()
    local rows = RaidConsumes_GetHistoryRows()
    local lines = { "Player,Item,Count" }
    for _, row in ipairs(rows) do
        table.insert(lines, CsvField(row.name) .. "," .. CsvField(row.label) .. "," .. tostring(row.count))
    end
    return table.concat(lines, "\n")
end

-- ===================== export window =====================
-- A second small popup with a scrollable, selectable text box holding the
-- CSV blob -- there's no 1.12 API to write a file or touch the OS
-- clipboard directly, so (same pattern as every other classic-era addon's
-- "export string") the player selects the box's text themselves (click
-- inside, Ctrl+A, Ctrl+C) and pastes it into Excel, a text file, Discord,
-- wherever.

local exportFrame = CreateFrame("Frame", "RaidConsumesExportFrame", UIParent)
exportFrame:SetWidth(420)
exportFrame:SetHeight(320)
exportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
exportFrame:SetFrameStrata("DIALOG")
exportFrame:SetToplevel(true)
exportFrame:SetClampedToScreen(true)
-- Solid black fill, same treatment as the other 3 windows.
exportFrame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
exportFrame:SetBackdropColor(0, 0, 0, 1)
exportFrame:SetMovable(true)
exportFrame:EnableMouse(true)
exportFrame:RegisterForDrag("LeftButton")
exportFrame:SetScript("OnDragStart", function() this:StartMoving() end)
exportFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
exportFrame:Hide()

local exportTitle = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
exportTitle:SetPoint("TOP", exportFrame, "TOP", 0, -14)
exportTitle:SetText("Export History")

local exportCloseBtn = CreateFrame("Button", nil, exportFrame, "UIPanelCloseButton")
exportCloseBtn:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", -4, -4)
exportCloseBtn:SetScript("OnClick", function() exportFrame:Hide() end)

local exportHint = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
exportHint:SetPoint("TOP", exportFrame, "TOP", 0, -32)
exportHint:SetWidth(380)
exportHint:SetText("Click in the box, Ctrl+A to select all, Ctrl+C to copy -- it's CSV, so it pastes straight into Excel/Sheets or a text file.")

local exportScroll = CreateFrame("ScrollFrame", "RaidConsumesExportScrollFrame", exportFrame, "UIPanelScrollFrameTemplate")
exportScroll:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 20, -58)
exportScroll:SetWidth(370)
exportScroll:SetHeight(220)

local exportEditBox = CreateFrame("EditBox", "RaidConsumesExportEditBox", exportScroll)
exportEditBox:SetMultiLine(true)
exportEditBox:SetFontObject(ChatFontNormal)
exportEditBox:SetWidth(360)
exportEditBox:SetAutoFocus(false)
exportEditBox:SetScript("OnEscapePressed", function()
    exportEditBox:ClearFocus()
    exportFrame:Hide()
end)
exportScroll:SetScrollChild(exportEditBox)

function RaidConsumes_ShowExport()
    exportTitle:SetText("Export History")
    exportEditBox:SetText(RaidConsumes_BuildHistoryExportText())
    exportFrame:ClearAllPoints()
    if RaidConsumesHistoryFrame and RaidConsumesHistoryFrame:IsShown() then
        exportFrame:SetPoint("LEFT", RaidConsumesHistoryFrame, "RIGHT", 10, 0)
    else
        exportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    exportFrame:Show()
    exportEditBox:SetFocus()
    exportEditBox:HighlightText()
end

function RaidConsumes_ToggleHistory()
    if history:IsShown() then
        history:Hide()
    else
        history:ClearAllPoints()
        -- Settings takes priority over the main window when both are open
        -- -- if you're in Settings tweaking the checklist, that's the
        -- window History should line up next to.
        if RaidConsumesSettingsFrame and RaidConsumesSettingsFrame:IsShown() then
            history:SetPoint("LEFT", RaidConsumesSettingsFrame, "RIGHT", 10, 0)
        elseif RaidConsumesFrame and RaidConsumesFrame:IsShown() then
            history:SetPoint("LEFT", RaidConsumesFrame, "RIGHT", 10, 0)
        else
            history:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        end
        local ok, err = pcall(RaidConsumes_RefreshHistory)
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes History error:|r " .. tostring(err))
        end
        history:Show()
    end
end

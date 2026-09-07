--[[
RaidConsumes - UI.lua

Two windows, no external UI library (matches WarlockCursePower):

  RaidConsumesFrame          - pops up, shows every raider sorted by
                                class, and what each one is missing (in
                                red) based on their checklist. Each
                                raider is checked against their CLASS's
                                list by default, or a per-raider ROLE
                                override (Tank/Healer/Physical DPS/Caster
                                DPS) if you've set one with the small
                                button next to their name -- useful for
                                e.g. a Protection Warrior who should be
                                checked as a Tank, not a generic Warrior,
                                or telling a Ret Paladin's needs apart
                                from a Balance Druid's.
  RaidConsumesSettingsFrame  - pick a class OR a role along the top,
                                then a scrollable checklist (with item
                                icons), grouped by category and then by
                                type (Flask / Food Buff / General /
                                Other) -- ticked ones are required for
                                that class/role. "Reset to Defaults"
                                puts the selected list back to its seed.
--]]

-- Each raider gets a two-line row: line 1 (name, role button, missing-item
-- icons) sits in the top ROW_LINE1_HEIGHT px, line 2 (the missing items'
-- full names, so you don't have to hover every icon) fills the rest of
-- ROW_HEIGHT below it.
local ROW_LINE1_HEIGHT = 16
local ROW_HEIGHT = 30
local NUM_ROWS = 16
local ROW_WIDTH = 380

-- Missing-item icons on each main-window row: small clickable (for the
-- tooltip) buttons rather than plain textures, since a 1.12 Texture object
-- can't take mouse scripts on its own. 12 slots at 16px pitch fits well
-- within the ~268px available after the name/role columns; a raider
-- missing more than that gets a "+N" label after the last icon instead of
-- silently truncating.
local MISSING_ICON_SIZE = 14
local MISSING_ICON_GAP = 2
local MAX_MISSING_ICONS = 12

-- Line 2's full-name list is capped by character count (not item count) so
-- it can never wrap onto a third line and bleed into the row below --
-- there's no 1.12 API to clip a FontString's overflow the way a real
-- scrollable container would. The first name always shows in full even if
-- it alone exceeds the cap; only the names after it are gated.
local MAX_NAME_LINE_CHARS = 46

-- Standard vanilla class grouping order for the main list.
local CLASS_ORDER = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9,
}

local function ClassSortRank(class)
    return CLASS_ORDER[class] or 99
end

-- Shown on the role button itself when no override is set, so it reads as
-- "here's their class, click to change it" instead of a bare, easy-to-miss
-- "-". Kept to 4 characters to match the other role labels (Tank/Heal/
-- PDPS/CDPS) in the same 34px-wide button.
local CLASS_ABBREV = {
    WARRIOR = "War", PALADIN = "Pal", HUNTER = "Hun", ROGUE = "Rog", PRIEST = "Pri",
    SHAMAN = "Sha", MAGE = "Mag", WARLOCK = "Lock", DRUID = "Dru",
}

local function ProfileLabel(key)
    return RaidConsumes_ClassLabels[key] or RaidConsumes_RoleLabels[key] or key or "?"
end

-- Standard role accent colors (matches the role-button text colors on the
-- main window's raider rows).
local ROLE_COLORS = {
    TANK = { r = 0.4, g = 0.7, b = 1 },
    HEALER = { r = 0.4, g = 1, b = 0.5 },
    PHYSDPS = { r = 1, g = 0.5, b = 0.4 },
    CASTERDPS = { r = 0.8, g = 0.4, b = 1 },
}

-- Class token -> its standard class color, or a role token -> its role
-- accent color. Falls back to white if neither table has it.
local function ProfileColor(profile)
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[profile]
    if c then return c.r, c.g, c.b end
    local rc = ROLE_COLORS[profile]
    if rc then return rc.r, rc.g, rc.b end
    return 1, 1, 1
end

-- Strips everything but letters/digits and lowercases, so "R.O.I.D.S."
-- and "roids", or "Danonzo's Tel'Abim Delight" with/without the
-- apostrophe, compare equal.
local function NormalizeItemName(s)
    s = string.lower(s or "")
    s = string.gsub(s, "[^%a%d]", "")
    return s
end

-- item.label is sometimes a combined "A / B" for two interchangeable items
-- (e.g. "Medivh's Merlot / Rumsey Rum Black Label") -- split on "/" so
-- each half can be checked separately against the live item name.
local function SplitLabelParts(label)
    local parts = {}
    local start = 1
    while true do
        local i, j = string.find(label, "%s*/%s*", start)
        if not i then
            table.insert(parts, string.sub(label, start))
            break
        end
        table.insert(parts, string.sub(label, start, i - 1))
        start = j + 1
    end
    return parts
end

-- True if the live item name (from GetItemInfo) actually looks like the
-- item Data.lua means -- a loose match (either direction, substring okay)
-- since some labels add flavor text GetItemInfo won't.
local function LiveNameMatchesItem(liveName, item)
    local normLive = NormalizeItemName(liveName)
    if normLive == "" then
        return false
    end
    for _, part in ipairs(SplitLabelParts(item.label or "")) do
        local normPart = NormalizeItemName(part)
        if normPart ~= "" and (normLive == normPart
            or string.find(normLive, normPart, 1, true)
            or string.find(normPart, normLive, 1, true)) then
            return true
        end
    end
    return false
end

-- Resolves the icon to actually display for an item: a player-set override
-- (via /rc icon) wins, then the item's real itemID (pulled live from the
-- game), then the best-effort guessed icon string as a last resort for
-- items OctoWoW added that have neither.
--
-- The itemID lookup is name-checked first (via GetItemInfo) rather than
-- trusted blindly: on a private server, a hardcoded itemID sourced from a
-- different item database (Wowhead Classic, Turtle WoW, etc.) can happen
-- to belong to a completely different item on THIS server -- GetItemIcon
-- would then return a real icon, just the wrong one, which looks like a
-- bug rather than a missing icon. If the live name doesn't look like the
-- item we mean (or isn't cached client-side yet), the guessed icon is used
-- instead -- safer than confidently showing the wrong picture.
local function ResolveIcon(item)
    local overrideID = RaidConsumesDB and RaidConsumesDB.iconOverrides and RaidConsumesDB.iconOverrides[item.key]
    if overrideID then
        local tex = GetItemIcon(overrideID)
        if tex then return tex end
    end
    if item.itemID then
        local liveName = GetItemInfo(item.itemID)
        if liveName and LiveNameMatchesItem(liveName, item) then
            local tex = GetItemIcon(item.itemID)
            if tex then return tex end
        end
    end
    return item.icon
end

-- ===================== helpers =====================

-- Per-profile (class OR role token) required-item table, seeded from
-- RaidConsumes_ClassDefaults the first time a profile is touched.
function RaidConsumes_EnsureRequiredDefaults(profile)
    if not RaidConsumesDB.required then
        RaidConsumesDB.required = {}
    end
    if not RaidConsumesDB.required[profile] then
        RaidConsumesDB.required[profile] = {}
        local seed = RaidConsumes_ClassDefaults[profile] or {}
        for _, item in ipairs(RaidConsumes_Items) do
            RaidConsumesDB.required[profile][item.key] = seed[item.key] and true or false
        end
    end
    return RaidConsumesDB.required[profile]
end

-- Puts a class/role's checklist back to its seeded starting point.
function RaidConsumes_ResetProfileToDefaults(profile)
    if not profile then return end
    local seed = RaidConsumes_ClassDefaults[profile] or {}
    RaidConsumesDB.required[profile] = {}
    for _, item in ipairs(RaidConsumes_Items) do
        RaidConsumesDB.required[profile][item.key] = seed[item.key] and true or false
    end
    RaidConsumes_RefreshSettings()
    RaidConsumes_RefreshList()
end

-- ===================== main frame =====================

local frame = CreateFrame("Frame", "RaidConsumesFrame", UIParent)
frame:SetWidth(ROW_WIDTH + 40)
-- 500 (was 422, was 400 before that): fits 16 single-line rows (16px
-- each); each row is now 30px tall (a names line under the icons), so the
-- window needs that much more room to keep showing all 16 without the
-- list running under the bottom buttons. The base grew again in v2.6.0:
-- +22 for the new "only show not ready" checkbox row above the list, and
-- +~44 more at the bottom for the auto-whisper row + window-opacity row
-- that moved/were added there (net of removing the old "your weapon buff
-- applied" text). If a future layout change adds/removes a fixed-height
-- row anywhere in the window, adjust this base by ~22px per row rather
-- than the NUM_ROWS term (that term only accounts for the roster list).
frame:SetHeight(500 + NUM_ROWS * (ROW_HEIGHT - ROW_LINE1_HEIGHT))
frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
-- Solid black fill (not the stock stone/parchment dialog texture, which
-- has its own baked-in translucency) tinted via SetBackdropColor, so the
-- window actually reads as opaque at 100% Window Opacity instead of
-- always looking faintly blended with whatever's behind it -- same idea
-- as CombatLedger's options window. Still fades normally at lower
-- opacity settings since that's a SetAlpha on the whole frame, applied on
-- top of this.
frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
frame:SetBackdropColor(0, 0, 0, 1)
frame:SetMovable(true)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("DIALOG") -- same reasoning as the Settings window: draw above other addon UI (pfUI, etc.) that might otherwise render over the row list
frame:SetToplevel(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() this:StartMoving() end)
frame:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    if RaidConsumesDB then
        local point, _, relPoint, x, y = this:GetPoint()
        RaidConsumesDB.framePos = { point = point, relPoint = relPoint, x = x, y = y }
    end
end)
frame:Hide()

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", frame, "TOP", 0, -14)
title:SetText("RaidConsumes")

local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function() frame:Hide() end)

local settingsBtn = CreateFrame("Button", "RaidConsumesSettingsButton", frame, "UIPanelButtonTemplate")
settingsBtn:SetWidth(90)
settingsBtn:SetHeight(22)
settingsBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 12)
settingsBtn:SetText("Settings")

local checkBtn = CreateFrame("Button", "RaidConsumesCheckButton", frame, "UIPanelButtonTemplate")
checkBtn:SetWidth(110)
checkBtn:SetHeight(22)
checkBtn:SetPoint("BOTTOM", frame, "BOTTOM", 10, 12)
checkBtn:SetText("Check Raid")

local historyBtn = CreateFrame("Button", "RaidConsumesHistoryButton", frame, "UIPanelButtonTemplate")
historyBtn:SetWidth(90)
historyBtn:SetHeight(22)
historyBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 12)
historyBtn:SetText("History")
historyBtn:SetScript("OnClick", function()
    RaidConsumes_ToggleHistory()
end)

local scanTimeText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
scanTimeText:SetPoint("BOTTOM", frame, "BOTTOM", 10, 138)
scanTimeText:SetText("No scan yet")

-- ---- window opacity ----
-- Applies to both this window and Settings (RaidConsumes_ApplyWindowOpacity,
-- defined after the Settings window below, since it needs to reach both).
local MIN_WINDOW_OPACITY = 20
local MAX_WINDOW_OPACITY = 100
local DEFAULT_WINDOW_OPACITY = 100

local opacityLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
opacityLabel:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 112)
opacityLabel:SetText("Window opacity")

local opacityBox = CreateFrame("EditBox", "RaidConsumesOpacityBox", frame, "InputBoxTemplate")
opacityBox:SetWidth(30)
opacityBox:SetHeight(16)
opacityBox:SetPoint("LEFT", opacityLabel, "RIGHT", 8, 0)
opacityBox:SetAutoFocus(false)
opacityBox:SetMaxLetters(3)
opacityBox:SetScript("OnEnterPressed", function()
    RaidConsumes_ApplyWindowOpacity(this:GetText())
    this:ClearFocus()
end)
opacityBox:SetScript("OnEscapePressed", function()
    opacityBox:SetText(tostring(RaidConsumesDB.windowOpacity or DEFAULT_WINDOW_OPACITY))
    this:ClearFocus()
end)
opacityBox:SetScript("OnEditFocusLost", function()
    RaidConsumes_ApplyWindowOpacity(this:GetText())
end)

local opacityPctLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
opacityPctLabel:SetPoint("LEFT", opacityBox, "RIGHT", 4, 0)
opacityPctLabel:SetText("%")

-- ---- auto-check ----
-- Optional, off by default: repeatedly scanning a full raid via the
-- hidden-tooltip name-matching technique isn't free (up to 32 tooltip
-- reads per raider per scan), so this is opt-in rather than always-on, and
-- only actually runs while this window is open (see the OnUpdate script
-- below) -- no point scanning into the void while it's closed.
local MIN_AUTO_SCAN_INTERVAL = 2
local MAX_AUTO_SCAN_INTERVAL = 300
local DEFAULT_AUTO_SCAN_INTERVAL = 5

local autoScanCheck = CreateFrame("CheckButton", "RaidConsumesAutoScanCheck", frame, "UICheckButtonTemplate")
autoScanCheck:SetWidth(20)
autoScanCheck:SetHeight(20)
autoScanCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 62)
autoScanCheck:SetScript("OnClick", function()
    RaidConsumesDB.autoScanEnabled = this:GetChecked() and true or false
end)
autoScanCheck:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Automatically re-scans the raid/party on this interval while this window is open. Off by default -- repeated scanning has a real cost on a large raid.")
    GameTooltip:Show()
end)
autoScanCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

local autoScanLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoScanLabel:SetPoint("LEFT", autoScanCheck, "RIGHT", 2, 0)
autoScanLabel:SetText("Auto-check every")

local autoScanIntervalBox = CreateFrame("EditBox", "RaidConsumesAutoScanInterval", frame, "InputBoxTemplate")
autoScanIntervalBox:SetWidth(28)
autoScanIntervalBox:SetHeight(16)
autoScanIntervalBox:SetPoint("LEFT", autoScanLabel, "RIGHT", 8, 0)
autoScanIntervalBox:SetAutoFocus(false)
autoScanIntervalBox:SetMaxLetters(3)

-- Clamps and stores whatever's typed (garbage input falls back to the
-- current/default value rather than erroring or silently doing nothing),
-- and always reflects the actual stored value back into the box so it
-- never shows something that wasn't actually accepted.
local function ApplyAutoScanInterval(text)
    local n = tonumber(text)
    if not n then
        n = RaidConsumesDB.autoScanInterval or DEFAULT_AUTO_SCAN_INTERVAL
    end
    if n < MIN_AUTO_SCAN_INTERVAL then n = MIN_AUTO_SCAN_INTERVAL end
    if n > MAX_AUTO_SCAN_INTERVAL then n = MAX_AUTO_SCAN_INTERVAL end
    RaidConsumesDB.autoScanInterval = n
    autoScanIntervalBox:SetText(tostring(n))
end

autoScanIntervalBox:SetScript("OnEnterPressed", function()
    ApplyAutoScanInterval(this:GetText())
    this:ClearFocus()
end)
autoScanIntervalBox:SetScript("OnEscapePressed", function()
    autoScanIntervalBox:SetText(tostring(RaidConsumesDB.autoScanInterval or DEFAULT_AUTO_SCAN_INTERVAL))
    this:ClearFocus()
end)
autoScanIntervalBox:SetScript("OnEditFocusLost", function()
    ApplyAutoScanInterval(this:GetText())
end)

local autoScanSecLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoScanSecLabel:SetPoint("LEFT", autoScanIntervalBox, "RIGHT", 4, 0)
autoScanSecLabel:SetText("sec")

-- The actual timer: accumulates elapsed time (the vanilla OnUpdate
-- convention -- the engine passes it as the global `arg1`, not a function
-- parameter) and fires a scan once it crosses the configured interval,
-- only while auto-check is on AND the window is actually shown.
local autoScanElapsed = 0
frame:SetScript("OnUpdate", function()
    if not (RaidConsumesDB and RaidConsumesDB.autoScanEnabled) then
        return
    end
    if not frame:IsShown() then
        return
    end
    autoScanElapsed = autoScanElapsed + (arg1 or 0)
    local interval = RaidConsumesDB.autoScanInterval or DEFAULT_AUTO_SCAN_INTERVAL
    if interval < MIN_AUTO_SCAN_INTERVAL then interval = MIN_AUTO_SCAN_INTERVAL end
    if autoScanElapsed >= interval then
        autoScanElapsed = 0
        RaidConsumes_ScanRaid()
        RaidConsumes_RefreshList()
    end
end)

-- Reflects RaidConsumesDB's stored auto-check settings into the checkbox
-- and interval box -- called whenever the window opens, so it's never
-- stale after a /reload or after Settings changed something else.
function RaidConsumes_RefreshAutoScanControls()
    autoScanCheck:SetChecked(RaidConsumesDB.autoScanEnabled and true or false)
    autoScanIntervalBox:SetText(tostring(RaidConsumesDB.autoScanInterval or DEFAULT_AUTO_SCAN_INTERVAL))
end

-- ---- auto-whisper (moved here from Settings in v2.6.0 -- lives with the
-- rest of the raid-check controls instead of a separate window) ----
-- Optional, off by default: whispers a raider the moment they're found
-- missing something they weren't missing on the previous scan, and again
-- after the cooldown if they're STILL missing something later -- so
-- someone who never pops anything gets a periodic nag instead of either
-- silence or a whisper on every single scan (a real risk with auto-check
-- running every few seconds). Never whispers the scanning player
-- themself -- see RaidConsumes_ProcessAutoWhispers further down for the
-- actual trigger logic, and the "Send Whisper Now" button below for an
-- immediate, cooldown-bypassing version of the same whisper.
local MIN_AUTO_WHISPER_COOLDOWN = 30
local MAX_AUTO_WHISPER_COOLDOWN = 1800
local DEFAULT_AUTO_WHISPER_COOLDOWN = 300

local autoWhisperCheck = CreateFrame("CheckButton", "RaidConsumesAutoWhisperCheck", frame, "UICheckButtonTemplate")
autoWhisperCheck:SetWidth(20)
autoWhisperCheck:SetHeight(20)
autoWhisperCheck:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 86)
autoWhisperCheck:SetScript("OnClick", function()
    RaidConsumesDB.autoWhisperEnabled = this:GetChecked() and true or false
end)
autoWhisperCheck:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Automatically whispers a raider when a scan finds them missing a required consumable. Off by default. Re-nags the same raider only after the cooldown below.")
    GameTooltip:Show()
end)
autoWhisperCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

local autoWhisperLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoWhisperLabel:SetPoint("LEFT", autoWhisperCheck, "RIGHT", 2, 0)
autoWhisperLabel:SetText("Auto-whisper, re-nag every")

local autoWhisperIntervalBox = CreateFrame("EditBox", "RaidConsumesAutoWhisperCooldown", frame, "InputBoxTemplate")
autoWhisperIntervalBox:SetWidth(34)
autoWhisperIntervalBox:SetHeight(16)
autoWhisperIntervalBox:SetPoint("LEFT", autoWhisperLabel, "RIGHT", 6, 0)
autoWhisperIntervalBox:SetAutoFocus(false)
autoWhisperIntervalBox:SetMaxLetters(4)

-- Clamps and stores whatever's typed (garbage input falls back to the
-- current/default value rather than erroring or silently doing nothing),
-- and always reflects the actual stored value back into the box so it
-- never shows something that wasn't actually accepted.
local function ApplyAutoWhisperCooldown(text)
    local n = tonumber(text)
    if not n then
        n = RaidConsumesDB.autoWhisperCooldown or DEFAULT_AUTO_WHISPER_COOLDOWN
    end
    if n < MIN_AUTO_WHISPER_COOLDOWN then n = MIN_AUTO_WHISPER_COOLDOWN end
    if n > MAX_AUTO_WHISPER_COOLDOWN then n = MAX_AUTO_WHISPER_COOLDOWN end
    RaidConsumesDB.autoWhisperCooldown = n
    autoWhisperIntervalBox:SetText(tostring(n))
end

autoWhisperIntervalBox:SetScript("OnEnterPressed", function()
    ApplyAutoWhisperCooldown(this:GetText())
    this:ClearFocus()
end)
autoWhisperIntervalBox:SetScript("OnEscapePressed", function()
    autoWhisperIntervalBox:SetText(tostring(RaidConsumesDB.autoWhisperCooldown or DEFAULT_AUTO_WHISPER_COOLDOWN))
    this:ClearFocus()
end)
autoWhisperIntervalBox:SetScript("OnEditFocusLost", function()
    ApplyAutoWhisperCooldown(this:GetText())
end)

local autoWhisperSecLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoWhisperSecLabel:SetPoint("LEFT", autoWhisperIntervalBox, "RIGHT", 4, 0)
autoWhisperSecLabel:SetText("sec")

-- Reflects RaidConsumesDB's stored auto-whisper settings into the checkbox
-- and cooldown box -- called whenever the main window opens.
function RaidConsumes_RefreshAutoWhisperControls()
    autoWhisperCheck:SetChecked(RaidConsumesDB.autoWhisperEnabled and true or false)
    autoWhisperIntervalBox:SetText(tostring(RaidConsumesDB.autoWhisperCooldown or DEFAULT_AUTO_WHISPER_COOLDOWN))
end

-- Immediately whispers everyone currently missing something, bypassing
-- the cooldown/edge-detection above entirely -- for "I want to nag people
-- right now" rather than waiting on auto-whisper's pacing. Still records
-- into the same trackers auto-whisper uses, so it doesn't immediately
-- whisper the same people again on the very next auto-check tick.
local sendWhisperBtn = CreateFrame("Button", "RaidConsumesSendWhisperButton", frame, "UIPanelButtonTemplate")
sendWhisperBtn:SetWidth(150)
sendWhisperBtn:SetHeight(20)
sendWhisperBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 38)
sendWhisperBtn:SetText("Send Whisper Now")
sendWhisperBtn:SetScript("OnClick", function()
    RaidConsumes_SendWhisperNow()
end)
sendWhisperBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Immediately whispers everyone currently missing something (from the last Check Raid scan), regardless of the auto-whisper cooldown.")
    GameTooltip:Show()
end)
sendWhisperBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local summaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
summaryText:SetPoint("TOP", frame, "TOP", 0, -34)
summaryText:SetText("Click Check Raid to scan.")

local listHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
listHint:SetPoint("TOP", summaryText, "BOTTOM", 0, -6)
-- Constrained to the frame's own width so long hint text wraps onto
-- another line instead of overflowing past the window's edges.
listHint:SetWidth(ROW_WIDTH + 40 - 32)
listHint:SetJustifyH("CENTER")
listHint:SetText("Sorted by class. The button next to each name shows their class -- click it to override the role they're checked against (only roles that class can actually fill).")

-- Display-only filter: hides "Ready" raiders from the list below so a big
-- raid's screen only shows who still needs to pop something. Purely
-- cosmetic -- doesn't affect scanning, history, or auto-whisper, all of
-- which still see everyone.
local hideReadyCheck = CreateFrame("CheckButton", "RaidConsumesHideReadyCheck", frame, "UICheckButtonTemplate")
hideReadyCheck:SetWidth(18)
hideReadyCheck:SetHeight(18)
hideReadyCheck:SetPoint("TOP", listHint, "BOTTOM", -70, -2)
hideReadyCheck:SetScript("OnClick", function()
    RaidConsumesDB.hideReadyPlayers = this:GetChecked() and true or false
    RaidConsumes_RefreshList()
end)
hideReadyCheck:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Only show raiders currently missing something -- hides everyone marked Ready from this list.")
    GameTooltip:Show()
end)
hideReadyCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

local hideReadyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
hideReadyLabel:SetPoint("LEFT", hideReadyCheck, "RIGHT", 2, 0)
hideReadyLabel:SetText("Only show not ready")

-- Reflects RaidConsumesDB's stored filter setting into the checkbox --
-- called whenever the main window opens.
function RaidConsumes_RefreshHideReadyControl()
    hideReadyCheck:SetChecked(RaidConsumesDB.hideReadyPlayers and true or false)
end

-- ===================== scrollable roster list =====================

local scrollFrame = CreateFrame("ScrollFrame", "RaidConsumesScrollFrame", frame, "FauxScrollFrameTemplate")
-- Anchored off `listHint` (which is itself centered under the window),
-- NOT off `hideReadyCheck` -- that checkbox is deliberately shifted 70px
-- left of center so ITS OWN label reads roughly centered under the
-- checkbox+label pair, and this scrollFrame is 380px wide, so inheriting
-- that same leftward offset dragged the whole roster list (and every
-- row's name/icons/text anchored off it) about 40px past the window's
-- own left edge -- exactly what showed up as "player name is too far
-- left". -30 (instead of the old -8) clears both listHint's hint text
-- AND the hideReadyCheck row now sitting between them.
scrollFrame:SetPoint("TOP", listHint, "BOTTOM", 10, -30)
scrollFrame:SetWidth(ROW_WIDTH)
scrollFrame:SetHeight(NUM_ROWS * ROW_HEIGHT)
scrollFrame:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(ROW_HEIGHT, function() RaidConsumes_RefreshList() end)
end)
scrollFrame:SetAlpha(1)


-- Rows are parented to `frame` (the main window), not to `scrollFrame`
-- (found via diagnostics: rows sitting at the window's normal DIALOG
-- strata never rendered, even though the game reported them as shown,
-- sized, and positioned correctly -- something else in this client's UI,
-- most likely another addon's frame, was drawing on top of that exact
-- strip of the window. Bumping rows to TOOLTIP strata, one above
-- everything else in this addon, fixed it.) Positioning still anchors off
-- scrollFrame (for layout only) so rows line up under it and the
-- scrollbar/mouse-wheel offset math is untouched.
local rows = {}
for i = 1, NUM_ROWS do
    local row = CreateFrame("Frame", "RaidConsumesRow" .. i, frame)
    row:SetWidth(ROW_WIDTH)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    row:SetAlpha(1)
    row:SetFrameStrata("TOOLTIP")
    row:SetFrameLevel(scrollFrame:GetFrameLevel() + 1)

    row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.nameText:SetWidth(72)
    row.nameText:SetJustifyH("LEFT")

    row.roleBtn = CreateFrame("Button", "RaidConsumesRoleBtn" .. i, row)
    row.roleBtn:SetWidth(34)
    row.roleBtn:SetHeight(ROW_LINE1_HEIGHT)
    row.roleBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 74, 0)
    -- A faint always-on background "chip" behind the text (not just the
    -- on-hover highlight below) so the button reads as clickable at rest
    -- -- otherwise it's easy to mistake for plain text, especially once it
    -- defaults to showing the raider's class abbreviation instead of a
    -- bare "-".
    row.roleBtn.bg = row.roleBtn:CreateTexture(nil, "BACKGROUND")
    row.roleBtn.bg:SetAllPoints(row.roleBtn)
    row.roleBtn.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    row.roleBtn.bg:SetVertexColor(1, 1, 1, 0.12)
    row.roleBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.roleBtn.text = row.roleBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.roleBtn.text:SetPoint("LEFT", row.roleBtn, "LEFT", 2, 0)
    -- Only cycles through the roles that raider's CLASS can actually fill
    -- (RaidConsumes_ClassRoles) -- a Hunter's button only ever offers
    -- Physical DPS, a Warrior's never offers Healer, a Priest's never
    -- offers Tank, and so on. Falls back to the class's first valid role
    -- if the stored override isn't one of them (stale data, e.g. from
    -- before this was added).
    row.roleBtn:SetScript("OnClick", function()
        if not row.playerName then return end
        local roles = RaidConsumes_ClassRoles[row.playerClass] or {}
        if table.getn(roles) == 0 then return end -- nothing this class can override to
        RaidConsumesDB.roleOverride = RaidConsumesDB.roleOverride or {}
        local cur = RaidConsumesDB.roleOverride[row.playerName]
        local nextRole = roles[1] -- default: start the cycle, or fall back here from a stale value
        if cur then
            for i, r in ipairs(roles) do
                if r == cur then
                    nextRole = roles[i + 1] -- nil past the last one -> back to class default
                    break
                end
            end
        end
        RaidConsumesDB.roleOverride[row.playerName] = nextRole
        RaidConsumes_RefreshList()
    end)
    row.roleBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_TOP")
        local className = (row.playerClass and RaidConsumes_ClassLabels[row.playerClass]) or "Class"
        local roles = RaidConsumes_ClassRoles[row.playerClass] or {}
        local roleNames = {}
        for _, r in ipairs(roles) do table.insert(roleNames, RaidConsumes_RoleLabels[r] or r) end
        if table.getn(roleNames) > 0 then
            GameTooltip:SetText("Click to override this raider's checklist: " .. className .. " (default) -> "
                .. table.concat(roleNames, " -> ") .. " -> " .. className)
        else
            GameTooltip:SetText(className .. " has no other role to override to.")
        end
        GameTooltip:Show()
    end)
    row.roleBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- 122 (was 112): the missing-icons/text column start. Bumped +10 so
    -- it clears the role button (which ends at x=108) with real breathing
    -- room instead of sitting almost flush against it.
    local MISSING_COL_X = 122

    row.missingText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.missingText:SetPoint("TOPLEFT", row, "TOPLEFT", MISSING_COL_X, 0)
    row.missingText:SetWidth(ROW_WIDTH - MISSING_COL_X)
    row.missingText:SetJustifyH("LEFT")

    -- One small icon button per missing item (a Button, not a plain
    -- Texture, since only Button-type frames can take mouse scripts in
    -- 1.12 -- needed here for the hover tooltip naming the item).
    row.missingIcons = {}
    for m = 1, MAX_MISSING_ICONS do
        local iconBtn = CreateFrame("Button", nil, row)
        iconBtn:SetWidth(MISSING_ICON_SIZE)
        iconBtn:SetHeight(MISSING_ICON_SIZE)
        iconBtn:SetPoint("TOPLEFT", row, "TOPLEFT", MISSING_COL_X + (m - 1) * (MISSING_ICON_SIZE + MISSING_ICON_GAP), -1)
        iconBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        iconBtn:SetScript("OnEnter", function()
            if iconBtn.itemLabel then
                GameTooltip:SetOwner(iconBtn, "ANCHOR_TOP")
                GameTooltip:SetText(iconBtn.itemLabel)
                GameTooltip:Show()
            end
        end)
        iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        iconBtn:Hide()
        row.missingIcons[m] = iconBtn
    end

    -- "+N" when someone's missing more than MAX_MISSING_ICONS items --
    -- rare, but better than silently truncating the list.
    row.missingMoreText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.missingMoreText:SetPoint("TOPLEFT", row, "TOPLEFT", MISSING_COL_X + MAX_MISSING_ICONS * (MISSING_ICON_SIZE + MISSING_ICON_GAP), 0)
    row.missingMoreText:SetTextColor(1, 0.3, 0.3, 1)
    row.missingMoreText:Hide()

    -- Line 2: the missing items' names spelled out, so the icons above
    -- don't rely on hovering each one to know what they are.
    row.missingNamesText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.missingNamesText:SetPoint("TOPLEFT", row, "TOPLEFT", 4, -(ROW_LINE1_HEIGHT + 2))
    row.missingNamesText:SetWidth(ROW_WIDTH - 8)
    row.missingNamesText:SetJustifyH("LEFT")
    row.missingNamesText:SetTextColor(0.85, 0.3, 0.3, 1)
    row.missingNamesText:Hide()

    row:Hide()
    rows[i] = row
end

-- Sorted-by-class copy of the last scan's results, for display only
-- (RaidConsumes_LastResults itself stays alphabetical from Scan.lua).
local function ClassSortedResults()
    local sorted = {}
    for _, entry in ipairs(RaidConsumes_LastResults or {}) do
        table.insert(sorted, entry)
    end
    table.sort(sorted, function(a, b)
        local ra, rb = ClassSortRank(a.class), ClassSortRank(b.class)
        if ra ~= rb then
            return ra < rb
        end
        return (a.name or "") < (b.name or "")
    end)
    return sorted
end

-- Returns the missing-required-item ITEMS (full table, not just the
-- label -- needed to resolve an icon) for one raider, checked against a
-- per-raider ROLE override if one is set (Tank/Healer/Physical DPS/Caster
-- DPS), otherwise against their class's list. Offline raiders are never
-- flagged missing anything (can't know what they'd have popped while
-- offline).
local function MissingItemsFor(entry)
    if not entry.online then
        return {}
    end
    local roleOverride = RaidConsumesDB.roleOverride and RaidConsumesDB.roleOverride[entry.name]
    local req = RaidConsumes_EnsureRequiredDefaults(roleOverride or entry.class)
    local missing = {}
    for _, item in ipairs(RaidConsumes_Items) do
        if req[item.key] then
            local has
            if RaidConsumes_ItemRequiresWeaponEnchant(item) then
                -- Never knowable for anyone but the scanning player -- see
                -- the isWeaponEnchant comment in Data.lua. Treat as
                -- "can't say" (not missing) for everyone else, same
                -- philosophy as offline raiders never being accused.
                has = entry.weaponBuffKnown and entry.weaponBuff or (not entry.weaponBuffKnown)
            else
                has = entry.hits[item.key]
            end
            if not has then
                table.insert(missing, item)
            end
        end
    end
    return missing
end

-- Same, but just the labels -- kept for the "offline" sentinel and for
-- anything (tests included) that only cares about display text, not icons.
local function MissingLabelsFor(entry)
    if not entry.online then
        return { "offline" }
    end
    local labels = {}
    for _, item in ipairs(MissingItemsFor(entry)) do
        table.insert(labels, item.label)
    end
    return labels
end

-- Builds line 2's text: missing item names, comma-separated, capped by
-- character count (not item count) so it can never wrap and bleed into
-- the row below (no 1.12 API clips FontString overflow). The first name
-- always shows in full regardless of length; only later names are gated
-- by the cap, with a "+N more" summary for whatever didn't fit.
local function BuildMissingNamesLine(items, maxChars)
    maxChars = maxChars or MAX_NAME_LINE_CHARS
    local total = table.getn(items)
    local parts = {}
    local usedChars = 0
    local shown = 0
    for _, item in ipairs(items) do
        local addition = (shown > 0 and ", " or "") .. item.label
        if shown > 0 and usedChars + string.len(addition) > maxChars then
            break
        end
        table.insert(parts, item.label)
        usedChars = usedChars + string.len(addition)
        shown = shown + 1
    end
    local text = table.concat(parts, ", ")
    if shown < total then
        text = text .. " +" .. (total - shown) .. " more"
    end
    return text
end

-- Pure data step (no frame access) so it's independently testable: sorts
-- the last scan's results by class then name, and computes each raider's
-- missing-required items (both as labels, for text/tests, and as full
-- item tables, for icon rendering) against their current checklist.
function RaidConsumes_ComputeDisplayRows()
    local sorted = ClassSortedResults()
    local total = table.getn(sorted)

    local readyCount = 0
    local rowsData = {}
    for _, entry in ipairs(sorted) do
        local missing = MissingLabelsFor(entry)
        local missingItems = MissingItemsFor(entry)
        if table.getn(missing) == 0 then
            readyCount = readyCount + 1
        end
        table.insert(rowsData, { entry = entry, missing = missing, missingItems = missingItems })
    end

    return rowsData, total, readyCount
end

-- Auto-whisper (opt-in, off by default -- see the checkbox/cooldown box in
-- the Settings window). Whispers a raider the moment a scan finds them
-- missing something they weren't missing on the PREVIOUS scan (edge-
-- detected, same not-had -> has idea usage/missed history already use,
-- just inverted -- "newly missing" instead of "newly has"), and again once
-- RaidConsumesDB.autoWhisperCooldown seconds have passed if they're STILL
-- missing something on a later scan -- so someone who never pops anything
-- gets a periodic nag, not silence after the first whisper, but also not a
-- fresh whisper on every single auto-check tick. Both trackers are
-- in-memory only (not persisted, like RaidConsumes_LastHitsByPlayer) and
-- global so tests can drive/inspect them directly.
RaidConsumes_LastWhisperTime = RaidConsumes_LastWhisperTime or {}
RaidConsumes_LastMissingSet = RaidConsumes_LastMissingSet or {}

-- Shared by the auto-whisper loop and the on-demand "Send Whisper Now"
-- button: sends the standard missing-consumables whisper and stamps the
-- cooldown tracker.
local function WhisperMissingRaider(name, missingItems)
    -- Capped well under vanilla's ~255-char chat message limit, leaving
    -- room for the surrounding sentence.
    local namesLine = BuildMissingNamesLine(missingItems, 150)
    SendChatMessage("RaidConsumes: you're missing " .. namesLine .. " -- please pop them for the raid!", "WHISPER", nil, name)
    RaidConsumes_LastWhisperTime[name] = time()
end

function RaidConsumes_ProcessAutoWhispers(rowsData)
    if not (RaidConsumesDB and RaidConsumesDB.autoWhisperEnabled) then
        return
    end
    local cooldown = RaidConsumesDB.autoWhisperCooldown or 300
    for _, rowData in ipairs(rowsData) do
        local entry = rowData.entry
        local name = entry.name
        -- Never whisper yourself, and offline raiders can't be missing
        -- anything actionable right now (MissingItemsFor already returns
        -- {} for them, so this is mostly a defensive skip).
        if entry.online and name and not UnitIsUnit(entry.unit, "player") then
            local missingItems = rowData.missingItems or {}
            if table.getn(missingItems) == 0 then
                -- Fully ready now -- forget what they were missing, so if
                -- they fall behind again later it's treated as fresh
                -- ("newly missing"), not a leftover cooldown.
                RaidConsumes_LastMissingSet[name] = nil
            else
                local prevSet = RaidConsumes_LastMissingSet[name] or {}
                local newSet = {}
                local isNew = false
                for _, item in ipairs(missingItems) do
                    newSet[item.key] = true
                    if not prevSet[item.key] then
                        isNew = true
                    end
                end
                local lastWhisper = RaidConsumes_LastWhisperTime[name]
                local cooldownElapsed = (not lastWhisper) or (time() - lastWhisper >= cooldown)
                if isNew or cooldownElapsed then
                    WhisperMissingRaider(name, missingItems)
                end
                RaidConsumes_LastMissingSet[name] = newSet
            end
        end
    end
end

-- "Send Whisper Now" (main window button): immediately whispers every
-- raider currently missing something, bypassing the cooldown/edge-
-- detection RaidConsumes_ProcessAutoWhispers uses for auto-whisper -- this
-- is an explicit, on-demand nag rather than the automatic re-nag loop.
-- Still records into the same trackers auto-whisper uses, so an
-- auto-whisper tick right afterward treats these as already-notified
-- instead of immediately whispering everyone again.
function RaidConsumes_SendWhisperNow()
    local rowsData = RaidConsumes_ComputeDisplayRows()
    local count = 0
    for _, rowData in ipairs(rowsData) do
        local entry = rowData.entry
        local name = entry.name
        if entry.online and name and not UnitIsUnit(entry.unit, "player") then
            local missingItems = rowData.missingItems or {}
            if table.getn(missingItems) > 0 then
                WhisperMissingRaider(name, missingItems)
                local newSet = {}
                for _, item in ipairs(missingItems) do
                    newSet[item.key] = true
                end
                RaidConsumes_LastMissingSet[name] = newSet
                count = count + 1
            end
        end
    end
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: everyone's ready -- no whispers sent.")
    else
        DEFAULT_CHAT_FRAME:AddMessage("RaidConsumes: whispered " .. count .. " raider" .. (count == 1 and "" or "s") .. ".")
    end
end

function RaidConsumes_RefreshList()
    local rowsData, total, readyCount = RaidConsumes_ComputeDisplayRows()
    RaidConsumes_ProcessAutoWhispers(rowsData)

    if total == 0 then
        summaryText:SetText("No raid/party detected -- click Check Raid.")
    elseif readyCount == total then
        summaryText:SetText("|cff20ff20All " .. total .. " raiders are ready!|r")
    else
        summaryText:SetText("|cffff3030" .. (total - readyCount) .. " of " .. total .. " raiders missing a consumable|r")
    end

    -- "Only show not ready" filters the visible rows/scroll range down to
    -- raiders missing something, but summaryText above still reports the
    -- TRUE full-roster counts (total/readyCount), not the filtered ones.
    local visibleRowsData = rowsData
    if RaidConsumesDB and RaidConsumesDB.hideReadyPlayers then
        visibleRowsData = {}
        for _, rowData in ipairs(rowsData) do
            if table.getn(rowData.missing) > 0 then
                table.insert(visibleRowsData, rowData)
            end
        end
    end

    FauxScrollFrame_Update(scrollFrame, table.getn(visibleRowsData), NUM_ROWS, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(scrollFrame)

    for i = 1, NUM_ROWS do
        local idx = i + offset
        local rowData = visibleRowsData[idx]
        local row = rows[i]
        if rowData then
            -- pcall'd per-row: a bug rendering ONE raider's row (bad data,
            -- an unexpected class token, etc.) prints to chat instead of
            -- silently leaving that row (and, before this, every row after
            -- it) blank.
            local ok, err = pcall(function()
                local data = rowData.entry
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
                if classColor then
                    row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
                else
                    row.nameText:SetTextColor(1, 1, 1, 1)
                end
                row.nameText:SetText(data.name or "?")

                row.playerName = data.name
                row.playerClass = data.class
                local roleOverride = RaidConsumesDB.roleOverride and RaidConsumesDB.roleOverride[data.name]
                if roleOverride == "TANK" then
                    row.roleBtn.text:SetText("Tank")
                    row.roleBtn.text:SetTextColor(0.4, 0.7, 1, 1)
                elseif roleOverride == "HEALER" then
                    row.roleBtn.text:SetText("Heal")
                    row.roleBtn.text:SetTextColor(0.4, 1, 0.5, 1)
                elseif roleOverride == "PHYSDPS" then
                    row.roleBtn.text:SetText("Phys")
                    row.roleBtn.text:SetTextColor(1, 0.5, 0.4, 1)
                elseif roleOverride == "CASTERDPS" then
                    row.roleBtn.text:SetText("Cast")
                    row.roleBtn.text:SetTextColor(0.8, 0.4, 1, 1)
                else
                    -- No override: show the raider's own class instead of
                    -- a bare "-", so the button reads as "this is their
                    -- current setting, click to change it" rather than
                    -- looking blank/disabled.
                    row.roleBtn.text:SetText(CLASS_ABBREV[data.class] or "-")
                    if classColor then
                        row.roleBtn.text:SetTextColor(classColor.r, classColor.g, classColor.b, 1)
                    else
                        row.roleBtn.text:SetTextColor(0.8, 0.8, 0.8, 1)
                    end
                end

                if table.getn(rowData.missing) == 0 then
                    row.missingText:SetTextColor(0.4, 1, 0.4, 1)
                    row.missingText:SetText("Ready")
                    row.missingText:Show()
                    for _, iconBtn in ipairs(row.missingIcons) do iconBtn:Hide() end
                    row.missingMoreText:Hide()
                    row.missingNamesText:Hide()
                elseif not data.online then
                    row.missingText:SetTextColor(0.6, 0.6, 0.6, 1)
                    row.missingText:SetText("offline")
                    row.missingText:Show()
                    for _, iconBtn in ipairs(row.missingIcons) do iconBtn:Hide() end
                    row.missingMoreText:Hide()
                    row.missingNamesText:Hide()
                else
                    -- Missing something and online: show item icons plus
                    -- their names spelled out on the line below, instead
                    -- of a hover-only tooltip or a plain text list.
                    row.missingText:Hide()
                    local items = rowData.missingItems or {}
                    local missingCount = table.getn(items)
                    for m, iconBtn in ipairs(row.missingIcons) do
                        local item = items[m]
                        if item then
                            iconBtn:SetNormalTexture(ResolveIcon(item))
                            iconBtn.itemLabel = item.label
                            iconBtn:Show()
                        else
                            iconBtn:Hide()
                        end
                    end
                    if missingCount > MAX_MISSING_ICONS then
                        row.missingMoreText:SetText("+" .. (missingCount - MAX_MISSING_ICONS))
                        row.missingMoreText:Show()
                    else
                        row.missingMoreText:Hide()
                    end
                    row.missingNamesText:SetText(BuildMissingNamesLine(items))
                    row.missingNamesText:Show()
                end

                row.nameText:SetAlpha(1)
                row.missingText:SetAlpha(1)
                row.missingNamesText:SetAlpha(1)
                row.roleBtn.text:SetAlpha(1)
                row:Show()
            end)
            if not ok then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes row error:|r " .. tostring(err))
                row:Hide()
            end
        else
            row:Hide()
        end
    end

    if RaidConsumes_LastScanTime then
        scanTimeText:SetText("Last checked: " .. date("%H:%M:%S", RaidConsumes_LastScanTime))
    end
end

checkBtn:SetScript("OnClick", function()
    RaidConsumes_ScanRaid()
    RaidConsumes_RefreshList()
end)

function RaidConsumes_ShowWindow()
    if RaidConsumesDB and RaidConsumesDB.framePos then
        local p = RaidConsumesDB.framePos
        frame:ClearAllPoints()
        frame:SetPoint(p.point or "CENTER", UIParent, p.relPoint or "CENTER", p.x or 0, p.y or 0)
    end
    frame:Show()
    RaidConsumes_RefreshAutoScanControls()
    RaidConsumes_RefreshAutoWhisperControls()
    RaidConsumes_RefreshOpacityControls()
    RaidConsumes_RefreshHideReadyControl()
    RaidConsumes_ApplyWindowOpacity(tostring(RaidConsumesDB.windowOpacity or 100))
    RaidConsumes_ScanRaid()
    RaidConsumes_RefreshList()
end

function RaidConsumes_ToggleWindow()
    if frame:IsShown() then
        frame:Hide()
    else
        RaidConsumes_ShowWindow()
    end
end

settingsBtn:SetScript("OnClick", function()
    RaidConsumes_ToggleSettings()
end)

-- ===================== settings window =====================

local SETTING_ROW_HEIGHT = 22
local NUM_SETTING_ROWS = 14
-- 430 (was 340): wide enough for the grid buttons to spell out "Physical
-- DPS"/"Caster DPS" in full instead of abbreviating them.
local SETTINGS_WIDTH = 430

local settings = CreateFrame("Frame", "RaidConsumesSettingsFrame", UIParent)
settings:SetWidth(SETTINGS_WIDTH)
-- 750 (was 693, was 613 before that): splitting DPS into Physical/Caster
-- adds a 13th profile to the grid, pushing it from 4 rows to 5 (at 3
-- columns) -- +23px (one PROFILE_BTN_HEIGHT + PROFILE_BTN_SPACING_Y); +80
-- more for the per-category show/hide toggle row added above the
-- checklist. (Auto-whisper moved to the main window in v2.6.0, so it no
-- longer adds to this.) +57 more in v2.6.2: adding up every fixed-height
-- element from the title down through the 14-row checklist showed the
-- checklist's own bottom row landing ~20-40px below where 693 actually
-- ends (confirmed by a screenshot: the last category header rendering
-- right at/past the window's bottom border) -- this wasn't introduced by
-- any single change, it's the accumulated total of everything stacked
-- above the checklist finally exceeding the window height. Bumped with
-- real margin instead of another minimal nudge.
settings:SetHeight(750)
settings:SetFrameStrata("DIALOG") -- always draw above the main window and other addon UI
settings:SetClampedToScreen(true) -- can never end up positioned off-screen
-- Solid black fill, same as the main window above -- see that comment.
settings:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
settings:SetBackdropColor(0, 0, 0, 1)
settings:SetMovable(true)
settings:EnableMouse(true)
settings:RegisterForDrag("LeftButton")
settings:SetScript("OnDragStart", function() this:StartMoving() end)
settings:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
settings:Hide()

-- Clamps and stores whatever's typed in the main window's opacity box
-- (garbage falls back to the current/default value), applies it to BOTH
-- windows immediately, and reflects the accepted value back into the box.
-- Defined here (after both `frame` and `settings` exist) rather than up
-- in the main-window section, since it needs to reach both.
function RaidConsumes_ApplyWindowOpacity(text)
    local n = tonumber(text)
    if not n then
        n = RaidConsumesDB.windowOpacity or DEFAULT_WINDOW_OPACITY
    end
    if n < MIN_WINDOW_OPACITY then n = MIN_WINDOW_OPACITY end
    if n > MAX_WINDOW_OPACITY then n = MAX_WINDOW_OPACITY end
    RaidConsumesDB.windowOpacity = n
    opacityBox:SetText(tostring(n))
    frame:SetAlpha(n / 100)
    settings:SetAlpha(n / 100)
end

-- Reflects RaidConsumesDB's stored opacity into the box -- called whenever
-- the main window opens, so it's never stale after a /reload.
function RaidConsumes_RefreshOpacityControls()
    opacityBox:SetText(tostring(RaidConsumesDB.windowOpacity or DEFAULT_WINDOW_OPACITY))
end

local settingsTitle = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
settingsTitle:SetPoint("TOP", settings, "TOP", 0, -14)
settingsTitle:SetText("Settings")

local settingsCloseBtn = CreateFrame("Button", nil, settings, "UIPanelCloseButton")
settingsCloseBtn:SetPoint("TOPRIGHT", settings, "TOPRIGHT", -4, -4)
settingsCloseBtn:SetScript("OnClick", function() settings:Hide() end)

-- ---- class/role selector grid ----
-- One combined grid of buttons: the 9 real classes plus the 4 role
-- profiles (Tank/Healer/Physical DPS/Caster DPS) -- both use the exact
-- same required-item storage (RaidConsumesDB.required[token]), so a
-- "role" is just another selectable profile here.

local settingsProfiles = {}
for _, c in ipairs(RaidConsumes_Classes) do table.insert(settingsProfiles, c) end
for _, r in ipairs(RaidConsumes_Roles) do table.insert(settingsProfiles, r) end

local PROFILE_BTN_WIDTH = 130
local PROFILE_BTN_HEIGHT = 20
local PROFILE_BTN_COLS = 3
local PROFILE_BTN_SPACING_X = 4
local PROFILE_BTN_SPACING_Y = 3

local classBar = CreateFrame("Frame", nil, settings)
classBar:SetPoint("TOP", settings, "TOP", 0, -34)
local numProfiles = table.getn(settingsProfiles)
local numProfileRows = math.ceil(numProfiles / PROFILE_BTN_COLS)
classBar:SetWidth(PROFILE_BTN_COLS * PROFILE_BTN_WIDTH + (PROFILE_BTN_COLS - 1) * PROFILE_BTN_SPACING_X)
classBar:SetHeight(numProfileRows * PROFILE_BTN_HEIGHT + (numProfileRows - 1) * PROFILE_BTN_SPACING_Y)

local classButtons = {}
for i, profile in ipairs(settingsProfiles) do
    local idx0 = i - 1
    local rowNum = math.floor(idx0 / PROFILE_BTN_COLS)
    local col = idx0 - rowNum * PROFILE_BTN_COLS
    local btn = CreateFrame("Button", "RaidConsumesClassBtn" .. i, classBar, "UIPanelButtonTemplate")
    btn:SetWidth(PROFILE_BTN_WIDTH)
    btn:SetHeight(PROFILE_BTN_HEIGHT)
    btn:SetPoint("TOPLEFT", classBar, "TOPLEFT",
        col * (PROFILE_BTN_WIDTH + PROFILE_BTN_SPACING_X),
        -rowNum * (PROFILE_BTN_HEIGHT + PROFILE_BTN_SPACING_Y))
    btn:SetText(ProfileLabel(profile))
    local pr, pg, pb = ProfileColor(profile)
    btn:GetFontString():SetTextColor(pr, pg, pb)
    btn.profile = profile
    btn:SetScript("OnClick", function()
        RaidConsumes_SelectSettingsClass(this.profile)
    end)
    classButtons[i] = btn
end

local settingsClassLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
settingsClassLabel:SetPoint("TOP", classBar, "BOTTOM", 0, -8)
settingsClassLabel:SetText("")

local settingsHint = settings:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
settingsHint:SetPoint("TOP", settingsClassLabel, "BOTTOM", 0, -4)
settingsHint:SetWidth(SETTINGS_WIDTH - 32)
settingsHint:SetText("Ticked items are required for the selected class/role. Roles can be assigned to individual raiders on the main window.")

local resetBtn = CreateFrame("Button", "RaidConsumesResetButton", settings, "UIPanelButtonTemplate")
resetBtn:SetWidth(120)
resetBtn:SetHeight(20)
resetBtn:SetPoint("TOP", settingsHint, "BOTTOM", 0, -6)
resetBtn:SetText("Reset to Defaults")
resetBtn:SetScript("OnClick", function()
    RaidConsumes_ResetProfileToDefaults(RaidConsumesDB_SelectedClass)
end)

-- ---- checklist sync (push to raid/party over the addon-message channel,
-- see Sync.lua) ----

local syncBar = CreateFrame("Frame", nil, settings)
syncBar:SetPoint("TOP", resetBtn, "BOTTOM", 0, -8)
syncBar:SetWidth(206)
syncBar:SetHeight(20)

-- Both require sync authority (raid officer/leader, or party leader) --
-- a non-authorized click prints a warning instead of sending anything, so
-- the tooltip explains that up front rather than surprising people.
local SYNC_AUTHORITY_TOOLTIP = "Requires raid officer/leader or party leader. Anyone else: use \"Request Sync From Officer\" below instead."

local syncClassBtn = CreateFrame("Button", "RaidConsumesSyncClassButton", syncBar, "UIPanelButtonTemplate")
syncClassBtn:SetWidth(110)
syncClassBtn:SetHeight(20)
syncClassBtn:SetPoint("LEFT", syncBar, "LEFT", 0, 0)
syncClassBtn:SetText("Sync This Class")
syncClassBtn:SetScript("OnClick", function()
    if RaidConsumesDB_SelectedClass then
        RaidConsumes_SyncBroadcastProfile(RaidConsumesDB_SelectedClass)
    end
end)
syncClassBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(SYNC_AUTHORITY_TOOLTIP)
    GameTooltip:Show()
end)
syncClassBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local syncAllBtn = CreateFrame("Button", "RaidConsumesSyncAllButton", syncBar, "UIPanelButtonTemplate")
syncAllBtn:SetWidth(90)
syncAllBtn:SetHeight(20)
syncAllBtn:SetPoint("LEFT", syncClassBtn, "RIGHT", 6, 0)
syncAllBtn:SetText("Sync All")
syncAllBtn:SetScript("OnClick", function()
    RaidConsumes_SyncBroadcastAll()
end)
syncAllBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText(SYNC_AUTHORITY_TOOLTIP)
    GameTooltip:Show()
end)
syncAllBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Anyone can click this one, no authority needed to ASK -- only to
-- answer. Whichever officer/leader is online with the addon auto-replies
-- privately with every checklist.
local requestSyncBtn = CreateFrame("Button", "RaidConsumesRequestSyncButton", settings, "UIPanelButtonTemplate")
requestSyncBtn:SetWidth(206)
requestSyncBtn:SetHeight(20)
requestSyncBtn:SetPoint("TOP", syncBar, "BOTTOM", 0, -6)
requestSyncBtn:SetText("Request Sync From Officer")
requestSyncBtn:SetScript("OnClick", function()
    RaidConsumes_SyncRequest()
end)
requestSyncBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:SetText("Asks your raid/party's officers to send you their current checklists. Anyone can ask; whoever's online with the addon and holds officer/leader rank replies privately.")
    GameTooltip:Show()
end)
requestSyncBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Left-aligned under requestSyncBtn (not perfectly centered -- a minor
-- cosmetic tradeoff for not having to guess the rendered width of the
-- label text).
local syncAcceptCheck = CreateFrame("CheckButton", "RaidConsumesSyncAcceptCheck", settings, "UICheckButtonTemplate")
syncAcceptCheck:SetWidth(20)
syncAcceptCheck:SetHeight(20)
syncAcceptCheck:SetPoint("TOPLEFT", requestSyncBtn, "BOTTOMLEFT", 0, -4)
syncAcceptCheck:SetScript("OnClick", function()
    RaidConsumesDB.syncEnabled = syncAcceptCheck:GetChecked() and true or false
end)

local syncAcceptLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
syncAcceptLabel:SetPoint("LEFT", syncAcceptCheck, "RIGHT", 2, 0)
syncAcceptLabel:SetText("Accept checklist syncs from raid/party")

-- ---- scrollable item checklist ----

-- Anchored off syncBar (properly centered), not the rows below it, so the
-- list stays centered; -62 clears both the Request Sync row and the
-- checkbox row now stacked beneath syncBar.
local settingsScroll = CreateFrame("ScrollFrame", "RaidConsumesSettingsScrollFrame", settings, "FauxScrollFrameTemplate")
settingsScroll:SetPoint("TOP", syncBar, "BOTTOM", -10, -62)
settingsScroll:SetWidth(SETTINGS_WIDTH - 40)
settingsScroll:SetHeight(NUM_SETTING_ROWS * SETTING_ROW_HEIGHT)
settingsScroll:SetScript("OnVerticalScroll", function()
    FauxScrollFrame_OnVerticalScroll(SETTING_ROW_HEIGHT, function() RaidConsumes_RefreshSettings() end)
end)

local checkRows = {}
for i = 1, NUM_SETTING_ROWS do
    -- Parented straight to `settings` (the settings window), not to
    -- settingsScroll, and bumped to TOOLTIP strata -- same fix already
    -- applied to the main window's roster rows above (see the comment on
    -- `rows` near RaidConsumesScrollFrame): on this client, some other
    -- addon's frame draws on top of that exact strip of the screen even
    -- though these rows report shown/sized/positioned correctly at their
    -- normal strata. Without this, the checklist icons/checkboxes/labels
    -- render underneath whatever that other UI is, which is what showed up
    -- as icons "not lining up" in the settings list.
    local row = CreateFrame("Frame", "RaidConsumesSettingRow" .. i, settings)
    row:SetWidth(SETTINGS_WIDTH - 40)
    row:SetHeight(SETTING_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", settingsScroll, "TOPLEFT", 0, -(i - 1) * SETTING_ROW_HEIGHT)
    row:SetFrameStrata("TOOLTIP")
    row:SetFrameLevel(settingsScroll:GetFrameLevel() + 1)

    -- A Button (not a plain Texture) so it can take mouse scripts -- only
    -- Button-type frames get OnEnter/OnLeave in 1.12 -- needed for the
    -- hover tooltip naming the item, same pattern as the main window's
    -- missing-item icons.
    row.icon = CreateFrame("Button", nil, row)
    row.icon:SetWidth(16)
    row.icon:SetHeight(16)
    -- +12 (was 6, was 0 before that): `row` starts only ~10px from the
    -- Settings window's own left border (settingsScroll sits close to
    -- it), so an icon anchored flush at row's own left edge rendered
    -- right against/under that border art. First nudge (+6) wasn't
    -- enough -- doubled it.
    row.icon:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.icon.texture = row.icon:CreateTexture(nil, "ARTWORK")
    row.icon.texture:SetAllPoints(row.icon)
    row.icon:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    row.icon:SetScript("OnEnter", function()
        if row.icon.itemLabel then
            GameTooltip:SetOwner(row.icon, "ANCHOR_TOPLEFT")
            GameTooltip:SetText(row.icon.itemLabel)
            GameTooltip:Show()
        end
    end)
    row.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.check = CreateFrame("CheckButton", "RaidConsumesSettingCheck" .. i, row, "UICheckButtonTemplate")
    row.check:SetWidth(20)
    row.check:SetHeight(20)
    row.check:SetPoint("LEFT", row.icon, "RIGHT", 2, 0)
    row.check:SetScript("OnClick", function()
        local req = RaidConsumes_EnsureRequiredDefaults(RaidConsumesDB_SelectedClass)
        if row.itemKey then
            req[row.itemKey] = row.check:GetChecked() and true or false
        end
        RaidConsumes_RefreshList()
    end)

    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.label:SetPoint("LEFT", row.check, "RIGHT", 2, 0)
    -- -56 (was -50, was -44 before that): shrunk by the same 12px the
    -- icon/check/label group as a whole shifted right by, so the label
    -- still ends at the row's original right edge instead of overflowing
    -- it.
    row.label:SetWidth(SETTINGS_WIDTH - 40 - 56)
    row.label:SetJustifyH("LEFT")

    -- Non-interactive category/subcategory divider row (shown instead of
    -- icon/check/label). Re-anchored and re-styled per use since the same
    -- FontString serves both category headers (bold, gold, flush left) and
    -- subcategory headers (smaller, blue, indented).
    row.headerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.headerText:SetWidth(SETTINGS_WIDTH - 40)
    row.headerText:SetJustifyH("LEFT")
    row.headerText:Hide()

    row:Hide()
    checkRows[i] = row
end

-- Category -> which of the 4 shared roles it corresponds to, used to work
-- out which categories a given class/role profile can actually use.
local ROLE_TO_CATEGORY = {
    TANK = "Tanks", HEALER = "Healers", PHYSDPS = "Physical DPS", CASTERDPS = "Caster DPS",
}

-- Per-category show/hide state for whatever profile is currently selected.
-- Reset to sensible defaults on every profile switch (see
-- DefaultCategoryVisibility below), but every category also gets its own
-- checkbox so any of them can be revealed or hidden by hand -- e.g. peek at
-- the Tank list while a Paladin is selected, or hide Universal to focus on
-- just the class-specific items.
local categoryVisible = {}

-- Narrows the checklist down to what a profile can actually use: a class
-- only sees the categories tied to roles it can fill (RaidConsumes_ClassRoles)
-- plus Universal (ALL), which applies to everyone; Paladin/Shaman Mix is
-- shown only for those two classes; a role profile (TANK/HEALER/PHYSDPS/
-- CASTERDPS) sees just its own matching category plus Universal. Keeps a
-- Mage's ~6 relevant items from being buried under ~40 Tank/Heal/Physical
-- DPS ones it'll never check.
local function DefaultCategoryVisibility(profile)
    for _, cat in ipairs(RaidConsumes_CategoryOrder) do
        categoryVisible[cat] = false
    end
    categoryVisible["Universal (ALL)"] = true
    local classRoles = RaidConsumes_ClassRoles[profile]
    if classRoles then
        for _, role in ipairs(classRoles) do
            local cat = ROLE_TO_CATEGORY[role]
            if cat then categoryVisible[cat] = true end
        end
        if profile == "PALADIN" or profile == "SHAMAN" then
            categoryVisible["Paladin/Shaman Mix"] = true
        end
    else
        local cat = ROLE_TO_CATEGORY[profile]
        if cat then categoryVisible[cat] = true end
    end
end

-- Flat list mixing category headers, subcategory headers, and items --
-- sorted by category (per RaidConsumes_CategoryOrder), then subcategory
-- (per RaidConsumes_SubcategoryOrder), then alphabetically by label. Only
-- includes categories currently marked visible (see categoryVisible below),
-- so it's rebuilt whenever the selected profile or a toggle changes -- not
-- the same for every class/role anymore, unlike before the per-category
-- filtering was added.
local function BuildSettingsFlatRows()
    local flat = {}
    local lastCategory, lastSub = nil, nil
    for _, item in ipairs(RaidConsumes_GetSortedItems()) do
        if categoryVisible[item.category] ~= false then
            if item.category ~= lastCategory then
                table.insert(flat, { rowType = "category", text = item.category or "Other" })
                lastCategory = item.category
                lastSub = nil -- force a subcategory header under the new category too
            end
            if item.subcategory ~= lastSub then
                table.insert(flat, { rowType = "subcategory", text = item.subcategory or "Other" })
                lastSub = item.subcategory
            end
            table.insert(flat, { rowType = "item", item = item })
        end
    end
    return flat
end

local settingsFlatRows = BuildSettingsFlatRows()

function RaidConsumes_RefreshSettings()
    local profile = RaidConsumesDB_SelectedClass
    if not profile then
        return
    end
    local req = RaidConsumes_EnsureRequiredDefaults(profile)
    local total = table.getn(settingsFlatRows)

    FauxScrollFrame_Update(settingsScroll, total, NUM_SETTING_ROWS, SETTING_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(settingsScroll)

    for i = 1, NUM_SETTING_ROWS do
        local idx = i + offset
        local flatRow = settingsFlatRows[idx]
        local row = checkRows[i]
        if not flatRow then
            row:Hide()
        elseif flatRow.rowType == "category" or flatRow.rowType == "subcategory" then
            row.itemKey = nil
            row.icon.itemLabel = nil
            row.icon:Hide()
            row.check:Hide()
            row.label:Hide()
            row.headerText:ClearAllPoints()
            if flatRow.rowType == "category" then
                row.headerText:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.headerText:SetFontObject(GameFontNormal)
                row.headerText:SetTextColor(1, 0.82, 0)
            else
                row.headerText:SetPoint("LEFT", row, "LEFT", 14, 0)
                row.headerText:SetFontObject(GameFontNormalSmall)
                row.headerText:SetTextColor(0.55, 0.8, 1)
            end
            row.headerText:SetText(flatRow.text)
            row.headerText:Show()
            row:Show()
        else
            local item = flatRow.item
            row.itemKey = item.key
            row.headerText:Hide()
            row.icon.texture:SetTexture(ResolveIcon(item))
            row.icon.itemLabel = item.label
            row.icon:Show()
            row.check:SetChecked(req[item.key])
            row.check:Show()
            row.label:SetText(item.label)
            row.label:Show()
            row:Show()
        end
    end
end

function RaidConsumes_SelectSettingsClass(profile)
    RaidConsumesDB_SelectedClass = profile
    settingsClassLabel:SetText(ProfileLabel(profile))
    local pr, pg, pb = ProfileColor(profile)
    settingsClassLabel:SetTextColor(pr, pg, pb)
    for _, btn in ipairs(classButtons) do
        if btn.profile == profile then
            btn:LockHighlight()
        else
            btn:UnlockHighlight()
        end
    end
    DefaultCategoryVisibility(profile)
    settingsFlatRows = BuildSettingsFlatRows()
    RaidConsumes_RefreshCategoryToggles()
    RaidConsumes_RefreshSettings()
end

-- ---- per-category show/hide toggles ----
-- Sits between the sync controls and the checklist itself: switching
-- class/role already narrows the list down to sensible defaults (see
-- DefaultCategoryVisibility above), but every category gets its own
-- checkbox here to reveal or hide it by hand on top of that default.
local categoryToggleLabel = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
categoryToggleLabel:SetPoint("TOP", syncAcceptLabel, "BOTTOM", 0, -10)
categoryToggleLabel:SetText("Show categories:")

local CATEGORY_TOGGLE_COLS = 2
local CATEGORY_TOGGLE_COL_WIDTH = (SETTINGS_WIDTH - 40) / CATEGORY_TOGGLE_COLS
local CATEGORY_TOGGLE_ROW_HEIGHT = 22

local categoryToggleBar = CreateFrame("Frame", nil, settings)
categoryToggleBar:SetPoint("TOP", categoryToggleLabel, "BOTTOM", 0, -4)
local numCategoryRows = math.ceil(table.getn(RaidConsumes_CategoryOrder) / CATEGORY_TOGGLE_COLS)
categoryToggleBar:SetWidth(SETTINGS_WIDTH - 40)
categoryToggleBar:SetHeight(numCategoryRows * CATEGORY_TOGGLE_ROW_HEIGHT)

local categoryToggles = {}
for i, cat in ipairs(RaidConsumes_CategoryOrder) do
    local idx0 = i - 1
    local rowNum = math.floor(idx0 / CATEGORY_TOGGLE_COLS)
    local col = idx0 - rowNum * CATEGORY_TOGGLE_COLS

    local check = CreateFrame("CheckButton", "RaidConsumesCategoryToggle" .. i, categoryToggleBar, "UICheckButtonTemplate")
    check:SetWidth(20)
    check:SetHeight(20)
    check:SetPoint("TOPLEFT", categoryToggleBar, "TOPLEFT",
        col * CATEGORY_TOGGLE_COL_WIDTH, -rowNum * CATEGORY_TOGGLE_ROW_HEIGHT)
    check.category = cat
    -- Reads this.category/this rather than closing over the loop variables
    -- (cat/check) directly. The class/role grid buttons above do the same
    -- (this.profile, not a captured `profile`) -- storing per-widget data
    -- on the widget itself rather than trusting a loop-variable closure is
    -- the established, working pattern in this codebase for buttons
    -- created in a loop. This one didn't follow it and threw "table index
    -- is nil" in-game (confirmed by Ryan) despite passing every test --
    -- test_scan.lua runs on lua5.1, and whatever the game's own Lua 5.0
    -- does differently here, it clearly doesn't behave the same way.
    check:SetScript("OnClick", function()
        categoryVisible[this.category] = this:GetChecked() and true or false
        settingsFlatRows = BuildSettingsFlatRows()
        RaidConsumes_RefreshSettings()
    end)

    local label = categoryToggleBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(cat)

    categoryToggles[i] = check
end

-- Syncs every checkbox's checked state to categoryVisible -- called after
-- a profile switch resets the defaults, so the boxes always reflect what's
-- actually showing below them.
function RaidConsumes_RefreshCategoryToggles()
    for _, check in ipairs(categoryToggles) do
        check:SetChecked(categoryVisible[check.category] and true or false)
    end
end

-- Which categories are currently visible in the checklist (categoryName ->
-- true), independent of scroll position -- for external inspection.
function RaidConsumes_GetVisibleCategories()
    local copy = {}
    for _, cat in ipairs(RaidConsumes_CategoryOrder) do
        if categoryVisible[cat] then
            copy[cat] = true
        end
    end
    return copy
end

-- The checklist scroll list was anchored off syncBar; re-anchor it below
-- the new toggle row instead so it doesn't overlap.
settingsScroll:ClearAllPoints()
settingsScroll:SetPoint("TOP", categoryToggleBar, "BOTTOM", -10, -10)

function RaidConsumes_ToggleSettings()
    if settings:IsShown() then
        settings:Hide()
    else
        -- Re-anchor fresh every time, relative to wherever the main window
        -- currently is -- with clamping this can never render off-screen,
        -- even after the main window has been dragged around.
        settings:ClearAllPoints()
        if frame:IsShown() then
            settings:SetPoint("LEFT", frame, "RIGHT", 10, 0)
        else
            settings:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
        end
        -- Populating the checklist is pcall'd so that a bug in the list
        -- rendering can never again silently block the window itself from
        -- showing -- worst case you'd see an empty/partial checklist
        -- instead of the whole window refusing to open.
        local ok, err = pcall(RaidConsumes_SelectSettingsClass, RaidConsumesDB_SelectedClass or "WARRIOR")
        if not ok then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff3030RaidConsumes Settings error:|r " .. tostring(err))
        end
        syncAcceptCheck:SetChecked(RaidConsumesDB.syncEnabled and true or false)
        settings:Show()
    end
end

-- Sets a permanent icon override for one item, used by the "/rc icon"
-- slash command (RaidConsumes.lua) -- lets you fix any wrong icon
-- in-game by shift-clicking the real item into chat, no code edit needed.
function RaidConsumes_SetIconOverride(itemKey, itemID)
    RaidConsumesDB.iconOverrides = RaidConsumesDB.iconOverrides or {}
    RaidConsumesDB.iconOverrides[itemKey] = itemID
    RaidConsumes_RefreshSettings()
end

-- Adds an extra buff name to match for an item, used by the "/rc name"
-- slash command -- lets you fix a name mismatch (a custom OctoWoW/Turtle
-- item whose actual applied buff doesn't match Data.lua's guess) yourself,
-- in-game, no code edit needed. Additive (appends to a list) rather than
-- replacing, so it can never break an already-working match.
function RaidConsumes_AddNameOverride(itemKey, buffName)
    RaidConsumesDB.nameOverrides = RaidConsumesDB.nameOverrides or {}
    RaidConsumesDB.nameOverrides[itemKey] = RaidConsumesDB.nameOverrides[itemKey] or {}
    for _, existing in ipairs(RaidConsumesDB.nameOverrides[itemKey]) do
        if existing == buffName then
            return false -- already there
        end
    end
    table.insert(RaidConsumesDB.nameOverrides[itemKey], buffName)
    return true
end

-- Clears every /rc name override for one item (back to just Data.lua's
-- built-in names list).
function RaidConsumes_ClearNameOverrides(itemKey)
    if RaidConsumesDB.nameOverrides then
        RaidConsumesDB.nameOverrides[itemKey] = nil
    end
end

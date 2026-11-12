-- SwingCast
-- Copyright (c) 2026 Bencepo. All rights reserved.
--
-- Adds to the standard player cast bar instead of replacing it:
--   * spell icon left of the bar
--   * remaining cast time on the bar
--   * latency zone at the end of the bar (red: what the server still needs)
--   * the swing timer as a thin strip right under the bar
-- The swing strip mirrors Forever's built-in swing timer (Blizzard_SwingTimer). That
-- timer is the only accurate one, because Forever keeps the combat log from addons.
-- SwingCast only draws it in its own place and look, and tints it while an
-- on-next-swing ability (Maul, Heroic Strike, Cleave, Raptor Strike) is queued.
-- The built-in swing timer has to be switched on (Options > Advanced > Swing Timer).
--
-- /swc  lists the settings.

local ADDON = ...

local DEFAULTS = {
	icon = true,       -- spell icon left of the cast bar
	time = true,       -- remaining cast time on the cast bar
	latency = true,    -- latency zone at the end of the cast bar
	swing = true,      -- swing strip under the cast bar
	swingText = true,  -- seconds to the next swing on the strip
	hideNative = true, -- hide the look of the built-in swing timer bars
	height = 6,        -- height of a swing strip in pixels
}

local SWING_FRAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }

local COLOR_SWING = { 0.85, 0.85, 0.85 }
local COLOR_QUEUED = { 1.00, 0.55, 0.10 }
local COLOR_CLEAVE = { 0.25, 0.60, 1.00 }

-- All ranks: an old action button can still hold a low rank, and IsCurrentSpell
-- only reports the exact rank that was queued. First match decides the colour.
local QUEUE = {
	DRUID = { -- Maul
		{ ids = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }, color = COLOR_QUEUED },
	},
	WARRIOR = { -- Heroic Strike, Cleave
		{ ids = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }, color = COLOR_QUEUED },
		{ ids = { 845, 7369, 11608, 11609, 20569 }, color = COLOR_CLEAVE },
	},
	HUNTER = { -- Raptor Strike
		{ ids = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }, color = COLOR_QUEUED },
	},
}

local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
local _, playerClass = UnitClass("player")
local queueList = QUEUE[playerClass]

local db
local castBar -- the standard player cast bar

local function P(msg) print("|cff7fbf3fSwingCast:|r " .. msg) end

---------------------------------------------------------------- cast bar
local icon, timeText, lagTex
local castEnd

local function castInfo()
	local name, _, tex, startMS, endMS = UnitCastingInfo("player")
	if name then return tex, startMS, endMS, false end
	name, _, tex, startMS, endMS = UnitChannelInfo("player")
	if name then return tex, startMS, endMS, true end
end

local function castRefresh()
	local tex, startMS, endMS, channel = castInfo()
	if not tex then
		castEnd = nil
		lagTex:Hide()
		return
	end
	castEnd = endMS / 1000

	icon:SetTexture(tex)
	icon:SetShown(db.icon)

	local dur = (endMS - startMS) / 1000
	local _, _, home, world = GetNetStats()
	local lag = math.max(home or 0, world or 0) / 1000
	if db.latency and dur > 0 and lag > 0 then
		local w = castBar:GetWidth() * math.min(lag / dur, 1)
		lagTex:ClearAllPoints()
		if channel then
			lagTex:SetPoint("TOPLEFT", castBar, "TOPLEFT")
			lagTex:SetPoint("BOTTOMLEFT", castBar, "BOTTOMLEFT")
		else
			lagTex:SetPoint("TOPRIGHT", castBar, "TOPRIGHT")
			lagTex:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT")
		end
		lagTex:SetWidth(math.max(w, 1))
		lagTex:Show()
	else
		lagTex:Hide()
	end
end

local function castOnUpdate()
	if not (db.time and castEnd) then
		timeText:SetText("")
		return
	end
	local left = castEnd - GetTime()
	timeText:SetText(left > 0 and string.format("%.1f", left) or "")
end

local function setupCastBar()
	castBar = PlayerCastingBarFrame or CastingBarFrame
	if not castBar then
		P("standard cast bar not found, cast bar parts are off.")
		return
	end

	local h = math.max(castBar:GetHeight(), 10)
	icon = castBar:CreateTexture(nil, "OVERLAY")
	icon:SetSize(h + 6, h + 6)
	icon:SetPoint("RIGHT", castBar, "LEFT", -5, 0)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:Hide()

	timeText = castBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeText:SetPoint("RIGHT", castBar, "RIGHT", -4, 0)
	timeText:SetJustifyH("RIGHT")

	lagTex = castBar:CreateTexture(nil, "ARTWORK", nil, 7)
	lagTex:SetColorTexture(1, 0.1, 0.1, 0.45)
	lagTex:Hide()

	castBar:HookScript("OnUpdate", castOnUpdate)

	local ev = CreateFrame("Frame")
	for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
		"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
		"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }) do
		ev:RegisterUnitEvent(e, "player")
	end
	ev:SetScript("OnEvent", castRefresh)
end

---------------------------------------------------------------- swing strips
local strips = {}   -- { native = frame, bar = our StatusBar }
local tint = COLOR_SWING
local sinceQueue = 0
local testUntil

local function queuedColor()
	if not queueList then return COLOR_SWING end
	for i = 1, #queueList do
		local ids = queueList[i].ids
		for j = 1, #ids do
			if IsCurrentSpell(ids[j]) then return queueList[i].color end
		end
	end
	return COLOR_SWING
end

local issecret = issecretvalue or function() return false end
local function layoutStrips()
	local anchor, first = castBar, true
	for _, s in ipairs(strips) do
		s.bar:ClearAllPoints()
		s.bar:SetHeight(db.height)
		s.spark:SetHeight(db.height * 2.5)
		if anchor then
			s.bar:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, first and -4 or -2)
			s.bar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, first and -4 or -2)
		else
			s.bar:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
			s.bar:SetWidth(200)
		end
		anchor, first = s.bar, false
	end
end

local failed
local function applyNativeLook()
	for _, s in ipairs(strips) do
		s.native:SetAlpha((db.swing and db.hideNative and not failed) and 0 or 1)
	end
end

-- Forever hands some combat values to addons as "secret" values: they can be passed
-- on to a bar or a text, but not compared or calculated with. So the strip copies the
-- built-in bar's values and its own seconds label as they are, without arithmetic.
local function stripUpdate(s, now)
	local sb = s.native.StatusBar
	if testUntil then
		local f = (now % 2) / 2
		s.bar:SetMinMaxValues(0, 1)
		s.bar:SetValue(f)
		s.text:SetText(db.swingText and string.format("%.1f", 2 - f * 2) or "")
		s.bar:Show()
		return
	end
	if not (db.swing and sb and s.native:IsShown()) then
		s.bar:Hide()
		return
	end
	local mn, mx = sb:GetMinMaxValues()
	if mn == nil or mx == nil then s.bar:Hide() return end
	s.bar:SetMinMaxValues(mn, mx)
	s.bar:SetValue(sb:GetValue())
	local label = db.swingText and sb.TimeLabel and sb.TimeLabel:GetText()
	if label ~= nil and (issecret(label) or label ~= "") then s.text:SetText(label) else s.text:SetText("") end
	s.bar:Show()
end

-- If the strip ever fails, the built-in bars come back, so a swing timer is never lost.
local function safeUpdate(s, now)
	if failed then return end
	local ok, err = pcall(stripUpdate, s, now)
	if not ok then
		failed = true
		for _, x in ipairs(strips) do x.bar:Hide(); x.native:SetAlpha(1) end
		P("swing strip off after an error, the built-in swing timer is shown again. /reload to retry. " .. tostring(err))
	end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, elapsed)
	local now = GetTime()
	if testUntil and now > testUntil then testUntil = nil end
	sinceQueue = sinceQueue + elapsed
	if sinceQueue >= 0.05 then
		sinceQueue = 0
		local c = testUntil and ((now % 4 < 2) and COLOR_QUEUED or COLOR_SWING) or queuedColor()
		if c ~= tint then
			tint = c
			for _, s in ipairs(strips) do s.bar:SetStatusBarColor(c[1], c[2], c[3]) end
		end
	end
	for _, s in ipairs(strips) do safeUpdate(s, now) end
end)

local function makeStrip(native)
	local bar = CreateFrame("StatusBar", nil, UIParent)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(COLOR_SWING[1], COLOR_SWING[2], COLOR_SWING[3])
	bar:SetFrameStrata("MEDIUM")
	bar:Hide()

	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.6)

	local border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 0.9)

	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetSize(10, db.height * 2.5)
	spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("RIGHT", bar, "RIGHT", -2, 0)
	local font, size = text:GetFont()
	if font then text:SetFont(font, math.max(size - 2, 8), "OUTLINE") end

	return { native = native, bar = bar, text = text, spark = spark }
end

local function setupSwing()
	if #strips > 0 then return end
	for _, name in ipairs(SWING_FRAMES) do
		local native = _G[name]
		if native and native.StatusBar then strips[#strips + 1] = makeStrip(native) end
	end
	if #strips == 0 then
		P("built-in swing timer not found. Switch it on: Options > Advanced Options > Swing Timer.")
		return
	end
	layoutStrips()
	applyNativeLook()
end

---------------------------------------------------------------- settings
local TOGGLES = {
	icon = "spell icon",
	time = "cast time",
	latency = "latency zone",
	swing = "swing strip",
	swingText = "swing seconds",
	hideNative = "hide the built-in swing bars",
}
local ORDER = { "icon", "time", "latency", "swing", "swingText", "hideNative" }

SLASH_SWINGCAST1 = "/swc"
SLASH_SWINGCAST2 = "/swingcast"
SlashCmdList.SWINGCAST = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	if TOGGLES[cmd] ~= nil then
		db[cmd] = not db[cmd]
		P(TOGGLES[cmd] .. ": " .. (db[cmd] and "on" or "off"))
		applyNativeLook()
	elseif cmd == "height" and tonumber(arg) then
		db.height = math.min(math.max(math.floor(tonumber(arg)), 2), 20)
		layoutStrips()
		P("swing strip height: " .. db.height)
	elseif cmd == "test" then
		testUntil = GetTime() + 8
		P("8 s preview of the swing strip, the second half tinted as if Maul were queued.")
	elseif cmd == "reset" then
		SwingCastDB = CopyTable(DEFAULTS)
		db = SwingCastDB
		layoutStrips()
		applyNativeLook()
		P("settings reset.")
	else
		P("/swc <setting> switches it on or off:")
		for _, k in ipairs(ORDER) do
			print(string.format("  %s - %s (%s)", k, TOGGLES[k], db[k] and "on" or "off"))
		end
		print("  height <2-20> - swing strip height (" .. db.height .. ")")
		print("  test - 8 s preview of the swing strip")
		print("  reset - default settings")
	end
end

---------------------------------------------------------------- start
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, name)
	if event == "ADDON_LOADED" and name == ADDON then
		SwingCastDB = SwingCastDB or {}
		db = SwingCastDB
		for k, v in pairs(DEFAULTS) do
			if db[k] == nil then db[k] = v end
		end
	elseif event == "ADDON_LOADED" and name == "Blizzard_SwingTimer" then
		if IsLoggedIn() then setupSwing() end
	elseif event == "PLAYER_LOGIN" then
		setupCastBar()
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_SwingTimer")
		if loaded or _G.SwingTimerMainHandFrame then setupSwing() end
	end
end)

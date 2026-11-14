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
	showMinimap = true, -- minimap button
	font = "FRIZQT",    -- font of the cast time and the swing seconds
	fontSize = 10,      -- size of the cast time; the swing seconds are 2 smaller
	attach = true,      -- swing strip under the cast bar; off: its own, movable position
	width = 200,        -- width of the swing strip at its own position
}
local WIDTH_MIN, WIDTH_MAX = 60, 600

-- Colours as { r, g, b }, kept in db.colors and changed in the options window.
local DEFAULT_COLORS = {
	swing = { 0.85, 0.85, 0.85 },   -- swing strip
	queued = { 1.00, 0.55, 0.10 },  -- Maul, Heroic Strike, Raptor Strike queued
	cleave = { 0.25, 0.60, 1.00 },  -- Cleave queued
	latency = { 1.00, 0.10, 0.10 }, -- latency zone on the cast bar
}
local COLOR_LABELS = {
	{ "swing", "Swing strip colour", "Colour of the swing strip." },
	{ "queued", "Queued swing colour", "Colour while Maul, Heroic Strike or Raptor Strike is queued." },
	{ "cleave", "Cleave colour", "Colour while Cleave is queued (warriors)." },
	{ "latency", "Latency zone colour", "Colour of the latency zone at the end of the cast bar." },
}

-- Fonts that ship with every game client.
local FONTS = {
	{ key = "FRIZQT", label = "Friz Quadrata (game default)", path = "Fonts\\FRIZQT__.TTF" },
	{ key = "ARIALN", label = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
	{ key = "MORPHEUS", label = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
	{ key = "SKURRI", label = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

local SWING_FRAMES = { "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }


-- All ranks: an old action button can still hold a low rank, and IsCurrentSpell
-- only reports the exact rank that was queued. First match decides the colour.
local QUEUE = {
	DRUID = { -- Maul
		{ ids = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 }, color = "queued" },
	},
	WARRIOR = { -- Heroic Strike, Cleave
		{ ids = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 }, color = "queued" },
		{ ids = { 845, 7369, 11608, 11609, 20569 }, color = "cleave" },
	},
	HUNTER = { -- Raptor Strike
		{ ids = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 }, color = "queued" },
	},
}

local IsCurrentSpell = (C_Spell and C_Spell.IsCurrentSpell) or IsCurrentSpell
local _, playerClass = UnitClass("player")
local queueList = QUEUE[playerClass]

local db
local castBar -- the standard player cast bar
local applyLook -- font and colours, defined with the swing strips

local function P(msg) print("|cff7fbf3fSwingCast:|r " .. msg) end

local function color(key)
	local c = db and db.colors and db.colors[key] or DEFAULT_COLORS[key]
	return c[1], c[2], c[3]
end

local function fontPath()
	for _, f in ipairs(FONTS) do
		if f.key == db.font then return f.path end
	end
	return FONTS[1].path
end

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

-- Runs every frame while the cast bar is shown: only touch the label when the shown
-- tenth of a second changes.
local shownTenths
local function castOnUpdate()
	local tenths
	if db.time and castEnd then
		local left = castEnd - GetTime()
		if left > 0 then tenths = math.floor(left * 10 + 0.5) end
	end
	if tenths == shownTenths then return end
	shownTenths = tenths
	timeText:SetText(tenths and string.format("%.1f", tenths / 10) or "")
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
	local r, g, b = color("latency")
	lagTex:SetColorTexture(r, g, b, 0.45)
	lagTex:Hide()

	castBar:HookScript("OnUpdate", castOnUpdate)
	applyLook()

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
local tint = "swing"
local sinceQueue = 0
local testUntil

local function queuedColor()
	if not queueList then return "swing" end
	for i = 1, #queueList do
		local ids = queueList[i].ids
		for j = 1, #ids do
			if IsCurrentSpell(ids[j]) then return queueList[i].color end
		end
	end
	return "swing"
end

local issecret = issecretvalue or function() return false end

-- The strip's own position: a frame the player can drag, used when the strip is not
-- attached to the cast bar or the cast bar cannot carry it (see castBarUsable).
local mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
mover:SetMovable(true)
mover:SetClampedToScreen(true)
mover:SetFrameStrata("HIGH")
mover:EnableMouse(false)
mover:RegisterForDrag("LeftButton")
mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
mover:SetBackdropColor(0.25, 0.75, 0.25, 0.35)
mover:SetBackdropBorderColor(0.25, 0.75, 0.25, 1)
local moverLabel = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
moverLabel:SetPoint("BOTTOM", mover, "TOP", 0, 4)
moverLabel:SetText("SwingCast: drag to move, right-click to lock")
local unlocked = false

local function placeMover()
	mover:ClearAllPoints()
	local p = db.pos
	if type(p) == "table" and p[1] then
		mover:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		mover:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
end

-- The cast bar can only carry the strip while it has a place on the screen and is the
-- one that shows casts. Another cast bar or unit frame addon may hide it, take its
-- events away or park it somewhere; then the strip uses its own position.
local castBarOk = false
local function castBarUsable()
	if not castBar or castBar:GetLeft() == nil then return false end
	if castBar.IsEventRegistered and not castBar:IsEventRegistered("UNIT_SPELLCAST_START") then return false end
	return true
end

local function layoutStrips()
	if #strips == 0 then return end
	local n = #strips
	mover:SetSize(db.width, n * db.height + (n - 1) * 2)
	placeMover()
	local onCastBar = db.attach and castBarOk
	local anchor, first = onCastBar and castBar or mover, true
	for _, s in ipairs(strips) do
		s.bar:ClearAllPoints()
		s.bar:SetHeight(db.height)
		s.spark:SetHeight(db.height * 2.5)
		local from = (first and not onCastBar) and "TOP" or "BOTTOM"
		local gap = first and (onCastBar and -4 or 0) or -2
		s.bar:SetPoint("TOPLEFT", anchor, from .. "LEFT", 0, gap)
		s.bar:SetPoint("TOPRIGHT", anchor, from .. "RIGHT", 0, gap)
		anchor, first = s.bar, false
	end
end

local function lock()
	if not unlocked then return end
	unlocked = false
	mover:EnableMouse(false)
	mover:SetBackdropColor(0, 0, 0, 0)
	mover:SetBackdropBorderColor(0, 0, 0, 0)
	moverLabel:Hide()
	testUntil = nil
end

-- Unlocking takes the strip off the cast bar, starting exactly where it is now.
local function unlock()
	if #strips == 0 then
		P("built-in swing timer not found. Switch it on: Options > Advanced Options > Swing Timer.")
		return
	end
	if db.attach then
		local b = strips[1].bar
		if castBarOk and b:GetLeft() then
			db.width = math.min(math.max(math.floor(b:GetWidth() + 0.5), WIDTH_MIN), WIDTH_MAX)
			db.pos = { "TOPLEFT", "BOTTOMLEFT", b:GetLeft(), b:GetTop() }
		end
		db.attach = false
	end
	unlocked = true
	layoutStrips()
	mover:EnableMouse(true)
	mover:SetBackdropColor(0.25, 0.75, 0.25, 0.35)
	mover:SetBackdropBorderColor(0.25, 0.75, 0.25, 1)
	moverLabel:Show()
	testUntil = math.huge
	P("swing strip unlocked: drag it, right-click it or /swc lock to lock.")
end

mover:SetScript("OnDragStart", function(self) self:StartMoving() end)
mover:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	db.pos = { "TOPLEFT", "BOTTOMLEFT", self:GetLeft(), self:GetTop() }
	placeMover()
end)
mover:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" then
		lock()
		P("swing strip locked.")
	end
end)
-- locked at start: the frame stays invisible and lets clicks through
mover:SetBackdropColor(0, 0, 0, 0)
mover:SetBackdropBorderColor(0, 0, 0, 0)
moverLabel:Hide()

local function resetPosition()
	lock()
	db.pos = nil
	db.attach = true
	db.width = DEFAULTS.width
	layoutStrips()
end

-- Checked once a second: the cast bar may get its place late (layouts load after
-- login) or lose it to another addon later on.
local loginTime
local hinted = false
local function checkCastBar()
	local ok = castBarUsable()
	if ok ~= castBarOk then
		castBarOk = ok
		layoutStrips()
	end
	if not ok and db.attach and not hinted and #strips > 0 and loginTime and GetTime() - loginTime > 5 then
		hinted = true
		P("the standard cast bar is hidden or replaced by another addon, so the swing strip uses its own position. /swc unlock to move it.")
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
local barsHidden = false
local sinceCheck = 0
driver:SetScript("OnUpdate", function(_, elapsed)
	if #strips == 0 then return end
	sinceCheck = sinceCheck + elapsed
	if sinceCheck >= 1 then
		sinceCheck = 0
		checkCastBar()
	end
	local now = GetTime()
	if testUntil and now > testUntil then testUntil = nil end
	-- swing strip switched off: hide the bars once, then nothing to do each frame
	if not (db.swing or testUntil) then
		if not barsHidden then
			for i = 1, #strips do strips[i].bar:Hide() end
			barsHidden = true
		end
		return
	end
	barsHidden = false
	sinceQueue = sinceQueue + elapsed
	if sinceQueue >= 0.05 then
		sinceQueue = 0
		local c = testUntil and ((now % 4 < 2) and "queued" or "swing") or queuedColor()
		if c ~= tint then
			tint = c
			local r, g, b = color(c)
			for _, s in ipairs(strips) do s.bar:SetStatusBarColor(r, g, b) end
		end
	end
	for i = 1, #strips do safeUpdate(strips[i], now) end
end)

local function makeStrip(native)
	local bar = CreateFrame("StatusBar", nil, UIParent)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(color("swing"))
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

	return { native = native, bar = bar, text = text, spark = spark }
end

-- Font and colours, applied again whenever a setting changes.
applyLook = function()
	local path = fontPath()
	if timeText then timeText:SetFont(path, db.fontSize, "OUTLINE") end
	if lagTex then
		local r, g, b = color("latency")
		lagTex:SetColorTexture(r, g, b, 0.45)
	end
	local r, g, b = color(tint)
	for _, s in ipairs(strips) do
		s.text:SetFont(path, math.max(db.fontSize - 2, 7), "OUTLINE")
		s.bar:SetStatusBarColor(r, g, b)
	end
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
	castBarOk = castBarUsable()
	layoutStrips()
	applyNativeLook()
	applyLook()
end

---------------------------------------------------------------- options window, minimap button
local category
local LDBIcon

local function openOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category:GetID())
	else
		SlashCmdList.SWINGCAST("")
	end
end

local function applyMinimap()
	if not LDBIcon then return end
	db.minimap = db.minimap or {}
	db.minimap.hide = not db.showMinimap
	if db.showMinimap then LDBIcon:Show(ADDON) else LDBIcon:Hide(ADDON) end
end

local function pickColor(key)
	local r, g, b = color(key)
	local function set(nr, ng, nb)
		db.colors[key] = { nr, ng, nb }
		applyLook()
	end
	local function swatch() set(ColorPickerFrame:GetColorRGB()) end
	local function cancel() set(r, g, b) end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = swatch, cancelFunc = cancel })
	else
		ColorPickerFrame.hasOpacity = false
		ColorPickerFrame.func = swatch
		ColorPickerFrame.cancelFunc = cancel
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Show()
	end
end

local function resetColors()
	db.colors = CopyTable(DEFAULT_COLORS)
	applyLook()
end

local function startTest()
	testUntil = GetTime() + 8
	P("8 s preview of the swing strip, the second half tinted as if Maul were queued.")
end

local function registerSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
	local layout
	category, layout = Settings.RegisterVerticalLayoutCategory(ADDON)
	local function checkbox(key, label, tooltip, onChange)
		local setting = Settings.RegisterAddOnSetting(category, "SWINGCAST_" .. key:upper(), key, db,
			Settings.VarType.Boolean, label, DEFAULTS[key])
		Settings.CreateCheckbox(category, setting, tooltip)
		if onChange then setting:SetValueChangedCallback(onChange) end
	end
	checkbox("icon", "Spell icon", "Show the spell icon left of the cast bar.")
	checkbox("time", "Cast time", "Show the remaining cast time on the cast bar.")
	checkbox("latency", "Latency zone", "Red zone at the end of the cast bar: once the bar reaches it, the next spell can be pressed.")
	checkbox("swing", "Swing strip", "Swing timer as a thin strip under the cast bar.", applyNativeLook)
	checkbox("swingText", "Swing seconds", "Seconds to the next swing on the strip.")
	checkbox("hideNative", "Hide the built-in swing bars", "Hide the look of Forever's own swing timer bars while the strip is on.", applyNativeLook)
	checkbox("showMinimap", "Minimap button", "Show the SwingCast button at the minimap.", applyMinimap)

	local height = Settings.RegisterAddOnSetting(category, "SWINGCAST_HEIGHT", "height", db,
		Settings.VarType.Number, "Swing strip height", DEFAULTS.height)
	local opts = Settings.CreateSliderOptions(2, 20, 1)
	if MinimalSliderWithSteppersMixin and opts.SetLabelFormatter then
		opts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, height, opts, "Height of the swing strip in pixels.")
	height:SetValueChangedCallback(function() layoutStrips() end)

	-- Position: under the cast bar, or a place of its own that the player drags.
	checkbox("attach", "Attach to cast bar", "Swing strip right under the cast bar. Off: the strip has its own position, set with \"Move swing strip\".",
		function() lock(); layoutStrips() end)
	local width = Settings.RegisterAddOnSetting(category, "SWINGCAST_WIDTH", "width", db,
		Settings.VarType.Number, "Swing strip width", DEFAULTS.width)
	local widthOpts = Settings.CreateSliderOptions(WIDTH_MIN, WIDTH_MAX, 5)
	if MinimalSliderWithSteppersMixin and widthOpts.SetLabelFormatter then
		widthOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, width, widthOpts, "Width of the swing strip at its own position. Under the cast bar it takes the cast bar's width.")
	width:SetValueChangedCallback(function() layoutStrips() end)
	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("Move swing strip", "Unlock", function()
			if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			unlock()
		end, "Takes the strip off the cast bar so you can drag it anywhere. Right-click it to lock.", true))
		layout:AddInitializer(CreateSettingsButtonInitializer("Default position", "Reset", resetPosition,
			"Put the strip back under the cast bar.", true))
	end

	-- Font: a dropdown of the fonts every client has, and the size.
	local dropdown = Settings.CreateDropdown or Settings.CreateDropDown
	if dropdown and Settings.CreateControlTextContainer then
		local font = Settings.RegisterAddOnSetting(category, "SWINGCAST_FONT", "font", db,
			Settings.VarType.String, "Font", DEFAULTS.font)
		dropdown(category, font, function()
			local c = Settings.CreateControlTextContainer()
			for _, f in ipairs(FONTS) do c:Add(f.key, f.label) end
			return c:GetData()
		end, "Font of the cast time and the swing seconds.")
		font:SetValueChangedCallback(function() applyLook() end)
	end
	local size = Settings.RegisterAddOnSetting(category, "SWINGCAST_FONTSIZE", "fontSize", db,
		Settings.VarType.Number, "Font size", DEFAULTS.fontSize)
	local sizeOpts = Settings.CreateSliderOptions(7, 20, 1)
	if MinimalSliderWithSteppersMixin and sizeOpts.SetLabelFormatter then
		sizeOpts:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
	end
	Settings.CreateSlider(category, size, sizeOpts, "Size of the cast time. The swing seconds are 2 smaller.")
	size:SetValueChangedCallback(function() applyLook() end)

	-- Colours: a button each that opens the game's colour picker.
	if layout and CreateSettingsButtonInitializer then
		for _, c in ipairs(COLOR_LABELS) do
			local key = c[1]
			layout:AddInitializer(CreateSettingsButtonInitializer(c[2], "Choose", function() pickColor(key) end, c[3], true))
		end
		layout:AddInitializer(CreateSettingsButtonInitializer("Default colours", "Reset", resetColors,
			"Set all colours back to the defaults.", true))
	end

	Settings.RegisterAddOnCategory(category)
end

local function registerMinimap()
	local LibStub = _G.LibStub
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if not (LDB and LDBIcon) then return end
	local obj = LDB:NewDataObject(ADDON, {
		type = "launcher",
		text = ADDON,
		icon = "Interface\\AddOns\\SwingCast\\Icons\\minimap",
		OnClick = function(_, button)
			if button == "RightButton" then startTest() else openOptions() end
		end,
		OnTooltipShow = function(tt)
			tt:AddLine(ADDON)
			tt:AddLine("|cffffffffLeft-click:|r options", 0.8, 0.8, 0.8)
			tt:AddLine("|cffffffffRight-click:|r swing strip preview", 0.8, 0.8, 0.8)
		end,
	})
	db.minimap = db.minimap or {}
	db.minimap.hide = not db.showMinimap
	LDBIcon:Register(ADDON, obj, db.minimap)
end

-- Entry in the game's addon menu (the button next to the minimap).
function SwingCast_OnCompartmentClick(_, button)
	if button == "RightButton" then startTest() else openOptions() end
end

---------------------------------------------------------------- settings
local TOGGLES = {
	icon = "spell icon",
	time = "cast time",
	latency = "latency zone",
	swing = "swing strip",
	swingText = "swing seconds",
	hideNative = "hide the built-in swing bars",
	attach = "swing strip attached to the cast bar",
}
local ORDER = { "icon", "time", "latency", "swing", "swingText", "hideNative", "attach" }
local KEY = {} -- lower-case command -> setting key, so /swc swingtext works too
for _, k in ipairs(ORDER) do KEY[k:lower()] = k end

SLASH_SWINGCAST1 = "/swc"
SLASH_SWINGCAST2 = "/swingcast"
SlashCmdList.SWINGCAST = function(msg)
	local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
	local num = tonumber(arg)
	local key = KEY[cmd or ""]
	if key then
		db[key] = not db[key]
		P(TOGGLES[key] .. ": " .. (db[key] and "on" or "off"))
		applyNativeLook()
		if key == "attach" then lock(); layoutStrips() end
	elseif cmd == "unlock" or cmd == "move" then
		unlock()
	elseif cmd == "lock" then
		lock()
		P("swing strip locked.")
	elseif cmd == "width" and num then
		db.width = math.min(math.max(math.floor(num), WIDTH_MIN), WIDTH_MAX)
		layoutStrips()
		P("swing strip width: " .. db.width .. (db.attach and " (used once the strip has its own position)" or ""))
	elseif cmd == "position" and arg == "reset" then
		resetPosition()
		P("swing strip back under the cast bar.")
	elseif cmd == "height" and num then
		db.height = math.min(math.max(math.floor(num), 2), 20)
		layoutStrips()
		P("swing strip height: " .. db.height)
	elseif cmd == "test" then
		startTest()
	elseif cmd == "color" or cmd == "colour" then
		if arg == "reset" then
			resetColors()
			P("colours reset.")
		elseif arg and DEFAULT_COLORS[arg] then
			pickColor(arg)
		else
			P("/swc color swing|queued|cleave|latency|reset")
		end
	elseif cmd == "font" and num then
		db.fontSize = math.min(math.max(math.floor(num), 7), 20)
		applyLook()
		P("font size: " .. db.fontSize)
	elseif cmd == "options" or cmd == "config" then
		openOptions()
	elseif cmd == "minimap" then
		db.showMinimap = not db.showMinimap
		applyMinimap()
		P("minimap button: " .. (db.showMinimap and "on" or "off"))
	elseif cmd == "reset" then
		lock()
		for k, v in pairs(DEFAULTS) do db[k] = v end
		db.pos = nil
		db.colors = CopyTable(DEFAULT_COLORS)
		applyLook()
		layoutStrips()
		applyNativeLook()
		applyMinimap()
		P("settings reset.")
	else
		P("/swc <setting> switches it on or off:")
		for _, k in ipairs(ORDER) do
			print(string.format("  %s - %s (%s)", k, TOGGLES[k], db[k] and "on" or "off"))
		end
		print("  height <2-20> - swing strip height (" .. db.height .. ")")
		print("  unlock - drag the swing strip anywhere, lock - fix it again")
		print("  width <" .. WIDTH_MIN .. "-" .. WIDTH_MAX .. "> - swing strip width at its own position (" .. db.width .. ")")
		print("  position reset - swing strip back under the cast bar")
		print("  test - 8 s preview of the swing strip")
		print("  color swing|queued|cleave|latency - pick a colour, color reset - default colours")
		print("  font <7-20> - font size")
		print("  options - settings window")
		print("  minimap - minimap button on or off")
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
		db.colors = db.colors or {}
		for k, v in pairs(DEFAULT_COLORS) do
			if type(db.colors[k]) ~= "table" then db.colors[k] = CopyTable(v) end
		end
		registerSettings()
		registerMinimap()
	elseif event == "ADDON_LOADED" and name == "Blizzard_SwingTimer" then
		if IsLoggedIn() then setupSwing() end
	elseif event == "PLAYER_LOGIN" then
		loginTime = GetTime()
		setupCastBar()
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_SwingTimer")
		if loaded or SwingTimerMainHandFrame then setupSwing() end
	end
end)

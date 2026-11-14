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
-- It is shown and draggable while unlocked (/swc unlock, options window) and while the
-- game's Edit Mode is open.
local mover = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
mover:SetMovable(true)
mover:SetClampedToScreen(true)
mover:SetFrameStrata("HIGH")
mover:EnableMouse(false)
mover:RegisterForDrag("LeftButton")
mover:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
local moverLabel = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
moverLabel:SetPoint("BOTTOM", mover, "TOP", 0, 4)
local unlocked -- nil, "manual" or "editmode"
local optionsShown = false -- the options window is open: the strip shows a preview

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
	local onCastBar = db.attach and castBarOk
	local anchor, first = onCastBar and castBar or mover, true
	if not onCastBar then
		mover:SetSize(db.width, n * db.height + (n - 1) * 2)
		placeMover()
	end
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
	-- attached: the (unlocked) frame lies over the strip, so Edit Mode can show and grab it
	if onCastBar then
		mover:ClearAllPoints()
		mover:SetPoint("TOPLEFT", strips[1].bar, "TOPLEFT")
		mover:SetPoint("BOTTOMRIGHT", strips[n].bar, "BOTTOMRIGHT")
	end
end

-- The preview runs while the strip is unlocked or the options window is open.
local function updatePreview()
	testUntil = (unlocked or optionsShown) and math.huge or nil
end

local refreshOptions = function() end -- set by the options window

-- Takes the strip off the cast bar, starting exactly where it is now.
local function detach()
	if not db.attach then return end
	local b = strips[1] and strips[1].bar
	if castBarOk and b and b:GetLeft() then
		db.width = math.min(math.max(math.floor(b:GetWidth() + 0.5), WIDTH_MIN), WIDTH_MAX)
		db.pos = { "TOPLEFT", "BOTTOMLEFT", b:GetLeft(), b:GetTop() }
	end
	db.attach = false
	layoutStrips()
	refreshOptions()
end

local function lock()
	if not unlocked then return end
	unlocked = nil
	mover:EnableMouse(false)
	mover:SetBackdropColor(0, 0, 0, 0)
	mover:SetBackdropBorderColor(0, 0, 0, 0)
	moverLabel:Hide()
	updatePreview()
	refreshOptions()
end

-- how: "manual" (/swc unlock, options window) takes the strip off the cast bar at once;
-- "editmode" leaves it attached until it is actually dragged, like the game's own frames.
local function unlock(how)
	if #strips == 0 then
		if how ~= "editmode" then
			P("built-in swing timer not found. Switch it on: Options > Advanced Options > Swing Timer.")
		end
		return
	end
	if how == "manual" then detach() end
	unlocked = how
	layoutStrips()
	mover:EnableMouse(true)
	if how == "editmode" then
		-- the look of Edit Mode's own frames: blue, with the name
		mover:SetBackdropColor(0.25, 0.55, 1, 0.3)
		mover:SetBackdropBorderColor(0.35, 0.65, 1, 1)
		moverLabel:SetText("SwingCast")
	else
		mover:SetBackdropColor(0.25, 0.75, 0.25, 0.35)
		mover:SetBackdropBorderColor(0.25, 0.75, 0.25, 1)
		moverLabel:SetText("SwingCast: drag to move, right-click to lock")
		P("swing strip unlocked: drag it, right-click it or /swc lock to lock.")
	end
	moverLabel:Show()
	updatePreview()
	refreshOptions()
end

mover:SetScript("OnDragStart", function(self)
	detach()
	self:StartMoving()
end)
mover:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	db.pos = { "TOPLEFT", "BOTTOMLEFT", self:GetLeft(), self:GetTop() }
	placeMover()
end)
mover:SetScript("OnMouseUp", function(_, button)
	if button == "RightButton" and unlocked == "manual" then
		lock()
		P("swing strip locked.")
	end
end)
-- locked at start: the frame stays invisible and lets clicks through
mover:SetBackdropColor(0, 0, 0, 0)
mover:SetBackdropBorderColor(0, 0, 0, 0)
moverLabel:Hide()

local function resetPosition()
	db.pos = nil
	db.attach = true
	db.width = DEFAULTS.width
	layoutStrips()
	refreshOptions()
end

-- The game's Edit Mode: the strip shows up there and can be dragged like the game's frames.
local function hookEditMode()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", function() unlock("editmode") end, mover)
		EventRegistry:RegisterCallback("EditMode.Exit", function() if unlocked == "editmode" then lock() end end, mover)
	elseif EditModeManagerFrame then
		hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function() unlock("editmode") end)
		hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function() if unlocked == "editmode" then lock() end end)
	end
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
		P("the standard cast bar is hidden or replaced by another addon, so the swing strip uses its own position. /swc unlock or Edit Mode to move it.")
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
local LDBIcon

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
		refreshOptions()
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
	refreshOptions()
end

local function startTest()
	testUntil = GetTime() + 8
	P("8 s preview of the swing strip, the second half tinted as if Maul were queued.")
end

-- Changing a switch: store it and redraw what depends on it.
local function setToggle(key, value)
	db[key] = value
	if key == "swing" or key == "hideNative" then applyNativeLook()
	elseif key == "attach" then layoutStrips()
	elseif key == "showMinimap" then applyMinimap()
	end
	refreshOptions()
end

-- Own window instead of a page in the game's options: it can be dragged anywhere and
-- stays open while you play, so every change shows live on the cast bar and the strip.
local win
local widgets = {}

local function tooltip(frame, title, text)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(title, 1, 1, 1)
		if text then GameTooltip:AddLine(text, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function header(parent, x, y, text)
	local h = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h:SetPoint("TOPLEFT", x, y)
	h:SetText(text)
end

local function checkbox(parent, x, y, key, label, tip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", x, y)
	local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
	t:SetText(label)
	cb:SetHitRectInsets(0, -(t:GetStringWidth() + 4), 0, 0)
	cb:SetScript("OnClick", function(self) setToggle(key, self:GetChecked() and true or false) end)
	tooltip(cb, label, tip)
	widgets[#widgets + 1] = function() cb:SetChecked(db[key] and true or false) end
end

local function slider(parent, x, y, key, label, minV, maxV, step, onChange, tip)
	local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", x, y)
	title:SetText(label)
	local s = CreateFrame("Slider", nil, parent, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(170, 12)
	s:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	s:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	s:SetBackdropColor(0, 0, 0, 0.6)
	s:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	local val = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	val:SetPoint("LEFT", s, "RIGHT", 8, 0)
	local syncing = false
	s:SetScript("OnValueChanged", function(_, v)
		v = math.floor(v / step + 0.5) * step
		val:SetText(v)
		if syncing or v == db[key] then return end
		db[key] = v
		onChange()
	end)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(math.min(math.max(self:GetValue() + delta * step, minV), maxV))
	end)
	tooltip(s, label, tip)
	widgets[#widgets + 1] = function()
		syncing = true
		s:SetValue(db[key])
		val:SetText(db[key])
		syncing = false
	end
end

local function makeButton(parent, text, width, onClick, tip)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	if tip then tooltip(b, text, tip) end
	return b
end

local function fontLabel()
	for _, f in ipairs(FONTS) do
		if f.key == db.font then return f.label end
	end
	return FONTS[1].label
end

local function buildWindow()
	win = CreateFrame("Frame", "SwingCastOptionsFrame", UIParent, "BackdropTemplate")
	win:SetSize(500, 470)
	win:SetFrameStrata("DIALOG")
	win:SetToplevel(true)
	win:SetClampedToScreen(true)
	win:SetMovable(true)
	win:EnableMouse(true)
	win:RegisterForDrag("LeftButton")
	win:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	win:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
	win:SetScript("OnDragStart", win.StartMoving)
	win:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		db.optPos = { "TOPLEFT", "BOTTOMLEFT", self:GetLeft(), self:GetTop() }
	end)
	local p = db.optPos
	if type(p) == "table" and p[1] then
		win:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
	-- Escape closes it like the game's windows
	tinsert(UISpecialFrames, "SwingCastOptionsFrame")

	local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -14)
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	title:SetText(ADDON .. ((version and not version:find("@")) and ("  |cff999999" .. version .. "|r") or ""))
	local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("TOPRIGHT", -36, -18)
	hint:SetText("drag to move, changes apply live")
	local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	-- left column: switches
	local L = 16
	header(win, L, -46, "Cast bar")
	checkbox(win, L, -64, "icon", "Spell icon", "Show the spell icon left of the cast bar.")
	checkbox(win, L, -88, "time", "Cast time", "Show the remaining cast time on the cast bar.")
	checkbox(win, L, -112, "latency", "Latency zone", "Zone at the end of the cast bar: once the bar reaches it, the next spell can be pressed.")
	header(win, L, -146, "Swing strip")
	checkbox(win, L, -164, "swing", "Swing strip", "Swing timer as a thin strip under the cast bar.")
	checkbox(win, L, -188, "swingText", "Swing seconds", "Seconds to the next swing on the strip.")
	checkbox(win, L, -212, "hideNative", "Hide built-in swing bars", "Hide the look of Forever's own swing timer bars while the strip is on.")
	checkbox(win, L, -236, "attach", "Attach to cast bar", "Strip right under the cast bar. Off: its own position, set by dragging it (Move, or the game's Edit Mode).")
	header(win, L, -270, "General")
	checkbox(win, L, -288, "showMinimap", "Minimap button", "Show the SwingCast button at the minimap.")

	-- right column: sizes, font, colours
	local R = 262
	header(win, R, -46, "Size and font")
	slider(win, R, -68, "height", "Strip height", 2, 20, 1, layoutStrips, "Height of the swing strip in pixels.")
	slider(win, R, -106, "width", "Strip width (own position)", WIDTH_MIN, WIDTH_MAX, 5, layoutStrips,
		"Width of the strip at its own position. Under the cast bar it takes the cast bar's width.")
	slider(win, R, -144, "fontSize", "Font size", 7, 20, 1, applyLook, "Size of the cast time. The swing seconds are 2 smaller.")
	local fontBtn = makeButton(win, "", 200, function()
		local i = 1
		for n, f in ipairs(FONTS) do if f.key == db.font then i = n end end
		db.font = FONTS[i % #FONTS + 1].key
		applyLook()
		refreshOptions()
	end, "Click to switch the font of the cast time and the swing seconds.")
	fontBtn:SetPoint("TOPLEFT", R, -184)
	widgets[#widgets + 1] = function() fontBtn:SetText("Font: " .. fontLabel()) end

	header(win, R, -222, "Colours")
	for i, c in ipairs(COLOR_LABELS) do
		local key = c[1]
		local sw = CreateFrame("Button", nil, win, "BackdropTemplate")
		sw:SetSize(18, 18)
		sw:SetPoint("TOPLEFT", R, -240 - (i - 1) * 24)
		sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		sw:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
		sw:SetScript("OnClick", function() pickColor(key) end)
		tooltip(sw, c[2], c[3] .. " Click to choose.")
		local t = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("LEFT", sw, "RIGHT", 8, 0)
		t:SetText(c[2])
		widgets[#widgets + 1] = function() sw:SetBackdropColor(color(key)) end
	end
	makeButton(win, "Default colours", 140, resetColors, "Set all colours back to the defaults."):SetPoint("TOPLEFT", R, -342)

	-- bottom row: position
	header(win, L, -378, "Position")
	local move = makeButton(win, "Move strip", 110, function()
		if unlocked then lock() else unlock("manual") end
	end, "Takes the strip off the cast bar so you can drag it anywhere. Click again or right-click the strip to lock. The game's Edit Mode moves it too.")
	move:SetPoint("TOPLEFT", L, -398)
	widgets[#widgets + 1] = function() move:SetText(unlocked == "manual" and "Lock strip" or "Move strip") end
	makeButton(win, "Default position", 130, resetPosition, "Put the strip back under the cast bar."):SetPoint("LEFT", move, "RIGHT", 8, 0)
	makeButton(win, "Reset all", 100, function() SlashCmdList.SWINGCAST("reset") end, "All settings back to the defaults.")
		:SetPoint("TOPRIGHT", -16, -398)
	local note = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	note:SetPoint("BOTTOMLEFT", 16, 14)
	note:SetPoint("BOTTOMRIGHT", -16, 14)
	note:SetJustifyH("LEFT")
	note:SetText("While this window is open the swing strip shows a preview. Needs the built-in swing timer: Options > Advanced Options > Swing Timer.")

	refreshOptions = function()
		if not (win and win:IsShown()) then return end
		for _, w in ipairs(widgets) do w() end
	end
	win:SetScript("OnShow", function()
		optionsShown = true
		updatePreview()
		refreshOptions()
	end)
	win:SetScript("OnHide", function()
		optionsShown = false
		updatePreview()
	end)
	win:Hide()
end

local function openOptions()
	if not win then buildWindow() end
	win:SetShown(not win:IsShown())
end

-- The game's options only point to the window, so the addon is still found there.
local function registerSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON)
	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("SwingCast has its own window", "Open", function()
			if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			if not win then buildWindow() end
			win:Show()
		end, "Opens the SwingCast window. It can be dragged anywhere and stays open while you play.", true))
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
		setToggle(key, not db[key])
		P(TOGGLES[key] .. ": " .. (db[key] and "on" or "off"))
	elseif cmd == nil or cmd == "" or cmd == "options" or cmd == "config" then
		openOptions()
	elseif cmd == "unlock" or cmd == "move" then
		unlock("manual")
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
	elseif cmd == "minimap" then
		setToggle("showMinimap", not db.showMinimap)
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
		P("/swc opens the window. /swc <setting> switches it on or off:")
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
		print("  options - SwingCast window (same as /swc)")
		print("  minimap - minimap button on or off")
		print("  reset - default settings")
	end
	refreshOptions()
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
		hookEditMode()
		local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_SwingTimer")
		if loaded or SwingTimerMainHandFrame then setupSwing() end
	end
end)

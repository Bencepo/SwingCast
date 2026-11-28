-- SwingCast
-- Copyright (c) 2026 Bencepo. All rights reserved.
--
-- Adds to the standard player cast bar instead of replacing it:
--   * spell icon inside the bar (or left of it)
--   * remaining cast time on the bar
--   * latency zone at the end of the bar (red: what the server still needs)
--   * the swing timer as a thin strip right under the bar
-- The swing strip runs on the game's PLAYER_SWING event: Forever reports each of your
-- swings (main hand, off hand, ranged) with its duration and without secrecy, so the
-- strip needs neither the combat log nor the built-in swing timer. It is tinted while an
-- on-next-swing ability (Maul, Heroic Strike, Cleave, Raptor Strike) is queued.
-- If the built-in swing timer is switched on, its bars can be hidden (hideNative).
--
-- /swc  opens the options window (/swc help lists the settings).

local ADDON = ...
local pairs, ipairs, type, tonumber = pairs, ipairs, type, tonumber
local floor, max, min, huge = math.floor, math.max, math.min, math.huge
local format = string.format
local GetTime = GetTime
local WHITE = "Interface\\Buttons\\WHITE8x8"
local SWING_NOT_FOUND = "swing strip not ready yet, try again in a moment."

local function clampInt(v, lo, hi)
	return min(max(floor(v), lo), hi)
end

local DEFAULTS = {
	icon = true,       -- spell icon on the cast bar
	iconInside = true, -- icon inside the bar; off: left of it (needs room there)
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

-- A full strip stays this long after its swing is due, so it does not flicker while
-- the next swing's event is on its way, and hides when auto attack stops.
local SWING_GRACE = 0.4
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
local issecret = issecretvalue or function() return false end
local _, playerClass = UnitClass("player")
local queueList = QUEUE[playerClass]

local db
local castBar -- the standard player cast bar
local applyLook -- font and colours, defined with the swing strips
local applyIcon -- icon size and place, defined with the cast bar
local syncDriver -- defined with the swing driver

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
local shownTenths

local function castInfo()
	local name, _, tex, startMS, endMS = UnitCastingInfo("player")
	if name then return tex, startMS, endMS, false end
	name, _, tex, startMS, endMS = UnitChannelInfo("player")
	if name then return tex, startMS, endMS, true end
end

local editModeOpen = false
local lagChannel

local function castRefresh()
	local tex, startMS, endMS, channel = castInfo()
	if not tex then
		castEnd = nil
		shownTenths = nil
		if timeText then timeText:SetText("") end
		lagTex:Hide()
		-- the icon goes with the cast; Edit Mode keeps its placeholder
		if editModeOpen then icon:SetTexture(134400) else icon:Hide() end
		return
	end
	local hasTimes = startMS ~= nil and endMS ~= nil and not (issecret(startMS) or issecret(endMS))
	castEnd = hasTimes and (endMS / 1000) or nil

	icon:SetTexture(tex)
	icon:SetShown(db.icon)

	local dur = hasTimes and ((endMS - startMS) / 1000) or 0
	local _, _, home, world = GetNetStats()
	local lag = max(home or 0, world or 0) / 1000
	if db.latency and dur > 0 and lag > 0 then
		local w = castBar:GetWidth() * min(lag / dur, 1)
		if lagChannel ~= channel then
			lagTex:ClearAllPoints()
			if channel then
				lagTex:SetPoint("TOPLEFT", castBar, "TOPLEFT")
				lagTex:SetPoint("BOTTOMLEFT", castBar, "BOTTOMLEFT")
			else
				lagTex:SetPoint("TOPRIGHT", castBar, "TOPRIGHT")
				lagTex:SetPoint("BOTTOMRIGHT", castBar, "BOTTOMRIGHT")
			end
			lagChannel = channel
		end
		lagTex:SetWidth(max(w, 1))
		lagTex:Show()
	else
		lagTex:Hide()
	end
end

-- Runs every frame while the cast bar is shown: only touch the label when the shown
-- tenth of a second changes.
local function castOnUpdate()
	local tenths
	if db.time and castEnd then
		local left = castEnd - GetTime()
		if left > 0 then tenths = floor(left * 10 + 0.5) end
	end
	if tenths == shownTenths then return end
	shownTenths = tenths
	timeText:SetText(tenths and format("%.1f", tenths / 10) or "")
end

-- Edit Mode's box around the cast bar: widened to the left while the icon sits
-- outside the bar, so the room the icon needs is visible while placing the bar.
local selPoints
local pendingSelection = false
local function applySelection()
	local sel = castBar and castBar.Selection
	if not sel then return end
	if InCombatLockdown() then
		pendingSelection = true
		return
	end
	pendingSelection = false
	if not selPoints then
		local pts = {}
		for i = 1, sel:GetNumPoints() do pts[i] = { sel:GetPoint(i) } end
		if #pts == 0 then return end
		selPoints = pts
	end
	local extra = 0
	if db.icon and not db.iconInside then extra = icon:GetWidth() + 5 end
	sel:ClearAllPoints()
	for _, pt in ipairs(selPoints) do
		local x = pt[4] or 0
		if pt[1]:find("LEFT") then x = x - extra end
		sel:SetPoint(pt[1], pt[2], pt[3], x, pt[5] or 0)
	end
end

applyIcon = function()
	if not icon then return end
	local h = max(castBar:GetHeight(), 10)
	icon:ClearAllPoints()
	if db.iconInside then
		icon:SetSize(h, h)
		icon:SetPoint("LEFT", castBar, "LEFT", 0, 0)
	else
		icon:SetSize(h + 6, h + 6)
		icon:SetPoint("RIGHT", castBar, "LEFT", -5, 0)
	end
	-- in Edit Mode the bar shows without a cast: show a placeholder icon there
	if editModeOpen and not castEnd then
		icon:SetTexture(134400)
		icon:SetShown(db.icon)
	elseif not castEnd then
		icon:Hide()
	else
		icon:SetShown(db.icon)
	end
	applySelection()
end

local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
}

local function setupCastBar()
	castBar = PlayerCastingBarFrame or CastingBarFrame
	if not castBar then
		P("standard cast bar not found, cast bar parts are off.")
		return
	end

	icon = castBar:CreateTexture(nil, "OVERLAY", nil, 7)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	icon:Hide()
	applyIcon()

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
	for _, e in ipairs(CAST_EVENTS) do
		ev:RegisterUnitEvent(e, "player")
	end
	ev:RegisterEvent("PLAYER_REGEN_ENABLED")
	ev:SetScript("OnEvent", function(_, event)
		if event == "PLAYER_REGEN_ENABLED" then
			if pendingSelection then applySelection() end
			return
		end
		if event == "UNIT_SPELLCAST_FAILED" and (UnitCastingInfo("player") or UnitChannelInfo("player")) then
			return
		end
		castRefresh()
	end)
end

---------------------------------------------------------------- swing strips
local strips = {}   -- { native = frame, bar = our StatusBar, isMainHand = bool }

-- Current swing speed of a hand (1 main, 2 off, 3 ranged). The game already counts
-- in Cat Form, Bear Form, haste buffs and slows; nil when that hand has no weapon.
-- Off hand counts only with a weapon in it: a shield or held-in-off-hand item never swings.
local offHandWeapon
local function hasOffHandWeapon()
	if offHandWeapon == nil then
		local id = GetInventoryItemID("player", 17)
		local classID = id and select(6, C_Item.GetItemInfoInstant(id))
		offHandWeapon = classID == 2 -- Enum.ItemClass.Weapon
	end
	return offHandWeapon
end

local function speedFor(i)
	local v
	if i == 2 and not hasOffHandWeapon() then return nil end
	if i == 3 then
		v = UnitRangedDamage("player")
	else
		local mh, oh = UnitAttackSpeed("player")
		v = (i == 2) and oh or mh
	end
	if issecret(v) or type(v) ~= "number" or v <= 0 then return nil end
	return v
end
local tint = "swing"
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

local function applyBarColors()
	local sr, sg, sb = color("swing")
	local tr, tg, tb = color(tint)
	for i = 1, #strips do
		local s = strips[i]
		-- Queued abilities (Maul, Heroic Strike, Cleave, Raptor Strike) only affect the Main-Hand swing.
		if s.isMainHand or testUntil then
			s.bar:SetStatusBarColor(tr, tg, tb)
		else
			s.bar:SetStatusBarColor(sr, sg, sb)
		end
	end
end

local function refreshTint(newTint)
	if newTint ~= tint then
		tint = newTint
		applyBarColors()
	end
end

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
mover:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
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
	local onCastBar = db.attach and castBarOk
	local showAll = testUntil ~= nil or unlocked ~= nil
	local activeCount = 0
	if not showAll then
		for i = 1, #strips do
			if strips[i].visible then activeCount = activeCount + 1 end
		end
	end
	local stackAll = showAll or activeCount == 0
	local count = stackAll and #strips or activeCount

	if not onCastBar then
		mover:SetSize(db.width, count * db.height + (count - 1) * 2)
		placeMover()
	end
	local anchor, first = onCastBar and castBar or mover, true
	local firstBar, lastBar
	for i = 1, #strips do
		local s = strips[i]
		s.bar:SetHeight(db.height)
		s.spark:SetHeight(db.height * 2.5)
		if stackAll or s.visible then
			s.bar:ClearAllPoints()
			local from = (first and not onCastBar) and "TOP" or "BOTTOM"
			local gap = first and (onCastBar and -4 or 0) or -2
			s.bar:SetPoint("TOPLEFT", anchor, from .. "LEFT", 0, gap)
			s.bar:SetPoint("TOPRIGHT", anchor, from .. "RIGHT", 0, gap)
			anchor, first = s.bar, false
			if not firstBar then firstBar = s.bar end
			lastBar = s.bar
		end
	end
	-- attached: the (unlocked) frame lies over the strip, so Edit Mode can show and grab it
	if onCastBar and firstBar and lastBar then
		mover:ClearAllPoints()
		mover:SetPoint("TOPLEFT", firstBar, "TOPLEFT")
		mover:SetPoint("BOTTOMRIGHT", lastBar, "BOTTOMRIGHT")
	end
end

local function endPreviewState()
	for i = 1, #strips do
		strips[i].previewInit = false
		strips[i].previewTenths = nil
	end
	tint = queuedColor()
	applyBarColors()
	layoutStrips()
end

-- The preview runs while the strip is unlocked or the options window is open.
local function updatePreview()
	local wasPreview = testUntil ~= nil
	testUntil = (unlocked or optionsShown) and huge or nil
	if wasPreview and not testUntil then
		endPreviewState()
	elseif testUntil and not wasPreview then
		layoutStrips()
	end
	if syncDriver then syncDriver() end
end

local refreshOptions = function() end -- set by the options window

-- Takes the strip off the cast bar, starting exactly where it is now.
local function detach()
	if not db.attach then return end
	local b = strips[1] and strips[1].bar
	if castBarOk and b and b:GetLeft() then
		db.width = clampInt(b:GetWidth() + 0.5, WIDTH_MIN, WIDTH_MAX)
		db.pos = { "TOPLEFT", "BOTTOMLEFT", b:GetLeft(), b:GetTop() }
	end
	db.attach = false
	layoutStrips()
	refreshOptions()
end

local function lock()
	if not unlocked then return false end
	unlocked = nil
	mover:EnableMouse(false)
	mover:SetBackdropColor(0, 0, 0, 0)
	mover:SetBackdropBorderColor(0, 0, 0, 0)
	moverLabel:Hide()
	updatePreview()
	refreshOptions()
	return true
end

-- how: "manual" (/swc unlock, options window) takes the strip off the cast bar at once;
-- "editmode" leaves it attached until it is actually dragged, like the game's own frames.
local function unlock(how)
	if #strips == 0 then
		if how ~= "editmode" then
			P(SWING_NOT_FOUND)
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

-- Checked on login, world transitions, Edit Mode exit, and attach changes: the cast bar
-- may get its place late (layouts load after login) or lose it to another addon.
local loginTime
local hinted = false
local function checkCastBar()
	if not (db and db.attach) then return end
	local ok = castBarUsable()
	if ok ~= castBarOk then
		castBarOk = ok
		layoutStrips()
	end
	if not ok and not hinted and #strips > 0 and loginTime and GetTime() - loginTime > 5 then
		hinted = true
		P("the standard cast bar is hidden or replaced by another addon, so the swing strip uses its own position. /swc unlock or Edit Mode to move it.")
	end
end

local function onEditModeEnter()
	editModeOpen = true
	applyIcon()
	unlock("editmode")
end

local function onEditModeExit()
	editModeOpen = false
	applyIcon()
	if unlocked == "editmode" then lock() end
	checkCastBar()
end

-- The game's Edit Mode: the strip shows up there and can be dragged like the game's frames.
local function hookEditMode()
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Enter", onEditModeEnter, mover)
		EventRegistry:RegisterCallback("EditMode.Exit", onEditModeExit, mover)
	elseif EditModeManagerFrame then
		hooksecurefunc(EditModeManagerFrame, "EnterEditMode", onEditModeEnter)
		hooksecurefunc(EditModeManagerFrame, "ExitEditMode", onEditModeExit)
	end
end

local failed
local settingAlpha = false
local function nativeAlpha()
	return (db and db.swing and db.hideNative and not failed) and 0 or 1
end
-- Hides only the built-in bar's contents. The frame's own alpha stays untouched:
-- the game reads it for its fading and hides the bar for good when it finds 0.
local function setNativeLook(native, a)
	if not native then return end
	settingAlpha = true
	if native:GetAlpha() == 0 then native:SetAlpha(1) end -- undo the old way of hiding
	for _, r in ipairs({ native:GetRegions() }) do r:SetAlpha(a) end
	for _, c in ipairs({ native:GetChildren() }) do c:SetAlpha(a) end
	settingAlpha = false
end
local function applyNativeLook()
	local a = nativeAlpha()
	for _, s in ipairs(strips) do
		setNativeLook(s.native, a)
	end
end

local function setStripVisible(s, show)
	if s.visible == show then return false end
	s.visible = show
	if show then s.bar:Show() else s.bar:Hide() end
	return true
end

-- The strip draws its own swing times from PLAYER_SWING (no secret values involved).
local function stripUpdate(s, now)
	if testUntil then
		local f = (now % 2) / 2
		if not s.previewInit then
			s.bar:SetMinMaxValues(0, 1)
			s.previewInit = true
			s.liveInit = false
			s.liveTenths = nil
			s.liveMode = nil
		end
		s.bar:SetValue(f)
		if db.swingText then
			local tenths = math.floor((2 - f * 2) * 10 + 0.5)
			if tenths ~= s.previewTenths then
				s.previewTenths = tenths
				s.text:SetText(string.format("%.1f", tenths / 10))
				s.hadText = true
			end
		elseif s.hadText then
			s.text:SetText("")
			s.hadText = false
			s.previewTenths = nil
		end
		return setStripVisible(s, true)
	end
	s.liveMode = "run"
	local dur = s.swingDur
	local left = s.swingEnd - now
	if left < 0 then left = 0 end
	if not s.liveInit or s.liveDur ~= dur then
		s.bar:SetMinMaxValues(0, dur)
		s.liveDur, s.liveInit = dur, true
	end
	s.bar:SetValue(dur - left)
	if db.swingText then
		local tenths = floor(left * 10 + 0.5)
		if tenths ~= s.liveTenths then
			s.liveTenths = tenths
			s.text:SetText(format("%.1f", tenths / 10))
			s.hadText = true
		end
	elseif s.hadText then
		s.text:SetText("")
		s.hadText = false
		s.liveTenths = nil
	end
	return setStripVisible(s, true)
end

-- If the strip ever fails, the built-in bars come back, so a swing timer is never lost.
-- "run": a swing is on its way; nil: hidden. A strip only shows while its swing runs.
local function stripMode(s, now)
	if s.swingEnd and now < s.swingEnd + SWING_GRACE then return "run" end
	return nil
end

local function safeUpdate(s, now)
	if failed then return false end
	s.mode = stripMode(s, now)
	if not testUntil and not (db.swing and s.mode) then
		return setStripVisible(s, false)
	end
	local ok, changed = pcall(stripUpdate, s, now)
	if not ok then
		failed = true
		for _, x in ipairs(strips) do
			x.visible = false
			x.bar:Hide()
			setNativeLook(x.native, 1)
		end
		P("swing strip off after an error, the built-in swing timer is shown again. /reload to retry. " .. tostring(changed))
		if syncDriver then syncDriver() end
		return false
	end
	return changed
end

local driver = CreateFrame("Frame")
driver:Hide()

local function anySwingRunning()
	local now = GetTime()
	for i = 1, #strips do
		local e = strips[i].swingEnd
		if e and now < e + SWING_GRACE then return true end
	end
	return false
end

syncDriver = function()
	local active = #strips > 0 and not failed and (testUntil ~= nil or (db and db.swing and anySwingRunning()))
	if active then
		driver:Show()
	else
		driver:Hide()
		local relayout = false
		for i = 1, #strips do
			if setStripVisible(strips[i], false) then relayout = true end
		end
		if relayout then layoutStrips() end
	end
end

driver:SetScript("OnUpdate", function()
	if #strips == 0 or failed then
		syncDriver()
		return
	end
	local now = GetTime()
	if testUntil and now > testUntil then
		testUntil = nil
		endPreviewState()
	end
	if not (db.swing or testUntil) then
		syncDriver()
		return
	end
	if testUntil then
		refreshTint((now % 4 < 2) and "queued" or "swing")
	end
	local anyShown, relayout = false, false
	for i = 1, #strips do
		if safeUpdate(strips[i], now) then relayout = true end
		if strips[i].visible then anyShown = true end
	end
	if relayout then layoutStrips() end
	if not anyShown and not testUntil then syncDriver() end
end)

local function makeStrip(name, isMainHand)
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
	border:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
	border:SetBackdropBorderColor(0, 0, 0, 0.9)

	local spark = bar:CreateTexture(nil, "OVERLAY")
	spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
	spark:SetBlendMode("ADD")
	spark:SetSize(10, db.height * 2.5)
	spark:SetPoint("CENTER", bar:GetStatusBarTexture(), "RIGHT", 0, 0)

	local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("RIGHT", bar, "RIGHT", -2, 0)

	return { name = name, bar = bar, text = text, spark = spark, isMainHand = isMainHand, visible = false, hadText = false }
end

-- The built-in swing timer (if the game loads it): only its look is hidden, nothing is read from it.
local function hookNative(s)
	if s.native then return end
	local native = _G[s.name]
	if not (native and native.StatusBar) then return end
	s.native = native
	native:HookScript("OnShow", function(self)
		setNativeLook(self, nativeAlpha())
	end)
	-- the game may set the alpha of the bar's parts itself (flash, fade): keep them hidden
	for _, c in ipairs({ native:GetChildren() }) do
		hooksecurefunc(c, "SetAlpha", function(self, a)
			if settingAlpha then return end
			if nativeAlpha() == 0 and a ~= 0 then
				settingAlpha = true
				self:SetAlpha(0)
				settingAlpha = false
			end
		end)
	end
	setNativeLook(native, nativeAlpha())
end

-- Font and colours, applied again whenever a setting changes.
applyLook = function()
	local path = fontPath()
	if timeText then timeText:SetFont(path, db.fontSize, "OUTLINE") end
	if lagTex then
		local r, g, b = color("latency")
		lagTex:SetColorTexture(r, g, b, 0.45)
	end
	for _, s in ipairs(strips) do
		s.text:SetFont(path, max(db.fontSize - 2, 7), "OUTLINE")
	end
	applyBarColors()
end

local function hookNatives()
	for _, s in ipairs(strips) do hookNative(s) end
end

-- PLAYER_SWING: (duration, swing type). The duration falls back to the weapon speed.
local HAND_INDEX
local function onSwing(dur, kind)
	if not HAND_INDEX then
		HAND_INDEX = {}
		local e = Enum and Enum.PlayerSwingType
		if e then
			if e.MainHand then HAND_INDEX[e.MainHand] = 1 end
			if e.OffHand then HAND_INDEX[e.OffHand] = 2 end
			if e.Ranged then HAND_INDEX[e.Ranged] = 3 end
		else
			HAND_INDEX[0], HAND_INDEX[1], HAND_INDEX[2] = 1, 2, 3
		end
	end
	if issecret(kind) or issecret(dur) then return end
	local i = HAND_INDEX[kind]
	local s = i and strips[i]
	if not s then return end
	local speed = speedFor(i)
	if type(dur) ~= "number" or dur <= 0 then dur = speed end
	if not dur then return end
	local now = GetTime()
	s.swingStart, s.swingDur, s.swingEnd, s.swingSpeed = now, dur, now + dur, speed
	s.liveInit = false
	syncDriver()
end

-- Speed changed mid-swing (shapeshift, haste buff on or off, slow): the rest of the
-- running swing scales with it, as the game does.
local function onSpeedChange()
	local now = GetTime()
	for i = 1, 2 do
		local s = strips[i]
		if s and s.swingEnd and now < s.swingEnd and s.swingSpeed then
			local new = speedFor(i)
			if new and new ~= s.swingSpeed then
				local left = (s.swingEnd - now) * new / s.swingSpeed
				s.swingEnd = now + left
				s.swingDur = (now - s.swingStart) + left
				s.swingSpeed = new
			end
		end
	end
end

local queueEvents
local swingEvents
local function setupSwing()
	if #strips > 0 then return end
	for _, name in ipairs(SWING_FRAMES) do
		strips[#strips + 1] = makeStrip(name, name == "SwingTimerMainHandFrame")
	end
	hookNatives()
	for i, s in ipairs(strips) do s.index = i end
	swingEvents = CreateFrame("Frame")
	swingEvents:RegisterEvent("PLAYER_SWING")
	swingEvents:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
	swingEvents:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	swingEvents:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	swingEvents:SetScript("OnEvent", function(_, event, a1, a2)
		if event == "PLAYER_SWING" then
			onSwing(a1, a2)
		elseif event == "PLAYER_EQUIPMENT_CHANGED" then
			offHandWeapon = nil
			if not hasOffHandWeapon() and strips[2] then strips[2].swingEnd = nil end
			onSpeedChange()
		else
			onSpeedChange()
		end
	end)
	if queueList and not queueEvents then
		queueEvents = CreateFrame("Frame")
		queueEvents:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
		queueEvents:SetScript("OnEvent", function()
			if not testUntil then refreshTint(queuedColor()) end
		end)
	end
	tint = queuedColor()
	castBarOk = castBarUsable()
	layoutStrips()
	applyNativeLook()
	applyLook()
	syncDriver()
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
	if #strips == 0 then
		P(SWING_NOT_FOUND)
		return
	end
	testUntil = max(testUntil or 0, GetTime() + 8) -- never cuts short the open window's preview
	layoutStrips()
	syncDriver()
	P("8 s preview of the swing strip, the second half tinted as if Maul were queued.")
end

-- Changing a switch: store it and redraw what depends on it.
local function setToggle(key, value)
	db[key] = value
	if key == "swing" or key == "hideNative" then
		applyNativeLook()
		syncDriver()
	elseif key == "attach" then
		checkCastBar()
		layoutStrips()
	elseif key == "icon" or key == "iconInside" then
		applyIcon()
	elseif key == "latency" then
		if castBar then castRefresh() end
	elseif key == "showMinimap" then
		applyMinimap()
	end
	refreshOptions()
end

-- Own window instead of a page in the game's options (BencepoUI, as in Bencepo's other
-- addons): it can be dragged anywhere and stays open while you play, so every change
-- shows live on the cast bar and the strip.
local win
local BUG_URL = "https://github.com/Bencepo/SwingCast/issues/new/choose"
local ACCENT = { 1.00, 0.55, 0.10, 1 }

local function buildWindow()
	local UI = LibStub("BencepoUI-1.0")
	local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
	win = UI:CreateWindow({
		name = "SwingCastOptionsFrame", title = ADDON,
		subtitle = (version and not version:find("@")) and version or nil,
		width = 500, height = 470, accent = ACCENT, db = db, posKey = "optPos", bugUrl = BUG_URL,
		onShow = function() optionsShown = true; updatePreview() end,
		onHide = function() optionsShown = false; updatePreview() end,
	})
	local w = win
	local function check(x, y, key, label, tip)
		w:Check(x, y, label, tip, function() return db[key] end, function(v) setToggle(key, v and true or false) end)
	end
	local function slider(x, y, key, label, minV, maxV, step, onChange, tip)
		w:Slider(x, y, label, minV, maxV, step, function() return db[key] end,
			function(v) db[key] = v; onChange() end, tip, 170)
	end

	-- left column: switches
	local L = 16
	w:Header(L, -48, "Cast bar")
	check(L, -72, "icon", "Spell icon", "Show the spell icon on the cast bar.")
	check(L, -96, "iconInside", "Icon inside the bar", "Icon at the left end inside the cast bar. Off: left of the bar; Edit Mode's box then includes the icon's room.")
	check(L, -120, "time", "Cast time", "Show the remaining cast time on the cast bar.")
	check(L, -144, "latency", "Latency zone", "Zone at the end of the cast bar: once the bar reaches it, the next spell can be pressed.")
	w:Header(L, -178, "Swing strip")
	check(L, -202, "swing", "Swing strip", "Swing timer as a thin strip under the cast bar.")
	check(L, -226, "swingText", "Swing seconds", "Seconds to the next swing on the strip.")
	check(L, -250, "hideNative", "Hide built-in swing bars", "Hide the look of Forever's own swing timer bars while the strip is on.")
	check(L, -274, "attach", "Attach to cast bar", "Strip right under the cast bar. Off: its own position, set by dragging it (Move, or the game's Edit Mode).")
	w:Header(L, -308, "General")
	check(L, -332, "showMinimap", "Minimap button", "Show the SwingCast button at the minimap.")

	-- right column: sizes, font, colours
	local R = 262
	w:Header(R, -48, "Size and font")
	slider(R, -72, "height", "Strip height", 2, 20, 1, layoutStrips, "Height of the swing strip in pixels.")
	slider(R, -108, "width", "Strip width (own position)", WIDTH_MIN, WIDTH_MAX, 5, layoutStrips,
		"Width of the strip at its own position. Under the cast bar it takes the cast bar's width.")
	slider(R, -144, "fontSize", "Font size", 7, 20, 1, applyLook, "Size of the cast time. The swing seconds are 2 smaller.")
	local fontItems = {}
	for _, f in ipairs(FONTS) do fontItems[#fontItems + 1] = { f.key, f.label } end
	w:Dropdown(R, -180, "Font", 210, fontItems, function() return db.font end,
		function(v) db.font = v; applyLook() end, "Font of the cast time and the swing seconds.")

	w:Header(R, -232, "Colours")
	for i, c in ipairs(COLOR_LABELS) do
		local key = c[1]
		local sw = w:Button(c[2], 36, function() pickColor(key) end, c[3] .. " Click to choose.")
		sw:SetText("")
		sw:SetHeight(18)
		sw:SetPoint("TOPLEFT", R, -254 - (i - 1) * 24)
		local fill = sw:CreateTexture(nil, "ARTWORK")
		fill:SetPoint("TOPLEFT", 3, -3)
		fill:SetPoint("BOTTOMRIGHT", -3, 3)
		w:OnRefresh(function() fill:SetColorTexture(color(key)) end)
		local t = w:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		t:SetPoint("LEFT", sw, "RIGHT", 8, 0)
		t:SetText(c[2])
	end
	w:Button("Default colours", 140, resetColors, "Set all colours back to the defaults."):SetPoint("TOPLEFT", R, -354)

	-- bottom row: position
	w:Header(L, -372, "Position")
	local move = w:Button("Move strip", 110, function()
		if unlocked then lock() else unlock("manual") end
	end, "Takes the strip off the cast bar so you can drag it anywhere. Click again or right-click the strip to lock. The game's Edit Mode moves it too.")
	move:SetPoint("TOPLEFT", L, -394)
	w:OnRefresh(function() move:SetText(unlocked == "manual" and "Lock strip" or "Move strip") end)
	w:Button("Default position", 130, resetPosition, "Put the strip back under the cast bar."):SetPoint("LEFT", move, "RIGHT", 8, 0)
	w:Button("Reset all", 100, function() SlashCmdList.SWINGCAST("reset") end, "All settings back to the defaults.")
		:SetPoint("LEFT", move, "RIGHT", 146, 0)
	w:Text(L, -426, "While this window is open the swing strip shows a preview.", 350)

	refreshOptions = function() if win then win:Refresh() end end
end

local function ensureWindow()
	if not win then buildWindow() end
	return win
end

local function openOptions()
	if not db then return end
	ensureWindow():Toggle()
end

-- The game's options only point to the window, so the addon is still found there.
local function registerSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local category, layout = Settings.RegisterVerticalLayoutCategory(ADDON)
	if layout and CreateSettingsButtonInitializer then
		layout:AddInitializer(CreateSettingsButtonInitializer("SwingCast has its own window", "Open", function()
			if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
			if not db then return end
			ensureWindow():Show()
		end, "Opens the SwingCast window. It can be dragged anywhere and stays open while you play.", true))
	end
	Settings.RegisterAddOnCategory(category)
end

-- Entry in the game's addon menu (the button next to the minimap) and minimap click handler.
function SwingCast_OnCompartmentClick(_, button)
	if button == "RightButton" then startTest() else openOptions() end
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
		OnClick = SwingCast_OnCompartmentClick,
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

---------------------------------------------------------------- settings
local TOGGLES = {
	icon = "spell icon",
	iconInside = "spell icon inside the cast bar",
	time = "cast time",
	latency = "latency zone",
	swing = "swing strip",
	swingText = "swing seconds",
	hideNative = "hide the built-in swing bars",
	attach = "swing strip attached to the cast bar",
}
local ORDER = { "icon", "iconInside", "time", "latency", "swing", "swingText", "hideNative", "attach" }
local KEY = {} -- lower-case command -> setting key, so /swc swingtext works too
for _, k in ipairs(ORDER) do KEY[k:lower()] = k end

SLASH_SWINGCAST1 = "/swc"
SLASH_SWINGCAST2 = "/swingcast"
SlashCmdList.SWINGCAST = function(msg)
	if not db then return end
	local cmd, arg = strtrim(msg or ""):lower():match("^(%S*)%s*(.-)$")
	if arg == "" then arg = nil end
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
		P(lock() and "swing strip locked." or "swing strip is already locked.")
	elseif cmd == "width" and num then
		db.width = clampInt(num, WIDTH_MIN, WIDTH_MAX)
		layoutStrips()
		P("swing strip width: " .. db.width .. (db.attach and " (used once the strip has its own position)" or ""))
	elseif cmd == "position" and arg == "reset" then
		resetPosition()
		P("swing strip back under the cast bar.")
	elseif cmd == "height" and num then
		db.height = clampInt(num, 2, 20)
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
		db.fontSize = clampInt(num, 7, 20)
		applyLook()
		P("font size: " .. db.fontSize)
	elseif cmd == "minimap" then
		setToggle("showMinimap", not db.showMinimap)
		P("minimap button: " .. (db.showMinimap and "on" or "off"))
	elseif cmd == "reset" then
		lock()
		for k, v in pairs(DEFAULTS) do db[k] = v end
		db.pos = nil
		db.optPos = nil
		if win then
			win:ClearAllPoints()
			win:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
		end
		db.colors = CopyTable(DEFAULT_COLORS)
		applyLook()
		applyIcon()
		layoutStrips()
		applyNativeLook()
		applyMinimap()
		syncDriver()
		P("settings reset.")
	else
		P("/swc opens the window. /swc <setting> switches it on or off:")
		for _, k in ipairs(ORDER) do
			print(format("  %s - %s (%s)", k, TOGGLES[k], db[k] and "on" or "off"))
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
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event, name)
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
		hookNatives()
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		loginTime = GetTime()
		setupCastBar()
		hookEditMode()
		setupSwing()
		-- Check cast bar layout again once Edit Mode / other UI addons have finished placing frames.
		C_Timer.After(6, checkCastBar)
	elseif event == "PLAYER_ENTERING_WORLD" then
		checkCastBar()
		applyNativeLook()
	end
end)

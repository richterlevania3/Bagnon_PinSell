--[[
	Bagnon_PinSell
	Slot roles (per character, backpack bags 0-4 only):
	- Ctrl-right-click an occupied slot: PIN the item to that slot (star marker).
	  Bagnon's sort button never moves it, and auto-sell never touches it.
	- Ctrl-right-click an empty slot: RESERVE it for quest items (! marker).
	  Sort skips it (won't dump items there or take items from it).
	- Ctrl-right-click a pinned/reserved slot again to clear it.
	Nothing is ever moved automatically -- sorting happens only when you sort.
	Plus: auto-sells unpinned grey items on MERCHANT_SHOW.
	/bps toggles auto-sell, /bps list shows slot assignments.
--]]

local ADDON_NAME = ...
local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon', true)
if not Bagnon or not Bagnon.ItemSlot then return end

local db, cdb    -- account / per-character saved vars, set on ADDON_LOADED
local hookedSlots = {}

local RAID_ICONS = [[Interface\TargetingFrame\UI-RaidTargetingIcons]]
local QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or [[Interface\ContainerFrame\UI-Icon-QuestBang]]

local function say(text)
	DEFAULT_CHAT_FRAME:AddMessage('|cff00ff98Bagnon PinSell:|r ' .. text)
end


--[[ Slot helpers ]]--

local function key(bag, slot)
	return bag .. ':' .. slot
end

local function parseKey(k)
	local bag, slot = string.match(k, '^(%-?%d+):(%d+)$')
	return tonumber(bag), tonumber(slot)
end

local function isBackpackBag(bag)
	return bag and bag >= 0 and bag <= NUM_BAG_SLOTS
end

local function slotItemId(bag, slot)
	local link = GetContainerItemLink(bag, slot)
	return link and tonumber(string.match(link, 'item:(%d+)')) or nil
end

local function isProtected(bag, slot)
	if not cdb then return false end
	local k = key(bag, slot)
	return cdb.pins[k] ~= nil or cdb.questSlots[k] == true
end


--[[ Slot markers ]]--

local function updateMarker(item)
	local bag, slot = item:GetBag(), item:GetID()
	local k = key(bag, slot)
	local role = cdb and (cdb.pins[k] and 'pin' or cdb.questSlots[k] and 'quest') or nil

	if role then
		local icon = item.pinSellIcon
		if not icon then
			icon = item:CreateTexture(nil, 'OVERLAY')
			icon:SetWidth(13)
			icon:SetHeight(13)
			icon:SetPoint('TOPLEFT', item, 'TOPLEFT', 2, -2)
			item.pinSellIcon = icon
		end
		if role == 'pin' then
			icon:SetTexture(RAID_ICONS)
			icon:SetTexCoord(0, 0.25, 0, 0.25) -- yellow star
		else
			icon:SetTexture(QUEST_BANG)
			icon:SetTexCoord(0, 1, 0, 1)
		end
		icon:Show()
	elseif item.pinSellIcon then
		item.pinSellIcon:Hide()
	end
end

local function updateAllMarkers()
	for item in pairs(hookedSlots) do
		if item:IsVisible() then
			updateMarker(item)
		end
	end
end


--[[ Keep sorting away from pinned/reserved slots ]]--

if Bagnon.Sorting and Bagnon.Sorting.GetSpaces then
	local origGetSpaces = Bagnon.Sorting.GetSpaces
	function Bagnon.Sorting:GetSpaces()
		local spaces = origGetSpaces(self)
		if not cdb then return spaces end

		local filtered = {}
		for _, space in ipairs(spaces) do
			if not isProtected(space.bag, space.slot) then
				space.index = #filtered
				table.insert(filtered, space)
			end
		end
		return filtered
	end
end


--[[ Ctrl-right-click: pin / reserve / clear ]]--

local function slotDesc(bag, slot)
	return 'bag ' .. bag .. ' slot ' .. slot
end

local function onCtrlRightClick(item)
	local bag, slot = item:GetBag(), item:GetID()
	if not isBackpackBag(bag) then
		say('pinning only works in backpack bags')
		return
	end

	local k = key(bag, slot)
	if cdb.pins[k] then
		cdb.pins[k] = nil
		say('unpinned ' .. slotDesc(bag, slot))
	elseif cdb.questSlots[k] then
		cdb.questSlots[k] = nil
		say(slotDesc(bag, slot) .. ' no longer reserved for quest items')
	else
		local id = slotItemId(bag, slot)
		if id then
			cdb.pins[k] = id
			local name = GetItemInfo(id)
			say('pinned ' .. (name or ('item:' .. id)) .. ' to ' .. slotDesc(bag, slot))
		else
			cdb.questSlots[k] = true
			say(slotDesc(bag, slot) .. ' reserved for quest items')
		end
	end

	updateAllMarkers()
end

-- Taint-safe click capture: we never touch the slot button's own OnClick
-- (running Blizzard's handler under addon taint gets the addon blocked).
-- Instead, a transparent overlay button per slot appears only while Ctrl is
-- held and catches the right-click; normal clicks never see addon code.

local function overlayOnClick(self)
	local item = self:GetParent()
	if cdb and IsControlKeyDown() and not CursorHasItem() and not item:IsCached() then
		onCtrlRightClick(item)
	end
end

local function overlayOnEnter(self)
	local item = self:GetParent()
	local onEnter = item:GetScript('OnEnter')
	if onEnter then onEnter(item) end
end

local function overlayOnLeave(self)
	local item = self:GetParent()
	local onLeave = item:GetScript('OnLeave')
	if onLeave then onLeave(item) end
end

local function hookSlot(item)
	if hookedSlots[item] then return end
	hookedSlots[item] = true

	local ov = CreateFrame('Button', nil, item)
	ov:SetAllPoints(item)
	ov:RegisterForClicks('RightButtonUp')
	ov:SetScript('OnClick', overlayOnClick)
	ov:SetScript('OnEnter', overlayOnEnter) -- keep the tooltip alive under Ctrl
	ov:SetScript('OnLeave', overlayOnLeave)
	ov:Hide()
	item.pinSellOverlay = ov
end

local function setOverlaysShown(shown)
	for item in pairs(hookedSlots) do
		local ov = item.pinSellOverlay
		if ov then
			if shown and item:IsVisible() then
				ov:SetFrameLevel(item:GetFrameLevel() + 5)
				ov:Show()
			else
				ov:Hide()
			end
		end
	end
end

local origNew = Bagnon.ItemSlot.New
function Bagnon.ItemSlot:New(...)
	local item = origNew(self, ...)
	hookSlot(item)
	updateMarker(item)
	if IsControlKeyDown() and item.pinSellOverlay then
		item.pinSellOverlay:SetFrameLevel(item:GetFrameLevel() + 5)
		item.pinSellOverlay:Show()
	end
	return item
end

hooksecurefunc(Bagnon.ItemSlot, 'Update', function(self)
	updateMarker(self)
end)


--[[ Auto-sell greys at vendors (pinned/reserved slots are safe) ]]--

local function coins(copper)
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then table.insert(parts, g .. '|cffffd700g|r') end
	if s > 0 then table.insert(parts, s .. '|cffc7c7cfs|r') end
	if c > 0 or #parts == 0 then table.insert(parts, c .. '|cffeda55fc|r') end
	return table.concat(parts, ' ')
end

local function sellGreys()
	local total, sold = 0, 0

	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)
			if link and not isProtected(bag, slot) then
				local _, _, quality, _, _, _, _, _, _, _, price = GetItemInfo(link)
				if quality == 0 and price and price > 0 then
					local _, count = GetContainerItemInfo(bag, slot)
					UseContainerItem(bag, slot)
					total = total + price * (count or 1)
					sold = sold + 1
				end
			end
		end
	end

	if sold > 0 then
		say('sold ' .. sold .. ' grey item' .. (sold > 1 and 's' or '')
			.. ' for ' .. coins(total))
	end
end


--[[ Events / setup ]]--

local watcher = CreateFrame('Frame')
watcher:RegisterEvent('ADDON_LOADED')
watcher:RegisterEvent('MERCHANT_SHOW')
watcher:RegisterEvent('MODIFIER_STATE_CHANGED')
watcher:SetScript('OnEvent', function(self, event, arg1, arg2)
	if event == 'MODIFIER_STATE_CHANGED' then
		if arg1 == 'LCTRL' or arg1 == 'RCTRL' then
			setOverlaysShown(arg2 == 1)
		end
	elseif event == 'ADDON_LOADED' then
		if arg1 == ADDON_NAME then
			BagnonPinSellDB = BagnonPinSellDB or {}
			db = BagnonPinSellDB

			BagnonPinSellCharDB = BagnonPinSellCharDB or {}
			BagnonPinSellCharDB.pins = BagnonPinSellCharDB.pins or {}
			BagnonPinSellCharDB.questSlots = BagnonPinSellCharDB.questSlots or {}
			cdb = BagnonPinSellCharDB

			self:UnregisterEvent('ADDON_LOADED')
		end
	elseif event == 'MERCHANT_SHOW' then
		if db and db.autosell ~= false then
			sellGreys()
		end
	end
end)


--[[ Slash commands ]]--

SLASH_BAGNONPINSELL1 = '/bps'
SlashCmdList['BAGNONPINSELL'] = function(input)
	local cmd = string.lower(string.match(input or '', '^%s*(%S*)'))

	if cmd == 'list' then
		say('pinned slots:')
		local n = 0
		for k, id in pairs(cdb.pins) do
			n = n + 1
			local bag, slot = parseKey(k)
			local name, link = GetItemInfo(id)
			DEFAULT_CHAT_FRAME:AddMessage('  - ' .. slotDesc(bag, slot) .. ': '
				.. (link or name or ('item:' .. id)))
		end
		if n == 0 then DEFAULT_CHAT_FRAME:AddMessage('  (none)') end

		say('quest-reserved slots:')
		n = 0
		for k in pairs(cdb.questSlots) do
			n = n + 1
			local bag, slot = parseKey(k)
			DEFAULT_CHAT_FRAME:AddMessage('  - ' .. slotDesc(bag, slot))
		end
		if n == 0 then DEFAULT_CHAT_FRAME:AddMessage('  (none)') end
	elseif cmd == '' then
		db.autosell = (db.autosell == false)
		say('auto-sell ' .. (db.autosell ~= false and '|cff00ff00on|r' or '|cffff0000off|r'))
	else
		say('usage: /bps  (toggle auto-sell) | /bps list  (show pinned/reserved slots)')
	end
end

--[[
	Bagnon_PinSell
	Slot roles (per character, backpack bags 0-4 only):
	- Alt-right-click an occupied slot: PIN the item to that slot (star marker).
	  Auto-sort never moves it, and if the item is found elsewhere in your
	  bags it gets moved back home.
	- Alt-right-click an empty slot: RESERVE it for quest items (! marker).
	  Auto-sort skips it, new quest items are pulled into reserved slots,
	  and non-quest items that land there are evicted.
	- Alt-right-click a pinned/reserved slot again to clear it.
	Plus: auto-sells unpinned grey items on MERCHANT_SHOW.
	/bps toggles auto-sell, /bps list shows slot assignments.
--]]

local ADDON_NAME = ...
local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon', true)
if not Bagnon or not Bagnon.ItemSlot then return end

local db, cdb    -- account / per-character saved vars, set on ADDON_LOADED
local hookedSlots = {}
local moveQueue = {}
local enforceAt, nextMoveAt

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

local function slotLocked(bag, slot)
	local _, _, locked = GetContainerItemInfo(bag, slot)
	return locked
end

local function isProtected(bag, slot)
	if not cdb then return false end
	local k = key(bag, slot)
	return cdb.pins[k] ~= nil or cdb.questSlots[k] == true
end

local function isQuestItemAt(bag, slot)
	if not GetContainerItemLink(bag, slot) then return false end
	if GetContainerItemQuestInfo then
		local isQuest, questID = GetContainerItemQuestInfo(bag, slot)
		return isQuest and true or (questID and true) or false
	end
	return false
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


--[[ Move engine (async, lock-aware) ]]--

local driver = CreateFrame('Frame')
driver:Hide()

local function wake()
	driver:Show()
end

local function scheduleEnforce()
	enforceAt = GetTime() + 0.6
	wake()
end

local function queueMove(sBag, sSlot, dBag, dSlot, itemID)
	table.insert(moveQueue, { sb = sBag, ss = sSlot, db = dBag, ds = dSlot, id = itemID })
	wake()
end

local function processQueue()
	local m = moveQueue[1]
	if not m then return end

	if InCombatLockdown() or UnitIsDead('player') then
		table.wipe(moveQueue)
		return
	end

	-- source changed since planning? drop this move, re-plan on next enforce
	if slotItemId(m.sb, m.ss) ~= m.id then
		table.remove(moveQueue, 1)
		scheduleEnforce()
		return
	end

	-- wait for pending server acks
	if slotLocked(m.sb, m.ss) or slotLocked(m.db, m.ds) then
		return
	end

	ClearCursor()
	PickupContainerItem(m.sb, m.ss)
	PickupContainerItem(m.db, m.ds)
	ClearCursor() -- returns any displaced item to the source slot (swap)

	table.remove(moveQueue, 1)
end


--[[ Enforcement: pinned items home, quest items into reserved slots ]]--

local function findItemAt(itemID)
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if not isProtected(bag, slot) and slotItemId(bag, slot) == itemID then
				return bag, slot
			end
		end
	end
end

local function findEmptyUnprotected()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, GetContainerNumSlots(bag) do
			if not isProtected(bag, slot) and not GetContainerItemLink(bag, slot) then
				return bag, slot
			end
		end
	end
end

local function enforce()
	if not cdb or InCombatLockdown() or UnitIsDead('player') then return end
	if #moveQueue > 0 then return end

	-- 1) bring pinned items back to their home slots
	for k, itemID in pairs(cdb.pins) do
		local bag, slot = parseKey(k)
		if slotItemId(bag, slot) ~= itemID then
			local sBag, sSlot = findItemAt(itemID)
			if sBag then
				queueMove(sBag, sSlot, bag, slot, itemID)
			end
		end
	end

	-- 2) evict non-quest items squatting in reserved slots
	for k in pairs(cdb.questSlots) do
		local bag, slot = parseKey(k)
		local id = slotItemId(bag, slot)
		if id and not isQuestItemAt(bag, slot) then
			local eBag, eSlot = findEmptyUnprotected()
			if eBag then
				queueMove(bag, slot, eBag, eSlot, id)
			end
		end
	end

	-- 3) pull loose quest items into empty reserved slots
	local emptyReserved = {}
	for k in pairs(cdb.questSlots) do
		local bag, slot = parseKey(k)
		if not GetContainerItemLink(bag, slot) then
			table.insert(emptyReserved, { bag = bag, slot = slot })
		end
	end

	if #emptyReserved > 0 then
		local n = 1
		for bag = 0, NUM_BAG_SLOTS do
			for slot = 1, GetContainerNumSlots(bag) do
				if n > #emptyReserved then break end
				if not isProtected(bag, slot) and isQuestItemAt(bag, slot) then
					local dest = emptyReserved[n]
					queueMove(bag, slot, dest.bag, dest.slot, slotItemId(bag, slot))
					n = n + 1
				end
			end
		end
	end
end

driver:SetScript('OnUpdate', function()
	local now = GetTime()

	if #moveQueue > 0 then
		if now >= (nextMoveAt or 0) then
			nextMoveAt = now + 0.15
			processQueue()
		end
	elseif enforceAt then
		if now >= enforceAt then
			enforceAt = nil
			enforce()
		end
	else
		driver:Hide()
	end
end)


--[[ Keep auto-sort away from pinned/reserved slots ]]--

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


--[[ Alt-right-click: pin / reserve / clear ]]--

local function slotDesc(bag, slot)
	return 'bag ' .. bag .. ' slot ' .. slot
end

local function onAltRightClick(item)
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
	scheduleEnforce()
end

local function hookClicks(item)
	if hookedSlots[item] then return end
	hookedSlots[item] = true

	local orig = item:GetScript('OnClick')
	item:SetScript('OnClick', function(self, button, ...)
		if button == 'RightButton' and IsAltKeyDown() and cdb
			and not CursorHasItem() and not self:IsCached() then
			onAltRightClick(self)
			return -- swallow: default handler would use/equip the item
		end
		if orig then
			return orig(self, button, ...)
		end
	end)
end

local origNew = Bagnon.ItemSlot.New
function Bagnon.ItemSlot:New(...)
	local item = origNew(self, ...)
	hookClicks(item)
	updateMarker(item)
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
watcher:RegisterEvent('PLAYER_ENTERING_WORLD')
watcher:RegisterEvent('BAG_UPDATE')
watcher:RegisterEvent('MERCHANT_SHOW')
watcher:SetScript('OnEvent', function(self, event, arg1)
	if event == 'ADDON_LOADED' then
		if arg1 == ADDON_NAME then
			BagnonPinSellDB = BagnonPinSellDB or {}
			db = BagnonPinSellDB

			BagnonPinSellCharDB = BagnonPinSellCharDB or {}
			BagnonPinSellCharDB.pins = BagnonPinSellCharDB.pins or {}
			BagnonPinSellCharDB.questSlots = BagnonPinSellCharDB.questSlots or {}
			cdb = BagnonPinSellCharDB

			self:UnregisterEvent('ADDON_LOADED')
		end
	elseif event == 'PLAYER_ENTERING_WORLD' then
		scheduleEnforce()
	elseif event == 'BAG_UPDATE' then
		if cdb and (next(cdb.pins) or next(cdb.questSlots)) then
			scheduleEnforce()
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

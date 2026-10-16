local _, ns = ...

-- Addon whispers between players (same idea as Grandma's Game Box):
--   * one queue sent at a steady pace (a small burst, then RATE per second), so we never hit
--     the game's addon message throttle; if the game throttles us anyway, the message goes
--     back in front and the queue pauses
--   * the same message to the same player is only queued once, and at most PER_TARGET wait
--   * messages longer than the game's 255 characters go in parts ("~id:2/3~text"), put back
--     together on the other side
--   * whispers to an offline player bounce with "No player named ... is currently playing.":
--     that's hidden, the player counts as offline (ns.Comm.IsOffline) and what's queued for
--     them is dropped
--   * message contents the game hides from addons (secret values) are ignored
local Comm = {}
ns.Comm = Comm

Comm.PREFIX = "Bestiary"
local SendAddonMessage = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
local RegisterPrefix = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
local THROTTLED = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle

local BURST = 4
local RATE = 1
local PER_TARGET = 20 -- whispers waiting per player at most (a catch-up can need a few parts)
local THROTTLE_PAUSE = 3
local BOUNCE_TIME = 10
local MAX_LENGTH = 255
local PART = MAX_LENGTH - 12 -- room for the "~id:1/2~" header
local PART_TIMEOUT = 60 -- seconds to wait for the rest of a message in parts

local queue = {}
local tokens = BURST
local pausedUntil = 0
local lastSent = {} -- player key -> GetTime() of our last whisper
local offlineAt = {} -- player key -> GetTime() of their last bounce
local parts = {} -- sender key .. message id -> { total, got, list, at }
local heard = {} -- player key -> GetTime() of their last whisper to us
local partId = 0

Comm.sent = 0 -- whispers actually sent (for tests and /bst debug)

local function Key(name)
	return Ambiguate(name, "none"):lower()
end
Comm.Key = Key

local function IsSecret(value)
	return issecretvalue and issecretvalue(value) or false
end

local pump = CreateFrame("Frame")
pump:Hide()

local function Transmit(entry)
	local result = SendAddonMessage(Comm.PREFIX, entry.msg, "WHISPER", entry.target)
	if THROTTLED and result == THROTTLED then
		return false
	end
	lastSent[entry.key] = GetTime()
	Comm.sent = Comm.sent + 1
	return true
end

pump:SetScript("OnUpdate", function(self, elapsed)
	tokens = math.min(BURST, tokens + elapsed * RATE)
	if GetTime() < pausedUntil then
		return
	end
	while tokens >= 1 do
		local entry = queue[1]
		if not entry then
			self:Hide()
			return
		end
		if not Transmit(entry) then
			pausedUntil = GetTime() + THROTTLE_PAUSE
			return
		end
		tremove(queue, 1)
		tokens = tokens - 1
	end
end)

local function Enqueue(msg, target, key)
	for _, entry in ipairs(queue) do
		if entry.key == key and entry.msg == msg then
			return -- already waiting
		end
	end
	local waiting = 0
	for _, entry in ipairs(queue) do
		if entry.key == key then
			waiting = waiting + 1
		end
	end
	if waiting >= PER_TARGET then
		return
	end
	queue[#queue + 1] = { msg = msg, target = target, key = key }
	pump:Show()
end

-- Whispers msg to target as soon as the pace allows; long messages go in parts
function Comm.Send(msg, target)
	if not target or target == "" then
		return
	end
	local key = Key(target)
	if #msg <= MAX_LENGTH and msg:sub(1, 1) ~= "~" then
		Enqueue(msg, target, key)
		return
	end
	local total = math.ceil(#msg / PART)
	partId = partId % 4095 + 1
	for i = 1, total do
		Enqueue(("~%x:%d/%d~%s"):format(partId, i, total, msg:sub((i - 1) * PART + 1, i * PART)), target, key)
	end
end

-- Seconds since this player last whispered us (this session), nil if they haven't
function Comm.LastHeard(name)
	local at = name and heard[Key(name)]
	return at and GetTime() - at or nil
end

function Comm.IsOffline(name)
	return name and offlineAt[Key(name)] ~= nil
end

-- Features listening to whispers (duels, the board): name -> { receive(msg, sender), offline(name) }.
-- Every message goes to all of them; each one only handles its own message kinds.
local handlers = {}
function Comm.Register(name, receive, offline)
	handlers[name] = { receive = receive, offline = offline }
	if RegisterPrefix then
		RegisterPrefix(Comm.PREFIX)
	end
end

-- A whisper came in (also called by tests)
function Comm.Receive(prefix, msg, channel, sender)
	if prefix ~= Comm.PREFIX or channel ~= "WHISPER" or IsSecret(msg) or IsSecret(sender) or not sender
		or type(msg) ~= "string" or #msg > MAX_LENGTH then
		return
	end
	local key = Key(sender)
	offlineAt[key] = nil -- anything from them means they're online
	heard[key] = GetTime()
	local id, index, total, text = msg:match("^~(%x+):(%d+)/(%d+)~(.*)$")
	if id then
		index, total = tonumber(index), tonumber(total)
		local now = GetTime()
		local slot = key .. ":" .. id
		local entry = parts[slot]
		if not entry or entry.total ~= total or now - entry.at > PART_TIMEOUT then
			entry = { total = total, got = 0, list = {}, at = now }
			parts[slot] = entry
		end
		if not entry.list[index] then
			entry.list[index] = text
			entry.got = entry.got + 1
		end
		if entry.got < total then
			return
		end
		parts[slot] = nil
		msg = table.concat(entry.list)
		for other, old in pairs(parts) do
			if now - old.at > PART_TIMEOUT then
				parts[other] = nil -- parts whose rest never came
			end
		end
	end
	for _, handler in pairs(handlers) do
		if handler.receive then
			handler.receive(msg, sender)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, ...)
	Comm.Receive(...)
end)

-- "No player named X is currently playing." right after our whisper to X: they're offline
local function Bounce(name)
	local key = Key(name)
	if not lastSent[key] or GetTime() - lastSent[key] > BOUNCE_TIME then
		return false -- not about one of our whispers
	end
	for i = #queue, 1, -1 do
		if queue[i].key == key then
			tremove(queue, i)
		end
	end
	offlineAt[key] = GetTime()
	for _, handler in pairs(handlers) do
		if handler.offline then
			handler.offline(name)
		end
	end
	return true
end
Comm.Bounce = Bounce

if ERR_CHAT_PLAYER_NOT_FOUND_S and ChatFrame_AddMessageEventFilter then
	local notFound = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("[%.%-%(%)%[%]%+%*%?%^%$]", "%%%0"):gsub("%%s", "(.+)") .. "$"
	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
		local name = type(msg) == "string" and not IsSecret(msg) and msg:match(notFound)
		if name then
			return Bounce((name:gsub("^'(.*)'$", "%1")))
		end
	end)
end

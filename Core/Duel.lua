local _, ns = ...

-- Duels between players (ARCHITECTURE.md 6), with as few whispers as possible: 4 per duel.
--
--   1. challenger -> C|version|id|nonce        the nonce sets the twist, both see it before picking
--   2. opponent   -> A|id|commit               the opponent picked in secret; commit = hash of
--                                              its squad and a secret salt, so it can't change
--   3. challenger -> R|id|squad                the challenger picks and shows its squad: no hash
--                                              needed, the opponent is already bound
--   4. opponent   -> S|id|squad|salt           checked against the commit
--
-- Then both clients run the same fight (seed from the nonce and the salt, so neither side could
-- choose it) with the challenger as side 1: no result is sent. Also D|id|reason (declined, busy,
-- version) and X|id (cancelled).
--
-- Nothing is acknowledged on its own. A message is only sent again when the reply it waits for
-- doesn't come (RESEND times), and a repeated message gets the same answer again, so lost
-- whispers heal without extra traffic. A squad that doesn't match its commit or breaks the
-- rules, or an opponent who doesn't reveal after seeing ours, loses by forfeit.
local Duel = {}
ns.Duel = Duel

ns.PROTOCOL = 1
local CHALLENGE_TIME = 120 -- seconds the opponent has to pick and accept
local PICK_TIME = 150 -- seconds the challenger has to pick after the accept
local REVEAL_TIME = 40 -- seconds the opponent has to reveal after seeing our squad
-- Seconds after which our last message goes out again if its answer hasn't come. Whispers are
-- rarely lost, so this is kept low: a lost accept is mostly healed by the repeated challenge (a
-- repeated challenge gets our accept again), so the accept itself is only repeated once, late.
local RESEND = {
	challenge = { 30, 75 },
	accept = { 90 },
	reveal = { 8, 18, 30 },
}

local duels = {} -- id -> duel
Duel.list = duels

-- Hashing (FNV-1a, two 32-bit lanes), only for commits and seeds ---------------------------

local function Fnv(text, seed)
	local h = seed
	for i = 1, #text do
		h = bit.bxor(h, text:byte(i))
		-- h * 16777619 mod 2^32 without losing precision: 16777619 = 2^24 + 403
		h = (h * 403 + (h % 256) * 16777216) % 4294967296
	end
	return h
end

function ns.Hash(text)
	return ("%08x%08x"):format(Fnv(text, 2166136261), Fnv(text, 84696351))
end

local function Number(text)
	return tonumber(ns.Hash(text):sub(1, 7), 16)
end

local function Token()
	return ("%06x%06x"):format(math.random(0, 16777215), math.random(0, 16777215))
end

-- Squads on the wire: "npcId,stars,type,rarity,family,flags,name;..." ----------------------

local TYPE_CODE = { Tank = "T", Mage = "M", Assassin = "A", Healer = "H" }
local RARITY_CODE = { normal = "n", elite = "e", rare = "r", rareelite = "R", worldboss = "b" }
local FAMILY_CODE = { Beast = "B", Humanoid = "H", Undead = "U", Demon = "D", Dragonkin = "K",
	Elemental = "E", Giant = "G", Mechanical = "M" }
local function Invert(t)
	local out = {}
	for k, v in pairs(t) do
		out[v] = k
	end
	return out
end
local TYPE_OF, RARITY_OF, FAMILY_OF = Invert(TYPE_CODE), Invert(RARITY_CODE), Invert(FAMILY_CODE)

function ns.EncodeSquad(cards)
	local out = {}
	for _, card in ipairs(cards) do
		local name = (card.name or "?"):gsub("[|;,~]", "")
		out[#out + 1] = table.concat({ card.npcId or 0, card.stars or 1, TYPE_CODE[card.type] or "T",
			RARITY_CODE[card.classification] or "n", FAMILY_CODE[card.family] or "H",
			card.player and "p" or "", name }, ",")
	end
	return table.concat(out, ";")
end

-- Card views from the wire, nil if it doesn't parse
function ns.DecodeSquad(text, owner)
	local cards = {}
	for part in (text or ""):gmatch("[^;]+") do
		local npcId, stars, kind, rarity, family, flags, name = part:match("^(%d+),(%d),(%a),(%a),(%a),(%a*),(.+)$")
		if not npcId or not TYPE_OF[kind] or not RARITY_OF[rarity] or not FAMILY_OF[family] then
			return nil
		end
		local view = ns.CardView({
			npcId = tonumber(npcId), stars = tonumber(stars), type = TYPE_OF[kind],
			classification = RARITY_OF[rarity], family = FAMILY_OF[family], name = name, zone = "",
			player = flags == "p" or nil, remote = owner,
		})
		cards[#cards + 1] = view
	end
	return #cards > 0 and cards or nil
end

-- Whether a squad from the other side keeps the rules (6.1)
function ns.ValidSquad(cards)
	if not cards or #cards < ns.MIN_SQUAD or #cards > ns.MAX_SQUAD then
		return false, "squad size"
	end
	local named, power = 0, 0
	for _, card in ipairs(cards) do
		if card.stars < 1 or card.stars > ns.MAX_STARS then
			return false, "stars"
		end
		power = power + card.power
		if ns.IsNamed(card) then
			named = named + 1
		end
	end
	if named > 1 then
		return false, "more than one leader"
	elseif power > ns.POWER_CAP then
		return false, "over the cap"
	end
	return true
end

-- Sending -----------------------------------------------------------------------------------

local function Send(duel, msg, kind)
	duel.last, duel.lastKind, duel.sentAt, duel.resends = msg, kind, GetTime(), 0
	ns.Comm.Send(msg, duel.other)
end

local function Event(event, duel, ...)
	if Duel.OnEvent then
		Duel.OnEvent(event, duel, ...)
	end
end

local function Finish(duel, state, ...)
	duel.state = state
	duel.finished = GetTime()
	Event(state, duel, ...)
end

local function Active(duel)
	return not duel.finished
end

-- The duel with this player that's still going, if any
function Duel.With(name)
	local key = ns.Comm.Key(name)
	for _, duel in pairs(duels) do
		if Active(duel) and ns.Comm.Key(duel.other) == key then
			return duel
		end
	end
end

function Duel.Busy()
	for _, duel in pairs(duels) do
		if Active(duel) and duel.state ~= "incoming" then
			return duel
		end
	end
end

local function Twist(duel)
	return ns.TWISTS[Number(duel.nonce) % #ns.TWISTS + 1]
end

-- Both squads known: the fight, the same on both sides (challenger is side 1), then shown from
-- our side (we're always side 1 in what the UI gets)
local function Fight(duel)
	local seed = Number(duel.nonce .. duel.salt)
	local first = duel.role == "challenger" and duel.mine or duel.theirs
	local second = duel.role == "challenger" and duel.theirs or duel.mine
	local events, winner, sides = ns.Fight({ cards = first }, { cards = second }, seed, duel.twist.key)
	if duel.role == "opponent" then
		-- seen from our side: swap
		for _, event in ipairs(events) do
			if event.side then
				event.side = 3 - event.side
			end
			if event.targetSide then
				event.targetSide = 3 - event.targetSide
			end
			if event.winner then
				event.winner = event.winner == 0 and 0 or 3 - event.winner
			end
		end
		winner = winner == 0 and 0 or 3 - winner
		sides = { sides[2], sides[1] }
		for side, units in ipairs(sides) do
			for _, unit in ipairs(units) do
				unit.side = side
			end
		end
	end
	duel.result = { events = events, winner = winner, sides = sides, seed = seed }
	Finish(duel, "fight", duel.result)
end

local function Forfeit(duel, why)
	duel.forfeit = why
	Finish(duel, "forfeit", why)
end

-- Starting and answering --------------------------------------------------------------------

function Duel.Challenge(name)
	if not name or name == "" then
		return nil, "no player"
	elseif ns.Comm.Key(name) == ns.Comm.Key(UnitName("player")) then
		return nil, "that's you"
	elseif Duel.Busy() then
		return nil, "already in a duel"
	elseif ns.Board and not ns.Board.IsFriend(name) then
		return nil, name .. " isn't your Bestiary friend yet (add them on the Board tab)"
	end
	local duel = { id = Token(), role = "challenger", other = name, nonce = Token(), state = "challenged", started = GetTime() }
	duel.twist = Twist(duel)
	duels[duel.id] = duel
	Send(duel, ("C|%d|%s|%s"):format(ns.PROTOCOL, duel.id, duel.nonce), "challenge")
	Event("challenged", duel)
	return duel
end

-- The opponent picked: commit to the squad and accept
function Duel.Accept(duel, cards)
	if not duel or duel.state ~= "incoming" then
		return
	end
	duel.mine = cards
	duel.salt = Token()
	duel.wire = ns.EncodeSquad(cards)
	duel.commit = ns.Hash(duel.wire .. "|" .. duel.salt)
	duel.state = "accepted"
	duel.acceptedAt = GetTime()
	Send(duel, ("A|%s|%s"):format(duel.id, duel.commit), "accept")
	Event("accepted", duel)
end

function Duel.Decline(duel, reason)
	if not duel or not Active(duel) then
		return
	end
	duel.final = ("D|%s|%s"):format(duel.id, reason or "no")
	ns.Comm.Send(duel.final, duel.other)
	Finish(duel, "declined", reason or "no")
end

-- The challenger picked: show the squad
function Duel.Reveal(duel, cards)
	if not duel or duel.state ~= "picking" then
		return
	end
	duel.mine = cards
	duel.wire = ns.EncodeSquad(cards)
	duel.state = "revealed"
	duel.revealedAt = GetTime()
	Send(duel, ("R|%s|%s"):format(duel.id, duel.wire), "reveal")
	Event("revealed", duel)
end

function Duel.Cancel(duel)
	if not duel or not Active(duel) then
		return
	end
	duel.final = "X|" .. duel.id
	ns.Comm.Send(duel.final, duel.other)
	Finish(duel, "cancelled", "you")
end

-- Receiving ---------------------------------------------------------------------------------

local function OnChallenge(sender, version, id, nonce)
	local existing = duels[id]
	if existing then
		if existing.state == "accepted" then
			ns.Comm.Send(existing.last, sender) -- our accept got lost
		elseif existing.final then
			ns.Comm.Send(existing.final, sender) -- our decline got lost
		end
		return
	end
	if tonumber(version) ~= ns.PROTOCOL then
		ns.Comm.Send(("D|%s|version %d"):format(id, ns.PROTOCOL), sender)
		return
	end
	if ns.Board and not ns.Board.IsFriend(sender) then
		ns.Comm.Send(("D|%s|not friends"):format(id), sender) -- only Bestiary friends duel
		return
	end
	-- Both challenged each other: the one whose name sorts first stays challenger
	local mine = Duel.With(sender)
	if mine and mine.role == "challenger" and mine.state == "challenged" then
		if ns.Comm.Key(UnitName("player")) < ns.Comm.Key(sender) then
			return -- they'll take ours
		end
		duels[mine.id] = nil -- take theirs
	elseif Duel.Busy() or Duel.With(sender) then
		ns.Comm.Send(("D|%s|busy"):format(id), sender)
		return
	end
	local duel = { id = id, role = "opponent", other = sender, nonce = nonce, state = "incoming", started = GetTime() }
	duel.twist = Twist(duel)
	duels[id] = duel
	Event("incoming", duel)
end

local function OnAccept(duel, commit)
	if duel.state == "challenged" then
		duel.commit = commit
		duel.state = "picking"
		duel.pickingAt = GetTime()
		duel.lastKind = nil -- nothing of ours to resend while we pick
		Event("picking", duel)
	elseif duel.state == "revealed" then
		ns.Comm.Send(duel.last, duel.other) -- our reveal got lost
	end
end

local function OnReveal(duel, squad)
	if duel.state == "accepted" then
		local cards = ns.DecodeSquad(squad, duel.other)
		local ok, why = ns.ValidSquad(cards)
		if not ok then
			duel.final = "X|" .. duel.id
			ns.Comm.Send(duel.final, duel.other)
			Forfeit(duel, "their squad breaks the rules: " .. tostring(why))
			return
		end
		duel.theirs = cards
		duel.reply = ("S|%s|%s|%s"):format(duel.id, duel.wire, duel.salt)
		ns.Comm.Send(duel.reply, duel.other)
		Fight(duel)
	elseif duel.reply then
		ns.Comm.Send(duel.reply, duel.other) -- our reveal got lost
	end
end

local function OnSecond(duel, squad, salt)
	if duel.state ~= "revealed" then
		return
	end
	if ns.Hash(squad .. "|" .. salt) ~= duel.commit then
		Forfeit(duel, "their squad isn't the one they picked")
		return
	end
	local cards = ns.DecodeSquad(squad, duel.other)
	local ok, why = ns.ValidSquad(cards)
	if not ok then
		Forfeit(duel, "their squad breaks the rules: " .. tostring(why))
		return
	end
	duel.theirs, duel.salt = cards, salt
	Fight(duel)
end

function Duel.Receive(msg, sender)
	local kind, rest = msg:match("^(%a)|(.*)$")
	if not kind then
		return
	end
	local fields = {}
	for field in (rest .. "|"):gmatch("([^|]*)|") do
		fields[#fields + 1] = field
	end
	if kind == "C" then
		OnChallenge(sender, fields[1], fields[2], fields[3])
		return
	end
	local duel = duels[fields[1]]
	if not duel or ns.Comm.Key(duel.other) ~= ns.Comm.Key(sender) then
		return -- not ours, or not from them
	end
	if not Active(duel) and duel.final and kind ~= "D" and kind ~= "X" then
		ns.Comm.Send(duel.final, duel.other) -- they missed our decline or cancel
		return
	end
	if kind == "A" and duel.role == "challenger" then
		OnAccept(duel, fields[2])
	elseif kind == "R" and duel.role == "opponent" then
		OnReveal(duel, fields[2])
	elseif kind == "S" and duel.role == "challenger" then
		OnSecond(duel, fields[2], fields[3])
	elseif kind == "D" and Active(duel) then
		Finish(duel, "declined", fields[2])
	elseif kind == "X" and Active(duel) then
		Finish(duel, "cancelled", "them")
	end
end

-- Timeouts and resends, every second --------------------------------------------------------

function Duel.Tick()
	local now = GetTime()
	for id, duel in pairs(duels) do
		if Active(duel) then
			-- resend our last message if its answer hasn't come
			local plan = duel.lastKind and RESEND[duel.lastKind]
			local next = plan and plan[duel.resends + 1]
			if next and now - duel.sentAt >= next and not ns.Comm.IsOffline(duel.other) then
				duel.resends = duel.resends + 1
				ns.Comm.Send(duel.last, duel.other)
			end
			if duel.state == "challenged" and now - duel.started > CHALLENGE_TIME then
				duel.final = "X|" .. duel.id -- answers an accept that comes too late
				Finish(duel, "expired", "no answer")
			elseif duel.state == "incoming" and now - duel.started > CHALLENGE_TIME then
				duel.final = ("D|%s|too late"):format(duel.id)
				Finish(duel, "expired", "too late")
			elseif duel.state == "accepted" and now - duel.acceptedAt > PICK_TIME then
				Finish(duel, "expired", "they didn't pick")
			elseif duel.state == "picking" and now - duel.pickingAt > PICK_TIME then
				Duel.Cancel(duel)
			elseif duel.state == "revealed" and now - duel.revealedAt > REVEAL_TIME then
				Forfeit(duel, "they didn't show their squad")
			end
		elseif now - duel.finished > 600 then
			duels[id] = nil
		end
	end
end

function Duel.Offline(name)
	local duel = Duel.With(name)
	if duel then
		Finish(duel, "offline", name)
	end
end

ns.Comm.Register("duel", Duel.Receive, Duel.Offline)
if C_Timer then
	C_Timer.NewTicker(1, Duel.Tick)
end

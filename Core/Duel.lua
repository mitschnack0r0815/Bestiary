local _, ns = ...

-- Duels (ARCHITECTURE.md 6), turn based (Fight.lua) and asynchronous like correspondence chess:
-- no timers, a game survives reloads, logouts and both players being offline. Games are saved
-- per character (BestiaryChar.games); the fight itself is rebuilt from the two squads, the seed
-- and the moves. One game at a time (decided): against a player or the sparring partner; a
-- challenge while you're in one is answered "busy".
--
--   1. challenger -> C|version|id|nonce        the nonce sets the 3 twists on offer
--   2. opponent   -> A|id|commit               picked a squad and banned a twist in secret;
--                                              commit = hash of both and a secret salt
--   3. challenger -> R|id|ban|squad            picks, bans and shows: the opponent is bound
--   4. opponent   -> S|id|ban|squad|salt       checked against the commit; the fight starts
--   5. either     -> M|id|n|move               move n, by the side whose turn it is
--   any           -> Q|id|step|n               "where are you?": answered with what the other
--                                              side is missing (our last message, later moves)
--   any           -> X|id|reason               declined, cancelled or resigned: the game ends
--
-- Q goes out when we log in, when we hear anything from that player, and every few minutes
-- while we wait for them, so lost whispers and offline time heal without timers. The challenger
-- is always side 1 of the fight. Against the sparring partner the same game runs locally.
local Duel = {}
ns.Duel = Duel

ns.PROTOCOL = 7 -- 3: turn based, twist bans; 4: virtual clock (attack times on the wire), Warrior;
-- 5: cast times on the wire; 6: heals without cooldown; 7: casters only cast, healers only heal,
-- waiting Healers act when an ally gets hurt. Any change to the fight rules needs a new number,
-- or two clients would play different fights.
local ASK_EVERY = 90 -- seconds between our "where are you?" while we wait on them
local ASK_GAP = 20 -- at most one per game this often
local KEEP_FINISHED = 1 -- the last finished game stays on the page

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

-- Squads on the wire ------------------------------------------------------------------------
-- "ownerLevel;npcId,stars,type,rarity,family,flags,level,health,attack,armor,spellPower,
--  attackTime,castTime (both in tenths of a second),spell,name;..."
-- Stats travel with the cards: a card is the real mob as its owner measured it. Both clients
-- build the fight from both wires, so they fight the same cards.

local TYPE_CODE = { Tank = "T", Mage = "M", Warrior = "W", Healer = "H" }
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

local function Clean(text)
	return ((text or ""):gsub("[|;,~]", ""))
end

function ns.EncodeSquad(cards, ownerLevel)
	local out = { tostring(ownerLevel or UnitLevel("player") or 1) }
	for _, card in ipairs(cards) do
		out[#out + 1] = table.concat({ card.npcId or 0, card.stars or 0, TYPE_CODE[card.type] or "T",
			RARITY_CODE[card.classification] or "n", FAMILY_CODE[card.family] or "H",
			card.player and "p" or "", card.level or 1, card.health, card.attack, card.armor,
			card.spellPower or 0, math.floor((card.attackSpeed or ns.ATTACK_SPEED) * 10 + 0.5),
			math.floor((card.castTime or ns.SPELL_TIME) * 10 + 0.5), Clean(card.spell),
			Clean(card.name) ~= "" and Clean(card.name) or "?" }, ",")
	end
	return table.concat(out, ";")
end

-- Card views from the wire and the owner's level, nil if it doesn't parse
function ns.DecodeSquad(text, owner)
	local ownerLevel = tonumber((text or ""):match("^(%d+);"))
	if not ownerLevel then
		return nil
	end
	local cards = {}
	for part in text:sub(#tostring(ownerLevel) + 2):gmatch("[^;]+") do
		local npcId, stars, kind, rarity, family, flags, level, health, attack, armor, spellPower, tenths, castTenths, spell, name =
			part:match("^(%d+),(%d),(%a),(%a),(%a),(%a*),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),(%d+),([^,]*),(.+)$")
		if not npcId or not TYPE_OF[kind] or not RARITY_OF[rarity] or not FAMILY_OF[family] or tonumber(tenths) < 5
			or tonumber(castTenths) < ns.GCD * 10 then
			return nil
		end
		local view = ns.CardView({
			npcId = tonumber(npcId), stars = tonumber(stars), type = TYPE_OF[kind],
			classification = RARITY_OF[rarity], family = FAMILY_OF[family], name = name, zone = "",
			player = flags == "p" or nil, remote = owner, level = tonumber(level), spell = spell ~= "" and spell or nil,
			attackSpeed = tonumber(tenths) / 10,
			stats = { health = tonumber(health), attack = tonumber(attack), armor = tonumber(armor),
				spellPower = tonumber(spellPower) > 0 and tonumber(spellPower) or nil, castTime = tonumber(castTenths) / 10 },
		})
		view.level, view.power = tonumber(level), tonumber(level) -- theirs, also for their own card
		if view.npcId == 0 and not view.player then
			view.npcId = nil -- a training card: no mob behind it
		end
		cards[#cards + 1] = view
	end
	return #cards > 0 and cards or nil, ownerLevel
end

-- Whether a squad from the other side keeps the rules (6.1), under its owner's cap
function ns.ValidSquad(cards, ownerLevel)
	if not cards or #cards < ns.MIN_SQUAD or #cards > ns.MAX_SQUAD then
		return false, "squad size"
	end
	local named, power, count = 0, 0, {}
	for _, card in ipairs(cards) do
		local key = card.npcId or card.name
		count[key] = (count[key] or 0) + 1
		if count[key] > (ns.CanHaveCopies(card) and ns.MAX_COPIES or 1) then
			return false, "too many copies of " .. card.name
		end
		if card.stars < 0 or card.stars > ns.MAX_STARS then
			return false, "stars"
		end
		if card.level < 1 or card.level > ns.MAX_LEVEL then
			return false, "level"
		end
		power = power + card.power
		if ns.IsNamed(card) then
			named = named + 1
		end
	end
	if named > 1 then
		return false, "more than one leader"
	elseif power > ns.PowerCap(ownerLevel) then
		return false, "over the cap"
	end
	return true
end

-- Twists: 3 on offer from the nonce; each side bans one; the twist is drawn from what's left

function Duel.Offered(nonce)
	local pool = {}
	for i, twist in ipairs(ns.TWISTS) do
		pool[i] = twist.key
	end
	local offered = {}
	for i = 1, math.min(ns.TWIST_CHOICES, #pool) do
		local pick = Number(nonce .. ":twist" .. i) % #pool + 1
		offered[i] = table.remove(pool, pick)
	end
	return offered
end

function ns.TwistByKey(key)
	for _, twist in ipairs(ns.TWISTS) do
		if twist.key == key then
			return twist
		end
	end
	return ns.TWISTS[1]
end

local function IsOffered(game, key)
	for _, offered in ipairs(game.twists) do
		if offered == key then
			return true
		end
	end
	return false
end

local function DrawTwist(game, banA, banB, salt)
	local left = {}
	for _, key in ipairs(game.twists) do
		if key ~= banA and key ~= banB then
			left[#left + 1] = key
		end
	end
	if #left == 0 then
		left = game.twists
	end
	return left[Number(game.nonce .. salt .. ":draw") % #left + 1]
end

-- Games ---------------------------------------------------------------------------------------

local function Games()
	BestiaryChar.games = BestiaryChar.games or {}
	return BestiaryChar.games
end
Duel.Games = Games

local function Event(event, game, ...)
	if Duel.OnEvent then
		Duel.OnEvent(event, game, ...)
	end
end

local function Active(game)
	return game.step ~= "over"
end
Duel.Active = Active

-- Our side in the fight (the challenger is side 1; we are side 1 against the sparring partner)
function Duel.MySide(game)
	return game.role == "opponent" and 2 or 1
end

local function Send(game, msg)
	if game.role ~= "sparring" then
		ns.Comm.Send(msg, game.other)
	end
end

-- The game with this player that's still going, if any
function Duel.With(name)
	local key = ns.Comm.Key(name)
	for _, game in pairs(Games()) do
		if Active(game) and game.role ~= "sparring" and ns.Comm.Key(game.other) == key then
			return game
		end
	end
end

-- The one game going on, if any
function Duel.Current()
	for _, game in pairs(Games()) do
		if Active(game) then
			return game
		end
	end
end

-- What the Duel page shows: the game going on, else the last finished one
function Duel.Shown()
	return Duel.Current() or Duel.List()[1]
end

function Duel.Sparring()
	for _, game in pairs(Games()) do
		if game.role == "sparring" and Active(game) then
			return game
		end
	end
end

-- All games, newest first: going ones before finished ones
function Duel.List()
	local list = {}
	for _, game in pairs(Games()) do
		list[#list + 1] = game
	end
	table.sort(list, function(a, b)
		if Active(a) ~= Active(b) then
			return Active(a)
		end
		return (a.created or 0) > (b.created or 0)
	end)
	return list
end

local function Prune()
	local finished = {}
	for id, game in pairs(Games()) do
		if not Active(game) then
			finished[#finished + 1] = game
		end
	end
	table.sort(finished, function(a, b)
		return (a.created or 0) > (b.created or 0)
	end)
	for i = KEEP_FINISHED + 1, #finished do
		Games()[finished[i].id] = nil
	end
end

-- The fight of a game, rebuilt from its squads, seed, twist and moves (cached per move count)
local states = {}

function Duel.State(game)
	if not game.seed or not game.myWire or not game.theirWire then
		return nil
	end
	local cached = states[game.id]
	if cached and cached.moves == #game.moves then
		return cached.state
	end
	local mine = ns.DecodeSquad(game.myWire)
	local theirs = ns.DecodeSquad(game.theirWire, game.other)
	if not mine or not theirs then
		return nil
	end
	local first, second = mine, theirs
	if Duel.MySide(game) == 2 then
		first, second = theirs, mine
	end
	local state, bad = ns.Fight.Replay(first, second, game.seed, game.twist, game.moves)
	if bad then
		-- a saved move that isn't legal (shouldn't happen): drop it and everything after
		for i = #game.moves, bad, -1 do
			game.moves[i] = nil
		end
	end
	states[game.id] = { moves = #game.moves, state = state }
	return state
end

-- Whose turn: "mine", "theirs", or nil when the fight isn't on
function Duel.Turn(game)
	local state = game.step == "playing" and Duel.State(game)
	if not state or not state.actor then
		return nil
	end
	return state.actor.side == Duel.MySide(game) and "mine" or "theirs"
end

-- What we're waiting for in a game, in words for the list and the page
function Duel.Status(game)
	local step = game.step
	if step == "over" then
		if game.reason then
			return game.reason
		end
		return game.winner == 1 and "won" or game.winner == 2 and "lost" or "draw"
	elseif step == "incoming" then
		return "pick your squad"
	elseif step == "challenged" then
		return "they pick first"
	elseif step == "accepted" then
		return "they pick"
	elseif step == "picking" then
		return "pick your squad"
	elseif step == "revealed" then
		return "waiting for their squad"
	elseif step == "playing" then
		return Duel.Turn(game) == "mine" and "your turn" or "their turn"
	end
	return step
end

-- A game is over: stats, stamina and card levels, once
local function Record(game)
	if game.recorded then
		return
	end
	game.recorded = true
	local state = Duel.State(game)
	if game.winner == nil then
		return -- declined, cancelled or abandoned: no result
	elseif not state then
		if game.winner == 1 then
			ns.RecordForfeit(game.role ~= "sparring" and game.other or nil) -- before the fight
		end
		return
	end
	-- Stats want us as side 1
	local mySide = Duel.MySide(game)
	local events, sides = state.events, state.sides
	if mySide == 2 then
		events = {}
		for i, event in ipairs(state.events) do
			local copy = {}
			for k, v in pairs(event) do
				copy[k] = v
			end
			if copy.side then
				copy.side = 3 - copy.side
			end
			if copy.targetSide then
				copy.targetSide = 3 - copy.targetSide
			end
			events[i] = copy
		end
		sides = { {}, {} }
		for side, units in ipairs(state.sides) do
			for slot, unit in ipairs(units) do
				local copy = {}
				for k, v in pairs(unit) do
					copy[k] = v
				end
				copy.side = 3 - side
				sides[3 - side][slot] = copy
			end
		end
	end
	ns.RecordDuel(events, game.winner, sides, game.squadName or "?", ns.TwistByKey(game.twist).name,
		game.role ~= "sparring" and game.other or nil)
	game.stamina = ns.ApplyStamina(sides[1])
	game.levelUps = {}
	for _, card in ipairs(ns.CardsPlayed((function()
		local views = {}
		for _, unit in ipairs(sides[1]) do
			views[#views + 1] = unit.card
		end
		return views
	end)())) do
		game.levelUps[#game.levelUps + 1] = card.name .. " " .. card.level
		ns.Print(("|cffffd200%s|r reached level %d."):format(card.name, card.level))
	end
end

local function Over(game, winner, reason)
	if not Active(game) then
		return
	end
	game.step = "over"
	game.winner = winner -- from our side: 1 won, 2 lost, 0 draw
	game.reason = reason
	game.finished = time()
	Record(game)
	Prune()
	Event("over", game)
end

-- After a move: is the fight over?
local function CheckEnd(game)
	local state = Duel.State(game)
	if state and state.winner then
		local mySide = Duel.MySide(game)
		Over(game, state.winner == 0 and 0 or state.winner == mySide and 1 or 2)
	end
end

-- Both squads known: the fight starts
local function Start(game)
	game.step = "playing"
	game.seed = Number(game.nonce .. game.salt)
	local challengerBan = game.role == "opponent" and game.theirBan or game.myBan
	local opponentBan = game.role == "opponent" and game.myBan or game.theirBan
	game.twist = DrawTwist(game, challengerBan, opponentBan, game.salt)
	Event("start", game)
	CheckEnd(game)
end

-- Starting --------------------------------------------------------------------------------------

local function NewGame(fields)
	local game = { moves = {}, created = time(), protocol = ns.PROTOCOL }
	for k, v in pairs(fields) do
		game[k] = v
	end
	game.twists = game.twists or Duel.Offered(game.nonce)
	Games()[game.id] = game
	return game
end

function Duel.Challenge(name)
	if not name or name == "" then
		return nil, "no player"
	elseif ns.Comm.Key(name) == ns.Comm.Key(UnitName("player")) then
		return nil, "that's you"
	elseif ns.Board and not ns.Board.IsFriend(name) then
		return nil, name .. " isn't your Bestiary friend yet (add them on the Friends tab)"
	end
	local existing = Duel.With(name)
	if existing then
		return existing
	elseif Duel.Current() then
		return nil, "you're in a duel already: finish or resign it first"
	end
	local game = NewGame({ id = Token(), role = "challenger", other = name, nonce = Token(), step = "challenged" })
	game.last = ("C|%d|%s|%s"):format(ns.PROTOCOL, game.id, game.nonce)
	Send(game, game.last)
	Event("challenged", game)
	return game
end

-- A game against the sparring partner: it picks and bans at once (seed: the game's number).
-- nil while another game is going on.
function Duel.NewSparring()
	if Duel.Current() then
		return nil, "you're in a duel already: finish or resign it first"
	end
	local game = NewGame({ id = "sparring:" .. Token(), role = "sparring", other = ns.SPARRING_NAME, nonce = Token(),
		step = "picking" })
	local seed = Number(game.nonce)
	local squads = ns.SparringSquads(seed)
	local squad = squads[seed % #squads + 1]
	game.theirName = squad.style or squad.name
	game.theirWire = ns.EncodeSquad(ns.SquadCards(squad))
	game.theirBan = game.twists[seed % #game.twists + 1]
	Event("picking", game)
	return game
end

-- We pick a squad and ban a twist (the opponent commits, the challenger shows)
function Duel.Pick(game, squad, ban)
	if not game or not IsOffered(game, ban) then
		return
	end
	local cards = ns.SquadCards(squad)
	game.squadName = squad.name
	game.myBan = ban
	game.myWire = ns.EncodeSquad(cards)
	if game.role == "opponent" and game.step == "incoming" then
		game.salt = Token()
		game.commit = ns.Hash(ban .. "|" .. game.myWire .. "|" .. game.salt)
		game.step = "accepted"
		game.last = ("A|%s|%s"):format(game.id, game.commit)
		Send(game, game.last)
		Event("accepted", game)
	elseif game.role == "challenger" and game.step == "picking" then
		game.step = "revealed"
		game.last = ("R|%s|%s|%s"):format(game.id, ban, game.myWire)
		Send(game, game.last)
		Event("revealed", game)
	elseif game.role == "sparring" and game.step == "picking" then
		game.salt = Token()
		Start(game)
	end
end

-- Ends a game from our side: declined, cancelled or resigned (a resign is a loss)
function Duel.Quit(game)
	if not game or not Active(game) then
		return
	end
	local reason = game.step == "incoming" and "declined" or game.step == "playing" and "resigned" or "cancelled"
	game.final = ("X|%s|%s"):format(game.id, reason)
	Send(game, game.final)
	Over(game, reason == "resigned" and 2 or nil, "you " .. reason)
end

-- Our move: checked, saved, sent
function Duel.Move(game, move)
	local state = Duel.State(game)
	if not state or Duel.Turn(game) ~= "mine" or not ns.Fight.Legal(state, move) then
		return false
	end
	local text = ns.Fight.Encode(move)
	game.moves[#game.moves + 1] = text
	game.updated = time()
	Send(game, ("M|%s|%d|%s"):format(game.id, #game.moves, text))
	Event("move", game, #game.moves)
	CheckEnd(game)
	return true
end

-- The sparring partner's move, if it's its turn
function Duel.RunAI(game)
	if game.role ~= "sparring" or Duel.Turn(game) ~= "theirs" then
		return false
	end
	local move = ns.Fight.AI(Duel.State(game))
	if not move then
		return false
	end
	game.moves[#game.moves + 1] = ns.Fight.Encode(move)
	Event("move", game, #game.moves)
	CheckEnd(game)
	return true
end

-- Asking and answering "where are you?" ---------------------------------------------------------

local function Ask(game, force)
	if game.role == "sparring" or not Active(game) then
		return
	end
	local now = GetTime()
	if not force and game.askedAt and now - game.askedAt < ASK_GAP then
		return
	end
	game.askedAt = now
	if game.step == "challenged" then
		ns.Comm.Send(game.last, game.other) -- they may never have got the challenge
		return
	end
	ns.Comm.Send(("Q|%s|%s|%d"):format(game.id, game.step, #game.moves), game.other)
end

local function Answer(game, theirStep, theirMoves)
	if game.final then
		ns.Comm.Send(game.final, game.other) -- they missed our decline, cancel or resign
		return
	end
	if game.step == "challenged" or game.step == "accepted" or game.step == "revealed" then
		ns.Comm.Send(game.last, game.other) -- our challenge, commit or squad
	elseif game.step == "playing" or game.step == "over" then
		if game.role == "opponent" and (theirStep == "revealed" or theirStep == "picking") then
			ns.Comm.Send(game.last, game.other) -- our squad and salt (S)
		elseif game.role == "challenger" and theirStep == "accepted" then
			ns.Comm.Send(game.last, game.other) -- our squad (R)
		end
		for n = (theirMoves or 0) + 1, #game.moves do
			ns.Comm.Send(("M|%s|%d|%s"):format(game.id, n, game.moves[n]), game.other)
		end
		if (theirMoves or 0) > #game.moves then
			Ask(game) -- they're ahead: we're missing moves
		end
	end
end

-- Receiving ---------------------------------------------------------------------------------------

local function OnChallenge(sender, version, id, nonce)
	local existing = Games()[id]
	if existing then
		Answer(existing)
		return
	end
	if tonumber(version) ~= ns.PROTOCOL then
		ns.Comm.Send(("X|%s|needs Bestiary protocol %d"):format(id, ns.PROTOCOL), sender)
		return
	elseif ns.Board and not ns.Board.IsFriend(sender) then
		ns.Comm.Send(("X|%s|not friends"):format(id), sender)
		return
	end
	-- Both challenged each other: the one whose name sorts first stays challenger
	local mine = Duel.With(sender)
	if mine and mine.role == "challenger" and mine.step == "challenged" then
		if ns.Comm.Key(UnitName("player")) < ns.Comm.Key(sender) then
			return -- they'll take ours
		end
		Games()[mine.id] = nil -- take theirs
	elseif mine then
		ns.Comm.Send(("X|%s|already in a game with you"):format(id), sender)
		return
	elseif Duel.Current() then
		ns.Comm.Send(("X|%s|busy in another duel"):format(id), sender) -- one game at a time
		return
	end
	local game = NewGame({ id = id, role = "opponent", other = sender, nonce = nonce, step = "incoming" })
	Event("incoming", game)
end

local function OnCommit(game, commit)
	if game.role ~= "challenger" then
		return
	end
	if game.step == "challenged" then
		game.commit = commit
		game.step = "picking"
		Event("picking", game)
	elseif game.step == "revealed" then
		Send(game, game.last) -- our squad got lost
	end
end

local function OnShow(game, ban, wire)
	if game.role ~= "opponent" then
		return
	end
	if game.step ~= "accepted" then
		if game.step == "playing" or game.step == "over" then
			Send(game, game.last) -- our S got lost
		end
		return
	end
	local cards, level = ns.DecodeSquad(wire, game.other)
	local ok, why = ns.ValidSquad(cards, level)
	if not IsOffered(game, ban) then
		ok, why = false, "a twist that isn't on offer"
	end
	if not ok then
		game.final = ("X|%s|squad breaks the rules"):format(game.id)
		Send(game, game.final)
		Over(game, 1, "they forfeit: their squad breaks the rules (" .. tostring(why) .. ")")
		return
	end
	game.theirBan, game.theirWire = ban, wire
	game.last = ("S|%s|%s|%s|%s"):format(game.id, game.myBan, game.myWire, game.salt)
	Send(game, game.last)
	Start(game)
end

local function OnSecond(game, ban, wire, salt)
	if game.role ~= "challenger" or game.step ~= "revealed" then
		return
	end
	if ns.Hash(ban .. "|" .. wire .. "|" .. salt) ~= game.commit then
		Over(game, 1, "they forfeit: their squad isn't the one they picked")
		return
	end
	local cards, level = ns.DecodeSquad(wire, game.other)
	local ok, why = ns.ValidSquad(cards, level)
	if not IsOffered(game, ban) then
		ok, why = false, "a twist that isn't on offer"
	end
	if not ok then
		Over(game, 1, "they forfeit: their squad breaks the rules (" .. tostring(why) .. ")")
		return
	end
	game.theirBan, game.theirWire, game.salt = ban, wire, salt
	Start(game)
end

local function OnMove(game, n, text)
	n = tonumber(n)
	if game.step ~= "playing" or not n then
		return
	end
	if n <= #game.moves then
		return -- had it
	elseif n > #game.moves + 1 then
		Ask(game) -- one got lost
		return
	end
	local state = Duel.State(game)
	local move = ns.Fight.Decode(text)
	if not state or Duel.Turn(game) ~= "theirs" or not move or not ns.Fight.Legal(state, move) then
		game.final = ("X|%s|move not legal"):format(game.id)
		Send(game, game.final)
		Over(game, 1, "they forfeit: a move that isn't legal")
		return
	end
	game.moves[#game.moves + 1] = text
	game.updated = time()
	Event("move", game, #game.moves)
	CheckEnd(game)
end

function Duel.Receive(msg, sender)
	-- Anything from a player we have a game with: they're online, catch up
	for _, game in pairs(Games()) do
		if Active(game) and game.role ~= "sparring" and ns.Comm.Key(game.other) == ns.Comm.Key(sender)
			and (not game.askedAt or GetTime() - game.askedAt > 60) then
			Ask(game)
		end
	end
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
	local game = Games()[fields[1]]
	if kind ~= "A" and kind ~= "R" and kind ~= "S" and kind ~= "M" and kind ~= "Q" and kind ~= "X" then
		return -- not ours (the board's)
	end
	if not game then
		if kind == "Q" or kind == "M" then
			ns.Comm.Send(("X|%s|game unknown"):format(fields[1]), sender) -- lost on our side
		end
		return
	end
	if ns.Comm.Key(game.other) ~= ns.Comm.Key(sender) then
		return -- not from them
	end
	if kind == "Q" then
		Answer(game, fields[2], tonumber(fields[3]))
	elseif not Active(game) then
		if game.final and kind ~= "X" then
			ns.Comm.Send(game.final, game.other)
		end
	elseif kind == "A" then
		OnCommit(game, fields[2])
	elseif kind == "R" then
		OnShow(game, fields[2], fields[3])
	elseif kind == "S" then
		OnSecond(game, fields[2], fields[3], fields[4])
	elseif kind == "M" then
		OnMove(game, fields[2], fields[3])
	elseif kind == "X" then
		local reason = fields[2] or "ended"
		if reason == "resigned" then
			Over(game, 1, "they resigned")
		else
			Over(game, nil, "they " .. (reason == "declined" and "declined" or reason == "cancelled" and "cancelled" or ("ended it: " .. reason)))
		end
	end
end

ns.Comm.Register("duel", Duel.Receive)

-- Catching up: after login, and every minute for games where we wait on them
local function Tick()
	if not BestiaryChar then
		return
	end
	local now = GetTime()
	for _, game in pairs(Games()) do
		local waiting = Active(game) and game.role ~= "sparring" and (game.step == "challenged" or game.step == "accepted"
			or game.step == "revealed" or Duel.Turn(game) == "theirs")
		if waiting and not ns.Comm.IsOffline(game.other) and (not game.askedAt or now - game.askedAt > ASK_EVERY) then
			Ask(game)
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	C_Timer.After(8, function()
		for _, game in pairs(Games()) do
			game.askedAt = nil -- GetTime() starts over after a restart
			if Active(game) and game.protocol ~= ns.PROTOCOL then
				-- from before an update that changed the fight: it can't go on
				game.final = ("X|%s|Bestiary was updated"):format(game.id)
				Send(game, game.final)
				Over(game, nil, "ended: Bestiary was updated")
			elseif Active(game) then
				Ask(game, true)
			end
		end
	end)
	C_Timer.NewTicker(60, Tick)
end)

-- Stamina after a duel (6.3): fighters lose health lost in % x 0.6, the others rest. units: our
-- side of the fight. Returns the loss per slot.
function ns.ApplyStamina(units)
	local fought, losses = {}, {}
	for _, unit in ipairs(units) do
		local card = unit.card.npcId and BestiaryChar.cards[unit.card.npcId]
		local loss = math.floor((1 - unit.hp / unit.maxHp) * 100 * 0.6 + 0.5)
		losses[unit.slot] = loss
		if card then
			fought[card] = math.max(fought[card] or 0, loss) -- copies share stamina: counted once
		end
	end
	for card, loss in pairs(fought) do
		card.stamina = math.max(0, (card.stamina or 100) - loss)
		if card.stamina == 0 then
			card.exhausted = 2
		end
	end
	for _, card in pairs(BestiaryChar.cards) do
		if not fought[card] then
			if card.exhausted then
				card.exhausted = card.exhausted - 1
				if card.exhausted == 0 then
					card.exhausted = nil
					card.stamina = 100
				end
			else
				card.stamina = math.min(100, (card.stamina or 100) + 25)
			end
		end
	end
	return losses
end

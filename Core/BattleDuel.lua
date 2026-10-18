local _, ns = ...

-- Battles between players (ARCHITECTURE.md 5.5), like duels asynchronous with no timers: a game
-- survives reloads, logouts and both players being offline. Saved per character
-- (BestiaryChar.battles); the battle itself is rebuilt from the two teams, the two leads, the seed
-- and the moves (Battle.lua). One battle at a time (duels are separate). Both pick a team and
-- its lead blind (decided: no team preview); the page only ever shows the cards on the field.
--
--   1. challenger -> Bc|version|id|nonce
--   2. opponent   -> Ba|id|commit               picked team and lead in secret: hash with a salt
--   3. challenger -> Bt|id|team|lead            shows them: the opponent is bound
--   4. opponent   -> Bu|id|team|lead|salt       shows them (checked against the commit): it starts
--   5. either     -> Bm|id|n|move               move n, by whoever the battle expects
--   any           -> Bq|id|step|n               "where are you?": answered with what's missing
--   any           -> Bx|id|reason               declined, cancelled or resigned: it ends
--
-- Two letters, so the duel's and the board's handlers leave these alone. The challenger is side 1.
-- Against the sparring partner the same game runs locally. Both clients need both teams to
-- rebuild the battle, so a team is hidden by the page, not on the wire.
local Battles = {}
ns.Battles = Battles

ns.BATTLE_PROTOCOL = 3 -- 2: team and lead picked together, no preview, no power cap; 3: teams of 3. Any change to the battle rules needs a new number
local ASK_EVERY = 90
local ASK_GAP = 20
local KEEP_FINISHED = 1

local function Number(text)
	return tonumber(ns.Hash(text):sub(1, 7), 16)
end

local function Token()
	return ("%06x%06x"):format(math.random(0, 16777215), math.random(0, 16777215))
end

local function Games()
	BestiaryChar.battles = BestiaryChar.battles or {}
	return BestiaryChar.battles
end
Battles.Games = Games

local function Event(event, game, ...)
	if Battles.OnEvent then
		Battles.OnEvent(event, game, ...)
	end
end

local function Active(game)
	return game.step ~= "over"
end
Battles.Active = Active

function Battles.MySide(game)
	return game.role == "opponent" and 2 or 1
end

-- A setup message: sent, and kept so a catch-up can send it again
local function Send(game, msg)
	game.sent = game.sent or {}
	game.sent[#game.sent + 1] = msg
	if game.role ~= "sparring" then
		ns.Comm.Send(msg, game.other)
	end
end

local function Whisper(game, msg)
	if game.role ~= "sparring" then
		ns.Comm.Send(msg, game.other)
	end
end

function Battles.With(name)
	local key = ns.Comm.Key(name)
	for _, game in pairs(Games()) do
		if Active(game) and game.role ~= "sparring" and ns.Comm.Key(game.other) == key then
			return game
		end
	end
end

function Battles.Current()
	for _, game in pairs(Games()) do
		if Active(game) then
			return game
		end
	end
end

function Battles.List()
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

-- What the Battle page shows: the game going on, else the last finished one
function Battles.Shown()
	return Battles.Current() or Battles.List()[1]
end

local function Prune()
	local finished = {}
	for _, game in pairs(Games()) do
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

-- Teams of a game as card views: mine, theirs (nil until known)
local teams = {} -- game id -> { mineWire, theirWire, mine, theirs }

function Battles.Teams(game)
	local cached = teams[game.id]
	if not cached or cached.mineWire ~= game.myWire or cached.theirWire ~= game.theirWire then
		cached = { mineWire = game.myWire, theirWire = game.theirWire,
			mine = game.myWire and ns.DecodeSquad(game.myWire) or nil,
			theirs = game.theirWire and ns.DecodeSquad(game.theirWire, game.other) or nil }
		teams[game.id] = cached
	end
	return cached.mine, cached.theirs
end

-- The battle of a game, rebuilt from teams, leads, seed and moves (cached per move count)
local states = {}

function Battles.State(game)
	if not game.seed or not game.myLead or not game.theirLead then
		return nil
	end
	local cached = states[game.id]
	if cached and cached.moves == #game.moves then
		return cached.state
	end
	local mine, theirs = Battles.Teams(game)
	if not mine or not theirs then
		return nil
	end
	local first, second, leadA, leadB = mine, theirs, game.myLead, game.theirLead
	if Battles.MySide(game) == 2 then
		first, second, leadA, leadB = theirs, mine, game.theirLead, game.myLead
	end
	local state, bad = ns.Battle.Replay(first, second, leadA, leadB, game.seed, game.moves)
	if bad then
		for i = #game.moves, bad, -1 do
			game.moves[i] = nil -- a saved move that isn't legal (shouldn't happen)
		end
	end
	states[game.id] = { moves = #game.moves, state = state }
	return state
end

-- Whose move: "mine", "theirs", or nil when the battle isn't on; and the phase ("act", "send")
function Battles.Turn(game)
	local state = game.step == "playing" and Battles.State(game)
	if not state then
		return nil
	end
	local side, phase = ns.Battle.Expecting(state)
	if not side then
		return nil
	end
	return side == Battles.MySide(game) and "mine" or "theirs", phase
end

function Battles.Status(game)
	local step = game.step
	if step == "over" then
		return game.reason or (game.winner == 1 and "won" or game.winner == 2 and "lost" or "draw")
	elseif step == "incoming" or step == "picking" then
		return "pick your team"
	elseif step == "challenged" then
		return "they pick first"
	elseif step == "accepted" or step == "revealed" then
		return "they pick"
	elseif step == "playing" then
		local turn, phase = Battles.Turn(game)
		if turn == "mine" then
			return phase == "send" and "send a card in" or "your turn"
		end
		return "their turn"
	end
	return step
end

-- Results ---------------------------------------------------------------------------------------

local function RecordResult(game)
	BestiaryChar.battleRecord = BestiaryChar.battleRecord or { wins = 0, losses = 0, draws = 0, vs = {} }
	local record = BestiaryChar.battleRecord
	local key = game.winner == 1 and "wins" or game.winner == 2 and "losses" or "draws"
	record[key] = record[key] + 1
	if game.role ~= "sparring" then
		local who = ns.Comm.Key(game.other)
		record.vs[who] = record.vs[who] or { wins = 0, losses = 0, draws = 0 }
		record.vs[who][key] = record.vs[who][key] + 1
	end
end

function Battles.RecordAgainst(name)
	local record = BestiaryChar and BestiaryChar.battleRecord
	return record and name and record.vs[ns.Comm.Key(name)]
end

-- A game is over: the result and our cards' XP, once
local function Record(game)
	if game.recorded then
		return
	end
	game.recorded = true
	if game.winner == nil then
		return -- declined, cancelled or abandoned
	end
	RecordResult(game)
	local state = Battles.State(game)
	if not state then
		return -- a forfeit before the battle: no XP
	end
	game.xp = ns.GiveBattleXp(state.sides[Battles.MySide(game)].units, game.winner == 1)
	for _, result in ipairs(game.xp) do
		if result.level then
			ns.Print(("|cffffd200%s|r reached level %d."):format(result.name, result.level))
		end
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

local function CheckEnd(game)
	local state = Battles.State(game)
	if state and state.winner then
		local mySide = Battles.MySide(game)
		Over(game, state.winner == 0 and 0 or state.winner == mySide and 1 or 2)
	end
end

local function Start(game)
	game.step = "playing"
	game.seed = Number(game.nonce .. game.salt)
	Event("start", game)
	CheckEnd(game)
end

-- Starting ----------------------------------------------------------------------------------------

local function NewGame(fields)
	local game = { moves = {}, created = time(), protocol = ns.BATTLE_PROTOCOL, sent = {} }
	for k, v in pairs(fields) do
		game[k] = v
	end
	Games()[game.id] = game
	return game
end

function Battles.Challenge(name)
	if not name or name == "" then
		return nil, "no player"
	elseif ns.Comm.Key(name) == ns.Comm.Key(UnitName("player")) then
		return nil, "that's you"
	elseif ns.Board and not ns.Board.IsFriend(name) then
		return nil, name .. " isn't your Bestiary friend yet (add them on the Friends tab)"
	end
	local existing = Battles.With(name)
	if existing then
		return existing
	elseif Battles.Current() then
		return nil, "you're in a battle already: finish or resign it first"
	end
	local game = NewGame({ id = Token(), role = "challenger", other = name, nonce = Token(), step = "challenged" })
	Send(game, ("Bc|%d|%s|%s"):format(ns.BATTLE_PROTOCOL, game.id, game.nonce))
	Event("challenged", game)
	return game
end

function Battles.NewSparring()
	if Battles.Current() then
		return nil, "you're in a battle already: finish or resign it first"
	end
	local game = NewGame({ id = "sparring:" .. Token(), role = "sparring", other = ns.SPARRING_NAME, nonce = Token(),
		step = "picking" })
	local cards, style = ns.SparringTeam(Number(game.nonce))
	game.theirName = style
	game.theirWire = ns.EncodeSquad(cards)
	Event("picking", game)
	return game
end

-- We pick a team and the card it leads with
function Battles.Pick(game, team, lead)
	local cards = team and ns.TeamCards(team)
	if not game or not ns.TeamReady(team) or not lead or not cards[lead] then
		return
	end
	game.teamName = team.name
	game.myWire = ns.EncodeSquad(cards)
	game.myLead = lead
	if game.role == "opponent" and game.step == "incoming" then
		game.salt = Token()
		game.commit = ns.Hash(game.myWire .. "|" .. lead .. "|" .. game.salt)
		game.step = "accepted"
		Send(game, ("Ba|%s|%s"):format(game.id, game.commit))
		Event("accepted", game)
	elseif game.role == "challenger" and game.step == "picking" then
		game.step = "revealed"
		Send(game, ("Bt|%s|%s|%d"):format(game.id, game.myWire, lead))
		Event("revealed", game)
	elseif game.role == "sparring" and game.step == "picking" then
		local _, theirs = Battles.Teams(game)
		game.theirLead = ns.Battle.AILead(theirs or {})
		game.salt = Token()
		Start(game)
	end
end

function Battles.Quit(game)
	if not game or not Active(game) then
		return
	end
	local reason = game.step == "incoming" and "declined" or game.step == "playing" and "resigned" or "cancelled"
	game.final = ("Bx|%s|%s"):format(game.id, reason)
	Whisper(game, game.final)
	Over(game, reason == "resigned" and 2 or nil, "you " .. reason)
end

function Battles.Move(game, move)
	local state = Battles.State(game)
	if not state or Battles.Turn(game) ~= "mine" or not ns.Battle.Legal(state, Battles.MySide(game), move) then
		return false
	end
	game.moves[#game.moves + 1] = move
	game.updated = time()
	Whisper(game, ("Bm|%s|%d|%s"):format(game.id, #game.moves, move))
	Event("move", game, #game.moves)
	CheckEnd(game)
	return true
end

function Battles.RunAI(game)
	if game.role ~= "sparring" or Battles.Turn(game) ~= "theirs" then
		return false
	end
	local state = Battles.State(game)
	local move = ns.Battle.AI(state)
	if not move or not ns.Battle.Legal(state, 2, move) then
		return false
	end
	game.moves[#game.moves + 1] = move
	Event("move", game, #game.moves)
	CheckEnd(game)
	return true
end

-- Catching up --------------------------------------------------------------------------------------

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
		ns.Comm.Send(game.sent[1], game.other) -- they may never have got the challenge
		return
	end
	ns.Comm.Send(("Bq|%s|%s|%d"):format(game.id, game.step, #game.moves), game.other)
end

-- They asked where we are: everything we sent in the setup (each side ignores what it had), then
-- the moves they lack
local function Answer(game, theirMoves)
	if game.final then
		ns.Comm.Send(game.final, game.other)
		return
	end
	for _, msg in ipairs(game.sent or {}) do
		ns.Comm.Send(msg, game.other)
	end
	for n = (theirMoves or 0) + 1, #game.moves do
		ns.Comm.Send(("Bm|%s|%d|%s"):format(game.id, n, game.moves[n]), game.other)
	end
	if (theirMoves or 0) > #game.moves then
		Ask(game)
	end
end

-- Receiving -----------------------------------------------------------------------------------------

local function Forfeit(game, why)
	game.final = ("Bx|%s|%s"):format(game.id, why)
	Whisper(game, game.final)
	Over(game, 1, "they forfeit: " .. why)
end

local function OnChallenge(sender, version, id, nonce)
	local existing = Games()[id]
	if existing then
		Answer(existing)
		return
	end
	if tonumber(version) ~= ns.BATTLE_PROTOCOL then
		ns.Comm.Send(("Bx|%s|needs Bestiary battle protocol %d"):format(id, ns.BATTLE_PROTOCOL), sender)
		return
	elseif ns.Board and not ns.Board.IsFriend(sender) then
		ns.Comm.Send(("Bx|%s|not friends"):format(id), sender)
		return
	end
	local mine = Battles.With(sender)
	if mine and mine.role == "challenger" and mine.step == "challenged" then
		if ns.Comm.Key(UnitName("player")) < ns.Comm.Key(sender) then
			return -- both challenged: the one whose name sorts first stays challenger
		end
		Games()[mine.id] = nil
	elseif mine then
		ns.Comm.Send(("Bx|%s|already in a battle with you"):format(id), sender)
		return
	elseif Battles.Current() then
		ns.Comm.Send(("Bx|%s|busy in another battle"):format(id), sender)
		return
	end
	local game = NewGame({ id = id, role = "opponent", other = sender, nonce = nonce, step = "incoming" })
	Event("incoming", game)
end

-- challenger: their commit
local function OnCommit(game, commit)
	if game.role == "challenger" and game.step == "challenged" then
		game.commit = commit
		game.step = "picking"
		Event("picking", game)
	end
end

local function CheckTeam(game, wire, lead)
	local cards, level = ns.DecodeSquad(wire, game.other)
	local ok, why = ns.ValidTeam(cards, level)
	lead = tonumber(lead)
	if ok and (not lead or not cards[lead]) then
		ok, why = false, "a lead that isn't in the team"
	end
	return ok, why, lead
end

-- opponent: the challenger's team and lead; we show ours and it starts
local function OnTeam(game, wire, lead)
	if game.role ~= "opponent" or game.step ~= "accepted" then
		return
	end
	local ok, why
	ok, why, lead = CheckTeam(game, wire, lead)
	if not ok then
		Forfeit(game, "team breaks the rules (" .. tostring(why) .. ")")
		return
	end
	game.theirWire, game.theirLead = wire, lead
	Send(game, ("Bu|%s|%s|%d|%s"):format(game.id, game.myWire, game.myLead, game.salt))
	Start(game)
end

-- challenger: the opponent's team and lead, checked against its commit
local function OnSecondTeam(game, wire, lead, salt)
	if game.role ~= "challenger" or game.step ~= "revealed" then
		return
	end
	if ns.Hash(wire .. "|" .. tostring(lead) .. "|" .. tostring(salt)) ~= game.commit then
		Over(game, 1, "they forfeit: their team isn't the one they picked")
		return
	end
	local ok, why
	ok, why, lead = CheckTeam(game, wire, lead)
	if not ok then
		Forfeit(game, "team breaks the rules (" .. tostring(why) .. ")")
		return
	end
	game.theirWire, game.theirLead, game.salt = wire, lead, salt
	Start(game)
end

local function OnMove(game, n, move)
	n = tonumber(n)
	if game.step ~= "playing" or not n then
		return
	end
	if n <= #game.moves then
		return
	elseif n > #game.moves + 1 then
		Ask(game)
		return
	end
	local state = Battles.State(game)
	if not state or Battles.Turn(game) ~= "theirs" or not ns.Battle.Legal(state, 3 - Battles.MySide(game), move) then
		Forfeit(game, "a move that isn't legal")
		return
	end
	game.moves[#game.moves + 1] = move
	game.updated = time()
	Event("move", game, #game.moves)
	CheckEnd(game)
end

local KINDS = { Bc = true, Ba = true, Bt = true, Bu = true, Bm = true, Bq = true, Bx = true }

function Battles.Receive(msg, sender)
	for _, game in pairs(Games()) do
		if Active(game) and game.role ~= "sparring" and ns.Comm.Key(game.other) == ns.Comm.Key(sender)
			and (not game.askedAt or GetTime() - game.askedAt > 60) then
			Ask(game) -- anything from them: they're online, catch up
		end
	end
	local kind, rest = msg:match("^(B%a)|(.*)$")
	if not kind or not KINDS[kind] then
		return
	end
	local fields = {}
	for field in (rest .. "|"):gmatch("([^|]*)|") do
		fields[#fields + 1] = field
	end
	if kind == "Bc" then
		OnChallenge(sender, fields[1], fields[2], fields[3])
		return
	end
	local game = Games()[fields[1]]
	if not game then
		if kind == "Bq" or kind == "Bm" then
			ns.Comm.Send(("Bx|%s|game unknown"):format(fields[1]), sender)
		end
		return
	end
	if ns.Comm.Key(game.other) ~= ns.Comm.Key(sender) then
		return
	end
	if kind == "Bq" then
		Answer(game, tonumber(fields[3]))
	elseif not Active(game) then
		if game.final and kind ~= "Bx" then
			ns.Comm.Send(game.final, game.other)
		end
	elseif kind == "Ba" then
		OnCommit(game, fields[2])
	elseif kind == "Bt" then
		OnTeam(game, fields[2], fields[3])
	elseif kind == "Bu" then
		OnSecondTeam(game, fields[2], fields[3], fields[4])
	elseif kind == "Bm" then
		OnMove(game, fields[2], fields[3])
	elseif kind == "Bx" then
		local reason = fields[2] or "ended"
		if reason == "resigned" then
			Over(game, 1, "they resigned")
		else
			Over(game, nil, "they " .. (reason == "declined" and "declined" or reason == "cancelled" and "cancelled" or ("ended it: " .. reason)))
		end
	end
end

ns.Comm.Register("battle", Battles.Receive)

local function Tick()
	if not BestiaryChar then
		return
	end
	local now = GetTime()
	for _, game in pairs(Games()) do
		local waiting = Active(game) and game.role ~= "sparring" and (game.step == "challenged" or game.step == "accepted"
			or game.step == "revealed" or Battles.Turn(game) == "theirs")
		if waiting and not ns.Comm.IsOffline(game.other) and (not game.askedAt or now - game.askedAt > ASK_EVERY) then
			Ask(game)
		end
	end
end
Battles.Tick = Tick

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function()
	C_Timer.After(8, function()
		for _, game in pairs(Games()) do
			game.askedAt = nil
			if Active(game) and game.protocol ~= ns.BATTLE_PROTOCOL then
				game.final = ("Bx|%s|Bestiary was updated"):format(game.id)
				Whisper(game, game.final)
				Over(game, nil, "ended: Bestiary was updated")
			elseif Active(game) then
				Ask(game, true)
			end
		end
	end)
	C_Timer.NewTicker(60, Tick)
end)

local _, ns = ...

-- Bestiary friends and the board. Friends are players who both agreed (a request and an
-- answer: F|ask, F|ok or F|no); only friends duel each other and share the board. The board:
-- short posts shared with your friends. Saved account wide in BestiaryAccount.board. Every post version has the
-- server time it was written (modified) and the newest version wins; only its author can edit
-- or delete it (deleting leaves a marker so the deletion syncs too). Posts older than KEEP_DAYS
-- are dropped everywhere by the same rule.
--
-- Nothing syncs on its own (decided): posts, edits and deletes stay here until you press Sync
-- now. Then, with as few whispers as possible (messages only from and to friends):
--   H|hash|since|reply|stamp                    to each friend: a fingerprint of our board
--                                               (taken at "stamp") and when we were last in
--                                               sync with them. Same fingerprint: no answer
--                                               (1 whisper). Different: they send what they
--                                               got after "since" and answer with their own H
--                                               (reply=1), and we send what they're missing
--                                               the same way, so one click syncs both sides.
--   P|id|created|modified|deleted|author|text   post versions, several joined by "||"
-- "got" is when this client stored a version (server time), so posts relayed from a third
-- friend are found too. Anything lost heals on the next sync.
local Board = {}
ns.Board = Board

local KEEP_DAYS = 60
local MAX_TEXT = 200

local function Now()
	return GetServerTime and GetServerTime() or time()
end

local function Data()
	BestiaryAccount.board = BestiaryAccount.board or { posts = {}, contacts = {}, seq = 0 }
	for _, contact in pairs(BestiaryAccount.board.contacts) do
		contact.state = contact.state or "friend" -- from before friend requests
	end
	return BestiaryAccount.board
end

local function Key(name)
	return ns.Comm.Key(name)
end

local function Me()
	return UnitName("player")
end

local function Changed()
	if Board.OnChange then
		Board.OnChange()
	end
end

-- Posts still kept (not too old)
local function Kept(post, now)
	return now - post.modified <= KEEP_DAYS * 86400
end

local function Prune()
	local now = Now()
	local posts = Data().posts
	for id, post in pairs(posts) do
		if not Kept(post, now) then
			posts[id] = nil
		end
	end
end

-- Fingerprint of the board: every kept post's id and version
function Board.Hash()
	local now, list = Now(), {}
	for id, post in pairs(Data().posts) do
		if Kept(post, now) then
			list[#list + 1] = id .. ":" .. post.modified .. (post.deleted and "x" or "")
		end
	end
	table.sort(list)
	return ns.Hash(table.concat(list, ";")), #list
end

local function Clean(text)
	text = tostring(text or ""):gsub("[|\n\r]", " "):sub(1, MAX_TEXT)
	return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function Wire(post)
	return ("P|%s|%d|%d|%d|%s|%s"):format(post.id, post.created, post.modified, post.deleted and 1 or 0,
		post.author, post.text)
end

-- Friends ------------------------------------------------------------------------------------
-- contacts[key] = { name, lastSync, state }: state "friend" (both agreed), "asked" (we asked,
-- no answer yet) or "incoming" (they asked us). Only friends duel and share the board.
local MAX_INCOMING = 10 -- unanswered requests kept at most (no spamming us full)

-- Everyone on the list (friends and open requests), by name
function Board.Contacts()
	local list = {}
	for _, contact in pairs(Data().contacts) do
		list[#list + 1] = contact
	end
	table.sort(list, function(a, b)
		if (a.state == "friend") ~= (b.state == "friend") then
			return a.state == "friend"
		end
		return a.name:lower() < b.name:lower()
	end)
	return list
end

local function Entry(name)
	return name and Data().contacts[Key(name)]
end

-- A confirmed friend's entry
local function Contact(name)
	local contact = Entry(name)
	return contact and contact.state == "friend" and contact or nil
end

function Board.IsFriend(name)
	return Contact(name) ~= nil
end
Board.IsContact = Board.IsFriend

local function Befriend(contact)
	contact.state = "friend"
	contact.lastSync = contact.lastSync or 0
	Changed()
	if Board.OnFriend then
		Board.OnFriend(contact.name)
	end
end

-- Ask a player to be friends (or say yes to their request)
function Board.AddFriend(name)
	name = name and name:gsub("%s", "")
	if not name or name == "" or Key(name) == Key(Me()) then
		return false
	end
	local contacts = Data().contacts
	local contact = contacts[Key(name)]
	if contact and contact.state == "incoming" then
		Board.AcceptFriend(name)
	elseif not contact then
		contacts[Key(name)] = { name = name, lastSync = 0, state = "asked" }
		ns.Comm.Send("F|ask", name)
		Changed()
	elseif contact.state == "asked" then
		ns.Comm.Send("F|ask", contact.name) -- ask again
	end
	return true
end
Board.AddContact = Board.AddFriend

function Board.AcceptFriend(name)
	local contact = Entry(name)
	if contact and contact.state == "incoming" then
		ns.Comm.Send("F|ok", contact.name)
		Befriend(contact)
	end
end

function Board.DeclineFriend(name)
	local contact = Entry(name)
	if contact and contact.state == "incoming" then
		ns.Comm.Send("F|no", contact.name)
		Data().contacts[Key(name)] = nil
		Changed()
	end
end

-- Removing is only on our side: they stay on theirs, but we don't answer them any more
function Board.RemoveContact(name)
	Data().contacts[Key(name)] = nil
	Changed()
end
Board.RemoveFriend = Board.RemoveContact

local function OnFriendMessage(sender, what)
	local contacts = Data().contacts
	local contact = contacts[Key(sender)]
	if what == "ask" then
		if contact and (contact.state == "asked" or contact.state == "friend") then
			-- we asked too, or they lost our yes: yes
			ns.Comm.Send("F|ok", contact.name)
			if contact.state ~= "friend" then
				Befriend(contact)
			end
		elseif not contact then
			local open = 0
			for _, other in pairs(contacts) do
				if other.state == "incoming" then
					open = open + 1
				end
			end
			if open >= MAX_INCOMING then
				return
			end
			contacts[Key(sender)] = { name = sender, lastSync = 0, state = "incoming" }
			Changed()
			if Board.OnRequest then
				Board.OnRequest(sender)
			end
		end
	elseif what == "ok" and contact and contact.state == "asked" then
		Befriend(contact)
	elseif what == "no" and contact and contact.state == "asked" then
		contacts[Key(sender)] = nil
		Changed()
		if Board.OnDeclined then
			Board.OnDeclined(sender)
		end
	end
end

-- Posting ------------------------------------------------------------------------------------


function Board.Post(text)
	text = Clean(text)
	if text == "" then
		return
	end
	local data, now = Data(), Now()
	data.seq = data.seq + 1
	local post = { id = ("%s-%d-%d"):format(Key(Me()), now, data.seq), author = Me(), created = now,
		modified = now, got = now, text = text }
	data.posts[post.id] = post
	Changed()
	return post
end

local function Own(post)
	return post and Key(post.author) == Key(Me())
end
Board.Own = Own

function Board.Edit(id, text)
	local post = Data().posts[id]
	text = Clean(text)
	if not Own(post) or post.deleted or text == "" then
		return
	end
	local now = Now()
	post.text, post.modified, post.got = text, math.max(now, post.modified + 1), now
	Changed()
end

function Board.Delete(id)
	local post = Data().posts[id]
	if not Own(post) or post.deleted then
		return
	end
	local now = Now()
	post.text, post.deleted, post.modified, post.got = "", true, math.max(now, post.modified + 1), now
	Changed()
end

-- Visible posts, newest first
function Board.List()
	local list, now = {}, Now()
	for _, post in pairs(Data().posts) do
		if not post.deleted and Kept(post, now) then
			list[#list + 1] = post
		end
	end
	table.sort(list, function(a, b)
		if a.created ~= b.created then
			return a.created > b.created
		end
		return a.id > b.id
	end)
	return list
end

-- Syncing ------------------------------------------------------------------------------------

-- Fingerprint and "last in sync" to one contact
function Board.Sync(name, reply)
	local contact = Contact(name)
	if not contact then
		return
	end
	local hash = Board.Hash()
	ns.Comm.Send(("H|%s|%d|%d|%d"):format(hash, contact.lastSync or 0, reply and 1 or 0, Now()), contact.name)
end

function Board.SyncAll()
	Prune()
	for _, contact in pairs(Data().contacts) do
		if contact.state == "friend" then
			Board.Sync(contact.name)
		end
	end
end

-- Everything we stored after "since" (that's still kept), to one contact, in one message
-- ("P|...||P|...", split into parts by Comm when long); not what we got from them
local function SendSince(name, since)
	local now, key, list = Now(), Key(name), {}
	for _, post in pairs(Data().posts) do
		if (post.got or 0) > since and Kept(post, now) and post.from ~= key then
			list[#list + 1] = Wire(post)
		end
	end
	if #list > 0 then
		ns.Comm.Send(table.concat(list, "||"), name)
	end
end

local function OnHello(sender, hash, since, reply, stamp)
	local contact = Contact(sender)
	if hash == Board.Hash() then
		-- In sync as of when they took the fingerprint (by their clock): what they store after
		-- that is what they'll have to send us next time
		contact.lastSync = math.min(Now(), tonumber(stamp) or 0)
		Changed()
		return
	end
	SendSince(contact.name, tonumber(since) or 0)
	if reply ~= "1" then
		Board.Sync(contact.name, true)
	end
end

local function OnPost(from, id, created, modified, deleted, author, text)
	created, modified = tonumber(created), tonumber(modified)
	if not id or not created or not modified or not author or author == "" then
		return
	end
	local now = Now()
	if modified > now + 300 or now - modified > KEEP_DAYS * 86400 then
		return -- from the future, or too old to keep
	end
	local posts = Data().posts
	local mine = posts[id]
	if mine and (mine.modified > modified or (mine.modified == modified and (mine.deleted or deleted ~= "1"))) then
		return -- we have this version or a newer one
	end
	if mine and Key(mine.author) ~= Key(author) then
		return -- an id can't change its author
	end
	posts[id] = { id = id, author = author, created = created, modified = modified, deleted = deleted == "1" or nil,
		text = Clean(text), got = now, from = from }
	Changed()
end

function Board.Receive(msg, sender)
	local what = msg:match("^F|(%a+)$")
	if what then
		OnFriendMessage(sender, what)
		return
	end
	local kind = msg:sub(1, 2)
	if (kind ~= "H|" and kind ~= "P|") or not Contact(sender) then
		return -- only our contacts' board messages
	end
	if kind == "H|" then
		local hash, since, reply, stamp = msg:match("^H|(%x+)|(%d+)|(%d)|(%d+)$")
		if hash then
			OnHello(sender, hash, since, reply, stamp)
		end
	else
		-- one post, or several joined by "||" (texts never contain "|")
		for record in (msg .. "||"):gmatch("(P|.-)||%f[P%z]") do
			local id, created, modified, deleted, author, text = record:match("^P|([^|]+)|(%d+)|(%d+)|([01])|([^|]+)|(.*)$")
			OnPost(Key(sender), id, created, modified, deleted, author, text)
		end
	end
end

ns.Comm.Register("board", Board.Receive)


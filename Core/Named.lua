local _, ns = ...

-- Named mobs the game doesn't flag (ARCHITECTURE.md 5.1): elites and normal mobs with a proper
-- name, like Hogger, look like any other mob to an addon. Rares, rare elites and bosses are
-- named anyway; this list adds the known named ones that aren't. Matched by NPC id (works in
-- every client language) or by English name. Extend as needed.
local NAMED = {
	-- Elwynn Forest
	{ 448, "Hogger" }, { 327, "Goldtooth" }, { 330, "Princess" }, { 473, "Morgan the Collector" },
	{ 472, "Fedfennel" }, { 79, "Narg the Taskmaster" }, { 100, "Gruff Swiftbite" },
	-- Westfall
	{ 391, "Old Murk-Eye" }, { 573, "Foe Reaper 4000" }, { nil, "Leprithus" },
	-- Redridge Mountains
	{ 334, "Gath'Ilzogg" }, { 345, "Bellygrub" }, { 703, "Lieutenant Fangore" }, { 486, "Tharil'zun" },
	{ 518, "Yowler" }, { 397, "Morganth" },
	-- Duskwood
	{ 412, "Stitches" }, { 522, "Mor'Ladim" }, { 315, "Stalvan Mistmantle" }, { 314, "Eliza" },
	{ 503, "Lord Malathrom" }, { nil, "Fenros" },
	-- Dun Morogh
	{ 808, "Grik'nir the Cold" }, { 1388, "Vagash" }, { 1271, "Old Icebeard" }, { 1132, "Timber" },
	{ 1130, "Bjarn" },
	-- Teldrassil, Darkshore
	{ 2038, "Lord Melenas" }, { 2039, "Ursal the Mauler" }, { nil, "Murkdeep" },
	-- Durotar
	{ 3204, "Gazz'uz" }, { 3205, "Zalazane" }, { 3281, "Sarkoth" }, { 3203, "Fizzle Darkstorm" },
	{ 3183, "Yarrog Baneshadow" }, { 3192, "Lieutenant Benedict" },
	-- Mulgore
	{ 5786, "Snagglespear" }, { 3058, "Arra'chea" }, { 3056, "Ghost Howl" }, { 3068, "Mazzranache" },
	-- The Barrens
	{ 3396, "Hezrul Bloodmark" }, { 3394, "Barak Kodobane" }, { 3395, "Verog the Dervish" },
	{ 3430, "Mangletooth" }, { 3475, "Echeyakee" }, { 3474, "Lakota'mani" }, { 3438, "Kreenig Snarlsnout" },
	{ 3467, "Baron Longshore" }, { 3398, "Gesharahan" }, { 5831, "Swiftmane" }, { 3473, "Owatanka" },
	-- Stranglethorn Vale
	{ 731, "King Bangalash" }, { 729, "Sin'Dall" }, { 728, "Bhag'thera" }, { 813, "Colonel Kurzen" },
	{ nil, "Mogh the Undying" }, { nil, "Gan'zulah" }, { nil, "Nezzliok the Dire" }, { nil, "Mai'Zoth" },
	-- The Deadmines
	{ 644, "Rhahk'Zor" }, { 642, "Sneed's Shredder" }, { 643, "Sneed" }, { 1763, "Gilnid" },
	{ 646, "Mr. Smite" }, { 647, "Captain Greenskin" }, { 639, "Edwin VanCleef" }, { 645, "Cookie" },
	-- The Stockade
	{ 1696, "Targorr the Dread" }, { 1666, "Kam Deepfury" }, { 1717, "Hamhock" }, { 1716, "Bazil Thredd" },
	{ 1663, "Dextren Ward" }, { 1720, "Bruegal Ironknuckle" },
	-- Ragefire Chasm
	{ 11520, "Taragaman the Hungerer" }, { 11518, "Jergosh the Invoker" }, { 11519, "Bazzalan" },
	{ 11517, "Oggleflint" },
	-- Wailing Caverns
	{ 3671, "Lady Anacondra" }, { 3669, "Lord Cobrahn" }, { 3670, "Lord Pythas" }, { 3673, "Lord Serpentis" },
	{ 3653, "Kresh" }, { 3674, "Skum" }, { 5775, "Verdan the Everliving" }, { 3654, "Mutanus the Devourer" },
	-- Shadowfang Keep
	{ 3914, "Rethilgore" }, { 3886, "Razorclaw the Butcher" }, { 3887, "Baron Silverlaine" },
	{ 4278, "Commander Springvale" }, { 4279, "Odo the Blindwatcher" }, { 4274, "Fenrus the Devourer" },
	{ 3927, "Wolf Master Nandos" }, { 4275, "Archmage Arugal" },
	-- Blackfathom Deeps
	{ 4887, "Ghamoo-ra" }, { 4831, "Lady Sarevess" }, { 6243, "Gelihast" }, { 12902, "Lorgus Jett" },
	{ 12876, "Baron Aquanis" }, { 4832, "Twilight Lord Kelris" }, { 4830, "Old Serra'kis" }, { 4829, "Aku'mai" },
	-- Razorfen Kraul
	{ 4421, "Charlga Razorflank" }, { 4422, "Agathelos the Raging" },
	-- Scarlet Monastery
	{ 3983, "Interrogator Vishas" }, { 4543, "Bloodmage Thalnos" }, { 3974, "Houndmaster Loksey" },
	{ 6487, "Arcanist Doan" }, { 3975, "Herod" }, { 4542, "High Inquisitor Fairbanks" },
	{ 3976, "Scarlet Commander Mograine" }, { 3977, "High Inquisitor Whitemane" },
}

local byId, byName = {}, {}
for _, entry in ipairs(NAMED) do
	if entry[1] then
		byId[entry[1]] = true
	end
	byName[entry[2]] = true
end

-- Whether a mob is on the list of known named mobs
function ns.IsKnownNamed(npcId, name)
	return (npcId and byId[npcId]) or (name and byName[name]) or false
end

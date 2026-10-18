local _, ns = ...

-- The family type chart of battles (ARCHITECTURE.md 5.5, Pokémon style): a family deals STRONG
-- damage to the two families it's strong against, and WEAK damage to the two that are strong
-- against it. Every family is strong against two and weak against two; Giant and Dragonkin are
-- rivals, strong against each other. Placeholders for balancing.
ns.TYPE_STRONG = 1.4
ns.TYPE_WEAK = 0.75

ns.TYPE_CHART = {
	Humanoid = { Undead = true, Demon = true },
	Undead = { Beast = true, Giant = true },
	Beast = { Humanoid = true, Elemental = true },
	Demon = { Humanoid = true, Mechanical = true },
	Elemental = { Undead = true, Mechanical = true },
	Mechanical = { Beast = true, Dragonkin = true },
	Giant = { Dragonkin = true, Elemental = true },
	Dragonkin = { Giant = true, Demon = true },
}
ns.FAMILY_ORDER = { "Humanoid", "Undead", "Beast", "Demon", "Elemental", "Mechanical", "Giant", "Dragonkin" }

-- Damage factor of an attacker's family against a defender's: strong, weak or 1. Rivals (strong
-- against each other) hit each other strong.
function ns.TypeFactor(attacker, defender)
	local chart = ns.TYPE_CHART
	if chart[attacker] and chart[attacker][defender] then
		return ns.TYPE_STRONG
	elseif chart[defender] and chart[defender][attacker] then
		return ns.TYPE_WEAK
	end
	return 1
end

-- The families this one is strong against and the ones strong against it
function ns.TypeMatchups(family)
	local strong, weak = {}, {}
	for _, other in ipairs(ns.FAMILY_ORDER) do
		if ns.TYPE_CHART[family] and ns.TYPE_CHART[family][other] then
			strong[#strong + 1] = other
		end
		if ns.TYPE_CHART[other] and ns.TYPE_CHART[other][family] then
			weak[#weak + 1] = other
		end
	end
	return strong, weak
end

-- "Super effective" and friends, for tooltips and the log
function ns.TypeWords(factor)
	if factor > 1 then
		return "|cff40ff40super effective|r"
	elseif factor < 1 then
		return "|cffff8040not very effective|r"
	end
end

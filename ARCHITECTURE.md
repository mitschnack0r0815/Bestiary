# Bestiary: design

A collectible auto battler fed by your real WoW play: the mobs you kill can drop trophy cards
of themselves. You prepare three squads of five from your collection; in a duel both players
secretly pick one, and the squads fight on their own. Every card is Tank, Mage or Assassin,
and those counter each other like rock, paper, scissors, so guessing what the other side sends
matters as much as having strong cards. Optional hardcore: when your character dies, your
bestiary dies.

Status: design only, nothing built. Sections marked **Open** still need a decision; everything
else is the current proposal and can be changed.

---

## 1. Core loop

1. Play WoW normally. Mobs you kill can drop a **card** of that mob.
2. Getting the same card again **levels it up** instead of giving a copy.
3. Build **three squads** of five cards. Every card is **Tank, Mage or Assassin** (3.5);
   squads mix them however you like. Families (beast, undead, ...) give bonuses when you
   field several of one kind.
4. **Duel** another player: both secretly pick one of their squads, then the two fight
   automatically and you watch the replay. Bring the squad that counters theirs and you win
   easily; get read and you lose.
5. Wins earn rating and small rewards; your collection is what you build up over time.

The building part is choosing what to hunt: want a dragonkin team, go farm whelps in the
Wetlands and wyrmkin in the Swamp of Sorrows.

## 2. What the addon can see

**The combat log is closed to addons on this client** (Midnight-style restrictions:
registering `COMBAT_LOG_EVENT_UNFILTERED` is forbidden and gets the addon blocked), and unit
values can be *secret* (`issecretvalue`), mostly in combat and instances. Everything comes from
the unit API on units we can see, and secret values are skipped, never compared or stored.

| What | How | Notes |
|---|---|---|
| A mob died that we killed | Whichever comes first: a mob that was fighting us (`UnitThreatSituation`, or it targets us or our pet) seen dead as target, focus, mouseover or nameplate (also when its nameplate goes away); looting its corpse (`GetLootSourceInfo`); `PARTY_KILL` if the client sends it | Counted once per mob. `PARTY_KILL` alone didn't work in the client. GUID gives the NPC id; skipped if secret |
| Mob name, level, elite/rare, creature type | `UnitName`, `UnitLevel`, `UnitClassification`, `UnitCreatureType` while it's target, mouseover, focus or nameplate; cached by NPC id | A mob never seen that way has no data: no drop |
| Tapped by someone else | `UnitIsTapDenied` while cached | Tapped-away mobs give nothing |
| Fighting time | Every 0.5 s: visible mobs with `UnitAffectingCombat` | Study time (4.0) |
| Instant casts and spell damage | Debuffs mobs put on you (`UNIT_AURA`, the aura names its caster), buffs on every visible mob (also before the fight: Lightning Shield, Stealth) credited to whoever cast them (itself or an ally), and damage you take by school (`UNIT_COMBAT`: non-physical = spells), credited to the one visible mob targeting you (nobody if several) | Instant spells (shocks, Lightning Shield) leave no cast bar and often no cast event; poisons point to Assassin |
| What the mob did | Casts of visible mobs: `UNIT_SPELLCAST_START` / `_SUCCEEDED` / `_CHANNEL_START` (counted even when the spell is secret) plus their cast bar every 0.5 s (`UnitCastingInfo` / `UnitChannelInfo`: name and icon), each cast once; heals by name; `UnitPowerType` (mana), `UnitClass`, `UnitAttackSpeed` | Used for its combat type (3.5); no damage numbers, schools, dodges or parries |
| Spells that hit us, and which mob cast them | Blizzard's damage meter `C_DamageMeter`, read once per fight when the combat restriction lifts: `DamageTaken` for the player lists spell id, damage and the mob's name; `EnemyDamageTaken` maps names to NPC ids | Mob casts themselves are **always secret** (`SecretWhenUnitSpellCastRestricted`: any unit but the player or pet, in or out of combat). The meter only has spells that did damage: misses, resists, heals and buffs aren't in it |
| Resisted spells | `UNIT_COMBAT` RESIST on the player (not secret), credited to every mob that finished a cast within 2 s | Melee can't be resisted, so a resist is a spell whose name we never learn |
| Death | `PLAYER_DEAD` | Not on Feign Death. Also check `UnitIsDeadOrGhost("player")` on login for deaths while the addon was off |

## 3. Cards

### 3.1 Identity

A card is one **NPC id** (all "Defias Pillager" share one id). Stored per card:
`npcId, name, classification, family, combat type, stars (card level),
obtained (time, zone)`.

### 3.2 Stats: the real mob, by level (decided 2026-10-17)

A card is a copy of the real mob, as accurate as possible, at the card's level. Replaces the
power budget (rarity x stars, level didn't matter).

- **How mobs scale with level:** the game builds a mob's stats from a table per level and NPC
  class (warrior, paladin, mage; rogues use the warrior rows) times the mob's own multipliers.
  We ship that table (`Core/LevelStats.lua`, levels 1-63: health, base damage, attack power,
  armor) from the MaNGOS Zero database (`creature_template_classlevelstats`,
  github.com/mangoszero/database). The emulator community rebuilt it from the original game, so
  Forever's numbers can differ a little; our measurements correct that at each mob's own level.
  Typical melee hit = (base damage + attack power / 14) x attack time (cMaNGOS). First check:
  Razormane Thornweaver (level 10 paladin, 2.0 s) is 15.5 per hit in the table; we measured
  about 14 with the armor undone.
- **A mob's factors:** measured value / table value at the level of that very mob (4.0,
  "Measuring"): health, melee hit, each spell (against a 2.0 s melee hit). Until measured, a guess
  by rarity (`ns.GUESSED_FACTORS`: elite health x3, damage x1.75, ...).
- **Card stats at level L:** health = table health(L, class) x health factor; melee hit = table
  hit(L, class, its attack speed) x melee factor; spell = table hit(L, class) x spell factor;
  armor = table armor(L, class). Each star adds 3% to health and damage or healing (3.3).
- **A fight round is 8 seconds** of the real fight (`ns.ROUND_SECONDS`): attack per round = melee
  hits in 8 s, or for Mages and Healers with a known signature spell one cast every 4 s. Real
  mobs take long to kill each other (two level 60 mobs: over a minute), so rounds are long; the
  proportions between mobs stay real. Armor works like in the game (5.2).
- **Levels (decided):** a card starts at the level of the mob it dropped from (skull = 63). Every
  **5 duels** (won or lost, the sparring partner counts too) it gains a level,
  never more than **3 above your level**, at most **60, named cards 63**. Your own card is always
  your level. Saved on the card (`level`, `games`); cards from before levels take their mob's
  level.
- **Power** (what counts against the cap; changed 2026-10-17, the level alone let elites in for
  the price of normal mobs): **level x strength**, strength = sqrt(health ratio x damage per
  second ratio) against a typical normal mob of that level (warrior row, 2 s attacks); damage is
  what its action does (casters and healers: spell or heal per cast). At level 20: normal mobs
  17-21 (Tanks cheaper), elites ~46, rare elites ~53, bosses ~98. Computed from the card's stats,
  so it follows measurements, stars and type rules, and cards from a duel get the same power on
  both sides. The cap stays `5 x your level` (`ns.CAP_PER_LEVEL`, 300 at 60): five normal cards
  of your level, or two elites. At most 7 cards. Each side's squad is checked against its
  owner's cap. The card's gem shows its level; power is in the tooltip.

Duels send the cards with their level and stats (protocol 2: owner level, then npcId, stars,
type, rarity, family, flags, level, health, attack, armor, name), so the other side fights the
mob as its owner measured it.

### 3.3 Rarity and drop chance

**Rarity = the game's item qualities (decided 2026-10-17)**, from what the mob is. It's the card's
color and status; strength comes from the real mob (3.2), drop chances from its classification.

| Mob | Card rarity | Drop chance per kill |
|---|---|---|
| Normal (trivial ones too) | Common (white); **1 star: Uncommon, 4 stars: Rare** | 4% |
| Named normal mob | Uncommon | 4% |
| Elite | Uncommon | 15% |
| Named elite (Hogger, Mor'Ladim, ...) | Rare | 15% |
| Rare (silver dragon, elite or not) | Epic | 100% on the first kill once studied, then 25% |
| Rare elite | Epic | 100% on the first kill once studied, then 35% |
| Dungeon boss (seen in a 5-man) | Epic | 100% on the first kill once studied, then 25% |
| Raid or world boss | Legendary | 100% on the first kill once studied, then 25% |
| Your own card | Rare | - |

Where a boss was seen is saved with the mob (`info.instance`) and travels with its card in duels.

No mob drops anything before the addon has seen its kind fighting for 10 seconds (4.0).

**Starter boost** (decided): all drop chances are x5 (500%) while you own fewer than 10
different cards, so a new collection fills up fast. After that the extra halves every 5 more
cards: x5 at 10, x3 at 15, x2 at 20, x1.5 at 25, about x1.1 at 39, gone at 40. Applied after
the farm halving (4.2); a chance never goes over 100%.

**Bad luck protection** (decided): per mob type, every kill of a studied mob that drops nothing
raises its chance by 20% of the base chance, up to x5 (`BestiaryChar.dry`); its next real card
resets it. A normal mob (4%) is at 12% after 10 dry kills and 20% after 20. Test tab drops
don't count either way.
**Copies** (decided): a normal (Common) card that isn't named can be owned up to **3 times**;
getting it again gives another copy (the drop says "copy 2 of 3"), and a squad can hold as many
copies as you own. The Collection tab shows "1x" to "3x" in the top left corner; on the Squads
tab the badge counts the copies still free, and a card whose copies are all in the squad turns
grey but stays listed. Copies share stars and stamina (a duel takes the biggest loss once).
Duels check it too: at most 3 of a normal card, 1 of anything else.
Rarer cards are owned once; after that (and after 3 copies) card drops of that mob stop.

**Stars (decided 2026-10-17)** are their own drop: cards start at 0 stars, and once you own a
mob's card, every kill of that mob rolls for the next star: **10%** for the first, then half as
likely for each next (5%, 2.5%, 1.25%, 0.625%), **max 5**. Each star makes the card **3%
stronger** in health and damage or healing (no glow: tried and removed). Cards from before had 1 as their lowest: they lost one star once.

### 3.4 Families

From `UnitCreatureType`. Critters and "Not specified" don't drop cards.

| Family | Stat lean | Example abilities | Team bonus (2 / 4 of a family) |
|---|---|---|---|
| Beast | Fast | Pounce (first hit x2), Pack Hunter | +1 / +2 speed |
| Humanoid | Balanced | Shield Wall, Rally (heal ally) | +10% attack and health / +20% and +1 speed |
| Undead | Tanky | Rise Again (once at 30% HP) | the first of them to die gets back up at 20% / 40% HP (once per squad) |
| Demon | Hard-hitting | Drain Life, Sacrifice | +15% / +35% attack, lose 2% HP each turn (never below 1) |
| Dragonkin | Strong, slow | Breath (hits all) | +15% / +30% health |
| Elemental | Area damage | Overload, Shield of Stone | splash +20% / +50% (ability damage once abilities exist) |
| Giant | Very tanky, slow | Stomp (stun) | +20% / +40% health, -1 speed |
| Mechanical | Armored | Self-Repair, Overcharge | take 10% / 20% less damage |

**Implemented** (`Core/Fight.lua`): with 2 cards of a family in the squad they get the first
bonus, with 4 or more the second; only the cards of that family get it. Speed bonuses are flat
since speed runs 1-10. Shown on the Squads tab under the type counts (what each bonus does) and
on the Duel tab under each squad and when both lock in (family and count). Numbers are
placeholders for balancing.

### 3.5 Combat types: Tank, Mage, Assassin

Every card has one of three combat types. They're the rock, paper, scissors of the game, and
the counters come from how each type fights (5.2), not from a "beats" table:

| Type | How it fights | Strong against | Weak against |
|---|---|---|---|
| **Tank** | Slow. **Armor** takes a share off every physical hit. Hits the front | Assassin: their many small hits barely get through | Mage |
| **Mage** | Fragile. Hits **ignore armor** and splash onto the next enemy | Tank: big slow targets standing together | Assassin |
| **Assassin** | Fastest. One hard strike that goes for the **back row**; armor counts triple against it | Mage: kills fragile casters before they cast | Tank |

- A squad is any mix: 3 Tank in front and 2 Mage behind is solid against Assassins and
  weak against Mage; a mixed squad is safe but never crushes.

**Healer**, a fourth type outside the triangle: support that strengthens whatever squad it's in.

| Type | How it fights | Strong against | Weak against |
|---|---|---|---|
| **Healer** | Built like Mage (fragile, medium speed, the same stats), but never deals damage: where Mage hits the front enemy and splashes the one behind, a Healer heals the ally with the lowest health share and splashes half that heal onto the ally behind it. Each of its heals is 10% weaker than the one before, so fights don't stall | Tank squads: their slow steady damage is easy to heal through | Assassins (healers stand at the back, where they strike); Mage splash outpaces healing |

- **No limit** on Healers per squad. More Healers means less damage: a squad of only Healers
  can't hurt anyone and loses on the round limit (5.2).
- Placement matters: in the middle, behind the tanks, but not back-most where Assassins strike
  first.
- A Healer leader: all heals +20%.
- A perfect counter should win clearly, but stronger cards still matter a little (target:
  a full counter squad wins about 80% at equal power; to be tuned in the headless tests).

**Which type a card gets:** from what the mob did while you fought it (4.0).

### 3.6 Your own card (decided)

Every character starts with a card of **themselves**, created on first login with the addon:
your name, your own 3D model as the portrait, family Humanoid, type from your class (Warrior
and Paladin Tank, Rogue and Hunter Warrior, Priest and Druid Healer, Mage, Warlock and Shaman
Mage). It counts as **named**, so it's your first leader; Rare rarity, the stats of a common mob
of your level, 0 stars, it never gains stars. Saved under NPC id 0 (`Core/Squads.lua`).

**4 class abilities (decided 2026-10-17)**, real Classic spells (rank 1 ids, names and icons
from the game) on our effects (`ns.CLASS_ABILITIES`, `Core/Abilities.lua`):

| Class | Abilities |
|---|---|
| Warrior | Hamstring (slow), Disarm, Intimidating Shout (fear), Berserker Rage (enrage) |
| Paladin | Hammer of Justice (stun), Turn Undead (fear), Consecration (damage over time), Judgement of Justice (silence) |
| Rogue | Kidney Shot (stun), Kick (silence), Crippling Poison (slow), Deadly Poison (poison) |
| Hunter | Scatter Shot (stun), Concussive Shot (slow), Serpent Sting (poison), Scare Beast (fear) |
| Mage | Frostbolt (slow, with its spell), Counterspell (silence), Polymorph (fear: damage breaks it), Frost Nova (root) |
| Warlock | Fear, Corruption (damage over time), Curse of Exhaustion (slow), Spell Lock (silence) |
| Shaman | Earth Shock (silence), Frost Shock (slow), Flame Shock (damage over time), Elemental Mastery (enrage) |
| Priest | Psychic Scream (fear), Shadow Word: Pain (damage over time), Silence, Mind Flay (slow) |
| Druid | Bash (stun), Hibernate (fear: damage breaks it), Entangling Roots (root), Moonfire (damage over time) |

Casters and healers cast their class's spell (Frostbolt, Shadow Bolt, Lightning Bolt, Lesser
Heal, Healing Touch). Abilities travel with their spell ids in duels (protocol 12).

## 4. Getting cards

### 4.0 Studying a mob: 10 seconds of watching it fight before any card (rule)

**A mob can never drop a card until the addon has seen that kind of mob fighting for 10
seconds.** Cards aren't made up from a table: they're built from what the addon saw the mob do.

(First decided as "10 seconds of combat log data". The combat log turned out to be closed to
addons on this client, see 2, so it's now fighting time seen through the unit API.)

- **Only fighting time counts,** not time standing next to it: every 0.5 seconds, each mob we
  can see (target, mouseover, focus, nameplates) that's alive and in combat adds 0.5 seconds
  to its kind. A mob killed in one hit adds almost nothing.
- It adds up **per mob type (NPC id)** across fights and across different mobs of that type,
  per character: three Defias Pillagers fighting for 4 seconds each is 12 seconds, enough.
- Progress shows in the bestiary: "Defias Pillager: studied 7 / 10 s".
- **What the fighting records:**
  - level, classification and creature type
  - every spell it cast (name, spell id, whether it's a heal, by name)
  - whether it uses mana, its NPC class, its attack speed
  - zone
- **Once past 10 seconds, the card can be built** from what was recorded (and refined by later
  fights until it first drops; from then on it's fixed):
  - **Combat type**, the first that fits:
    - Healer: at least 2 heal casts and a third or more of its casts heal (Healer stats are
      Mage's).
    - Mage: uses mana (or its NPC class is a mana class: paladin, mage, ...) and cast at
      least 2 spells; or cast at least 3 spells at 1 or more per 10 seconds, mana or not.
    - By NPC class: mage, warlock, priest Mage; rogue, hunter Assassin. (NPC classes only say
      how a mob uses resources: "paladin" is any mana user, often a casting beast, so it
      doesn't mean Tank.)
    - Mage also: more than 3 spell hits on you, at least half as many as its melee hits (instant
      casters like shamans).
    - Tank or Assassin by points: poisoned you +1 Assassin; Stealth or Prowl on itself +1
      Assassin; Stoneskin, Harden Skin, Shield Wall/Block, Defensive Stance +1 Tank; fast attacks (under 1.8 s) +1 Assassin, slow, heavy attacks
      (over 2.6 s) +1 Tank; and **sturdiness** (decided): the mob's maximum health against the
      median of mobs you've seen of the same rarity within 2 levels (at least 5 of them; else
      typical Classic health by level, elites x3, rares x1.4): 125% or more +1 Tank, 160% +2;
      80% or less +1 Assassin, 60% or less +2. Bosses aren't compared. Most mobs
      swing every 2.0 s, so health is what tells a sturdy Defias Thug from a frail wolf.
    - Otherwise its family's lean.
  - **Ability** (after the prototype) from its signature spell (the one it cast most). Mobs
    that cast nothing get a melee ability from their type and family.
  - **Art:** the creature's **3D portrait** (decided; icons rarely showed the actual creature),
    zoomed onto its face like the target frame. The game can draw any creature it has seen
    by NPC id (`PlayerModel:SetCreature`), so nothing has to be captured or stored. While the
    model loads, or if it can't, the icon of its signature spell (or its family) shows. In
    scrolling lists a model only shows while its card is fully in view.
    The portrait stands still (animation frozen) inside a round frame. Models can't be cut
    round, so the frame is drawn above the model with the addon's own textures
    (`Media/RingCover.tga`, `Media/RingBorder.tga`): a cover in the card's color hides the
    model's corners outside the circle, and the ring in the rarity color sits on top. **Leaders** get the dragon ring around it, like an elite's portrait.
  - Stats from the formula (3.2).
- From then on, kills of that mob type can drop the card with the chances in 3.3, starting
  with the kill after the 10 seconds are reached.
- Since it's built from what **you** saw, two players' Defias Pillager cards can differ a
  little. Duels send the card data along (3.2), so that doesn't matter for fighting.
- **Resisted only, no card** (decided): a mob seen casting whose spells were only ever resisted, with none of its spells known, never drops a card: it would guess its spells and is too likely wrong. Once one of its spells hits you and the damage meter names it, it can drop again. A kill of a casting mob whose spells are unknown waits until that fight's damage meter is read.
- **Rares and bosses** usually fight for more than 10 seconds, so one proper fight studies
  them; their first kill after that drops the card for sure (3.3).
- **Everything counts** (decided): a mob fighting anyone you can see is knowledge about it. A
  dungeon run studies the boss for the whole group at once, and watching a mob fight someone
  else (on its nameplate) teaches you about it too. Only the drop needs your group's kill (4.1).

**Measuring (decided: as accurate as possible).** Per mob type, account wide (the numbers
don't depend on who measured), last 25 samples, the median counts:
- **Health:** mob health is always secret on this client (`UnitHealthMax` for anything not
  player-controlled). Taken from the damage meter instead: damage it took to die (EnemyDamageTaken)
  minus our overkill. Only when we're alone, it was the only mob of its type fighting us, the
  only kill of the fight, nobody else's tapped mob died and none of our mobs went after a player
  outside our group (a passerby's damage isn't in our meter), else the numbers mix.
- **Whose cast:** resists, spell hits and loss of control go to the mob that just finished a
  cast, and only mobs fighting us count (on our threat list, or targeting us or our pet), so a
  mob nearby casting at someone else never gets them.
- **Melee hit:** plain physical hits on us (`UNIT_COMBAT`, no crit, crushing, glancing, block),
  credited to the one mob targeting us, with **our armor taken back out**: raw = hit / (1 -
  armor / (armor + 400 + 85 x mob level)) (Classic formula, 75% cap, other constant from level
  60). Our armor is read whenever it isn't secret. Not undone: damage taken talents and stances
  (a few %), and physical specials of the mob mixed in (the median mostly ignores them).
- **Spell damage:** plain non-physical hits on us right after one mob (only one) finished a
  cast; after the fight they go to its spell if only one of its spells hit us in that fight
  (the damage meter names it). Spells ignore armor; full hits aren't resisted, partial resists
  are flagged and skipped.
- Samples are stored as **factors** against the level table (3.2) at the level of that very mob
  (seen on its nameplate or target), so mobs of one type at different levels agree.
- Shown on the Test tab ("Measured": the value at its level, the factor, the sample count).

**Fight log (the data to learn from).** Every fight is one record in `BestiaryAccount.fights`
(account wide, newest 500): when and where, our level, class, armor, group and whether we died;
each mob type in it (name, level range, class, rarity, attack speed, how many, kills, casts,
resists, spells and their damage from the damage meter, health if measured); every hit on us in
order (seconds, which mob we think, school, amount, flag: plain, crit, crushing, glancing, block,
resist, or miss / dodge / parry); damage meter totals. `/bst fights` or "Fight log" on the Test
tab shows it as text to copy out (`Core/FightLog.lua`).

### 4.1 Counting a kill

A kill counts if: we (or our pet) damaged it, it wasn't tapped by someone else, and it isn't
a critter. The mob's level doesn't matter: grey mobs (no XP) drop cards like any other, so a
level 60 can still go back and hunt the Young Wolf they're missing. Farming them quickly is
held back by the rules in 4.2, not by level.

Group kills count for everyone who damaged the mob, so dungeons with friends are fun. Drop
chance x0.75 in a 5-man group, x0.25 in a raid (to be balanced).

### 4.2 Against farming

- Same NPC id: drop chance halves for every card dropped from it within the last hour.
- **No daily cap** (decided).

### 4.3 Loot luck

Dropped for now: unclear what it would add. Can come back if cards need another source.

## 5. Squads and battle

### 5.1 Squads

You prepare **three squads**, in order, front to back, with **no minimum or maximum size**: only the power cap counts (decided; at most 7 fit under the cap of 100, since the weakest card has power 13). Dropping a card onto another card in the squad swaps the two; a card from the collection dropped onto one takes its slot. **Leaders**
(decided): only cards of **named mobs** lead, a named card always leads its squad, and a squad
holds at most one; a squad doesn't need a leader (decided: named cards are hard to get), but at most one. The game has no
"named" flag, so named means: **Rare, Rare Elite and Boss** (skull level, or in the boss
frames during a dungeon or raid encounter; once seen as a boss it stays one), plus a **manual
list of known named mobs** (`Core/Named.lua`, by NPC id or English name): named elites and
quest mobs like Hogger, Gath'Ilzogg, Mor'Ladim, Stitches, and the bosses of the early
dungeons. Their rarity doesn't change (Hogger stays an Uncommon card), they just lead.
The leader's bonus goes to allies of its combat type (6.1). Front cards get
attacked first, except by Assassins (back row) and splash. A card can be in more than one
squad. You can change your squads any time, but a duel uses the squad you locked in for it.

### 5.2 Fight rules: turn based (decided 2026-10-17)

No autobattler any more: players play their cards' turns, a bit like Hearthstone, but all
cards are on the table from the start (`Core/Fight.lua`).

**Deterministic.** No damage rolls; a seeded generator (seed from the duel's nonce and salt)
only breaks speed ties. A fight is its two squads, the seed, the twist and the list of moves,
so a duel only sends moves, and any client can rebuild the fight from them (after a reload,
days later). A move is: action, target side, target slot (`a2.3`); the acting card is always
the one whose turn it is. Moves that aren't legal are refused (a player sending one forfeits).

**Stats.** Health, attack (one melee hit), spell power (one cast), armor and attack time: the
real mob at the card's level (3.2). **Fights run 4x faster than real ones** (`ns.PACE`, decided):
real mobs take long to kill each other, so every hit and cast counts 4 times; the proportions
stay real.

**Turn order: a virtual clock, no rounds (decided).** Every card has its own clock. A card's
next turn comes after its real attack time (a mob that swings every 1.5 s gets twice the turns
of one that swings every 3 s); after a spell or heal, after 3 s (its cast). Whichever card's
time comes first, on either side, gets the turn, and its owner still picks what it does. Ties:
the side that didn't just act (the very first tie: a coin flip by the seed), then the lower
slot. Times are kept in tenths of a second. The Duel tab shows the clock and the next turns.

**Actions** (picked by the player on the card's turn, by clicking a circle under the target).
**Casters only cast, healers only heal (decided):** Mages have no Attack, Healers neither attack
nor cast at enemies; a Healer with nobody hurt can only wait: it's off the clock until an ally gets hurt,
then its turn comes at once (decided). Tanks and Warriors attack or use their spell.
- **Attack:** its melee, physical.
- **Spell:** the mob's signature spell, ignores armor, takes its **real cast time** (from the
  game's spell data, `C_Spell.GetSpellInfo`, at least 1.5 s; 3 s if unknown). Mages cast
  whenever they like; other cards every 10 s. **Strength (decided 2026-10-17):** as measured on
  you (4.0); until then from the damage numbers in the spell's description
  (`C_Spell.GetSpellDescription`, "18 to 20 Frost damage", at the mob's level); else **twice the
  card's melee hit**. Mages and Healers without a known spell get such a guessed spell too.
  Spell data is saved per mob account wide (`info.spellData`); the fight dump shows what the
  game says about each spell (to check the descriptions have numbers on this client).
- **Heal** (Healers instead of a spell): an ally below full health. Works like a Mage's spell
  (decided): its cast time, no cooldown. Each heal 10% weaker than the one before.

**Combat types:** Tank (blocks; **+25% health, +50% armor, -25% damage** (attack and spell), **25% longer attack
time**, decided
2026-10-17 until the game tells tanks apart better), Mage (spells without cooldown), **Warrior** (melee damage; was
Assassin until 2026-10-17, renamed, decided), Healer. Leaders: Tank allies +20% armor, Mage
spells +15%, Warrior allies attack 10% faster, heals +20%.

**Abilities (decided 2026-10-17, `Core/Abilities.lua`).** Mobs pass their stuns, fears,
silences, disarms/roots, slows, poisons and enrages on to their cards, **at most 4 per card**
(the strongest). Learned from: the **loss of control alert** on us (`C_LossOfControl`, readable
in combat for the player; credited to the mob that just cast, else the one attacking us), the
**descriptions** of the mob's known spells (Frostbolt: "reduces movement speed"), mob **emotes**
(enrage) and **poisons** it left on us. Saved per mob account wide (`info.abilities`, spell
descriptions' effects in `info.spellData`). Hooks in the fight:
- **Stun:** the target's next turn comes X s later (the real duration).
- **Fear:** the same, but any damage breaks it (back to its old turn).
- **Silence:** no spells or heals for X s. **Disarm/root:** no attacks for X s.
- **Slow:** the target's turns come 30% later for X s.
- **Poison:** a tick at each of the target's turns for X s (30% of the poisoner's attack).
- **Enrage** (passive): below 30% health, 50% more damage.
An ability that's part of the card's signature spell comes with every cast of it; the others are
their own action (a circle with the ability's icon, 1.5 s, cooldown 15-20 s). A card that can't
do anything (silenced caster, disarmed fighter) waits a moment. Abilities raise power: stun +15%,
fear and silence +10%, poison and enrage +8%, slow and disarm +5%. Flee: left out (decided).
Duels send them with the cards (protocol 11). The fight dump logs loss of control and the
effects read from spell descriptions. Test cards (Test tab, "Fill with 5 basic cards") and the
sparring partner's training cards have no mob to learn from: they get a set by type (Tank: stun
and disarm; Mage: slow with its spell and silence; Warrior: poison and enrage; Healer: fear).

**On screen (decided):** on your turn, every card your card can act on gets round icon buttons
underneath, one per possible action (attack, spell; heal under allies that can be healed), no
text (the tooltip shows the damage or heal). The card whose turn it is has sparks wandering
around its border, like the autocast shine on pet buttons. The board's cards are 18% bigger
(window 860 x 760). Status effects on a card (stun, fear, silence, disarm, slow, poison) show
above it as icons with the seconds left. A knocked out card turns over and lies face down
(Media/CardBack.tga: gold border, lattice, the Bestiary emblem in a gold ring); an Undead that
gets back up turns face up again.

**Tanks block (decided):** while a side has a living Tank, attacks and spells against it must
target one of its Tanks. **The order in a squad doesn't matter
any more.**

**Armor** like in the game: armor / (armor + 400 + 85 x attacker level), at most 75%.
Family bonuses and leaders as before (Elemental now strengthens spells and heals; Mage leader:
Mage spells +15%; Tank leader: Tank armor +20%).

**End.** A side with no living cards loses; after 180 virtual seconds the side with more health
left in percent wins. A resign is a loss.

**Sparring partner (decided: simple):** heals an ally below 70% if it can, else the action
and target that kill the most dangerous card it can kill, else the most damage, preferring
hurt targets.

**Balance:** fine tuning comes next (open question).

### 5.3 Where the strategy is

This decides whether building a squad is interesting, and it's also the answer to balancing
duels (6). Levers a player can pull, all before the fight (it's an auto battler):

- **Order:** who stands in front takes the hits; back cards with ranged or area abilities
  are safe until the front falls. Tanky front, damage behind, or a fast striker up front to
  kill something before it acts.
- **Speed:** turn order. Fast cards act first in their pair, so a fast high-damage card can
  remove an enemy before it acts; slow tanks act late but survive.
- **Family bonuses:** 2 or 4 of a family trade flexibility for a strong bonus.
- **Combat types:** the Tank / Mage / Assassin mix of a squad (3.5), and which of your
  three squads you send against which opponent (6). This is the main strategy: there's no
  single best squad, and a squad built against one opponent loses to another.
- **Abilities:** triggers (first attack, low health, on death, every N turns) and targets
  (front, back, lowest health, all) that combine: an undead "rise again" in front, a
  dragonkin breath behind, a humanoid healer in the middle.
- **Power cap (proposal for fairness):** every card has a power cost (its budget from 3.2).
  A duel sets a team power cap, for example 100, 200 or 400, and both teams must fit under it.
  A big collection gives more options to fill the cap well, not a guaranteed win; two strong
  cards or five weaker ones becomes a real choice. Stars and rarity raise power, so they
  matter by making a card better per cost, not just bigger.

Next step: implement the rules from 5.2 and test them headless with many random squads: the
triangle has to hold (each type beats the one it should), mixed squads should land in between,
and no single squad should beat everything.

### 5.4 Example fight

> **Outdated:** written for the old automatic fight (front and back rows, splash). The fight is
> turn based now (5.2).

Twist: Calm Waters (none). Numbers are illustrative.

**Alice's Tank wall**, front to back:
1. Skeletal Warder (Undead, Tank, rare elite, **leader**: all Tank cards +2 armor): Health 160, Attack
   14, Speed 3, Armor 6+2 = 8
2. Harvest Watcher (Mechanical, Tank): Health 110, Attack 12, Speed 2, Armor 5+2 = 7
3. Defias Pillager (Humanoid, Mage): Health 55, Attack 26, Speed 5

**Bob's Assassin pack**, front to back:
1. Plainstrider (Beast, Assassin): Health 60, Attack 18 (strikes 29), Speed 9
2. Kolkar Centaur (Humanoid, Assassin, rare, **leader**: Assassins +2 speed in round 1): Health 80,
   Attack 22 (strikes 35), Speed 7
3. Thunderhawk Cloudscraper (Beast, Assassin): Health 65, Attack 20 (strikes 32), Speed 8

**Round 1.** Fastest first on each side, in pairs: Plainstrider (9) and Pillager (5), Kolkar
(7 + 2 leader bonus) and Warder (3), Thunderhawk (8) and Watcher (2).
- Plainstrider strikes Alice's back-most card, the **Pillager** (no armor): 29 (55 → 26).
- Pillager casts on the Plainstrider for 26 (60 → 34) and splashes the Kolkar for 13 (→ 67).
- Kolkar strikes the Pillager for 35: **dead** after a single cast (Assassin beats Mage).
- Warder hits the Plainstrider for 14 (→ 20).
- Thunderhawk strikes the new back-most, the Watcher: 32 - 3 x 7 = 11 (110 → 99).
- Watcher hits the Plainstrider for 12 (→ 8).

**Rounds 2-6.** Against the tanks the Assassins get 8 to 14 through per strike, about **25 per
round instead of 96** without armor (Tank beats Assassin). The tanks hit 26 per round: the
Plainstrider dies in round 2, the Kolkar in round 5. The Watcher falls in round 6.

**Rounds 7-9.** Only the Warder is left, Armor 8: the Thunderhawk gets 32 - 24 = 8 through per
round and dies in round 9.

**Alice wins** with the Warder at about 136 of 160 health. Stamina: Warder -9 (lost 15%),
Watcher and Pillager -60 (died).

**Had Bob sent his Mage squad instead:** spells ignore the Warder's 8 armor, and every splash
hits the Watcher right behind it, so both tanks melt at once. Alice's only answer, the
Pillager, gets a single cast off before the casters trade it away. That's the hidden pick:
Alice built well against Assassins and would be crushed by Mage.

### 5.5 Battles: Pokémon style (decided 2026-10-18, branch `pokemon-battles`)

A second fight mode next to the duels, with **its own rules**: it shares nothing with the board
fight (5.2) but the cards themselves (stats, type, family, abilities, signature spell). Engine
`Core/Battle.lua`, type chart `Core/TypeChart.lua`, teams `Core/Teams.lua`, protocol
`Core/BattleDuel.lua`, pages `UI/Teams.lua` and `UI/Battle.lua`. All numbers are first guesses;
balancing comes from playing (decided: not from AI simulations).

**Teams.** Own **Teams tab**: three teams of **up to 3 cards** (decided 2026-10-18: 3 v 3 for now, quicker to test; `Battle.MAX_TEAM`), kept apart from the squads
(`BestiaryChar.teams`). **No power cap and no leaders** in this mode (decided): named cards don't
lead, and the cards show no leader frame, cap or stamina here. Copies like in squads.

**Hidden teams (decided).** Both pick a team **and the card it leads with** in secret (commit
and reveal), no team preview. Of the other side **only the card on the field is shown**: their
bench stays face down ("?", "Field", "KO"), and the log names their bench cards only as "a card
on their bench". Everything is shown once the battle is over. (Both clients need both teams to
rebuild the battle, so this is hidden on the page, not on the wire.)

**One card each on the field**, the others on the bench. **Strict alternating turns**: the faster
lead (attack time; casters: cast time) starts, a tie by the seed. A turn is one move or a switch:
- **Attack** (melee, armor counts), **Spell** (ignores armor; Mages cast every turn, the others'
  spell waits 2 turns), **abilities** (each hits for half the card's damage and puts its effect on
  the enemy; cooldown 3-4 turns), Tanks **Guard** (next hit halved), Healers **Heal** (itself),
  **Mend** (one bench card you click) and **Restore** (every hurt bench card, half a heal each).
- **Switch:** click a card of your bench; costs the turn, the new card takes the next hit.
- A card knocked out: its owner **picks which one comes in next** (the cards that can come in
  sparkle), for free, then it's their turn.
- Win: all enemy cards out. After 100 turns the side with more health left in percent wins.
  Resign is a loss.

**Damage per turn** is damage per second times 4 s (`Battle.TURN`), so fast and slow attackers
are even per turn and speed only decides who starts. Armor like the game (at most 75%).
- **Tanks block:** physical hits on them x0.7 (after armor); no slow turns in battles.
- **Healers** are weak fighters (half melee); their strength is healing the bench (decided).
  Each heal of a card is 80% of the one before.
- **Effects** last some of the target's turns (from their real duration, 4 s a turn, capped):
  stun skips a turn, fear skips until hit, silence (no spells or heals), disarm (no attacks),
  slow (30% less damage), poison (15% of the poisoner's damage per turn at the start of each of
  its side's turns, **also on the bench**), enrage (passive, +50% below 30% health). Leaving
  the field clears everything but poison. **Control immunity:** after a stun, fear, silence or
  disarm the card can't be controlled again until 2 of its turns after it ends (no stun locks by
  switching in fresh stunners).

**Type chart (families):** hits on a family the attacker is strong against x1.4, hits on one
strong against it x0.75. Each is strong against two:

| Family | Strong against |
|---|---|
| Humanoid | Undead, Demon |
| Undead | Beast, Giant |
| Beast | Humanoid, Elemental |
| Demon | Humanoid, Mechanical |
| Elemental | Undead, Mechanical |
| Mechanical | Beast, Dragonkin |
| Giant | Dragonkin, Elemental |
| Dragonkin | Giant, Demon |

Giant and Dragonkin are rivals (strong against each other). Combat types keep their roles: in
headless tests a team of one type beats the type it should (Warrior > Mage > Tank > Warrior).

**XP, no stamina (decided).** Every card that was on the field gets 20 XP, +15 per knockout, +15
if its side won; 100 XP is a level (up to the card's level cap). Shown under the cards on the
Teams tab and in the tooltip. Battles don't touch stamina, ratings or the duel record; they
keep their own win/loss record (`BestiaryChar.battleRecord`).

**Protocol** (`Bc` challenge, `Ba` commit, `Bt`/`Bu` team and lead, `Bm` moves, `Bq` catch-up,
`Bx` end; two letters so duels and the board ignore them; battle protocol 3): asynchronous like
duels, one battle at a time, saved per character (`BestiaryChar.battles`), rebuilt from teams,
leads, seed and moves. **Tested headless:** two clients with up to 50% of whispers lost and
random reloads: every game ended with the same moves and winner on both sides; the Battle page
drawn through a whole sparring battle. Sparring partner: simple (type matchups, heals, knockouts).
`/bst battle [name]`, `/bst teams`, and a Battle button on the Friends tab.

## 6. Duels

Turn based and **asynchronous, no timers** (decided): a game survives reloads, logouts and
both players being offline, like correspondence chess. Games are saved per character
(`BestiaryChar.games`, the last finished one kept to look at). **One game at a time**
(decided), against a player or the sparring partner: a new one (challenge or sparring) only
once it's over or resigned, and a challenge that comes in meanwhile is answered "busy"
(`Core/Duel.lua`, UI in `UI/Duel.lua`).

Both players pick a squad and **ban one of 3 offered twists without seeing the other's**
(commit and reveal):

1. **A → B `C|version|id|nonce`**: the challenge. The nonce sets the 3 twists on offer.
2. **B → A `A|id|commit`**: B picked a squad and banned a twist; the commit is a hash of both
   plus a secret salt.
3. **A → B `R|id|ban|squad`**: A picks, bans and shows. No hash needed: B is bound.
4. **B → A `S|id|ban|squad|salt`**: B shows; A checks it against the commit. The twist is drawn
   from what's left, the seed comes from the nonce and the salt.
5. **`M|id|n|move`**: move n, by whoever's turn it is.

Also `Q|id|step|n` ("where are you?") and `X|id|reason` (declined, cancelled, resigned).
Squads go with their stats (protocol 3: owner level, then per card npcId, stars, type, rarity,
family, flags, level, health, attack, armor, spell power, spell, name).

- **Catching up instead of timers:** Q goes out 8 s after login for every running game,
  whenever we hear anything from that player (they're online), and every 90 s while we wait
  on them. The answer is whatever they're missing: our last message (challenge, commit,
  squad) and the moves after their count. Duplicates are ignored.
- **Cheating:** a squad that doesn't match its commit, breaks the rules (size, cap of its
  owner's level, one leader) or bans a twist that isn't on offer, or a move that isn't legal,
  loses by forfeit.
- **Tested headless:** two simulated clients with 20-50% of whispers lost, reloads every few
  steps and one player going offline and back: every game finished with the same moves and
  the same winner on both sides. And a whole sparring game through the page's buttons.

**What you know about your opponent:** nothing about their squads before the fight, only the
twist (6.2). Reading them comes from knowing the player and what they sent before.

**Open:** best of 3 (each round both send one squad, a squad can't be sent twice) instead of a
single fight.

Messages go through a paced queue like Grandma's Game Box's Box/Comm.lua (copied, since this
is its own addon): burst then 1 per second, deduplicated, offline players retried rarely.

**Fairness:** the hidden pick and the type triangle already mean the stronger collection
doesn't simply win. On top, the **power cap** (decided, 5.3): the challenger picks the cap,
and the squads both send must fit under it, like the points limit of a Warcry warband. Each of
your three squads can be built for a different cap, or you rebuild before locking in. **For now the cap is fixed at 100** (decided) and can't be picked; the cap button on the
Squads tab is greyed out.

Rating: simple Elo per opponent and overall, per character.

### 6.1 Ideas from Warhammer Warcry

Warcry's roster building fits this game. What we take from it:

| Warcry | In Bestiary | Proposal |
|---|---|---|
| Points limit per warband | Power cap per duel; cards cost their power; fixed at 100 for now (later maybe a choice of caps) | **Decided** |
| Warband size varies | No size rule, only the power cap limits it (one strong card up to 7 weak ones) | **Decided** |
| A leader is required | The named card (Rare, Rare Elite, Boss) always leads; at most one per squad; a leader isn't required (named cards are hard to get) | **Decided** |
| Runemarks (keywords abilities refer to) | Family and combat type are the keywords abilities refer to ("other Undead get +armor") | **Decided** |
| Battleplan and twist cards | Each duel draws a twist, revealed at the challenge before both pick (6.2) | **Decided** |
| Limits on allies and monsters | At most one named card (so at most one Legendary); no per-card limit beyond the cap | **Decided** |
| Campaign: injuries | Cards get worn out and sit out duels: stamina (6.3) | **Decided** |
| Campaign: experience | Cards gaining XP from duels | Not for now |
| Battle groups (Dagger / Shield / Hammer) | Reserves joining later | **No**: too complicated |
| Wild dice fuel abilities | A seeded roll per round that fuels abilities | **No** |

Squad sizes change 5.1: a squad is any number of cards that fits the cap, front to back, led by its named card if it has one.

### 6.2 Twists

**Decided 2026-10-17:** each duel offers 3 twists (seeded from the challenge); both players ban
one in secret while picking their squad, and the twist is drawn from the ones left (if both
ban the same, from the two left). It changes which squad is the right one each time,
so the same three squads don't always win. Examples:

- **Fog:** Warriors hit 50% harder in the first 10 seconds.
- **Consecrated Ground:** Undead have no armor.
- **Ambush:** Tanks don't protect anyone in the first 10 seconds.
- **Ley Lines:** Mage splash hits two enemies behind the target.
- **Shield Wall:** Armor takes double the usual off each hit, but everyone is slower.
- **Blood Moon:** Beasts and Demons +25% attack.
- **Calm Waters:** no twist.

Twists are pure rules in the simulation, so both sides apply them the same way.

### 6.3 Stamina: cards get worn out

Every card has a **stamina bar** (0 to 100). It makes you rotate cards instead of always
sending your best ones, so collection depth matters:

- **Fighting drains it** by how much health the card lost in the duel: stamina loss =
  health lost in % x a factor (proposal 0.6, so a card that dies loses 60). A card that
  wasn't hit loses nothing.
- **Resting refills it:** every duel you play where a card doesn't fight gives it stamina
  back (proposal +25).
- **At 0 the card is exhausted:** it sits out your next **2 duels**, then comes back with
  **full** stamina.
- Squads with an exhausted card can't be locked in, so your three squads need spares.
- Counted per duel you play, not per day, so players who duel a lot aren't punished more.
- Stamina has no effect on how a card fights; it only decides whether it can be sent.
- Card UI: a stamina bar under the health, "exhausted: back in 2 duels" when at 0.

### 6.4 Bestiary friends and the board (decided)

**Only Bestiary friends duel each other** and share the board. Adding a friend by name sends a
request (`F|ask`); they get a popup and answer `F|ok` or `F|no`. If both asked each other,
it's a yes on its own. A friendship costs 2 whispers (request, yes).
Removing a friend only takes them off your list. Challenges from players who aren't your
friend are declined ("not friends"), and the challenge button refuses them. Friends have their own
**Friends tab** (`UI/Friends.lua`): add by name or your target; one row per player with the
status (friend, asked, wants to be your friend), your duel record against them and when you
last heard from them, and buttons: Duel / Remove, Accept / Decline, or Ask again / Cancel.

A **Board** tab with short posts (up to 200 characters) shared with your friends. Everyone edits and deletes
only their own posts. Saved account wide (`BestiaryAccount.board`, `Core/Board.lua`,
`UI/Board.lua`). Every post version carries the server time it was written; the newest wins,
a deletion leaves a marker so it syncs too, and posts older than 60 days are dropped
everywhere by the same rule.

**Nothing syncs on its own** (decided): posts, edits and deletes stay on your side until you
press **Sync now** on the Board tab. Then, with as few whispers as possible, only with friends:
- Each friend gets a fingerprint of your board, taken at a given time, plus when you were
  last in sync with them. Same fingerprint: no answer, so 1 whisper per friend. Different:
  they send everything they stored after that time, as one message (in parts if long), and
  answer with their own fingerprint, so you send what they lack the same way: one click
  syncs both sides (4 whispers when both have something new). Nothing they sent you is sent
  back to them.
- Posts travel on: if you share with Bob and Bob with Cid, Cid's posts reach you through Bob.
  Only messages from your contacts are accepted.
- **Tested headless** with up to four simulated clients: online and offline posting, catching
  up on login, edit and delete, only authors change posts, relaying, strangers ignored, long
  posts, old versions never win, both posting while apart (4 whispers to sync); 50 fuzz
  rounds of four players in a ring with 20% loss and random offline times: every board ended
  up the same. And through the UI of two complete clients.

## 7. Hardcore

- **Opt-in** when you start a bestiary on a character: Normal or Hardcore. Can't switch a
  running bestiary to Hardcore later (so nobody collects safely and then switches).
- Hardcore perks: drop chance x1.5, a separate rating, a skull on your cards in duels.
- When the character dies (`PLAYER_DEAD`, or found dead/ghost on login): the bestiary is
  **gone**. It moves to a "Hall of the Fallen" (per account): character, level, days survived,
  card count, best card, duel record. You can start a new one.
- Hardcore means complete loss **of the cards**, on purpose; that's its only death penalty.
  **What you've studied stays** (decided): you still know those mobs. Your own card (3.6)
  stays too, back to 1 star.
- **Implemented (prototype):** a checkbox on the Test tab, per character, with a
  confirmation (`Core/Hardcore.lua`). Feign Death doesn't count, the same death isn't counted
  twice, and a death while the addon was off is caught at the next login. Each loss is saved in
  `BestiaryAccount.fallen` for the Hall of the Fallen. The opt-in lock and the perks above
  come later; for now it can be switched any time.
- **Normal bestiaries:** no penalty when you die.

## 8. Saved data

- **Per character** (`BestiaryChar`): cards, three squads, mode (normal/hardcore), alive, duels,
  rating, anti-farming counters, mob info cache.
- **Account** (`BestiaryAccount`): Hall of the Fallen, settings, a shared mob info cache
  (npcId -> family, classification, class, level, attack speed, measured factors), so alts
  don't need to target a mob first, and the fight log (`fights`, 4.0).

Per character, because the hardcore twist is about that character's life.

## 9. UI

- **Collection:** grid of cards, filters by family/rarity/zone, card detail with stats and
  abilities. Cards are 2D: the mob's name, family icon as art, rarity border, stars, and the
  combat type as a badge (shield, flame, dagger).
- **Squads:** three squads of five slots, drag cards in; each shows its type mix, family
  bonuses and power.
- **Pick screen:** before a duel, your three squads side by side (and what you know about
  theirs); pick one and lock it in.
- **Duels:** list like Quiz Duel (challenge, incoming, finished) with replays.
- **Replay:** both teams side by side, hits and deaths played back over a few seconds, skip
  button.
- **Drop alert** when a card drops, like the game's loss of control alert (decided; the first
  loot-window version sat in the top left corner and went unnoticed): a dark band centered in
  the upper half of the screen with the card's art, "New card" or "+1 star", its name in the
  rarity color, type, rarity, family and power. Shows right away, stays 4 seconds, then fades;
  more drops queue up. Hover keeps it and shows the card, click opens the collection. Rare
  drops louder.
- Minimap button.

## 10. First version (MVP)

1. Kill tracking, mob info cache, card drops, collection list (no fancy UI).
2. Card stats, combat types and abilities from the formula; three squads.
3. Battle simulation with a test fight against a fixed dummy squad, replay as text; headless
   balance runs for the type triangle.
4. Duels over whispers, with sealed picks.
5. Hardcore mode and the Hall of the Fallen.
6. Proper UI (card grid, replay with visuals), balancing.

Headless tests for 3 and 4, like Quiz Duel's (the simulation must give the same result on
both sides for the same seed).

## 11. Decisions

- Name: Bestiary.
- Group and raid kills count (4.1).
- No loot luck for now (4.3).
- Hardcore is complete loss (7).
- Cards are 2D (9).
- Own addon, own git repo and GitHub.
- Combat types Tank, Mage, Assassin per card; squads mix them freely (3.5). Plus Healer:
  works like Mage but heals the lowest ally instead of damaging, never deals damage, no
  limit per squad (3.5, 5.2).
- No card before 10 seconds of seeing that mob type fight (across fights; first decided as
  combat log data, which addons can't read on this client); cards are built from that (4.0).
- Mob level and XP don't matter for drops (grey mobs drop cards, 4.1). ~~Or for card power (3.2)~~:
  dropped 2026-10-17, cards copy the real mob's measured strength (4.0), level included.
- No card for a mob whose casts were only resisted and whose spells are unknown (4.0).
- Studying counts the mob fighting anyone, as long as we can see it (4.0).
- No daily drop cap (4.2).
- Starter boost: drops x5 under 10 cards, then fading with diminishing returns, gone at 40 (3.3).
- No abilities in the first prototype: cards have type, stats and leader bonuses only.
- Drops show as an alert like the loss of control alert, centered in the upper half (9).
- Three prepared squads per player; both pick one in secret before a duel (6).
- A perfect counter wins easily (3.5).
- Power cap per duel, picked by the challenger (6). ~~One fixed cap of 100~~: since 2026-10-17
  power is the card's level and the cap the sum of levels, 5 x your level (3.2).
- Card levels (3.2): start at the mob's level, +1 every 5 duels (won or lost, sparring too),
  at most 3 above your level, 60 (named 63).
- From Warcry: squad size limited only by the power cap, a leader, keywords, twists, roster limits, cards getting
  worn out (6.1). No battle groups, no wild dice, no XP for now.
- Stamina per card: drained by health lost in duels, refilled by resting, 2 duels out at 0
  (6.3).
- You see nothing of the opponent's squads before the fight, only the twist (6).
- Death: hardcore loses the whole bestiary; normal has no penalty (7).

- Turn-based fights (5.2, 2026-10-17): players pick each card's action and target, turns on a
  virtual clock by each mob's real attack time (no rounds), fights at 4x pace, Tanks block
  attacks and spells, squad order doesn't matter. Assassin renamed Warrior. Spells are the mob's real spells (fine tuning open).
- Duels have no timers and survive reloads and being offline (6). One game at a time. 3 twists on offer, each
  player bans one, the twist is drawn from the rest (6.2). The sparring partner plays simply.
- Stars are their own drop (3.3); every duel counts toward card levels, sparring too (3.2).
- Cards follow what's learned about their mob (2026-10-17): type, signature spell and art are
  built again after every fight and at login (a known spell stays until another is used more).

## 12. Open questions

1. Fight rules: the proposal in 5.2, then balance with headless runs.
2. Single fight or best of 3 (6).
3. Cap per level (5 x your level for now, 3.2); stamina numbers (6.3); combat type balance with
   real stats.
4. ~~Stars: how many copies per star~~: stars are their own drop now (3.3).
5. Abilities, after the prototype.

## 13. Prototype (no more mockup)

`Bestiary.toc` loads:

- **Collection tab (prototype, real data):** the tracker (`Core/Tracker.lua`, unit API only)
  studies every mob type it sees fighting; after 10 seconds a kill can drop its card
  (`Core/Cards.lua`). The card's type comes from what the mob did, its art from its signature
  spell. The tab shows your cards and the mob types you're still studying with progress.
  Drops show the drop alert (`UI/Loot.lua`). Saved per character in `BestiaryChar`,
  mob info account-wide in `BestiaryAccount`.
- **Squads tab (real cards):** three squads of your own cards, saved per character
  (`BestiaryChar.squads`, `Core/Squads.lua`), built by drag and drop from your collection;
  power bar, type and family counts, checks. A card you lose drops out of its squads.
- **Duel tab (real cards):** twist, hidden pick (switch freely, drag to reorder, Ready locks it
  in), replay, stamina saved on your real cards. **Challenge target** (or `/bst duel [name]`)
  starts a duel with another player who has Bestiary: they get a popup, pick first, then you
  (protocol in 6). Without one, "New duel" fights the **Sparring
  Partner**: three squads (Tank, Mage and Assassin heavy) of mobs you've seen (not named ones),
  random stars, built up to about your own squads' average power; with fewer than 7 seen mobs
  it uses training cards. The fight (`Core/Fight.lua`) follows 5.2 with Healers and family
  bonuses (3.4). Rules shared by everything are in `Core/Rules.lua`.
- **Studying tab** (arcane eye): the mob types you're studying, most studied first, with
  progress, the card it would give so far and casts seen; hover for details (`UI/Studying.lua`).
  The Collection tab only shows cards now.
- **Stats tab:** duel record, streaks, by squad and twist; leaderboards of your cards (heavy
  hitters, healers, walls, killers, best of the duel, fell the most) and the enemy cards that
  hurt you most; hunting (kills, drops, drop rate, study time) and the collection by rarity,
  type and family. Recorded in `BestiaryChar.stats` (`Core/Stats.lua`) from every finished
  duel, kill and real drop (test drops don't count). `/bst stats`.
- **Info tab:** the rules explained (getting cards, rarity, combat types with leader bonuses,
  family bonuses, leaders, squads, the fight, twists, stamina), built from the same tables and
  numbers the code uses (`UI/Info.lua`), so it stays right while balancing. `/bst info`.
- **Test tab (prototype):** pick a mob (your target or one from the list of mobs seen), see
  the card its next drop would give and everything recorded about it (type and why, drop
  chance), show its drop alert without keeping it, give, rebuild (type and art from today's
  data, stars kept) or remove its card, or
  force a drop on the next kill (skips studying and the roll once, this session only), or
  set the drop chance to 90% until the next drop (studied mobs only, this session only).
  Also: clear the collection (with a confirmation; your own card and study stay), fill it
  with 5 basic cards (common, 1 star: 2 Tank, Mage, Assassin, Healer; not counted as drops),
  and the hardcore checkbox (7).
- `/bst` opens it, `/bst mob` prints everything known about your target's mob type, `/bst
  debug` prints kills and drop rolls, `/bst test` opens the Test tab.

To check in the game client: which unit values are secret in open world combat (if
`UnitAffectingCombat` or GUIDs are secret, studying only works out of the restricted cases),
whether `PARTY_KILL` fires for our kills and pet kills, whether mob spell casts show up
(spell ids secret?), how dungeon bosses report (elite, skull level), UnitCreatureType names in
the client's language, how the drop alert looks.

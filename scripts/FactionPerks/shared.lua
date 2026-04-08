--[[
Faction Perk Pack for OpenMW using ErnPerkFramework.
All 10 vanilla joinable factions. 40 perks total.

ESP REQUIREMENTS - Created in FactionPerkSpells.ESP
  

    TG:
        FPerks_TG1_Passive               = Ability, +5 Agility, +10 Sneak, +10 Security
        FPerks_TG2_Passive               = Ability, +15(10) Agility, +25 Sneak(15), +25 Acrobatics
        FPerks_TG3_Passive               = Ability, +25(10) Agility, +50 Sneak(25), +50 Mercantile
        FPerks_TG4_Passive               = Ability, +25 Luck, +75(65) Security
        FPerks_TG3_Cham                  - Ability, 25 Chameleon
        FPerks_TG4_Cham                  - Ability, 25 Chameleon

    MT:
        FPerks_MT1_Passive               - +5 Speed, +10 Short Blade, +10 Speechcraft
        FPerks_MT2_Passive               - +15 Speed(10), +25 Short Blade(15), +25 Light Armour 
        FPerks_MT3_Passive               - +25 Speed(15), +50 Sneak, +50 Short Blade(25)
        FPerks_MT4_Passive               - +25 Strength, +75 Short Blade(25), +75 Sneak(25)
        FPerks_MT2_Frenzy                - Spell, Frenzy, free, unlimited
        FPerks_MT4_Invisibility          - Spell, Invisibility, free, unlimited
        FPerks_MT4_Lifesteal             - Spell Effect, Absorb Life 25pts 5s

    HH:



    FG:

        FPerks_FG4_Restore_Phys          - Ability, Restore Health 1pt + Restore Fatigue 1pt


    IL:

        FPerks_IL4_Restore_Phys          - Ability, Restore Health 1pt + Restore Fatigue 1pt

    IC:

        FPerks_IC4_AllAttributes         - Power, Fortify All Attributes +50 / 30s, 1/day

    MG:

    TT:
        FPerks_TT1_Passive               - +5 Intelligence, +10 Reflect, +10 Resist Paralysis +10 Resist Blight Disease
        FPerks_TT2_Passive               = +15 Intelligence (10), +25 Reflect(15), +25 Resist Paralysis(15), +25 Resist Blight Disease(15)
        FPerks_TT3_Passive               = +25 Intelligence (19), +50 Reflect(25), +50 Resist Paralysis(25), +50 Resist Blight Disease(25)
        FPerks_TT4_Passive               - +25 Personality, +75 Reflect(25), +75 Resist Paralysis(25), +75 Resist Blight Disease(25)
        FPerks_TT2_Cure_All              - Power. Cure Disease + Cure Poison + Cure Blight Touch, 1/day
        FPerks_TT4_Summon_Army           - Power, Summon 2 Greater Bonewalkers + 2 Bonelords / 60s, 1/day

    HR:

    HT:
        FPerks_HT3_Restore_Magicka_1     - Ability, Restore Magicka 1pt  (HT P3)
        FPerks_HT4_Restore_Magicka_2     - Ability, Restore Magicka 1pt  (HT P4, stacks)


  Vanilla spell IDs used directly:
  "orc_beserk"           FG Perk 3 
  "adrenaline rush"      IL Perk 3
  "divine intervention"  IC Perk 1
  "almsivi intervention" TT Perk 1
  "strong levitate"      HT Perk 1
  "mark"                 HT Perk 2
  "recall"               HT Perk 2

]]

local ns         = require("scripts.FactionPerks.namespace")
local interfaces = require("openmw.interfaces")
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local storage    = require('openmw.storage')
-- ============================================================
--  STORAGE
-- ============================================================
local perkStore = storage.playerSection("FactionPerks")


-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements


local selfIsPlayer = self.type == types.Player
PlayerIsSneaking = false


-- ============================================================
--  MORAG TONG SNEAK ATTACKS
-- ============================================================
function UpdatePlayerSneakStatus(currentSneakStatus)
    PlayerIsSneaking = currentSneakStatus
end

local function MT4AttackSuccessful(attack)

    -- Successful attack check
    if not (attack.sourceType == interfaces.Combat.ATTACK_SOURCE_TYPES.Melee or attack.sourceType == interfaces.Combat.ATTACK_SOURCE_TYPES.Ranged) then--If it's NOT a successful hit with a weapon, back out
        return false
    end 


    -- Proceed

     -- player crouch check
    if attack.attacker.type == types.Player and not PlayerIsSneaking then --If the attacker is the player, and PlayerIsSneaking is true back out
        return false
    end

    --Proceed

    return true --If all are true, then the attack is a successful one
end

function DoMT4Attack(attack)

    if not MT4AttackSuccessful(attack) then return end --If the attack wasn't successful

    -- mesage for debugging
    local msg = "Mephala's Kiss applied!"

    -- if the blow did health damage, produce the magic effect
    if attack.damage.health >= 0 then
        types.Actor.activeSpells(self):add({
        id = "FPerks_MT4_Lifesteal",
        effects = {0}})
    else
        return
    end
end


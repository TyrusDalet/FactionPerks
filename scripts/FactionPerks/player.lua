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

        FPerks_MT2_Frenzy                - Spell, Frenzy, free, unlimited
        FPerks_MT4_Invisibility          - Spell, Invisibility, free, unlimited

    HH:



    FG:

        FPerks_FG4_Restore_Phys          - Ability, Restore Health 1pt + Restore Fatigue 1pt


    IL:

        FPerks_IL4_Restore_Phys          - Ability, Restore Health 1pt + Restore Fatigue 1pt

    IC:

        FPerks_IC4_AllAttributes         - Power, Fortify All Attributes +50 / 30s, 1/day

    MG:

    TT:

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
local ui         = require('openmw.ui')
local types      = require('openmw.types')
local self       = require('openmw.self')
local core       = require('openmw.core')
local nearby     = require('openmw.nearby')
local storage    = require('openmw.storage')

-- ============================================================
--  STORAGE
-- ============================================================
local perkStore = storage.playerSection("FactionPerks")



-- ============================================================
--  MAGIC EFFECTS - loaded once at startup
-- ============================================================
local FX = {}
local function loadFX()
    local function fx(id)
        local e = core.magic.effects.records[id]
        if not e then print("WARNING Faction Perks: effect not found - " .. id) end
        return e
    end
    FX.chameleon       = fx("chameleon")
end
loadFX()

-- ============================================================
--  CORE HELPERS
-- ============================================================

-- Shorthand requirement builders
local R = interfaces.ErnPerkFramework.requirements

-- ============================================================
--  CHAMELEON (Thieves Guild P3 / P4)
-- ============================================================
local chameleonActive = false
local hasChameleon25  = false
local hasChameleon50  = false

local function chameleonMag()
    local m = 0
    if hasChameleon25 then m = m + 25 end
    if hasChameleon50 then m = m + 25 end
    return m
end
local function applyChameleon()
    if not chameleonActive then
        local m = chameleonMag()
        if m >= 25 then 
            types.Actor.spells(self):add("FPerks_TG3_Cham") 
            chameleonActive = true

            if m == 50 then 
                types.Actor.spells(self):add("FPerks_TG4_Cham") 
            end
        end
    end
end
local function removeChameleon()
    if chameleonActive then
        types.Actor.spells(self):remove("FPerks_TG3_Cham")
        types.Actor.spells(self):remove("FPerks_TG4_Cham")
        chameleonActive = false
    end
end

-- ============================================================
--  HLAALU MERCHANT EFFECTS
--  Cumulative Disposition / Mercantile modifier per rank.
--  Rank 1: +10 Disp / -5  Merc
--  Rank 2: +25 Disp / -10 Merc  (total)
--  Rank 3: +50 Disp / -15 Merc  (total)
--  Rank 4: +100 Disp / -20 Merc (total)
-- ============================================================
 
local HH_DISP = { 10, 25, 50, 100 }
local HH_MERC = { -5, -10, -15, -20 }
 
local HH_TALK_MODES = {
    Barter        = true,
    Dialogue      = true,
    Training      = true,
    SpellBuying   = true,
    MerchantRepair = true,
    Enchanting    = true,
    Companion     = true,
}
 
-- The single merchant currently being spoken to, and what we applied.
local hhCurrentMerchant  = nil
local hhCurrentDisp      = 0
local hhCurrentMerc      = 0
 
-- Checks to see if they're an NPC, and whether they have gold.
-- This means it won't work for things like those TG/HH merchants
-- that only sell lockpicks and probes. But that's fine imo
local function isMerchant(actor)
    if not types.NPC.record(actor) then return false end
    local ai = types.NPC.record(actor).aiData
    return ai and ai.hello > 0
        and types.Actor.stats(actor).dynamic.gold
        and types.Actor.stats(actor).dynamic.gold.base > 0
end
 
-- Checks to make sure that you even have the Hlaalu perks
-- Just in case
local function hhTargetValues()
    local rank = perkStore:get("hh_rank") or 0
    if rank == 0 then return 0, 0 end
    return HH_DISP[rank], HH_MERC[rank]
end
 
-- Tracks the current actor, so it knows who to remove the buff from
-- If they don't currently have the buff, apply is
local function hhApplyTo(actor)
    local d, m = hhTargetValues()
    if d == 0 and m == 0 then return end
    local s = types.Actor.stats(actor)
    s.dynamic.disposition.modifier = s.dynamic.disposition.modifier + d
    local ms = s.skills["mercantile"]
    if ms then ms.modifier = ms.modifier + m end
    hhCurrentMerchant = actor
    hhCurrentDisp     = d
    hhCurrentMerc     = m
end
 

-- If the current actor isn't a merchant, does nothing
-- Otherwise clears the buff from the prior actor (if it needs to)
-- and applies it to this one
local function hhRemoveCurrent()
    if not hhCurrentMerchant then return end
    local s = types.Actor.stats(hhCurrentMerchant)
    s.dynamic.disposition.modifier = s.dynamic.disposition.modifier - hhCurrentDisp
    local ms = s.skills["mercantile"]
    if ms then ms.modifier = ms.modifier - hhCurrentMerc end
    hhCurrentMerchant = nil
    hhCurrentDisp     = 0
    hhCurrentMerc     = 0
end
 

-- Main event handler
local function hhOnUiModeChanged(data)
    local rank = perkStore:get("hh_rank") or 0 -- Checks for Hlaalu perks
    if rank == 0 then return end
 
    if not data.newMode then
        -- Dialogue closed entirely - remove modifier from whoever we applied it to.
        hhRemoveCurrent()
        return
    end
 
    -- If a talk is initiated
    if HH_TALK_MODES[data.newMode] and data.arg then
        local npc = data.arg
        if npc == hhCurrentMerchant then return end   -- already applied to this one
        hhRemoveCurrent()                              -- leaving previous NPC mid-session
        if isMerchant(npc) then
            hhApplyTo(npc)
        end
    end
end
 

-- These handle rank changes, enabling some things
-- like if your perk rank somehow changes during conversation
-- to stop it from applying two different rank effects
-- to the same NPC
local function hhRankUp(rank)
    local old = perkStore:get("hh_rank") or 0
    if old >= rank then return end
    perkStore:set("hh_rank", rank)
end
 
local function hhRankDown(rank)
    local cur = perkStore:get("hh_rank") or 0
    if cur < rank then return end
    hhRemoveCurrent()
    perkStore:set("hh_rank", rank - 1)
end

-- ============================================================
--  HOUSE REDORAN DOUBLING BUFF
--  Reads the player's base Strength and Endurance (unmodified)
--  and adds those values as modifiers, effectively doubling them.
--  Recalculates whenever the player levels up so the bonus grows
--  naturally with character progression.
-- ============================================================
local hasRedoranDouble  = false
local redoranStrApplied = 0
local redoranEndApplied = 0
local hasRedoranBounty   = false
local lastOrganicBounty  = 0      -- the bounty value before our additions
local redoranBountyAdded = 0      -- total we have added via doubling
local bountyCheckTimer   = 0
local BOUNTY_CHECK_RATE  = 1.0    -- seconds between checks
 
local function applyRedoranDouble()
    if not hasRedoranDouble then return end
    local s = types.Actor.stats(self)
    -- Remove previous modifier before recalculating
    s.attributes.strength.modifier  = s.attributes.strength.modifier  - redoranStrApplied
    s.attributes.endurance.modifier = s.attributes.endurance.modifier - redoranEndApplied
    -- Base values are always unmodified, so reading them after stripping is safe
    redoranStrApplied = s.attributes.strength.base
    redoranEndApplied = s.attributes.endurance.base
    s.attributes.strength.modifier  = s.attributes.strength.modifier  + redoranStrApplied
    s.attributes.endurance.modifier = s.attributes.endurance.modifier + redoranEndApplied
end
 
local function removeRedoranDouble()
    local s = types.Actor.stats(self)
    s.attributes.strength.modifier  = s.attributes.strength.modifier  - redoranStrApplied
    s.attributes.endurance.modifier = s.attributes.endurance.modifier - redoranEndApplied
    redoranStrApplied = 0
    redoranEndApplied = 0
end
 
-- ============================================================
--  onUpdate
-- ============================================================
local lastLevel = 0
local function onUpdate()
    -- Chameleon sneak tracking
    if hasChameleon25 or hasChameleon50 then
        if self.controls.sneak == true and not chameleonActive then
            applyChameleon()
        elseif not self.controls.sneak == true and chameleonActive then
            removeChameleon()
            end
    elseif chameleonActive then
        removeChameleon()
    end
 
    -- Redoran: recalculate doubling buff on level-up
    local currentLevel = types.Actor.stats.level(self)
    if hasRedoranDouble and currentLevel ~= lastLevel and lastLevel ~= 0 then
        applyRedoranDouble()
    end

  --[[WIP    
    lastLevel = currentLevel
 
    -- Redoran: bounty doubling - checked once per second, not every frame.
    --    Tracks organic bounty (what the game applied) separately from
    --    our own additions, so we never react to changes we made ourselves.
    if hasRedoranBounty then
        bountyCheckTimer = bountyCheckTimer - dt
        if bountyCheckTimer <= 0 then
            bountyCheckTimer = BOUNTY_CHECK_RATE
            local ok, cur = pcall(function() return types.Player.bounty(self) end)
            if ok and cur then
                local organicBounty = cur - redoranBountyAdded
                if organicBounty > lastOrganicBounty then
                    local increase = organicBounty - lastOrganicBounty
                    pcall(function()
                        types.Player.setBounty(self, cur + increase)
                    end)
                    redoranBountyAdded  = redoranBountyAdded + increase
                    lastOrganicBounty   = organicBounty
                elseif organicBounty < lastOrganicBounty then
                    -- Bounty was paid off or reduced - reset our additions proportionally.
                    lastOrganicBounty  = math.max(0, organicBounty)
                    redoranBountyAdded = math.max(0, cur - lastOrganicBounty)
                end
            end
        end
    end
    ]]
end
 
-- ============================================================
--  THIEVES GUILD
--  Primary attribute: Agility
--  Scaling: Sneak, Security, Acrobatics, Mercantile
--  Special: passive Chameleon 25% (Fence Network) - 50% total
--           (Master Thief) while sneaking
-- ============================================================

local tg1_id = ns .. "_tg_light_fingers"
interfaces.ErnPerkFramework.registerPerk({
    id = tg1_id,
    localizedName = "Light Fingers",
    hidden = false,
    localizedDescription = "Years of petty theft have given you an instinct for opportunity. "
        .. "Your hands are quick and your presence quiet.\n "
        .. "(+5 Agility, +10 Sneak, +10 Security)",
    art = "textures\\levelup\\acrobat", cost = 1,
    requirements = {
        R().minimumFactionRank('thieves guild', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_TG1_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_TG1_Passive");
    end,
})

local tg2_id = ns .. "_tg_shadow_step"
interfaces.ErnPerkFramework.registerPerk({
    id = tg2_id,
    localizedName = "Shadow Step",
    --hiden = true,
    localizedDescription = "You have learned to move between pools of darkness with uncanny ease. "
        .. "Guards look straight through you.\n "
        .. "(+15 Agility, +25 Sneak, +25 Acrobatics)",
    art = "textures\\levelup\\acrobat", cost = 2,
    requirements = {
        R().hasPerk(tg1_id),
        R().minimumFactionRank('thieves guild', 3),
        R().minimumAttributeLevel('agility', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_TG2_Passive");
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_TG2_Passive");
    end,
})

local tg3_id = ns .. "_tg_fence_network"
interfaces.ErnPerkFramework.registerPerk({
    id = tg3_id,
    localizedName = "Fence Network",
    --hiden = true,
    localizedDescription = "You have cultivated contacts willing to move stolen goods with no "
        .. "questions asked. When you crouch, shadow swallows you whole.\n "
        .. "Requires Shadow Step. "
        .. "(+20 Agility, +50 Sneak, +50 Mercantile, 25% Chameleon while sneaking)",
    art = "textures\\levelup\\acrobat", cost = 3,
    requirements = {
        R().hasPerk(tg2_id),
        R().minimumFactionRank('thieves guild', 6),
        R().minimumAttributeLevel('agility', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        types.Actor.spells(self):add("FPerks_TG3_Passive");
        hasChameleon25 = true
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_TG3_Passive");
        hasChameleon25 = false
    end,
})

local tg4_id = ns .. "_tg_master_thief"
interfaces.ErnPerkFramework.registerPerk({
    id = tg4_id,
    localizedName = "Master Thief",
    --hiden = true,
    localizedDescription = "There is no lock you cannot pick, no pocket you cannot cut. "
        .. "Crouch, and you vanish almost entirely from sight.\n "
        .. "Requires Fence Network. "
        .. "(+25 Luck, +75 Security, 50% Chameleon while sneaking)",
    art = "textures\\levelup\\acrobat", cost = 4,
    requirements = {
        R().hasPerk(tg3_id),
        R().minimumFactionRank('thieves guild', 9),
        R().minimumAttributeLevel('agility', 75),
        R().minimumLevel(15),
    },
   onAdd = function()
        types.Actor.spells(self):add("FPerks_TG4_Passive");
        hasChameleon50 = true
    end,
    onRemove = function()
        types.Actor.spells(self):remove("FPerks_TG4_Passive");
        hasChameleon50 = false
    end,
})

-- ============================================================
--  MORAG TONG
--  Primary attribute: Speed
--  Scaling: Short Blade, Unarmored, Sneak
--  Special: Frenzy power (Blade Discipline),
--           Invisibility power (Honoured Executioner)
-- ============================================================

local mt1_id = ns .. "_mt_writ_bearer"
interfaces.ErnPerkFramework.registerPerk({
    id = mt1_id,
    localizedName = "Writ Bearer",
    --hiden = true,
    localizedDescription = "You carry the legal sanction of the Morag Tong. "
        .. "Your kills are honoured executions, not murders.\n "
        .. "(+5 Speed, +10 Short Blade)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('morag tong', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() modStat("attribute","speed",5);  modStat("skill","short blade",10);  msg("Writ Bearer granted.") end,
    onRemove = function() modStat("attribute","speed",-5); modStat("skill","short blade",-10); msg("Writ Bearer lost.")    end,
})

local mt2_id = ns .. "_mt_blade_discipline"
interfaces.ErnPerkFramework.registerPerk({
    id = mt2_id,
    localizedName = "Blade Discipline",
    --hiden = true,
    localizedDescription = "The Tong teaches economy of motion. Your strikes are precise "
        .. "and swift. You have learned to channel pure battle-fury at will.\n "
        .. "Requires Writ Bearer. "
        .. "(+15 Speed, +25 Short Blade, +25 Unarmored, grants Frenzy power)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(mt1_id),
        R().minimumFactionRank('morag tong', 3),
        R().minimumAttributeLevel('speed', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        modStat("attribute","speed",   15)
        modStat("skill","short blade", 25)
        modStat("skill","unarmored",   25)
        addSpell("FPerks_MT_Frenzy")
        msg("Blade Discipline granted.")
    end,
    onRemove = function()
        modStat("attribute","speed",   -15)
        modStat("skill","short blade", -25)
        modStat("skill","unarmored",   -25)
        removeSpell("FPerks_MT_Frenzy")
        msg("Blade Discipline lost.")
    end,
})

local mt3_id = ns .. "_mt_calm_before"
interfaces.ErnPerkFramework.registerPerk({
    id = mt3_id,
    localizedName = "Calm Before",
    --hiden = true,
    localizedDescription = "You have learned the art of stillness. "
        .. "A Tong assassin who cannot wait cannot succeed.\n "
        .. "Requires Blade Discipline. "
        .. "(+20 Speed, +50 Sneak, +50 Short Blade)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(mt2_id),
        R().minimumFactionRank('morag tong', 6),
        R().minimumAttributeLevel('speed', 50),
        R().minimumLevel(10),
    },
    onAdd    = function() modStat("attribute","speed",20);  modStat("skill","sneak",50);  modStat("skill","short blade",50);  msg("Calm Before granted.") end,
    onRemove = function() modStat("attribute","speed",-20); modStat("skill","sneak",-50); modStat("skill","short blade",-50); msg("Calm Before lost.")    end,
})

local mt4_id = ns .. "_mt_honoured_executioner"
interfaces.ErnPerkFramework.registerPerk({
    id = mt4_id,
    localizedName = "Honoured Executioner",
    --hiden = true,
    localizedDescription = "The Grand Master himself has commended your work. "
        .. "The shadows open for you whenever you call upon them.\n "
        .. "Requires Calm Before. "
        .. "(+25 Speed, +75 Short Blade, grants Invisibility power)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(mt3_id),
        R().minimumFactionRank('morag tong', 9),
        R().minimumAttributeLevel('speed', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","speed",   25)
        modStat("skill","short blade", 75)
        addSpell("FPerks_MT_Invisibility")
        msg("Honoured Executioner granted.")
    end,
    onRemove = function()
        modStat("attribute","speed",   -25)
        modStat("skill","short blade", -75)
        removeSpell("FPerks_MT_Invisibility")
        msg("Honoured Executioner lost.")
    end,
})

-- ============================================================
--  HOUSE HLAALU
--  Primary attribute: Personality
--  Scaling: Speechcraft, Illusion, Mercantile
--  Special: merchant Disposition / Mercantile modifiers (P1-P4)
--           DOWNSIDE at P4: -25 Disposition to all NPCs
-- ============================================================

local hh1_id = ns .. "_hh_courtesies"
interfaces.ErnPerkFramework.registerPerk({
    id = hh1_id,
    localizedName = "Hlaalu Courtesies",
    --hiden = true,
    localizedDescription = "The formal pleasantries of Great House Hlaalu open many doors. "
        .. "Nearby merchants warm to you and find their resolve to haggle weakened.\n "
        .. "(+5 Personality, +10 Speechcraft, merchants +10 Disposition / -5 Mercantile)",
    art = "textures\\levelup\\healer", cost = 1,
    requirements = {
        R().minimumFactionRank('hlaalu', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() modStat("attribute","personality",5);  modStat("skill","speechcraft",10);  hhRankUp(1);   msg("Hlaalu Courtesies granted.") end,
    onRemove = function() modStat("attribute","personality",-5); modStat("skill","speechcraft",-10); hhRankDown(1); msg("Hlaalu Courtesies lost.")    end,
})

local hh2_id = ns .. "_hh_silver_tongue"
interfaces.ErnPerkFramework.registerPerk({
    id = hh2_id,
    localizedName = "Silver Tongue",
    --hiden = true,
    localizedDescription = "Your words carry weight. Merchants sense your confidence "
        .. "and their prices soften further.\n "
        .. "Requires Hlaalu Courtesies. "
        .. "(+15 Personality, +25 Speechcraft, +25 Illusion, "
        .. "merchants +25 Disposition / -10 Mercantile total)",
    art = "textures\\levelup\\healer", cost = 2,
    requirements = {
        R().hasPerk(hh1_id),
        R().minimumFactionRank('hlaalu', 3),
        R().minimumAttributeLevel('personality', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() modStat("attribute","personality",15);  modStat("skill","speechcraft",25);  modStat("skill","illusion",25);  hhRankUp(2);   msg("Silver Tongue granted.") end,
    onRemove = function() modStat("attribute","personality",-15); modStat("skill","speechcraft",-25); modStat("skill","illusion",-25); hhRankDown(2); msg("Silver Tongue lost.")    end,
})

local hh3_id = ns .. "_hh_trade_acumen"
interfaces.ErnPerkFramework.registerPerk({
    id = hh3_id,
    localizedName = "Trade Acumen",
    --hiden = true,
    localizedDescription = "Merchants treat you as one of their own, dropping their guard further.\n "
        .. "Requires Silver Tongue. "
        .. "(+20 Personality, +50 Mercantile, "
        .. "merchants +50 Disposition / -15 Mercantile total)",
    art = "textures\\levelup\\healer", cost = 3,
    requirements = {
        R().hasPerk(hh2_id),
        R().minimumFactionRank('hlaalu', 6),
        R().minimumAttributeLevel('personality', 50),
        R().minimumLevel(10),
    },
    onAdd    = function() modStat("attribute","personality",20);  modStat("skill","mercantile",50);  hhRankUp(3);   msg("Trade Acumen granted.") end,
    onRemove = function() modStat("attribute","personality",-20); modStat("skill","mercantile",-50); hhRankDown(3); msg("Trade Acumen lost.")    end,
})

local hh4_id = ns .. "_hh_councillors_ear"
interfaces.ErnPerkFramework.registerPerk({
    id = hh4_id,
    localizedName = "Councillor's Ear",
    --hiden = true,
    localizedDescription = "A Councillor of House Hlaalu considers you a trusted confidant. "
        .. "Merchants can barely bring themselves to refuse you anything.\n "
        .. "But your reputation precedes you everywhere now - people smile to your face "
        .. "and count their fingers behind their back. Handing them pocket change "
        .. "is an insult, not a gesture.\n "
        .. "Requires Trade Acumen. "
        .. "(+25 Personality, +75 Speechcraft, "
        .. "merchants +100 Disposition / -20 Mercantile total.\n "
        .. "DOWNSIDE: -25 Disposition with all NPCs.)",
    art = "textures\\levelup\\healer", cost = 4,
    requirements = {
        R().hasPerk(hh3_id),
        R().minimumFactionRank('hlaalu', 9),
        R().minimumAttributeLevel('personality', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","personality", 25)
        modStat("skill","speechcraft",     75)
        hhRankUp(4)
        applyGlobalDisp(HH_GLOBAL_DISP)
        perkStore:set("hh_global_disp", true)
        msg("Councillor's Ear granted.")
    end,
    onRemove = function()
        modStat("attribute","personality", -25)
        modStat("skill","speechcraft",     -75)
        hhRankDown(4)
        applyGlobalDisp(-HH_GLOBAL_DISP)
        perkStore:set("hh_global_disp", false)
        msg("Councillor's Ear lost.")
    end,
})

-- ============================================================
--  FIGHTERS GUILD
--  Primary attribute: Strength
--  Scaling: Fortify Attack (magic effect)
--  Special: vanilla Berserk power (Battle Tested),
--           Restore Health + Fatigue ability (Champion of the Guild)
-- ============================================================

local fg1_id = ns .. "_fg_dues_paid"
interfaces.ErnPerkFramework.registerPerk({
    id = fg1_id,
    localizedName = "Dues Paid",
    --hiden = true,
    localizedDescription = "The basic drills are already sharpening your edge.\n "
        .. "(+5 Strength, +10 Fortify Attack)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('fighters guild', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() modStat("attribute","strength",5);  modEffect(FX.fortifyAttack, 10);  msg("Dues Paid granted.") end,
    onRemove = function() modStat("attribute","strength",-5); modEffect(FX.fortifyAttack,-10);  msg("Dues Paid lost.")    end,
})

local fg2_id = ns .. "_fg_iron_discipline"
interfaces.ErnPerkFramework.registerPerk({
    id = fg2_id,
    localizedName = "Iron Discipline",
    --hiden = true,
    localizedDescription = "The Guild's contracts have hardened you. "
        .. "You wade into battle with the confidence of experience.\n "
        .. "Requires Dues Paid. "
        .. "(+15 Strength, +25 Fortify Attack)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(fg1_id),
        R().minimumFactionRank('fighters guild', 3),
        R().minimumAttributeLevel('strength', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() modStat("attribute","strength",15);  modEffect(FX.fortifyAttack, 25);  msg("Iron Discipline granted.") end,
    onRemove = function() modStat("attribute","strength",-15); modEffect(FX.fortifyAttack,-25);  msg("Iron Discipline lost.")    end,
})

local fg3_id = ns .. "_fg_battle_tested"
interfaces.ErnPerkFramework.registerPerk({
    id = fg3_id,
    localizedName = "Battle Tested",
    --hiden = true,
    localizedDescription = "Daedra, bandits, necromancers - you have killed them all on contract. "
        .. "When the moment demands it, you can call upon a terrifying fury.\n "
        .. "Requires Iron Discipline. "
        .. "(+20 Strength, +50 Fortify Attack, grants Berserk power)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(fg2_id),
        R().minimumFactionRank('fighters guild', 6),
        R().minimumAttributeLevel('strength', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        modStat("attribute","strength",20); modEffect(FX.fortifyAttack,50)
        addSpell("orc_beserk")   -- note: Bethesda's own typo, no second 'e'
        msg("Battle Tested granted.")
    end,
    onRemove = function()
        modStat("attribute","strength",-20); modEffect(FX.fortifyAttack,-50)
        removeSpell("orc_beserk")
        msg("Battle Tested lost.")
    end,
})

local fg4_id = ns .. "_fg_champion_of_the_guild"
interfaces.ErnPerkFramework.registerPerk({
    id = fg4_id,
    localizedName = "Champion of the Guild",
    --hiden = true,
    localizedDescription = "The Fighters Guild holds you as one of its finest. "
        .. "Your body recovers on its own - health and fatigue knit themselves back "
        .. "even in the heat of battle.\n "
        .. "Requires Battle Tested. "
        .. "(+25 Strength, +75 Fortify Attack, Restore Health 1pt/s, Restore Fatigue 1pt/s)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(fg3_id),
        R().minimumFactionRank('fighters guild', 9),
        R().minimumAttributeLevel('strength', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","strength",25); modEffect(FX.fortifyAttack,75)
        addSpell("FPerks_FG_Restore_Phys")
        msg("Champion of the Guild granted.")
    end,
    onRemove = function()
        modStat("attribute","strength",-25); modEffect(FX.fortifyAttack,-75)
        removeSpell("FPerks_FG_Restore_Phys")
        msg("Champion of the Guild lost.")
    end,
})

-- ============================================================
--  MAGES GUILD
--  Primary attribute: Intelligence
--  Scaling: Fortify Magicka (flat) + INT-scaled bonus at P3/P4
-- ============================================================

local mg1_id = ns .. "_mg_guild_initiate"
interfaces.ErnPerkFramework.registerPerk({
    id = mg1_id,
    localizedName = "Guild Initiate",
    --hiden = true,
    localizedDescription = "You have passed the Guild's entrance rites. "
        .. "The library shelves are open to you.\n "
        .. "(+5 Intelligence, +10 Fortify Magicka)",
    art = "textures\\levelup\\mage", cost = 1,
    requirements = {
        R().minimumFactionRank('mages guild', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() modStat("attribute","intelligence",5);  modEffect(FX.fortifyMagicka, 10);  msg("Guild Initiate granted.") end,
    onRemove = function() modStat("attribute","intelligence",-5); modEffect(FX.fortifyMagicka,-10);  msg("Guild Initiate lost.")    end,
})

local mg2_id = ns .. "_mg_scholastic_rigour"
interfaces.ErnPerkFramework.registerPerk({
    id = mg2_id,
    localizedName = "Scholastic Rigour",
    --hiden = true,
    localizedDescription = "The Guild's structured study has sharpened your mind considerably.\n "
        .. "Requires Guild Initiate. "
        .. "(+15 Intelligence, +25 Fortify Magicka)",
    art = "textures\\levelup\\mage", cost = 2,
    requirements = {
        R().hasPerk(mg1_id),
        R().minimumFactionRank('mages guild', 3),
        R().minimumAttributeLevel('intelligence', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() modStat("attribute","intelligence",15);  modEffect(FX.fortifyMagicka, 25);  msg("Scholastic Rigour granted.") end,
    onRemove = function() modStat("attribute","intelligence",-15); modEffect(FX.fortifyMagicka,-25);  msg("Scholastic Rigour lost.")    end,
})

local mg3_id = ns .. "_mg_arcane_reservoir"
interfaces.ErnPerkFramework.registerPerk({
    id = mg3_id,
    localizedName = "Arcane Reservoir",
    --hiden = true,
    localizedDescription = "Years of disciplined spellcasting have deepened your reserves. "
        .. "Your magicka pool expands with your intellect.\n "
        .. "Requires Scholastic Rigour. "
        .. "(+20 Intelligence, +50 Fortify Magicka, "
        .. "Fortify Maximum Magicka 0.5x Intelligence)",
    art = "textures\\levelup\\mage", cost = 3,
    requirements = {
        R().hasPerk(mg2_id),
        R().minimumFactionRank('mages guild', 6),
        R().minimumAttributeLevel('intelligence', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        modStat("attribute","intelligence",20)
        modEffect(FX.fortifyMagicka, 50)
        modEffect(FX.fortifyMaxMagicka, 5)
        msg("Arcane Reservoir granted.")
    end,
    onRemove = function()
        modStat("attribute","intelligence",-20)
        modEffect(FX.fortifyMagicka,-50)
        modEffect(FX.fortifyMaxMagicka,-5)
        msg("Arcane Reservoir lost.")
    end,
})

local mg4_id = ns .. "_mg_archmagisters_peer"
interfaces.ErnPerkFramework.registerPerk({
    id = mg4_id,
    localizedName = "Archmagister's Peer",
    --hiden = true,
    localizedDescription = "The senior mages regard you as a genuine equal. "
        .. "Your intellect feeds your power directly.\n "
        .. "Requires Arcane Reservoir. "
        .. "(+25 Intelligence, +75 Fortify Magicka, "
        .. "Fortify Maximum Magicka 1.0x Intelligence [replaces Arcane Reservoir's 0.5x bonus])",
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(mg3_id),
        R().minimumFactionRank('mages guild', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","intelligence",25)
        modEffect(FX.fortifyMagicka, 75)
        modEffect(FX.fortifyMaxMagicka, 5)   -- adds 5 on top of Arcane Reservoir's 5 = 10 total
        msg("Archmagister's Peer granted.")
    end,
    onRemove = function()
        modStat("attribute","intelligence",-25)
        modEffect(FX.fortifyMagicka,-75)
        modEffect(FX.fortifyMaxMagicka,-5)
        msg("Archmagister's Peer lost.")
    end,
})

-- ============================================================
--  IMPERIAL LEGION
--  Primary attribute: Endurance
--  Scaling: Shield (magic effect)
--  Special: vanilla Adrenaline Rush power (Forced March),
--           Restore Health + Fatigue ability (Legate)
-- ============================================================

local il1_id = ns .. "_il_legion_recruit"
interfaces.ErnPerkFramework.registerPerk({
    id = il1_id,
    localizedName = "Legion Recruit",
    --hiden = true,
    localizedDescription = "You have sworn the oath and donned the cuirass. "
        .. "The Legion's drillmasters have improved your guard.\n "
        .. "(+5 Endurance, +10 Shield)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('imperial legion', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() modStat("attribute","endurance",5);  modEffect(FX.shield, 10);  msg("Legion Recruit granted.") end,
    onRemove = function() modStat("attribute","endurance",-5); modEffect(FX.shield,-10);  msg("Legion Recruit lost.")    end,
})

local il2_id = ns .. "_il_shield_wall"
interfaces.ErnPerkFramework.registerPerk({
    id = il2_id,
    localizedName = "Shield Wall",
    --hiden = true,
    localizedDescription = "You have mastered the disciplined defensive formations of the Imperial army. \n"
        .. "Requires Legion Recruit. "
        .. "(+15 Endurance, +25 Shield)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(il1_id),
        R().minimumFactionRank('imperial legion', 3),
        R().minimumAttributeLevel('endurance', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() modStat("attribute","endurance",15);  modEffect(FX.shield, 25);  msg("Shield Wall granted.") end,
    onRemove = function() modStat("attribute","endurance",-15); modEffect(FX.shield,-25);  msg("Shield Wall lost.")    end,
})

local il3_id = ns .. "_il_forced_march"
interfaces.ErnPerkFramework.registerPerk({
    id = il3_id,
    localizedName = "Forced March",
    --hiden = true,
    localizedDescription = "The Legion demands its soldiers keep pace regardless of terrain. "
        .. "When the situation demands it, you can push far beyond normal limits.\n "
        .. "Requires Shield Wall. "
        .. "(+20 Endurance, +50 Shield, grants Adrenaline Rush power)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(il2_id),
        R().minimumFactionRank('imperial legion', 6),
        R().minimumAttributeLevel('endurance', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        modStat("attribute","endurance",20); modEffect(FX.shield,50)
        addSpell("adrenaline rush")
        msg("Forced March granted.")
    end,
    onRemove = function()
        modStat("attribute","endurance",-20); modEffect(FX.shield,-50)
        removeSpell("adrenaline rush")
        msg("Forced March lost.")
    end,
})

local il4_id = ns .. "_il_legate"
interfaces.ErnPerkFramework.registerPerk({
    id = il4_id,
    localizedName = "Legate",
    --hiden = true,
    localizedDescription = "You command the respect of every soldier who serves alongside you. "
        .. "The Emperor's discipline has forged your body into something that endures.\n "
        .. "Requires Forced March. "
        .. "(+25 Endurance, +75 Shield, Restore Health 1pt/s, Restore Fatigue 1pt/s)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(il3_id),
        R().minimumFactionRank('imperial legion', 9),
        R().minimumAttributeLevel('endurance', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","endurance",25); modEffect(FX.shield,75)
        addSpell("FPerks_IL_Restore_Phys")
        msg("Legate granted.")
    end,
    onRemove = function()
        modStat("attribute","endurance",-25); modEffect(FX.shield,-75)
        removeSpell("FPerks_IL_Restore_Phys")
        msg("Legate lost.")
    end,
})

-- ============================================================
--  IMPERIAL CULT
--  Primary attribute: Willpower
--  Scaling: Resist Disease, Resist Poison, Resist Normal Weapons
--  Special: Divine Intervention spell (Lay Worshipper),
--           1/day Fortify All Attributes power (Blessed of the Nine)
-- ============================================================

local ic1_id = ns .. "_ic_lay_worshipper"
interfaces.ErnPerkFramework.registerPerk({
    id = ic1_id,
    localizedName = "Lay Worshipper",
    --hiden = true,
    localizedDescription = "You have joined the Cult and attend its rites faithfully. "
        .. "The Nine Divines offer you modest but real protection.\n "
        .. "(+5 Willpower, +10 Resist Disease, +10 Resist Poison, "
        .. "+10 Resist Normal Weapons, grants Divine Intervention)",
    art = "textures\\levelup\\healer", cost = 1,
    requirements = {
        R().minimumFactionRank('imperial cult', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        modStat("attribute","willpower",5)
        modEffect(FX.resistDisease,10); modEffect(FX.resistPoison,10); modEffect(FX.resistNormalWpn,10)
        addSpell("divine intervention")
        msg("Lay Worshipper granted.")
    end,
    onRemove = function()
        modStat("attribute","willpower",-5)
        modEffect(FX.resistDisease,-10); modEffect(FX.resistPoison,-10); modEffect(FX.resistNormalWpn,-10)
        removeSpell("divine intervention")
        msg("Lay Worshipper lost.")
    end,
})

local ic2_id = ns .. "_ic_charitable_hand"
interfaces.ErnPerkFramework.registerPerk({
    id = ic2_id,
    localizedName = "Charitable Hand",
    --hiden = true,
    localizedDescription = "You have distributed alms and tended to the sick in the name of the Divines. "
        .. "Your faith has strengthened your body as well as your spirit.\n "
        .. "Requires Lay Worshipper. "
        .. "(+15 Willpower, +25 Resist Disease, +25 Resist Poison, +25 Resist Normal Weapons)",
    art = "textures\\levelup\\healer", cost = 2,
    requirements = {
        R().hasPerk(ic1_id),
        R().minimumFactionRank('imperial cult', 3),
        R().minimumAttributeLevel('willpower', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() modStat("attribute","willpower",15);  modEffect(FX.resistDisease, 25); modEffect(FX.resistPoison, 25); modEffect(FX.resistNormalWpn, 25); msg("Charitable Hand granted.") end,
    onRemove = function() modStat("attribute","willpower",-15); modEffect(FX.resistDisease,-25); modEffect(FX.resistPoison,-25); modEffect(FX.resistNormalWpn,-25); msg("Charitable Hand lost.")    end,
})

local ic3_id = ns .. "_ic_divine_favour"
interfaces.ErnPerkFramework.registerPerk({
    id = ic3_id,
    localizedName = "Divine Favour",
    --hiden = true,
    localizedDescription = "The Divines have marked you as a servant of true worth.\n "
        .. "Requires Charitable Hand. "
        .. "(+20 Willpower, +50 Resist Disease, +50 Resist Poison, +50 Resist Normal Weapons)",
    art = "textures\\levelup\\healer", cost = 3,
    requirements = {
        R().hasPerk(ic2_id),
        R().minimumFactionRank('imperial cult', 6),
        R().minimumAttributeLevel('willpower', 50),
        R().minimumLevel(10),
    },
    onAdd    = function() modStat("attribute","willpower",20);  modEffect(FX.resistDisease, 50); modEffect(FX.resistPoison, 50); modEffect(FX.resistNormalWpn, 50); msg("Divine Favour granted.") end,
    onRemove = function() modStat("attribute","willpower",-20); modEffect(FX.resistDisease,-50); modEffect(FX.resistPoison,-50); modEffect(FX.resistNormalWpn,-50); msg("Divine Favour lost.")    end,
})

local ic4_id = ns .. "_ic_blessed_of_the_nine"
interfaces.ErnPerkFramework.registerPerk({
    id = ic4_id,
    localizedName = "Blessed of the Nine",
    --hiden = true,
    localizedDescription = "The Nine Divines have extended their grace to you directly. "
        .. "Once each day you may call upon their full blessing.\n "
        .. "Requires Divine Favour. "
        .. "(+25 Willpower, +75 Resist Disease, +75 Resist Poison, +75 Resist Normal Weapons, "
        .. "1/day Fortify All Attributes +50 for 30s)",
    art = "textures\\levelup\\healer", cost = 4,
    requirements = {
        R().hasPerk(ic3_id),
        R().minimumFactionRank('imperial cult', 9),
        R().minimumAttributeLevel('willpower', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","willpower",25)
        modEffect(FX.resistDisease,75); modEffect(FX.resistPoison,75); modEffect(FX.resistNormalWpn,75)
        addSpell("myperkpack_ic_allattrib_power")
        msg("Blessed of the Nine granted.")
    end,
    onRemove = function()
        modStat("attribute","willpower",-25)
        modEffect(FX.resistDisease,-75); modEffect(FX.resistPoison,-75); modEffect(FX.resistNormalWpn,-75)
        removeSpell("myperkpack_ic_allattrib_power")
        msg("Blessed of the Nine lost.")
    end,
})

-- ============================================================
--  TRIBUNAL TEMPLE
--  Primary attribute: Willpower
--  Scaling: Reflect, Resist Paralysis, Resist Blight Disease
--  Special: Almsivi Intervention (Ordinate Aspirant),
--           1/day Cure power (Pilgrim Soul),
--           1/day Summon honoured ancestors power (Hand of ALMSIVI)
-- ============================================================

local tt1_id = ns .. "_tt_ordinate_aspirant"
interfaces.ErnPerkFramework.registerPerk({
    id = tt1_id,
    localizedName = "Ordinate Aspirant",
    --hiden = true,
    localizedDescription = "You have taken up the Temple's creed and begun study of its mysteries. "
        .. "ALMSIVI turns aside blows and afflictions that threaten their faithful.\n "
        .. "(+5 Willpower, +10 Reflect, +10 Resist Paralysis, "
        .. "+10 Resist Blight Disease, grants Almsivi Intervention)",
    art = "textures\\levelup\\healer", cost = 1,
    requirements = {
        R().minimumFactionRank('temple', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        modStat("attribute","willpower",5)
        modEffect(FX.reflect,10); modEffect(FX.resistParalysis,10); modEffect(FX.resistBlight,10)
        addSpell("almsivi intervention")
        msg("Ordinate Aspirant granted.")
    end,
    onRemove = function()
        modStat("attribute","willpower",-5)
        modEffect(FX.reflect,-10); modEffect(FX.resistParalysis,-10); modEffect(FX.resistBlight,-10)
        removeSpell("almsivi intervention")
        msg("Ordinate Aspirant lost.")
    end,
})

local tt2_id = ns .. "_tt_pilgrim_soul"
interfaces.ErnPerkFramework.registerPerk({
    id = tt2_id,
    localizedName = "Pilgrim Soul",
    --hiden = true,
    localizedDescription = "You have walked the Pilgrimages of the Seven Graces. "
        .. "Once each day you may call upon ALMSIVI to cleanse disease, poison, and blight.\n "
        .. "Requires Ordinate Aspirant. "
        .. "(+15 Willpower, +25 Reflect, +25 Resist Paralysis, +25 Resist Blight Disease, "
        .. "1/day Cure Disease + Cure Poison + Cure Blight on Touch)",
    art = "textures\\levelup\\healer", cost = 2,
    requirements = {
        R().hasPerk(tt1_id),
        R().minimumFactionRank('temple', 3),
        R().minimumAttributeLevel('willpower', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        modStat("attribute","willpower",15)
        modEffect(FX.reflect,25); modEffect(FX.resistParalysis,25); modEffect(FX.resistBlight,25)
        addSpell("FPerks_TT_Cure_All")
        msg("Pilgrim Soul granted.")
    end,
    onRemove = function()
        modStat("attribute","willpower",-15)
        modEffect(FX.reflect,-25); modEffect(FX.resistParalysis,-25); modEffect(FX.resistBlight,-25)
        removeSpell("FPerks_TT_Cure_All")
        msg("Pilgrim Soul lost.")
    end,
})

local tt3_id = ns .. "_tt_voice_of_reclamation"
interfaces.ErnPerkFramework.registerPerk({
    id = tt3_id,
    localizedName = "Voice of Reclamation",
    --hiden = true,
    localizedDescription = "The Temple's holy authority now speaks through you.\n "
        .. "Requires Pilgrim Soul. "
        .. "(+20 Willpower, +50 Reflect, +50 Resist Paralysis, +50 Resist Blight Disease)",
    art = "textures\\levelup\\healer", cost = 3,
    requirements = {
        R().hasPerk(tt2_id),
        R().minimumFactionRank('temple', 6),
        R().minimumAttributeLevel('willpower', 50),
        R().minimumLevel(10),
    },
    onAdd    = function() modStat("attribute","willpower",20);  modEffect(FX.reflect, 50); modEffect(FX.resistParalysis, 50); modEffect(FX.resistBlight, 50); msg("Voice of Reclamation granted.") end,
    onRemove = function() modStat("attribute","willpower",-20); modEffect(FX.reflect,-50); modEffect(FX.resistParalysis,-50); modEffect(FX.resistBlight,-50); msg("Voice of Reclamation lost.")    end,
})

local tt4_id = ns .. "_tt_hand_of_almsivi"
interfaces.ErnPerkFramework.registerPerk({
    id = tt4_id,
    localizedName = "Hand of ALMSIVI",
    --hiden = true,
    localizedDescription = "You are an instrument of Vivec, Almalexia, and Sotha Sil. "
        .. "Once each day you may call upon honoured ancestors to fight at your side.\n "
        .. "Requires Voice of Reclamation. "
        .. "(+25 Willpower, +75 Reflect, +75 Resist Paralysis, +75 Resist Blight Disease, "
        .. "1/day Summon 2 Greater Bonewalkers + 2 Bonelords for 60s)",
    art = "textures\\levelup\\healer", cost = 4,
    requirements = {
        R().hasPerk(tt3_id),
        R().minimumFactionRank('temple', 9),
        R().minimumAttributeLevel('willpower', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","willpower",25)
        modEffect(FX.reflect,75); modEffect(FX.resistParalysis,75); modEffect(FX.resistBlight,75)
        addSpell("FPerks_TT_Summon_Army")
        msg("Hand of ALMSIVI granted.")
    end,
    onRemove = function()
        modStat("attribute","willpower",-25)
        modEffect(FX.reflect,-75); modEffect(FX.resistParalysis,-75); modEffect(FX.resistBlight,-75)
        removeSpell("FPerks_TT_Summon_Army")
        msg("Hand of ALMSIVI lost.")
    end,
})

-- ============================================================
--  HOUSE REDORAN
--  Primary attribute: Endurance
--  Scaling: Spear, Athletics, Heavy Armor, Block
--  Special P4: Strength & Endurance doubled (base added as modifier),
--              recalculates on level-up, stripped on rest/wait/travel,
--              reapplied after 2s cooldown.
--              DOWNSIDE: bounty increases are doubled.
-- ============================================================

local hr1_id = ns .. "_hr_redoran_pledge"
interfaces.ErnPerkFramework.registerPerk({
    id = hr1_id,
    localizedName = "Redoran Pledge",
    --hiden = true,
    localizedDescription = "You have pledged yourself to House Redoran's code of duty and honour.\n"
        .. "(+5 Endurance, +10 Spear, +10 Athletics)",
    art = "textures\\levelup\\knight", cost = 1,
    requirements = {
        R().minimumFactionRank('redoran', 0),
        R().minimumLevel(1),
    },
    onAdd    = function() modStat("attribute","endurance",5);  modStat("skill","spear",10);  modStat("skill","athletics",10);  msg("Redoran Pledge granted.") end,
    onRemove = function() modStat("attribute","endurance",-5); modStat("skill","spear",-10); modStat("skill","athletics",-10); msg("Redoran Pledge lost.")    end,
})

local hr2_id = ns .. "_hr_burden_of_duty"
interfaces.ErnPerkFramework.registerPerk({
    id = hr2_id,
    localizedName = "Burden of Duty",
    --hiden = true,
    localizedDescription = "Redoran warriors do not complain - they endure. "
        .. "The weight of armour and obligation have become one and the same to you.\n "
        .. "Requires Redoran Pledge. "
        .. "(+15 Endurance, +25 Heavy Armor, +25 Block)",
    art = "textures\\levelup\\knight", cost = 2,
    requirements = {
        R().hasPerk(hr1_id),
        R().minimumFactionRank('redoran', 3),
        R().minimumAttributeLevel('endurance', 40),
        R().minimumLevel(5),
    },
    onAdd    = function() modStat("attribute","endurance",15);  modStat("skill","heavy armor",25);  modStat("skill","block",25);  msg("Burden of Duty granted.") end,
    onRemove = function() modStat("attribute","endurance",-15); modStat("skill","heavy armor",-25); modStat("skill","block",-25); msg("Burden of Duty lost.")    end,
})

local hr3_id = ns .. "_hr_unbroken_line"
interfaces.ErnPerkFramework.registerPerk({
    id = hr3_id,
    localizedName = "Unbroken Line",
    --hiden = true,
    localizedDescription = "House Redoran does not retreat. You have internalised this truth "
        .. "until it became something closer to armour than principle.\n "
        .. "Requires Burden of Duty. "
        .. "(+20 Endurance, +50 Spear, +50 Block)",
    art = "textures\\levelup\\knight", cost = 3,
    requirements = {
        R().hasPerk(hr2_id),
        R().minimumFactionRank('redoran', 6),
        R().minimumAttributeLevel('endurance', 50),
        R().minimumLevel(10),
    },
    onAdd    = function() modStat("attribute","endurance",20);  modStat("skill","spear",50);  modStat("skill","block",50);  msg("Unbroken Line granted.") end,
    onRemove = function() modStat("attribute","endurance",-20); modStat("skill","spear",-50); modStat("skill","block",-50); msg("Unbroken Line lost.")    end,
})

local hr4_id = ns .. "_hr_guardian_of_the_house"
interfaces.ErnPerkFramework.registerPerk({
    id = hr4_id,
    localizedName = "Guardian of the House",
    --hiden = true,
    localizedDescription = "You are House Redoran's shield made flesh. Your honour is "
        .. "unimpeachable, your resolve unyielding - and your strength and endurance "
        .. "are doubled while you stand. Rest strips the fury from you.\n "
        .. "But a Guardian of the House is held to a higher standard than any common soldier. "
        .. "The guards and magistrates of Vvardenfell know your name, and any crime you "
        .. "commit reflects on the House itself - doubling the shame, and the bounty that follows.\n "
        .. "Requires Unbroken Line. "
        .. "(+25 Strength, +75 Spear, +75 Heavy Armor, "
        .. "Strength and Endurance doubled [recalcs on level-up, resets on rest].\n "
        .. "DOWNSIDE: all Bounty received is doubled.)",
    art = "textures\\levelup\\knight", cost = 4,
    requirements = {
        R().hasPerk(hr3_id),
        R().minimumFactionRank('redoran', 9),
        R().minimumAttributeLevel('endurance', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","strength",25)
        modStat("skill","spear",75); modStat("skill","heavy armor",75)
        hasRedoranDouble = true
        hasRedoranBounty = true
        lastBounty   = 0
        lastGameTime = core.getGameTime()
        applyRedoranDouble()
        msg("Guardian of the House granted.")
    end,
    onRemove = function()
        modStat("attribute","strength",-25)
        modStat("skill","spear",-75); modStat("skill","heavy armor",-75)
        removeRedoranDouble()
        hasRedoranDouble = false
        hasRedoranBounty = false
        redoranCooldown  = 0
        msg("Guardian of the House lost.")
    end,
})

-- ============================================================
--  HOUSE TELVANNI
--  Primary attribute: Intelligence
--  Scaling: Enchant, Alchemy, Spell Absorption
--  Special: Strong Levitate spell (Uninvited Student),
--           Mark + Recall spells (Tower Sorcery),
--           INT-scaled Fortify Magicka + Restore Magicka 1pt/s (Self-Made Power),
--           INT-scaled Fortify Magicka upgrade + stacking Restore Magicka (Telvanni Lord)
--           DOWNSIDE at Telvanni Lord: -30 Disposition to all NPCs
-- ============================================================

local ht1_id = ns .. "_ht_uninvited_student"
interfaces.ErnPerkFramework.registerPerk({
    id = ht1_id,
    localizedName = "Uninvited Student",
    --hiden = true,
    localizedDescription = "House Telvanni does not recruit - it tolerates those strong enough "
        .. "to push their way in. You have done so. For now, that is enough.\n "
        .. "(+5 Intelligence, +10 Enchant, +10 Alchemy, +10 Spell Absorption, "
        .. "grants Strong Levitate)",
    art = "textures\\levelup\\mage", cost = 1,
    requirements = {
        R().minimumFactionRank('telvanni', 0),
        R().minimumLevel(1),
    },
    onAdd = function()
        modStat("attribute","intelligence",5)
        modStat("skill","enchant",10); modStat("skill","alchemy",10)
        modEffect(FX.spellAbsorption,10)
        addSpell("strong levitate")
        msg("Uninvited Student granted.")
    end,
    onRemove = function()
        modStat("attribute","intelligence",-5)
        modStat("skill","enchant",-10); modStat("skill","alchemy",-10)
        modEffect(FX.spellAbsorption,-10)
        removeSpell("strong levitate")
        msg("Uninvited Student lost.")
    end,
})

local ht2_id = ns .. "_ht_tower_sorcery"
interfaces.ErnPerkFramework.registerPerk({
    id = ht2_id,
    localizedName = "Tower Sorcery",
    --hiden = true,
    localizedDescription = "Telvanni wizards are defined by their mastery of enchantment. "
        .. "You have begun to understand the principles that animate their towers and servants.\n "
        .. "Requires Uninvited Student. "
        .. "(+15 Intelligence, +25 Enchant, +25 Alchemy, +25 Spell Absorption, "
        .. "grants Mark and Recall)",
    art = "textures\\levelup\\mage", cost = 2,
    requirements = {
        R().hasPerk(ht1_id),
        R().minimumFactionRank('telvanni', 3),
        R().minimumAttributeLevel('intelligence', 40),
        R().minimumLevel(5),
    },
    onAdd = function()
        modStat("attribute","intelligence",15)
        modStat("skill","enchant",25); modStat("skill","alchemy",25)
        modEffect(FX.spellAbsorption,25)
        addSpell("mark"); addSpell("recall")
        msg("Tower Sorcery granted.")
    end,
    onRemove = function()
        modStat("attribute","intelligence",-15)
        modStat("skill","enchant",-25); modStat("skill","alchemy",-25)
        modEffect(FX.spellAbsorption,-25)
        removeSpell("mark"); removeSpell("recall")
        msg("Tower Sorcery lost.")
    end,
})

local ht3_id = ns .. "_ht_self_made_power"
interfaces.ErnPerkFramework.registerPerk({
    id = ht3_id,
    localizedName = "Self-Made Power",
    --hiden = true,
    localizedDescription = "House Telvanni respects only power earned, never granted. "
        .. "You have shaped yourself through relentless study.\n "
        .. "Requires Tower Sorcery. "
        .. "(+20 Intelligence, +50 Enchant, +50 Alchemy, +50 Spell Absorption, "
        .. "Fortify Maximum Magicka 0.5x Intelligence, Restore Magicka 1pt/s)",
    art = "textures\\levelup\\mage", cost = 3,
    requirements = {
        R().hasPerk(ht2_id),
        R().minimumFactionRank('telvanni', 6),
        R().minimumAttributeLevel('intelligence', 50),
        R().minimumLevel(10),
    },
    onAdd = function()
        modStat("attribute","intelligence",20)
        modStat("skill","enchant",50); modStat("skill","alchemy",50)
        modEffect(FX.spellAbsorption, 50)
        modEffect(FX.fortifyMaxMagicka, 5)
        addSpell("FPerks_HT_Restore_Magicka_1")
        msg("Self-Made Power granted.")
    end,
    onRemove = function()
        modStat("attribute","intelligence",-20)
        modStat("skill","enchant",-50); modStat("skill","alchemy",-50)
        modEffect(FX.spellAbsorption,-50)
        modEffect(FX.fortifyMaxMagicka,-5)
        removeSpell("FPerks_HT_Restore_Magicka_1")
        msg("Self-Made Power lost.")
    end,
})

local ht4_id = ns .. "_ht_telvanni_lord"
interfaces.ErnPerkFramework.registerPerk({
    id = ht4_id,
    localizedName = "Telvanni Lord",
    --hiden = true,
    localizedDescription = "You are acknowledged by the Telvanni masters - a rare concession "
        .. "from those who acknowledge no one. The heights are yours to claim.\n "
        .. "But you have become something other people find deeply unsettling. "
        .. "Your isolation and accumulated power have made you alien - ordinary folk "
        .. "sense it before you even open your mouth, and they want nothing to do with you.\n "
        .. "Requires Self-Made Power. "
        .. "(+25 Intelligence, +75 Enchant, +75 Alchemy, +75 Spell Absorption, "
        .. "Fortify Maximum Magicka 1.0x Intelligence [replaces Self-Made Power's 0.5x bonus], "
        .. "additional Restore Magicka 1pt/s [stacks with Self-Made Power for 2pt/s total].\n "
        .. "DOWNSIDE: -30 Disposition with all NPCs.)",
    art = "textures\\levelup\\mage", cost = 4,
    requirements = {
        R().hasPerk(ht3_id),
        R().minimumFactionRank('telvanni', 9),
        R().minimumAttributeLevel('intelligence', 75),
        R().minimumLevel(15),
    },
    onAdd = function()
        modStat("attribute","intelligence",25)
        modStat("skill","enchant",75); modStat("skill","alchemy",75)
        modEffect(FX.spellAbsorption, 75)
        modEffect(FX.fortifyMaxMagicka, 5)   -- adds 5 on top of Self-Made Power's 5 = 10 total
        addSpell("FPerks_HT_Restore_Magicka_2")
        applyGlobalDisp(HT_GLOBAL_DISP)
        perkStore:set("ht_global_disp", true)
        msg("Telvanni Lord granted.")
    end,
    onRemove = function()
        modStat("attribute","intelligence",-25)
        modStat("skill","enchant",-75); modStat("skill","alchemy",-75)
        modEffect(FX.spellAbsorption,-75)
        modEffect(FX.fortifyMaxMagicka,-5)
        removeSpell("FPerks_HT_Restore_Magicka_2")
        applyGlobalDisp(-HT_GLOBAL_DISP)
        perkStore:set("ht_global_disp", false)
        msg("Telvanni Lord lost.")
    end,
})

-- ============================================================
--  ENGINE CALLBACKS
-- ============================================================
return {
    engineHandlers = {
        onUpdate = onUpdate,
        onLoad   = reapplyOnLoad,
    }
}

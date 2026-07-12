--[[
    FactionPerks utils.lua

    Shared utilities for player-context faction scripts.
    Require this file in faction lua files, NOT in npc.lua.
    npc.lua uses shared.lua instead.
]]

local core = require("openmw.core")
local types = require("openmw.types")
local self = require("openmw.self")
local interfaces = require("openmw.interfaces")
local settings = require("scripts.FactionPerks.Settings.settings")

-- ============================================================
--  REPUTATION CAPS
--  Used by Honour The Great House scaling to determine the
--  maximum faction reputation that contributes to the effect.
--  Beyond this cap the bonus does not increase further, to
--  prevent snowballing and to keep the scaling predictable.
--
--  Vanilla Great Houses cap at 125 faction rep.
--  TR_Factions raises these significantly, so we detect that
--  content file and swap to a different cap table.
-- ============================================================

-- ============================================================
--  REPUTATION CAPS
-- ============================================================

local VANILLA_CAPS = {
    hlaalu   = 125,
    redoran  = 125,
    telvanni = 125,
}

local TR_CAPS = {
    hlaalu   = 250,
    redoran  = 175,
    telvanni = 225,
}

local function getRepCap(factionId)
    if core.contentFiles.has("TR_Factions.esp") then
        return TR_CAPS[factionId] or 125
    end
    return VANILLA_CAPS[factionId] or 125
end

-- ============================================================
--  FACTION GROUPS
--
--  Maps each joinable faction to the list of faction IDs that
--  count as membership. Vanilla factions use a single entry.
--  Mods that add regional branches (e.g. Tamriel Rebuilt)
--  are detected here and their branch IDs appended so every
--  perkHidden and FactionGroupRank call stays up to date.
--
--  This is the part that lets new regional branches be added
--  later without editing every faction script again.
-- ============================================================

-- ============================================================
--  FACTION GROUPS
-- ============================================================

local FACTION_GROUPS = {
    thievesGuild      = { 'thieves guild' },
    moragTong         = { 'morag tong' },
    fightersGuild     = { 'fighters guild' },
    magesGuild        = { 'mages guild' },
    imperialLegion    = { 'imperial legion' },
    imperialCult      = { 'imperial cult' },
    temple            = { 'temple' },
    hlaalu            = { 'hlaalu' },
    redoran           = { 'redoran' },
    telvanni          = { 'telvanni' },
    eastEmpireCompany = { 'east empire company' },
}

if core.contentFiles.has("Tamriel_Data.esm") then
    table.insert(FACTION_GROUPS.thievesGuild,   't_cyr_thievesguild')
    table.insert(FACTION_GROUPS.thievesGuild,   't_sky_thievesguild')
    table.insert(FACTION_GROUPS.fightersGuild,  't_cyr_fightersguild')
    table.insert(FACTION_GROUPS.fightersGuild,  't_sky_fightersguild')
    table.insert(FACTION_GROUPS.magesGuild,     't_cyr_magesguild')
    table.insert(FACTION_GROUPS.magesGuild,     't_sky_magesguild')
    table.insert(FACTION_GROUPS.magesGuild,     't_ham_magesguild')
    table.insert(FACTION_GROUPS.imperialLegion, 't_cyr_imperiallegion')
    table.insert(FACTION_GROUPS.imperialLegion, 't_sky_imperiallegion')
    table.insert(FACTION_GROUPS.imperialCult,   't_sky_imperialcult')
    table.insert(FACTION_GROUPS.imperialCult,   't_cyr_itinerantpriests')
end

local function resolve(field)
    if type(field) == 'function' then
        return field()
    end
    return field
end

-- ============================================================
--  SETTINGS ACCESSORS
--
--  These are read once per check so the settings page can
--  control visibility, costs, and requirement enforcement
--  without rewriting the perk records themselves.
-- ============================================================

local function currentVisibilityMode()
    return settings.perkVisibilityMode or 3
end

local function currentCostMode()
    return settings.perkCostMode or 1
end

local function currentRequirementMode()
    return settings.perkRequirementMode or 1
end

local function isMemberOfFaction(factionId)
    for _, foundId in pairs(types.NPC.getFactions(self)) do
        if foundId == factionId then
            return not types.NPC.isExpelled(self, factionId)
        end
    end
    return false
end

-- ============================================================
--  REQUIREMENT WRAPPER
--
--  Returns the standard ErnPerkFramework requirement builders,
--  but with the current settings applied to level/stat/rank
--  requirements. This keeps the faction scripts simple while
--  letting the Settings page decide how strict the perks are.
-- ============================================================

local function requirements()
    local base = interfaces.ErnPerkFramework.requirements()
    local wrapped = {}

    wrapped.minimumLevel = function(level)
        local req = base.minimumLevel(level)
        local baseCheck = req.check
        req.settingKind = "level"
        req.check = function()
            local mode = currentRequirementMode()
            if mode == 1 then
                return baseCheck()
            end
            return true
        end
        return req
    end

    wrapped.minimumSkillLevel = function(skillID, level)
        local req = base.minimumSkillLevel(skillID, level)
        local baseCheck = req.check
        req.settingKind = "stat"
        req.check = function()
            local mode = currentRequirementMode()
            if mode == 1 or mode == 2 then
                return baseCheck()
            end
            return true
        end
        return req
    end

    wrapped.minimumAttributeLevel = function(attributeID, level)
        local req = base.minimumAttributeLevel(attributeID, level)
        local baseCheck = req.check
        req.settingKind = "stat"
        req.check = function()
            local mode = currentRequirementMode()
            if mode == 1 or mode == 2 then
                return baseCheck()
            end
            return true
        end
        return req
    end

    wrapped.minimumFactionRank = function(factionID, rank)
        local req = base.minimumFactionRank(factionID, rank)
        local baseCheck = req.check
        local baseLocalizedName = req.localizedName
        req.settingKind = "rank"
        req.check = function()
            local mode = currentRequirementMode()
            if mode == 4 then
                return isMemberOfFaction(factionID)
            end
            return baseCheck()
        end
        req.localizedName = function()
            local mode = currentRequirementMode()
            if mode == 4 then
                local factionRecord = core.factions.records[factionID]
                return factionRecord.name .. " membership"
            end
            return resolve(baseLocalizedName)
        end
        return req
    end

    wrapped.hasPerk = base.hasPerk
    wrapped.race = base.race
    wrapped.orGroup = base.orGroup
    wrapped.andGroup = base.andGroup
    wrapped.invert = base.invert
    wrapped.vampire = base.vampire
    wrapped.werewolf = base.werewolf
    wrapped.readGlobalVariable = base.readGlobalVariable

    return wrapped
end

-- ============================================================
--  FACTION GROUP RANK
--
--  Builds a rank requirement that accepts any faction in the
--  configured group. This is the branch-aware helper used by
--  the guild scripts so Tamriel_Data branches can be added in
--  one place instead of editing each perk file.
-- ============================================================

local function FactionGroupRank(groupName, rank)
    local factions = FACTION_GROUPS[groupName]
    assert(factions, ("Unknown faction group: %s"):format(tostring(groupName)))

    local reqs = {}
    for _, factionId in ipairs(factions) do
        table.insert(reqs, requirements().minimumFactionRank(factionId, rank))
    end

    if #reqs == 1 then
        return reqs[1]
    end

    return requirements().orGroup(table.unpack(reqs))
end

-- ============================================================
--  FACTION GROUP CURRENT RANK
--
--  Searches through the selected Faction Group's individual
--  ranks, and returns the highest
-- ============================================================

local function FactionGroupCurrentRank(groupName)
    local factions = FACTION_GROUPS[groupName]
    assert(factions, ("Unknown faction group: %s"):format(tostring(groupName)))

    local rank = 0
    local highestRank = 0

    for _, factionId in ipairs(factions) do
        rank = types.NPC.getFactionRank(self, factionId)
        if types.NPC.getFactionRank(self, factionId) > highestRank then
            highestRank = rank
        end
    end
    return highestRank
end

-- ============================================================
--  HONOUR SCALE
--  Returns a scale factor for Honour The Great House effects.
--  Pre-cap it grows linearly; post-cap it keeps growing at a
--  reduced rate so players still get some benefit from more
--  Great House reputation.
-- ============================================================

local function honourScale(factionId)
    local rep = types.NPC.getFactionReputation(self, factionId)
    local cap = getRepCap(factionId)
    if cap <= 0 then return 0 end

    local preCap = math.min(rep, cap) / cap
    local excess = math.max(rep - cap, 0)
    local postCap = (excess / cap) * 0.3

    return preCap + postCap
end

-- ============================================================
--  makeSetRank(perkTable, flagHandlers, appliedStats)
--
--  appliedStats is an optional table owned by the calling file:
--    { attributes = {}, skills = {} }
--  It is mutated by setRank and must be persisted via onSave/onLoad.
--
--  perkTable entries may contain:
--    passive    = { "SpellId", ... }   -- kept for remaining spell effects
--    flags      = { flagName = true }  -- unchanged
--    attributes = { attrId = value }   -- applied via stat.modifier
--    skills     = { skillId = value }   -- applied via stat.modifier
-- ============================================================

local safeAddSpell
local safeRemoveSpell

local function makeSetRank(perkTable, flagHandlers, appliedStats)
    return function(NewRank)
        for _, rankData in pairs(perkTable) do
            if rankData.passive then
                for i = 1, #rankData.passive do
                    safeRemoveSpell(rankData.passive[i])
                end
            end
            if rankData.flags and flagHandlers then
                for flag, _ in pairs(rankData.flags) do
                    if flagHandlers[flag] then
                        flagHandlers[flag](false)
                    end
                end
            end
        end

        if appliedStats then
            for id, val in pairs(appliedStats.attributes or {}) do
                if val ~= 0 then
                    types.Actor.stats.attributes[id](self).modifier =
                        types.Actor.stats.attributes[id](self).modifier - val
                end
            end
            for id, val in pairs(appliedStats.skills or {}) do
                if val ~= 0 then
                    types.NPC.stats.skills[id](self).modifier =
                        types.NPC.stats.skills[id](self).modifier - val
                end
            end
            appliedStats.attributes = {}
            appliedStats.skills = {}
        end

        if not NewRank or not perkTable[NewRank] then return end
        local rankData = perkTable[NewRank]

        if rankData.passive then
            for i = 1, #rankData.passive do
                safeAddSpell(rankData.passive[i])
            end
        end

        if appliedStats then
            if rankData.attributes then
                for id, val in pairs(rankData.attributes) do
                    types.Actor.stats.attributes[id](self).modifier =
                        types.Actor.stats.attributes[id](self).modifier + val
                    appliedStats.attributes[id] = val
                end
            end
            if rankData.skills then
                for id, val in pairs(rankData.skills) do
                    types.NPC.stats.skills[id](self).modifier =
                        types.NPC.stats.skills[id](self).modifier + val
                    appliedStats.skills[id] = val
                end
            end
        end

        if rankData.flags and flagHandlers then
            for flag, value in pairs(rankData.flags) do
                if flagHandlers[flag] then
                    flagHandlers[flag](value)
                end
            end
        end
    end
end

-- ============================================================
--  perkHidden(factionIds, minimumRank, minimumLevel)
--
--  Returns a function suitable for the ErnPerkFramework hidden
--  field. The visibility mode setting decides how much of the
--  requirement chain must be met before a perk is revealed.
--
--  mode 1: never hidden
--  mode 2: hide unless faction membership is met
--  mode 3: hide unless membership + rank are met
--  mode 4: hide unless membership + rank + level are met
--  mode 5: hide unless all requirements are met
-- ============================================================

local function perkHidden(factionIds, minimumRank, minimumLevel)
    if type(factionIds) == "string" then
        factionIds = { factionIds }
    end

    minimumRank = minimumRank or 0
    minimumLevel = minimumLevel or 1

    return function(perk)
        local mode = currentVisibilityMode()
        if mode == 1 then
            return false
        end
        if mode == 5 then
            if perk and type(perk.evaluateRequirements) == "function" then
                local result = perk:evaluateRequirements()
                return not (result and result.satisfied)
            end
            return false
        end

        local idSet = {}
        for _, id in ipairs(factionIds) do
            idSet[id] = true
        end

        local membership = false
        local rankOK = false
        for _, foundId in pairs(types.NPC.getFactions(self)) do
            if idSet[foundId] and not types.NPC.isExpelled(self, foundId) then
                membership = true
                if mode == 2 then
                    break
                end
                local rank = types.NPC.getFactionRank(self, foundId) or 0
                if rank >= (minimumRank + 1) then
                    rankOK = true
                    if mode == 3 then
                        break
                    end
                end
            end
        end

        if not membership then
            return true
        end
        if mode == 2 then
            return false
        end
        if mode == 3 then
            return not rankOK
        end

        if not rankOK then
            return true
        end

        local level = types.Actor.stats.level(self).current
        return level < minimumLevel
    end
end

-- ============================================================
--  PERK COSTS
--  Default mode uses the tier number as the point cost.
--  Cheap mode forces everything to 1 point.
--  Free mode drops faction perks to 0.
-- ============================================================

local function perkCost(tier)
    local mode = currentCostMode()
    if mode == 2 then
        return 1
    elseif mode == 3 then
        return 0
    end
    return tier
end

-- ============================================================
--  safeAddSpell(spellId) / safeRemoveSpell(spellId)
--
--  Idempotent wrappers around Actor.spells:add/remove.
--  safeAddSpell checks whether the spell is already present
--  before adding, preventing duplicate entries on load when
--  ErnPerkFramework re-fires onAdd for every held perk.
--  safeRemoveSpell is a no-op if the spell isn't present,
--  matching the same safe pattern.
-- ============================================================

local function validSpellId(spellId)
    return type(spellId) == "string"
        and spellId ~= ""
        and spellId ~= "Empty{}"
        and core.magic.spells.records[spellId] ~= nil
end

safeAddSpell = function(spellId)
    if not validSpellId(spellId) then return end
    local spells = types.Actor.spells(self)
    if not spells[spellId] then
        spells:add(spellId)
    end
end

safeRemoveSpell = function(spellId)
    if not validSpellId(spellId) then return end
    local spells = types.Actor.spells(self)
    if spells[spellId] then
        spells:remove(spellId)
    end
end


return {
    getRepCap       = getRepCap,
    honourScale     = honourScale,
    makeSetRank     = makeSetRank,
    FactionGroupRank = FactionGroupRank,
    perkCost        = perkCost,
    perkHidden      = perkHidden,
    requirements    = requirements,
    safeAddSpell    = safeAddSpell,
    safeRemoveSpell = safeRemoveSpell,
    FactionGroupCurrentRank = FactionGroupCurrentRank,
    FACTION_GROUPS  = FACTION_GROUPS,
}

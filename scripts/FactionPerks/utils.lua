--[[
    FactionPerks utils.lua

    Shared utilities for player-context faction scripts.
    Actor-context combat helpers live in shared.lua and actor.lua.
]]

local core = require("openmw.core")
local types = require("openmw.types")
local self = require("openmw.self")
local interfaces = require("openmw.interfaces")
local settings = require("scripts.FactionPerks.settings")

local MOD_NAME = "FactionPerks"

-- ============================================================
--  REPUTATION CAPS
--  Used by Honour The Great House scaling to determine the
--  maximum faction reputation that contributes to the effect.
--  Vanilla Great Houses cap at 125 faction rep. TR_Factions
--  raises these, so we detect that content file and swap tables.
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

--- Returns the faction reputation cap used by Honour The Great House scaling.
--- @param factionId string Vanilla lowercase faction id.
--- @return number cap Reputation value treated as the normal full-scaling point.
local function getRepCap(factionId)
    if core.contentFiles.has("TR_Factions.esp") then
        return TR_CAPS[factionId] or 125
    end
    return VANILLA_CAPS[factionId] or 125
end

-- ============================================================
--  FACTION GROUPS
--  Maps each joinable faction to the list of faction IDs that
--  count as membership. Vanilla factions use a single entry.
--  Tamriel_Data branches are appended once here so every faction
--  script stays branch-aware without duplicating IDs.
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

--- Resolves a literal value or a zero-argument function used by wrapped records.
--- @param field any Literal value or function.
--- @return any resolved The literal value, or the function return value.
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

--- Reads the current perk visibility setting with a defensive default.
--- @return number mode Visibility mode selected in mod settings.
local function currentVisibilityMode()
    return settings.perkVisibilityMode or 3
end

--- Reads the current perk cost setting with a defensive default.
--- @return number mode Cost mode selected in mod settings.
local function currentCostMode()
    return settings.perkCostMode or 1
end

--- Reads the current requirement strictness setting with a defensive default.
--- @return number mode Requirement mode selected in mod settings.
local function currentRequirementMode()
    return settings.perkRequirementMode or 1
end

--- Reads the current debug logging verbosity with a defensive default.
--- @return number mode Debug verbosity selected in mod settings.
local function currentDebugVerbosity()
    return settings.debugVerbosity or 0
end

--- Checks whether tier 4 leader-training acquisition is active.
--- @return boolean enabled True when P4 perks must be unlocked through dialogue.
local function leaderTrainingEnabled()
    return settings.leaderTrainingEnabled == true
end

--- Checks current player membership, excluding expelled memberships.
--- @param factionId string Faction id to test.
--- @return boolean member True when the player is an active member.
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

--- Returns framework requirement builders wrapped with FactionPerks settings.
--- @return table wrapped Requirement builder table.
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

--- Builds a rank requirement that accepts any faction in a configured group.
--- @param groupName string Key in FACTION_GROUPS.
--- @param rank number Zero-based faction rank, matching UESP-facing rank numbers.
--- @return table requirement ErnPerkFramework requirement data.
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

--- Returns the highest current rank across every faction in a configured group.
--- @param groupName string Key in FACTION_GROUPS.
--- @return number rank Highest OpenMW faction rank found, or 0.
local function FactionGroupCurrentRank(groupName)
    local factions = FACTION_GROUPS[groupName]
    assert(factions, ("Unknown faction group: %s"):format(tostring(groupName)))

    local highestRank = 0

    for _, factionId in ipairs(factions) do
        local rank = types.NPC.getFactionRank(self, factionId) or 0
        if rank > highestRank then
            highestRank = rank
        end
    end
    return highestRank
end

--- Checks whether the player meets a strict faction-group rank.
--- Unlike the normal wrapped requirement builder, this ignores the FactionPerks
--- requirement-mode setting. Use it for acquisition gates that must remain hard
--- requirements even in debug or relaxed modes.
--- @param groupName string Key in FACTION_GROUPS.
--- @param rank number Zero-based required faction rank.
--- @return boolean met True when the player has at least rank + 1 in the group.
local function hasStrictFactionGroupRank(groupName, rank)
    return FactionGroupCurrentRank(groupName) >= (rank + 1)
end

--- Builds a hard faction-group rank requirement.
--- @param groupName string Key in FACTION_GROUPS.
--- @param rank number Zero-based required faction rank.
--- @return table requirement ErnPerkFramework requirement data.
local function StrictFactionGroupRank(groupName, rank)
    return {
        id = MOD_NAME .. "_strictFactionGroupRank_" .. groupName,
        localizedName = function()
            local group = FACTION_GROUPS[groupName]
            local names = {}
            for _, factionId in ipairs(group or {}) do
                local record = core.factions.records[factionId]
                if record then
                    local rankRecord = record.ranks[rank + 1]
                    table.insert(names, record.name .. " " .. ((rankRecord and rankRecord.name) or tostring(rank + 1)))
                end
            end
            if #names == 0 then
                return groupName .. " rank " .. tostring(rank + 1)
            end
            return table.concat(names, " or ")
        end,
        check = function()
            return hasStrictFactionGroupRank(groupName, rank)
        end,
    }
end

-- ============================================================
--  HONOUR SCALE
--  Returns a scale factor for Honour The Great House effects.
--  Pre-cap it grows linearly; post-cap it keeps growing at a
--  reduced rate so players still get some benefit from more
--  Great House reputation.
-- ============================================================

--- Computes Honour The Great House scaling from current faction reputation.
--- @param factionId string Great House faction id.
--- @return number scale Linear pre-cap scale plus reduced post-cap excess.
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

--- Creates the standard rank application function used by faction perk chains.
--- The returned function removes all previous passive spells, flags, and tracked
--- stat modifiers before applying the selected rank.
--- @param perkTable table Rank-indexed perk effect data.
--- @param flagHandlers table|nil Optional flag name -> setter callback table.
--- @param appliedStats table|nil Persisted stat modifier tracker.
--- @return function setRank Function accepting a rank number or nil.
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

--- Builds a hidden predicate for faction perk records using visibility settings.
--- @param factionIds string|table Accepted faction id or ids.
--- @param minimumRank number|nil Zero-based minimum rank used by visibility modes.
--- @param minimumLevel number|nil Minimum player level used by visibility mode 4.
--- @return function hidden Predicate suitable for ErnPerkFramework perk data.
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

--- Wraps a perk hidden predicate so leader-trained P4 perks stay out of the menu.
--- When leader training is disabled, the original hidden predicate is used. When
--- enabled, unowned and untrained P4 perks remain hidden regardless of visibility
--- mode; owned perks still appear because the framework always shows active perks.
--- @param leaderKey string Leader-training key registered by leader_training.lua.
--- @param baseHidden function|boolean|nil Existing hidden predicate.
--- @return function hidden Combined hidden predicate.
local function leaderTrainingHidden(leaderKey, baseHidden)
    return function(perk)
        if leaderTrainingEnabled() then
            local leaderTraining = interfaces.FactionPerksLeaderTraining
            if not leaderTraining or not leaderTraining.isUnlocked(leaderKey) then
                return true
            end
        end
        if type(baseHidden) == "function" then
            return baseHidden(perk)
        end
        return baseHidden == true
    end
end

--- Creates the hidden acquisition-token requirement for a leader-trained P4 perk.
--- The requirement is omitted while leader training is disabled, so old menu-based
--- acquisition behaves as before. While enabled, the dialogue handler unlocks this
--- requirement immediately before attempting to grant the perk.
--- @param leaderKey string Leader-training key registered by leader_training.lua.
--- @return table requirement ErnPerkFramework requirement data.
local function leaderTrainingRequirement(leaderKey)
    return {
        id = MOD_NAME .. "_leaderTraining_" .. leaderKey,
        localizedName = "Leadership instruction",
        omit = function()
            return not leaderTrainingEnabled()
        end,
        hidden = true,
        check = function()
            local leaderTraining = interfaces.FactionPerksLeaderTraining
            return leaderTraining and leaderTraining.isUnlocked(leaderKey)
        end,
    }
end

--- Creates the hard rank requirement used by leader-trained P4 perks.
--- This is omitted while the feature is disabled so the old menu-based
--- acquisition path and requirement-mode settings behave as they did before.
--- @param groupName string Key in FACTION_GROUPS.
--- @param rank number Zero-based required faction rank.
--- @return table requirement ErnPerkFramework requirement data.
local function leaderTrainingRankRequirement(groupName, rank)
    local req = StrictFactionGroupRank(groupName, rank)
    req.id = MOD_NAME .. "_leaderTrainingRank_" .. groupName
    req.omit = function()
        return not leaderTrainingEnabled()
    end
    return req
end

-- ============================================================
--  PERK COSTS
--  Default mode uses the tier number as the point cost.
--  Cheap mode forces everything to 1 point.
--  Free mode drops faction perks to 0.
-- ============================================================

--- Resolves a tier's point cost under the current FactionPerks cost mode.
--- @param tier number Default tier cost.
--- @return number cost Effective perk point cost.
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

--- Adds a spell only when the player does not already have it.
--- @param spellId string Spell id.
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

--- Removes a spell only when the player currently has it.
--- @param spellId string Spell id.
safeRemoveSpell = function(spellId)
    if not validSpellId(spellId) then return end
    local spells = types.Actor.spells(self)
    if spells[spellId] then
        spells:remove(spellId)
    end
end

-- ============================================================
--  AAM / MODIFIER REPORTING
--
--  ErnPerkFramework owns optional AbilitiesAsModifiers interop.
--  Keep a fallback here so FactionPerks remains tolerant of older
--  framework builds during development.
-- ============================================================

--- Reports rank stat modifiers through the framework/AAM compatibility path.
--- @param sourceName string Label shown by AbilitiesAsModifiers.
--- @param rankData table|nil Rank data containing attributes/skills, or nil to clear.
--- @return boolean reported True when a reporting interface accepted the data.
local function reportExternalModifiers(sourceName, rankData)
    if interfaces.ErnPerkFramework and interfaces.ErnPerkFramework.reportExternalModifiers then
        return interfaces.ErnPerkFramework.reportExternalModifiers(sourceName, rankData)
    end

    if not interfaces.AAM then
        return false
    end

    if rankData == nil then
        interfaces.AAM.reportExternalModifiers(sourceName, nil)
        return true
    end

    local report = {}
    for id, val in pairs(rankData.attributes or {}) do report[id] = val end
    for id, val in pairs(rankData.skills or {}) do report[id] = val end

    if next(report) then
        interfaces.AAM.reportExternalModifiers(sourceName, report)
    else
        interfaces.AAM.reportExternalModifiers(sourceName, nil)
    end
    return true
end

--- Logs a debug message when the configured verbosity is high enough.
--- @param level number Required verbosity level, from 1 to 3.
--- @param source string Short subsystem/faction label.
--- @param message string Message to print.
local function debug(level, source, message)
    if currentDebugVerbosity() >= level then
        print("FactionPerks[" .. tostring(source) .. "]: " .. tostring(message))
    end
end

--- Returns the highest owned perk rank from a rank-indexed id table.
--- @param rankIDs table Rank number -> perk id.
--- @param defaultRank number|nil Value returned when no ids are owned.
--- @return number rank Highest owned rank, or defaultRank/0.
local function highestOwnedPerkRank(rankIDs, defaultRank)
    local owned = interfaces.ErnPerkFramework.getPlayerPerkSet()

    local maxRank = 0
    for rank in pairs(rankIDs) do
        if type(rank) == "number" and rank > maxRank then
            maxRank = rank
        end
    end

    for rank = maxRank, 1, -1 do
        local perkID = rankIDs[rank]
        if perkID and owned[perkID] == true then
            return rank
        end
    end
    return defaultRank or 0
end

--- Creates the standard AAM reporter closure used by faction scripts.
--- @param sourceName string Label shown by AbilitiesAsModifiers.
--- @param perkTable table Rank-indexed perk data.
--- @param getRank function Function returning the current rank.
--- @return function reporter No-argument reporter function.
local function makeAAMReporter(sourceName, perkTable, getRank)
    return function()
        reportExternalModifiers(sourceName, perkTable[getRank()])
    end
end

--- Reverses saved stat modifiers and clears the live appliedStats tracker.
--- Use during onLoad before ErnPerkFramework re-fires onAdd for active perks.
--- @param savedStats table|nil Saved appliedStats table.
--- @param appliedStats table Live appliedStats table captured by makeSetRank.
local function clearSavedAppliedStats(savedStats, appliedStats)
    savedStats = savedStats or { attributes = {}, skills = {} }
    for id, val in pairs(savedStats.attributes or {}) do
        if val ~= 0 then
            types.Actor.stats.attributes[id](self).modifier =
                types.Actor.stats.attributes[id](self).modifier - val
        end
    end
    for id, val in pairs(savedStats.skills or {}) do
        if val ~= 0 then
            types.NPC.stats.skills[id](self).modifier =
                types.NPC.stats.skills[id](self).modifier - val
        end
    end
    appliedStats.attributes = {}
    appliedStats.skills = {}
end

--- Builds the standard direct health damage event payload.
--- @param amount number Raw direct damage amount.
--- @param source GameObject|nil Source actor or object.
--- @param sourceEffect string|nil Stable id for the source effect.
--- @param damageType string|nil Damage classification, e.g. physical or divine.
--- @param extra table|nil Extra context fields to merge into the payload.
--- @return table payload Event payload for FPerks_TakeDamage.
local function directHealthDamagePayload(amount, source, sourceEffect, damageType, extra)
    local payload = extra or {}
    payload.amount = amount
    payload.source = source
    payload.sourceEffect = sourceEffect
    payload.damageType = damageType
    return payload
end

--- Normalizes player-entered console commands before matching.
--- Trims surrounding whitespace, removes trailing "\" markers seen in some
--- OpenMW console paths, and collapses repeated spaces so scripts can use
--- exact command comparisons instead of broad prefix matches.
--- @param command string|nil Raw console command.
--- @return string command Normalized command text.
local function normalizeConsoleCommand(command)
    command = tostring(command or "")
    command = command:match("^%s*(.-)%s*$")
    command = command:gsub("%s*\\+$", "")
    command = command:match("^%s*(.-)%s*$")
    return command:gsub("%s+", " ")
end

return {
    MOD_NAME        = MOD_NAME,
    getRepCap       = getRepCap,
    honourScale     = honourScale,
    makeSetRank     = makeSetRank,
    FactionGroupRank = FactionGroupRank,
    StrictFactionGroupRank = StrictFactionGroupRank,
    hasStrictFactionGroupRank = hasStrictFactionGroupRank,
    perkCost        = perkCost,
    perkHidden      = perkHidden,
    leaderTrainingEnabled = leaderTrainingEnabled,
    leaderTrainingHidden = leaderTrainingHidden,
    leaderTrainingRequirement = leaderTrainingRequirement,
    leaderTrainingRankRequirement = leaderTrainingRankRequirement,
    requirements    = requirements,
    safeAddSpell    = safeAddSpell,
    safeRemoveSpell = safeRemoveSpell,
    reportExternalModifiers = reportExternalModifiers,
    debug = debug,
    highestOwnedPerkRank = highestOwnedPerkRank,
    makeAAMReporter = makeAAMReporter,
    clearSavedAppliedStats = clearSavedAppliedStats,
    directHealthDamagePayload = directHealthDamagePayload,
    normalizeConsoleCommand = normalizeConsoleCommand,
    FactionGroupCurrentRank = FactionGroupCurrentRank,
    FACTION_GROUPS  = FACTION_GROUPS,
}

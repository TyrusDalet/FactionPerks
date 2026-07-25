--[[
    FactionPerks leader_training.lua

    Handles the optional dialogue-based acquisition path for tier 4 faction
    perks. The matching topic must exist in content, then this script performs
    the runtime faction/rank checks and grants the relevant perk.
]]

local core = require("openmw.core")
local interfaces = require("openmw.interfaces")
local self = require("openmw.self")
local types = require("openmw.types")
local ui = require("openmw.ui")
local utils = require("scripts.FactionPerks.utils")

local MOD_NAME = "FactionPerks"
local localization = core.l10n(MOD_NAME)
local TOPIC = string.lower(localization("leaderTrainingTopic"))
local PLAYER_REQUIRED_RANK = 9
local SPEAKER_REQUIRED_RANK = 7

local grantInProgress = {}
local topicAdded = false

local LEADER_ORDER = {
    "fightersGuild",
    "imperialLegion",
    "imperialCult",
    "magesGuild",
    "thievesGuild",
    "moragTong",
    "temple",
    "hlaalu",
    "redoran",
    "telvanni",
    "eastEmpireCompany",
}

local LEADER_PERKS = {
    fightersGuild = {
        perkID = MOD_NAME .. "_fg_champion_of_the_guild",
        groupName = "fightersGuild",
    },
    imperialLegion = {
        perkID = MOD_NAME .. "_il_legate",
        groupName = "imperialLegion",
    },
    imperialCult = {
        perkID = MOD_NAME .. "_ic_blessed_of_the_nine",
        groupName = "imperialCult",
    },
    magesGuild = {
        perkID = MOD_NAME .. "_mg_archmagisters_peer",
        groupName = "magesGuild",
    },
    thievesGuild = {
        perkID = MOD_NAME .. "_tg_master_thief",
        groupName = "thievesGuild",
    },
    moragTong = {
        perkID = MOD_NAME .. "_mt_honoured_executioner",
        groupName = "moragTong",
    },
    temple = {
        perkID = MOD_NAME .. "_tt_hand_of_almsivi",
        groupName = "temple",
    },
    hlaalu = {
        perkID = MOD_NAME .. "_hh_councillors_ear",
        groupName = "hlaalu",
    },
    redoran = {
        perkID = MOD_NAME .. "_hr_guardian_of_the_house",
        groupName = "redoran",
    },
    telvanni = {
        perkID = MOD_NAME .. "_ht_telvanni_lord",
        groupName = "telvanni",
    },
    eastEmpireCompany = {
        perkID = MOD_NAME .. "_eec_senior_factor",
        groupName = "eastEmpireCompany",
    },
}

--- Returns the localized display name for a faction id.
--- @param factionId string Faction id.
--- @return string name Display name, or the raw id if the record is missing.
local function factionName(factionId)
    local record = core.factions.records[factionId]
    return (record and record.name) or factionId
end

--- Returns the display name for a dialogue speaker.
--- @param actor GameObject Dialogue speaker.
--- @return string name NPC name.
local function actorName(actor)
    local record = actor and types.NPC.record(actor)
    return (record and record.name) or "This speaker"
end

--- Checks whether an NPC can teach one leader perk.
--- The player must be rank 10 in the faction group and the speaker must be rank
--- 7 or higher in one of the same concrete faction ids.
--- @param actor GameObject Dialogue speaker.
--- @param data table Leader perk metadata.
--- @return string|nil factionId Concrete faction id that qualified.
local function qualifyingFaction(actor, data)
    if not actor or not actor:isValid() or not types.NPC.objectIsInstance(actor) then
        return nil
    end
    if not utils.hasStrictFactionGroupRank(data.groupName, PLAYER_REQUIRED_RANK) then
        return nil
    end

    local factions = utils.FACTION_GROUPS[data.groupName] or {}
    for _, factionId in ipairs(factions) do
        if not types.NPC.isExpelled(self, factionId) then
            local playerRank = types.NPC.getFactionRank(self, factionId) or 0
            local speakerRank = types.NPC.getFactionRank(actor, factionId) or 0
            if playerRank >= (PLAYER_REQUIRED_RANK + 1) and speakerRank >= SPEAKER_REQUIRED_RANK then
                return factionId
            end
        end
    end
    return nil
end

--- Finds the first leader perk this speaker can teach.
--- @param actor GameObject Dialogue speaker.
--- @return string|nil key Leader-training key.
--- @return table|nil data Leader perk metadata.
--- @return string|nil factionId Concrete faction id that qualified.
local function findTraining(actor)
    for _, key in ipairs(LEADER_ORDER) do
        local data = LEADER_PERKS[key]
        local factionId = qualifyingFaction(actor, data)
        if factionId then
            return key, data, factionId
        end
    end
    return nil
end

--- Handles the leader-training topic selection and grants the matching P4 perk.
--- @param event table DialogueResponse event data.
local function onDialogueResponse(event)
    if not utils.leaderTrainingEnabled() or event.recordId ~= TOPIC then
        return
    end

    local key, data, factionId = findTraining(event.actor)
    local speakerName = actorName(event.actor)
    if not key then
        ui.showMessage(localization("leaderTrainingNotEligible", { speaker = speakerName }), { showInDialogue = true })
        return
    end

    local framework = interfaces.ErnPerkFramework
    local perk = framework.getPerk(data.perkID)
    if not perk then
        utils.debug(1, "LeaderTraining", "Missing registered leader perk " .. tostring(data.perkID))
        return
    end
    if framework.playerHasPerk(data.perkID) then
        ui.showMessage(localization("leaderTrainingAlreadyKnown", {
            speaker = speakerName,
            factionName = factionName(factionId),
        }), { showInDialogue = true })
        return
    end

    grantInProgress[key] = true
    local granted, reason = framework.grantPerk(data.perkID, {
        checkRequirements = true,
        checkCost = false,
    })
    grantInProgress[key] = nil
    if not granted then
        if reason == "requirements" then
            ui.showMessage(localization("leaderTrainingRequirementsMissing", {
                speaker = speakerName,
                perkName = perk:name(),
            }), { showInDialogue = true })
        else
            utils.debug(1, "LeaderTraining", "grantPerk(" .. data.perkID .. ") failed: " .. tostring(reason))
        end
        return
    end

    ui.showMessage(localization("leaderTrainingGranted", {
        speaker = speakerName,
        factionName = factionName(factionId),
        perkName = perk:name(),
    }), { showInDialogue = true })
end

--- Makes the shared topic known to the player when the feature is enabled.
local function onUpdate()
    if utils.leaderTrainingEnabled() and not topicAdded then
        self.type.addTopic(self, TOPIC)
        topicAdded = true
    end
end

--- Returns whether a leader perk may currently satisfy its instruction token.
--- The token exists only during the dialogue grant or while the perk is already
--- owned. Respeccing therefore locks the menu entry until the conversation is
--- completed again instead of leaving a permanent free-purchase permission.
--- @param key string Leader-training key.
--- @return boolean unlocked True during its dialogue grant or while owned.
local function isUnlocked(key)
    if grantInProgress[key] then
        return true
    end

    local data = LEADER_PERKS[key]
    local framework = interfaces.ErnPerkFramework
    return data ~= nil
        and framework ~= nil
        and framework.playerHasPerk(data.perkID)
end

local function onSave()
    return {}
end

local function onLoad(_)
    grantInProgress = {}
end

return {
    interfaceName = MOD_NAME .. "LeaderTraining",
    interface = {
        isUnlocked = isUnlocked,
        leaderPerks = LEADER_PERKS,
    },
    eventHandlers = {
        DialogueResponse = onDialogueResponse,
    },
    engineHandlers = {
        onUpdate = onUpdate,
        onSave = onSave,
        onLoad = onLoad,
    },
}

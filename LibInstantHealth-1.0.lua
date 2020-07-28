local major = "LibInstantHealth-1.0"
local minor = tonumber(string.match("@project-version@", "^v(%d+).*$")) or 1000000

assert(LibStub, format("%s requires LibStub", major))

local InstantHealth, oldminor = LibStub:NewLibrary(major, minor)

if not InstantHealth then
    return
end

local eventHandlers = {}

InstantHealth.callbacks = InstantHealth.callbacks or LibStub("CallbackHandler-1.0"):New(InstantHealth)

local callbacks = InstantHealth.callbacks

InstantHealth.eventFrame = InstantHealth.eventFrame or CreateFrame("Frame")
InstantHealth.eventFrame:UnregisterAllEvents()
InstantHealth.eventFrame:SetScript(
    "OnEvent",
    function(self, event, ...)
        eventHandlers[event](event, ...)
    end
)

local eventFrame = InstantHealth.eventFrame

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_ADDED")
eventFrame:RegisterEvent("FORBIDDEN_NAME_PLATE_UNIT_REMOVED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_HEALTH_FREQUENT")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

if oldminor and oldminor <= 4 then
    if InstantHealth.delayFrame then
        InstantHealth.delayFrame:UnregisterAllEvents()
        InstantHealth.delayFrame = nil
    end

    if InstantHealth.dummyFrame then
        InstantHealth.dummyFrame:UnregisterAllEvents()
        InstantHealth.dummyFrame = nil
    end

    if InstantHealth.unitHealth then
        wipe(InstantHealth.unitHealth)
    end

    InstantHealth.unitHealthMax = nil
    InstantHealth.unitIDs = nil
    InstantHealth.unitPartyIDs = nil
    InstantHealth.petGUIDs = nil
end

if oldminor and oldminor <= 5 then
    InstantHealth.unitHealth = nil
end

InstantHealth.units = InstantHealth.units or {}
InstantHealth.unitHealthFrequentEventQueue = InstantHealth.unitHealthFrequentEventQueue or {}

local units = InstantHealth.units
local unitHealthFrequentEventQueue = InstantHealth.unitHealthFrequentEventQueue
local targetGUID = UnitGUID("target")

local UNITS_SOLO = {"player"}
local UNITS_PARTY = {"player"}
local UNITS_RAID = {}

for i = 1, MAX_PARTY_MEMBERS do
    tinsert(UNITS_PARTY, "party" .. i)
end

for i = 1, MAX_RAID_MEMBERS do
    tinsert(UNITS_RAID, "raid" .. i)
end

local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local wipe = wipe
local bit_band = bit.band

local COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local COMBATLOG_OBJECT_AFFILIATION_OUTSIDER = COMBATLOG_OBJECT_AFFILIATION_OUTSIDER

InstantHealth.eventFrame:SetScript(
    "OnUpdate",
    function()
        for unit in pairs(unitHealthFrequentEventQueue) do
            local subgroupID = unit.subgroupID

            if subgroupID then
                callbacks:Fire("UNIT_HEALTH_FREQUENT", subgroupID)
            end

            local groupID = unit.groupID

            callbacks:Fire("UNIT_HEALTH_FREQUENT", groupID)

            local nameplateID = unit.nameplateID

            if nameplateID then
                callbacks:Fire("UNIT_HEALTH_FREQUENT", nameplateID)
            end

            if unit.guid == targetGUID then
                callbacks:Fire("UNIT_HEALTH_FREQUENT", "target")
            end
        end

        wipe(unitHealthFrequentEventQueue)
    end
)

function InstantHealth.UnitHealth(unitID)
    local unitGUID = UnitGUID(unitID)
    local unit = units[unitGUID]

    local unitHealth = UnitHealth(unitID)
    local unitHealthFrequent = unit and unit.healthFrequent

    if not unitHealthFrequent then
        return unitHealth
    end

    local unitHealthMax = unit.healthMax

    if unitHealthFrequent <= 1 then
        return 1
    end

    if unitHealthFrequent >= unitHealthMax then
        return unitHealthMax
    end

    return unitHealthFrequent
end

InstantHealth.UnitHealthMax = UnitHealthMax

function eventHandlers.PLAYER_TARGET_CHANGED()
    targetGUID = UnitGUID("target")
end

function eventHandlers.NAME_PLATE_UNIT_ADDED(event, unitID)
    local unitGUID = UnitGUID(unitID)
    local unit = units[unitGUID]

    if unit then
        unit.nameplateID = unitID
    end
end

function eventHandlers.NAME_PLATE_UNIT_REMOVED(event, unitID)
    local unitGUID = UnitGUID(unitID)
    local unit = units[unitGUID]

    if unit then
        unit.nameplateID = nil
    end
end

eventHandlers.FORBIDDEN_NAME_PLATE_UNIT_ADDED = eventHandlers.NAME_PLATE_UNIT_ADDED
eventHandlers.FORBIDDEN_NAME_PLATE_UNIT_REMOVED = eventHandlers.NAME_PLATE_UNIT_REMOVED

function eventHandlers.GROUP_ROSTER_UPDATE()
    local unitIDs

    if GetNumGroupMembers() == 0 then
        unitIDs = UNITS_SOLO
    elseif not IsInRaid() then
        unitIDs = UNITS_PARTY
    else
        unitIDs = UNITS_RAID
    end

    for _, unitID in ipairs(unitIDs) do
        local unitGUID = UnitGUID(unitID)

        if unitGUID then
            if not units[unitGUID] then
                units[unitGUID] = {
                    guid = unitGUID,
                    health = UnitHealth(unitID),
                    healthMax = UnitHealthMax(unitID),
                    healthFrequentUpdate = false,
                    nameplateID = C_NamePlate.GetNamePlateForUnit(unitID, true)
                }

                assert(units[unitGUID].health)
                assert(units[unitGUID].healthMax)
            end

            units[unitGUID].groupID = unitID
            units[unitGUID].subgroupID = nil
        end
    end

    if IsInRaid() then
        for _, unitID in ipairs(UNITS_PARTY) do
            local unitGUID = UnitGUID(unitID)

            if unitGUID then
                units[unitGUID].subgroupID = unitID
            end
        end
    end

    for unitGUID, unit in pairs(units) do
        if unitGUID ~= UnitGUID(unit.groupID) then
            units[unitGUID] = nil
        end
    end
end

eventHandlers.PLAYER_ENTERING_WORLD = eventHandlers.GROUP_ROSTER_UPDATE

function eventHandlers.UNIT_HEALTH(event, unitID)
    local unitGUID = UnitGUID(unitID)
    local unit = units[unitGUID]

    if unit then
        local unitHealth = UnitHealth(unitID)

        unit.health = unitHealth

        if unitHealth == 0 then
            unit.healthFrequent = nil
        else
            unit.healthFrequent = unitHealth
        end

        unit.healthMax = UnitHealthMax(unitID)

        unitHealthFrequentEventQueue[unit] = nil
    end

    callbacks:Fire(event, unitID)
end

function eventHandlers.UNIT_MAXHEALTH(event, unitID)
    local unitGUID = UnitGUID(unitID)
    local unit = units[unitGUID]

    if unit then
        local unitHealthMax = UnitHealthMax(unitID)

        if unit.healthMax ~= unitHealthMax then
            unit.healthMax = unitHealthMax
        end
    end

    callbacks:Fire(event, unitID)
end

function eventHandlers.UNIT_HEALTH_FREQUENT(event, unitID)
    local unitGUID = UnitGUID(unitID)
    local unit = units[unitGUID]

    if unit then
        unitHealthFrequentEventQueue[unit] = nil
    end

    callbacks:Fire(event, unitID)
end

local clueEventHandlers = {}

function clueEventHandlers.RANGE_DAMAGE(spellId, spellName, spellSchool, amount, overkill)
    return overkill > 0 and overkill - amount or -amount
end

clueEventHandlers.SPELL_DAMAGE = clueEventHandlers.RANGE_DAMAGE
clueEventHandlers.SPELL_PERIODIC_DAMAGE = clueEventHandlers.RANGE_DAMAGE
clueEventHandlers.DAMAGE_SPLIT = clueEventHandlers.RANGE_DAMAGE
clueEventHandlers.DAMAGE_SHIELD = clueEventHandlers.RANGE_DAMAGE

function clueEventHandlers.ENVIRONMENTAL_DAMAGE(environmentalType, amount, overkill)
    return overkill > 0 and overkill - amount or -amount
end

function clueEventHandlers.SPELL_HEAL(spellId, spellName, spellSchool, amount, overhealing)
    return amount - overhealing
end

clueEventHandlers.SPELL_PERIODIC_HEAL = clueEventHandlers.SPELL_HEAL

function eventHandlers.COMBAT_LOG_EVENT_UNFILTERED()
    local _, event, _, _, _, _, _, unitGUID, _, unitFlags, _, arg12, arg13, arg14, arg15, arg16 = CombatLogGetCurrentEventInfo()

    if bit_band(unitFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 or bit_band(unitFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == 0 then
        return
    end

    local clueEventHandler = clueEventHandlers[event]

    if not clueEventHandler then
        return
    end

    local unit = units[unitGUID]

    if not unit then
        return
    end

    local unitHealthFrequent = unit.healthFrequent

    if not unitHealthFrequent then
        return
    end

    local healthChange = clueEventHandler(arg12, arg13, arg14, arg15, arg16)

    if healthChange ~= 0 then
        unit.healthFrequent = unitHealthFrequent + healthChange
        unitHealthFrequentEventQueue[unit] = true
    end
end

if IsLoggedIn() then
    eventHandlers.PLAYER_ENTERING_WORLD()
end

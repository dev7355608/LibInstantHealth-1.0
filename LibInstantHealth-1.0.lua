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

InstantHealth.unitHealth = InstantHealth.unitHealth or {}

local unitHealth = InstantHealth.unitHealth

local groupNone = {"player"}
local groupParty = {"player"}
local groupRaid = {}

for i = 1, MAX_PARTY_MEMBERS do
    tinsert(groupParty, "party" .. i)
end

for i = 1, MAX_RAID_MEMBERS do
    tinsert(groupRaid, "raid" .. i)
end

local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsUnit = UnitIsUnit
local UnitInRaid = UnitInRaid
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local C_NamePlate = C_NamePlate

local bit_band = bit.band

local COMBATLOG_OBJECT_TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local COMBATLOG_OBJECT_AFFILIATION_OUTSIDER = COMBATLOG_OBJECT_AFFILIATION_OUTSIDER
local COMBATLOG_OBJECT_AFFILIATION_PARTY = COMBATLOG_OBJECT_AFFILIATION_PARTY
local COMBATLOG_OBJECT_AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE

function InstantHealth.UnitHealth(unit)
    local unitGUID = UnitGUID(unit)

    local health = unitHealth[unitGUID]

    if not health or UnitIsFeignDeath(unit) then
        return UnitHealth(unit)
    end

    local healthMax = UnitHealthMax(unit)

    if health <= 0 then
        health = 1
    end

    if health > healthMax then
        health = healthMax
    end

    return health
end

InstantHealth.UnitHealthMax = UnitHealthMax

local function fireEvent(...)
    callbacks:Fire(...)
end

function eventHandlers.GROUP_ROSTER_UPDATE()
    local group

    if GetNumGroupMembers() == 0 then
        group = groupNone
    elseif not IsInRaid() then
        group = groupParty
    else
        group = groupRaid
    end

    local unitIDs = {}

    for _, unit in ipairs(group) do
        local unitGUID = UnitGUID(unit)

        if unitGUID then
            unitIDs[unitGUID] = unit

            if not unitHealth[unitGUID] then
                unitHealth[unitGUID] = false
            end
        end
    end

    for unitGUID in pairs(unitHealth) do
        if not unitIDs[unitGUID] then
            unitHealth[unitGUID] = nil
        end
    end
end

eventHandlers.PLAYER_ENTERING_WORLD = eventHandlers.GROUP_ROSTER_UPDATE

function eventHandlers.UNIT_HEALTH(event, unit)
    local unitGUID = UnitGUID(unit)

    if unitHealth[unitGUID] ~= nil then
        unitHealth[unitGUID] = UnitHealth(unit)
    end

    fireEvent(event, unit)
end

eventHandlers.UNIT_MAXHEALTH = fireEvent
eventHandlers.UNIT_HEALTH_FREQUENT = fireEvent

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
    local _, event, _, _, _, _, _, unitGUID, unitName, unitFlags, _, arg12, arg13, arg14, arg15, arg16 = CombatLogGetCurrentEventInfo()

    if bit_band(unitFlags, COMBATLOG_OBJECT_AFFILIATION_OUTSIDER) > 0 or bit_band(unitFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == 0 then
        return
    end

    local clueEventHandler = clueEventHandlers[event]

    if not clueEventHandler then
        return
    end

    local health = unitHealth[unitGUID]

    if not health then
        return
    end

    local healthChange = clueEventHandler(arg12, arg13, arg14, arg15, arg16)

    if healthChange ~= 0 then
        unitHealth[unitGUID] = health + healthChange

        local unit1

        if bit_band(unitFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) > 0 then
            unit1 = "player"
        elseif bit_band(unitFlags, COMBATLOG_OBJECT_AFFILIATION_PARTY) > 0 then
            if UnitIsUnit(unitName, "party1") then
                unit1 = "party1"
            elseif UnitIsUnit(unitName, "party2") then
                unit1 = "party2"
            elseif UnitIsUnit(unitName, "party3") then
                unit1 = "party3"
            else
                unit1 = "party4"
            end
        end

        if unit1 then
            fireEvent("UNIT_HEALTH_FREQUENT", unit1)
        end

        local unit2 = groupRaid[UnitInRaid(unitName)]

        if unit2 then
            fireEvent("UNIT_HEALTH_FREQUENT", unit2)
        end

        local unit = unit2 or unit1

        local nameplate = C_NamePlate.GetNamePlateForUnit(unit, true)

        if nameplate then
            fireEvent("UNIT_HEALTH_FREQUENT", nameplate.UnitFrame.unit)
        end

        if UnitIsUnit(unit, "target") then
            fireEvent("UNIT_HEALTH_FREQUENT", "target")
        end
    end
end

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
        eventHandlers[event](...)
    end
)

local eventFrame = InstantHealth.eventFrame

InstantHealth.delayFrame = InstantHealth.delayFrame or CreateFrame("Frame")
InstantHealth.delayFrame:UnregisterAllEvents()
InstantHealth.delayFrame:SetScript(
    "OnEvent",
    function()
        eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    end
)

local delayFrame = InstantHealth.delayFrame

InstantHealth.dummyFrame = InstantHealth.dummyFrame or CreateFrame("Frame")
InstantHealth.dummyFrame:UnregisterAllEvents()

local dummyFrame = InstantHealth.dummyFrame

InstantHealth.unitHealth = InstantHealth.unitHealth or {}
InstantHealth.unitHealthMax = InstantHealth.unitHealthMax or {}
InstantHealth.unitIDs = InstantHealth.unitIDs or {}
InstantHealth.unitPartyIDs = InstantHealth.unitPartyIDs or {}
InstantHealth.petGUIDs = InstantHealth.petGUIDs or {}

local unitHealth = InstantHealth.unitHealth
local unitHealthMax = InstantHealth.unitHealthMax
local unitIDs = InstantHealth.unitIDs
local unitPartyIDs = InstantHealth.unitPartyIDs
local petGUIDs = InstantHealth.petGUIDs

local groupNone = {"player"}
local groupParty = {"player"}
local groupRaid = {}

for i = 1, MAX_PARTY_MEMBERS do
    tinsert(groupParty, "party" .. i)
end

for i = 1, MAX_RAID_MEMBERS do
    tinsert(groupRaid, "raid" .. i)
end

local petIDs = {["player"] = "pet"}

for i = 1, MAX_PARTY_MEMBERS do
    petIDs["party" .. i] = "partypet" .. i
end

for i = 1, MAX_RAID_MEMBERS do
    petIDs["raid" .. i] = "raidpet" .. i
end

local wipe = wipe
local math = math
local UnitGUID = UnitGUID
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsFeignDeath = UnitIsFeignDeath
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local C_NamePlate = C_NamePlate

local function fireEvent(...)
    callbacks:Fire(...)
end

local function fireEventAll(event, unit)
    fireEvent(event, unit)

    local unit2 = unitPartyIDs[unit]

    if unit2 then
        fireEvent(event, unit2)
    end

    if UnitIsUnit(unit, "target") then
        fireEvent(event, "target")
    end

    local nameplate = C_NamePlate.GetNamePlateForUnit(unit)

    if nameplate then
        fireEvent(event, nameplate.UnitFrame.unit)
    end
end

local function updateHealth(unit)
    local unitGUID = UnitGUID(unit)
    unit = unitIDs[unitGUID]

    if not unit then
        return
    end

    local health = unitHealth[unitGUID]
    local healthMax = unitHealthMax[unitGUID]

    local newHealth = UnitHealth(unit)
    local newHealthMax = UnitHealthMax(unit)

    if newHealth == 0 and not UnitIsFeignDeath(unit) then
        newHealth = nil
    end

    local healthUpdate = newHealth ~= health
    local healthMaxUpdate = newHealthMax ~= healthMax

    if healthUpdate or healthMaxUpdate then
        unitHealth[unitGUID] = newHealth
        unitHealthMax[unitGUID] = newHealthMax
    end

    return healthUpdate, healthMaxUpdate
end

function InstantHealth.UnitHealth(unit)
    local unitGUID = UnitGUID(unit)

    if not unitIDs[unitGUID] then
        return UnitHealth(unit)
    end

    local health = unitHealth[unitGUID]
    local healthMax = unitHealthMax[unitGUID]

    if not health then
        health = 0
    else
        if health < 1 then
            health = 1
        end

        if health > healthMax then
            health = healthMax
        end
    end

    return health
end

function InstantHealth.UnitHealthMax(unit)
    local unitGUID = UnitGUID(unit)

    if not unitIDs[unitGUID] then
        return UnitHealthMax(unit)
    end

    return unitHealthMax[unitGUID]
end

function eventHandlers.UNIT_PET(unit)
    local unitGUID = UnitGUID(unit)

    unit = unitIDs[unitGUID]

    if not unit then
        return
    end

    local pet = petIDs[unit]
    local petGUID = UnitGUID(pet)

    local lastPetGUID = petGUIDs[unitGUID]

    if petGUID ~= lastPetGUID then
        if lastPetGUID then
            unitIDs[lastPetGUID] = nil
            unitHealth[lastPetGUID] = nil
        end

        petGUIDs[unitGUID] = petGUID

        if petGUID then
            unitIDs[petGUID] = pet

            updateHealth(pet)

            fireEventAll("UNIT_HEALTH", pet)
            fireEventAll("UNIT_MAXHEALTH", pet)
            fireEventAll("UNIT_HEALTH_FREQUENT", pet)
        end
    end
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

    for _, unit in ipairs(group) do
        local unitGUID = UnitGUID(unit)

        if unitGUID then
            unitIDs[unitGUID] = unit

            local pet = petIDs[unit]
            local petGUID = UnitGUID(pet)

            petGUIDs[unitGUID] = petGUID

            if petGUID then
                unitIDs[petGUID] = pet
            end
        end
    end

    wipe(unitPartyIDs)

    if IsInRaid() then
        for _, unit in ipairs(groupParty) do
            local unitGUID = UnitGUID(unit)

            if unitGUID then
                local unit2 = unitIDs[unitGUID]
                unitPartyIDs[unit2] = unit
                unitPartyIDs[petIDs[unit2]] = petIDs[unit]
            end
        end
    end

    for unitGUID, unit in pairs(unitIDs) do
        if unitGUID ~= UnitGUID(unit) then
            unitHealth[unitGUID] = nil
            unitHealthMax[unitGUID] = nil
            unitIDs[unitGUID] = nil
            petGUIDs[unitGUID] = nil
        else
            local healthUpdate, healthMaxUpdate = updateHealth(unit)

            if healthUpdate or healthMaxUpdate then
                fireEventAll("UNIT_HEALTH", unit)
                fireEventAll("UNIT_MAXHEALTH", unit)
                fireEventAll("UNIT_HEALTH_FREQUENT", unit)
            end
        end
    end
end

function eventHandlers.PLAYER_ENTERING_WORLD()
    eventFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")

    eventHandlers.GROUP_ROSTER_UPDATE()
end

function eventHandlers.UNIT_MAXHEALTH(unit)
    local healthUpdate = updateHealth(unit)

    if healthUpdate == nil then
        fireEvent("UNIT_MAXHEALTH", unit)
        return
    end

    fireEventAll("UNIT_MAXHEALTH", unit)
end

function eventHandlers.UNIT_HEALTH(unit)
    local healthUpdate = updateHealth(unit)

    if healthUpdate == nil then
        fireEvent("UNIT_HEALTH", unit)
        return
    end

    fireEventAll("UNIT_HEALTH", unit)
end

function eventHandlers.UNIT_HEALTH_FREQUENT(unit)
    local healthUpdate = updateHealth(unit)

    if healthUpdate == nil then
        fireEvent("UNIT_HEALTH_FREQUENT", unit)
        return
    end

    fireEventAll("UNIT_HEALTH_FREQUENT", unit)
end

function eventHandlers.UNIT_CONNECTION(unit)
    local healthUpdate = updateHealth(unit)

    if healthUpdate == nil then
        return
    end

    fireEventAll("UNIT_HEALTH", unit)
    fireEventAll("UNIT_MAXHEALTH", unit)
    fireEventAll("UNIT_HEALTH_FREQUENT", unit)
end

function eventHandlers.UNIT_DIED(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags)
    if UnitIsFeignDeath(unitIDs[destGUID]) then
        return 0, 0
    else
        return nil, -math.huge
    end
end

function eventHandlers.SPELL_INSTAKILL(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags)
    return nil, -math.huge
end

-- function eventHandlers.SWING_DAMAGE(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
--     overkill = overkill and overkill > 0 and overkill or 0
--     local change = overkill - amount
--     return change, -overkill
-- end

-- function eventHandlers.RANGE_DAMAGE(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
--     overkill = overkill and overkill > 0 and overkill or 0
--     local change = overkill - amount
--     return change, -overkill
-- end

-- eventHandlers.SPELL_DAMAGE = eventHandlers.RANGE_DAMAGE
-- eventHandlers.SPELL_PERIODIC_DAMAGE = eventHandlers.RANGE_DAMAGE
-- eventHandlers.DAMAGE_SPLIT = eventHandlers.RANGE_DAMAGE
-- eventHandlers.DAMAGE_SHIELD = eventHandlers.RANGE_DAMAGE

-- function eventHandlers.ENVIRONMENTAL_DAMAGE(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, environmentalType, amount, overkill, school, resisted, blocked, absorbed, critical, glancing, crushing, isOffHand)
--     overkill = overkill and overkill > 0 and overkill or 0
--     local change = overkill - amount
--     return change, -overkill
-- end

-- eventHandlers.SPELL_DAMAGE = eventHandlers.RANGE_DAMAGE
-- eventHandlers.SPELL_PERIODIC_DAMAGE = eventHandlers.RANGE_DAMAGE
-- eventHandlers.DAMAGE_SPLIT = eventHandlers.RANGE_DAMAGE
-- eventHandlers.DAMAGE_SHIELD = eventHandlers.RANGE_DAMAGE

function eventHandlers.SPELL_HEAL(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, spellId, spellName, spellSchool, amount, overhealing, absorbed, critical)
    local change = amount - overhealing
    return change, overhealing
end

eventHandlers.SPELL_PERIODIC_HEAL = eventHandlers.SPELL_HEAL

function eventHandlers.ENVIRONMENTAL_HEAL(timestamp, event, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags, destGUID, destName, destFlags, destRaidFlags, environmentalType, amount, overhealing, absorbed, critical)
    local change = amount - overhealing
    return change, overhealing
end

function eventHandlers.COMBAT_LOG_EVENT_UNFILTERED()
    eventFrame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    local _, event, _, _, _, _, _, destGUID = CombatLogGetCurrentEventInfo()

    local eventHandler = eventHandlers[event]

    if not eventHandler then
        return
    end

    local unitGUID = destGUID
    local unit = unitIDs[unitGUID]

    if not unit then
        return
    end

    local health = unitHealth[unitGUID]

    if not health then
        return
    end

    local change, state = eventHandler(CombatLogGetCurrentEventInfo())

    if health == 0 and UnitIsFeignDeath(unit) then
        change = 0
    end

    local newHealth = state >= 0 and health + change or nil

    local healthUpdate = newHealth ~= health

    if healthUpdate then
        unitHealth[unitGUID] = newHealth

        fireEventAll("UNIT_HEALTH_FREQUENT", unit)
    end
end

function eventHandlers.PLAYER_LOGIN()
    eventFrame:UnregisterEvent("PLAYER_LOGIN")

    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UNIT_PET")
    eventFrame:RegisterEvent("UNIT_MAXHEALTH")
    eventFrame:RegisterEvent("UNIT_HEALTH")
    eventFrame:RegisterEvent("UNIT_HEALTH_FREQUENT")
    eventFrame:RegisterEvent("UNIT_CONNECTION")

    delayFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

    dummyFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

do
    if not IsLoggedIn() then
        eventFrame:RegisterEvent("PLAYER_LOGIN")
    else
        eventHandlers.PLAYER_LOGIN()

        if oldminor then
            eventHandlers.GROUP_ROSTER_UPDATE()
        end
    end
end

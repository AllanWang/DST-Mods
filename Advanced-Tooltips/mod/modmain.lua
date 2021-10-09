local OPT_ENABLE_DAMAGE = GetModConfigData("OPT_ENABLE_DAMAGE")
local OPT_ENABLE_USES = GetModConfigData("OPT_ENABLE_USES")
local OPT_ENABLE_TEMPERATURE = GetModConfigData("OPT_ENABLE_TEMPERATURE")
local OPT_ENABLE_ARMOR = GetModConfigData("OPT_ENABLE_ARMOR")
local OPT_ENABLE_INSULATION = GetModConfigData("OPT_ENABLE_INSULATION")
local OPT_ENABLE_FOOD_VALUES = GetModConfigData("OPT_ENABLE_FOOD_VALUES")
local OPT_ENABLE_SPOIL_TIME = GetModConfigData("OPT_ENABLE_SPOIL_TIME")

local OPT_REPLACE_USES_PERCENTAGE = GetModConfigData(
                                        "OPT_REPLACE_USES_PERCENTAGE")
local OPT_REPLACE_ARMOR_PERCENTAGE = GetModConfigData(
                                         "OPT_REPLACE_ARMOR_PERCENTAGE")

local OPT_TIME_ALWAYS_REAL = GetModConfigData("OPT_TIME_ALWAYS_REAL")
local OPT_FOOD_COMPACT = GetModConfigData("OPT_FOOD_COMPACT")
local OPT_SHOW_MAX = GetModConfigData("OPT_SHOW_MAX")
local OPT_USE_FAHRENHEIT = GetModConfigData("OPT_USE_FAHRENHEIT")

local DEGREES = "\176"
local DEGREES_C = DEGREES .. "C"
local DEGREES_F = DEGREES .. "F"

local require = GLOBAL.require

local ItemTile = require "widgets/itemtile"
local ContainerWidget = require "widgets/containerwidget"
local prep_foods = require("preparedfoods")

-- Override supers

local ContainerWidget_Refresh_base = ContainerWidget.Refresh or
                                         function() return "" end
local ItemTile_GetDescriptionString_base =
    ItemTile.GetDescriptionString or function() return "" end
local ItemTile_GetTooltipPos_base = ItemTile.GetTooltipPos or
                                        function() return "" end
local ItemTile_SetPercent_base = ItemTile.SetPercent or function() return "" end
local ItemTile_SetPerishPercent_base = ItemTile.SetPerishPercent or
                                           function() return "" end
local PrefabItems = {}
local BadPrefabs = {
    butterfly = true,
    blueprint = true,
    chester_eyebone = true,
    bernie_inactive = true,
    horn = true
}

--- StringBuilder
-- Helper class to concatenate strings
local StringBuilder = Class(function(self, str) self.str = str or "" end)

function StringBuilder:Append(str) self.str = self.str .. str end

function StringBuilder:AppendLine(str) self:Append("\n" .. str) end

function StringBuilder:Get() return self.str end

if not GLOBAL.TheNet:GetIsServer() then
    AddPrefabPostInit("wx78", function(inst)
        inst:AddComponent("eater")
        inst.components.eater.ignoresspoilage = true
        inst.components.eater:SetCanEatGears()
    end)
end

local function formatDecimal(number, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(number * factor + 0.5) / factor
end

local function formatDoubleDigit(number)
    return (number < 10 and "0" or "") .. number
end

--- Retrieve display value for damage
-- For most cases, damage is a number value.
-- However, in cases like the trident, it is a function
local function formatDamage(damage)
    return type(damage) == "function" and damage() or damage
end

local function formatTimeReal(time)
    local hour = math.floor(time / 3600)
    local min = math.floor(time / 60) - (hour * 60)
    local sec = math.floor(time) - (hour * 3600) - (min * 60)
    if hour > 0 then
        return hour .. ":" .. formatDoubleDigit(min) .. ":" ..
                   formatDoubleDigit(sec)
    end
    if min > 0 then return min .. ":" .. formatDoubleDigit(sec) end
    return sec .. "s"
end

local function formatFoodValues(hunger, sanity, health)
    if OPT_FOOD_COMPACT then return hunger .. "/" .. sanity .. "/" .. health end
    local result = StringBuilder()
    if hunger ~= 0 then result:AppendLine("Hunger: " .. hunger) end
    if health ~= 0 then result:AppendLine("Health: " .. health) end
    if sanity ~= 0 then result:AppendLine("Sanity: " .. sanity) end
    -- Trim whitespace
    return result:Get():gsub("^%s*(.-)%s*$", "%1")
end

local function formatTime(time)
    local days = time / TUNING.TOTAL_DAY_TIME
    if days < 1 or OPT_TIME_ALWAYS_REAL then return formatTimeReal(time) end
    return formatDecimal(days, 1) .. "d"
end

local function describeUses(finiteuses, showtotal)
    local use = 1
    for k, v in pairs(finiteuses.consumption) do
        use = v
        break
    end
    local currentuses = finiteuses.current
    -- Patch for percent
    if currentuses == finiteuses.total then 
        currentuses = localGetComponentPercent(finiteuses) * finiteuses.total 
    end 
    local current = formatDecimal(currentuses / use)
    if showtotal and OPT_SHOW_MAX then
        return current .. "/" .. formatDecimal(finiteuses.total / use)
    end
    return current
end

local function describeFuel(fueled, showtotal)
    local currentfuel = fueled.currentfuel 
    -- Patch for percent
    if currentfuel == fueled.maxfuel then 
      currentfuel = localGetComponentPercent(fueled) * fueled.maxfuel
    end
    local current = formatTime(currentfuel / fueled.rate)
    if showtotal and OPT_SHOW_MAX then
        return current .. "/" .. formatTime(fueled.maxfuel / fueled.rate)
    end
    return current
end

local function describeHeatrock(fueled)
    local current = localGetComponentPercent(fueled) * TUNING.HEATROCK_NUMUSES
    if OPT_SHOW_MAX then return formatDecimal(current, 0) .. "/" .. TUNING.HEATROCK_NUMUSES end
    return current
end

local function describeArmor(armor, showtotal)
    local condition = armor.condition
    -- Patch for percent
    if condition == armor.maxcondition then 
      condition = localGetComponentPercent(armor) * armor.maxcondition
    end
    local current = formatDecimal(condition)
    if showtotal and OPT_SHOW_MAX then
        return current .. "/" .. formatDecimal(armor.maxcondition)
    end
    return current
end

local function describeTemperature(temperature, decimals)
    if OPT_USE_FAHRENHEIT then
        return formatDecimal(temperature * 1.0 + 32, decimals) .. DEGREES_F
    end
    return formatDecimal(temperature, decimals) .. DEGREES_C
end

local function describeSpoilTime(perishable, modifier)
    local totalperishtime = perishable.perishtime / modifier
    local remainingperishtime = perishable.perishremainingtime / modifier 
    -- Backwards compatible check; if remaining time is still max and we have a percentage, use percentage
    if remainingperishtime == totalperishtime and perishable._tooltips_percent_value ~= nil then 
        remainingperishtime = totalperishtime * perishable._tooltips_percent_value
    end 
    local current = formatTime(remainingperishtime)
    if OPT_SHOW_MAX then
        return current .. "/" .. formatTime(totalperishtime)
    end
    return current
end

-- Local functions
-- Note that the functions may call each other, so they need to be defined before usage
local localItem, localSetPercent

--- Get local item
-- Takes in ItemTile, and expects ItemTile.item to be valid
localItem = function(itemtile)
    local item = itemtile.item
    if GLOBAL.TheNet:GetIsServer() then return item end
    local prefab = item.prefab
    if prefab ~= nil and not BadPrefabs[prefab] then
        item = PrefabItems[prefab]
        if item == nil then
            GLOBAL.TheWorld.ismastersim = true
            GLOBAL.pcall(function() item = GLOBAL.SpawnPrefab(prefab) end)
            if item and item.replica and item.replica.inventoryitem then
                item.replica.inventoryitem.DeserializeUsage = function() end
            end
            if item then item:Remove() end
            -- Filter out any moving creatures
            if item and item.components and item.components.locomotor ~= nil then
                item = true
            end
            GLOBAL.TheWorld.ismastersim = false
            if item == nil then item = true end
            PrefabItems[prefab] = item
        end
        if not item or item == true then item = itemtile.item end
    end

    if itemtile._tooltips_percent_value == nil then return item end

    local value = itemtile._tooltips_percent_value
    local components = item.components

    -- Populate components that could have resulted in SetPercent call; see scripts/widgets/itemtile.lua
    -- Note that perishables have SetPerishPercent instead
    localSetComponentPercent(components.armor, value)
    localSetComponentPercent(components.fueled, value)
    localSetComponentPercent(components.finiteuses, value)
  
    return item
end

-- For getting a handle to the container
function ContainerWidget:Refresh()
    ContainerWidget_Refresh_base(self)
    local items = self.container.replica.container:GetItems()
    for k, v in pairs(self.inv) do
        if v.tile ~= nil then v.tile.container = self.container end
    end
end

-- Grab the percent as they come in
function ItemTile:SetPerishPercent(percent)
    localSetComponentPercent(self.item.components.perishable, percent)
    ItemTile_SetPerishPercent_base(self, percent)
end

localSetPercent = function(itemtile, percent)
    if itemtile == nil then return end
    itemtile._tooltips_percent_value = percent
    if itemtile.item == nil then return end

    local isserver = GLOBAL.TheNet:GetIsServer()
    local item = localItem(itemtile)
    local prefab = item.prefab
    local components = item.components

    if components.finiteuses ~= nil and OPT_REPLACE_USES_PERCENTAGE then
        itemtile.percent:SetString(describeUses(components.finiteuses, false))
    elseif components.armor ~= nil and components.armor.condition ~= nil and
        OPT_REPLACE_ARMOR_PERCENTAGE then
        itemtile.percent:SetString(describeArmor(components.armor, false))
    elseif components.fueled ~= nil and OPT_REPLACE_USES_PERCENTAGE then
        if item.prefab == "heatrock" then
            itemtile.percent:SetString(describeHeatrock(components.fueled))
        else
            itemtile.percent:SetString(describeFuel(components.fueled, false))
        end
    end
end

localSetComponentPercent = function(component, percent) 
  if component == nil then return end
  component._tooltips_percent_value = percent
end

localGetComponentPercent = function(component) 
  if component == nil then return 1.0 end 
  if component._tooltips_percent_value ~= nil then return component._tooltips_percent_value end 
  return component:GetPercent() 
end

-- Grab the percent as they come in
function ItemTile:SetPercent(percent)
    ItemTile_SetPercent_base(self, percent)
    localSetPercent(self, percent)
end

function ItemTile:GetTooltipPos()
    local str = self.tooltip
    local lines = 0

    if str then
        for i in string.gfind(str, "\n") do lines = lines + 1 end
        lines = lines - 1
    end

    return GLOBAL.Vector3(0, 40 + 15 * lines, 0)
end

function ItemTile:GetDescriptionString()
    local str = ItemTile_GetDescriptionString_base(self)

    -- Our description is only for valid items in the inventory
    if self.item == nil or not self.item:IsValid() or
        self.item.replica.inventoryitem == nil then return str end

    local result = StringBuilder(str)

    local isserver = GLOBAL.TheNet:GetIsServer()
    local player = GLOBAL.ThePlayer
    local item = localItem(self)
    local prefab = item.prefab
    local components = item.components
    local tilecontainer = self.container

    if components.weapon ~= nil and components.weapon.damage ~= nil and
        OPT_ENABLE_DAMAGE then
        local damage = formatDamage(components.weapon.damage)
        -- Hambats have special logic for damage; note that we cannot generalize the implementation
        -- as tuning constants are hardcoded per item.
        if prefab == "hambat" and components.perishable ~= nil and components.perishable._tooltips_percent_value ~= nil then 
          damage = TUNING.HAMBAT_DAMAGE * components.perishable._tooltips_percent_value
          damage = GLOBAL.Remap(damage, 0, TUNING.HAMBAT_DAMAGE, TUNING.HAMBAT_MIN_DAMAGE_MODIFIER * TUNING.HAMBAT_DAMAGE, TUNING.HAMBAT_DAMAGE)
        end 
        result:AppendLine("DMG: " .. formatDecimal(damage, 1))
    end
    if components.finiteuses ~= nil and OPT_ENABLE_USES then
        result:AppendLine("USE: " .. describeUses(components.finiteuses, true))
    end
    if components.temperature ~= nil and components.temperature.current ~= nil and
        isserver and OPT_ENABLE_TEMPERATURE then
        result:AppendLine("TEMP: " ..
                              describeTemperature(components.temperature.current,
                                                1))
    end
    if components.fueled ~= nil and OPT_ENABLE_USES then
        if item.prefab == "heatrock" then
            result:AppendLine("USE: " .. describeHeatrock(components.fueled))
        else
            result:AppendLine("USE: " .. describeFuel(components.fueled, true))
        end
    end
    if components.armor ~= nil and OPT_ENABLE_ARMOR then
        if components.armor.condition ~= nil then
            result:AppendLine("HP: " .. describeArmor(components.armor, true))
        end
        if components.armor.tags ~= nil then
            for k, v in pairs(components.armor.tags) do
                result:AppendLine("VS: " .. v)
            end
        end
        if components.armor.absorb_percent ~= nil then
            result:AppendLine("DR: " .. components.armor.absorb_percent * 100 ..
                                  "%")
        end
    end

    local insulator = components.insulator
    if insulator ~= nil and OPT_ENABLE_INSULATION then
        if insulator.type == GLOBAL.SEASONS.WINTER then
            result:AppendLine("Heating: " .. formatDecimal(insulator.insulation))
        else
            result:AppendLine("Cooling: " .. formatDecimal(insulator.insulation))
        end
    end

    local waterproofer = components.waterproofer
    if waterproofer ~= nil and OPT_ENABLE_INSULATION then
        result:AppendLine("Waterproof: " ..
                              formatDecimal(waterproofer.effectiveness * 100))
    end

    local isfood = nil
    local actions = player.components.playeractionpicker:GetInventoryActions(
                        self.item)
    if #actions > 0 then
        for k, v in pairs(actions) do
            if v.action == GLOBAL.ACTIONS.EAT or v.action == GLOBAL.ACTIONS.HEAL then
                isfood = true
                break
            end
        end
    end

    if components.edible and isfood and OPT_ENABLE_FOOD_VALUES then
        local hunger = formatDecimal(components.edible:GetHunger(player), 1)
        local health = formatDecimal(components.edible:GetHealth(player), 1)
        local sanity = formatDecimal(components.edible:GetSanity(player), 1)

        if player.components.eater and player.components.eater.monsterimmune and
            not player.components.eater:DoFoodEffects(self.item) then
            if hunger < 0 then hunger = 0 end
            if health < 0 then health = 0 end
            if sanity < 0 then sanity = 0 end
        end

        result:AppendLine(formatFoodValues(hunger, sanity, health))
    end
    if components.healer and isfood and OPT_ENABLE_FOOD_VALUES then
        result:AppendLine(formatFoodValues(0, 0, components.healer.health))
    end
    if components.perishable and OPT_ENABLE_SPOIL_TIME then
        local modifier = 1
        local owner = components.inventoryitem and
                          components.inventoryitem.owner or nil
        if owner then
            if owner:HasTag("fridge") then
                modifier = TUNING.PERISH_FRIDGE_MULT
            elseif owner:HasTag("spoiler") then
                modifier = TUNING.PERISH_GROUND_MULT
            end
        elseif isserver then
            modifier = TUNING.PERISH_GROUND_MULT
        elseif tilecontainer ~= nil then
            if tilecontainer:HasTag("fridge") then
                modifier = TUNING.PERISH_FRIDGE_MULT
            elseif tilecontainer:HasTag("spoiler") then
                modifier = TUNING.PERISH_GROUND_MULT
            end
        end

        if GLOBAL.TheWorld.state.temperature < 0 then
            modifier = modifier * TUNING.PERISH_WINTER_MULT
        end

        modifier = modifier * TUNING.PERISH_GLOBAL_MULT

        if modifier ~= 0 then
            result:AppendLine("Spoil: " ..
                                  describeSpoilTime(components.perishable,
                                                  modifier))
        end
    end

    return result:Get()
end

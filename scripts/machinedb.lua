local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

---@class MachineInfo
---@field name string
---@field categories {[string]:boolean}
---@field allowed_effects {[string]:boolean}
---@field module_inventory_size integer
---@field crafting_speed number

---@class ModuleInfo
---@field name string
---@field effects ModuleEffects
---@field limitations {[string]:boolean}

---@class MachineDb
---@field machines {[string]:MachineInfo}
---@field category_to_machines {[string]:MachineInfo[]}
---@field modules {[string]:ModuleInfo}
---@field initialized boolean
machinedb = {

    machines = {},
    category_to_machines = {},
    modules = {}

}

---@param machine LuaEntityPrototype
---@return MachineInfo
function machinedb.get_machine(machine)
    local existing = machinedb.machines[machine.name]
    if existing then
        return existing
    end

    existing = {
        name = machine.name,
        categories = {},
        allowed_effects = machine.allowed_effects,
        module_inventory_size = machine.module_inventory_size,
        crafting_speed = machine.crafting_speed
    }
    machinedb.machines[machine.name] = existing
    return existing
end

local excluded_module_groups = {

    ["ee-tools"] = true
}

function machinedb.initialize()
    if machinedb.initialized then
        return
    end
    machinedb.initialized = true
    for category_name, _ in pairs(game.recipe_category_prototypes) do
        local machines = game.get_filtered_entity_prototypes { { filter = "crafting-category", crafting_category = category_name } }
        local machine_infos = {}
        for _, machine in pairs(machines) do
            local info = machinedb.get_machine(machine)
            info.categories[category_name] = true
            table.insert(machine_infos, info)
        end
        machinedb.category_to_machines[category_name] = machine_infos
        table.sort(machine_infos, function(e1, e2) return e1.crafting_speed < e2.crafting_speed end)
    end

    local modules = game.get_filtered_item_prototypes { { filter = "type", type = "module" } }
    for module_name, module in pairs(modules) do
        if not excluded_module_groups[module.group.name] then
            ---@type ModuleInfo
            local module_info = {
                name = module_name,
                effects = module.module_effects
            }
            if module_info.effects then
                if module.limitations and #module.limitations > 0 then
                    module_info.limitations = {}
                    for _, recipe_name in pairs(module.limitations) do
                        module_info.limitations[recipe_name] = true
                    end
                end
                machinedb.modules[module_name] = module_info
            end
        end
    end
end

---@param force LuaForce
---@param machine_name string
---@return boolean
function machinedb.is_machine_enabled(force, machine_name)
    local entity = game.entity_prototypes[machine_name]
    local item = entity.items_to_place_this[1]
    local machine_recipes = game.get_filtered_recipe_prototypes {
        { filter = "has-product-item",
            elem_filters = { { filter = "name", name = item } } } }
    for _, mr in pairs(machine_recipes) do
        if force.recipes[mr.name].enabled then
            return true
        end
    end
    return false
end

local is_machine_enabled = machinedb.is_machine_enabled

---@param g Graph
---@param recipe_name string
---@param enabled_cache {[string]:boolean}
---@return ProductionConfig?
function machinedb.get_default_config(g, recipe_name, enabled_cache)
    local force = g.player.force --[[@as LuaForce]]
    local recipe = game.recipe_prototypes[recipe_name]
    if not recipe then
        return nil
    end

    machinedb.initialize()
    local machines           = machinedb.category_to_machines[recipe.category]

    local preferred_machines = g.preferred_machines
    local preferred_modules  = g.preferred_modules

    if not preferred_machines then
        preferred_machines = {}
    end
    if not preferred_modules then
        preferred_modules = {}
    end

    ---@type {[string]:integer}
    local machine_set = {}
    local order = 0
    for _, machine_name in pairs(preferred_machines) do
        machine_set[machine_name] = order
        order = order + 1
    end

    local found_index
    local found_order
    for i = 1, #machines do
        local machine = machines[i]
        local machine_name = machine.name
        local enabled = enabled_cache[machine_name]
        if enabled == nil then
            enabled = is_machine_enabled(force, machine_name)
            enabled_cache[machine_name] = enabled
        end
        if enabled or machine_set[machine_name] then
            local new_order = machine_set[machine_name]
            if new_order then
                if not found_order or (found_order and new_order < found_order) then
                    found_order = new_order
                    found_index = i
                end
            elseif not found_order then
                found_index = i
            end
        end
    end
    if not found_index then
        if not g.show_only_researched then
            for i = 1, #machines do
                if machine_set[machines[i].name] then
                    found_index = i
                    break
                end
            end
            if not found_index then
                found_index = 1
            end
        else
            return nil
        end
    end
    local found_machine = machines[found_index]
    local found_machine_module


    local preferred_beacon_name = g.preferred_beacon
    local preferred_beacon
    local found_beacon_module
    if preferred_beacon_name then
        preferred_beacon = game.entity_prototypes[preferred_beacon_name]
    end

    for _, module_name in pairs(preferred_modules) do
        local module = machinedb.modules[module_name]
        if module.limitations and not module.limitations[recipe_name] then
            goto skip
        end

        local effects = module.effects

        local allowed_effects = found_machine.allowed_effects
        if effects.productivity and not allowed_effects.productivity then goto skip end
        if effects.speed and not allowed_effects.speed then goto skip end
        if effects.consumption and not allowed_effects.consumption then goto skip end

        if not found_machine_module then
            found_machine_module = module_name
        end
        if not preferred_beacon then
            break
        end

        allowed_effects = preferred_beacon.allowed_effects
        ---@cast allowed_effects -nil
        if effects.productivity and not allowed_effects.productivity then goto skip end
        if effects.speed and not allowed_effects.speed then goto skip end
        if effects.consumption and not allowed_effects.consumption then goto skip end

        found_beacon_module = module_name
        break

        ::skip::
    end

    if not found_machine then
        return nil
    end

    ---@type ProductionConfig
    local config = {
        machine_name = found_machine.name,
    }
    if found_machine_module then
        config.machine_modules = {}
        for i = 1, found_machine.module_inventory_size do
            table.insert(config.machine_modules, found_machine_module)
        end
    end
    if found_beacon_module then
        config.beacon_name = preferred_beacon_name
        config.beacon_modules = {}
        for i = 1, preferred_beacon.module_inventory_size do
            table.insert(config.beacon_modules, found_beacon_module)
        end
    end
    config.beacon_count = g.preferred_beacon_count or 0
    return config
end

return machinedb

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local machinedb = require("scripts.machinedb")

local production = {}


local free_value = 1e8


---@param g Graph
function production.compute(g)
    machinedb.initialize()

    g.preferred_machines = { "assembling-machine-2" }
    g.preferred_modules = nil
    g.preferred_beacon = nil
    g.preferred_beacon_count = 0
    -- g.iovalues = { ["item/electronic-circuit"] = 10 }

    local failed = false

    ---@type {[string]:ProductionRecipe}
    local precipes = {}

    local enabled_cache = {}
    for recipe_name, grecipe in pairs(g.recipes) do
        if not g.selection[recipe_name] then goto skip end
        if grecipe.is_product then goto skip end

        local config = grecipe.production_config
        if not config then
            config = machinedb.get_default_config(g, recipe_name, enabled_cache)
            if not config then goto skip end
        end

        local recipe = game.recipe_prototypes[recipe_name]

        ---@type ProductionRecipe
        local production = {
            recipe_name = recipe_name,
            grecipe = grecipe,
            recipe = recipe,
            machine = game.entity_prototypes[config.machine_name],
        }

        if config.machine_modules then
            production.modules = {}
            for _, module_name in pairs(config.machine_modules) do
                table.insert(production.modules, game.item_prototypes[module_name])
            end
        end

        precipes[recipe_name] = production

        local speed = 0
        ---@cast speed -nil
        local productivity = 0
        local consumption = 0

        if production.modules then
            for _, module in pairs(production.modules) do
                local effects = module.module_effects
                if effects then
                    if effects.speed then speed = speed + effects.speed.bonus end
                    if effects.productivity then productivity = productivity + effects.productivity.bonus end
                    if effects.consumption then consumption = consumption + effects.consumption.bonus end
                end
            end
        end

        if config.beacon_name and config.beacon_modules then
            local beacon = game.entity_prototypes[config.beacon_name]
            local effectivity = beacon.distribution_effectivity

            local beacon_count = g.preferred_beacon_count
            for _, module_name in pairs(config.beacon_modules) do
                local module = game.item_prototypes[module_name]
                local effects = module.module_effects
                if effects then
                    if effects.speed then speed = speed + beacon_count * effectivity * effects.speed.bonus end
                    if effects.productivity then productivity = productivity + beacon_count * effectivity * effects.productivity.bonus end
                    if effects.consumption then consumption = consumption + beacon_count * effectivity * effects.consumption.bonus end
                end
            end
        end
        production.speed = speed
        production.productivity = productivity
        production.consumption = consumption
        production.craft_per_s = (1 + speed) * (1 + productivity) * production.machine.crafting_speed / recipe.energy

        ::skip::
    end

    ---@type {[string]:{[string]:number}}       @ prod name => recipe name => number
    local equations = {}

    ---@type table<string, number>
    local iovalues = {}

    ---@type table<string, boolean>
    local is_free = {}
    ---@type table<string, boolean>
    local is_input = {}
    ---@type table<string, boolean>
    local is_output = {}

    if g.iovalues then
        for product_name, iovalue in pairs(g.iovalues) do
            if iovalue == true then
                is_free[product_name] = true
            else
                iovalues[product_name] = iovalue --[[@as number]]
            end
        end
    end

    for _, precipe in pairs(precipes) do
        local craft_per_s = precipe.craft_per_s

        local recipe_name = precipe.recipe_name
        for _, ingredient in pairs(precipe.recipe.ingredients) do
            local iname = ingredient.type .. "/" .. ingredient.name
            local eq = equations[iname]
            if not eq then
                eq = {}
                equations[iname] = eq
            end
            is_input[iname] = true
            local coef = eq[recipe_name]
            if not coef then
                coef = 0
            end
            coef = coef - ingredient.amount * craft_per_s
            eq[recipe_name] = coef
        end

        for _, product in pairs(precipe.recipe.products) do
            local pname = product.type .. "/" .. product.name
            local eq = equations[pname]
            if not eq then
                eq = {}
                equations[pname] = eq
            end
            is_output[pname] = true
            local coef = eq[recipe_name]
            if not coef then
                coef = 0
            end
            local amount
            if product.amount_min then
                amount = (product.amount_max + product.amount_min) / 2 * product.probability
            else
                amount = product.amount
            end
            coef = coef + amount * craft_per_s
            eq[recipe_name] = coef
        end
    end

    local to_solve = {}
    local eq_values = {}
    for name, value in pairs(iovalues) do
        eq_values[name] = value
    end
    for product_name, eq in pairs(equations) do
        if is_input[product_name] and is_output[product_name] then
            if not is_free[product_name] then
                if not iovalues[product_name] then
                    eq_values[product_name] = 0
                end
            end
        end
        if eq_values[product_name] then
            to_solve[product_name] = eq
        end
    end

    local equation_list = {}
    local constant_list = {}
    local product_name_list = {}
    for product_name, eq in pairs(to_solve) do
        table.insert(equation_list, eq)
        table.insert(constant_list, eq_values[product_name])
        table.insert(product_name_list, product_name)
    end

    local function trim(v) return math.abs(v) > 0.0001 and v or nil end

    local name_map = {}
    local var_list = {}
    for i = 1, #equation_list do
        ---@type table<string, number>
        local pivot_eq = equation_list[i]

        -- find pivot
        local pivot_var, pivot_value
        for var_name, value in pairs(pivot_eq) do
            if value ~= 0 and not name_map[var_name] then
                if not pivot_value then
                    pivot_var = var_name
                    pivot_value = value
                elseif math.abs(value) > math.abs(pivot_value) then
                    pivot_var = var_name
                    pivot_value = value
                end
            end
        end
        if not pivot_value then goto next_eq end

        name_map[pivot_var] = true
        for n, v in pairs(pivot_eq) do
            pivot_eq[n] = v / pivot_value
        end
        constant_list[i] = constant_list[i] / pivot_value
        var_list[i] = pivot_var

        for j = i + 1, #equation_list do
            local eq_line = equation_list[j]
            local line_pivot = eq_line[pivot_var]
            if line_pivot then
                for n, v in pairs(pivot_eq) do
                    eq_line[n] = trim((eq_line[n] or 0) - line_pivot * v)
                end
                constant_list[j] = constant_list[j] - line_pivot * constant_list[i]
            end
        end

        ::next_eq::
    end

    -- Initialize
    local machine_counts = {}
    local count = #equation_list
    local last_eq = equation_list[count]
    local last_const = constant_list[count]
    local is_neg = last_const < 0
    local last_count = 0

    --- Compute machine counts
    local end_const = {}
    for recipe_name, value in pairs(last_eq) do
        if is_neg == (value < 0) then
            end_const[recipe_name] = value
            last_count = last_count + 1
        else
            end_const[recipe_name] = 0
        end
    end

    if last_count > 0 then
        for recipe_name, value in pairs(end_const) do
            if value == 0 then
                machine_counts[recipe_name] = 0
            else
                machine_counts[recipe_name] = last_const / value / last_count
            end
        end
    else
        failed = true
    end

    for i = count - 1, 1, -1 do
        local eq = equation_list[i]
        local recipe_name = var_list[i]

        if recipe_name then
            local machine_count = constant_list[i]
            for name, value in pairs(eq) do
                if name ~= recipe_name then
                    local mc = machine_counts[name]
                    if mc then
                        machine_count = machine_count - mc * value
                    end
                end
            end
            if math.abs(machine_count) < 0.01 then
                machine_count = 0
            end
            machine_counts[recipe_name] = machine_count
            if machine_count < 0 then
                failed = true
            end
        end
    end

    --- compute products
    local product_counts = {}
    for _, precipe in pairs(precipes) do
        local recipe_name = precipe.recipe_name
        local machine_count = machine_counts[recipe_name]
        if machine_count then
            local craft_per_s = precipe.craft_per_s
            for _, ingredient in pairs(precipe.recipe.ingredients) do
                local iname = ingredient.type .. "/" .. ingredient.name
                local coef = product_counts[iname]
                if not coef then
                    coef = 0
                end
                product_counts[iname] = coef - ingredient.amount * craft_per_s * machine_count
            end

            for _, product in pairs(precipe.recipe.products) do
                local pname = product.type .. "/" .. product.name
                local coef = product_counts[pname]
                if not coef then
                    coef = 0
                end
                local amount
                if product.amount_min then
                    amount = (product.amount_max + product.amount_min) / 2 * product.probability
                else
                    amount = product.amount
                end
                product_counts[pname] = coef + amount * craft_per_s * machine_count
            end
        end
    end
    g.machine_counts = machine_counts
    g.product_counts = product_counts
    g.production_failed = failed
    return precipes
end

---@param g Graph
---@param structure_change boolean?
function production.push(g, structure_change)
    if not global.production_queue then
        global.production_queue = {}
    end
    local player_index = g.player.index
    local data = global.production_queue[player_index]
    if data then
        if structure_change then
            data.structure_change = true
        end
    else
        global.production_queue[player_index] = { g = g, structure_change = structure_change }
    end
end

tools.on_nth_tick(30, function()
    local production_queue = global.production_queue
    if not production_queue then
        return
    end
    global.production_queue = nil
    for _, data in pairs(production_queue) do
        production.compute(data.g)
        tools.fire_user_event(commons.production_compute_event, { g = data.g, structure_change = data.structure_change })
    end
end)

tools.register_user_event(commons.selection_change_event, function(data)
    production.push(data.g, true)
end)

tools.register_user_event(commons.production_data_change_event, function(data)
    production.push(data.g)
end)

return production

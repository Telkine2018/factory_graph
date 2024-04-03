local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local machinedb = require("scripts.machinedb")

local production = {}

local abs = math.abs
local math_precision = commons.math_precision

---@param g Graph
---@param grecipe GRecipe
---@param config ProductionConfig
---@return ProductionMachine?
function production.compute_machine(g, grecipe, config)
    local machine = nil

    do
        ---@cast grecipe GRecipe
        if grecipe.is_product then goto skip end

        local recipe_name = grecipe.name
        local recipe = game.recipe_prototypes[recipe_name]

        ---@type ProductionMachine
        machine = {
            recipe_name = recipe_name,
            grecipe = grecipe,
            recipe = recipe,
            machine = game.entity_prototypes[config.machine_name],
            config = config
        }

        if config.machine_modules then
            machine.modules = {}
            for _, module_name in pairs(config.machine_modules) do
                table.insert(machine.modules, game.item_prototypes[module_name])
            end
        end

        local speed = 0
        ---@cast speed -nil
        local productivity = 0
        local consumption = 0
        local pollution = 0

        if machine.modules then
            for _, module in pairs(machine.modules) do
                local effects = module.module_effects
                if effects then
                    if effects.speed then speed = speed + effects.speed.bonus end
                    if effects.productivity then productivity = productivity + effects.productivity.bonus end
                    if effects.consumption then consumption = consumption + effects.consumption.bonus end
                    if effects.pollution then pollution = pollution + effects.pollution.bonus end
                end
            end
        end

        if config.beacon_name and config.beacon_modules then
            local beacon = game.entity_prototypes[config.beacon_name]
            local effectivity = beacon.distribution_effectivity

            local beacon_count = config.beacon_count or 0
            for _, module_name in pairs(config.beacon_modules) do
                local module = game.item_prototypes[module_name]
                local effects = module.module_effects

                if module.limitations and #module.limitations > 0 then
                    if not g.module_limitations then
                        g.module_limitations = {}
                    end
                    local limitation_map = g.module_limitations[module_name]
                    if not limitation_map then
                        limitation_map = {}
                        g.module_limitations[module_name] = limitation_map
                        for _, name in pairs(module.limitations) do
                            limitation_map[name] = true
                        end
                    end
                    if not limitation_map[recipe_name] then
                        goto skip
                    end
                end
                if effects then
                    if effects.speed then speed = speed + beacon_count * effectivity * effects.speed.bonus end
                    if effects.productivity then productivity = productivity + beacon_count * effectivity * effects.productivity.bonus end
                    if effects.consumption then consumption = consumption + beacon_count * effectivity * effects.consumption.bonus end
                    if effects.pollution then pollution = pollution + beacon_count * effectivity * effects.pollution.bonus end
                end
                ::skip::
            end
        end
        machine.name = recipe_name
        machine.speed = speed
        machine.productivity = productivity
        machine.consumption = consumption
        machine.pollution = pollution
        machine.craft_per_s = (1 + speed) * (1 + productivity) * machine.machine.crafting_speed / recipe.energy
    end
    ::skip::
    return machine
end

local compute_machine = production.compute_machine

---@param g Graph
function production.compute(g)
    machinedb.initialize()

    local failed = nil

    ---@type {[string]:ProductionMachine}
    local machines = {}

    local enabled_cache = {}

    ---@type {[string]:GRecipe}
    local connected_recipes = gutils.get_connected_recipes(g, g.iovalues)

    for recipe_name, grecipe in pairs(connected_recipes) do
        ---@cast grecipe GRecipe

        local config = grecipe.production_config
        if not config then
            config = machinedb.get_default_config(g, recipe_name, enabled_cache)
        end

        if config then
            local machine = compute_machine(g, grecipe, config)
            grecipe.machine = machine
            if machine then
                machines[recipe_name] = machine
            end
        end
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

    local all_recipes = {}

    for _, machine in pairs(machines) do
        local craft_per_s = machine.craft_per_s

        local recipe_name = machine.name
        for _, ingredient in pairs(machine.recipe.ingredients) do
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
            coef = coef - ingredient.amount * craft_per_s / (1 + machine.productivity)
            eq[recipe_name] = coef
            all_recipes[recipe_name] = true
        end

        for _, product in pairs(machine.recipe.products) do
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
            all_recipes[recipe_name] = true
        end
    end
    local free_recipes

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

    local function trim(v) return math.abs(v) > math_precision and v or nil end

    --[[
    local saved_equations = tools.table_deep_copy(equation_list)
    local saved_const = tools.table_deep_copy(constant_list)
    ]]
    local machine_counts
    local name_map = {}
    local var_list = {}

    free_recipes = tools.table_dup(all_recipes)

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
        free_recipes[pivot_var] = nil

        for j = i + 1, #equation_list do
            local eq_line = equation_list[j]
            local pivot_coef = eq_line[pivot_var]
            if pivot_coef then
                for n, v in pairs(pivot_eq) do
                    eq_line[n] = trim((eq_line[n] or 0) - pivot_coef * v)
                end
                constant_list[j] = constant_list[j] - pivot_coef * constant_list[i]
            end

            -- check linear depencies
            if not next(eq_line) and math.abs(constant_list[j]) > math_precision then
                failed = commons.production_failures.linear_dependecy
            end
        end

        ::next_eq::
    end

    -- Reverse
    for i = #equation_list, 1, -1 do
        ---@type table<string, number>
        local pivot_eq = equation_list[i]

        -- find pivot
        local pivot_var = var_list[i]
        for j = i - 1, 1, -1 do
            local eq_line = equation_list[j]
            local pivot_coef = eq_line[pivot_var]
            if pivot_coef then
                for n, v in pairs(pivot_eq) do
                    eq_line[n] = trim((eq_line[n] or 0) - pivot_coef * v)
                end
                constant_list[j] = constant_list[j] - pivot_coef * constant_list[i]
            end
        end
        ::next_eq::
    end


    -- Compute end values
    machine_counts = {}
    local count = #equation_list
    local main_var

    local function solve_linear(current_error)
        for i = 1, count do
            local cst = constant_list[i]
            local var_name = var_list[i]
            if not var_name then
                if abs(cst) > math_precision then
                    failed = current_error
                end
            else
                if abs(cst) < math_precision then
                    cst = 0
                    machine_counts[var_name] = cst
                elseif cst < 0 then
                    failed = current_error
                else
                    machine_counts[var_name] = cst
                end
            end
        end
    end

    if table_size(free_recipes) > 1 then
        if count > 0 and abs(constant_list[count]) < math_precision then
            for name, _ in pairs(free_recipes) do
                machine_counts[name] = 0
            end
            solve_linear(commons.production_failures.too_many_free_variables)
        else
            failed = commons.production_failures.too_many_free_variables
        end
        goto end_compute
    else
        main_var = next(free_recipes)
        if not main_var then
            solve_linear(commons.production_failures.too_many_constraints)
            goto end_compute
        else
            local minv, maxv
            for i = 1, count do
                local eq = equation_list[i]
                local coef = eq[main_var]
                local cst = constant_list[i]

                if coef then
                    if abs(coef) < math_precision then
                        if abs(cst) > math_precision then
                            failed = commons.production_failures.linear_dependecy
                        end
                    else
                        local limit = cst / coef
                        if coef >= 0 then
                            if not maxv or limit < maxv then
                                maxv = limit
                            end
                        else
                            if not minv or limit > minv then
                                minv = limit
                            end
                        end
                    end
                end
            end

            --- compute end value
            local main_value
            if minv then
                if maxv then
                    if minv >= maxv then
                        main_value = 0
                        failed = commons.production_failures.too_many_constraints
                        goto end_compute
                    else
                        main_value = (minv + maxv) / 2
                    end
                else
                    main_value = minv
                end
            elseif maxv then
                main_value = maxv
            end
            if not main_value then
                failed = commons.production_failures.linear_dependecy
                goto end_compute
            else
                machine_counts[main_var] = main_value
            end
        end

        for i = count, 1, -1 do
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
                if math.abs(machine_count) < math_precision then
                    machine_count = 0
                end
                machine_counts[recipe_name] = machine_count
                if machine_count < 0 then
                    if not fail_index then
                        fail_index = i
                    end
                    failed = commons.production_failures.invalid_soluce
                    goto end_compute
                end
            end
        end
    end
    ::end_compute::

    --- compute products    
    local product_outputs = {}
    local product_effective = {}
    for _, machine in pairs(machines) do
        local recipe_name = machine.name
        local machine_count = machine_counts[recipe_name]
        if machine_count then
            machine.count = machine_count
            local craft_per_s = machine.craft_per_s
            for _, ingredient in pairs(machine.recipe.ingredients) do
                local iname = ingredient.type .. "/" .. ingredient.name
                local coef = product_outputs[iname]
                if not coef then
                    coef = 0
                end
                local total = ingredient.amount * craft_per_s * machine_count / (machine.productivity + 1)
                if abs(total) >= math_precision then
                    product_outputs[iname] = coef - total
                end
            end

            for _, product in pairs(machine.recipe.products) do
                local pname = product.type .. "/" .. product.name
                local coef = product_outputs[pname]
                if not coef then
                    coef = 0
                end
                local amount
                if product.amount_min then
                    amount = (product.amount_max + product.amount_min) / 2 * product.probability
                else
                    amount = product.amount
                end
                ---@cast amount -nil
                if abs(amount) <= math_precision then
                    amount = 0
                else
                    local total = amount * craft_per_s * machine_count
                    if abs(total) >= math_precision then
                        product_outputs[pname] = coef + total
                        product_effective[pname] = (product_effective[pname] or 0) + total
                    end
                end
            end
        end
    end
    g.product_outputs = product_outputs
    g.product_effective = product_effective
    g.production_failed = failed
    return machines
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

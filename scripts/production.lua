local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local machinedb = require("scripts.machinedb")
local graph = require("scripts.graph")

local production = {}

local abs = math.abs
local math_precision = commons.math_precision

---@param machine ProductionMachine
---@param product Product
---@return number
local function get_product_amount(machine, product)
    local probability = (product.probability or 1)
    local amount = product.amount or ((product.amount_max + product.amount_min) / 2)

    local catalyst_amount = product.catalyst_amount or 0
    local total
    if catalyst_amount > 0 then
        total = (amount * machine.limited_craft_s +
            math.max(0, amount - catalyst_amount) * machine.productivity * machine.theorical_craft_s
        ) * probability
    else
        total = (amount * machine.limited_craft_s + amount *
            machine.productivity * machine.theorical_craft_s) * probability
    end
    amount = total
    
    return amount
end

---@param machine ProductionMachine
---@param ingredient Ingredient
---@return number
local function get_ingredient_amout(machine, ingredient)
    local amount = ingredient.amount * machine.limited_craft_s
    return amount
end

production.get_product_amount = get_product_amount
production.get_ingredient_amout = get_ingredient_amout

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
        if speed < -0.8 then
            speed = -0.8
        end
        machine.name = recipe_name
        machine.speed = speed
        machine.productivity = productivity
        machine.consumption = consumption
        machine.pollution = pollution
        machine.theorical_craft_s = (1 + speed) * machine.machine.crafting_speed / recipe.energy
        machine.limited_craft_s = math.min(machine.theorical_craft_s, 60)
        machine.produced_craft_s = machine.limited_craft_s + productivity * machine.theorical_craft_s
    end
    ::skip::
    return machine
end

local compute_machine = production.compute_machine

---@param g Graph
---@param machines {[string]:ProductionMachine}
function production.compute_products(g, machines)
    ---@type table<string, number>
    local product_inputs = {}
    ---@type table<string, number>
    local product_outputs = {}

    g.product_inputs = product_inputs
    g.product_outputs = product_outputs

    --- compute products
    for _, machine in pairs(machines) do
        local machine_count = machine.count
        if machine_count then
            if machine_count > 0 then
                machine.count = machine_count
                for _, ingredient in pairs(machine.recipe.ingredients) do
                    local iname = ingredient.type .. "/" .. ingredient.name
                    local coef = product_inputs[iname]
                    if not coef then
                        coef = 0
                    end

                    local amount = get_ingredient_amout(machine, ingredient)
                    if abs(amount) >= math_precision then
                        local total = amount * machine_count
                        product_inputs[iname] = coef + total
                    end
                end
                for _, product in pairs(machine.recipe.products) do
                    local pname = product.type .. "/" .. product.name
                    local coef = product_outputs[pname]
                    if not coef then
                        coef = 0
                    end

                    local amount = get_product_amount(machine, product)
                    if abs(amount) <= math_precision then
                        amount = 0
                    else
                        local total = amount * machine_count
                        product_outputs[pname] = coef + total
                    end
                end
            end
        end
    end
end

---@param g Graph
function production.compute_matrix(g)
    machinedb.initialize()

    local failed = nil

    ---@type {[string]:ProductionMachine}
    local machines = {}

    local enabled_cache = {}

    for _, grecipe in pairs(g.recipes) do
        grecipe.machine = nil
    end

    ---@type {[string]:GRecipe}
    local connected_recipes
    if g.unrestricted_production then
        connected_recipes = g.selection --[[@as {[string]:GRecipe}]]
    else
        connected_recipes = gutils.get_connected_recipes(g, g.iovalues)
    end

    graph.sort_recipes(connected_recipes)


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
            coef = coef - ingredient.amount * machine.limited_craft_s
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

            local amount = get_product_amount(machine, product)
            coef = coef + amount
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

    ---@type {[string]:boolean}
    local bound_products = {}
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
            bound_products[product_name] = true
        end
    end
    g.bound_products = bound_products

    local equation_list = {}
    local constant_list = {}
    local product_name_list = {}
    for product_name, eq in pairs(to_solve) do
        table.insert(equation_list, eq)
        table.insert(constant_list, eq_values[product_name])
        table.insert(product_name_list, product_name)
    end

    local function trim(v) return abs(v) > math_precision and v or nil end

    local machine_counts
    local name_map = {}
    local var_list = {}
    local failed_recipes = {}

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
                elseif abs(value) > abs(pivot_value) then
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
            if not next(eq_line) and abs(constant_list[j]) > math_precision then
                failed_recipes[pivot_var] = true
                failed = commons.production_failures.too_many_constraints
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
    ---@type table<string, number>
    machine_counts = {}
    local count = #equation_list
    local main_var

    ---@param recipe_name any
    ---@param machine_count any
    local function compensate(recipe_name, machine_count)
        --- compensate < 0
        machine_counts[recipe_name] = machine_count
    end

    if table_size(free_recipes) > 1 then
        local free_values = {}
        for name, _ in pairs(free_recipes) do
            free_values[name] = 0
        end

        local change = true
        local iter = 1
        while change and iter < 4 do
            change = false
            iter = iter + 1
            for i = 1, #equation_list do
                local eq = equation_list[i]
                local c = constant_list[i]

                local max_var_name, min_value
                for eqname, eqvalue in pairs(eq) do
                    local free_value = free_values[eqname]
                    if free_value then
                        c = c - free_value * eqvalue
                        if not min_value or min_value > free_value then
                            min_value = eqvalue
                            max_var_name = eqname
                        end
                    end
                end
                if c < 0 and min_value and min_value > 0 then
                    local delta = -c / min_value
                    free_values[max_var_name] = free_values[max_var_name] + delta
                    change = true
                end
            end
        end

        for name, value in pairs(free_values) do
            machine_counts[name] = value
        end
    else
        main_var = next(free_recipes)
        if main_var then
            local minv, maxv
            for i = 1, count do
                local eq = equation_list[i]
                local coef = eq[main_var]
                local cst = constant_list[i]

                if coef then
                    if abs(coef) < math_precision then
                        if abs(cst) > math_precision then
                            failed = commons.production_failures.linear_dependecy
                            failed_recipes[main_var] = true
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
            local main_value = 0
            if minv then
                if maxv then
                    main_value = math.min(maxv, minv)
                    if minv > maxv then
                        failed = commons.production_failures.too_many_constraints
                        failed_recipes[main_var] = true
                    end
                else
                    main_value = minv
                end
            elseif maxv then
                main_value = maxv
            end
            if not main_value then
                failed = commons.production_failures.too_many_constraints
                failed_recipes[main_var] = true
            else
                machine_counts[main_var] = main_value
            end
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
            if abs(machine_count) < math_precision then
                machine_count = 0
            end
            machine_counts[recipe_name] = machine_count
            if machine_count < 0 then
                failed = commons.production_failures.too_many_constraints
                failed_recipes[recipe_name] = true
                compensate(recipe_name, machine_count)
            end
        end
    end

    for name, count in pairs(machine_counts) do
        local machine = machines[name]
        if machine then
            machine.count = count
        end
    end

    --- compute products
    production.compute_products(g, machines)

    g.production_failed = failed
    g.production_recipes_failed = failed_recipes
    return machines
end

---@param g Graph
---@param machines {[string]:ProductionMachine}
function production.compute_linear(g, machines)
    ---@type ProductionMachine[]
    local machine_table = {}
    for _, machine in pairs(machines) do
        table.insert(machine_table, machine)
    end
    table.sort(machine_table,
        ---@param m1 ProductionMachine
        ---@param m2 ProductionMachine
        function(m1, m2)
            return m1.grecipe.sort_level < m2.grecipe.sort_level
        end)

    local requested = {}
    local free = {}
    for name, value in pairs(g.iovalues) do
        if value == true then
            free[name] = true
        else
            requested[name] = value
        end
    end

    for i = #machine_table, 1, -1 do
        local machine = machine_table[i]
        local grecipe = machine.grecipe

        local max_count
        local max_index
        for iproduct, gproduct in pairs(grecipe.products) do
            local vreq = requested[gproduct.name]
            if vreq and vreq > 0 then
                local new_count = vreq / production.get_product_amount(machine, machine.recipe.products[iproduct])
                if not max_count or new_count > max_count then
                    max_count = new_count
                    max_index = iproduct
                end
            end
        end

        if not max_index then
            machine.count = 0
        else
            machine.count = max_count
            for iproduct, gproduct in pairs(grecipe.products) do
                local amount = max_count * production.get_product_amount(machine, machine.recipe.products[iproduct])
                requested[gproduct.name] = (requested[gproduct.name] or 0) - amount
            end
            for index, ingredient in pairs(grecipe.ingredients) do
                local amount = max_count * production.get_ingredient_amout(machine, machine.recipe.ingredients[index])
                requested[ingredient.name] = (requested[ingredient.name] or 0) + amount
            end
        end
    end
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

---@param g Graph
function production.clear(g)
    g.iovalues = {}
    for _, grecipe in pairs(g.recipes) do
        grecipe.machine = nil
    end
    g.product_inputs = nil
    g.product_outputs = nil
    g.production_failed = nil
    gutils.fire_production_data_change(g)
end

tools.on_nth_tick(30, function()
    local production_queue = global.production_queue
    if not production_queue then
        return
    end
    global.production_queue = nil
    for _, data in pairs(production_queue) do
        production.compute_matrix(data.g)
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

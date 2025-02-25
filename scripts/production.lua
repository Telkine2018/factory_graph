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
local function get_ingredient_amount(machine, ingredient)
    local amount = ingredient.amount * machine.limited_craft_s
    return amount
end

---@param machine ProductionMachine
---@return number
local function get_energy(machine)
    if not machine or not machine.machine then return 0 end
    local percent = machine.consumption
    if percent < -0.8 then
        percent = -0.8
    end
    local energy = machine.machine.get_max_energy_usage() * machine.count * (1 + percent) * 60
    return energy
end

production.get_product_amount = get_product_amount
production.get_ingredient_amount = get_ingredient_amount
production.get_energy = get_energy

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
        local recipe = prototypes.recipe[recipe_name]

        local smachine = tools.id_to_signal(config.machine_name)
        ---@cast smachine -nil

        ---@type ProductionMachine
        machine = {
            recipe_name = smachine.name,
            machine_quality = smachine.quality or "normal",
            grecipe = grecipe,
            recipe = recipe,
            machine = prototypes.entity[smachine.name],
            config = config
        }

        machine.modules = {}
        machine.module_qualities = {}
        if config.machine_modules then
            for _, module_id in pairs(config.machine_modules) do
                local smodule = tools.id_to_signal(module_id)
                ---@cast smodule -nil
                table.insert(machine.modules,prototypes.item[smodule.name])
                table.insert(machine.module_qualities, smodule.quality)
            end
        end

        if not g.recipes_productivities then
            g.recipes_productivities = machinedb.compute_recipes_productivities(g)
        end
        local research_productivity = g.recipes_productivities[recipe_name] or 0

        local speed = 0
        ---@cast speed -nil
        local productivity = research_productivity
        local consumption = 0
        local pollution = 0
        local quality = 0

        if machine.machine.effect_receiver then
            local base_effect = machine.machine.effect_receiver.base_effect

            if base_effect then
                productivity = productivity + (base_effect.productivity or 0)
                speed = speed + (base_effect.speed or 0)
                consumption = consumption + (base_effect.consumption or 0)
                quality = quality + (base_effect.quality or 0)
                pollution = pollution + (base_effect.pollution or 0)
            end
        end

        ---@param effects ModuleEffects
        ---@param qmodifier number
        ---@param effectivity integer
        local function apply_effect(effects, qmodifier, effectivity)
            if effects then
                if effects.speed then 
                    speed = speed + effectivity * (effects.speed > 0 and qmodifier * effects.speed or effects.speed) 
                end
                if effects.productivity then 
                    productivity = productivity + effectivity * qmodifier * effects.productivity 
                end
                if effects.consumption then 
                    consumption = consumption + effectivity * (effects.consumption < 0 and qmodifier * effects.consumption or effects.consumption) 
                end
                if effects.pollution then 
                    pollution = pollution + effectivity * (effects.pollution < 0 and qmodifier * effects.pollution or effects.pollution)
                end
                if effects.quality then 
                    quality = quality + effectivity * (effects.quality > 0 and qmodifier * effects.quality or effects.quality) 
                end
            end
        end

        if machine.modules then
            for index = 1, #machine.modules  do
                local module = machine.modules[index]
                local module_quality = machine.module_qualities[index]
                local effects = module.module_effects
                local qproto = prototypes.quality[module_quality or "normal"]
                local qmodifier = 1 + qproto.level * 0.3

                apply_effect(effects, qmodifier, 1)
            end
        end

        if config.beacon_name and config.beacon_modules and config.beacon_count > 0 then
            local sbeacon = tools.id_to_signal(config.beacon_name)
            ---@cast sbeacon -nil
            local beacon = prototypes.entity[sbeacon.name]
            local effectivity = beacon.distribution_effectivity
            local profile = beacon.profile
            local beacon_count = config.beacon_count or 0

            local qproto = prototypes.quality[sbeacon.quality or "normal"]
            effectivity = effectivity + beacon.distribution_effectivity_bonus_per_quality_level * qproto.level

            if profile then
                local index = #profile
                if index > config.beacon_count then
                    index = config.beacon_count
                end
                effectivity = profile[index] * effectivity
            end
            
            for _, module_id in pairs(config.beacon_modules) do
                local smodule = tools.id_to_signal(module_id)
                ---@cast smodule -nil
                local module = prototypes.item[smodule.name]
                local effects = module.module_effects

                local qproto = prototypes.quality[smodule.quality or "normal"]
                local qmodifier = 1 + qproto.level * 0.3

                apply_effect(effects, qmodifier, effectivity * beacon_count)
                ::skip::
            end
        end
        if speed < -0.8 then
            speed = -0.8
        end
        if productivity > 3.0 then
            productivity = 3.0
        end
        machine.name = recipe_name
        machine.speed = speed
        machine.productivity = productivity
        machine.consumption = consumption
        machine.pollution = pollution
        machine.quality = quality / 10

        if machine.machine then
            machine.theorical_craft_s = (1 + speed) * machine.machine.get_crafting_speed(smachine.quality) / recipe.energy
            machine.limited_craft_s = machine.theorical_craft_s
            machine.produced_craft_s = machine.limited_craft_s + productivity * machine.theorical_craft_s
        else
            machine.theorical_craft_s = 0
            machine.limited_craft_s = 0
            machine.produced_craft_s = 0
        end
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
    g.total_energy = 0

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

                    local amount = get_ingredient_amount(machine, ingredient)
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

                if machine.grecipe.visible then
                    g.total_energy = g.total_energy + get_energy(machine)
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

    local has_neg_value
    if g.iovalues then
        for _, v in pairs(g.iovalues) do
            if type(v) == "number" and v < 0 then
                has_neg_value = true
            end
        end
    else
        return
    end

    ---@type {[string]:GRecipe}
    local connected_recipes
    g.use_connected_recipes = false
    if g.always_use_full_selection or has_neg_value then
        connected_recipes = g.selection --[[@as {[string]:GRecipe}]]
    else
        connected_recipes = gutils.get_connected_recipes(g, g.iovalues)
        g.use_connected_recipes = true
    end
    graph.sort_recipes(connected_recipes)

    for _, grecipe in pairs(g.selection) do
        grecipe.machine = nil
    end

    for recipe_name, grecipe in pairs(connected_recipes) do
        ---@cast grecipe GRecipe

        if not grecipe.is_product then
            local config = grecipe.production_config
            if not config then
                config = machinedb.get_default_config(g, recipe_name, enabled_cache)
            end
            if config then
                local machine = compute_machine(g, grecipe, config)
                grecipe.machine = machine
                if machine then
                    if not machine.machine then
                        g.production_failed = commons.production_failures.cannot_find_machine
                        g.production_recipes_failed = {
                            [recipe_name] = true
                        }
                        return
                    end
                    machines[recipe_name] = machine
                end
            else
                failed = commons.production_failures.use_handcraft_recipe
                g.production_failed = failed
                g.production_recipes_failed = {[recipe_name]=true}
                return
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

    ---@type {[string]:string[]}
    local product_to_recipes = {}

    for _, machine in pairs(machines) do
        local recipe_name = machine.recipe.name
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

            local products = product_to_recipes[pname]
            if not products then
                products = { recipe_name }
                product_to_recipes[pname] = products
            else
                table.insert(products, recipe_name)
            end
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

    ---@class SortedEquation
    ---@field eq {[string]:number}
    ---@field constant number
    ---@field product_name string
    ---@field is_output boolean

    local deferred = {}

    ---@type SortedEquation[]
    local sorted_list = {}
    for product_name, eq in pairs(to_solve) do
        local s = {
            eq = eq,
            constant = eq_values[product_name],
            product_name = product_name,
            is_output = (not not iovalues[product_name]) or (is_output[product_name] and not is_input[product_name])
        }
        table.insert(sorted_list, s)
    end

    for product_name, recipes in pairs(product_to_recipes) do
        if is_output[product_name] and not is_input[product_name] then
            for _, recipe_name in pairs(recipes) do
                deferred[recipe_name] = true
            end
        end
    end

    table.sort(sorted_list,
        ---@param s1 SortedEquation
        ---@param s2 SortedEquation
        ---@return boolean
        function(s1, s2)
            local result
            if s1.is_output then
                if s2.is_output then
                    result = s1.product_name < s2.product_name
                else
                    result = false
                end
            elseif s2.is_output then
                result = true
            else
                result = s1.product_name < s2.product_name
            end
            return not result
        end
    )
    local equation_list = {}
    local constant_list = {}
    local product_name_list = {}
    for _, sorted in pairs(sorted_list) do
        table.insert(equation_list, sorted.eq)
        table.insert(constant_list, sorted.constant)
        table.insert(product_name_list, sorted.product_name)
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
        local pivot_var, pivot_value, pivot_deferred
        for var_name, value in pairs(pivot_eq) do
            if value ~= 0 and not name_map[var_name] then
                local var_deferred = deferred[var_name]
                if not pivot_value or (not var_deferred and pivot_deferred)
                then
                    pivot_var = var_name
                    pivot_value = value
                    pivot_deferred = deferred[var_name]
                elseif var_deferred and not pivot_deferred then
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
            for i = #equation_list, 1, -1 do
                local eq = equation_list[i]
                local c = constant_list[i]

                local min_free_value, min_eqvalue, min_var_name
                for eqname, eqvalue in pairs(eq) do
                    local free_value = free_values[eqname]
                    if free_value then
                        c = c - free_value * eqvalue
                        if not min_free_value or min_free_value < free_value then
                            min_free_value = free_value
                            min_var_name = eqname
                            min_eqvalue = eqvalue
                        end
                    end
                end
                if min_free_value then
                    local delta = c / min_eqvalue
                    if delta > 0.001 then
                        local newvalue = min_free_value + delta
                        free_values[min_var_name] = newvalue
                        change = true
                    end
                end
            end
        end

        for name, _ in pairs(free_recipes) do
            machine_counts[name] = free_values[name]
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
            if not main_value or main_value < 0 then
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
                local amount = max_count * production.get_ingredient_amount(machine, machine.recipe.ingredients[index])
                requested[ingredient.name] = (requested[ingredient.name] or 0) + amount
            end
        end
    end
end

---@param g Graph
---@param structure_change boolean?
function production.push(g, structure_change)
    if not storage.production_queue then
        storage.production_queue = {}
    end
    local player_index = g.player.index
    local data = storage.production_queue[player_index]
    if data then
        if structure_change then
            data.structure_change = true
        end
    else
        storage.production_queue[player_index] = { g = g, structure_change = structure_change }
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
    local production_queue = storage.production_queue
    if not production_queue then
        return
    end
    storage.production_queue = nil
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

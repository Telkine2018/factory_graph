local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local drawing = require("scripts.drawing")

local prefix = commons.prefix

local graph = {}
local recipe_sprite_scale = 0.5

local e_recipe_name = commons.recipe_symbol_name
local e_product_name = commons.product_symbol_name
local e_unresearched_name = commons.unresearched_symbol_name

local initial_col = 2

local log_enabled = false

local floor = math.floor
local ceil = math.ceil
local abs = math.abs
local max = math.max
local sqrt = math.sqrt

---@param  surface LuaSurface
---@return Graph
function graph.new(surface)
    ---@type Graph
    return {
        surface = surface,
        recipes = {},
        products = {},
        entity_map = {},
        selection = {},
        gcols = {},
        root_products = {},
        select_mode = commons.default_selection,
        x_routing = {},
        y_routing = {},
        grid_size = commons.grid_size,
        color_index = 0,
        iovalues = {},
        show_hidden = false,
        show_only_researched = false,
        always_use_full_selection = true,
        visibility = commons.visibility_all,
        layout_on_selection = true,
        autosave_on_graph_switching = true,
        graph_zoom_level = 0.5,
        world_zoom_level = 2,
        line_gap = 0.2,
        show_products = true
    }
end

---@param g Graph
---@param name string
local function get_product(g, name)
    ---@type GProduct
    local product = g.products[name]
    if not product then
        product = {
            name = name,
            ingredient_of = {},
            product_of = {},
            is_root = true
        }
        g.products[name] = product
    end
    product.used = true
    return product
end

---@param g Graph
---@param recipes table<string, LuaRecipe>
---@param excluded_categories {[string]:boolean}?
---@param excluded_subgroups {[string]:boolean}?
---@return boolean
function graph.update_recipes(g, recipes, excluded_categories, excluded_subgroups)
    if not excluded_categories then
        excluded_categories = {}
    end
    if not excluded_subgroups then
        excluded_subgroups = {}
    end
    local changed
    g.excluded_categories = excluded_categories
    g.excluded_subgroups = excluded_subgroups

    for _, gproduct in pairs(g.products) do
        gproduct.ingredient_of = {}
        gproduct.product_of = {}
    end

    for name, recipe in pairs(recipes) do
        if not excluded_categories[recipe.category]
            and not excluded_subgroups[recipe.subgroup.name]
            and not recipe.prototype.is_parameter then
            local grecipe = g.recipes[name]
            if not grecipe then
                grecipe = {
                    name = name,
                    ingredients = {},
                    products = {},
                    visible = true,
                    order = 1,
                    hidden = recipe.hidden
                }
                g.recipes[name] = grecipe
                changed = true
            else
                grecipe.machine = nil
                grecipe.hidden = recipe.hidden
                local pconfig = grecipe.production_config
                if pconfig then
                    ---@type boolean?
                    local failed = pconfig.machine_name and not prototypes.entity[tools.extract_name(pconfig.machine_name)]
                    failed = failed or (pconfig.beacon_name and not prototypes.entity[tools.extract_name(pconfig.beacon_name)])
                    if pconfig.machine_modules then
                        for _, module in pairs(pconfig.machine_modules) do
                            failed = failed or (module and not prototypes.item[module])
                        end
                    end
                    if pconfig.beacon_modules then
                        for _, module in pairs(pconfig.beacon_modules) do
                            failed = failed or (module and not prototypes.item[module])
                        end
                    end
                    if failed then
                        grecipe.production_config = nil
                    end
                end
            end
            grecipe.used = true
            if recipe.enabled then
                grecipe.enabled = true
            else
                grecipe.enabled = false
            end
            if recipe.ingredients then
                grecipe.ingredients = {}
                for _, ingredient in pairs(recipe.ingredients) do
                    local iname = ingredient.type .. "/" .. ingredient.name
                    local gproduct = get_product(g, iname)

                    table.insert(grecipe.ingredients, gproduct)
                    gproduct.ingredient_of[recipe.name] = grecipe
                end
            end

            if recipe.products then
                grecipe.products = {}
                for _, production in pairs(recipe.products) do
                    if production.type ~= "research-progress" then
                        local iname = production.type .. "/" .. production.name
                        local gproduct = get_product(g, iname)

                        table.insert(grecipe.products, gproduct)
                        gproduct.product_of[recipe.name] = grecipe
                        gproduct.is_root = nil
                    end
                end
                if #grecipe.products == 1 and recipe.products[1].probability == 0 then
                    grecipe.is_void = true
                end
            end
        end
    end

    local resources = prototypes.get_entity_filtered { { filter = "type", type = "resource" } }
    for _, resource in pairs(resources) do
        local minable = resource.mineable_properties
        if minable and minable.minable and minable.products then
            for _, p in pairs(minable.products) do
                if p.type ~= "research-progress" then
                    local pname = p.type .. "/" .. p.name
                    local product = get_product(g, pname)
                    product.is_root = true
                end
            end
        end
    end

    --[[
    local pumps = prototypes.get_entity_filtered  { { filter = "type", type = "offshore-pump" } }
    for _, pump in pairs(pumps) do
        local box = pump.fluid_box
        local fluid = box.filter
        if fluid then
            local product = get_product(g, "fluid/" .. fluid.name)
            product.is_root = true
        end
    end
    ]]

    for _, product in pairs(g.products) do
        if product.used and product.is_root then
            local name = product.name
            local grecipe = product.root_recipe
            if not grecipe then
                ---@type GRecipe
                grecipe = {
                    name = name,
                    ingredients = {},
                    products = { product },
                    is_product = true,
                    visible = true,
                    used = true
                }
                g.recipes[name] = grecipe
                product.root_recipe = grecipe
            else
                product.root_recipe.used = true
            end
            product.product_of[name] = grecipe
        end
    end

    changed = graph.remove_unused(g) or changed
    return changed
end

---@param g Graph
---@param except_names table<string, any>
function graph.delete_product_recipes(g, except_names)
    for product_name, product in pairs(g.products) do
        local recipe = g.recipes[product_name]
        if not except_names[product_name] then
            if recipe then
                product.product_of[product_name] = nil
                g.recipes[product_name] = nil
                g.selection[product_name] = nil
            end
        else
            recipe.visible = true
            g.selection[recipe.name] = recipe
        end
    end
end

---@param g Graph
---@param except_names table<string, any>
function graph.invisible_product_recipes(g, except_names)
    for product_name, product in pairs(g.products) do
        local recipe = g.recipes[product_name]
        if not except_names[product_name] then
            if recipe then
                recipe.visible = nil
                g.selection[recipe.name] = nil
            end
        else
            recipe.visible = true
            g.selection[recipe.name] = recipe
            product.product_of[recipe.name] = recipe
        end
    end
end

---@param g Graph
---@param product_name string
function graph.get_product_recipe(g, product_name)
    local recipe = g.recipes[product_name]
    local product = g.products[product_name]
    if recipe then
        recipe.visible = true
        g.selection[recipe.name] = recipe
        product.product_of[recipe.name] = recipe
        return recipe
    end

    recipe = {
        name = product_name,
        ingredients = {},
        products = { product },
        is_product = true,
        visible = true,
        used = true
    }
    g.recipes[product_name] = recipe
    product.product_of[product_name] = recipe
    return recipe
end

---@param g Graph
---@return boolean
function graph.remove_unused(g)
    local changed

    if g.rs_recipe and not g.rs_recipe.used then
        g.rs_recipe = nil
    end
    if g.rs_product and not g.rs_product.used then
        g.rs_product = nil
    end
    if g.selected_recipe and not g.selected_recipe.used then
        g.selected_recipe = nil
    end

    ---@type table<string, GRecipe>
    local to_remove_recipes = {}
    for _, grecipe in pairs(g.recipes) do
        if not grecipe.used then
            to_remove_recipes[grecipe.name] = grecipe
        else
            grecipe.used = nil
        end
    end
    for name, grecipe in pairs(to_remove_recipes) do
        if grecipe.entity and grecipe.entity.valid then
            grecipe.entity.destroy()
        end
        g.recipes[name] = nil
        g.selection[name] = nil
        changed = true
    end

    local to_remove_products = {}
    for _, product in pairs(g.products) do
        if not product.used then
            to_remove_products[product.name] = product
            g.iovalues[product.name] = nil
            if g.product_outputs then
                g.product_outputs[product.name] = nil
            end
            if g.product_inputs then
                g.product_inputs[product.name] = nil
            end
        else
            product.used = nil
        end
    end
    for name in pairs(to_remove_products) do
        g.products[name] = nil
        changed = true
    end

    if changed then
        if g.preferred_beacon and prototypes.entity[tools.id_to_signal(g.preferred_beacon).name] == nil then
            g.preferred_beacon = nil
        end
        if g.preferred_machines then
            for i = #g.preferred_machines, 1, -1 do
                if prototypes.entity[g.preferred_machines[i]] == nil then
                    table.remove(g.preferred_machines, i)
                end
            end
        end
        if g.preferred_modules then
            for i = #g.preferred_modules, 1, -1 do
                if prototypes.item[tools.id_to_signal(g.preferred_modules[i]).name] == nil then
                    table.remove(g.preferred_modules, i)
                end
            end
        end
        if g.preferred_beacon_modules then
            for i = #g.preferred_beacon_modules, 1, -1 do
                if prototypes.item[tools.id_to_signal(g.preferred_beacon_modules[i]).name] == nil then
                    table.remove(g.preferred_beacon_modules, i)
                end
            end
        end
    end
    return changed
end

---@param gcol GCol
---@param initial integer
---@return integer
function find_free_line(gcol, initial)
    local dist = 0
    local line
    local found
    repeat
        line = initial - dist
        found = gcol.line_set[line]
        if found and dist > 0 then
            line = initial + dist
            found = gcol.line_set[line]
        end
        dist = dist + 1
    until not found
    dist = dist - 1
    return line
end

---@param gcol GCol
---@param line integer
---@param recipe GRecipe
---@return integer
function set_free_line(gcol, line, recipe)
    recipe.line = line
    recipe.col = gcol.col
    gcol.line_set[line] = recipe
    if not gcol.max_line then
        gcol.max_line = line
        gcol.min_line = line
    else
        if line > gcol.max_line then gcol.max_line = line end
        if line < gcol.min_line then gcol.min_line = line end
    end
    return line
end

---@param g Graph
---@param recipe GRecipe
---@param col integer
---@param line integer
function set_recipe_location(g, recipe, col, line)
    local gcol = g.gcols[col]
    if not gcol then
        gcol = {
            col = col,
            line_set = {}
        }
        g.gcols[col] = gcol
    end
    set_free_line(gcol, line, recipe)
end

---@param gcol GCol
---@param initial integer
---@param recipe GRecipe
---@return integer
function alloc_free_line(gcol, initial, recipe)
    local line = find_free_line(gcol, initial)
    set_free_line(gcol, line, recipe)
    return line
end

---@param g Graph
---@param grecipe GRecipe
function graph.layout_recipe(g, grecipe)
    local line = 0
    local count = 0
    local max_col
    local gcols = g.gcols

    local gname = grecipe.name
    if g.current_col ~= initial_col then
        for _, ingredient in pairs(grecipe.ingredients) do
            for _, irecipe in pairs(ingredient.product_of) do
                if irecipe.visible and irecipe.name ~= gname then
                    local col = irecipe.col
                    if col then
                        if not max_col or col > max_col then
                            max_col = col
                            count = 1
                            line = irecipe.line
                        elseif max_col == col then
                            count = count + 1
                            line = line + irecipe.line
                        end
                    end
                end
            end
        end
        -- no ingredient or products
        if count == 0 then
            col = initial_col
            local gcol = g.gcols[col]
            if gcol and gcol.max_line then
                line = gcol.max_line + 1
            else
                line = 0
            end
            count = 1
            max_col = col
        end
    end
    if count == 0 then
        for _, ingredient in pairs(grecipe.ingredients) do
            for _, irecipe in pairs(ingredient.product_of) do
                if irecipe.visible and irecipe.line and irecipe.name ~= gname then
                    line = line + irecipe.line
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then
        for _, product in pairs(grecipe.products) do
            for _, precipe in pairs(product.ingredient_of) do
                if precipe.visible and precipe.line and precipe.name ~= gname then
                    line = line + precipe.line
                    count = count + 1
                end
            end
        end
    end

    local gcol = gcols[g.current_col]
    if not gcol then
        gcol = { col = g.current_col, line_set = {} }
        gcols[g.current_col] = gcol
    end

    if count == 0 then
        if not gcol.max_line then
            line = find_free_line(gcol, 0)
        else
            line = find_free_line(gcol, gcol.max_line + 1)
        end
    else
        line = ceil(line / count)
    end

    local found_dist
    local found_line
    local found_col
    if not max_col then
        line = g.product_line
        if not gcol.max_line then
            local prevcol = gcols[g.current_col - 1]
            if prevcol and prevcol.line then
                line = floor((prevcol.min_line + prevcol.max_line) / 2)
            else
                line = 1
            end
        end
        line = alloc_free_line(gcol, line, grecipe)
        grecipe.order = g.recipe_order
        g.recipe_order = g.recipe_order + 1
        found_col = g.current_col
    else
        local col = max_col + 1
        while true do
            local gcol = gcols[col]
            if not gcol then
                gcol = {
                    col = col,
                    line_set = {}
                }
                gcols[col] = gcol
            end

            local free_line = find_free_line(gcol, line)
            local dcol = col - max_col
            local d = abs(free_line - line) + dcol

            if not found_dist or d < found_dist then
                found_dist = d
                found_col = col
                found_line = free_line
            else
                break
            end
            col = col + 1
        end
        set_free_line(gcols[found_col], found_line, grecipe)
        grecipe.order = g.recipe_order
        g.recipe_order = g.recipe_order + 1
    end
    grecipe.col = found_col
    if log_enabled then
        log("Process: " .. grecipe.name)
    end
end

local layout_recipe = graph.layout_recipe

---@param g Graph
---@param grecipe GRecipe
function graph.insert_recipe(g, grecipe)
    local center_line, center_col, count = 0, 0, 0

    for _, ingredient in pairs(grecipe.ingredients) do
        local col1, line1, count1 = gutils.compute_sum(ingredient.product_of, grecipe.name)
        center_col = center_col + col1
        center_line = center_line + line1
        count = count + count1
    end
    for _, product in pairs(grecipe.products) do
        local col1, line1, count1 = gutils.compute_sum(product.ingredient_of, grecipe.name)
        center_col = center_col + col1
        center_line = center_line + line1
        count = count + count1
    end
    if count == 0 then
        graph.layout_recipe(g, grecipe)
        return
    end
    center_col = floor(center_col / count)
    center_line = floor(center_line / count)
    graph.insert_recipe_at_position(g, grecipe, center_col, center_line)
end

---@param g Graph
---@param grecipe GRecipe
function graph.remove_recipe_visibility(g, grecipe)
    if grecipe.line then
        local gcols = g.gcols[grecipe.col]
        if gcols then
            gcols.line_set[grecipe.line] = nil
        end
    end
    grecipe.visible = false
    g.selection[grecipe.name] = nil
    g.selected_recipe = nil
    g.selected_recipe_entity = nil
    grecipe.entity = nil
end

---@param g Graph
---@param grecipe GRecipe
---@param start_col integer
---@param start_line integer
function graph.insert_recipe_at_position(g, grecipe, start_col, start_line)
    local min_d
    local min_col
    local min_line
    local gcols = g.gcols

    ---@param col integer
    ---@param line integer
    local function process_position(col, line)
        local gcol = gcols[col]
        if gcol then
            if gcol.line_set[line] and gcols[col] ~= grecipe then
                return
            end
        end
        local dcol = col - start_col
        local dline = line - start_line
        local d = dcol * dcol + dline * dline
        if not min_d or d < min_d then
            min_col = col
            min_line = line
            min_d = d
        end
    end

    local radius = 0
    while (true) do
        min_d = nil
        for col = start_col - radius, start_col + radius do
            process_position(col, start_line + radius)
            process_position(col, start_line - radius)
        end
        for line = start_line - radius + 1, start_line + radius - 1 do
            process_position(start_col + radius, line)
            process_position(start_col - radius, line)
        end
        if min_d then
            break
        end
        radius = radius + 1
    end

    local gcol = gcols[min_col]
    if not gcol then
        gcol = { col = min_col, line_set = {} }
        gcols[min_col] = gcol
    end

    set_free_line(gcol, min_line, grecipe)
    if log_enabled then
        log("Process: " .. grecipe.name)
    end
end

---@param g Graph
function graph.standard_layout(g)
    -- Processed product
    ---@type {[string]:GProduct}
    local processed_products = {}

    ---@type GCol[]
    local gcols = {}
    g.gcols = gcols
    g.product_line = 1
    g.recipe_order = 1

    ---@type {[string]:GRecipe}
    local remaining_recipes = {}

    if log_enabled then
        log("------- Start layout ----------")
    end

    ---@type {[string]:GProduct}
    local product_to_process = {}

    ---@param product GProduct
    function add_processed_product(product)
        processed_products[product.name] = product
        product_to_process[product.name] = nil
        for rname, grecipe in pairs(product.ingredient_of) do
            if grecipe.visible and not grecipe.line then
                remaining_recipes[rname] = grecipe
            end
        end
    end

    local inputs = gutils.get_product_flow(g, g.recipes)
    local gcol = {
        col = 1,
        line_set = {}
    }
    gcols[1] = gcol
    for _, product in pairs(inputs) do
        local recipe = product.root_recipe
        if recipe then
            if recipe.visible then
                recipe.col = 1
                recipe.line = g.product_line
                set_free_line(gcol, g.product_line, recipe)
                g.product_line = g.product_line + 1
                recipe.order = g.recipe_order
                g.recipe_order = g.recipe_order + 1
                if log_enabled then
                    log("Process: " .. product.name)
                end
            end
        end
        processed_products[product.name] = product
        for _, recipe in pairs(product.ingredient_of) do
            if recipe.visible then
                remaining_recipes[recipe.name] = recipe
            end
        end
    end

    local recipe_count = 0
    for _, recipe in pairs(g.recipes) do
        if recipe.visible then
            if not recipe.line then
                local is_root = true
                for _, ing in pairs(recipe.ingredients) do
                    if not processed_products[ing.name] then
                        product_to_process[ing.name] = ing
                        for _, irecipe in pairs(ing.product_of) do
                            if irecipe.visible then
                                is_root = false
                                goto skip
                            end
                        end
                    end
                    ::skip::
                end
                if is_root then
                    remaining_recipes[recipe.name] = recipe
                end
            end
            recipe_count = recipe_count + 1
        end
    end


    local edge_size = max(ceil(0.5 * sqrt(recipe_count)), 3)

    g.current_col = initial_col
    while true do
        ---@type {[string]:GRecipe}
        local processed_recipes = {}

        ---@type {[string]:GProduct}
        local new_products = {}

        ---@type GCol
        local gcol = gcols[g.current_col]
        if not gcol then
            gcol = { col = g.current_col, line_set = {} }
            gcols[g.current_col] = gcol
        end

        ::restart::
        for name, grecipe in pairs(remaining_recipes) do
            -- check all ingredients
            for _, iproduct in pairs(grecipe.ingredients) do
                if not processed_products[iproduct.name] then
                    goto not_completed
                end
            end

            -- register recipes and new products
            processed_recipes[name] = grecipe
            for _, gproduct in pairs(grecipe.products) do
                if not processed_products[gproduct.name] then
                    new_products[gproduct.name] = gproduct
                end
            end

            ::not_completed::
        end

        if not next(processed_recipes) then
            if not next(product_to_process) then
                break
            end

            if log_enabled then
                log("Process: no completed recipe")
            end

            local found_count
            local found_product
            local found_avg_col
            local found_avg_col_count
            for _, gproduct in pairs(product_to_process) do
                if not processed_products[gproduct.name] then
                    local count = 0
                    local avg_col = 0
                    local avg_col_count = 0
                    for _, grecipe in pairs(gproduct.ingredient_of) do
                        if grecipe.col then
                            avg_col = avg_col + grecipe.col
                            avg_col_count = avg_col_count + 1
                        end
                    end
                    for _, grecipe in pairs(gproduct.product_of) do
                        if grecipe.col then
                            avg_col = avg_col + grecipe.col
                            avg_col_count = avg_col_count + 1
                        end
                    end
                    if count == 0 then
                        found_product = gproduct
                        found_avg_col = avg_col
                        found_avg_col_count = avg_col_count
                        goto product_found
                    elseif not found_count or found_count > count then
                        found_count = count
                        found_product = gproduct
                        found_avg_col = avg_col
                        found_avg_col_count = avg_col_count
                    end
                end
            end
            if not found_product then
                break
            end
            ::product_found::

            if found_product then
                log("Process: restart=" .. found_product.name)
            end

            if found_avg_col then
                found_avg_col = ceil(found_avg_col / found_avg_col_count)
                if found_avg_col < g.current_col - 1 then
                    local col = found_avg_col + 1
                    local gcol = gcols[col]

                    if not gcol or (gcol.max_line - gcol.min_line + 1) < edge_size then
                        g.current_col = col
                    end
                end
            end
            add_processed_product(found_product)

            ::line_found::
            goto restart
        end

        for name, grecipe in pairs(processed_recipes) do
            remaining_recipes[name] = nil

            layout_recipe(g, grecipe)
        end

        for _, gproduct in pairs(new_products) do
            for rname, grecipe in pairs(gproduct.ingredient_of) do
                if grecipe.visible then
                    remaining_recipes[rname] = grecipe
                end
            end
            processed_products[gproduct.name] = gproduct
        end

        gcol = gcols[g.current_col]
        if gcol.max_line then
            g.current_col = g.current_col + 1
        end
    end
    log("------- End layout ----------")

    graph.reverse_equalize_recipes(g)
    graph.equalize_recipes(g)

    graph.sort_recipes(g.selection)
end

---@param g Graph
function graph.reverse_equalize_recipes(g)
    local gcols = g.gcols
    for i = #gcols, 1, -1 do
        local gcol = gcols[i]
        local new_cols = {
            col = gcol.col,
            line_set = {}
        }
        gcols[i] = new_cols
        for _, line_recipe in pairs(gcol.line_set) do
            local count = 0
            local line = 0
            local min_dcol

            ---@cast line_recipe GRecipe
            for _, product in pairs(line_recipe.products) do
                for _, recipe in pairs(product.ingredient_of) do
                    if recipe.visible and recipe.col and recipe.col >= line_recipe.col then
                        local dcol = abs(recipe.col - line_recipe.col)
                        if not min_dcol or dcol < min_dcol then
                            min_dcol = dcol
                            count = 1
                            line = recipe.line
                        elseif min_dcol == dcol then
                            count = count + 1
                            line = line + recipe.line
                        end
                    end
                end
            end

            for _, ingredient in pairs(line_recipe.ingredients) do
                for _, recipe in pairs(ingredient.product_of) do
                    if recipe.visible and recipe.col and recipe.col >= line_recipe.col then
                        local dcol = abs(recipe.col - line_recipe.col)
                        if not min_dcol or dcol < min_dcol then
                            min_dcol = dcol
                            count = 1
                            line = recipe.line
                        elseif min_dcol == dcol then
                            count = count + 1
                            line = line + recipe.line
                        end
                    end
                end
            end

            if count == 0 then
                alloc_free_line(new_cols, line_recipe.line, line_recipe)
            else
                line = ceil(line / count)
                alloc_free_line(new_cols, line, line_recipe)
            end
        end
    end
end

---@param g Graph
function graph.equalize_recipes(g)
    local gcols = g.gcols
    for i = 1, #gcols do
        local gcol = gcols[i]
        local new_col = {
            col = gcol.col,
            line_set = {}
        }
        gcols[i] = new_col
        for _, line_recipe in pairs(gcol.line_set) do
            local count = 0
            local line = 0
            local min_dcol

            ---@cast line_recipe GRecipe
            if line_recipe.visible then
                if i == 1 then
                    for _, product in pairs(line_recipe.ingredients) do
                        if product.col then
                            local dcol = abs(product.col - line_recipe.col)
                            if not min_dcol or dcol < min_dcol then
                                min_dcol = dcol
                                count = 1
                                line = product.line
                            elseif min_dcol == dcol then
                                count = count + 1
                                line = line + product.line
                            end
                        end
                    end
                else
                    for _, ingredient in pairs(line_recipe.ingredients) do
                        for _, recipe in pairs(ingredient.product_of) do
                            if recipe.visible and recipe.col and recipe.col < line_recipe.col then
                                local dcol = abs(recipe.col - line_recipe.col)
                                if not min_dcol or dcol < min_dcol then
                                    min_dcol = dcol
                                    count = 1
                                    line = recipe.line
                                elseif min_dcol == dcol then
                                    count = count + 1
                                    line = line + recipe.line
                                end
                            end
                        end
                    end

                    for _, product in pairs(line_recipe.products) do
                        for _, recipe in pairs(product.ingredient_of) do
                            if recipe.visible and recipe.col and recipe.col < line_recipe.col then
                                local dcol = abs(recipe.col - line_recipe.col)
                                if not min_dcol or dcol < min_dcol then
                                    min_dcol = dcol
                                    count = 1
                                    line = recipe.line
                                elseif min_dcol == dcol then
                                    count = count + 1
                                    line = line + recipe.line
                                end
                            end
                        end
                    end
                end
                if count == 0 then
                    alloc_free_line(new_col, line_recipe.line, line_recipe)
                else
                    line = ceil(line / count)
                    alloc_free_line(new_col, line, line_recipe)
                end
            end
        end
    end
end

---@param g Graph
---@param grecipe GRecipe
local function create_recipe_object(g, grecipe)
    if not grecipe.line or not grecipe.visible or grecipe.entity then
        return
    end
    local sprite_name
    local entity_name
    if grecipe.is_product then
        sprite_name = grecipe.name
        entity_name = e_product_name
    elseif grecipe.enabled then
        sprite_name = "recipe/" .. grecipe.name
        entity_name = e_recipe_name
    else
        sprite_name = "recipe/" .. grecipe.name
        entity_name = e_unresearched_name
    end
    local surface = g.surface
    local x = grecipe.col * g.grid_size + 0.5
    local y = grecipe.line * g.grid_size + 0.5
    local e_recipe = surface.create_entity { name = entity_name, position = { x, y }, force = g.player.force_index, create_build_effect_smoke = false }
    ---@cast e_recipe -nil
    local scale = recipe_sprite_scale
    rendering.draw_sprite { surface = surface, sprite = sprite_name, target = e_recipe, x_scale = scale, y_scale = scale }
    grecipe.entity = e_recipe
    g.entity_map[e_recipe.unit_number] = grecipe
    return e_recipe
end
graph.create_recipe_object = create_recipe_object

---@param g Graph
function graph.create_recipe_objects(g)
    for _, grecipe in pairs(g.recipes) do
        create_recipe_object(g, grecipe)
    end
    drawing.draw_layers(g)
end

---@param player LuaPlayer
---@param keep_location boolean?
---@param keep_player_location boolean?
function graph.refresh(player, keep_location, keep_player_location)
    local g = gutils.get_graph(player)
    gutils.compute_visibility(g, keep_location)
    drawing.delete_content(g, keep_location)
    if not keep_location then
        graph.do_layout(g)
    end
    graph.create_recipe_objects(g)
    drawing.redraw_selection(player)
    if not keep_player_location and not keep_location and player.surface_index == g.surface.index then
        gutils.recenter(g)
    end
end

---@param player LuaPlayer
---@param data RedrawRequest?
function graph.deferred_update(player, data)
    local redraw_queue = storage.redraw_queue
    if not redraw_queue then
        redraw_queue = {}
        storage.redraw_queue = redraw_queue
    end
    if not data then
        data = {
            selection_changed = true
        }
    end
    local previous_data = redraw_queue[player.index]
    if previous_data then
        for key, value in pairs(data) do
            previous_data[key] = data[key]
        end
    else
        redraw_queue[player.index] = data
    end
end

tools.on_event(defines.events.on_tick,
    function(e)
        ---@type {[integer]:RedrawRequest}
        local redraw_queue = storage.redraw_queue
        if not redraw_queue then
            return
        end
        storage.redraw_queue = nil
        for player_index, data in pairs(redraw_queue) do
            local g = gutils.get_graph(game.players[player_index])
            if data.do_layout then
                drawing.clear_selection(g)
                gutils.compute_visibility(g)
                drawing.delete_content(g)
                graph.do_layout(g)
                graph.create_recipe_objects(g)
            elseif data.do_redraw then
                drawing.clear_selection(g)
                local position_missing = gutils.compute_visibility(g, true)
                if not position_missing then
                    drawing.delete_content(g, true)
                    graph.create_recipe_objects(g)
                else
                    drawing.delete_content(g)
                    graph.do_layout(g)
                    graph.create_recipe_objects(g)
                end
            end
            drawing.redraw_selection(game.players[player_index])
            if data.selection_changed then
                gutils.fire_selection_change(g)
                if not data.no_recipe_selection_update then
                    graph.update_recipe_selection(g.player)
                end
            end
            if data.center_on_recipe then
                if g.player.surface_index == g.surface.index then
                    gutils.move_to_recipe(g.player, data.center_on_recipe)
                end
            elseif data.center_on_graph then
                if g.player.surface_index == g.surface.index then
                    gutils.recenter(g)
                end
            end
            if data.draw_target and data.center_on_recipe then
                local grecipe = g.recipes[data.center_on_recipe]
                if grecipe then
                    drawing.draw_target(g, grecipe)
                end
            end
            drawing.draw_layers(g)
            if data.update_command then
                graph.update_command_display(g.player)
            end
            if data.update_product_list then
                tools.fire_user_event(commons.production_compute_event, { g = g })
            end
        end
    end
)

---@param player LuaPlayer
function graph.unselect(player)
    local g = gutils.get_graph(player)
    gutils.clear(g)
    graph.refresh(player)
    gutils.fire_production_data_change(g)
end

---@param g Graph
---@param data SavingData
function graph.load_saving(g, data)
    drawing.delete_content(g)
    local selection = {}
    for _, grecipe in pairs(data.selection) do
        local current = g.recipes[grecipe.name]
        if current then
            selection[grecipe.name] = current
            current.layer = tools.check_sprite(grecipe.layer)
            if grecipe.col then
                set_recipe_location(g, current, grecipe.col, grecipe.line)
            end
        end
    end
    g.selection = selection

    for _, field in pairs(gutils.saved_graph_fields) do
        if field ~= "visibility" then
            g[field] = data.config[field]
        end
    end
    if not g.color_index then g.color_index = 0 end

    if data.colors then
        for product_name, color in pairs(data.colors) do
            local gproduct = g.products[product_name]
            if gproduct then
                gproduct.color = color
            end
        end
    end

    g.visibility = data.config.visibility
    graph.deferred_update(g.player, {
        selection_changed = true,
        do_redraw = true,
        center_on_graph = true,
        update_command = true
    })
    gutils.fire_selection_change(g)
end

---@param g Graph
---@param data SavingData
function graph.import_saving(g, data)
    drawing.delete_content(g)
    local selection = g.selection
    for _, grecipe in pairs(data.selection) do
        local current = g.recipes[grecipe.name]
        selection[grecipe.name] = current
    end
    graph.refresh(g.player)
    gutils.fire_selection_change(g)
end

---@param node GRecipe
---@param set {[string]:GRecipe}
---@return GRecipe?
local function next_sort_node(node, set)
    local grecipe, gproduct

    local sort_recipe_current = node.sort_recipe_current
    local sort_product_current = node.sort_product_current
    while true do
        if sort_product_current then
            repeat
                sort_recipe_current, grecipe = next(node.products[sort_product_current].ingredient_of, sort_recipe_current)
                if grecipe and set[grecipe.name] then
                    node.sort_recipe_current = sort_recipe_current
                    node.sort_product_current = sort_product_current
                    return grecipe
                end
            until sort_recipe_current == nil
        end

        sort_product_current, gproduct = next(node.products, sort_product_current)
        sort_recipe_current            = nil
        if not gproduct then
            return nil
        end
    end
end


---@param set {[string]:GRecipe}
function graph.sort_recipes(set)
    local path = {}

    ---@type {[string]:GRecipe}
    local remaining = {}
    ---@type {[string]:GRecipe}
    local roots = {}

    --- reset
    for _, grecipe in pairs(set) do
        grecipe.sort_level = nil
        grecipe.sort_product_current = nil
        grecipe.sort_recipe_current = nil
        remaining[grecipe.name] = grecipe
        for _, ingredient in pairs(grecipe.ingredients) do
            for _, prev_recipe in pairs(ingredient.product_of) do
                if set[prev_recipe.name] then
                    goto not_a_root
                end
            end
        end
        roots[grecipe.name] = grecipe
        ::not_a_root::
    end

    local start_level = 1
    for _, grecipe in pairs(roots) do
        table.insert(path, grecipe)
        grecipe.in_path = true
        grecipe.sort_level = start_level
        start_level = start_level + 1000
        remaining[grecipe.name] = nil
    end

    while true do
        if #path == 0 then
            local recipe_name, grecipe = next(remaining)
            if not recipe_name then
                break
            end
            remaining[recipe_name] = nil
            table.insert(path, grecipe)
            grecipe.in_path = true
            grecipe.sort_level = start_level
            start_level = start_level + 1000
        end

        local node = path[#path]
        local next_in_path = next_sort_node(node, set)
        if not next_in_path then
            table.remove(path, #path)
            node.in_path = nil
        elseif not next_in_path.in_path then
            local next_level = node.sort_level + 1
            if not next_in_path.sort_level or next_in_path.sort_level < next_level then
                next_in_path.sort_level = next_level
                next_in_path.in_path = true
                next_in_path.sort_product_current = nil
                next_in_path.sort_recipe_current = nil
                table.insert(path, next_in_path)
                remaining[next_in_path.name] = nil
            end
        else
            next_in_path.is_recursive = true
        end
    end
end

---@param set {[string]:GRecipe}
function graph.create_sorted_recipe_table(set)
    local sort_table = {}
    for _, grecipe in pairs(set) do
        table.insert(sort_table, grecipe)
    end
    table.sort(sort_table, function(r1, r2) return r1.sort_level < r2.sort_level end)
    return sort_table
end

local get_element_at_position = gutils.get_element_at_position
local set_colline = gutils.set_colline

---@class DisplayTreeNode
---@field recipe_name string
---@field grecipe GRecipe
---@field parent DisplayTreeNode
---@field children table<string, DisplayTreeNode>
---@field height integer
---@field top integer
---@field depth integer

---@param g Graph
---@param settings {horizontal:boolean?, invert:boolean?, show_products:boolean?}
function graph.tree_layout(g, settings)
    local inputs, outputs, intermediates, to_process, recipes = gutils.get_product_flow(g, g.recipes)

    if g.show_products then
        ---@param product_name string
        local function add_product(product_name)
            local grecipe = graph.get_product_recipe(g, product_name)
            recipes[grecipe.name] = grecipe
            grecipe.visible = true
            g.selection[grecipe.name] = grecipe
        end

        graph.invisible_product_recipes(g, {})
        for product_name, _ in pairs(inputs) do
            add_product(product_name)
        end
        for ioname, value in pairs(g.iovalues) do
            if value == true or (type(value) == "number" and value < 0) then
                if value == true and g.product_outputs and g.product_inputs then
                    local output = g.product_outputs[ioname]
                    local input = g.product_inputs[ioname]
                    if output and input and output > input then
                        goto skip
                    end
                end
                if inputs[ioname] or outputs[ioname] or intermediates[ioname] then
                    add_product(ioname)
                end
                ::skip::
            end
        end
    else
        graph.invisible_product_recipes(g, {})
    end

    local horizontal = settings.horizontal
    local invert = settings.invert

    ---@type table<string, boolean>
    local processed_products = {}

    ---@type DisplayTreeNode[]
    local node_table = {}

    if table_size(to_process) == 0 then
        return
    end

    local node_index = 1
    local processed_recipes = {}

    local function build_tree()
        while node_index <= #node_table do
            local current = node_table[node_index]
            node_index = node_index + 1
            for _, ingredient in pairs(current.grecipe.ingredients) do
                if not processed_products[ingredient.name] then
                    processed_products[ingredient.name] = true
                    to_process[ingredient.name] = nil
                    for pname, precipe in pairs(ingredient.product_of) do
                        if precipe.visible and not processed_recipes[pname] then
                            ---@type DisplayTreeNode
                            local newnode = {
                                recipe_name = pname,
                                grecipe = precipe,
                                parent = current,
                                depth = current.depth + 1
                            }
                            table.insert(node_table, newnode)
                            processed_recipes[pname] = true
                            if current.children then
                                current.children[pname] = newnode
                            else
                                current.children = { [pname] = newnode }
                            end
                        end
                    end
                end
            end
        end
    end

    ---@param product GProduct
    local function add_root(product)
        if processed_products[product.name] then
            return
        end
        processed_products[product.name] = true
        to_process[product.name] = nil
        for pname, precipe in pairs(product.product_of) do
            if precipe.visible and not processed_recipes[pname] then
                ---@type DisplayTreeNode
                local newnode = {
                    recipe_name = pname,
                    grecipe = precipe,
                    depth = 1
                }
                processed_recipes[pname] = true
                table.insert(node_table, newnode)
            end
        end
    end

    ---@param grecipe GRecipe
    local function add_empty(grecipe)
        ---@type DisplayTreeNode
        local newnode = {
            recipe_name = grecipe.name,
            grecipe = grecipe,
            depth = 1
        }
        processed_recipes[grecipe.name] = true
        table.insert(node_table, newnode)
    end

    local sorted_table = {}
    for _, product in pairs(to_process) do
        if type(g.iovalues[product.name]) == "number" or outputs[product.name] then
            table.insert(sorted_table, product)
        end
    end

    table.sort(sorted_table,
        ---@param p1 GProduct
        ---@param p2 GProduct
        function(p1, p2)
            local s1 = tools.sprite_to_signal(p1.name)
            local s2 = tools.sprite_to_signal(p2.name)
            local order1, order2
            ---@cast s1 -nil
            ---@cast s2 -nil
            if s1.type == "item" then
                local proto = prototypes.item[s1.name]
                order1 = proto.group.order .. " " .. proto.subgroup.order .. " " .. proto.order
            elseif s1.type == "fluid" then
                local proto = prototypes.fluid[s1.name]
                order1 = proto.subgroup.order .. " " .. proto.order
            end
            if s2.type == "item" then
                local proto = prototypes.item[s2.name]
                order2 = proto.group.order .. " " .. proto.subgroup.order .. " " .. proto.order
            elseif s2.type == "fluid" then
                local proto = prototypes.fluid[s2.name]
                order2 = proto.subgroup.order .. " " .. proto.order
            end
            return order1 < order2
        end)

    for _, product in pairs(sorted_table) do
        if type(g.iovalues[product.name]) == "number" then
            add_root(product)
            build_tree()
        end
    end

    for _, product in pairs(sorted_table) do
        add_root(product)
        build_tree()
    end

    for _, grecipe in pairs(g.selection) do
        if grecipe.visible then
            if #grecipe.products == 0 then
                add_empty(grecipe)
            end
        end
    end

    --- Process other product
    while table_size(to_process) > 0 do
        ---@type GProduct
        local found
        local found_partial
        for _, product in pairs(to_process) do
            local is_complete = true
            local is_partial = false
            for _, recipe in pairs(product.ingredient_of) do
                for _, ingredient in pairs(recipe.ingredients) do
                    if not processed_products[ingredient] then
                        is_complete = false
                    else
                        is_partial = true
                    end
                end
            end
            if is_complete then
                found = product
                break
            elseif not found_partial and is_partial then
                found = product
                found_partial = is_partial
            elseif not found then
                found = product
                found_partial = is_partial
            end
        end
        if not found then
            break
        end
        add_root(found)
        build_tree()
    end

    for i = #node_table, 1, -1 do
        local node = node_table[i]

        node.height = 1
        if node.children then
            local height = 0
            for _, child in pairs(node.children) do
                height = height + child.height
            end
            node.height = height
        end
    end

    local tree_top = 0
    local tree_height = 0
    local tree_depth = 0
    for i = 1, #node_table do
        local node = node_table[i]
        if node.depth > tree_depth then
            tree_depth = node.depth
        end
        if not node.parent then
            node.top = tree_top
            tree_top = tree_top + node.height
            tree_height = tree_height + node.height
        end
        if node.children then
            local top = node.top
            for _, child in pairs(node.children) do
                child.top = top
                top = top + child.height
            end
        end
    end

    g.gcols = {}
    g.product_line = 1
    g.recipe_order = 1

    if horizontal then
        for _, node in pairs(node_table) do
            local line = node.top + math.floor(node.height / 2)
            local col = node.depth
            if invert then
                col = tree_depth - col
            end

            set_colline(g, node.grecipe, col, line)
        end
    else
        for _, node in pairs(node_table) do
            local col = node.top + math.floor(node.height / 2)
            local line = node.depth
            if invert then
                line = tree_depth - line
            end

            set_colline(g, node.grecipe, col, line)
        end
    end

    graph.sort_recipes(recipes)
end

function graph.do_layout(g)
    local mode = settings.global["factory_graph-auto_layout"].value
    if mode == "standard" or g.visibility == commons.visibility_all then
        graph.standard_layout(g)
    elseif mode == "htree" then
        graph.tree_layout(g, { horizontal = true, invert = false })
    elseif mode == "htreei" then
        graph.tree_layout(g, { horizontal = true, invert = true })
    elseif mode == "vtree" then
        graph.tree_layout(g, { horizontal = false, invert = false })
    elseif mode == "vtreei" then
        graph.tree_layout(g, { horizontal = false, invert = true })
    end
end

---@param player LuaPlayer
function graph.update_command_display(player)
end

---@param player LuaPlayer
function graph.update_recipe_selection(player)
end

return graph

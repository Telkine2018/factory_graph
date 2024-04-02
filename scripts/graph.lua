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

local log_enabled = true

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
        iovalues = {}
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
function graph.update_recipes(g, recipes, excluded_categories)
    if not excluded_categories then
        excluded_categories = {}
    end
    g.excluded_categories = excluded_categories
    for name, recipe in pairs(recipes) do
        if not excluded_categories[recipe.category] then
            if not recipe.hidden or g.show_hidden then
                local grecipe = g.recipes[name]
                if not grecipe then
                    grecipe = {
                        name = name,
                        ingredients = {},
                        products = {},
                        visible = true
                    }
                    g.recipes[name] = grecipe
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
                        local iname = production.type .. "/" .. production.name
                        local gproduct = get_product(g, iname)

                        table.insert(grecipe.products, gproduct)
                        gproduct.product_of[recipe.name] = grecipe
                        gproduct.is_root = nil
                    end
                end
            end
        end
    end

    local resources = game.get_filtered_entity_prototypes { { filter = "type", type = "resource" } }
    for _, resource in pairs(resources) do
        local minable = resource.mineable_properties
        if minable and minable.minable and minable.products then
            for _, p in pairs(minable.products) do
                local pname = p.type .. "/" .. p.name
                local product = get_product(g, pname)
                product.is_root = true
            end
        end
    end

    local pumps = game.get_filtered_entity_prototypes { { filter = "type", type = "offshore-pump" } }
    for _, pump in pairs(pumps) do
        local fluid = pump.fluid
        if fluid then
            local product = get_product(g, "fluid/" .. fluid.name)
            product.is_root = true
        end
    end

    for _, product in pairs(g.products) do
        if product.is_root then
            if not product.root_recipe then
                local name = product.name
                ---@type GRecipe
                local grecipe = {
                    name = name,
                    ingredients = {},
                    products = { product },
                    is_product = true,
                    visible = true,
                    used = true
                }
                g.recipes[name] = grecipe
                product.root_recipe = grecipe
                product.product_of[name] = grecipe
            else
                product.root_recipe.used = true
            end
        end
    end

    graph.remove_unused(g)
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

    local to_remove = {}
    for _, recipe in pairs(g.recipes) do
        if not recipe.used then
            to_remove[recipe.name] = true
        else
            recipe.used = nil
        end
    end
    for name in pairs(to_remove) do
        g.recipes[name] = nil
        g.selection[name] = nil
        changed = true
    end

    to_remove = {}
    for _, product in pairs(g.products) do
        if not product.used then
            to_remove[product.name] = true
            g.iovalues[product.name] = nil
            g.product_outputs[product.name] = nil
            g.product_effective[product.name] = nil
        else
            product.used = nil
        end
    end
    for name in pairs(to_remove) do
        g.products[name] = nil
        changed = true
    end

    if changed then
        if g.preferred_beacon and game.entity_prototypes[g.preferred_beacon] == nil then
            g.preferred_beacon = nil
        end
        if g.preferred_machines then
            for i = #g.preferred_machines, 1, -1 do
                if game.entity_prototypes[g.preferred_machines[i]] == nil then
                    table.remove(g.preferred_machines, i)
                end
            end
        end
        if g.preferred_modules then
            for i = #g.preferred_modules, 1, -1 do
                if game.item_prototypes[g.preferred_modules[i]] == nil then
                    table.remove(g.preferred_modules, i)
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

    if g.current_col ~= initial_col then
        for _, ingredient in pairs(grecipe.ingredients) do
            for _, irecipe in pairs(ingredient.product_of) do
                if irecipe.visible then
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
    end
    if count == 0 then
        for _, ingredient in pairs(grecipe.ingredients) do
            for _, irecipe in pairs(ingredient.product_of) do
                if irecipe.visible and irecipe.line then
                    line = line + irecipe.line
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then
        for _, product in pairs(grecipe.products) do
            for _, precipe in pairs(product.ingredient_of) do
                if precipe.visible and precipe.line then
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
        line = math.ceil(line / count)
    end

    local found_dist
    local found_line
    local found_col
    if not max_col then
        line = g.product_line
        if not gcol.max_line then
            local prevcol = gcols[g.current_col - 1]
            if prevcol and prevcol.line then
                line = math.floor((prevcol.min_line + prevcol.max_line) / 2)
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
            local d = math.abs(free_line - line) + dcol

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
    local gcols = g.gcols

    for _, ingredient in pairs(grecipe.ingredients) do
        local col1, line1, count1 = gutils.compute_sum(ingredient.product_of)
        center_col = center_col + col1
        center_line = center_line + line1
        count = count + count1
    end
    for _, product in pairs(grecipe.products) do
        local col1, line1, count1 = gutils.compute_sum(product.ingredient_of)
        center_col = center_col + col1
        center_line = center_line + line1
        count = count + count1
    end
    if count == 0 then
        graph.layout_recipe(g, grecipe)
        return
    end
    center_col = math.floor(center_col / count)
    center_line = math.floor(center_line / count)

    local min_d
    local min_col
    local min_line

    ---@param col integer
    ---@param line integer
    local function process_position(col, line)
        local gcol = gcols[col]
        if gcol then
            if gcol.line_set[line] then
                return
            end
        end
        if col <= 1 then
            return
        end
        local dcol = col - center_col
        local dline = line - center_line
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
        for col = center_col - radius, center_col + radius do
            process_position(col, center_line + radius)
            process_position(col, center_line - radius)
        end
        for line = center_line - radius + 1, center_line + radius - 1 do
            process_position(center_col + radius, line)
            process_position(center_col - radius, line)
        end
        if min_d then
            break
        end
        radius = radius + 1
    end

    local gcol = gcols[min_col]
    if not gcol then
        gcol = { col = g.current_col, line_set = {} }
        gcols[min_col] = gcol
    end

    set_free_line(gcol, min_line, grecipe)
    if log_enabled then
        log("Process: " .. grecipe.name)
    end
end

---@param g Graph
function graph.do_layout(g)
    -- Processed product
    ---@type {[string]:GProduct}
    local processed_products = {}

    ---@type GCol[]
    local gcols = {}
    g.gcols = gcols

    ---@type {[string]:GRecipe}
    local remaining_recipes = {}
    g.product_line = 1
    g.recipe_order = 1

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

    local inputs, outputs, intermediates, recipe_count = gutils.get_product_flow(g, true)
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


    local edge_size = math.max(math.ceil(0.5 * math.sqrt(recipe_count)), 3)

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
                        if not grecipe.col then
                            for _, ingredient in pairs(grecipe.ingredients) do
                                if ingredient ~= gproduct and not processed_products[ingredient.name] then
                                    count = count + 1
                                end
                            end
                        else
                            avg_col = avg_col + grecipe.col
                            avg_col_count = avg_col_count + 1
                        end
                    end
                    for _, grecipe in pairs(gproduct.product_of) do
                        if not grecipe.col then
                            local count = 0
                            for _, prod in pairs(grecipe.products) do
                                if prod ~= gproduct and not processed_products[prod.name] then
                                    count = count + 1
                                end
                            end
                        else
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
                found_avg_col = math.ceil(found_avg_col / found_avg_col_count)
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
                        local dcol = math.abs(recipe.col - line_recipe.col)
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
                        local dcol = math.abs(recipe.col - line_recipe.col)
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
                line = math.ceil(line / count)
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
                            local dcol = math.abs(product.col - line_recipe.col)
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
                                local dcol = math.abs(recipe.col - line_recipe.col)
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
                                local dcol = math.abs(recipe.col - line_recipe.col)
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
                    line = math.ceil(line / count)
                    alloc_free_line(new_col, line, line_recipe)
                end
            end
        end
    end
end

---@param g Graph
---@param grecipe GRecipe
local function draw_recipe(g, grecipe)
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
end

---@param g Graph
function graph.draw(g)
    for _, grecipe in pairs(g.recipes) do
        draw_recipe(g, grecipe)
    end
end

---@param player LuaPlayer
function graph.refresh(player)
    local g = gutils.get_graph(player)
    gutils.compute_visibility(g)
    drawing.delete_content(g)
    graph.do_layout(g)
    graph.draw(g)
    drawing.update_drawing(player)
    gutils.recenter(g)
end

---@param player LuaPlayer
function graph.unselect(player)
    local g = gutils.get_graph(player)
    g.selection = {}
    g.iovalues = {}
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
        selection[grecipe.name] = current
        set_recipe_location(g, current, grecipe.col, grecipe.line)
    end
    g.selection = selection

    for _, field in pairs(gutils.saved_graph_fields) do
        if field ~= "visibility" then
            g[field] = data.config[field]
        end
    end

    if g.visibility == commons.visibility_selection and
        data.config.visibility == commons.visibility_selection then
        gutils.compute_visibility(g, true)
        graph.draw(g)
        drawing.update_drawing(g.player)
        gutils.recenter(g)
    else
        graph.refresh(g)
    end
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
end


return graph

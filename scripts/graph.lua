local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local drawing = require("scripts.drawing")

local prefix = commons.prefix

local surface_prefix = commons.surface_prefix
local tile_name = commons.tile_name

local graph = {}
local recipe_sprite_scale = 0.5

local e_recipe_name = commons.recipe_symbol_name
local e_product_name = commons.product_symbol_name

local initial_col = 2


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
        color_index = 0
    }
end

---@param g Graph
---@param name string
local function get_product(g, name)
    ---@type GProduct
    local product = g.products[name]
    if product then return product end

    product = {
        name = name,
        ingredient_of = {},
        product_of = {},
        is_root = true
    }
    g.products[name] = product
    return product
end

---@param g Graph
---@param recipes table<string, LuaRecipePrototype>
---@param excluded_categories {[string]:boolean}?
function graph.add_recipes(g, recipes, excluded_categories)
    if not excluded_categories then
        excluded_categories = {}
    end
    g.excluded_categories = excluded_categories
    for name, recipe in pairs(recipes) do
        if not excluded_categories[recipe.category] then
            if not recipe.hidden or g.show_hidden then
                ---@type GRecipe
                local grecipe = {
                    name = name,
                    ingredients = {},
                    products = {},
                    visible = true
                }
                g.recipes[name] = grecipe
                if recipe.ingredients then
                    for _, ingredient in pairs(recipe.ingredients) do
                        local iname = ingredient.type .. "/" .. ingredient.name
                        local gproduct = get_product(g, iname)

                        table.insert(grecipe.ingredients, gproduct)
                        gproduct.ingredient_of[recipe.name] = grecipe
                    end
                end

                if recipe.products then
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
            local name = product.name
            ---@type GRecipe
            local grecipe = {
                name = name,
                ingredients = {},
                products = { product },
                is_product = true,
                visible = true
            }
            g.recipes[name] = grecipe
            product.root_recipe = grecipe
            product.product_of[name] = grecipe
        end
    end
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
    if count == 0 then
        line = g.product_line
        g.product_line = g.product_line + 1
    else
        line = math.ceil(line / count)
    end

    local found_dist
    local found_line
    local found_col
    if not max_col then
        local gcol = gcols[g.current_col]
        if not gcol then
            gcol = { col = g.current_col, line_set = {} }
            gcols[g.current_col] = gcol
        end
        line = alloc_free_line(gcol, line, grecipe)
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
    end
    grecipe.col = found_col
end

local layout_recipe = graph.layout_recipe

---@param g Graph
function graph.do_layout(g)
    -- Processed product
    ---@type {[string]:GProduct}
    local processed_products = {}

    local gcols = {}
    g.gcols = gcols

    ---@type {[string]:GRecipe}
    local remaining_recipes = {}
    local root_products = {}
    g.root_products = root_products
    g.product_line = 1

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

    local gcol = {
        col = 1,
        line_set = {}
    }
    gcols[1] = gcol
    for _, product in pairs(g.products) do
        local recipe = product.root_recipe
        if recipe and recipe.visible then
            add_processed_product(product)
            recipe.col = 1
            recipe.line = g.product_line
            set_free_line(gcol, g.product_line, recipe)
            g.product_line = g.product_line + 1
            root_products[product.name] = product
        end
    end

    for _, recipe in pairs(g.recipes) do
        if recipe.visible and not recipe.line then
            local is_root = true
            for _, ing in pairs(recipe.ingredients) do
                product_to_process[ing.name] = ing
                for _, irecipe in pairs(ing.product_of) do
                    if irecipe.visible then 
                        is_root = false
                        goto skip
                    end
                end
                ::skip::
            end
            for _, prod in pairs(recipe.products) do
                product_to_process[prod.name] = prod
            end
            if is_root then
                remaining_recipes[recipe.name] = recipe
            end
        end
    end

    g.current_col = initial_col
    while next(remaining_recipes) do
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
            local found_count
            local found_product
            for name, gproduct in pairs(product_to_process) do
                if not processed_products[name] then
                    local count = table_size(gproduct.ingredient_of) + table_size(gproduct.product_of)
                    if not found_count or count > found_count then
                        found_product = gproduct
                        found_count = count
                    end
                end
            end

            if not found_product then
                break
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
                    if recipe.visible then
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
function graph.equalize_roots(g)
    local root_col = {
        col = 1,
        line_set = {}
    }
    for _, product in pairs(g.root_products) do
        if product.root_recipe.visible then
            local count = 0
            local line = 0
            local min_dcol

            for _, recipe in pairs(product.ingredient_of) do
                if recipe.visible then
                    local dcol = math.abs(recipe.col - product.col)
                    if not min_dcol or dcol < min_dcol then
                        line = recipe.line
                        min_dcol = dcol
                        count = 1
                    elseif min_dcol == dcol then
                        line = line + recipe.line
                        count = count + 1
                    end
                end
            end

            if count == 0 then
                alloc_free_line(root_col, product.line, product.root_recipe)
            else
                line = math.ceil(line / count)
                alloc_free_line(root_col, line, product.root_recipe)
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
                    for _, product in pairs(line_recipe.ingredients) do
                        for _, recipe in pairs(product.product_of) do
                            if recipe.visible and recipe.col then
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
    else
        sprite_name = "recipe/" .. grecipe.name
        entity_name = e_recipe_name
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

tools.on_configuration_changed(function(data)
    for _, player in pairs(game.players) do
        local g = tools.get_vars(player).graph
        if g then
            if not g.grid_size then
                g.grid_size = commons.grid_size
            end
            if not g.color_index then
                g.color_index = 0
            end
        end
    end
end)

return graph

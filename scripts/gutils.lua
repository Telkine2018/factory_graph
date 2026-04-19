local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")

local gutils = {}

local recipe_entity_names = commons.recipe_entity_names

local function np(name)
    return commons.prefix .. "-gutils." .. name
end

---@param ids LuaRenderObject[]?
---@return nil
function gutils.destroy_drawing(ids)
    if not ids then return nil end

    for _, id in pairs(ids) do
        id.destroy()
    end
    return nil
end

---@param recipe GRecipe
---@return {[string]:GProduct}
function gutils.product_set(recipe)
    local result = {}
    for _, product in pairs(recipe.ingredients) do
        result[product.name] = product
    end
    for _, product in pairs(recipe.products) do
        result[product.name] = product
    end
    return result
end

---@param player LuaPlayer
---@return Graph
function gutils.get_graph(player)
    return tools.get_vars(player).graph
end

local match = string.match

---@param player LuaPlayer
---@param grecipe GRecipe
---@return LocalisedString
function gutils.get_recipe_name(player, grecipe)
    ---@type LocalisedString
    local localised_name

    if grecipe.is_product then
        if match(grecipe.name, "^item/") then
            localised_name = translations.get_item_name(player.index, string.sub(grecipe.name, 6))
        else -- fluid
            localised_name = translations.get_fluid_name(player.index, string.sub(grecipe.name, 7))
        end
    else
        localised_name = translations.get_recipe_name(player.index, grecipe.name) or ""
    end
    return localised_name
end

---@param player LuaPlayer
---@param name string
---@return LocalisedString
function gutils.get_product_name(player, name)
    ---@type LocalisedString
    local localised_name

    if match(name, "^item/") then
        localised_name = translations.get_item_name(player.index, string.sub(name, 6))
    else -- fluid
        localised_name = translations.get_fluid_name(player.index, string.sub(name, 7))
    end
    return localised_name
end

---@param g Graph
---@param line integer
---@param col integer
---@return number
---@return number
function gutils.get_position(g, col, line)
    local grid_size = g.grid_size
    local x = col * grid_size + 0.5
    local y = line * grid_size + 0.5
    return x, y
end

---@param g Graph
---@param x number
---@param y number
---@return number
---@return number
function gutils.get_colline(g, x, y)
    local grid_size = g.grid_size
    local col = math.floor((x - 0.5 + grid_size / 2) / grid_size)
    local line = math.floor((y - 0.5 + grid_size / 2) / grid_size)
    return col, line
end

---@param g Graph
---@param recipe GRecipe
---@return MapPosition?
function gutils.get_recipe_position(g, recipe)
    if not recipe.col then return nil end
    local x, y = gutils.get_position(g, recipe.col, recipe.line)
    return { x = x, y = y }
end

---@param player LuaPlayer
---@param position MapPosition
function gutils.move_view(player, position)
    local speed = 50 / 60.0
    local origin = player.position
    local dx = (position.x - origin.x)
    local dy = (position.y - origin.y)
    local dist = math.sqrt(dx * dx + dy * dy)
    local count = math.ceil(dist / speed)
    if count == 0 then return end
    dx = dx / count
    dy = dy / count
    if not storage.recipe_move then
        storage.recipe_move = {}
    end
    storage.recipe_move[player.index] = {
        x = origin.x,
        y = origin.y,
        dx = dx,
        dy = dy,
        count = count
    }
end

---@param player LuaPlayer
---@param recipe_name string
---@param fast boolean?
function gutils.move_to_recipe(player, recipe_name, fast)
    local g = gutils.get_graph(player)
    if not g then return end

    if g.surface ~= player.surface then return end

    local grecipe = g.recipes[recipe_name]
    if not grecipe or not grecipe.line then return end

    local position = gutils.get_recipe_position(g, grecipe)
    if not position then return end

    if fast then
        player.set_controller { type = defines.controllers.remote, position = position, surface = g.surface }
    else
        gutils.move_view(player, position)
    end
end

---@class MoveProcess
---@field dx number
---@field dy number
---@field count integer

local function move_tick_handler()
    ---@type {[integer]:MoveProcess}
    local moves = storage.recipe_move
    if not moves then return end

    local toremove = {}
    for player_index, move in pairs(moves) do
        local player = game.players[player_index]
        local g = gutils.get_graph(player)
        local count = move.count
        count = count - 1
        if count <= 0 then
            toremove[player_index] = true
        else
            local pos = player.position
            local x = pos.x + move.dx
            local y = pos.y + move.dy
            gutils.teleport(player, { x, y })
            move.count = count
        end
    end
    for player_index, _ in pairs(toremove) do
        moves[player_index] = nil
    end
    if table_size(moves) == 0 then
        storage.recipe_move = nil
    end
end
tools.on_event(defines.events.on_tick, move_tick_handler)

---@param g Graph
---@param recipe GRecipe?
---@return boolean
function gutils.select_current_recipe(g, recipe)
    if not recipe then return false end
    if g.selection[recipe.name] then return false end
    g.selection[recipe.name] = recipe
    if g.visibility == commons.visibility_layers then
        recipe.layer = g.current_layer
    end
    return true
end

---@param g Graph
---@param keep_position boolean?
---@return boolean
function gutils.compute_visibility(g, keep_position)
    local show_only_researched = g.show_only_researched
    local position_missing = false
    if g.visibility == commons.visibility_selection then
        local selection = g.selection
        if not selection then
            selection = {}
        end
        for _, grecipe in pairs(g.recipes) do
            grecipe.selector_positions = nil
            grecipe.entity = nil
            grecipe.visible = true
            if selection[grecipe.name] then
                if not keep_position then
                    grecipe.line = nil
                    grecipe.col = nil
                elseif not grecipe.line or not grecipe.col then
                    position_missing = true
                end
            else
                grecipe.line = nil
                grecipe.col = nil
                grecipe.visible = nil
            end
        end
    elseif g.visibility == commons.visibility_layers then
        local selection = g.selection
        if not selection then
            selection = {}
        end
        local visible_layers = g.visible_layers
        if not visible_layers then
            visible_layers = {}
        end
        for _, grecipe in pairs(g.recipes) do
            grecipe.selector_positions = nil
            grecipe.entity = nil
            if selection[grecipe.name] then
                if grecipe.layer and visible_layers[grecipe.layer] then
                    grecipe.visible = true
                else
                    grecipe.visible = nil
                end
                if not keep_position then
                    grecipe.line = nil
                    grecipe.col = nil
                else
                    if not grecipe.line or not grecipe.col then
                        position_missing = true
                    end
                end
            else
                grecipe.line = nil
                grecipe.col = nil
                grecipe.visible = nil
            end
        end
    else -- if g.visibility == commons.visibility_all then
        for _, grecipe in pairs(g.recipes) do
            if not keep_position then
                grecipe.line = nil
                grecipe.col = nil
            end
            grecipe.visible = true
            grecipe.entity = nil
            grecipe.selector_positions = nil
            if not g.show_hidden and grecipe.hidden then
                grecipe.visible = false
            end
            if show_only_researched and not grecipe.enabled then
                grecipe.visible = false
            end
        end
    end
    return position_missing
end

---@param g Graph
---@return table<string, GProduct>
function gutils.get_visible_products(g)
    local products = {}
    for _, product in pairs(g.products) do
        for _, grecipe in pairs(product.ingredient_of) do
            if grecipe.visible then
                products[product.name] = product
                goto skip
            end
        end
        for _, grecipe in pairs(product.product_of) do
            if grecipe.visible then
                products[product.name] = product
                goto skip
            end
        end
        ::skip::
    end
    return products
end

---@generic KEY
---@param recipes table<KEY, GRecipe>
---@return table<KEY, GRecipe>
function gutils.filter_enabled_recipe(recipes)
    local new_recipes = {}
    for key, recipe in pairs(recipes) do
        if recipe.enabled and not recipe.is_product then
            new_recipes[key] = recipe
        end
    end
    return new_recipes
end

---@generic KEY
---@param recipes table<KEY, GRecipe>
---@return table<KEY, GRecipe>
function gutils.filter_non_product_recipe(recipes)
    local new_recipes = {}
    for key, recipe in pairs(recipes) do
        if not recipe.is_product then
            new_recipes[key] = recipe
        end
    end
    return new_recipes
end

---@generic KEY
---@param recipes table<KEY, GRecipe>
---@param g Graph
---@return table<KEY, GRecipe>
function gutils.filter_lab_pack(recipes, g)
    local lab_packs = g.lab_packs
    if lab_packs == nil or #lab_packs == 0 then return recipes end
    local lab_filter = {}
    for _, lab in pairs(lab_packs) do
        lab_filter[lab] = true
    end
    local new_recipes = {}
    for index, recipe in pairs(recipes) do
        local technologies = prototypes.get_technology_filtered({ { filter = "unlocks-recipe", recipe = recipe.name } })
        if #technologies > 0 then
            for _, tech in pairs(technologies) do
                for _, ingredient in pairs(tech.research_unit_ingredients) do
                    if not lab_filter[ingredient.name] then
                        goto skip
                    end
                end
            end
        else
            if not g.recipes[recipe.name].enabled then
                goto skip
            end
        end
        new_recipes[recipe.name] = recipe
        ::skip::
    end
    return new_recipes
end

---@param grecipe GRecipe
function gutils.get_connected_recipe(grecipe)
    local result = gutils.get_connected_ingredients(grecipe)
    gutils.get_connected_productions(grecipe)
    result[grecipe.name] = nil
    return result
end

---@param grecipe GRecipe
---@param result table<string, GRecipe>?
---@return table<string, GRecipe>
function gutils.get_connected_ingredients(grecipe, result)
    if not result then result = {} end

    for _, ingredient in pairs(grecipe.ingredients) do
        for _, irecipe in pairs(ingredient.product_of) do
            if irecipe.visible then
                result[irecipe.name] = irecipe
            end
        end
    end
    return result
end

---@param grecipe GRecipe
---@param result table<string, GRecipe>?
---@return table<string, GRecipe>
function gutils.get_connected_productions(grecipe, result)
    if not result then result = {} end

    for _, product in pairs(grecipe.products) do
        for _, precipe in pairs(product.ingredient_of) do
            if precipe.visible and precipe.col then
                result[precipe.name] = precipe
            end
        end
    end
    return result
end

---@param g Graph
---@param recipes {[string]:GRecipe}?
---@return table<string, GProduct>
---@return table<string, GProduct>
---@return table<string, GProduct>
---@return table<string, GProduct>
---@return table<string, GRecipe>
function gutils.get_product_flow(g, recipes)
    ---@type table<string, GProduct>
    local inputs
    ---@type table<string, GProduct>
    local outputs
    ---@type table<string, GProduct>
    local intermediates
    ---@type table<string, GProduct>
    local all

    inputs = {}
    outputs = {}
    intermediates = {}
    all = {}
    local used_recipes = {}
    if recipes then
        for _, recipe in pairs(recipes) do
            if recipe.visible and not recipe.is_product then
                used_recipes[recipe.name] = recipe
                for _, ingredient in pairs(recipe.ingredients) do
                    local name = ingredient.name
                    inputs[name] = ingredient
                    all[name] = ingredient
                end
            end
        end
        for _, recipe in pairs(recipes) do
            if recipe.visible and not recipe.is_product then
                used_recipes[recipe.name] = recipe
                for _, product in pairs(recipe.products) do
                    local name = product.name
                    if inputs[name] then
                        intermediates[name] = product
                        inputs[name] = nil
                    elseif not intermediates[name] then
                        outputs[name] = product
                    end
                    all[name] = product
                end
            end
        end
    end
    return inputs, outputs, intermediates, all, used_recipes
end

local line_margin = 5

---@param flow LuaGuiElement
---@param title LocalisedString?
function gutils.add_line(flow, title)
    if not title then
        line = flow.add { type = "line" }
        line.style.top_margin = line_margin
        line.style.bottom_margin = line_margin
    else
        local hflow = flow.add { type = "flow", direction = "horizontal" }
        hflow.add { type = "label", caption = title }
        local line = hflow.add { type = "line" }
        line.style.top_margin = 10
        hflow.style.top_margin = 3
        hflow.style.bottom_margin = 5
    end
end

---@param g Graph
function gutils.fire_selection_change(g)
    tools.fire_user_event(commons.selection_change_event, { g = g })
end

---@param g Graph
function gutils.recenter(g)
    local mincol, maxcol, minline, maxline

    local count = 0
    for _, grecipe in pairs(g.recipes) do
        if grecipe.col then
            if minline then
                if grecipe.col < mincol then mincol = grecipe.col end
                if grecipe.col > maxcol then maxcol = grecipe.col end
                if grecipe.line < minline then minline = grecipe.line end
                if grecipe.line > maxline then maxline = grecipe.line end
            else
                mincol, minline = grecipe.col, grecipe.line
                maxcol, maxline = grecipe.col, grecipe.line
            end
        end
    end

    local center_col = 0
    local center_line = 0
    if minline then
        center_col = math.floor((mincol + maxcol) / 2)
        center_line = math.floor((minline + maxline) / 2)
    end

    local x, y = gutils.get_position(g, center_col, center_line)

    gutils.teleport(g.player, { x, y })
end

---@param recipes table<any, GRecipe>
---@param gname string?
function gutils.compute_sum(recipes, gname)
    local col, line, count = 0, 0, 0
    for _, recipe in pairs(recipes) do
        if recipe.visible and recipe.col and recipe.name ~= gname then
            col = col + recipe.col
            line = line + recipe.line
            count = count + 1
        end
    end
    return col, line, count
end

---@param container LuaGuiElement
---@param product_name string
---@param button_name string?
---@return LuaGuiElement
---@return string
---@return string
function gutils.create_product_button(container, product_name, button_name)
    ---@cast button_name -nil
    local b
    local type
    local name
    if string.find(product_name, "^item/") then
        name = string.sub(product_name, 6)
        b = container.add { type = "choose-elem-button", elem_type = "item", item = name, name = button_name }
        type = "item"
    else
        name = string.sub(product_name, 7)
        b = container.add { type = "choose-elem-button", elem_type = "fluid", fluid = name, name = button_name }
        type = "fluid"
    end
    b.locked = true
    return b, type, name
end

-- Fire production change
---@param g Graph
function gutils.fire_production_data_change(g)
    tools.fire_user_event(commons.production_data_change_event, { g = g })
end

---@param g Graph
---@return {[string]:GProduct}
function gutils.get_output_products(g)
    ---@type {[string]:GProduct}
    local products = {}
    for _, recipe in pairs(g.selection) do
        if not recipe.is_product then
            for _, product in pairs(recipe.products) do
                local name = product.name
                products[name] = product
            end
        end
    end
    return products
end

local saved_graph_fields = {
    "preferred_machines",
    "preferred_modules",
    "preferred_beacon",
    "preferred_beacon_count",
    "preferred_beacon_modules",
    "iovalues",
    "visibility",
    "color_index",
    "current_layer",
    "visible_layers",
    "show_products"

}

local saved_reciped_fields = {
    "name",
    "production_config", "line",
    "col",
    "layer",
    "mcount"
}

gutils.saved_graph_fields = saved_graph_fields

---@param g Graph
---@return SavingData
function gutils.create_saving_data(g)
    ---@type SavingData
    local saved = {}
    saved.config = {}
    for _, field in pairs(saved_graph_fields) do
        saved.config[field] = g[field]
    end

    saved.selection = {}
    if g.selection then
        for _, grecipe in pairs(g.selection) do
            local saved_recipe = {}
            for _, field in pairs(saved_reciped_fields) do
                saved_recipe[field] = grecipe[field]
            end
            table.insert(saved.selection, saved_recipe)
        end
    end
    saved.colors = {}
    for _, gproduct in pairs(g.products) do
        if gproduct.color then
            saved.colors[gproduct.name] = gproduct.color
        end
    end
    return saved
end

---@param g Graph
---@param products {[string]:any}
---@return {[string]:GRecipe}
function gutils.get_connected_recipes(g, products)
    ---@type {[string]:GProduct}
    local to_scan = {}
    local done_scan = {}
    for product_name, _ in pairs(products) do
        local product = g.products[product_name]
        to_scan[product_name] = product
    end

    ---@type {[string]:GRecipe}
    local connected_recipes = {}
    while (true) do
        local product_name, gproduct = next(to_scan)
        if not product_name then break end
        to_scan[product_name] = nil
        done_scan[product_name] = true
        for _, grecipe in pairs(gproduct.product_of) do
            if g.selection[grecipe.name] then
                connected_recipes[grecipe.name] = grecipe
                for _, ingredient in pairs(grecipe.ingredients) do
                    if not done_scan[ingredient.name] then
                        to_scan[ingredient.name] = ingredient
                    end
                end
            end
        end
        for _, grecipe in pairs(gproduct.ingredient_of) do
            if grecipe.is_void and g.selection[grecipe.name] then
                connected_recipes[grecipe.name] = grecipe
            end
        end
    end
    return connected_recipes
end

---@param g Graph
---@param grecipe GRecipe
---@param col integer
---@param line integer
function gutils.set_colline(g, grecipe, col, line)
    local gcol
    if grecipe.col then
        gcol = g.gcols[grecipe.col]
        if gcol then
            gcol.line_set[grecipe.line] = nil
        end
    end

    gcol = g.gcols[col]
    if not gcol then
        gcol = {
            col = col,
            line_set = {}
        }
        g.gcols[col] = gcol
    end
    grecipe.line = line
    grecipe.col = col
    gcol.line_set[line] = grecipe

    if not gcol.min_line or line < gcol.min_line then
        gcol.min_line = line
    end
    if not gcol.max_line or line > gcol.max_line then
        gcol.max_line = line
    end
end

---@param g Graph
---@param col integer
---@param line integer
---@return GElement?
function gutils.get_element_at_position(g, col, line)
    local gcol = g.gcols[col]
    if not gcol then return nil end
    return gcol.line_set[line]
end

---@param player LuaPlayer
---@param recipe_name string
function gutils.set_cursor_stack(player, recipe_name)
    local g = gutils.get_graph(player)
    local layer
    if g.visibility == commons.visibility_layers then
        layer = g.current_layer
    end
    player.cursor_stack.clear()
    player.cursor_stack.set_stack { name = commons.recipe_symbol_name, count = 1 }
    player.cursor_stack.tags = { recipe_name = recipe_name, layer = layer }
end

---@param player LuaPlayer
function gutils.exit(player) end

---@param player LuaPlayer
---@param recipe_name string?
function gutils.enter(player, recipe_name) end

---@param g Graph
function gutils.clear(g)
    g.selection = {}
    g.iovalues = {}
    g.color_index = 0
    for _, gproduct in pairs(g.products) do
        gproduct.color = nil
    end
    g.product_outputs = nil
    g.product_inputs = nil
    g.production_failed = nil
    g.production_recipes_failed = nil
    g.bound_products = nil
    for _, grecipe in pairs(g.recipes) do
        grecipe.production_config = nil
        grecipe.computed_config = nil
        grecipe.machine = nil
        grecipe.layer = nil
        grecipe.mcount = nil
    end
end

---@param g Graph
function gutils.clean_iovalues(g)
    if not g.selection then return end

    local all_products = {}
    local to_remove = {}
    for _, grecipe in pairs(g.selection) do
        for _, i in pairs(grecipe.ingredients) do
            all_products[i.name] = true
        end
        for _, p in pairs(grecipe.products) do
            all_products[p.name] = true
        end
    end

    for name, _ in pairs(g.iovalues) do
        if not all_products[name] then
            to_remove[name] = true
        end
    end

    for name, _ in pairs(to_remove) do
        g.iovalues[name] = nil
    end
end

local colors = commons.colors
local display_time = 5 * 60
local text_dist = 30

---@param player LuaPlayer
---@param recipe_name string?
---@param move_player boolean?
function gutils.show_machine(player, recipe_name, move_player)
    local g = gutils.get_graph(player)
    if not recipe_name then return end
    local grecipe = g.recipes[recipe_name]
    if not grecipe then return end

    local surface, player_position = gutils.get_real_surface(player)
    if not surface or not player_position then return end
    local show_machine_radius = settings.get_player_settings(player)["factory_graph-scan-radius"].value
    local entities = surface.find_entities_filtered {
        type = { "furnace", "assembling-machine", "rocket-silo" },
        position = player_position, radius = show_machine_radius
    }
    local count = 0
    if #entities > 0 then
        local main_color = colors.main
        local ingredient_color = colors.ingredient
        local product_color = colors.production

        local i_map = {}
        for _, i in pairs(grecipe.ingredients) do
            for r_name, r in pairs(i.product_of) do
                i_map[r_name] = { recipe = r, product = i }
            end
        end

        local p_map = {}
        for _, p in pairs(grecipe.products) do
            for r_name, r in pairs(p.ingredient_of) do
                p_map[r_name] = { recipe = r, product = p }
            end
        end

        i_map[recipe_name] = nil
        p_map[recipe_name] = nil

        local function draw_entity(entity, color)
            local w = entity.tile_width / 2
            local h = entity.tile_height / 2
            rendering.draw_rectangle {
                surface = surface,
                color = color,
                left_top = { entity = entity, offset = { -w, -h } },
                right_bottom = { entity = entity, offset = { w, h } },
                width = 2,
                time_to_live = display_time
            }
        end

        local main_entity
        local ingredient_links = {}
        local product_links = {}
        local player_pos = player_position
        local dist
        for _, entity in pairs(entities) do
            local crecipe = entity.get_recipe() or (entity.type == "furnace" and entity.previous_recipe and entity.previous_recipe.name)
            if crecipe then
                local cname = crecipe.name
                if cname == recipe_name then
                    draw_entity(entity, main_color)
                    local newdist = tools.distance(player_pos, entity.position)
                    if not main_entity or newdist < dist then
                        main_entity = entity
                        dist = newdist
                    end
                    count = count + 1
                elseif i_map[cname] then
                    draw_entity(entity, ingredient_color)
                    local p = i_map[cname]
                    table.insert(ingredient_links, { entity = entity, recipe = p.recipe, product = p.product })
                elseif p_map[cname] then
                    draw_entity(entity, product_color)
                    local p = p_map[cname]
                    table.insert(product_links, { entity = entity, recipe = p.recipe, product = p.product })
                end
            end
        end
        if main_entity then
            local mp = main_entity.position
            local mx = mp.x
            local my = mp.y
            local function draw_link(color, other, product)
                local op = other.position
                local ox = op.x
                local oy = op.y
                rendering.draw_line {
                    color = color,
                    from = mp,
                    to = op,
                    surface = surface,
                    time_to_live = display_time,
                    width = 2,
                    draw_on_ground = false
                }
                local dd = tools.distance(mp, op)
                local textpos
                if dd < text_dist then
                    textpos = { x = (mx + ox) / 2, y = (my + oy) / 2 }
                else
                    local ux = mx + (ox - mx) / dd * text_dist / 2
                    local uy = my + (oy - my) / dd * text_dist / 2
                    textpos = { x = ux, y = uy }
                end

                local radius = 1
                rendering.draw_circle {
                    surface = surface,
                    color = { 0, 0, 0 },
                    filled = true,
                    time_to_live = display_time,
                    radius = radius,
                    target = textpos
                }

                rendering.draw_circle {
                    surface = surface,
                    color = color,
                    filled = false,
                    time_to_live = display_time,
                    radius = radius,
                    target = textpos,
                    width = 2,
                }

                local text = tools.text_sprite(tools.id_to_signal(product.name))
                rendering.draw_text {
                    text = text,
                    surface = surface,
                    target = textpos,
                    color = color,
                    orientation = 0,
                    alignment = "center",
                    vertical_alignment = "middle",
                    time_to_live = display_time,
                    use_rich_text = true,
                    scale = 1.8
                }
            end
            for _, i in pairs(ingredient_links) do
                draw_link(ingredient_color, i.entity, i.product)
            end
            for _, p in pairs(product_links) do
                draw_link(product_color, p.entity, p.product)
            end
            if move_player and main_entity and surface == player.surface then
                if tools.distance(player.position, main_entity.position) > 30 then
                    player.set_controller {
                        type = defines.controllers.remote,
                        position = main_entity.position,
                        surface = player.surface
                    }
                end
            end
        end
    end
    player.print({ np("machine_report"), count })
end

---@param player LuaPlayer
---@return GRecipe?
---@return Graph?
function gutils.get_selected_recipe_in_graph(player)
    local g = gutils.get_graph(player)
    if not g then return nil end

    local entity = player.selected
    if not entity or not entity.valid then return nil end

    if not recipe_entity_names[entity.name] then return nil end

    ---@type GRecipe
    local grecipe = g.entity_map[entity.unit_number]
    if not grecipe then return nil end

    return grecipe, g
end

---@param player LuaPlayer
function gutils.show_machine_from_selection(player)
    ---@type GRecipe
    local grecipe, g = gutils.get_selected_recipe_in_graph(player)
    if not grecipe then return end

    gutils.refresh_machine_list(g, grecipe.name)
    gutils.exit(player)
    gutils.show_machine(player, grecipe.name, true)
end

---@param g Graph
---@param recipe_name string?
function gutils.refresh_machine_list(g, recipe_name)
    ---@type BackgroundCommand
    local command = {
        event_name = commons.refresh_machine_list,
        player = g.player,
        g = g,
        recipe_name = recipe_name,
    }
    tools.background_exec(command)
end

---@param player LuaPlayer
---@return {[string]:boolean}
function gutils.get_scanned_recipes(player)
    local vars = tools.get_vars(player)

    ---@type {[string]:boolean}?
    local scanned_recipes = vars.scanned_recipes
    if scanned_recipes then
        return scanned_recipes
    end

    local surface, player_position = gutils.get_real_surface(player)
    if not surface or not player_position then return {} end
    local show_machine_radius = settings.get_player_settings(player)["factory_graph-scan-radius"].value
    local entities = surface.find_entities_filtered {
        type = { "furnace", "assembling-machine", "rocket-silo" },
        position = player_position, radius = show_machine_radius
    }

    ---@type {[string]:boolean}
    scanned_recipes = {}
    for _, entity in pairs(entities) do
        local crecipe = entity.get_recipe() or (entity.type == "furnace" and entity.previous_recipe and entity.previous_recipe.name)
        if crecipe then
            scanned_recipes[crecipe.name] = true
        end
    end
    vars.scanned_recipes = scanned_recipes
    return scanned_recipes
end

---@param player LuaPlayer
---@return LuaSurface?
---@return MapPosition?
function gutils.get_real_surface(player)
    local vars = tools.get_vars(player)
    local surface = player.surface
    local g = gutils.get_graph(player)
    if g == nil then return nil, nil end
    if surface ~= g.surface then
        return surface, player.position
    else
        ---@type Extern
        local extern = vars.extern
        if extern.surface.valid then
            return extern.surface, extern.position
        end
        if player.physical_surface then
            return player.physical_surface, player.physical_position
        end
        return game.surfaces("nauvis"), { 0, 0 }
    end
end

function gutils.clear_scanned_recipes(data)
    for _, player in pairs(game.players) do
        local vars = tools.get_vars(player)
        vars.scanned_recipes = nil
        local g = gutils.get_graph(player)
        if g then
            gutils.refresh_machine_list(g, nil)
        end
    end
end

tools.register_user_event(commons.clear_scanned_recipes, gutils.clear_scanned_recipes)

---@param player LuaPlayer
---@param refresh boolean?
function gutils.reset_scanned_recipes(player, refresh)
    local vars = tools.get_vars(player)
    vars.scanned_recipes = nil
    if refresh then
        local g = gutils.get_graph(player)
        if g then
            gutils.refresh_machine_list(g, nil)
        end
    end
end

function gutils.post_clear_scanned_recipes()
    ---@type BackgroundCommand
    local command = {
        event_name = commons.clear_scanned_recipes,
        player = nil
    }
    tools.background_exec(command)
end

tools.on_event(defines.events.on_player_changed_position,
    ---@param e EventData.on_player_changed_position
    function(e)
        local player = game.players[e.player_index]
        local surface = gutils.get_real_surface(player)
        if not surface then return end
        if surface ~= player.surface then return end

        local vars = tools.get_vars(player)
        local player_position = player.position

        local position = vars.scanned_position
        if position then
            if math.max(math.abs(position.x - player_position.x), math.abs(position.y - player_position.y)) < 10 then
                return
            end
        end
        vars.scanned_position = player_position
        gutils.reset_scanned_recipes(player, true)
    end
)

---@param player LuaPlayer
---@return LuaInventory?
function gutils.get_player_inventory(player)
    local character = gutils.get_character(player)

    ---@type LuaInventory?
    local inv
    if character then
        return character.get_main_inventory()
    end
    return nil
end

---@param player LuaPlayer
---@return LuaEntity?
function gutils.get_character(player)
    ---@type LuaEntity
    local character = player.character
    if character then return character end

    local vars = tools.get_vars(player)

    ---@type Extern?
    local extern = vars.extern
    if extern and extern.character and extern.character.valid then
        character = extern.character
    end

    return character
end

---@param player LuaPlayer
---@param  item string
---@param  count integer
---@return {[string]:integer}?
---@return {[string]:integer}?
---@return {[string]:integer}?
function gutils.find_missing_ingredients(player, item, count)
    local character = gutils.get_character(player)
    if not character then return nil, nil end
    return tools.find_missing_ingredients(character, { [item] = count })
end

---@param player LuaPlayer
---@param machine_entity LuaEntityPrototype
---@param machine_count integer?
---@return table
function gutils.create_machine_tooltip(player, machine_entity, machine_count)
    local parts = { "" }
    if not machine_count then machine_count = 1 end
    if machine_entity and machine_entity.items_to_place_this then
        local machine_item = machine_entity.items_to_place_this[1]
        if machine_item then
            local missing, used, inv = gutils.find_missing_ingredients(player, machine_item.name, machine_count)

            if not used then
                local machine_recipes =
                    prototypes.get_recipe_filtered { {
                        filter = "has-product-item",
                        elem_filters = { { filter = "name", name = machine_item.name } } } }

                local machine_recipe
                for _, mp in pairs(machine_recipes) do
                    machine_recipe = mp
                    break
                end
                if machine_recipe then
                    local ingredients = machine_recipe.ingredients
                    for _, p in pairs(ingredients) do
                        local amount = p.amount or ((p.amount_max + p.amount_min) / 2)
                        local label = gutils.get_product_name(player, p.type .. "/" .. p.name)
                        local ptext = {
                            np("machine_product_tooltip"),
                            amount, label, "[" .. p.type .. "=" .. p.name .. "]" }
                        table.insert(parts, ptext)
                    end
                end
            else
                inv = inv or {}
                local mcount = "0"
                if inv[machine_item.name] then mcount = tostring(inv[machine_item.name]) end
                table.insert(parts, { np("from_inventory"), mcount })
                for name, count in pairs(missing) do
                    local label = gutils.get_product_name(player, "item/" .. name)
                    local ptext = { np("machine_product_missing_tooltip"), count, label, "[item=" .. name .. "]" }
                    table.insert(parts, ptext)
                end
                for name, count in pairs(used) do
                    local label = gutils.get_product_name(player, "item/" .. name)
                    local ptext = { np("machine_product_tooltip"), count, label, "[item=" .. name .. "]" }
                    table.insert(parts, ptext)
                end
            end
        end
    end
    return parts
end

---@param player LuaPlayer
---@param position MapPosition
function gutils.teleport(player, position)
    local surface = player.surface
    local zoom = player.zoom
    player.set_controller { type = defines.controllers.remote, position = position, surface = surface }
    player.zoom = zoom
end

---@param player LuaPlayer
---@param item string
---@param count integer
---@return integer?
---@return string?
function gutils.craft(player, item, count)
    local recipes = prototypes.get_recipe_filtered { { filter = "has-product-item",
        elem_filters = { { filter = "name", name = item } } } }

    if not count then
        count = 1
    end
    if not player.character then
        return nil
    end
    local crafting_categories = player.character.prototype.crafting_categories
    if #recipes > 0 and crafting_categories then
        for recipe_name, recipe in pairs(recipes) do
            if crafting_categories[recipe.category] then
                local missing = gutils.find_missing_ingredients(player, item, count)
                if missing and table_size(missing) > 0 then
                    for name, count in pairs(missing) do
                        local label = translations.get_item_name(player.index, name)
                        player.create_local_flying_text {
                            text = { np("missing_ingredient"), count, "[item=" .. name .. "]", label },
                            color = { 1, 0, 0 },
                            create_at_cursor = true,
                            speed = 2
                        }
                    end
                else
                    local inv = player.character.get_main_inventory()
                    local inv_count = 0
                    if inv then
                        inv_count = inv.get_item_count(item)
                    end
                    if count < 0 then count = -count end
                    local craft_count = player.begin_crafting { recipe = recipe_name, count = count }
                    player.print { np("craft"), count, "[item=" .. item .. "]", inv_count }
                    return craft_count, recipe_name.name
                end
            end
        end
    end
    return nil
end

return gutils

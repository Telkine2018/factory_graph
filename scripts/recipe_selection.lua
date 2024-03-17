local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local drawing = require("scripts.drawing")
local graph = require("scripts.graph")

local debug = tools.debug
local prefix = commons.prefix

local recipe_selection = {}

local function np(name)
    return prefix .. "-recipe_selection." .. name
end

local recipe_selection_frame_name = np("recipe_selection_frame")
local cb_name = np("cb")

tools.add_panel_name(recipe_selection_frame_name)

local sprite_button_size = 30

---@param player LuaPlayer
---@param g Graph
---@param product GProduct
---@param src GRecipe
function recipe_selection.open(player, g, product, src)
    local player_index = player.index

    g.rs_product = product
    g.rs_recipe = src

    recipe_selection.close(player_index)

    local recipes = {}
    if product.product_of[src.name] then
        for name, i_recipe in pairs(product.ingredient_of) do
            recipes[name] = i_recipe
        end
    end
    if product.ingredient_of[src.name] then
        for name, p_recipe in pairs(product.product_of) do
            recipes[name] = p_recipe
        end
    end
    recipes[src.name] = nil

    local recipe_count = table_size(recipes)
    if recipe_count == 0 then return end

    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = recipe_selection_frame_name
    }

    --frame.style.width = 600
    --frame.style.minimal_height = 300

    local product_name = gutils.get_product_name(player, product.name)

    local titleflow = frame.add { type = "flow" }
    titleflow.add {
        type = "label",
        caption = { np("title"), product_name },
        style = "frame_title",
        ignored_by_interaction = true
    }

    local drag = titleflow.add {
        type = "empty-widget",
        style = "flib_titlebar_drag_handle"
    }

    drag.drag_target = frame
    titleflow.drag_target = frame

    titleflow.add {
        type = "sprite-button",
        name = np("close"),
        tooltip = { np("close-tooltip") },
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = "utility/close_white",
        hovered_sprite = "utility/close_black"
    }

    local flow = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    flow.style.horizontally_stretchable = true

    local scroll = flow.add { type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
    scroll.style.maximal_height = 700

    local recipe_table = scroll.add { type = "table", column_count = 2, draw_horizontal_lines = true, name = "recipe_table" };

    local sorted_list = {}
    for _, grecipe in pairs(recipes) do
        local recipe = game.recipe_prototypes[grecipe.name]
        if recipe then
            table.insert(sorted_list, { grecipe = grecipe, recipe = recipe, localised = translations.get_recipe_name(player_index, grecipe.name) })
        else
            table.insert(sorted_list, { grecipe = grecipe, localised = gutils.get_recipe_name(player, grecipe) })
        end
    end
    if #sorted_list == 0 then return end

    table.sort(sorted_list, function(r1, r2) return r1.localised < r2.localised end)

    local img_arrow = commons.prefix .. "_arrow"

    for _, recipe_element in pairs(sorted_list) do
        local recipe_line = recipe_table.add { type = "flow", direction = "horizontal" }
        local recipe_name = recipe_element.grecipe.name
        recipe_line.tags = { recipe_name = recipe_name }
        local state = g.selection[recipe_name] ~= nil

        local recipe = recipe_element.recipe

        local b = recipe_line.add {
            type = "sprite-button",
            name = np("goto"),
            tooltip = { np("goto-tooltip") },
            mouse_button_filter = { "left" },
            sprite = commons.prefix .. "_arrow",
        }
        b.style.size = 18
        b.style.right_margin = 3

        if recipe then
            local tooltip_builder = {}
            local start = true
            local i_table = {}
            local p_table = {}
            for _, i in pairs(recipe.ingredients) do
                if start then
                    start = false
                else
                    table.insert(tooltip_builder, "\n")
                end
                local name, label
                if i.type == "item" then
                    name = "item/" .. i.name
                    label = translations.get_item_name(player_index, i.name)
                    table.insert(tooltip_builder, "[img=" .. name .. "] " .. tostring(i.amount) .. " x " .. label)
                else
                    name = "fluid/" .. i.name
                    label = translations.get_fluid_name(player_index, i.name)
                    table.insert(tooltip_builder, "[img=" .. name .. "] " .. tostring(i.amount) .. " x " .. label)
                end
                table.insert(i_table, { name = name, tooltip = label })
            end
            table.insert(tooltip_builder, "\n           [img=" .. prefix .. "_down]\n")

            start = true
            for _, p in pairs(recipe.products) do
                if start then
                    start = false
                else
                    table.insert(tooltip_builder, "\n")
                end
                local amount = ""
                if p.amount then
                    amount = tostring(p.amount)
                elseif p.amount_min and p.amount_max then
                    amount = tostring(p.amount_min) .. "-" .. tostring(p.amount_max)
                end
                if p.probability and p.probability < 1 then
                    amount = amount .. "(" .. tostring(p.probability * 100) .. "%)"
                end
                local name
                local label
                if p.type == "item" then
                    name = "item/" .. p.name
                    label = translations.get_item_name(player_index, p.name)
                    table.insert(tooltip_builder, "[img=" .. name .. "] " .. amount .. " x " .. label)
                else
                    name = "fluid/" .. p.name
                    label = translations.get_fluid_name(player_index, p.name)
                    table.insert(tooltip_builder, "[img=" .. name .. "] " .. amount .. " x " .. label)
                end
                table.insert(p_table, { name = name, tooltip = label })
            end
            table.insert(tooltip_builder, "\n[img=" .. prefix .. "_sep]")

            local tooltip = { "", table.concat(tooltip_builder), "\n", { np("time") }, ":", tostring(recipe.energy), "s " }
            recipe_line.add {
                type = "checkbox",
                state = state,
                caption = "[img=recipe/" .. recipe_name .. "] " .. recipe_element.localised,
                name = cb_name,
                tooltip = tooltip
            }
            recipe_line.tooltip = tooltip
            local recipe_table = recipe_table.add { type = "flow", direction = "horizontal", tooltip = tooltip }
            recipe_table.style.left_margin = 10
            for _, def in pairs(i_table) do
                local b = recipe_table.add { type = "sprite-button", sprite = def.name, tooltip = def.tooltip  }
                b.style.size = sprite_button_size
                b.style.margin = 0
                tools.set_name_handler(b, np("product_button"), { product_name = def.name, recipe_name = recipe_name})
            end
            recipe_table.add { type = "sprite", sprite = img_arrow, tooltip = tooltip }
            for _, def in pairs(p_table) do
                local b = recipe_table.add { type = "sprite-button", sprite = def.name, tooltip = def.tooltip }
                b.style.size = sprite_button_size
                b.style.margin = 0
                tools.set_name_handler(b, np("product_button"), { product_name = def.name, recipe_name = recipe_name })
            end
        else
            recipe_line.add {
                type = "checkbox",
                state = state,
                caption = "[img=" .. recipe_name .. "] " .. recipe_element.localised,
                name = cb_name
            }
            recipe_table.add { type = "label", caption = "" }
        end
    end

    if g.rs_location then
        frame.location = g.rs_location
    else
        frame.force_auto_center()
    end
end

tools.on_named_event(np("product_button"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        local e = e.element
        if e.valid then
            local product_name = e.tags.product_name
            local recipe_name = e.tags.recipe_name
            local g = gutils.get_graph(player)
            if g then
                recipe_selection.open(player, g, g.products[product_name], g.recipes[recipe_name])
            end
        end
    end)

---@param player LuaPlayer
---@return {[string]:GRecipe}   @ all selected
---@return {[string]:GRecipe}   @ all invisible
local function set_recipes_to_selection(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    local recipe_table = tools.get_child(frame, "recipe_table")
    local g = gutils.get_graph(player)

    local recipes = {}
    local not_visible = {}
    ---@cast recipe_table -nil
    for _, line in pairs(recipe_table.children) do
        local name = line.tags.recipe_name
        local cb = line[cb_name]
        if name and cb then
            if cb.state then
                local grecipe = g.recipes[name]
                g.selection[name] = grecipe
                recipes[name] = grecipe
                if not grecipe.visible then
                    not_visible[name] = grecipe
                end
            else
                g.selection[name] = nil
            end
        end
    end
    return recipes, not_visible
end

tools.on_named_event(np("cb"), defines.events.on_gui_checked_state_changed,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        local _, not_visible = set_recipes_to_selection(player)
        
        for _, grecipe in pairs(not_visible) do
            grecipe.visible = true
            graph.layout_recipe(g, grecipe)
        end
        graph.draw(g)
        gutils.select_current_recipe(g, g.rs_recipe)
        drawing.update_drawing(player)
    end)

---@param player_index integer
function recipe_selection.close(player_index)
    local player = game.players[player_index]

    local frame = player.gui.screen[recipe_selection_frame_name]
    if frame then
        local g = gutils.get_graph(player)
        g.rs_location = frame.location
        frame.destroy()
    end
end

tools.on_gui_click(np("close"),
    ---@param e EventData.on_gui_click
    function(e)
        recipe_selection.close(e.player_index)
    end)


tools.on_gui_click(np("goto"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local line = e.element.parent
        ---@cast line -nil
        local recipe_name = line.tags.recipe_name

        local g = gutils.get_graph(player)
        local recipe = g.recipes[recipe_name]
        if not recipe.visible  then
            return 
        end
        local position = gutils.get_position(g, recipe)

        if e.control then
            player.teleport(position, g.surface, false)
        else
            gutils.move_view(player, position)
        end
    end)

tools.on_event(defines.events.on_gui_closed,
    function(e)
        local player = game.players[e.player_index]

        if player.selected ~= e.entity then
            recipe_selection.close(e.player_index)
        end
    end)


drawing.open_recipe_selection=recipe_selection.open

return recipe_selection

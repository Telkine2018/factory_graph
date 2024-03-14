local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local debug = tools.debug
local prefix = commons.prefix

local recipe_selection = {}

local function np(name)
    return prefix .. "-recipe_selection." .. name
end

local recipe_selection_frame_name = np("recipe_selection_frame")
tools.add_panel_name(recipe_selection_frame_name)

---@param player LuaPlayer
---@param g Graph
---@param product GProduct
---@param src GRecipe
function recipe_selection.open(player, g, product, src)
    local player_index = player.index

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

    if recipe_count == 1 then
        local _, found_recipe = next(recipes)
        if not g.selection[found_recipe.name] then
            g.selection[found_recipe.name] = found_recipe
            recipe_selection.update_drawing(player)
            return
        end
    end

    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = recipe_selection_frame_name
    }

    --frame.style.width = 600
    --frame.style.minimal_height = 300

    local titleflow = frame.add { type = "flow" }
    local title_label = titleflow.add {
        type = "label",
        caption = { np("title") },
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

    local scroll = flow.add { type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
    scroll.style.maximal_height = 700

    local recipe_table = scroll.add { type = "table", column_count = 1, draw_horizontal_lines = true, name = "recipe_table" };

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
    for _, recipe_element in pairs(sorted_list) do
        local recipe_line = recipe_table.add { type = "flow", direction = "vertical" }
        local recipe_name = recipe_element.grecipe.name
        recipe_line.tags = { recipe_name = recipe_name }
        local state = g.selection[recipe_name] ~= nil

        local recipe = recipe_element.recipe
        if recipe then
            local tooltip_builder = {}
            local start = true
                for _, i in pairs(recipe.ingredients) do
                if start then
                    start = false
                else
                    table.insert(tooltip_builder, "\n")
                end
                if i.type == "item" then
                    table.insert(tooltip_builder,
                        "[img=item/" .. i.name .. "] "
                        .. tostring(i.amount) .. " x "
                        .. translations.get_item_name(player_index, i.name)
                    )
                else
                    table.insert(tooltip_builder,
                        "[img=fluid/" .. i.name .. "] "
                        .. tostring(i.amount) .. " x "
                        .. translations.get_fluid_name(player_index, i.name))
                end
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
                    amount = amount .. "(" .. tostring(p.probability * 100) .. ")"
                end
                if p.type == "item" then
                    table.insert(tooltip_builder,
                        "[img=item/" .. p.name .. "] "
                        .. amount .. " x "
                        .. translations.get_item_name(player_index, p.name))
                else
                    table.insert(tooltip_builder,
                        "[img=fluid/" .. p.name .. "] "
                        .. amount .. " x "
                        .. translations.get_fluid_name(player_index, p.name))
                end
            end
            table.insert(tooltip_builder, "\n[img=" .. prefix .. "_sep]")

            local tooltip = { "", table.concat(tooltip_builder), "\n", { np("time") }, ":", tostring(recipe.energy), "s " }
            recipe_line.add {
                type = "checkbox",
                state = state,
                caption = "[img=recipe/" .. recipe_name .. "] " .. recipe_element.localised,
                name = "cb",
                tooltip = tooltip
            }
        else
            recipe_line.add {
                type = "checkbox",
                state = state,
                caption = "[img=" .. recipe_name .. "] " .. recipe_element.localised,
                name = "cb"
            }
        end
    end

    local button_flow = frame.add { type = "flow", direction = "horizontal" }

    button_flow.add { type = "button", name = np("ok"), caption = { np("ok") } }
    button_flow.add { type = "button", name = np("cancel"), caption = { np("cancel") } }

    frame.force_auto_center()
end

---@param player LuaPlayer
local function set_recipes_to_selection(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    local recipe_table = tools.get_child(frame, "recipe_table")
    local g = gutils.get_graph(player)

    local recipes = {}
    ---@cast recipe_table -nil
    for _, line in pairs(recipe_table.children) do
        local name = line.tags.recipe_name
        if line.cb.state then
            g.selection[name] = g.recipes[name]
        else
            g.selection[name] = nil
        end
    end
    return recipes
end

---@param player_index integer
function recipe_selection.close(player_index)
    local player = game.players[player_index]

    local frame = player.gui.screen[recipe_selection_frame_name]
    if frame then
        frame.destroy()
    end
end

tools.on_gui_click(np("ok"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]

        set_recipes_to_selection(player)
        recipe_selection.close(e.player_index)
        recipe_selection.update_drawing(player)
    end)


tools.on_gui_click(np("close"),
    ---@param e EventData.on_gui_click
    function(e)
        recipe_selection.close(e.player_index)
    end)

tools.on_gui_click(np("cancel"),
    ---@param e EventData.on_gui_click
    function(e)
        recipe_selection.close(e.player_index)
    end)

tools.on_event(defines.events.on_gui_closed,
    function(e)
        local player = game.players[e.player_index]

        if player.selected ~= e.entity then
            recipe_selection.close(e.player_index)
        end
    end)

---@param player LuaPlayer
function recipe_selection.update_drawing(player)
end

return recipe_selection

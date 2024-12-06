local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")

local drawing = require("scripts.drawing")
local graph = require("scripts.graph")
local production = require("scripts.production")

local debug = tools.debug
local prefix = commons.prefix

local recipe_selection = {}

local function np(name)
    return prefix .. "-recipe_selection." .. name
end


local ingredient_button_style = commons.buttons.ingredient
local product_button_style = commons.buttons.product
local recipe_button_style = commons.buttons.recipe

local recipe_selection_frame_name = np("recipe_selection_frame")
local cb_name = np("cb")

tools.add_panel_name(recipe_selection_frame_name)

local sprite_button_size = 30


---@param g Graph
---@param product GProduct?
---@param recipe GRecipe?
---@param only_product boolean?
---@return table<string, GRecipe>?
function load_initial_recipes(g, product, recipe, only_product)
    local recipes = {}

    if product and recipe then
        if product.product_of[recipe.name] then
            for name, i_recipe in pairs(product.ingredient_of) do
                recipes[name] = i_recipe
            end
        end
        if product.ingredient_of[recipe.name] then
            for name, p_recipe in pairs(product.product_of) do
                recipes[name] = p_recipe
            end
        end
        recipes[recipe.name] = nil
        if g.show_only_researched then
            recipes = gutils.filter_enabled_recipe(recipes)
        else
            recipes = gutils.filter_non_product_recipe(recipes)
        end
        local recipe_count = table_size(recipes)
        if recipe_count == 0 then return end
    elseif product and not recipe then
        if not only_product then
            for name, i_recipe in pairs(product.ingredient_of) do
                recipes[name] = i_recipe
            end
        end
        for name, p_recipe in pairs(product.product_of) do
            recipes[name] = p_recipe
        end
        if g.show_only_researched then
            recipes = gutils.filter_enabled_recipe(recipes)
        else
            recipes = gutils.filter_non_product_recipe(recipes)
        end
        local recipe_count = table_size(recipes)
        if recipe_count == 0 then return end
    elseif recipe then
        recipes = { recipe }
    end
    return recipes
end

---@param player LuaPlayer
---@param recipe_name string?
---@param product_name string?
local function push_history_with_names(player, recipe_name, product_name)
    if not recipe_name and not product_name then
        return
    end
    local vars = tools.get_vars(player)
    local history = vars.recipe_history
    if not history then
        history = {}
        vars.recipe_history = history
        vars.recipe_history_index = 0
    end

    local index = vars.recipe_history_index
    if index > 0 then
        local top = history[index]
        if top.recipe_name == recipe_name and top.product_name == product_name then
            return
        end
    end

    --[[
        history: [h1 h2]
        index: 1
    ]]
    while #history > index do
        table.remove(history, index + 1)
    end
    while #history > 20 do
        table.remove(history, 1)
        index = index - 1
    end

    table.insert(history, { product_name = product_name, recipe_name = recipe_name })
    index = index + 1
    vars.recipe_history_index = index
end

---@param player LuaPlayer
---@param gproduct GProduct?
---@param grecipe GRecipe?
local function push_history(player, gproduct, grecipe)
    local recipe_name = grecipe and grecipe.name
    local product_name = gproduct and gproduct.name

    push_history_with_names(player, recipe_name, product_name)
end

---@param player LuaPlayer
local function backward_history(player)
    local vars = tools.get_vars(player)
    local history = vars.recipe_history
    if not history then
        return
    end

    local index = vars.recipe_history_index
    if index < 2 then return end

    index = index - 1
    local top = history[index]
    vars.recipe_history_index = index
    local g = gutils.get_graph(player)
    local gproduct = top.product_name and g.products[top.product_name]
    local grecipe = top.recipe_name and g.recipes[top.recipe_name]
    recipe_selection.open(g, gproduct, grecipe, false, true)
end

---@param player LuaPlayer
local function clear_history(player)
    local vars = tools.get_vars(player)
    local history = vars.recipe_history
    if not history then
        return
    end
    local vars = tools.get_vars(player)
    local history = {}
    vars.recipe_history = history
    vars.recipe_history_index = 0
end

---@param player LuaPlayer
local function forward_history(player)
    local vars = tools.get_vars(player)
    local history = vars.recipe_history
    if not history then
        return
    end

    local index = vars.recipe_history_index
    if index >= #history then return end

    index = index + 1
    local top = history[index]
    vars.recipe_history_index = index
    local g = gutils.get_graph(player)
    local gproduct = top.product_name and g.products[top.product_name]
    local grecipe = top.recipe_name and g.recipes[top.recipe_name]
    recipe_selection.open(g, gproduct, grecipe)
end


---@param g Graph
---@param product GProduct?
---@param recipe GRecipe?
---@param only_product boolean?
---@param nohistory boolean?
function recipe_selection.open(g, product, recipe, only_product, nohistory)
    local player = g.player
    local player_index = player.index

    if not nohistory then
        push_history(player, product, recipe)
    end
    g.rs_product = product
    g.rs_recipe = recipe

    recipe_selection.close(player_index)

    local recipes = load_initial_recipes(g, product, recipe, only_product)

    local product_title
    if (product) then
        product_title = gutils.get_product_name(player, product.name)
    else
        product_title = { np("search-title") }
    end

    ---@type Params.create_standard_panel
    local params                               = {
        panel_name           = recipe_selection_frame_name,
        title                = { np("title"), product_title },
        create_inner_frame   = true,
        close_button_name    = np("close"),
        close_button_tooltip = { np("close-tooltip") },
        is_draggable         = true,
        title_menu_func      = function(titleflow)
            local b = titleflow.add {
                type = "sprite-button",
                name = "backward",
                style = "frame_action_button",
                mouse_button_filter = { "left" },
                sprite = prefix .. "_backward-white",
                hovered_sprite = prefix .. "_backward-black"
            }
            tools.set_name_handler(b, np("backward"))
            local b = titleflow.add {
                type = "sprite-button",
                name = "forward",
                style = "frame_action_button",
                mouse_button_filter = { "left" },
                sprite = prefix .. "_forward-white",
                hovered_sprite = prefix .. "_forward-black"
            }
            tools.set_name_handler(b, np("forward"))
        end
    }
    local frame, inner_frame                   = tools.create_standard_panel(player, params)

    frame.style.minimal_width                  = 400
    inner_frame.style.horizontally_stretchable = true

    local flow1                                = inner_frame.add { type = "flow", direction = "horizontal" }

    local label                                = flow1.add { type = "label", caption = { np("choose_recipe") } }
    label.style.top_padding                    = 7
    local b                                    = flow1.add { type = "choose-elem-button", elem_type = "recipe", name = "choose_recipe" }
    tools.set_name_handler(b, np("choose_recipe"))

    local signal
    if (product) then
        signal = tools.sprite_to_signal(product.name)
    end
    label = flow1.add { type = "label", caption = { np("choose_item") } }
    label.style.top_padding = 7
    b = flow1.add { type = "choose-elem-button", elem_type = "item", name = "choose_item" }
    label.style.left_margin = 10
    flow1.style.bottom_margin = 10
    tools.set_name_handler(b, np("choose_item"))
    if signal and signal.type == "item" then
        b.elem_value = signal.name
    end

    label = flow1.add { type = "label", caption = { np("choose_fluid") } }
    label.style.top_padding = 7
    b = flow1.add { type = "choose-elem-button", elem_type = "fluid", name = "choose_fluid" }
    label.style.left_margin = 10
    flow1.style.bottom_margin = 10
    tools.set_name_handler(b, np("choose_fluid"))
    if signal and signal.type == "fluid" then
        b.elem_value = signal.name
    end

    local search_text_flow = inner_frame.add { type = "flow", direction = "horizontal" }
    local search_text = search_text_flow.add { type = "textfield", name = np("search_field"), clear_and_focus_on_right_click = true }
    search_text_flow.add { type = "button", caption = { np("search_button") }, name = np("search_button") }
    search_text_flow.style.bottom_margin = 10
    search_text.style.width = 100

    local action_list = {}
    local tooltip_list = { "" }
    for i = 1, 5 do
        table.insert(action_list, { np("action-" .. i) })
        table.insert(tooltip_list, { np("action-" .. i .. "-tooltip") })
    end
    local selector = search_text_flow.add { type = "drop-down", items = action_list, tooltip = tooltip_list, selected_index = 1, name = np("action") }
    tools.set_name_handler(selector, np("action_in_list"))

    b = search_text_flow.add { type = "button", tooltip = { np("select-all-tooltip") }, caption = { np("select-all") }, name = np("select-all") }

    local scroll = inner_frame.add { type = "scroll-pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
    scroll.style.height = 400
    scroll.style.minimal_width = 500
    scroll.style.horizontally_stretchable = true

    local recipe_table = scroll.add { type = "table", column_count = 2, draw_horizontal_lines = true, name = "recipe_table" };
    recipe_table.style.horizontally_stretchable = true

    local remaining_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    local remaining_pane = remaining_frame.add { type = "table", column_count = 14, name = "remaining_pane" }
    remaining_pane.style.horizontally_stretchable = true
    remaining_pane.style.minimal_height = 30
    recipe_selection.display_remaining(g, remaining_pane)

    if recipes and table_size(recipes) > 0 then
        recipe_selection.display_recipes(player, recipes, recipe_table)
    end

    if g.rs_location then
        frame.location = g.rs_location
    else
        frame.force_auto_center()
    end
end

local function do_search_text(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return end
    local textfield = tools.get_child(frame, np("search_field"))
    if not textfield then return end

    local g = gutils.get_graph(player)
    local dic = translations.get_all(player.index, "recipe_name")

    ---@type table<string, GRecipe>
    local recipes = {}
    local text = string.lower(textfield.text)
    if #text == 0 then return end

    for name, recipe in pairs(g.recipes) do
        local translation = dic[name]
        if not translation then
            translation = gutils.get_product_name(player, name)
        end
        if translation then
            translation = string.lower(translation)
            if string.find(translation, text) then
                recipes[name] = recipe
            end
        end
    end
    if g.show_only_researched then
        recipes = gutils.filter_enabled_recipe(recipes)
    else
        recipes = gutils.filter_non_product_recipe(recipes)
    end

    recipe_selection.show_recipes(player, recipes)
end

---@param player LuaPlayer
---@param recipes GRecipe[]
function recipe_selection.show_recipes(player, recipes)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return end

    local recipe_table = tools.get_child(frame, "recipe_table")
    if not recipe_table then return end

    recipe_table.clear()
    recipe_selection.display_recipes(player, recipes, recipe_table)
end

tools.on_named_event(np("search_button"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        do_search_text(player)
    end
)

tools.on_event(defines.events.on_gui_confirmed, function(e)
    local player = game.players[e.player_index]
    do_search_text(player)
end)

tools.on_named_event(np("product_button"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        local e = e.element
        if e.valid then
            local product_name = e.tags.product_name
            local recipe_name = e.tags.recipe_name
            local g = gutils.get_graph(player)
            if g then
                recipe_selection.open(g, g.products[product_name], g.recipes[recipe_name])
            end
        end
    end)

---@param player LuaPlayer
---@return {[string]:GRecipe}   @ all selected
---@return {[string]:GRecipe}   @ all invisible
local function set_recipes_to_selection(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return {}, {} end
    local recipe_table = tools.get_child(frame, "recipe_table")
    local g = gutils.get_graph(player)

    local recipes = {}
    local not_visible = {}
    ---@cast recipe_table -nil
    for _, line in pairs(recipe_table.children) do
        local name = line.tags.recipe_name --[[@as string]]
        local cb = line[cb_name]
        if name and cb then
            if cb.state then
                local grecipe = g.recipes[name]
                if grecipe then
                    g.selection[name] = grecipe
                    recipes[name] = grecipe
                    if not grecipe.visible then
                        not_visible[name] = grecipe
                    end
                    if g.visibility == commons.visibility_layers then
                        grecipe.layer = g.current_layer
                    end
                end
            else
                g.selection[name] = nil
            end
        end
    end
    return recipes, not_visible
end

tools.on_named_event(cb_name, defines.events.on_gui_checked_state_changed,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        local _, not_visible = set_recipes_to_selection(player)
        for _, grecipe in pairs(not_visible) do
            grecipe.visible = true
            graph.insert_recipe(g, grecipe)
        end
        graph.create_recipe_objects(g)
        if g.rs_recipe and g.rs_recipe.visible then
            gutils.select_current_recipe(g, g.rs_recipe)
        end
        local recipe_name
        if e.element.state then
            recipe_name = e.element.tags.recipe_name --[[@as string]]
        end
        graph.deferred_update(player, {
            selection_changed = true,
            do_layout = g.layout_on_selection,
            center_on_recipe = recipe_name,
            draw_target = true,
            no_recipe_selection_update = true
        })
    end)

---@param player_index integer|uint32
function recipe_selection.close(player_index)
    local player = game.players[player_index]

    local frame = player.gui.screen[recipe_selection_frame_name]
    if frame then
        local g = gutils.get_graph(player)
        g.rs_location = frame.location
        frame.destroy()
    end
end

---@param g Graph
---@param remaining_pane LuaGuiElement
function recipe_selection.display_remaining(g, remaining_pane)
    remaining_pane.clear()
    local inputs = gutils.get_product_flow(g, g.selection)
    for _, gproduct in pairs(inputs) do
        if not gproduct.is_root then
            local b = gutils.create_product_button(remaining_pane, gproduct.name)
            b.style.size = sprite_button_size
            tools.set_name_handler(b, np("remaining"), { product_name = gproduct.name })
        end
    end
end

---@param player LuaPlayer
---@param recipes table<string, GRecipe>
---@param recipe_table LuaGuiElement
function recipe_selection.display_recipes(player, recipes, recipe_table)
    local player_index = player.index
    ---@cast player_index integer
    local g = gutils.get_graph(player)

    ---@type {grecipe:GRecipe, recipe:LuaRecipePrototype?, localized:string}[]
    local sorted_list = {}
    for _, grecipe in pairs(recipes) do
        local recipe = prototypes.recipe[grecipe.name]
        if (not grecipe.hidden) or g.show_hidden then
            if recipe then
                table.insert(sorted_list, { grecipe = grecipe, recipe = recipe, localised = translations.get_recipe_name(player_index, grecipe.name) })
            else
                table.insert(sorted_list, { grecipe = grecipe, localised = gutils.get_recipe_name(player, grecipe) })
            end
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

        local grecipe = recipe_element.recipe

        local b = recipe_line.add {
            type = "sprite-button",
            name = np("goto"),
            tooltip = { np("goto-tooltip") },
            mouse_button_filter = { "left" },
            sprite = commons.prefix .. "_arrow",
        }
        b.style.size = 18
        b.style.right_margin = 3
        b.style.top_margin = 6

        if grecipe then
            local tooltip_builder = {}
            local start = true
            local i_table = {}
            local p_table = {}
            local machine = recipe_element.grecipe.machine
            if machine and not machine.count then machine = nil end

            if machine and machine.machine then
                local machine_label = translations.get_recipe_name(player_index, machine.machine.name)
                if machine.count > 0 then
                    table.insert(tooltip_builder, "[font=heading-2][color=#42ff4b]")
                    table.insert(tooltip_builder, tools.fround(machine.count) .. " x " .. (machine_label or machine.name))
                    table.insert(tooltip_builder, "[/color][/font]\n");
                else
                    table.insert(tooltip_builder, "[font=heading-2][color=red]")
                    table.insert(tooltip_builder, machine_label)
                    table.insert(tooltip_builder, "[/color][/font]\n");
                end
            end

            if machine and machine.count < 0 then
                table.insert(tooltip_builder, "[color=red]")
            else
                table.insert(tooltip_builder, "[color=cyan]")
            end

            for _, i in pairs(grecipe.ingredients) do
                if start then
                    start = false
                else
                    table.insert(tooltip_builder, "\n")
                end
                local name, label
                if i.type == "item" then
                    name = "item/" .. i.name
                    label = translations.get_item_name(player_index, i.name)
                else
                    name = "fluid/" .. i.name
                    label = translations.get_fluid_name(player_index, i.name)
                end
                local amount
                if machine then
                    amount = tools.fround(production.get_ingredient_amount(machine, i) * machine.count)
                else
                    amount = i.amount
                end
                table.insert(tooltip_builder, "[img=" .. name .. "] " .. tools.fround(amount) .. " x " .. label)
                table.insert(i_table, { name = name, tooltip = label })
            end
            table.insert(tooltip_builder, "\n           [img=" .. prefix .. "_down]\n")

            if not machine or machine.count >= 0 then
                table.insert(tooltip_builder, "[/color][color=orange]")
            end

            start = true
            for _, p in pairs(grecipe.products) do
                local name
                local label
                if p.type == "item" then
                    name = "item/" .. p.name
                    label = translations.get_item_name(player_index, p.name)
                else
                    name = "fluid/" .. p.name
                    label = translations.get_fluid_name(player_index, p.name)
                end

                if start then
                    start = false
                else
                    table.insert(tooltip_builder, "\n")
                end
                local amount = ""
                if machine then
                    amount = tostring(tools.fround(production.get_product_amount(machine, p) * machine.count))
                else
                    if p.amount then
                        amount = tostring(p.amount)
                    elseif p.amount_min and p.amount_max then
                        amount = tostring(p.amount_min) .. "-" .. tostring(p.amount_max)
                    end
                    if p.probability and p.probability < 1 then
                        amount = amount .. "(" .. tostring(tools.fround(p.probability * 100)) .. "%)"
                    end
                end
                table.insert(tooltip_builder, "[img=" .. name .. "] " .. amount .. " x " .. label)
                table.insert(p_table, { name = name, tooltip = label })
            end
            table.insert(tooltip_builder, "[/color]")
            table.insert(tooltip_builder, "\n[img=" .. prefix .. "_sep]")

            local tooltip = { "", table.concat(tooltip_builder), "\n", { np("time") }, ":", tostring(grecipe.energy), "s " }

            local b_recipe = recipe_line.add { type = "choose-elem-button", elem_type = "recipe", recipe = recipe_name }
            b_recipe.style = recipe_button_style
            b_recipe.locked = true
            b_recipe.style.size = 28
            tools.set_name_handler(b_recipe, np("recipe"), { recipe_name = recipe_name })

            local cb = recipe_line.add {
                type = "checkbox",
                state = state,
                name = cb_name,
                tooltip = tooltip,
                caption = recipe_element.grecipe.enabled and recipe_element.localised
                    or ("[color=orange]" .. recipe_element.localised .. "[/color]"),
                tags = { recipe_name = recipe_name }
            }
            cb.style.top_margin = 6
            recipe_line.tooltip = tooltip

            local recipe_line = recipe_table.add { type = "flow", direction = "horizontal", tooltip = tooltip }
            recipe_line.style.left_margin = 10
            for _, def in pairs(i_table) do
                local b = gutils.create_product_button(recipe_line, def.name)
                b.style = ingredient_button_style
                b.style.size = sprite_button_size
                b.style.margin = 0
                tools.set_name_handler(b, np("product_button"), { product_name = def.name, recipe_name = recipe_name })
            end
            local arrow = recipe_line.add { type = "sprite", sprite = img_arrow, tooltip = tooltip }
            arrow.style.top_margin = 6
            local product_set = {}
            for _, def in pairs(p_table) do
                if not product_set[def.name] then
                    product_set[def.name] = true
                    local b = gutils.create_product_button(recipe_line, def.name)
                    b.style = product_button_style
                    b.style.size = sprite_button_size
                    b.style.margin = 0
                    tools.set_name_handler(b, np("product_button"), { product_name = def.name, recipe_name = recipe_name })
                end
            end
            recipe_line.style.horizontally_stretchable = true
        else
            local b = gutils.create_product_button(recipe_line, recipe_name)
            b.style.size = sprite_button_size

            recipe_line.add {
                type = "checkbox",
                state = state,
                caption = recipe_element.localised,
                name = cb_name
            }
            recipe_table.add { type = "label", caption = "" }
        end
    end
end

---@param player LuaPlayer
function recipe_selection.update_recipes(player)
    local g = gutils.get_graph(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return end

    local recipe_table = tools.get_child(frame, "recipe_table")
    if not recipe_table then return end

    local recipes = {}
    for _, line in pairs(recipe_table.children) do
        local recipe_name = line.tags.recipe_name --[[@as string]]
        local grecipe = g.recipes[recipe_name]
        if grecipe then
            recipes[recipe_name] = grecipe
        end
    end
    recipe_table.clear()
    recipe_selection.display_recipes(player, recipes, recipe_table)
end

tools.on_gui_click(np("close"),
    ---@param e EventData.on_gui_click
    function(e)
        recipe_selection.close(e.player_index --[[@as integer]])
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
        if not recipe.visible then
            return
        end
        local position = gutils.get_recipe_position(g, recipe)

        drawing.draw_target(g, recipe)

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
            recipe_selection.close(e.player_index --[[@as integer]])
        end
    end)

tools.on_named_event(np("choose_recipe"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if not e.element.valid then return end

        e.element.parent.choose_item.elem_value = nil
        e.element.parent.choose_fluid.elem_value = nil

        local name = e.element.elem_value
        ---@cast name string
        if not name then
            recipe_selection.show_recipes(player, {})
            return
        end
        local g = gutils.get_graph(player)
        local grecipe = g.recipes[name]
        recipe_selection.show_recipes(player, { grecipe })
        gutils.set_cursor_stack(player, name)
        recipe_selection.close(player.index)
    end)

---@param player LuaPlayer
---@param name string
function recipe_selection.process_query(player, name)
    local g = gutils.get_graph(player)

    local frame = player.gui.screen[recipe_selection_frame_name]
    local faction = tools.get_child(frame, np("action"))
    local action = faction and faction.selected_index or 1
    local recipes = {}

    local gproduct = g.products[name]
    if gproduct then
        if action == 1 then
            for _, grecipe in pairs(gproduct.ingredient_of) do
                recipes[grecipe.name] = grecipe
            end
            for _, grecipe in pairs(gproduct.product_of) do
                recipes[grecipe.name] = grecipe
            end
        elseif action == 2 then
            local kproducts = gutils.get_output_products(g)
            local uproducts = { [name] = gproduct }
            while (true) do
                local _, product = next(uproducts)
                if not product then break end

                local frecipe
                if product.root_recipe then
                    frecipe = product.root_recipe
                else
                    _, frecipe = next(product.product_of)
                end

                uproducts[product.name] = nil
                kproducts[product.name] = product

                if frecipe then
                    recipes[frecipe.name] = frecipe
                    for _, p in pairs(frecipe.products) do
                        kproducts[p.name] = p
                    end
                    for _, i in pairs(frecipe.ingredients) do
                        if not kproducts[i.name] then
                            uproducts[i.name] = i
                        end
                    end
                end
            end
        elseif action == 3 then
            recipes = gproduct.ingredient_of
        elseif action == 4 then
            recipes = gproduct.product_of
        elseif action == 5 then
            for _, grecipe in pairs(gproduct.ingredient_of) do
                if g.selection[grecipe.name] then
                    recipes[grecipe.name] = grecipe
                end
            end
            for _, grecipe in pairs(gproduct.product_of) do
                if g.selection[grecipe.name] then
                    recipes[grecipe.name] = grecipe
                end
            end
        end
    end
    if g.show_only_researched then
        recipes = gutils.filter_enabled_recipe(recipes)
    else
        recipes = gutils.filter_non_product_recipe(recipes)
    end
    recipe_selection.show_recipes(player, recipes)
end

tools.on_named_event(np("choose_item"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if not e.element.valid then return end

        e.element.parent.choose_recipe.elem_value = nil
        e.element.parent.choose_fluid.elem_value = nil

        local name = e.element.elem_value
        ---@cast name string
        if not name then
            recipe_selection.show_recipes(player, {})
            return
        end

        name = "item/" .. name
        push_history_with_names(player, nil, name)
        recipe_selection.process_query(player, name)
    end)

tools.on_named_event(np("choose_fluid"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if not e.element.valid then return end

        e.element.parent.choose_recipe.elem_value = nil
        e.element.parent.choose_item.elem_value = nil

        local name = e.element.elem_value
        ---@cast name string
        if not name then
            recipe_selection.show_recipes(player, {})
            return
        end

        name = "fluid/" .. name
        push_history_with_names(player, nil, name)
        recipe_selection.process_query(player, name)
    end)

tools.on_gui_click(np("select-all"),
    ---@param e EventData.on_gui_click
    function(e)
        if not e.element.valid then return end
        local player = game.players[e.player_index]
        local frame = player.gui.screen[recipe_selection_frame_name]
        if not frame then return end
        local recipe_table = tools.get_child(frame, "recipe_table")
        local g = gutils.get_graph(player)

        ---@cast recipe_table -nil
        for _, line in pairs(recipe_table.children) do
            local name = line.tags.recipe_name --[[@as string]]
            local cb = line[cb_name]
            if name and cb then
                local grecipe = g.recipes[name]
                g.selection[name] = grecipe
                cb.state = true
                if g.visibility == commons.visibility_layers then
                    grecipe.layer = g.current_layer
                end
            end
        end
        graph.deferred_update(player, { do_layout = true, center_on_graph = true, no_recipe_selection_update = true })
    end)


tools.on_named_event(np("action_in_list"), defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        if not e.element.valid then return end

        local player = game.players[e.player_index]
        local frame = player.gui.screen[recipe_selection_frame_name]
        if not frame then return end

        local choose_item = tools.get_child(frame, "choose_item")
        local choose_fluid = tools.get_child(frame, "choose_fluid")
        local name
        if not choose_item or not choose_fluid then return end
        local item = choose_item.elem_value
        local fluid = choose_fluid.elem_value
        if item then
            name = "item/" .. item
        elseif fluid then
            name = "fluid/" .. fluid
        else
            return
        end
        recipe_selection.process_query(player, name)
    end)

tools.on_named_event(np("recipe"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        ---@type LuaPlayer
        local player = game.players[e.player_index]
        local recipe_name = e.element.tags.recipe_name --[[@as string]]

        gutils.set_cursor_stack(player, recipe_name)
        recipe_selection.close(player.index)
    end)

tools.on_named_event(np("backward"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if not (e.button ~= defines.mouse_button_type.left or e.control or e.alt or e.shift) then
            backward_history(game.players[e.player_index])
        elseif not (e.button ~= defines.mouse_button_type.left or not e.control or e.alt or e.shift) then
            clear_history(game.players[e.player_index])
        end
    end)

tools.on_named_event(np("forward"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if not (e.button ~= defines.mouse_button_type.left or e.control or e.alt or e.shift) then
            forward_history(game.players[e.player_index])
        end
    end)

tools.on_named_event(np("remaining"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        local product_name = e.element.tags.product_name --[[@as string]]
        if not product_name then return end
        local gproduct = g.products[product_name]
        if not gproduct then return end
        recipe_selection.open(g, gproduct, nil, true)
    end)


tools.register_user_event(commons.selection_change_event, function(data)
    ---@type Graph
    local g = data.g
    local player = g.player

    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return end

    local remaining_pane = tools.get_child(frame, "remaining_pane")
    if not remaining_pane then return end

    recipe_selection.display_remaining(g, remaining_pane)
end)

tools.register_user_event(commons.open_recipe_selection, function(data)
    local g = data.g
    recipe_selection.open(g, data.product, data.recipe, data.only_product)
end)


drawing.open_recipe_selection = recipe_selection.open
graph.update_recipe_selection = recipe_selection.update_recipes

return recipe_selection

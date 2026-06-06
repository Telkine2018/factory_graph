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
local label_style_name = prefix .. "_count_label_bottom"

local recipe_selection_frame_name = np("recipe_selection_frame")
local cb_name = np("cb")

-- tools.add_panel_name(recipe_selection_frame_name)

local general_button_size = commons.general_button_size

local action_used_in_recipe = commons.action_used_in_recipe
local action_path_to_build = commons.action_path_to_build
local action_consumer = commons.action_consumer
local action_producer = commons.action_producer
local action_in_selection = commons.action_in_selection

---@param options RecipeSelectionOptions
local function load_base(options)
    local product = options.product
    if product and product.derived_from then product = product.derived_from end
    options.product = product

    local recipe = options.recipe
    if recipe and recipe.derived_from then recipe = recipe.derived_from end
    options.recipe = recipe
end

---@param g Graph
---@param options RecipeSelectionOptions
---@return table<string, GRecipe>?
function load_initial_recipes(g, options)
    local recipes = {}

    load_base(options)
    local product = options.product
    local recipe = options.recipe

    if product and options.related_to_product then
        for name, i_recipe in pairs(product.ingredient_of) do
            if i_recipe.visible and not i_recipe.is_product then
                recipes[name] = i_recipe
            end
        end
        for name, p_recipe in pairs(product.product_of) do
            if p_recipe.visible and not p_recipe.is_product then
                recipes[name] = p_recipe
            end
        end
    elseif product and recipe then
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
        if not options.only_product then
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
    recipes = gutils.filter_candidate_recipes(recipes, g)
    return recipes
end

---@param player LuaPlayer
---@param recipe_name string?
---@param product_name string?
---@param action integer?
local function push_history_with_names(player, recipe_name, product_name, action)
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
        if top.recipe_name == recipe_name and top.product_name == product_name and top.action == action then
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

    table.insert(history, { product_name = product_name, recipe_name = recipe_name, action = action })
    index = index + 1
    vars.recipe_history_index = index
end

---@param player LuaPlayer
---@param gproduct GProduct?
---@param grecipe GRecipe?
---@param action integer?
local function push_history(player, gproduct, grecipe, action)
    local recipe_name = grecipe and grecipe.name
    local product_name = gproduct and gproduct.name

    push_history_with_names(player, recipe_name, product_name, action)
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
    local action = top.action
    recipe_selection.open(g, { product = gproduct, recipe = grecipe, nohistory = true, action = action })
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
    local action = top.action
    recipe_selection.open(g, { product = gproduct, recipe = grecipe, action = action })
end

---@class RecipeSelectionOptions
---@field g Graph?
---@field product GProduct?
---@field recipe GRecipe?
---@field only_product boolean?
---@field nohistory boolean?
---@field related_to_product boolean?
---@field action integer
---@field if_opened boolean?

---@param g Graph
---@param options RecipeSelectionOptions
function recipe_selection.open(g, options)
    local player = g.player
    local player_index = player.index

    if options.if_opened then
        if not player.gui.screen[recipe_selection_frame_name] then return end
    end

    if not options.nohistory then
        push_history(player, options.product, options.recipe, options.action)
    end
    g.rs_product = options.product
    g.rs_recipe = options.recipe

    recipe_selection.close(player_index)

    local product = options.product
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

    frame.style.minimal_width                  = 450
    inner_frame.style.horizontally_stretchable = true

    local flow1                                = inner_frame.add { type = "flow", direction = "horizontal" }

    local label                                = flow1.add { type = "label", caption = { np("choose_recipe") } }
    label.style.top_padding                    = 7
    local b                                    = flow1.add { type = "choose-elem-button", elem_type = "recipe", name = "choose_recipe" }
    local filters                              = {}
    if g.show_only_researched then
        -- table.insert(filters, { filter = 'enabled', mode = 'and' })
    end
    if not g.show_hidden then
        table.insert(filters, { filter = 'hidden', invert = true, mode = 'and' })
    end
    if #filters > 0 then b.elem_filters = filters end

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

    local only_researched = flow1.add {
        type = "checkbox",
        name = "only_researched",
        caption = { np("only_researched") },
        state = not not g.show_only_researched }
    only_researched.style.left_margin = 10
    only_researched.style.top_margin = 10
    tools.set_name_handler(only_researched, np("only_researched"))

    local search_text_flow = inner_frame.add { type = "flow", direction = "horizontal" }
    local search_text = search_text_flow.add { type = "textfield", name = np("search_field"), clear_and_focus_on_right_click = true }
    search_text_flow.add { type = "button", caption = { np("search_button") }, name = np("search_button") }
    search_text_flow.style.bottom_margin = 10
    search_text.style.width = 100

    local action = options.action
    load_base(options)
    if not action and options.recipe then
        if options.product then
            if options.product.product_of[options.recipe.name] then
                action = action_consumer
            end
            if options.product.ingredient_of[options.recipe.name] then
                if action then
                    action = action_used_in_recipe
                else
                    action = action_producer
                end
            end
        end
    end
    action = action or action_used_in_recipe

    local action_list = {}
    local tooltip_list = { "" }
    for i = 1, 5 do
        table.insert(action_list, { np("action-" .. i) })
        table.insert(tooltip_list, { np("action-" .. i .. "-tooltip") })
    end
    local selector = search_text_flow.add { type = "drop-down", items = action_list, tooltip = tooltip_list, selected_index = action, name = np("action") }
    tools.set_name_handler(selector, np("action_in_list"))

    b = search_text_flow.add { type = "button", tooltip = { np("select-all-tooltip") }, caption = { np("select-all") }, name = np("select-all") }

    local scroll = inner_frame.add { type = "scroll-pane", horizontal_scroll_policy = "always", vertical_scroll_policy = "always" }
    scroll.style.minimal_height = 200
    scroll.style.maximal_height = 600
    scroll.style.minimal_width = 500
    scroll.style.maximal_width = 900

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

    if not options.action then
        local recipes = load_initial_recipes(g, options)
        if recipes and table_size(recipes) > 0 then
            recipe_selection.display_recipes(player, recipes, recipe_table)
        end
    else
        recipe_selection.refresh(player)
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

    recipes = gutils.filter_candidate_recipes(recipes, g)
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
        local element = e.element
        if element.valid then
            local product_name = element.tags.product_name
            local recipe_name = element.tags.recipe_name
            local g = gutils.get_graph(player)
            if g then
                if not (e.button ~= defines.mouse_button_type.left or e.shift or e.control or e.alt) then
                    recipe_selection.open(g, { product = g.products[product_name], recipe = g.recipes[recipe_name] })
                elseif not (e.button ~= defines.mouse_button_type.right or e.shift or e.control or e.alt) then
                    recipe_selection.open(g, { product = g.products[product_name], action = action_used_in_recipe })
                elseif not (e.button ~= defines.mouse_button_type.left or e.shift or not e.control or e.alt) then
                    local signal = tools.id_to_signal(product_name)
                    if signal and signal.type == "item" then
                        gutils.craft(player, signal.name, 1)
                    end
                end
            end
        end
    end)

---@param player LuaPlayer
---@param selected_recipe_name string?
---@return {[string]:GRecipe}   @ all selected
---@return {[string]:GRecipe}   @ all invisible
local function set_recipes_to_selection(player, selected_recipe_name)
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
            if selected_recipe_name and name == selected_recipe_name then
                cb.state = true
            end
            local grecipe = g.recipes[name]
            if grecipe then
                if cb.state then
                    if grecipe.use_temperature then
                        recipes[name] = nil
                        grecipe = gutils.get_derived_recipe(g, grecipe, grecipe.i_temperatures, grecipe.p_temperatures)
                        name = grecipe.name
                    end
                    g.selection[name] = grecipe
                    recipes[name] = grecipe
                    if not grecipe.visible then
                        not_visible[name] = grecipe
                    end
                    if g.visibility == commons.visibility_layers then
                        grecipe.layer = g.current_layer
                    end
                else
                    if grecipe.use_temperature then
                        name = gutils.get_derived_name(grecipe.name, grecipe.i_temperatures, grecipe.p_temperatures)
                        grecipe = g.recipes[name]
                    end
                    if grecipe then
                        g.selection[name] = nil
                        grecipe.visible = nil
                    end
                end
            end
        end
    end
    return recipes, not_visible
end

---@param player LuaPlayer
---@param recipe_name  string?
---@param do_add boolean?
local function select_recipe(player, recipe_name, do_add)
    local g = gutils.get_graph(player)

    local _, not_visible = set_recipes_to_selection(player, do_add and recipe_name or nil)
    for _, grecipe in pairs(not_visible) do
        grecipe.visible = true
        graph.insert_recipe(g, grecipe)
    end
    graph.create_recipe_objects(g)
    if g.rs_recipe and g.rs_recipe.visible then
        gutils.select_current_recipe(g, g.rs_recipe)
    end
    graph.deferred_update(player, {
        selection_changed = true,
        do_layout = g.layout_on_selection,
        center_on_recipe = recipe_name,
        draw_target = true,
        no_recipe_selection_update = true
    })
end

tools.on_named_event(cb_name, defines.events.on_gui_checked_state_changed,
    function(e)
        local player = game.players[e.player_index]
        local recipe_name
        if e.element.state then
            recipe_name = e.element.tags.recipe_name --[[@as string]]
        end
        select_recipe(player, recipe_name)
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
            local b, type, name = gutils.create_product_button(remaining_pane, gproduct.name)
            b.style.size = general_button_size
            b.elem_tooltip = { type = type, name = name }
            b.tooltip = { np("remaining_tooltip") }
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
        local recipe = gutils.get_recipe_prototype(grecipe.name)
        if recipe and (not recipe.hidden) or g.show_hidden then
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
        local recipe_col1 = recipe_table.add { type = "flow", direction = "horizontal" }
        local recipe_name = recipe_element.grecipe.name
        recipe_col1.tags = { recipe_name = recipe_name }
        local state = g.selection[recipe_name] ~= nil

        local recipe = recipe_element.recipe
        local grecipe = recipe_element.grecipe

        local b = recipe_col1.add {
            type = "sprite-button",
            name = np("goto"),
            tooltip = { np("goto-tooltip") },
            mouse_button_filter = { "left" },
            sprite = commons.prefix .. "_arrow",
        }
        b.style.size = 18
        b.style.right_margin = 3
        b.style.top_margin = 6

        if recipe then
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
                table.insert(tooltip_builder, "[img=" .. name .. "] " .. amount .. " x " .. label)
                table.insert(i_table, { name = name, tooltip = label, amount = amount })
            end
            table.insert(tooltip_builder, "\n           [img=" .. prefix .. "_down]\n")

            if not machine or machine.count >= 0 then
                table.insert(tooltip_builder, "[/color][color=orange]")
            end

            start = true
            for _, p in pairs(recipe.products) do
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
                table.insert(p_table, { name = name, tooltip = label, amount = amount })
            end
            table.insert(tooltip_builder, "[/color]")
            table.insert(tooltip_builder, "\n[img=" .. prefix .. "_sep]")

            local tooltip = { "", table.concat(tooltip_builder), "\n", { np("time") }, ":", tostring(recipe.energy), "s " }

            local b_recipe = recipe_col1.add { type = "choose-elem-button", elem_type = "recipe", recipe = gutils.get_recipe_base_name(recipe_name) }
            b_recipe.style = recipe_button_style
            b_recipe.locked = true
            b_recipe.style.size = general_button_size
            tools.set_name_handler(b_recipe, np("recipe"), { recipe_name = recipe_name })

            local technologies = prototypes.get_technology_filtered({ {
                filter = "unlocks-recipe",
                recipe = gutils.get_recipe_base_name(recipe_name)
            } })
            if #technologies > 0 then
                for _, tech in pairs(technologies) do
                    local b_tech = recipe_col1.add { type = "choose-elem-button", elem_type = "technology", technology = tech.name }
                    b_tech.locked = true
                    b_tech.style.size = general_button_size
                    b_tech.tooltip = { np("tech_tooltip") }
                    b_tech.elem_tooltip = { type = "technology", name = tech.name }

                    tools.set_name_handler(b_tech, np("technology"), { technology = tech.name })
                end
            end

            local machines = machinedb.get_machines_for_recipe(recipe_name)
            if machines and #machines > 0 then
                local machine_names = {}
                for _, machineinfo in pairs(machines) do
                    table.insert(machine_names, machineinfo.name)
                end
                local b_machine = recipe_col1.add {
                    type = "choose-elem-button",
                    elem_type = "entity",
                    elem_filters = { { filter = "name", name = machine_names } }
                }
                b_machine.style.size = general_button_size
                b_machine.elem_value = machines[1].name
                b_machine.elem_tooltip = { type = "entity", name = machines[1].name }
                -- b_machine.tooltip = { np("machine_tooltip") }
                b_machine.raise_hover_events = true

                tools.set_name_handler(b_machine, np("machine"), { recipe_name = recipe_name })
            end

            local cb = recipe_col1.add {
                type = "checkbox",
                state = state,
                name = cb_name,
                tooltip = tooltip,
                caption = recipe_element.grecipe.enabled and recipe_element.localised
                    or ("[color=orange]" .. recipe_element.localised .. "[/color]"),
                tags = { recipe_name = recipe_name }
            }
            cb.style.top_margin = 6
            cb.style.minimal_width = 100
            if #technologies == 0 then
                cb.style.left_margin = general_button_size + 4
            end
            recipe_col1.tooltip = tooltip

            local recipe_col2 = recipe_table.add { type = "flow", direction = "horizontal", tooltip = tooltip }
            recipe_col2.style.left_margin = 10
            local ingredient_table = recipe_col2.add { type = "table", column_count = 5 }
            for index, def in pairs(i_table) do
                local b, type, name = gutils.create_product_button(ingredient_table, def.name)
                b.style = ingredient_button_style
                b.style.size = general_button_size
                b.style.margin = 0
                b.elem_tooltip = { type = type, name = name }
                b.tooltip = { np("ingredient_tooltip") }
                local qtlabel = b.add { type = "label", style = label_style_name, name = "label", ignored_by_interaction = true }
                qtlabel.caption = tostring(def.amount)
                tools.set_name_handler(b, np("product_button"), 
                    { type="ingredient", product_name = def.name, recipe_name = recipe_name, index = index })
            end
            local arrow = recipe_col2.add { type = "sprite", sprite = img_arrow, tooltip = tooltip }
            arrow.style.top_margin = 6
            local product_table = recipe_col2.add { type = "table", column_count = 5 }
            for index, def in pairs(p_table) do
                local b, type, name = gutils.create_product_button(product_table, def.name)
                b.style = product_button_style
                b.style.size = general_button_size
                b.style.margin = 0
                b.elem_tooltip = { type = type, name = name }
                b.tooltip = { np("production_tooltip") }
                local qtlabel = b.add { type = "label", style = label_style_name, name = "label", ignored_by_interaction = true }
                qtlabel.caption = tostring(def.amount)
                tools.set_name_handler(b, np("product_button"), 
                    { type="product", product_name = def.name, recipe_name = recipe_name, index = index })
            end
            recipe_col2.style.horizontally_stretchable = true

            if grecipe.use_temperature then
                local temperature_table = recipe_table.add { type = "table", column_count = 2 }

                if not grecipe.i_temperatures then grecipe.i_temperatures = {} end
                if not grecipe.p_temperatures then grecipe.p_temperatures = {} end

                for i_ingredient, i in pairs(recipe.ingredients) do
                    if i.minimum_temperature and i.maximum_temperature then
                        local gproduct = g.products[i.type .. "/" .. i.name]
                        if gproduct and gproduct.temperatures then
                            local idx = tostring(i_ingredient)
                            local labels = { { np("temperature_default") } }
                            local values = { commons.default_temperature }
                            local tcurrent = grecipe.i_temperatures[idx]
                            local index = 1
                            local tdefault = i.minimum_temperature
                            local icurrent
                            if tcurrent == commons.default_temperature then
                                icurrent = 1
                            end
                            for t, _ in pairs(gproduct.temperatures) do
                                if t >= i.minimum_temperature and t <= i.maximum_temperature then
                                    table.insert(values, t)
                                    table.insert(labels, { np("temperature_value"), tostring(t) })
                                    index = index + 1
                                    if tcurrent and t == tcurrent then
                                        icurrent = index
                                    elseif not icurrent and t == tdefault then
                                        icurrent = index
                                    end
                                end
                            end
                            icurrent = icurrent or 1
                            grecipe.i_temperatures[idx] = values[icurrent]
                            temperature_table.add { type = "label", caption = { np("temperature_in"), "[img=" .. i.type .. "." .. i.name .. "]" } }
                            local f = temperature_table.add { type = "drop-down", items = labels, selected_index = icurrent }
                            tools.set_name_handler(f, np("temperature_in"), { recipe = grecipe.name, ingredient = idx, values = values })
                        end
                    end
                end

                for i_product, p in pairs(recipe.products) do
                    if p.temperature then
                        local gproduct = g.products[p.type .. "/" .. p.name]
                        if gproduct and gproduct.temperatures then
                            local idx = tostring(i_product)
                            local values = { commons.default_temperature }
                            local labels = { { np("temperature_default") } }
                            local tcurrent = grecipe.p_temperatures[idx]
                            local icurrent
                            local index = 1
                            local tdefault = p.temperature
                            if tcurrent == commons.default_temperature then
                                icurrent = 1
                            end
                            for t, _ in pairs(gproduct.temperatures) do
                                if t <= tdefault then
                                    table.insert(values, t)
                                    table.insert(labels, { np("temperature_value"), tostring(t) })
                                    index = index + 1
                                    if tcurrent and tcurrent == t then
                                        icurrent = index
                                    elseif not icurrent and t == tdefault then
                                        icurrent = index
                                    end
                                end
                            end
                            icurrent = icurrent or 1
                            grecipe.p_temperatures[idx] = values[icurrent]
                            temperature_table.add { type = "label", caption = { np("temperature_out"), "[img=" .. p.type .. "." .. p.name .. "]" } }
                            local f = temperature_table.add { type = "drop-down", items = labels, selected_index = icurrent }
                            tools.set_name_handler(f, np("temperature_out"), { recipe = grecipe.name, product = idx, values = values })
                            f.style.bottom_margin = 10
                        end
                    end
                end

                local derived_name = gutils.get_derived_name(grecipe.name, grecipe.i_temperatures, grecipe.p_temperatures)
                if g.recipes[derived_name] and g.recipes[derived_name].visible then
                    cb.state = true
                end
                recipe_table.add { type = "empty-widget" }
            end
        else
            local b = gutils.create_product_button(recipe_col1, recipe_name)
            b.style.size = general_button_size

            recipe_col1.add {
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

---@param g Graph
---@param grecipe GRecipe
---@param control boolean?
function recipe_selection.goto_recipe(g, grecipe, control)
    local position = gutils.get_recipe_position(g, grecipe)
    if not position then return end
    drawing.draw_target(g, grecipe)
    if control then
        gutils.teleport(g.player, position)
    else
        gutils.move_view(g.player, position)
    end
    gutils.refresh_machine_list(g, grecipe.name)
end

tools.on_gui_click(np("goto"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local line = e.element.parent
        ---@cast line -nil
        local recipe_name = line.tags.recipe_name
        local g = gutils.get_graph(player)

        local grecipe = gutils.get_instanced_recipe(g, recipe_name)
        if not grecipe then return end

        if not (e.shift or e.control or e.alt) then
            if player.surface == g.surface then
                recipe_selection.goto_recipe(g, grecipe, e.control)
            else
                gutils.show_machine(player, recipe_name, true)
                gutils.refresh_machine_list(g, recipe_name)
            end
        end
    end)


tools.on_named_event(np("choose_recipe"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
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
    end)

---@param player LuaPlayer
---@return integer
function recipe_selection.get_action(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then
        return 1
    end
    local faction = tools.get_child(frame, np("action"))
    local action = faction and faction.selected_index or 1
    return action
end

---@param player LuaPlayer
---@param product_name string
---@param action integer?
function recipe_selection.process_query(player, product_name, action)
    local g = gutils.get_graph(player)

    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then
        recipe_selection.open(g, { product = g.products[product_name] })
        return
    end
    local recipes = {}

    local gproduct = g.products[product_name]
    if gproduct then
        if action == 1 then
            for _, grecipe in pairs(gproduct.ingredient_of) do
                recipes[grecipe.name] = grecipe
            end
            for _, grecipe in pairs(gproduct.product_of) do
                recipes[grecipe.name] = grecipe
            end
        elseif action == 2 then
            local target_products = { [product_name] = gproduct }
            local found_products = gutils.get_output_products(g)
            while (true) do
                local _, product = next(target_products)
                if not product then break end

                local frecipe
                for _, recipe in pairs(product.product_of) do
                    if not recipe.is_product then
                        frecipe = recipe
                        break
                    end
                end

                if not frecipe then
                    found_products[product.name] = product
                    target_products[product.name] = nil
                    goto skip
                end

                ---@cast frecipe -nil
                if frecipe.is_product then
                    goto skip
                end

                recipes[frecipe.name] = frecipe
                for _, p in pairs(frecipe.products) do
                    found_products[p.name] = p
                    target_products[p.name] = nil
                end

                for _, i in pairs(frecipe.ingredients) do
                    if not found_products[i.name] then
                        target_products[i.name] = i
                    end
                end

                ::skip::
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
    recipes = gutils.filter_candidate_recipes(recipes, g)

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
        local action = recipe_selection.get_action(player)
        push_history_with_names(player, nil, name, action)
        recipe_selection.process_query(player, name, action)
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
        local action = recipe_selection.get_action(player)
        push_history_with_names(player, nil, name, action)
        recipe_selection.process_query(player, name, action)
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
        tools.fire_user_event(commons.production_data_change_event, { g = g })
    end)

---@param player LuaPlayer
---@return string?
function recipe_selection.get_product_name(player)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return end

    local choose_item = tools.get_child(frame, "choose_item")
    local choose_fluid = tools.get_child(frame, "choose_fluid")

    if not choose_item or not choose_fluid then return end
    local item = choose_item.elem_value
    local fluid = choose_fluid.elem_value
    local name
    if item then
        name = "item/" .. item
    elseif fluid then
        name = "fluid/" .. fluid
    end
    return name
end

---@param player LuaPlayer
function recipe_selection.refresh(player)
    local name = recipe_selection.get_product_name(player)
    if not name then
        recipe_selection.show_recipes(player, {})
        return
    end
    local action = recipe_selection.get_action(player)
    recipe_selection.process_query(player, name, action)
end

tools.on_named_event(np("action_in_list"), defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        if not e.element.valid then return end
        local player = game.players[e.player_index]

        local product_name = recipe_selection.get_product_name(player)
        local action = recipe_selection.get_action(player)
        push_history_with_names(player, nil, product_name, action)
        recipe_selection.refresh(player)
    end)

tools.on_named_event(np("recipe"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        ---@type LuaPlayer
        local player = game.players[e.player_index]
        local recipe_name = e.element.tags.recipe_name --[[@as string]]

        local g = gutils.get_graph(player)
        if g and g.surface == player.surface then
            if not (e.shift or e.control or e.alt) then
                local grecipe = g.recipes[recipe_name]
                if not grecipe.visible then
                    if not g.layout_on_selection then
                        gutils.set_cursor_stack(player, recipe_name)
                        recipe_selection.close(player.index)
                    elseif g.selection[recipe_name] then
                        if g.visibility == commons.visibility_layers then
                            if grecipe.layer ~= g.current_layer then
                                grecipe.layer = g.current_layer
                            end
                            graph.deferred_update(player, { do_layout = true })
                            tools.fire_user_event(commons.production_data_change_event, { g = g })
                        elseif grecipe.visible then
                            recipe_selection.show_recipes(player, grecipe)
                        end
                    else
                        select_recipe(player, recipe_name, true)
                    end
                else
                    recipe_selection.show_recipes(player, { grecipe })
                end
            end
        end
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
        recipe_selection.open(g, { product = gproduct, only_product = true, action = action_producer })
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
    ---@cast data RecipeSelectionOptions
    local g = data.g
    recipe_selection.open(g, data)
end)

tools.register_user_event(commons.query_product, function(data)
    local product_name = data.product_name
    local player = data.player
    local action = recipe_selection.get_action(player)
    recipe_selection.process_query(player, product_name, action)
end
)

drawing.open_recipe_selection = recipe_selection.open
graph.update_recipe_selection = recipe_selection.update_recipes

tools.on_named_event(np("only_researched"), defines.events.on_gui_checked_state_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        if not g then return end

        g.show_only_researched = e.element.state
        recipe_selection.refresh(player)
    end)

tools.on_named_event(np("technology"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local technology = e.element.tags.technology
        if not (e.shift or e.control or e.alt) then
            player.open_technology_gui(technology)
        end
    end)

tools.on_named_event(np("machine"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
    function(e)
        local player = game.players[e.player_index]
        local selected = e.element.elem_value
        if selected then
            e.element.elem_tooltip = { type = "entity", name = selected }
        else
            e.element.elem_tooltip = nil
        end
    end)


tools.on_named_event(np("machine"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if e.control and not e.shift and not e.alt then
            local selected = e.element.elem_value
            if not selected then return end

            local bp_entity = {
                entity_number = 1,
                name = selected,
                position = { 0.5, 0.5 },
                recipe = e.element.tags.recipe_name,

            }
            local cursor_stack = player.cursor_stack
            if not cursor_stack then return end

            cursor_stack.clear()
            cursor_stack.set_stack { name = "blueprint", count = 1 }
            cursor_stack.set_blueprint_entities { bp_entity }
            player.cursor_stack_temporary = true
        end
    end)

tools.on_named_event(np("machine"), defines.events.on_gui_hover,
    ---@param e EventData.on_gui_hover
    function(e)
        local player = game.players[e.player_index]
        local machine_name = e.element.elem_value

        local machine
        if machine_name then
            machine = prototypes.entity[machine_name]
        end
        local parts = { "" }

        e.element.tooltip = { np("machine-tooltip"), "" }
        if machine then
            parts = gutils.create_machine_tooltip(player, machine)
            if #parts > 16 then
                local newparts = {}
                for i = 1, 16 do
                    table.insert(newparts, parts[i])
                end
                parts = newparts
            end
            e.element.tooltip = { np("machine-tooltip"), { "", machine.localised_name }, parts }
        end
    end)

---@param player LuaPlayer
---@param g Graph
---@param grecipe GRecipe
local function update_cb(player, g, grecipe)
    local derived_name = gutils.get_derived_name(grecipe.name, grecipe.i_temperatures, grecipe.p_temperatures)
    local frame = player.gui.screen[recipe_selection_frame_name]
    if not frame then return end

    local recipe_table = tools.get_child(frame, "recipe_table")

    ---@cast recipe_table -nil
    for _, line in pairs(recipe_table.children) do
        local recipe_name = line.tags.recipe_name --[[@as string]]
        if recipe_name == grecipe.name then
            local cb = line[cb_name]
            if cb then
                if g.recipes[derived_name] and g.recipes[derived_name].visible then
                    cb.state = true
                else
                    cb.state = false
                end
            end
            return
        end
    end
end

tools.on_named_event(np("temperature_in"), defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        local player = game.players[e.player_index]
        local element = e.element
        if not (element and element.valid) then return end

        local tags = element.tags
        local g = gutils.get_graph(player)
        local recipe_name = tags.recipe
        local grecipe = g.recipes[recipe_name]
        if not grecipe then return end

        local ingredient = tags.ingredient
        local values = tags.values
        if not grecipe.i_temperatures then
            grecipe.i_temperatures = {}
        end
        grecipe.i_temperatures[ingredient] = values[element.selected_index]

        update_cb(player, g, grecipe)
    end)

tools.on_named_event(np("temperature_out"), defines.events.on_gui_selection_state_changed,
    ---@param e EventData.on_gui_selection_state_changed
    function(e)
        local player = game.players[e.player_index]
        local element = e.element
        if not (element and element.valid) then return end

        local tags = element.tags
        local g = gutils.get_graph(player)
        local recipe_name = tags.recipe
        local grecipe = g.recipes[recipe_name]
        if not grecipe then return end

        local product = tags.product
        local values = tags.values
        if not grecipe.p_temperatures then
            grecipe.p_temperatures = {}
        end
        grecipe.p_temperatures[product] = values[element.selected_index]

        update_cb(player, g, grecipe)
    end)


return recipe_selection

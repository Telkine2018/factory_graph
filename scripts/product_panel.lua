local luautil = require("__core__/lualib/util")

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local drawing = require("scripts.drawing")
local graph = require("scripts.graph")

local recipe_selection = require("scripts.recipe_selection")
local production = require("scripts.production")
local msettings_panel = require("scripts.msettings_panel")

local product_panel = {}
local prefix = commons.prefix

local label_style_name = prefix .. "_count_label_bottom"
local label_style_top = prefix .. "_count_label_top"

local default_button_style = prefix .. "_button_default"
local default_button_label_style = prefix .. "_count_label_bottom"

local arrow_sprite_white = prefix .. "_arrow-white"
local arrow_sprite_black = prefix .. "_arrow"

local math_precision = commons.math_precision
local abs = math.abs

local product_button_style = commons.buttons.product
local ingredient_button_style = commons.buttons.ingredient
local recipe_button_style = commons.buttons.recipe

local green_button = commons.buttons.green
local red_button = commons.buttons.red
local default_button = commons.buttons.default


local function np(name)
    return prefix .. "-product-panel." .. name
end

local product_panel_name = np("frame")
local input_qty_name = np("frame")
local location_name = np("location")
local min_name = np("mini")

local fround = tools.fround

---@param g Graph
local function get_production_title(g)
    if not g.production_failed then
        return { np("title") }
    elseif type(g.production_failed) == "string" then
        return { "", { np("failed-title") }, { np("failure_" .. g.production_failed) } }
    else
        return { "", { np("failed-title") }, g.production_failed }
    end
end

---@param player_index integer
function product_panel.create(player_index)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)

    if not g then return end

    if (player.gui.screen[product_panel_name]) then
        product_panel.close(player)
        return
    end

    local vars = tools.get_vars(player)
    local is_mini = vars[min_name]

    ---@type Params.create_standard_panel
    local params = {
        panel_name           = product_panel_name,
        title                = get_production_title(g),
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = np("close_button_tooltip"),
        title_menu_func      = function(flow)
            local b
            b = flow.add {
                type = "button",
                tooltip = { np("unselect_tooltip") },
                caption = { np("unselect") },
            }
            tools.set_name_handler(b, np("unselect"))

            b = flow.add {
                type = "sprite-button",
                tooltip = { np("mini_tooltip") },
                name = "mini_maxi",
                style = "frame_action_button",
                mouse_button_filter = { "left" },
                sprite = not is_mini and commons.prefix .. "_mini_white" or commons.prefix .. "_maxi_white",
                hovered_sprite = not is_mini and commons.prefix .. "_mini_black" or commons.prefix .. "_maxi_black"
            }
            tools.set_name_handler(b, np("mini_maxi"))
        end
    }
    local frame = tools.create_standard_panel(player, params)
    frame.style.maximal_height = 800

    local inner_flow = frame.add { type = "flow", direction = "horizontal" }
    local product_frame = inner_flow.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
        name = "product_frame"
    }
    product_frame.style.vertically_stretchable = true
    product_frame.style.horizontally_stretchable = true
    local scroll = product_frame.add { type = "scroll-pane", horizontal_scroll_policy = "never", name = "scroll-table" }
    scroll.style.horizontally_stretchable = true
    product_panel.create_product_tables(player)

    local machine_frame = inner_flow.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    machine_frame.style.minimal_width = 200
    machine_frame.style.minimal_height = 400

    local tabbed_pane = machine_frame.add { type = "tabbed-pane" }
    tabbed_pane.style.vertically_stretchable = true
    tabbed_pane.style.horizontally_stretchable = true

    local setup_tab = tabbed_pane.add { type = "tab", caption = { np("setup") } }
    local summary_tab = tabbed_pane.add { type = "tab", caption = { np("summary") } }
    local setup_flow = tabbed_pane.add { type = "flow", direction = "vertical", name = "setup_flow" }

    local summary_scroll = tabbed_pane.add { type = "scroll-pane", direction = "vertical",
        horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" }
    summary_scroll.style.horizontally_stretchable = true
    summary_scroll.style.vertically_stretchable = true
    local summary_flow = summary_scroll.add { type = "flow", direction = "vertical", name = "summary_flow" }

    tabbed_pane.add_tab(setup_tab, setup_flow)
    tabbed_pane.add_tab(summary_tab, summary_scroll)

    local error_panel = setup_flow.add { type = "flow", direction = "vertical", name = "error_panel" }
    error_panel.visible = false
    error_panel.style.vertically_stretchable = true
    error_panel.style.maximal_height = 600

    local machine_scroll = setup_flow.add { type = "scroll-pane",
        horizontal_scroll_policy = "never", name = "machine_scroll", vertical_scroll_policy = "auto-and-reserve-space" }
    machine_scroll.add { type = "table", column_count = 1, name = "machine_container" }
    machine_scroll.style.horizontally_stretchable = true
    machine_scroll.style.vertically_stretchable = true

    summary_flow.add { type = "label", caption = "" }

    product_panel.update_machine_panel(g, setup_flow, summary_flow)

    local location = vars[location_name]
    if location then
        frame.location = location
    else
        frame.force_auto_center()
    end
    if is_mini then
        product_frame.visible = false
    end
end

---@param g Graph
---@param product_name string
---@param qtlabel LuaGuiElement
---@return number?
local function set_output_value(g, product_name, qtlabel)
    ---@type any
    local value = g.iovalues[product_name]
    local caption
    local is_unlinked
    local mark = ""
    if value == 0 then
        caption = "0"
    else
        is_unlinked = value == true
        if is_unlinked then
            value = nil
            mark = "*"
        end

        local input, output
        local is_computed
        if not value then
            if g.product_outputs then
                output = g.product_outputs[product_name] or 0
                is_computed = true
                input = g.product_inputs[product_name] or 0

                output = fround(output)
                input = fround(input)
                if output >= input then
                    value = output
                else
                    value = -input
                end
            end
        end

        if value and math.abs(value) > math_precision then
            value = fround(value)
            if is_computed and value > 0 then
                caption = mark .. "[color=orange]" .. luautil.format_number(value, true) .. "[/color]"
                if input ~= output then
                    caption = caption .. "[color=red]?[/color]"
                end
            elseif is_computed then
                caption = mark .. "[color=cyan]" .. luautil.format_number(-value, true) .. "[/color]"
                if input ~= output then
                    caption = caption .. "[color=red]?[/color]"
                end
            else
                caption = luautil.format_number(value, true)
            end
        elseif is_unlinked then
            caption = "*"
        end
    end
    if caption then
        qtlabel.caption = caption
        return value
    else
        qtlabel.caption = ""
        return nil
    end
end


function product_panel.create_product_tables(player)
    local frame = player.gui.screen[product_panel_name]
    if not frame then return end

    local scroll = tools.get_child(frame, "scroll-table")
    if not scroll then return end

    scroll.clear()

    ---@param title LocalisedString?
    local function add_line(title)
        gutils.add_line(scroll, title)
    end

    local g = gutils.get_graph(player)
    local recipes = g.recipes
    if g.use_connected_recipes and not g.require_full_selection then
        recipes = gutils.get_connected_recipes(g, g.iovalues)
        if not next(recipes) then
            recipes = g.recipes
        end
    end
    g.require_full_selection             = nil
    local inputs, outputs, intermediates = gutils.get_product_flow(g, recipes)

    local column_count                   = 3
    local column_width                   = 120
    local product_button_tooltip         = { np("product_button_tooltip") }

    ---@param products table<string, GProduct>
    ---@param table_name string
    function create_product_table(products, table_name)
        ---@type {product:GProduct, label:string}[]
        local list = {}
        for _, prod in pairs(products) do
            table.insert(list, { product = prod, label = gutils.get_product_name(player, prod.name) })
        end
        table.sort(list, function(e1, e2) return e1.label < e2.label end)

        local product_table = scroll.add { type = "table", column_count = column_count, name = table_name,
            style = prefix .. "_default_table", draw_vertical_lines = true }
        product_table.style.cell_padding = 0
        for _, product in pairs(list) do
            local product_name = product.product.name
            local pline = product_table.add { type = "flow", direction = "horizontal" }

            local b = gutils.create_product_button(pline, product_name, "product_button")
            b.raise_hover_events = true
            tools.set_name_handler(b, np("product"), { product_name = product_name, label = product.label })

            local qtlabel = b.add { type = "label", style = label_style_name, name = "label", ignored_by_interaction = true }
            local value = set_output_value(g, product_name, qtlabel)

            b.style.size = 36
            b.style.vertical_align = "top"

            local vinput = pline.add { type = "flow", direction = "vertical", name = "vinput" }
            local label = vinput.add { type = "label", caption = product.label }

            if g.iovalues[product_name] then
                b.style = red_button
            else
                value = value
                if value then
                    if value < 0 then
                        b.style = ingredient_button_style
                    else
                        b.style = product_button_style
                    end
                else
                    b.style = default_button
                end
            end

            label.style.width = column_width
        end
    end

    add_line({ np("outputs") })
    create_product_table(outputs, "outputs")

    add_line({ np("inputs") })
    create_product_table(inputs, "inputs")

    add_line({ np("intermediates") })
    create_product_table(intermediates, "intermediates")
end

---@param g Graph
local function update_products(g)
    local player = g.player

    local frame = tools.get_panel(player, product_panel_name)
    if not frame then return end

    ---@param table_name string
    local function update_table(table_name)
        local product_table = tools.get_child(frame, table_name)
        if product_table then
            for _, line in pairs(product_table.children) do
                local b = line.product_button
                local product_name = b.tags.product_name --[[@as string]]
                local value = set_output_value(g, product_name, b.label)
                if g.iovalues[product_name] then
                    b.style = red_button
                else
                    if value then
                        if value < 0 then
                            b.style = ingredient_button_style
                        else
                            b.style = product_button_style
                        end
                    else
                        b.style = default_button
                    end
                end
            end
        end
    end
    local title = get_production_title(g)
    local ftitle = tools.get_child(frame, "title")
    if ftitle then
        ftitle.caption = title
    end

    update_table("inputs")
    update_table("outputs")
    update_table("intermediates")
end

---@param parent LuaGuiElement
local function get_vinput(parent)
    local vinput = tools.get_child(parent, "vinput")
    ---@cast vinput -nil

    if #vinput.children > 1 then
        while #vinput.children > 1 do vinput.children[2].destroy() end
        return nil
    end
    return vinput
end

tools.on_named_event(np("product"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end

        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        if not e.element.valid then return end

        local product_name = e.element.tags.product_name --[[@as string]]
        if not product_name then return end

        if not (e.button ~= defines.mouse_button_type.right or e.control or e.shift) then
            recipe_selection.open(g, g.products[product_name], nil)
        elseif not (e.button ~= defines.mouse_button_type.left or not e.control or e.shift) then
            get_vinput(e.element.parent)
            if g.iovalues[product_name] == true then
                g.iovalues[product_name] = nil
            else
                g.iovalues[product_name] = true
            end
        elseif not (e.button ~= defines.mouse_button_type.left or e.control or not e.shift) then
            for _, grecipe in pairs(g.selection) do
                for _, ingredient in pairs(grecipe.ingredients) do
                    if ingredient.name == product_name then
                        grecipe.layer = product_name
                        goto skip
                    end
                end
                for _, product in pairs(grecipe.products) do
                    if product.name == product_name then
                        grecipe.layer = product_name
                        goto skip
                    end
                end
                ::skip::
            end
            drawing.draw_layers(g)
        elseif not (e.button ~= defines.mouse_button_type.left or e.control or e.shift) then
            local vinput = get_vinput(e.element.parent)
            if not vinput then return end
            local hinput = vinput.add { type = "flow", direction = "horizontal" }
            hinput.add { type = "label", caption = { np("product_qty") } }
            local input = hinput.add { type = "textfield",
                numeric = true, allow_negative = true, allow_decimal = true,
                name = np("qty") }
            tools.set_name_handler(input, np("qty"), { product_name = product_name })
            input.style.maximal_width = 80
            input.focus()
            local qty = g.iovalues[product_name]
            if type(qty) == "number" then
                input.text = tostring(qty)
            end
        end
        gutils.fire_production_data_change(g)
    end)

tools.on_named_event(np("product"), defines.events.on_gui_hover,
    ---@param e EventData.on_gui_hover
    function(e)
        if not e.element.valid then return end
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        local tags = e.element.tags
        local product_name = tags.product_name --[[@as string]]

        if not g.product_inputs then
            return
        end

        local input = g.product_inputs[product_name] or 0
        local output = g.product_outputs[product_name] or 0
        output = fround(output)
        input = fround(input)

        ---@type LocalisedString
        local output_label = ""
        ---@type LocalisedString
        local input_label = ""
        if math.abs(output) > math_precision or math.abs(input) > math_precision then
            output_label = { np("product_produced"), tostring(output) }

            if output ~= input then
                input_label = { np("product_consumed"), tostring(input) }
            else
                input_label = { np("product_all_consumed") }
            end
        end

        local gproduct = g.products[product_name]
        local pline = {}
        local set = {}

        ---@param recipes any
        local function scan_list(recipes)
            for _, grecipe in pairs(recipes) do
                local machine = grecipe.machine
                if machine and machine.count and not set[grecipe.name] and machine.count ~= 0 then
                    set[grecipe.name] = true
                    table.insert(pline, "\n")
                    table.insert(pline, "[recipe=" .. grecipe.name .. "] : ")

                    if machine.count > 0 then
                        table.insert(pline, "[color=cyan]")
                    else
                        table.insert(pline, "[color=red]")
                    end

                    for _, ingredient in pairs(machine.recipe.ingredients) do
                        local amount = production.get_ingredient_amount(machine, ingredient) * machine.count
                        table.insert(pline, fround(amount))
                        table.insert(pline, " x ")
                        table.insert(pline, " [" .. ingredient.type .. "=" .. ingredient.name .. "]")
                    end

                    if machine.count > 0 then
                        table.insert(pline, "[/color][color=orange]")
                    end

                    table.insert(pline, " [img=factory_graph_arrow-white] ")
                    for _, product in pairs(machine.recipe.products) do
                        local amount = production.get_product_amount(machine, product) * machine.count
                        table.insert(pline, fround(amount))
                        table.insert(pline, " x ")
                        table.insert(pline, " [" .. product.type .. "=" .. product.name .. "]")
                    end
                    table.insert(pline, "[/color]")
                end
            end
        end
        scan_list(gproduct.ingredient_of)
        scan_list(gproduct.product_of)

        local recipe_str = table.concat(pline)
        e.element.tooltip = { np("product_button_tooltip"), "[img=" .. product_name .. "]", tags.label, output_label, input_label, recipe_str }
    end)

tools.on_named_event(np("qty"), defines.events.on_gui_text_changed,
    ---@param e EventData.on_gui_text_changed
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        local product_name = e.element.tags.product_name --[[@as string]]

        local text = e.element.text
        local value = nil
        if #text > 0 then
            value = tonumber(text)
            g.iovalues[product_name] = value
            g.product_outputs[product_name] = value
        else
            g.iovalues[product_name] = nil
            g.product_outputs[product_name] = nil
        end
        gutils.fire_production_data_change(g)
    end)

function product_panel.close(player)
    local frame = player.gui.screen[product_panel_name]
    if not frame then return end

    local location = frame.location
    tools.get_vars(player)[location_name] = location
    frame.destroy()
end

tools.on_gui_click(np("close"), function(e)
    product_panel.close(game.players[e.player_index])
end)

tools.on_event(defines.events.on_gui_confirmed,
    ---@param e EventData.on_gui_confirmed
    function(e)
        if e.element.valid and e.element.name == np("qty") then
            e.element.parent.destroy()
        end
    end)

-- React to production computation
tools.register_user_event(commons.production_compute_event, function(data)
    ---@type Graph
    local g = data.g
    local player = g.player
    if data.structure_change then
        g.require_full_selection = true
    end

    if not player.gui.screen[product_panel_name] then return end

    if not g.selection or not next(g.selection) then
        product_panel.close(player)
        return
    end

    if not data.structure_change then
        update_products(g)
    else
        product_panel.close(player)
        product_panel.create(player.index)
    end
end)

local get_product_amount = production.get_product_amount

---@param container LuaGuiElement
---@param machine ProductionMachine
local function create_product_line(container, machine)
    local line1 = container.add { type = "flow", direction = "horizontal" }
    line1.style.height = 40

    if not machine.count then
        machine.count = 1
    end

    local caption
    if machine.count > 1000 then
        caption = string.format("%.0f", math.ceil(machine.count))
    else
        caption = string.format("%.1f", math.ceil(machine.count * 10) / 10)
    end

    local b = line1.add {
        type = "choose-elem-button",
        elem_type = "entity",
        entity = machine.machine.name,
        style = green_button,
        tooltip = { np("machine-tooltip") }
    }
    b.locked = true
    tools.set_name_handler(b, np("machine"), { recipe_name = machine.recipe.name })
    b.raise_hover_events = true
    local label = b.add { type = "label", style = default_button_label_style, caption = caption, ignored_by_interaction = true }

    local frecipe = line1.add { type = "choose-elem-button", elem_type = "recipe", recipe = machine.name, style = recipe_button_style }
    frecipe.style.right_margin = 5
    frecipe.locked = true
    tools.set_name_handler(frecipe, np("recipe_detail"), { recipe_name = machine.name })

    line = line1.add { type = "line", direction = "vertical" }
    line.style.left_margin = 5
    line.style.right_margin = 8

    for _, ingredient in pairs(machine.recipe.ingredients) do
        local type = ingredient.type
        b = line1.add { type = "choose-elem-button", elem_type = type, item = ingredient.name, fluid = ingredient.name, style = ingredient_button_style }
        b.locked = true
        tools.set_name_handler(b, np("open_product"), { recipe_name = machine.name, product_name = type .. "/" .. ingredient.name })

        local amount = ingredient.amount * machine.limited_craft_s * machine.count
        amount = fround(amount)
        b.add { type = "label", style = default_button_label_style,
            caption = tostring(amount), ignored_by_interaction = true }
    end

    -- local col2 = container.add { type = "flow", direction = "horizontal" }
    local line2 = line1

    local b = line2.add {
        type = "sprite-button",
        name = np("goto"),
        tooltip = { np("goto-tooltip") },
        mouse_button_filter = { "left" },
        sprite = arrow_sprite_white,
        hovered_sprite = arrow_sprite_black,
        tags = { recipe_name = machine.name }
    }
    b.style.size = 24
    b.style.margin = 5

    for _, product in pairs(machine.recipe.products) do
        local type = product.type
        b = line2.add { type = "choose-elem-button", elem_type = type, item = product.name, fluid = product.name, style = product_button_style }
        b.locked = true
        tools.set_name_handler(b, np("open_product"), { recipe_name = machine.name, product_name = type .. "/" .. product.name })

        local amount = get_product_amount(machine, product)

        amount = amount * machine.count
        amount = fround(amount)
        b.add { type = "label", style = default_button_label_style, caption = tostring(amount), ignored_by_interaction = true }
    end
end
product_panel.create_product_line = create_product_line

---@param g Graph
---@param error_panel LuaGuiElement
function product_panel.update_error_panel(g, error_panel)
    ---@type ProductionMachine[]
    local failed_machines = {}
    for name in pairs(g.production_recipes_failed) do
        local machine = g.recipes[name].machine
        if machine then
            table.insert(failed_machines, machine)
        end
    end
    if #failed_machines == 0 then
        return
    end
    error_panel.add { type = "label", caption = { np("error_title") } }

    for _, machine in pairs(failed_machines) do
        local line = error_panel.add { type = "flow", direction = "horizontal" }

        local b = line.add { type = "choose-elem-button", elem_type = "recipe", recipe = machine.name }
        b.locked = true
        tools.set_name_handler(b, np("recipe_detail"), { recipe_name = machine.name })

        local flow = line.add { type = "flow", direction = "vertical" }
        flow.add { type = "label", caption = { np("error_recipe_lanel"),
            translations.get_recipe_name(error_panel.player_index, machine.name) } }

        local line1 = flow.add { type = "flow", direction = "horizontal" }

        local current = machine.grecipe
        local recurs_set = {}
        while true do
            ---@param products GProduct[]
            ---@return integer, GProduct?
            local function unbound_count(products)
                local count = 0
                local found
                for _, gproduct in pairs(products) do
                    if g.bound_products[gproduct.name] then
                        count = count + 1
                        found = gproduct
                    end
                    if count > 1 then
                        return count, nil
                    end
                end
                return count, found
            end
            local count_product = unbound_count(current.products)
            if count_product > 1 then break end

            local _, ingredient = unbound_count(current.ingredients)
            if not ingredient then break end

            local irecipes = {}
            for _, irecipe in pairs(ingredient.product_of) do
                if g.selection[irecipe.name] then
                    table.insert(irecipes, irecipe)
                end
            end

            if #irecipes ~= 1 then
                break
            end
            recurs_set[current.name] = true
            current = irecipes[1]
            if recurs_set[current.name] then
                break
            end
            if current == machine.grecipe then
                break
            end
        end

        line1.add { type = "label", caption = { np("error_recipe_constraints") } }
        for _, product in pairs(current.products) do
            if not g.iovalues[product.name] then
                local signal = tools.sprite_to_signal(product.name)
                local b
                ---@cast signal -nil
                if signal.type == "item" then
                    b = line1.add { type = "choose-elem-button", elem_type = "item", item = signal.name }
                else
                    b = line1.add { type = "choose-elem-button", elem_type = "fluid", fluid = signal.name }
                end

                local qtlabel = b.add { type = "label", style = label_style_name, name = "label", ignored_by_interaction = true }
                set_output_value(g, product.name, qtlabel)

                tools.set_name_handler(b, np("error-unlock-product"), { product_name = product.name })
                b.style.size = 30
                b.locked = true
            end
        end
    end
end

---@param player any
---@return LuaInventory?
---@return LuaLogisticNetwork?
---@return {[string]:integer}
local function get_inventories(player)
    ---@type LuaEntity
    local character = player.character
    local vars = tools.get_vars(player)
    if not character and vars.saved_character and vars.saved_character.valid then
        character = vars.saved_character
    end

    ---@type LuaInventory?
    local inv
    ---@type LuaLogisticNetwork?
    local network

    if character then
        inv = character.get_main_inventory()
        network = character.surface.find_logistic_network_by_position(character.position, player.force_index)
    end
    local craft_queue = {}
    if player.crafting_queue_size > 0 then
        for _, c in pairs(player.crafting_queue) do
            local recipe = game.recipe_prototypes[c.recipe]
            if recipe then
                for _, p in pairs(recipe.products) do
                    if p.type == "item" then
                        local amount = p.amount
                        if not amount then
                            amount = (p.amount_min + p.amount_max) / 2
                        end
                        craft_queue[p.name] = (craft_queue[p.name] or 0) + amount * c.count
                    end
                end
            end
        end
    end
    return inv, network, craft_queue
end

---@param count integer
---@param in_inventory_count integer
---@param in_network_count integer
---@param crafted integer
local function get_summary_labels(count, in_inventory_count, in_network_count, crafted)
    local count_label = tostring(count)
    if count > in_inventory_count + in_network_count + crafted then
        count_label = "[color=red][font=default-bold]" .. count_label .. "[/font][/color]"
    elseif count > in_inventory_count + crafted then
        count_label = "[color=yellow][font=default-bold]" .. count_label .. "[/font][/color]"
    else
        count_label = "[color=green][font=default-bold]" .. count_label .. "[/font][/color]"
    end

    local inventory_count = tostring(in_inventory_count)
    if crafted > 0 then
        inventory_count = inventory_count .. " (" .. crafted .. ")"
    end

    return count_label, inventory_count
end

---@param g Graph
---@param setup_flow LuaGuiElement
---@param summary_flow LuaGuiElement
function product_panel.update_machine_panel(g, setup_flow, summary_flow)
    local machine_scroll = setup_flow.machine_scroll
    local machine_container = machine_scroll.machine_container
    local player = g.player
    local vars = tools.get_vars(player)

    machine_container.clear()
    if not g.selection then return end

    local error_panel = machine_container.parent.parent.error_panel
    if error_panel then
        error_panel.clear()
    end

    if g.production_failed then
        if not error_panel or not g.production_recipes_failed then
            return
        end
        error_panel.visible = true
        machine_scroll.visible = false
        summary_flow.visible = false

        product_panel.update_error_panel(g, error_panel)
        return
    end

    error_panel.visible = false
    machine_scroll.visible = true
    summary_flow.visible = true

    ---@type ProductionMachine[]
    local machines = {}
    for _, grecipe in pairs(g.selection) do
        local machine = grecipe.machine
        if machine and machine.count and machine.count > math_precision then
            table.insert(machines, machine)
        end
    end
    if #machines == 0 then return end

    table.sort(machines, function(m1, m2) return m1.grecipe.sort_level < m2.grecipe.sort_level end)

    if g.visibility == commons.visibility_layers then
        local visible_layers = g.visible_layers or {}
        local new_machines = {}
        for _, machine in pairs(machines) do
            if machine.grecipe.layer and visible_layers[machine.grecipe.layer] then
                table.insert(new_machines, machine)
            end
        end
        machines = new_machines
    end

    local count_per_machine = {}
    for _, machine in pairs(machines) do
        create_product_line(machine_container, machine)

        local count = math.ceil(machine.count)
        if count > 0 and machine.machine then
            local machine_name = machine.machine.name

            count_per_machine[machine_name] = (count_per_machine[machine_name] or 0) + count
        end
    end

    for i = 1, 5 do
        local empty = machine_container.add { type = "empty-widget" }
        empty.style.vertically_stretchable = true
    end

    summary_flow.clear()
    summary_flow.add { type = "label", caption = { np("total_energy"), g.total_energy and luautil.format_number(g.total_energy or "", true) } }

    summary_flow.add { type = "line" }
    local per_machine_table = summary_flow.add { type = "table", column_count = 5, style = prefix .. "_default_table", draw_vertical_lines = true }
    per_machine_table.style.horizontally_stretchable = true

    local inv, network, craft_queue = get_inventories(player)

    ---@class ProductPanel_Machines
    ---@field name string
    ---@field label string
    ---@field count integer

    ---@type ProductPanel_Machines[]
    local sorted_table = {}

    local lwidth = 50

    per_machine_table.add { type = "empty-widget" }
    per_machine_table.add { type = "empty-widget" }

    local label                  = per_machine_table.add { type = "label", caption = { np("build-used") } }
    label.style.horizontal_align = "center"
    label.style.width            = lwidth

    label                        = per_machine_table.add { type = "label", caption = { np("build-inventory") } }
    label.style.horizontal_align = "center"
    label.style.width            = lwidth

    label                        = per_machine_table.add { type = "label", caption = { np("build-logistic") } }
    label.style.horizontal_align = "center"
    label.style.width            = lwidth

    for name, count in pairs(count_per_machine) do
        table.insert(sorted_table, {
            name = name,
            label = translations.get_entity_name(summary_flow.player_index, name),
            count = count
        })
    end
    table.sort(sorted_table, function(m1, m2) return m1.label < m2.label end)

    for _, m in pairs(sorted_table) do
        local name               = m.name
        local count              = m.count
        local item               = game.entity_prototypes[name].items_to_place_this[1].name
        local crafted            = craft_queue[item] or 0
        local in_inventory_count = inv and inv.get_item_count(item) or 0
        local in_network_count   = network and network.get_item_count(item) or 0
        local b                  = per_machine_table.add {
            type = "choose-elem-button",
            elem_type = "item",
            item = item,
            tooltip = { np("build-button-tooltip") } }
        tools.set_name_handler(b, np("summary_machine"), {
            item = item,
            count = count,
            in_inventory_count = in_inventory_count,
            in_network_count = in_network_count,
            machine_name = name
        })
        b.locked                         = true
        b.raise_hover_events             = true
        local machine_label              = per_machine_table.add {
            type = "label", caption = translations.get_entity_name(summary_flow.player_index, name) }
        machine_label.style.right_margin = 10

        local count_label, inv_label     = get_summary_labels(count, in_inventory_count, in_network_count, crafted)

        local label                      = per_machine_table.add {
            type = "label", caption = count_label, tooltip = { np("build-used-tooltip") } }
        label.style.horizontal_align     = "center"
        label.style.width                = lwidth

        label                            = per_machine_table.add {
            type = "label", caption = inv_label, tooltip = { np("build-inventory-tooltip") } }
        label.style.horizontal_align     = "center"
        label.style.width                = lwidth

        label                            = per_machine_table.add {
            type = "label", caption = tostring(in_network_count), tooltip = { np("build-logistic-tooltip") } }
        label.style.horizontal_align     = "center"
        label.style.width                = lwidth
    end
end

---@param g Graph
local function update_machines(g)
    local player = g.player
    local frame = player.gui.screen[product_panel_name]
    if not frame then return end

    local setup_flow = tools.get_child(frame, "setup_flow")
    local summary_flow = tools.get_child(frame, "summary_flow")
    if setup_flow and summary_flow then
        product_panel.update_machine_panel(g, setup_flow, summary_flow)
    end
end

tools.on_event(defines.events.on_player_crafted_item,
    ---@param e EventData.on_player_crafted_item
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        if e.recipe and vars.current_craft_recipe == e.recipe.name then
            graph.deferred_update(player, { update_product_list = true })
        end
    end)

---@param player LuaPlayer
---@param item string
---@param count integer?
function product_panel.craft_machine(player, item, count)
    local recipes = game.get_filtered_recipe_prototypes { { filter = "has-product-item",
        elem_filters = { { filter = "name", name = item } } } }

    if string.find(player.surface.name, commons.surface_prefix_filter) then
        gutils.exit(player)
    end
    if not count then
        count = 1
    end
    if #recipes > 0 then
        for name in pairs(recipes) do
            local craft_count = player.begin_crafting { recipe = name, count = count }
            local vars = tools.get_vars(player)
            vars.current_craft_recipe = name
            if craft_count > 0 then
                break
            end
        end
    end
end

local logistic_request_timeout = 60 * 60

---@param player LuaPlayer
---@param notcreate boolean?
---@return {[string]:LogisticRequest} ?
function product_panel.get_request_table(player, notcreate)
    local vars = tools.get_vars(player)
    local logistic_request_table = vars.logistic_request_table
    if not logistic_request_table then
        if notcreate then return nil end
        logistic_request_table = {}
        vars.logistic_request_table = logistic_request_table
    end
    return logistic_request_table
end

---@class LogisticRequest
---@field slot_index integer
---@field item string
---@field total_count integer
---@field has_value boolean
---@field min integer?
---@field max integer?

---@param player LuaPlayer
---@param item string
---@param total_count integer
function product_panel.request_items(player, item, total_count)
    local request_table = product_panel.get_request_table(player)
    ---@cast request_table -nil
    local current = request_table[item]

    if not player.character then return end

    local vars = tools.get_vars(player)
    vars.logistic_request_start = game.tick
    if current then
        current.total_count = total_count
        player.set_personal_logistic_slot(current.slot_index,
            {
                name = item,
                min = current.total_count,
                max = current.total_count
            })
        return
    end

    local slot_index = 1
    for i = 1, player.character.request_slot_count + 1 do
        local slot = player.get_personal_logistic_slot(i)
        if slot.name == nil or slot.name == item then
            slot_index = i
            break
        end
    end

    local slot = player.get_personal_logistic_slot(slot_index)

    ---@type LogisticRequest
    local current = {
        item = item,
        total_count = total_count,
        slot_index = slot_index,
        has_value = slot.name ~= nil,
        min = slot and slot.min,
        max = slot and slot.max
    }
    request_table[item] = current
    player.set_personal_logistic_slot(current.slot_index, { name = item, min = current.total_count, max = current.total_count })
end

local function clear_logistic_slot(player, request)
    if not request.has_value then
        player.clear_personal_logistic_slot(request.slot_index)
    else
        player.set_personal_logistic_slot(request.slot_index,
            {
                name = request.item,
                min = request.min,
                max = request.max
            })
    end
end

---@param player LuaPlayer
function product_panel.clear_requests(player)
    local vars = tools.get_vars(player)
    local request_table = product_panel.get_request_table(player, true)
    if not request_table then
        return
    end

    for _, request in pairs(request_table) do
        clear_logistic_slot(player, request)
    end
    vars.logistic_request_table = nil
    vars.logistic_request_start = nil
    graph.deferred_update(player, { update_product_list = true })
end

tools.on_event(defines.events.on_player_main_inventory_changed,

    ---@param e EventData.on_player_main_inventory_changed
    function(e)
        if not e.player_index then return end
        ---@type LuaPlayer
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)

        local start = vars.logistic_request_start
        if not start then return end
        local tick = game.tick
        if tick - start > logistic_request_timeout then
            product_panel.clear_requests(player)
        else
            local request_table = product_panel.get_request_table(player, true)
            if not request_table then return end

            for _, request in pairs(request_table) do
                local inv = player.character.get_main_inventory()
                if inv then
                    local current_count = inv.get_item_count(request.item)
                    if current_count >= request.total_count then
                        clear_logistic_slot(player, request)
                        request_table[request.item] = nil
                        if not next(request_table) then
                            vars.logistic_request_table = nil
                            vars.logistic_request_start = nil
                            graph.deferred_update(player, { update_product_list = true })
                        end
                    end
                end
            end
        end
    end
)

tools.on_named_event(np("summary_machine"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local item = e.element.tags.item --[[@as string]]
        local player = game.players[e.player_index]
        if e.alt then return end
        if not (e.button ~= defines.mouse_button_type.left or e.control or e.shift) then
            product_panel.craft_machine(player, item)
        elseif not (e.button ~= defines.mouse_button_type.left or not e.control or e.shift) then
            local count                        = e.element.tags.count --[[@as integer]]
            local inv, network, crafting_queue = get_inventories(player)

            local in_inventory_count           = inv and inv.get_item_count(item) or 0
            local in_network_count             = network and network.get_item_count(item) or 0
            local crafted                      = crafting_queue[item] or 0
            count                              = count - in_inventory_count - in_network_count - crafted
            if count > 0 then
                product_panel.craft_machine(player, item, count)
            end
        elseif not (e.button ~= defines.mouse_button_type.left or e.control or not e.shift) then
            local count                        = e.element.tags.count --[[@as integer]]
            local inv, network, crafting_queue = get_inventories(player)
            local in_inventory_count           = inv and inv.get_item_count(item) or 0
            local in_network_count             = network and network.get_item_count(item) or 0
            count                              = math.min(count - in_inventory_count, in_network_count) + in_inventory_count
            if count > 0 then
                product_panel.request_items(player, item, count)
            end
        end
        graph.deferred_update(player, { update_product_list = true })
    end)


tools.on_named_event(np("summary_machine"), defines.events.on_gui_hover,
    ---@param e EventData.on_gui_hover
    function(e)
        if not e.element.valid then return end
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        local tags = e.element.tags
        local machine_name = tags.machine_name --[[@as string]]

        if not machine_name then return end

        local parts = { "" }
        local proto = game.entity_prototypes[machine_name]
        if proto then
            parts = product_panel.create_parts_tooltip(player, proto)
            e.element.tooltip = { np("build-button-tooltip_hover"), parts }
        end
    end)

tools.on_named_event(np("recipe_detail"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end
        if e.button == defines.mouse_button_type.left then
            if not (e.shift or not e.control or e.alt) then
                local element = e.element
                local player = game.players[e.player_index]
                if not element or not element.valid then return end

                local recipe_name = element.tags.recipe_name --[[@as string]]
                if not recipe_name then return end
                gutils.move_to_recipe(player, recipe_name, e.control)

                local g = gutils.get_graph(player)
                drawing.draw_target(g, g.recipes[recipe_name])
            end
        elseif e.button == defines.mouse_button_type.right then
            local player = game.players[e.player_index]
            local element = e.element
            if not element.valid then return end

            local recipe_name = element.tags.recipe_name --[[@as string]]
            local g = gutils.get_graph(player)
            recipe_selection.open(g, nil, g.recipes[recipe_name])
        end
    end)

tools.on_named_event(np("open_product"), defines.events.on_gui_click,

    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end
        if not (e.button ~= defines.mouse_button_type.right or e.shift or e.control or e.alt) then
            local element = e.element
            local player = game.players[e.player_index]
            if not element or not element.valid then return end

            local recipe_name = element.tags.recipe_name --[[@as string]]
            local product_name = element.tags.product_name --[[@as string]]
            if not recipe_name or not product_name then return end

            local g = gutils.get_graph(player)
            recipe_selection.open(g, g.products[product_name], g.recipes[recipe_name])
        elseif not (e.button ~= defines.mouse_button_type.left or e.shift or e.control or e.alt) then
        end
    end)

---@param player LuaPlayer
---@param machine_entity LuaEntityPrototype
---@return table
function product_panel.create_parts_tooltip(player, machine_entity)
    local parts = { "" }
    if machine_entity then
        local machine_item = machine_entity.items_to_place_this[1]
        if machine_item then
            local machine_recipes =
                game.get_filtered_recipe_prototypes { {
                    filter = "has-product-item",
                    elem_filters = { { filter = "name", name = machine_item } } } }

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
        end
    end
    return parts
end

tools.on_named_event(np("machine"), defines.events.on_gui_hover,
    ---@param e EventData.on_gui_hover
    function(e)
        local element = e.element
        if not element or not element.valid then return end

        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        local recipe_name = element.tags.recipe_name --[[@as string]]
        if not recipe_name then return end

        local grecipe = g.recipes[recipe_name]
        local machine = grecipe.machine

        local parts = { "" }
        if machine then
            parts = product_panel.create_parts_tooltip(player, machine.machine)
        end

        if machine then
            e.element.tooltip = { np("machine-tooltip"), { "", tools.fround(machine.count), " x ", machine.machine.localised_name }, parts }
        else
            e.element.tooltip = { np("machine-tooltip"), "" }
        end
    end)

tools.on_named_event(np("machine"), defines.events.on_gui_click,

    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end

        local player = game.players[e.player_index]
        if e.button == defines.mouse_button_type.left then
            local element = e.element
            if not element or not element.valid then return end

            local g = gutils.get_graph(player)
            local recipe_name = element.tags.recipe_name --[[@as string]]
            if not recipe_name then return end
            local grecipe = g.recipes[recipe_name]

            if e.control then
                local machine = grecipe.machine
                if not machine then return end

                if string.find(player.surface.name, commons.surface_prefix_filter) then
                    gutils.exit(player)
                end

                local bp_entity = {

                    entity_number = 1,
                    name = machine.machine.name,
                    position = { 0.5, 0.5 },
                    recipe = recipe_name
                }
                if machine.modules then
                    bp_entity.items = {}
                    for _, module in pairs(machine.modules) do
                        bp_entity.items[module.name] = (bp_entity.items[module.name] or 0) + 1
                    end
                end

                local cursor_stack = player.cursor_stack
                if not cursor_stack then return end

                cursor_stack.clear()
                cursor_stack.set_stack { name = "blueprint", count = 1 }
                cursor_stack.set_blueprint_entities { bp_entity }
                player.cursor_stack_temporary = true
            elseif e.shift then
                ---@type ProductionMachine
                local machine = grecipe.machine
                if not machine or not machine.machine then return end
                local item = machine.machine.items_to_place_this[1].name

                product_panel.craft_machine(player, item)
            else
                msettings_panel.create(e.player_index, grecipe)
            end
        elseif e.button == defines.mouse_button_type.right then
            if not (e.control or e.shift) then
                if string.find(player.surface.name, commons.surface_prefix_filter) then
                    gutils.exit(player)
                end

                local g = gutils.get_graph(player)
                local recipe_name = e.element.tags.recipe_name --[[@as string]]
                if not recipe_name then return end
                local grecipe = g.recipes[recipe_name]

                local machine = grecipe.machine
                if not machine or not machine.machine then return end

                local surface = player.surface
                local entities = surface.find_entities_filtered { name = machine.machine.name, position = player.position, radius = 1000 }
                local count = 0
                if #entities > 0 then
                    local color = { 0, 1, 1 }
                    for _, entity in pairs(entities) do
                        local crecipe = entity.get_recipe() or (entity.type == "furnace" and entity.previous_recipe)
                        if crecipe and crecipe.name == recipe_name then
                            local w = entity.tile_width / 2
                            local h = entity.tile_height / 2
                            rendering.draw_rectangle {
                                surface = surface,
                                color = color,
                                left_top = entity,
                                right_bottom = entity,
                                left_top_offset = { -w, -h },
                                right_bottom_offset = { w, h },
                                width = 2, time_to_live = 2 * 60
                            }
                            count = count + 1
                        end
                    end
                end
                player.print({ np("machine_report"), count })
            end
        end
    end)

-- React to production computation
tools.register_user_event(commons.production_compute_event, function(data)
    if not data.structure_change then
        update_machines(data.g)
    end
end)

tools.on_named_event(np("mini_maxi"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[product_panel_name]
        if not frame then return end

        local vars = tools.get_vars(player)
        local is_mini = vars[min_name]

        product_frame = tools.get_child(frame, "product_frame")
        if not product_frame then return end

        if is_mini then
            product_frame.visible = true
        else
            product_frame.visible = false
        end

        local button = tools.get_child(frame, "mini_maxi")
        is_mini = not is_mini
        if button then
            button.sprite = not is_mini and commons.prefix .. "_mini_white" or commons.prefix .. "_maxi_white"
            button.hovered_sprite = not is_mini and commons.prefix .. "_mini_black" or commons.prefix .. "_maxi_black"
        end

        vars[min_name] = is_mini
    end
)

tools.on_named_event(np("error-unlock-product"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[product_panel_name]
        if not frame then return end

        local g = gutils.get_graph(player)
        local product_name = e.element.tags.product_name --[[@as string]]

        if g.iovalues[product_name] == true then
            g.iovalues[product_name] = nil
        else
            g.iovalues[product_name] = true
        end
        gutils.fire_production_data_change(g)
    end)

tools.on_named_event(np("unselect"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[product_panel_name]
        if not frame then return end

        local g = gutils.get_graph(player)
        for _, grecipe in pairs(g.recipes) do
            if not grecipe.machine or grecipe.machine.count == 0 then
                g.selection[grecipe.name] = nil
            end
        end
        graph.refresh(g.player)
        gutils.fire_selection_change(g)
    end)

tools.on_gui_click(np("goto"),
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local recipe_name = e.element.tags.recipe_name --[[@as string]]
        local g = gutils.get_graph(player)
        local recipe = g.recipes[recipe_name]
        if not recipe or not recipe.visible then
            return
        end
        local position = gutils.get_recipe_position(g, recipe)
        drawing.draw_target(g, recipe)
        if e.control then
            player.teleport(position, g.surface, false)
        else
            gutils.move_view(player, position)
        end
        product_panel.close(player)
    end)

msettings_panel.create_product_line = create_product_line

return product_panel

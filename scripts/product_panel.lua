local luautil = require("__core__/lualib/util")


local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local drawing = require("scripts.drawing")

local recipe_selection = require("scripts.recipe_selection")
local production = require("scripts.production")

local product_panel = {}
local prefix = commons.prefix

local label_style_name = prefix .. "_count_label_bottom"
local label_style_top = prefix .. "_count_label_top"

local default_button_style = prefix .. "_button_default"
local default_button_label_style = prefix .. "_count_label_bottom"

local arrow_sprite = prefix .. "_arrow"

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
-- tools.add_panel_name(product_panel_name)

local round_digit = 2

---@param value number
local function fround(value)
    if abs(value) <= math_precision then
        return 0
    end
    local precision = math.pow(10, math.floor(0.5 + math.log(math.abs(value), 10)) - round_digit)
    value = math.floor(value / precision) * precision
    return value
end


---@param g Graph
local function get_production_title(g)
    if not g.production_failed or type(g.production_failed) ~= "string" then
        return { np("title") }
    else
        return { "", { np("failed-title") }, { np("failure_" .. g.production_failed) } }
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

    ---@type Params.create_standard_panel
    local params = {
        panel_name           = product_panel_name,
        title                = get_production_title(g),
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = np("close_button_tooltip"),
    }

    local frame = tools.create_standard_panel(player, params)
    frame.style.maximal_height = 800
    frame.style.maximal_height = 800

    local inner_flow = frame.add { type = "flow", direction = "horizontal" }
    local product_frame = inner_flow.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    product_frame.style.vertically_stretchable = true
    product_frame.style.horizontally_stretchable = true
    product_frame.add { type = "scroll-pane", horizontal_scroll_policy = "never", name = "sroll-table" }
    product_panel.create_product_tables(player)

    local machine_frame = inner_flow.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    machine_frame.style.minimal_width = 200
    machine_frame.style.vertically_stretchable = true
    local machine_scroll = machine_frame.add { type = "scroll-pane", horizontal_scroll_policy = "never" }
    local machine_flow = machine_scroll.add { type = "table", column_count = 2, name = "machine_container" }
    product_panel.update_machine_panel(g, machine_flow)

    local vars = tools.get_vars(player)
    local location = vars[location_name]
    if location then
        frame.location = location
    else
        frame.force_auto_center()
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

        local is_computed
        if not value and g.product_outputs then
            value = g.product_outputs[product_name]
            is_computed = true
        end

        ---@cast value number
        if value and math.abs(value) > math_precision then
            value = fround(value)
            if value < 0 and is_computed then
                caption = mark .. "[color=cyan]" .. luautil.format_number(-value, true) .. "[/color]"
            elseif is_computed then
                caption = mark .. "[color=orange]" .. luautil.format_number(value, true) .. "[/color]"
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

---@param g Graph
---@param product_name string
---@param qtlabel LuaGuiElement
---@return number?
function set_effective_value(g, product_name, qtlabel)
    local product_effective = g.product_effective
    if not qtlabel or not product_effective then
        return nil
    end

    local value = product_effective[product_name]
    local caption

    ---@cast value number
    if value and math.abs(value) > math_precision then
        value = fround(value)
        caption = "x [color=yellow]" .. luautil.format_number(value, true) .. "[/color]"
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

    local scroll = tools.get_child(frame, "sroll-table")
    if not scroll then return end

    scroll.clear()

    ---@param title LocalisedString?
    local function add_line(title)
        gutils.add_line(scroll, title)
    end

    local g = gutils.get_graph(player)
    local inputs, outputs, intermediates = gutils.get_product_flow(g)

    local column_count = 3
    local column_width = 120
    local product_button_tooltip = { np("product_button_tooltip") }

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
        local production_only = products == inputs
        for _, product in pairs(list) do
            local product_name = product.product.name
            local pline = product_table.add { type = "flow", direction = "horizontal" }

            local b = gutils.create_product_button(pline, product_name, "product_button")
            b.tooltip = product_button_tooltip

            tools.set_name_handler(b, np("product"), { product_name = product_name, production_only = production_only })

            local qtlabel = b.add { type = "label", style = label_style_name, name = "label", ignored_by_interaction = true }
            local value = set_output_value(g, product_name, qtlabel)


            b.style.size = 36
            b.style.vertical_align = "top"

            local vinput = pline.add { type = "flow", direction = "vertical", name = "vinput" }
            local label = vinput.add { type = "label", caption = product.label }

            local elabel = pline.add { type = "label", name = "elabel" }
            elabel.style.width = 50
            elabel.style.horizontal_align = "right"
            elabel.style.right_margin = 10
            local evalue = set_effective_value(g, product_name, elabel)

            if g.iovalues[product_name] then
                b.style = red_button
            else
                value = value or evalue
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

    add_line({ np("inputs") })
    create_product_table(inputs, "inputs")

    add_line({ np("outputs") })
    create_product_table(outputs, "outputs")

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
                local evalue = set_effective_value(g, product_name, line.elabel)
                if g.iovalues[product_name] then
                    b.style = red_button
                else
                    value = value or evalue
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

        local product_name = e.element.tags.product_name
        if not product_name then return end

        local production_only = e.element.tags.production_only --[[@as boolean]]

        if e.button == defines.mouse_button_type.right then
            recipe_selection.open(g, g.products[product_name], nil, production_only)
        elseif e.control then
            get_vinput(e.element.parent)
            if g.iovalues[product_name] == true then
                g.iovalues[product_name] = nil
            else
                g.iovalues[product_name] = true
            end
        else
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
        if e.element.name == np("qty") then
            e.element.parent.destroy()
        end
    end)

-- React to production computation
tools.register_user_event(commons.production_compute_event, function(data)
    local player = data.g.player
    if not player.gui.screen[product_panel_name] then return end
    if not data.structure_change then
        update_products(data.g)
    else
        product_panel.close(data.g.player)
        product_panel.create(data.g.player.index)
    end
end)


---@param g Graph
---@param container LuaGuiElement
function product_panel.update_machine_panel(g, container)
    container.clear()
    if not g.selection then return end

    ---@type ProductionMachine[]
    local machines = {}
    for _, grecipe in pairs(g.selection) do
        local machine = grecipe.machine
        if machine and machine.count and abs(machine.count) > math_precision then
            table.insert(machines, machine)
        end
    end
    if #machines == 0 then return end

    table.sort(machines, function(m1, m2) return m1.grecipe.order < m2.grecipe.order end)

    local index = 1
    for _, machine in pairs(machines) do
        local col1 = container.add { type = "flow", direction = "horizontal" }

        local caption
        if machine.count > 1000 then
            caption = string.format("%.0f", math.ceil(machine.count))
        else
            caption = string.format("%.1f", math.ceil(machine.count * 10) / 10)
        end

        local b = col1.add { type = "choose-elem-button", elem_type = "entity", entity = machine.machine.name, style = green_button }
        b.locked = true
        tools.set_name_handler(b, np("machine"), { recipe_name = machine.recipe.name })
        index = index + 1
        local label = b.add { type = "label", style = default_button_label_style,
            caption = caption, ignored_by_interaction = true }

        local frecipe = col1.add { type = "choose-elem-button", elem_type = "recipe", recipe = machine.name, style = recipe_button_style }
        frecipe.style.right_margin = 5
        frecipe.locked = true
        tools.set_name_handler(frecipe, np("goto_recipe"), { recipe_name = machine.name })

        for _, ingredient in pairs(machine.recipe.ingredients) do
            local type = ingredient.type
            b = col1.add { type = "choose-elem-button", elem_type = type, item = ingredient.name, fluid = ingredient.name, style = ingredient_button_style }
            b.locked = true
            tools.set_name_handler(b, np("open_product"), { recipe_name = machine.name, product_name = type .. "/" .. ingredient.name })

            local amount = ingredient.amount * machine.craft_per_s * machine.count / (1 + machine.productivity)
            amount = fround(amount)
            b.add { type = "label", style = default_button_label_style,
                caption = tostring(amount), ignored_by_interaction = true }
        end

        local col2 = container.add { type = "flow", direction = "horizontal" }
        local sep = col2.add { type = "sprite", sprite = arrow_sprite }
        sep.style.left_margin = 5
        sep.style.top_margin = 10
        sep.style.right_margin = 5

        for _, product in pairs(machine.recipe.products) do
            local type = product.type
            b = col2.add { type = "choose-elem-button", elem_type = type, item = product.name, fluid = product.name, style = product_button_style }
            b.locked = true
            tools.set_name_handler(b, np("open_product"), { recipe_name = machine.name, product_name = type .. "/" .. product.name })

            local amount
            if product.amount_min then
                amount = (product.amount_min + product.amount_max) / 2
            else
                amount = product.amount
            end
            amount = amount * machine.craft_per_s * machine.count
            amount = fround(amount)
            b.add { type = "label", style = default_button_label_style,
                caption = tostring(amount), ignored_by_interaction = true }
        end
    end
end

---@param g Graph
local function update_machines(g)
    local player = g.player
    local frame = player.gui.screen[product_panel_name]
    if not frame then return end

    local container = tools.get_child(frame, "machine_container")
    if container then
        product_panel.update_machine_panel(g, container)
    end
end

tools.on_named_event(np("goto_recipe"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end
        if not e.shift and not e.control then
            local element = e.element
            local player = game.players[e.player_index]
            if not element or not element.valid then return end

            local recipe_name = element.tags.recipe_name --[[@as string]]
            if not recipe_name then return end
            product_panel.close(player)
            gutils.move_to_recipe(player, recipe_name, e.control)

            local g = gutils.get_graph(player)
            drawing.draw_target(g, g.recipes[recipe_name])
        elseif e.control then
            
        end
    end)

tools.on_named_event(np("open_product"), defines.events.on_gui_click,

    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end
        if not e.shift and not e.control then
            local element = e.element
            local player = game.players[e.player_index]
            if not element or not element.valid then return end

            local recipe_name = element.tags.recipe_name --[[@as string]]
            local product_name = element.tags.product_name --[[@as string]]
            if not recipe_name or not product_name then return end

            local g = gutils.get_graph(player)
            recipe_selection.open(g, g.products[product_name], g.recipes[recipe_name])
        end
    end)

tools.on_named_event(np("machine"), defines.events.on_gui_click,

    ---@param e EventData.on_gui_click
    function(e)
        if e.alt then return end
        if not e.control and not e.shift then
            local element = e.element
            local player = game.players[e.player_index]
            if not element or not element.valid then return end

            local g = gutils.get_graph(player)
            local recipe_name = element.tags.recipe_name --[[@as string]]
            if not recipe_name then return end

            local grecipe = g.recipes[recipe_name]
            local machine = grecipe.machine
            if not machine then return end

            local bp_entity = {

                entity_number = 1,
                name = machine.machine.name,
                position = { 0.5, 0.5 },
                recipe = recipe_name
            }
            if machine.modules then
                bp_entity.items = {}
                for _, module in pairs(machine.modules) do
                    bp_entity[module.name] = (bp_entity[module.name] or 0) + 1
                end
            end

            local cursor_stack = player.cursor_stack
            if not cursor_stack then return end

            cursor_stack.clear()
            cursor_stack.set_stack { name = "blueprint", count = 1 }
            cursor_stack.set_blueprint_entities { bp_entity }
            player.cursor_stack_temporary = true
        end
    end)

-- React to production computation
tools.register_user_event(commons.production_compute_event, function(data)
    if not data.structure_change then
        update_machines(data.g)
    end
end)

return product_panel

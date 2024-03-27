local luautil = require("__core__/lualib/util")


local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
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

local function np(name)
    return prefix .. "-product-panel." .. name
end

local product_panel_name = np("frame")
local input_qty_name = np("frame")
local location_name = np("location")
tools.add_panel_name(product_panel_name)

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

    if (player.gui.screen[product_panel_name]) then
        product_panel.close(player)
        return
    end

    ---@type LuaGuiElement
    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = product_panel_name
    }
    frame.style.maximal_height = 800

    local title = get_production_title(g)
    local titleflow = frame.add { type = "flow" }
    titleflow.add {
        type = "label",
        caption = title,
        style = "frame_title",
        ignored_by_interaction = true,
        name = "title"
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
    local machine_flow = machine_scroll.add { type = "table", column_count = 1, name = "machine_container" }
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
function product_panel.set_output_value(g, product_name, qtlabel)
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
        if value then
            qtlabel.parent.tooltip = tools.comma_value(value)
        end
    else
        qtlabel.caption = ""
        qtlabel.parent.tooltip = ""
    end
end

local set_output_value = product_panel.set_output_value

---@param g Graph
---@param product_name string
---@param qtlabel LuaGuiElement
function product_panel.set_effective_value(g, product_name, qtlabel)
    local product_effective = g.product_effective
    if not qtlabel or not product_effective then
        return
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
    else
        qtlabel.caption = ""
    end
end

local set_effective_value = product_panel.set_effective_value

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
            local b = pline.add { type = "sprite-button", sprite = product_name, name = "product_button" }
            tools.set_name_handler(b, np("product"), { product_name = product_name })
            b.style.size = 36
            b.style.vertical_align = "top"

            local qtlabel = b.add { type = "label", style = label_style_name, name = "label", ignored_by_interaction = true }
            set_output_value(g, product_name, qtlabel)

            local vinput = pline.add { type = "flow", direction = "vertical", name = "vinput" }
            local label = vinput.add { type = "label", caption = product.label }

            local elabel = pline.add { type = "label", name = "elabel" }
            elabel.style.width = 50
            elabel.style.horizontal_align = "right"
            elabel.style.right_margin = 10
            set_effective_value(g, product_name, elabel)

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
                set_output_value(g, product_name, b.label)

                set_effective_value(g, product_name, line.elabel)
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
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)

        if not e.element.valid then return end

        local product_name = e.element.tags.product_name
        if not product_name then return end

        if e.shift then
            recipe_selection.open(player, g, g.products[product_name], nil)
            product_panel.close(player)
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
        product_panel.fire_production_data_change(g)
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
        product_panel.fire_production_data_change(g)
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

-- Fire production change
function product_panel.fire_production_data_change(g)
    tools.fire_user_event(commons.production_data_change_event, { g = g })
end

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

    for _, machine in pairs(machines) do
        local line = container.add { type = "flow", direction = "horizontal" }

        local b = line.add { type = "sprite-button", sprite = "entity/" .. machine.machine.name, style = default_button_style }
        local label = b.add { type = "label", style = default_button_label_style,
            caption = tostring(math.ceil(machine.count)), ignored_by_interaction = true }

        local frecipe = line.add { type = "sprite-button", sprite = "recipe/" .. machine.name, style = default_button_style }
        frecipe.style.right_margin = 5

        for _, ingredient in pairs(machine.recipe.ingredients) do
            b = line.add { type = "sprite-button",
                sprite = ingredient.type .. "/" .. ingredient.name,
                style = default_button_style }

            local amount = ingredient.amount * machine.craft_per_s * machine.count
            amount = fround(amount)
            label = b.add { type = "label", style = default_button_label_style,
                caption = "[color=cyan]" .. tostring(amount) .. "[/color]", ignored_by_interaction = true }
        end

        local sep = line.add {type="sprite", sprite=arrow_sprite}
        sep.style.left_margin = 5
        sep.style.top_margin = 5
        sep.style.right_margin = 5

        for _, product in pairs(machine.recipe.products) do
            b = line.add { type = "sprite-button",
                sprite = product.type .. "/" .. product.name,
                style = default_button_style }

            local amount
            if product.amount_min then
                amount = (product.amount_min + product.amount_max) / 2
            else
                amount = product.amount
            end
            amount = amount * machine.craft_per_s * machine.count
            amount = fround(amount)
            label = b.add { type = "label", style = default_button_label_style,
                caption = "[color=orange]" .. tostring(amount) .. "[/color]", ignored_by_interaction = true }
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

-- React to production computation
tools.register_user_event(commons.production_compute_event, function(data)
    if not data.structure_change then
        update_machines(data.g)
    end
end)

return product_panel

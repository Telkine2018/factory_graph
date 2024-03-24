local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local recipe_selection = require("scripts.recipe_selection")

local flow_panel = {}
local prefix = commons.prefix

local label_style_name = commons.prefix .. "_count_label_bottom"

local function np(name)
    return prefix .. "-flow-panel." .. name
end

local flow_panel_name = np("frame")
local input_qty_name = np("frame")
local location_name = np("location")

tools.add_panel_name(flow_panel_name)

---@param player_index integer
function flow_panel.create(player_index)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)

    if (player.gui.screen[flow_panel_name]) then
        flow_panel.close(player)
        return
    end

    ---@type LuaGuiElement
    local frame = player.gui.screen.add {
        type = "frame",
        direction = 'vertical',
        name = flow_panel_name
    }
    frame.style.maximal_height = 800

    local titleflow = frame.add { type = "flow" }
    titleflow.add {
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

    local inner_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    inner_frame.style.horizontally_stretchable = true

    inner_frame.add { type = "scroll-pane", horizontal_scroll_policy = "never", name = "sroll-table" }

    flow_panel.update(player)

    local vars = tools.get_vars(player)
    local location = vars[location_name]
    if location then
        frame.location = location
    else
        frame.force_auto_center()
    end
end



function flow_panel.update(player)
    local frame = player.gui.screen[flow_panel_name]
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
    local column_width = 200

    ---@param products table<string, GProduct>
    function show_products(products)
        ---@type {product:GProduct, label:string}[]
        local list = {}
        for _, prod in pairs(products) do
            table.insert(list, { product = prod, label = gutils.get_product_name(player, prod.name) })
        end
        table.sort(list, function(e1, e2) return e1.label < e2.label end)

        local product_table = scroll.add { type = "table", column_count = column_count }
        product_table.style.cell_padding = 0
        for _, product in pairs(list) do
            local pline = product_table.add { type = "flow", direction = "horizontal" }
            local b = pline.add { type = "sprite-button", sprite = product.product.name }
            tools.set_name_handler(b, np("product"), { product_name = product.product.name })
            b.style.size = 36
            b.style.vertical_align = "top"

            qtlabel = b.add{type="label", style=label_style_name, name="label", ignored_by_interaction = true}
            local value = g.iovalues[product.product.name]
            if value == true then
                qtlabel.caption = "-"
            elseif value then
                qtlabel.caption = string.format("%.1f", value)
            elseif g.product_counts then
                value = g.product_counts[product.product.name]
                if value and math.abs(value) > 0.001 then
                    qtlabel.caption = string.format("%.1f", value)
                end
            end

            local vinput = pline.add { type = "flow", direction = "vertical", name = "vinput" }
            local label = vinput.add { type = "label", caption = product.label }
            label.style.width = column_width
        end
    end

    add_line({ np("inputs") })
    show_products(inputs)

    add_line({ np("outputs") })
    show_products(outputs)

    add_line({ np("intermediates") })
    show_products(intermediates)
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
            flow_panel.close(player)
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
                name=np("qty") }
            tools.set_name_handler(input, np("qty"), { product_name = product_name })
            input.style.maximal_width = 80
            local qty = g.iovalues[product_name]
            if type(qty) == "number" then
                input.text = tostring(qty)
            end
        end
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
        end
        g.iovalues[product_name] = value

    end)

function flow_panel.close(player)
    local frame = player.gui.screen[flow_panel_name]
    if not frame then return end

    local location = frame.location
    tools.get_vars(player)[location_name] = location
    frame.destroy()
end

tools.on_gui_click(np("close"), function(e)
    flow_panel.close(game.players[e.player_index])
end)

tools.on_event(defines.events.on_gui_confirmed, 
---@param e EventData.on_gui_confirmed
function(e)
    if e.element.name == np("qty") then
        e.element.parent.destroy()
    end
end)


return flow_panel

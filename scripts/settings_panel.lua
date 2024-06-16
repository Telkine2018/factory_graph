local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local graph = require("scripts.graph")
local gutils = require("scripts.gutils")
local colors = require("scripts.colors")

local prefix = commons.prefix

local settings_panel = {}

local function np(name)
    return prefix .. "-setting-panel." .. name
end

local settings_panel_name = np("frame ")
commons.settings_panel_name = settings_panel_name

local selected_style = "flib_slot_button_red"
local unselected_style = "flib_slot_button_default"

tools.add_panel_name(settings_panel_name)

---@param container LuaGuiElement
---@param machine_name string?
---@return LuaGuiElement
local function add_machine_button(container, machine_name)
    local b = container.add { type = "choose-elem-button", elem_type = "entity", entity = machine_name,
        elem_filters = { { filter = "type", type = "assembling-machine" }, { filter = "type", type = "furnace" } } }
    tools.set_name_handler(b, np("preferred_machines"))
    return b
end

---@param container LuaGuiElement
---@param module_name string?
---@return LuaGuiElement
local function add_module_button(container, module_name)
    local b = container.add { type = "choose-elem-button", elem_type = "item", item = module_name,
        elem_filters = { { filter = "type", type = "module" } } }
    tools.set_name_handler(b, np("preferred_modules"))
    return b
end

---@param g Graph
---@param pmachine_flow LuaGuiElement
local function set_machine_buttons(g, pmachine_flow)
    if g.preferred_machines then
        for _, machine_name in pairs(g.preferred_machines) do
            add_machine_button(pmachine_flow, machine_name)
        end
    end
    add_machine_button(pmachine_flow)
end

---@param g Graph
---@param pmodule_flow LuaGuiElement
local function set_module_buttons(g, pmodule_flow)
    if g.preferred_modules then
        for _, name in pairs(g.preferred_modules) do
            add_module_button(pmodule_flow, name)
        end
    end
    add_module_button(pmodule_flow)
end

---@param player_index integer
function settings_panel.create(player_index)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)

    if not g then return end

    if (player.gui.screen[settings_panel_name]) then
        settings_panel.close(player)
        return
    end

    ---@type Params.create_standard_panel
    local params = {
        panel_name           = settings_panel_name,
        title                = { np("title") },
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = { np("close_button_tooltip") },
        create_inner_frame   = true
    }
    local frame, inner_frame = tools.create_standard_panel(player, params)

    local flow = inner_frame.add { type = "table", column_count = 2, name = "field_table" }

    flow.add { type = "label", caption = { np("grid-size") } }
    flow.add { type = "textfield", numeric = true, text = tostring(g.grid_size), name = "grid_size" }

    flow.add { type = "label", caption = { np("show_hidden") } }
    flow.add { type = "checkbox", numeric = true, state = not not g.show_hidden, name = "show_hidden" }

    flow.add { type = "label", caption = { np("only-researched") } }
    flow.add { type = "checkbox", name = "show_only_researched", state = not not g.show_only_researched }

    flow.add { type = "label", caption = { np("layout-on-selection") } }
    flow.add { type = "checkbox", name = "layout-on-selection", state = not not g.layout_on_selection, tooltip = { np("layout_on_selection_tooltip") } }

    flow.add { type = "label", caption = { np("always_use_full_selection") } }
    flow.add { type = "checkbox", name = "always_use_full_selection", state = not not g.always_use_full_selection, tooltip = { np("always_use_full_selection_tooltip") } }

    flow.add { type = "label", caption = { np("graph_zoom_level") } }
    flow.add { type = "textfield", name = "graph_zoom_level", text = g.graph_zoom_level and tostring(g.graph_zoom_level) or 1, numeric = true, allow_decimal = true }

    flow.add { type = "label", caption = { np("world_zoom_level") } }
    flow.add { type = "textfield", name = "world_zoom_level", text = g.world_zoom_level and tostring(g.world_zoom_level) or 1, numeric = true, allow_decimal = true }

    flow.add { type = "label", caption = { np("autosave_on_graph_switching") } }
    flow.add { type = "checkbox", name = "autosave_on_graph_switching", state = not not g.autosave_on_graph_switching,
        tooltip = { np("autosave_on_graph_switching_tooltip") } }

    flow.add { type = "label", caption = { np("current_layer") } }
    local current_layer = g.current_layer
    if not current_layer then current_layer = "virtual-signal/signal-yellow" end
    local layer_signal = tools.sprite_to_signal(current_layer)
    local b = flow.add { type = "choose-elem-button", elem_type = "signal", signal = layer_signal,
        name = "current_layer", tooltip = { np("current_layer_tooltip") } }

    flow.add { type = "line" }
    flow.add { type = "line" }
    flow.add { type = "label", caption = { np("visible_layers") } }
    local visible_layers = g.visible_layers
    if not visible_layers then
        visible_layers = {}
    end
    local all_layers = {}
    for _, grecipe in pairs(g.selection) do
        if grecipe.layer then
            all_layers[grecipe.layer] = true
        end
    end
    local layer_flow = flow.add { type = "table", name = "visible_layers", column_count = 6 }
    for layer in pairs(all_layers) do
        local layer_signal = tools.sprite_to_signal(layer)
        b = layer_flow.add { type = "choose-elem-button", elem_type = "signal", signal = layer_signal, tooltip = { np("visible_layers_tooltip") } }
        b.locked = true
        tools.set_name_handler(b, np("visible_layer"))
        if visible_layers[layer] then
            b.style = selected_style
        else
            b.style = unselected_style
        end
    end
    flow.add { type = "line" }
    flow.add { type = "line" }

    flow.add { type = "label", caption = { np("preferred_machines") } }
    local pmachine_flow = flow.add { type = "table", direction = "horizontal", name = "preferred_machines", column_count = 6 }
    set_machine_buttons(g, pmachine_flow)

    flow.add { type = "label", caption = { np("preferred_modules") } }
    local pmodule_flow = flow.add { type = "flow", direction = "horizontal", name = "preferred_modules" }
    set_module_buttons(g, pmodule_flow)

    flow.add { type = "label", caption = { np("preferred_beacon") } }
    flow.add { type = "choose-elem-button", elem_type = "entity", elem_filters = { { filter = "type", type = "beacon" } },
        name = "preferred_beacon", entity = g.preferred_beacon }

    flow.add { type = "label", caption = { np("preferred_beacon_count") } }
    flow.add { type = "textfield", numeric = true, text = tostring(g.preferred_beacon_count or 0),
        name = "preferred_beacon_count" }

    local bpanel = frame.add { type = "flow", direction = "horizontal" }
    local b = bpanel.add { type = "button", caption = { np("save") } }
    tools.set_name_handler(b, np("save"))

    b = bpanel.add { type = "button", caption = { np("cancel") } }
    tools.set_name_handler(b, np("cancel"))

    b = bpanel.add { type = "button", caption = { np("copy") }, tooltip= {np("copy-tooltip")} }
    tools.set_name_handler(b, np("copy"))

    b = bpanel.add { type = "button", caption = { np("paste") }, tooltip= {np("paste-tooltip")} }
    tools.set_name_handler(b, np("paste"))


    frame.force_auto_center()
end

---@param e EventData.on_gui_click
---@param add_func fun(LuaGuiElement)
local function blist_on_click(e, add_func)
    if e.button == defines.mouse_button_type.left and e.control then
        local index = e.element.get_index_in_parent()
        local parent = e.element.parent
        if parent then
            add_func(parent)
            for i = #parent.children, index + 1, -1 do
                parent.children[i].elem_value = parent.children[i - 1].elem_value
            end
            e.element.elem_value = nil
        end
    end
end

---@param e EventData.on_gui_elem_changed
---@param add_func fun(LuaGuiElement)
local function blist_on_gui_elem_changed(e, add_func)
    local parent = e.element.parent
    if parent then
        local index = e.element.get_index_in_parent()
        if index == #parent.children then
            if e.element.elem_value then
                add_func(parent)
            end
        elseif not e.element.elem_value then
            e.element.destroy()
        end
    end
end

---@param button_table any
---@return string[]
local function blist_values(button_table)
    local values = {}
    for _, button in pairs(button_table.children) do
        local elem_value = button.elem_value
        if elem_value then
            table.insert(values, elem_value)
        end
    end
    return values
end

tools.on_named_event(np("preferred_machines"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        blist_on_click(e, add_machine_button)
    end)

tools.on_named_event(np("preferred_machines"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
    function(e)
        blist_on_gui_elem_changed(e, add_machine_button)
    end)

tools.on_named_event(np("preferred_modules"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        blist_on_click(e, add_module_button)
    end)

tools.on_named_event(np("preferred_modules"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
    function(e)
        blist_on_gui_elem_changed(e, add_module_button)
    end)

tools.on_named_event(np("close"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        tools.close_panel(game.players[e.player_index], settings_panel_name)
    end
)

---@param player LuaPlayer
---@param frame LuaGuiElement
local function save(player, frame)
    local field_table = tools.get_child(frame, "field_table")
    if not field_table then return end

    local g = gutils.get_graph(player)

    local grid_size_value = tonumber(field_table.grid_size.text)
    if not grid_size_value or grid_size_value < 2 or grid_size_value > 10 then
        player.print({ np("invalid_grid_size") })
        return
    end

    g.always_use_full_selection = field_table.always_use_full_selection.state
    g.autosave_on_graph_switching = field_table.autosave_on_graph_switching.state
    g.layout_on_selection = field_table["layout-on-selection"].state
    g.graph_zoom_level = tonumber(field_table.graph_zoom_level.text)
    g.world_zoom_level = tonumber(field_table.world_zoom_level.text)
    g.show_hidden = field_table.show_hidden.state
    g.show_only_researched = field_table.show_only_researched.state
    if grid_size_value ~= g.grid_size then
        g.grid_size = grid_size_value
        graph.refresh(player)
    end

    local signal = field_table.current_layer.elem_value --[[@as SignalID]]
    g.current_layer = tools.signal_to_sprite(signal)
    g.preferred_machines = blist_values(field_table.preferred_machines)
    g.preferred_modules = blist_values(field_table.preferred_modules)
    g.preferred_beacon = field_table.preferred_beacon.elem_value --[[@as string]]
    g.preferred_beacon_count = tonumber(field_table.preferred_beacon_count.text) or 0

    local visible_layers_flow = field_table.visible_layers
    local visible_layers = {}
    if g.current_layer and g.visibility == commons.visibility_layers then
        visible_layers[g.current_layer] = true
    end
    for i = 1, #visible_layers_flow.children do
        local b = visible_layers_flow.children[i]
        local signal = b.elem_value --[[@as SignalID]]
        if signal and b.style.name == selected_style then
            local sprite = tools.signal_to_sprite(signal)
            if sprite then
                visible_layers[sprite] = true
            end
        end
    end
    local layer_change
    if g.visibility == commons.visibility_layers then
        if g.visible_layers then
            if table_size(g.visible_layers) ~= table_size(visible_layers) then
                layer_change = true
            else
                for layer in pairs(visible_layers) do
                    if not g.visible_layers[layer] then
                        layer_change = true
                        break
                    end
                end
            end
        else
            layer_change = true
        end
    end

    g.visible_layers = visible_layers
    if layer_change then
        graph.deferred_update(player, { do_layout = true, center_on_graph = true })
        gutils.fire_selection_change(g)
    else
        gutils.fire_production_data_change(g)
    end
    frame.destroy()
end

tools.on_named_event(np("save"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[settings_panel_name]

        if not frame then return end
        save(player, frame)
    end
)

tools.on_named_event(np("cancel"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        tools.close_panel(game.players[e.player_index], settings_panel_name)
    end
)

tools.on_named_event(np("copy"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[settings_panel_name]
        if not frame then return end

        local field_table = tools.get_child(frame, "field_table")
        if not field_table then return end

        ---@type Graph
        local copy = {}
        copy.preferred_machines = blist_values(field_table.preferred_machines)
        copy.preferred_modules = blist_values(field_table.preferred_modules)
        copy.preferred_beacon = field_table.preferred_beacon.elem_value --[[@as string]]
        copy.preferred_beacon_count = tonumber(field_table.preferred_beacon_count.text) or 0
        local vars = tools.get_vars(player)
        vars.copy_g = copy
    end
)

tools.on_named_event(np("paste"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[settings_panel_name]
        if not frame then return end

        local field_table = tools.get_child(frame, "field_table")
        if not field_table then return end

        ---@type Graph
        local vars = tools.get_vars(player)
        local copy = vars.copy_g 
        if not copy then return end

        local g = gutils.get_graph(player)
        if not g then return end

        field_table.preferred_machines.clear()
        set_machine_buttons(copy, field_table.preferred_machines)

        field_table.preferred_modules.clear()
        set_module_buttons(copy, field_table.preferred_modules)

        field_table.preferred_beacon.elem_value = copy.preferred_beacon
        field_table.preferred_beacon_count.text =  copy.preferred_beacon_count and tostring(copy.preferred_beacon_count) or ""
    end
)


tools.on_event(defines.events.on_gui_confirmed,
    ---@param e EventData.on_gui_confirmed
    function(e)
        if not e.element.valid then return end
        if not tools.is_child_of(e.element, settings_panel_name) then return end

        local player = game.players[e.player_index]
        local frame = player.gui.screen[settings_panel_name]
        save(player, frame)
    end
)

tools.on_named_event(np("visible_layer"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        if not e.element.valid then return end

        local frame = player.gui.screen[settings_panel_name]
        local field_table = tools.get_child(frame, "field_table")
        if not field_table then return end

        if not (e.button ~= defines.mouse_button_type.left or e.control or e.shift or e.alt) then
            local name = e.element.style.name
            if name == selected_style then
                name = unselected_style
            else
                name = selected_style
            end
            e.element.style = name
        elseif not (e.button ~= defines.mouse_button_type.right or e.control or e.shift or e.alt) then
            local signal = e.element.elem_value
            field_table.current_layer.elem_value = signal
        end
    end
)


---@param player LuaPlayer
function settings_panel.close(player)
    tools.close_panel(player, settings_panel_name)
end

return settings_panel

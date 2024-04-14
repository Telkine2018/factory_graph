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

tools.add_panel_name(settings_panel_name)

---@param container LuaGuiElement
---@param machine_name string?
---@return LuaGuiElement
local function add_machine_button(container, machine_name)
    local b = container.add { type = "choose-elem-button", elem_type = "entity", entity = machine_name,
        elem_filters = { { filter = "type", type = "assembling-machine" },  { filter = "type", type = "furnace" } } }
    tools.set_name_handler(b, np("preferred_machines"))
    return b
end

---@param container LuaGuiElement
---@param module_name string?
---@return LuaGuiElement
local function add_module_button(container, module_name)
    local b = container.add { type = "choose-elem-button", elem_type = "item", item = module_name,
        elem_filters = { { filter = "type", type="module" } } }
    tools.set_name_handler(b, np("preferred_modules"))
    return b
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

    local flow = inner_frame.add { type = "table", column_count = 2, name="field_table" }

    flow.add { type = "label", caption = { np("grid-size") } }
    flow.add { type = "textfield", numeric = true, text = tostring(g.grid_size), name = "grid_size" }

    flow.add { type = "label", caption = { np("show_hidden") } }
    flow.add { type = "checkbox", numeric = true, state = not not g.show_hidden, name = "show_hidden" }

    flow.add { type = "label", caption = { np("only-researched") } }
    flow.add { type = "checkbox", name = "show_only_researched", state = not not g.show_only_researched }

    flow.add { type = "label", caption = { np("layout-on-selection") } }
    flow.add { type = "checkbox", name = "layout-on-selection", state = not not g.layout_on_selection }

    flow.add { type = "label", caption = { np("preferred_machines") }}
    local pmachine_flow = flow.add { type = "flow", direction = "horizontal", name="preferred_machines"  }
    if g.preferred_machines then
        for _, machine_name in pairs(g.preferred_machines) do
            add_machine_button(pmachine_flow, machine_name)
        end
    end
    add_machine_button(pmachine_flow)

    flow.add { type = "label", caption = { np("preferred_modules") } }
    local pmodule_flow = flow.add { type = "flow", direction = "horizontal", name = "preferred_modules" }
    if g.preferred_modules then
        for _, name in pairs(g.preferred_modules) do
            add_module_button(pmodule_flow, name)
        end
    end
    add_module_button(pmodule_flow)

    flow.add { type = "label", caption = { np("preferred_beacon") }}
    flow.add { type = "choose-elem-button", elem_type = "entity", elem_filters = { { filter = "type", type = "beacon" } }, 
            name = "preferred_beacon", entity=g.preferred_beacon }

    flow.add { type = "label", caption = { np("preferred_beacon_count") } }
    flow.add { type = "textfield", numeric = true, text = tostring(g.preferred_beacon_count or 0), 
        name = "preferred_beacon_count" }

    local bpanel = frame.add{type="flow", direction="horizontal"}
    local b = bpanel.add{type="button", caption={np("save")}}
    tools.set_name_handler(b, np("save"))

    b = bpanel.add{type="button", caption={np("cancel")}}
    tools.set_name_handler(b, np("cancel"))
    
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
        player.print({np("invalid_grid_size")})
        return
    end

    local show_hidden = field_table.show_hidden.state
    local show_only_researched = field_table.show_only_researched.state
    local layout_on_selection = field_table["layout-on-selection"].state

    local preferred_machines = blist_values(field_table.preferred_machines)

    local preferred_modules = blist_values(field_table.preferred_modules)

    local preferred_beacon = field_table.preferred_beacon.elem_value

    local preferred_beacon_count = tonumber(field_table.preferred_beacon_count.text) or 0

    g.layout_on_selection = layout_on_selection
    if show_hidden ~= g.show_hidden or show_only_researched ~= g.show_only_researched then
        g.show_hidden = show_hidden
        g.show_only_researched = show_only_researched
        local recipes = player.force.recipes
        graph.update_recipes(g, recipes, g.excluded_categories)
        graph.refresh(player)
    elseif grid_size_value ~= g.grid_size then
        g.grid_size = grid_size_value
        graph.refresh(player)
    end
    g.preferred_machines = preferred_machines
    g.preferred_modules = preferred_modules
    g.preferred_beacon = preferred_beacon --[[@as string]]
    g.preferred_beacon_count = preferred_beacon_count
    gutils.fire_production_data_change(g)
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

---@param player LuaPlayer
function settings_panel.close(player)
    tools.close_panel(player, settings_panel_name)
end

return settings_panel

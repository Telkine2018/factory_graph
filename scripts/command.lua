local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local colors = require("scripts.colors")
local recipe_selection = require("scripts.recipe_selection")

local graph = require("scripts.graph")
local drawing = require("scripts.drawing")
local product_panel = require("scripts.product_panel")
local production = require("scripts.production")
local settings_panel = require("scripts.settings_panel")
local saving = require("scripts.saving")

local debug = tools.debug
local prefix = commons.prefix

local command = {}

local function np(name)
    return prefix .. "-command." .. name
end

local command_frame_name = np("command")
tools.add_panel_name(command_frame_name)

command.frame_name      = command_frame_name

local select_modes      = {

    commons.none_selection,
    commons.ingredient_selection,
    commons.product_selection,
    commons.ingredient_and_product_selection
}
local select_mode_items = {}
for _, name in pairs(select_modes) do
    table.insert(select_mode_items, { np(name .. "_selection") })
end

local visibility_items = {
    { np("visibility_all") },
    { np("visibility_selection") }
}

---@param player LuaPlayer
function command.open(player)
    local player_index = player.index
    local g = gutils.get_graph(player)

    command.close(player)

    
    ---@type Params.create_standard_panel
    local params = {
        panel_name = command_frame_name,
        title  = {np("title")},
        is_draggable = false,
        container=player.gui.left,
        create_inner_frame = true
    }
    local frame, inner_frame = tools.create_standard_panel(player, params)

    --frame.style.width = 600
    --frame.style.minimal_height = 300

    local select_index = 1
    for i = 1, #select_modes do
        if select_modes[i] == g.select_mode then
            select_index = i
            break
        end
    end
    local hflow

    local visibility = g.visibility
    if not visibility then visibility = commons.visibility_all end
    hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "label", caption = { np("visibility_label") } }
    hflow.add { type = "drop-down", caption = { "visibility_mode" }, items = visibility_items, selected_index = visibility, name = np("visibility") }
    hflow.add {
        type = "sprite-button",
        name = np("refresh"),
        style = "frame_action_button",
        mouse_button_filter = { "left" },
        sprite = prefix .. "_refresh_white",
        hovered_sprite = prefix .. "_refresh_black"
    }
    hflow.style.bottom_margin = 5

    hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "button", caption = { np("add") }, name = np("add") }
    hflow.add { type = "button", caption = { np("production") }, name = np("production") }
    hflow.style.bottom_margin = 5

    hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "button", caption = { np("settings") }, name = np("settings") }
    hflow.add { type = "button", caption = { np("save") }, name = np("save") }
    hflow.style.bottom_margin = 5

    hflow = inner_frame.add { type = "flow", direction = "horizontal" }
    hflow.add { type = "button", caption = { np("unselect_all") }, name = np("unselect_all") }
    hflow.add { type = "button", caption = { np("recompute-colors") }, name = np("recompute-colors") }
    hflow.style.bottom_margin = 5

end

tools.on_named_event(np("recompute-colors"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        colors.recompute_colors(g)
        drawing.redraw_selection(player)
    end)

tools.on_named_event(np("add"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        recipe_selection.open(g)
    end)

tools.on_named_event(np("selection"), defines.events.on_gui_selection_state_changed,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        g.select_mode = select_modes[e.element.selected_index]
    end)


tools.on_named_event(np("visibility"), defines.events.on_gui_selection_state_changed,
    function(e)
        local player = game.players[e.player_index]
        local g = gutils.get_graph(player)
        g.visibility = e.element.selected_index
        graph.refresh(player)
        gutils.recenter(g)
    end)

tools.on_named_event(np("refresh"), defines.events.on_gui_click,
    function(e)
        local player = game.players[e.player_index]
        graph.refresh(player)
        local g = gutils.get_graph(player)
        gutils.fire_production_data_change(g)
    end)

tools.on_named_event(np("production"), defines.events.on_gui_click,
    function(e)
        product_panel.create(e.player_index)
    end)

tools.on_named_event(np("settings"), defines.events.on_gui_click,
    function(e)
        settings_panel.create(e.player_index)
    end)

tools.on_named_event(np("unselect_all"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        graph.unselect(game.players[e.player_index])
    end)

---@param player LuaPlayer
function command.close(player)
    local frame = player.gui.left[command_frame_name]
    if frame then
        frame.destroy()
    end
end

tools.on_named_event(np("save"), defines.events.on_gui_click,
    function(e)
        saving.create(e.player_index)
    end)

return command

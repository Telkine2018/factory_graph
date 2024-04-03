local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local graph = require("scripts.graph")
local gutils = require("scripts.gutils")
local machinedb = require("scripts.machinedb")
local production = require("scripts.production")

local prefix = commons.prefix

local function np(name)
    return prefix .. "-saving." .. name
end

local panel_name = np("frame")

tools.add_panel_name(panel_name)

local saving = {}
local button_size = 28

---@param flow LuaGuiElement
---@param save Saving
local function load_current(flow, save)
    flow.icon1.elem_value = tools.sprite_to_signal(save.icon1)
    flow.icon2.elem_value = tools.sprite_to_signal(save.icon2)
    flow.label.text = save.label
end

---@param player_index integer
function saving.create(player_index)
    local player = game.players[player_index]
    local vars = tools.get_vars(player)
    local g = gutils.get_graph(player)

    if not g then return end

    if (player.gui.screen[panel_name]) then
        saving.close(player)
    end

    ---@type Params.create_standard_panel
    local params                             = {
        panel_name           = panel_name,
        title                = { np("title") },
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = np("close_button_tooltip"),
        create_inner_frame   = true
    }
    local frame, inner_frame                 = tools.create_standard_panel(player, params)
    frame.style.width                        = 800
    frame.style.minimal_height               = 400

    local newflow                            = inner_frame.add { type = "flow", name = "new_flow" }
    newflow.style.horizontally_stretchable   = true
    newflow.style.bottom_margin              = 7
    local bnew1                              = newflow.add { type = "choose-elem-button", elem_type = "signal", name = "icon1" }
    bnew1.style.size                         = button_size
    local bnew2                              = newflow.add { type = "choose-elem-button", elem_type = "signal", name = "icon2" }
    bnew2.style.size                         = button_size
    local newlabel                           = newflow.add { type = "textfield", name = "label" }
    newlabel.style.horizontally_stretchable  = true
    local bsave                              = newflow.add { type = "button", caption = { np("save") }, name = np("save") }

    local scroll                             = inner_frame.add { type = "scroll-pane",
        horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
    scroll.style.horizontally_stretchable    = true
    scroll.style.vertically_stretchable      = true

    local container                          = scroll.add { type = "table", column_count = 1, name = "save_list" }
    container.style.horizontally_stretchable = true
    container.style.vertically_stretchable   = true

    if vars.current_save then
        load_current(newflow, vars.current_save)
    end

    ---@type Saving[]
    local saves                              = vars.saves
    if not saves then
        saves = {}
    end

    saving.update(player, container)
    frame.force_auto_center()
end

---@param player LuaPlayer
---@param container LuaGuiElement
function saving.update(player, container)
    local vars  = tools.get_vars(player)

    ---@type Saving[]
    local saves = vars.saves
    if not saves then
        saves = {}
    end

    container.clear()
    for _, save in pairs(saves) do
        local line                               = container.add { type = "flow", direction = "horizontal" }

        local signal1                            = tools.sprite_to_signal(save.icon1)
        local b                                  = line.add { type = "choose-elem-button", elem_type = "signal", signal = signal1 }
        b.locked                                 = true
        b.style.size                             = button_size

        local signal2                            = tools.sprite_to_signal(save.icon2)
        b                                        = line.add { type = "choose-elem-button", elem_type = "signal", signal = signal2 }
        b.locked                                 = true
        b.style.size                             = button_size

        local flow_text                          = line.add { type = "flow", direction = "vertical" }
        flow_text.style.horizontally_stretchable = true

        local ftext                              = flow_text.add { type = "label", caption = save.label }
        ftext.style.horizontally_stretchable     = true


        local bload = line.add { type = "button", caption = { np("load") } }
        tools.set_name_handler(bload, np("load"))

        local bimport = line.add { type = "button", caption = { np("import") } }
        tools.set_name_handler(bimport, np("import"))

        local bdelete = line.add { type = "button", caption = { np("delete") } }
        tools.set_name_handler(bdelete, np("delete"))
    end
end

---@param player LuaPlayer
function saving.close(player)
    local frame = player.gui.screen[panel_name]
    if frame and frame.valid then
        frame.destroy()
    end
end

tools.on_named_event(np("save"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local g = gutils.get_graph(player)

        local frame = player.gui.screen[panel_name]
        if not (frame and frame.valid) then return end

        local new_flow = tools.get_child(frame, "new_flow")
        if not new_flow then return end

        ---@type Saving
        local save = {}
        save.icon1 = tools.signal_to_sprite(new_flow.icon1.elem_value --[[@as SignalID]])
        save.icon2 = tools.signal_to_sprite(new_flow.icon2.elem_value --[[@as SignalID]])
        save.label = tools.trim(new_flow.label.text)

        if not save.icon1 then
            player.print { np("missing_icon") }
            return
        end
        if save.label == "" then
            player.print { np("missing_label") }
            return
        end

        local data  = gutils.create_saving_data(g)
        local json  = game.table_to_json(data)
        json        = game.encode_string(json) --[[@as string]]
        save.json   = json

        ---@type Saving[]
        local saves = vars.saves
        if not saves then
            saves = {}
            vars.saves = saves
        end
        for index, existing in pairs(saves) do
            if existing.icon1 == save.icon1 and
                existing.icon2 == save.icon2 and
                existing.label == save.label then
                existing.json = json
                save = existing
                goto done
            end
        end
        table.insert(saves, save)
        ::done::

        vars.current_save = save
        local container = tools.get_child(frame, "save_list")
        if not container then return end
        saving.update(player, container)

        saving.close(player)
    end)

tools.on_named_event(np("close"), defines.events.on_gui_click,
    function(e)
        saving.close(game.players[e.player_index])
    end)

tools.on_named_event(np("delete"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local g = gutils.get_graph(player)

        local line = e.element.parent
        if not line then return end
        local index = line.get_index_in_parent()
        local saves = vars.saves

        table.remove(saves, index)

        local frame = player.gui.screen[panel_name]
        if not (frame and frame.valid) then return end
        local container = tools.get_child(frame, "save_list")
        if not container then return end
        saving.update(player, container)
    end)

tools.on_named_event(np("load"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local g = gutils.get_graph(player)
        local frame = player.gui.screen[panel_name]

        local line = e.element.parent
        if not line then return end
        local index = line.get_index_in_parent()
        
        ---@type Saving[]
        local saves = vars.saves

        local save = saves[index]
        local json = game.decode_string(save.json) --[[@as string]]
        local data = game.json_to_table(json) --[[@as SavingData]]

        local new_flow = tools.get_child(frame, "new_flow")
        if new_flow then 
            load_current(new_flow, save)
        end
        vars.current_save = save

        graph.load_saving(g, data)
        saving.close(player)
    end)

tools.on_named_event(np("import"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local g = gutils.get_graph(player)

        local line = e.element.parent
        if not line then return end
        local index = line.get_index_in_parent()
        local saves = vars.saves

        local save = saves[index]
        local json = game.decode_string(save.json) --[[@as string]]
        local data = game.json_to_table(json) --[[@as SavingData]]

        graph.import_saving(g, data)
    end)


return saving

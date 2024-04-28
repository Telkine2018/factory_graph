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

---@param player LuaPlayer
function saving.clear_current(player)

    local vars = tools.get_vars(player)
    vars.saving_current = nil
    local frame = player.gui.screen[panel_name]
    if not (frame and frame.valid) then return end
    local flow = tools.get_child(frame, "new_flow")
    if not flow then return end
    flow.icon1.elem_value = nil
    flow.icon2.elem_value = nil
    flow.label.text = ""
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
    local params                           = {
        panel_name           = panel_name,
        title                = { np("title") },
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = np("close_button_tooltip"),
        create_inner_frame   = true
    }
    local frame, inner_frame               = tools.create_standard_panel(player, params)
    frame.style.minimal_width              = 400
    frame.style.height                     = 400

    local newflow                          = inner_frame.add { type = "flow", name = "new_flow" }
    newflow.style.horizontally_stretchable = true
    newflow.style.bottom_margin            = 7
    local bnew1                            = newflow.add { type = "choose-elem-button", elem_type = "signal", name = "icon1" }
    bnew1.style.size                       = button_size
    tools.set_name_handler(bnew1, np("icon1"))
    local bnew2                              = newflow.add { type = "choose-elem-button", elem_type = "signal", name = "icon2" }
    bnew2.style.size                         = button_size
    local newlabel                           = newflow.add { type = "textfield", name = "label" }
    newlabel.style.horizontally_stretchable  = true
    local bsave                              = newflow.add { type = "button", caption = { np("save") }, name = np("save"), tooltip = { np("save-tooltip") } }

    local scroll                             = inner_frame.add { type = "scroll-pane",
        horizontal_scroll_policy = "never", vertical_scroll_policy = "auto-and-reserve-space" }
    scroll.style.horizontally_stretchable    = true
    scroll.style.vertically_stretchable      = true

    local container                          = scroll.add { type = "table", column_count = 1, name = "save_list" }
    container.style.horizontally_stretchable = true
    container.style.vertically_stretchable   = true

    if vars.saving_current then
        load_current(newflow, vars.saving_current)
    end

    ---@type Saving[]
    local saves = vars.saves
    if not saves then
        saves = {}
    end

    saving.update(player, container)
    local location = vars.saving_location
    if location then
        frame.location = location
    else
        frame.force_auto_center()
    end
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
        local line    = container.add { type = "flow", direction = "horizontal" }

        local signal1 = tools.sprite_to_signal(save.icon1)
        local b       = line.add { type = "choose-elem-button", elem_type = "signal", signal = signal1, tooltip = { np("load-tooltip") }, name = "b1" }
        b.locked      = true
        b.style.size  = button_size
        tools.set_name_handler(b, np("load"))

        local signal2 = tools.sprite_to_signal(save.icon2)
        b             = line.add { type = "choose-elem-button", elem_type = "signal", signal = signal2, tooltip = { np("load-tooltip") }, name = "b2" }
        b.locked      = true
        b.style.size  = button_size
        tools.set_name_handler(b, np("load"))

        local flow_text                          = line.add { type = "flow", direction = "vertical" }
        flow_text.style.horizontally_stretchable = true

        local ftext                              = flow_text.add { type = "label", caption = save.label }
        ftext.style.horizontally_stretchable     = true


        local bdelete = line.add { type = "button", caption = { np("delete") }, tooltip = { np("delete-tooltip") } }
        tools.set_name_handler(bdelete, np("delete"))
    end

    saving.update_selection(container)
end

---@param container LuaGuiElement
function saving.update_selection(container)
    local player = game.players[container.player_index]
    local frame = player.gui.screen[panel_name]

    if not (frame and frame.valid) then return end
    local flow = tools.get_child(frame, "new_flow")
    if not flow then return end

    local vars  = tools.get_vars(player)
    local saves = vars.saves
    if not saves then return end

    local s1 = flow.icon1.elem_value --[[@as SignalID]]
    local ls1 = tools.signal_to_sprite(s1)
    local s2 = flow.icon2.elem_value --[[@as SignalID]]
    local ls2 = tools.signal_to_sprite(s2)
    local s3 = flow.label.text

    local default_style = prefix .. "_small_slot_button_default"
    local hstyle = prefix .. "_small_slot_button_yellow"
    for i = 1, math.min(#container.children, #saves) do
        local save = saves[i]
        local line = container.children[i]

        local style = default_style
        if (save.icon1 == ls1 and save.icon2 == ls2 and save.label == s3) then
            style = hstyle
        end
        line.b1.style = style
        line.b2.style = style
    end
end

---@param player LuaPlayer
function saving.close(player)
    local frame = player.gui.screen[panel_name]
    if frame and frame.valid then
        tools.get_vars(player).saving_location = frame.location
        frame.destroy()
    end
end

---@param icon string?
---@return string
local function get_proto(icon)
    if not icon then
        return ""
    end
    local s_icon = tools.sprite_to_signal(icon)
    if not s_icon then return "" end
    if s_icon.type == "item" then
        ---@type LuaItemPrototype
        local proto = game.item_prototypes[s_icon.name]
        return "A " .. proto.group.order .. " " .. proto.subgroup.order .. " " .. proto.order
    elseif s_icon.type == "fluid" then
        ---@type LuaFluidPrototype
        local proto = game.fluid_prototypes[s_icon.name]
        return "B " .. proto.group.order .. " " .. proto.subgroup.order .. " " .. proto.order
    elseif s_icon.type == "virtual" then
        ---@type LuaVirtualSignalPrototype
        local proto = game.virtual_signal_prototypes[s_icon.name]
        return "C " .. proto.subgroup.order .. " " .. proto.order
    else
        return ""
    end
end

---@param icon1 string?
---@param icon2 string?
---@return string
---@return string
local function compare_icon(icon1, icon2)
    local c1 = get_proto(icon1)
    local c2 = get_proto(icon2)
    return c1, c2
end

---@param player LuaPlayer
function saving.sort(player)
    local vars = tools.get_vars(player)

    ---@type Saving[]
    local saves = vars.saves
    if not saves then
        return
    end

    table.sort(saves,
        ---@param s1 Saving
        ---@param s2 Saving
        function(s1, s2)
            local c1, c2 = compare_icon(s1.icon1, s2.icon1)
            if c1 ~= c2 then return c1 < c2 end
            c1, c2 = compare_icon(s1.icon2, s2.icon2)
            if c1 ~= c2 then return c1 < c2 end
            return s1.label < s2.label
        end)
end

---@param g Graph
---@param save Saving
local function update_save(g, save)
    local data = gutils.create_saving_data(g)
    local json = game.table_to_json(data)
    json       = game.encode_string(json) --[[@as string]]
    save.json  = json
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

        update_save(g, save)

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
                existing.json = save.json
                save = existing
                goto done
            end
        end
        table.insert(saves, save)
        ::done::
        saving.sort(player)

        vars.saving_current = save
        local container = tools.get_child(frame, "save_list")
        if not container then return end
        saving.update(player, container)

        --saving.close(player)
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

        if saves[index] == vars.saving_current then
            vars.saving_current = nil
        end
        table.remove(saves, index)

        local frame = player.gui.screen[panel_name]
        if not (frame and frame.valid) then return end
        local container = tools.get_child(frame, "save_list")
        if not container then return end
        local parent = line.parent --[[@as LuaGuiElement]]
        saving.update(player, container)
        saving.clear_current(player)
        saving.update_selection(parent)
    end)

tools.on_named_event(np("load"), defines.events.on_gui_click,
    ---@param e EventData.on_gui_click
    function(e)
        local player = game.players[e.player_index]
        local vars = tools.get_vars(player)
        local g = gutils.get_graph(player)
        local frame = player.gui.screen[panel_name]
        if not (frame and frame.valid) then return end

        local line = e.element.parent
        if not line then return end

        ---@type Saving[]
        local saves = vars.saves
        local index = line.get_index_in_parent()
        local save = saves[index]

        if not (e.button ~= defines.mouse_button_type.left or e.shift or e.alt) then
            local json = game.decode_string(save.json) --[[@as string]]
            local data = game.json_to_table(json) --[[@as SavingData]]
            local new_flow = tools.get_child(frame, "new_flow")
            if new_flow then
                load_current(new_flow, save)
            end
            if (e.control or g.autosave_on_graph_switching) and vars.saving_current then
                update_save(g, vars.saving_current)
            end
            vars.saving_current = save
            graph.load_saving(g, data)
            saving.update_selection(line.parent)
        elseif not (e.button ~= defines.mouse_button_type.left or not e.shift or e.control or e.alt) then
            local json = game.decode_string(save.json) --[[@as string]]
            local data = game.json_to_table(json) --[[@as SavingData]]
            graph.import_saving(g, data)
        end
    end)

tools.on_named_event(np("icon1"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
    function(e)
        if not (e.element and e.element.valid) then return end

        local value = e.element.elem_value
        local parent = e.element.parent
        if not parent then return end

        parent.icon2.elem_value = value
    end)

return saving

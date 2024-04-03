local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local graph = require("scripts.graph")
local gutils = require("scripts.gutils")
local machinedb = require("scripts.machinedb")
local production = require("scripts.production")

local prefix = commons.prefix

local function np(name)
    return prefix .. "-msettings." .. name
end

local panel_name = np("frame")
commons.msettings_panel_name = panel_name

tools.add_panel_name(panel_name)

local msettings = {}

---@param container LuaGuiElement
---@param config ProductionConfig
local function install_modules(container, config)
    container.clear()

    local machine = game.entity_prototypes[config.machine_name]
    if not machine then
        return
    end
    local count = machine.module_inventory_size
    if count == 0 then
        return
    end

    ---@cast count -nil
    for i = 1, count do
        local module_name

        if config.machine_modules then
            module_name = config.machine_modules[i]
            if module_name then
                local module = game.item_prototypes[module_name]
                if module then
                    for effect in pairs(module.module_effects) do
                        if not machine.allowed_effects[effect] then
                            goto skip
                        end
                    end
                end
                module_name = module.name
                ::skip::
            end
        end

        local b = container.add { type = "choose-elem-button", elem_type = "item", item = module_name,
            elem_filters = { { filter = "type", type = "module" } } }
        tools.set_name_handler(b, np("module_button"), { count = count })
    end
end

---@param container LuaGuiElement
---@param g Graph
---@param config ProductionConfig
---@param grecipe GRecipe
local function install_beacon_modules(container, g, config, grecipe)
    container.clear()

    if count == 0 then
        return
    end

    container.clear()
    if config.beacon_name then
        local beacon = game.entity_prototypes[config.beacon_name]
        if not beacon then return end

        local count = beacon.module_inventory_size
        local allowed = {}
        local modules = game.get_filtered_item_prototypes { { filter = "type", type = "module" } }
        for _, module in pairs(modules) do
            for effect, _ in pairs(module.module_effects) do
                if not beacon.allowed_effects[effect] then
                    goto skip
                end
            end
            if module.limitations and #module.limitations > 0 then
                if g.module_limitations then
                    limitations = g.module_limitations[module.name]
                    if limitations and not limitations[grecipe.name] then
                        goto skip
                    end
                end
            end
            table.insert(allowed, module.name)
            ::skip::
        end

        for i = 1, count do
            local module_name
            if config.beacon_modules and config.beacon_modules[i] then
                module_name = config.beacon_modules[i]
            end
            local b = container.add { type = "choose-elem-button", elem_type = "item", item = module_name,
                elem_filters = { { filter = "name", name = allowed } } }
            tools.set_name_handler(b, np("module_button"), { count = count })
        end
    end
end

---@param field_table LuaGuiElement
---@param is_default boolean
local function enable_config(field_table, is_default)
    local enabled = not is_default
    field_table.machine.enabled = enabled
    for _, c in pairs(field_table.modules.children) do
        c.enabled = enabled
    end
    field_table.beacon.enabled = enabled
    for _, c in pairs(field_table.beacon_modules.children) do
        c.enabled = enabled
    end
    field_table.beacon_count.enabled = enabled
end

---@param player_index integer
---@param grecipe GRecipe
function msettings.create(player_index, grecipe)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)

    if not g then return end

    if (player.gui.screen[panel_name]) then
        msettings.close(player)
    end

    if not grecipe.machine then return end

    ---@type Params.create_standard_panel
    local params = {
        panel_name           = panel_name,
        title                = { np("title") },
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = np("close_button_tooltip"),
        create_inner_frame   = true
    }
    local frame, inner_frame = tools.create_standard_panel(player, params)
    local field_table = inner_frame.add { type = "table", column_count = 2, name = "field_table" }

    if not grecipe.machine then
        return
    end
    local config = grecipe.machine.config
    config = tools.table_dup(config)

    local is_default = grecipe.production_config == nil
    local label = field_table.add { type = "label", caption = { np("default_config") } }
    label.style.right_margin = 5
    local b = field_table.add { type = "checkbox", state = is_default, name = "is_default" }
    b.style.height = 40
    tools.set_name_handler(b, np("is_default"))

    local recipe = game.recipe_prototypes[grecipe.name]
    local category = recipe.category
    field_table.add { type = "label", caption = { np("machine") } }
    b = field_table.add { type = "choose-elem-button", elem_type = "entity", entity = config.machine_name, name = "machine",
        elem_filters = { { filter = "crafting-category", crafting_category = category } } }
    tools.set_name_handler(b, np("machine"), { recipe_name = grecipe.name })

    field_table.add { type = "label", caption = { np("modules") } }
    local module_flow = field_table.add { type = "table", column_count = 6, name = "modules" }
    install_modules(module_flow, config)

    field_table.add { type = "label", caption = { np("beacon") } }
    b = field_table.add { type = "choose-elem-button", elem_type = "entity", entity = config.beacon_name, name = "beacon",
        elem_filters = { { filter = "type", type = "beacon" } } }
    tools.set_name_handler(b, np("beacon"), { recipe_name = grecipe.name })

    field_table.add { type = "label", caption = { np("beacon_modules") } }
    local beacon_modules_flow = field_table.add { type = "table", column_count = 6, name = "beacon_modules" }
    install_beacon_modules(beacon_modules_flow, g, config, grecipe)

    field_table.add { type = "label", caption = { np("beacon_count") } }
    b = field_table.add { type = "textfield", numeric = true, text = tostring(config.beacon_count or 0), name = "beacon_count" }
    tools.set_name_handler(b, np("beacon_count"))

    enable_config(field_table, is_default)

    local report_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding",
        name = "report_frame"
    }
    report_frame.style.vertically_stretchable = true
    report_frame.style.horizontally_stretchable = true
    report_frame.style.minimal_height = 100

    local vars = tools.get_vars(player)
    vars.msettings_config = config
    vars.msettings_recipe_name = grecipe.name
    msettings.report(player)

    if vars.msettings_location then
        frame.location = vars.msettings_location
    else
        frame.force_auto_center()
    end
end

tools.on_named_event(np("beacon_count"), defines.events.on_gui_text_changed,
    ---@param e EventData.on_gui_text_changed
    function(e)
        msettings.save(game.players[e.player_index])
    end)

tools.on_named_event(np("is_default"), defines.events.on_gui_checked_state_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[panel_name]
        local g = gutils.get_graph(player)

        local field_table = tools.get_child(frame, "field_table")
        if not field_table then return end

        enable_config(field_table, e.element.state)
        if e.element.state then
            local vars = tools.get_vars(player)
            local recipe_name = vars.msettings_recipe_name
            ---@type ProductionConfig
            local config = vars.msettings_config

            local def_config = machinedb.get_default_config(g, recipe_name, {})
            if not def_config then return end
            for name, value in pairs(def_config) do
                config[name] = value
            end

            field_table.machine.elem_value = config.machine_name
            install_modules(field_table.modules, config)

            field_table.beacon.elem_value = config.beacon_name
            install_beacon_modules(field_table.beacon_modules, g, config, recipe_name)

            field_table.beacon_count.text = tostring(config.beacon_count or 0)
            msettings.save(player)
        end
        msettings.report(player)
    end)

tools.on_named_event(np("machine"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[panel_name]
        local g = gutils.get_graph(player)

        if not g then return end

        local field_table = tools.get_child(frame, "field_table")
        if not field_table then return end

        local recipe_name = e.element.tags.recipe_name --[[@as string]]
        if not recipe_name then return end

        local machine = g.recipes[recipe_name].machine
        if not machine then return end

        local vars = tools.get_vars(player)
        local config = vars.msettings_config
        config.machine_name = e.element.elem_value --[[@as string]]
        install_modules(field_table.modules, config)
        msettings.save(player)
    end
)

tools.on_named_event(np("beacon"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_checked_state_changed
    function(e)
        local player = game.players[e.player_index]
        local frame = player.gui.screen[panel_name]
        local g = gutils.get_graph(player)

        if not g then return end

        local field_table = tools.get_child(frame, "field_table")
        if not field_table then return end

        local recipe_name = e.element.tags.recipe_name --[[@as string]]
        if not recipe_name then return end

        local machine = g.recipes[recipe_name].machine
        if not machine then return end

        local vars = tools.get_vars(player)
        local config = vars.msettings_config
        local recipe_name = vars.msettings_recipe_name
        config.beacon_name = e.element.elem_value --[[@as string]]

        install_beacon_modules(field_table.beacon_modules, g, config, recipe_name)
        msettings.save(player)
    end
)

---@param player LuaPlayer
---@return ProductionConfig?
local function read_config(player)
    local frame = player.gui.screen[panel_name]
    if not frame then return nil end

    local field_table = tools.get_child(frame, "field_table")
    if not field_table then return nil end

    local g = gutils.get_graph(player)
    local vars = tools.get_vars(player)
    ---@type ProductionConfig
    local config = vars.msettings_config
    local recipe_name = vars.msettings_recipe_name
    local grecipe = g.recipes[recipe_name]

    if field_table.is_default.state then
        grecipe.production_config = nil
        gutils.fire_production_data_change(g)
        return nil
    end

    config.machine_name = field_table.machine.elem_value --[[@as string]]
    if not config.machine_name then
        player.print { np("no_machine_set") }
        return nil
    end
    config.machine_modules = {}
    for _, fmod in pairs(field_table.modules.children) do
        local module_name = fmod.elem_value
        if module_name then
            table.insert(config.machine_modules, module_name)
        end
    end

    config.beacon_name = field_table.beacon.elem_value --[[@as string]]
    if config.beacon_name then
        config.beacon_modules = {}
        for _, fmod in pairs(field_table.beacon_modules.children) do
            local module_name = fmod.elem_value
            if module_name then
                table.insert(config.beacon_modules, module_name)
            end
        end
    else
        config.beacon_modules = nil
    end
    config.beacon_count = tonumber(field_table.beacon_count.text) or 0
    return config
end

---@param player LuaPlayer
function msettings.save(player)
    local frame = player.gui.screen[panel_name]
    if not frame then return end

    local field_table = tools.get_child(frame, "field_table")
    if not field_table then return end

    local g = gutils.get_graph(player)
    local vars = tools.get_vars(player)
    local recipe_name = vars.msettings_recipe_name
    local grecipe = g.recipes[recipe_name]

    local config = read_config(player)
    if field_table.is_default.state then
        grecipe.production_config = nil
    else
        grecipe.production_config = config
    end
    if not config then
        return
    end
    gutils.fire_production_data_change(g)
    msettings.report(player)
end

---@param player LuaPlayer
function msettings.close(player)
    local frame = player.gui.screen[panel_name]
    if frame and frame.valid then
        local vars = tools.get_vars(player)
        vars.msettings_location = frame.location
        frame.destroy()
    end
end

tools.on_named_event(np("module_button"), defines.events.on_gui_elem_changed,
    ---@param e EventData.on_gui_elem_changed
    function(e)
        if not e.element.valid then return end

        local count = e.element.tags.count --[[@as integer]]
        local parent = e.element.parent
        if not parent then return end
        local value = e.element.elem_value
        local index = e.element.get_index_in_parent()
        for i = index + 1, count do
            parent.children[i].elem_value = value
        end
        local player = game.players[e.player_index]
        msettings.save(player)
    end)

tools.on_named_event(np("close"), defines.events.on_gui_click,
    function(e)
        msettings.close(game.players[e.player_index])
    end)

function msettings.report(player)
    local frame = player.gui.screen[panel_name]
    if not frame then return end

    local report_frame = tools.get_child(frame, "report_frame")
    if not report_frame then return end

    report_frame.clear()
    local report_table = report_frame.add { type = "table", column_count = 2 }

    local g = gutils.get_graph(player)
    local vars = tools.get_vars(player)
    ---@type string
    local recipe_name = vars.msettings_recipe_name
    ---@type ProductionConfig
    local config = vars.msettings_config

    local machine = production.compute_machine(g, g.recipes[recipe_name], config)
    if not machine then return end

    ---@param v number
    local function format(v)
        v = v * 100
        if v < 0 then
            return string.format("%.2f", v) .. "%"
        else
            return "+" .. string.format("%.2f", v) .. "%"
        end
    end

    local function report_value(caption, value)
        label = report_table.add { type = "label", caption = caption }
        label.style.width = 100
        label = report_table.add { type = "label", caption = format(value) }
        label.style.width = 100
        label.style.horizontal_align = "right"
    end

    report_value({ np("report_speed") }, machine.speed)
    report_value({ np("report_productivity") }, machine.productivity)
    report_value({ np("report_consumption") }, machine.consumption)
    report_value({ np("report_pollution") }, machine.pollution)
end

return msettings

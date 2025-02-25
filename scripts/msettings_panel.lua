local luautil = require("__core__/lualib/util")

local commons = require("scripts.commons")
local tools = require("scripts.tools")
local gutils = require("scripts.gutils")
local machinedb = require("scripts.machinedb")
local production = require("scripts.production")

local prefix = commons.prefix

local function np(name)
    return prefix .. "-msettings." .. name
end

local panel_name = np("frame")
commons.msettings_panel_name = panel_name

local msettings = {}

---@param container LuaGuiElement
---@param g Graph
---@param config ProductionConfig
---@param grecipe GRecipe
local function install_modules(container, g, config, grecipe)
    container.clear()

    local assembly_machine = prototypes.entity[tools.extract_name(config.machine_name)]
    if not assembly_machine then
        return
    end
    local count = assembly_machine.module_inventory_size
    if count == 0 then
        return
    end

    local allowed = {}
    local modules = prototypes.get_item_filtered { { filter = "type", type = "module" } }
    local recipe = prototypes.recipe[grecipe.name]
    local allowed_effects = recipe.allowed_effects
    local allowed_module_categories = recipe.allowed_module_categories
    for _, module in pairs(modules) do
        for effect, _ in pairs(module.module_effects) do
            if not assembly_machine.allowed_effects[effect] then
                goto skip
            end
            if allowed_effects and not allowed_effects[effect] then
                goto skip
            end
            if allowed_module_categories and not allowed_module_categories[module.category] then
                goto skip
            end
        end
        table.insert(allowed, module.name)
        ::skip::
    end

    ---@cast count -nil
    for i = 1, count do
        local module_id
        local smodule = nil

        if config.machine_modules then
            module_id = config.machine_modules[i]
            if module_id then
                smodule = tools.id_to_signal(module_id)
                ---@cast smodule -nil

                local module = prototypes.item[smodule.name]
                if module then
                    for effect in pairs(module.module_effects) do
                        if not assembly_machine.allowed_effects[effect] then
                            goto skip
                        end
                    end
                end
                module_id = module.name
                ::skip::
            end
        end

        local b = container.add { type = "choose-elem-button", elem_type = "item-with-quality", 
            elem_filters = { { filter = "name", name = allowed } } }
        b.elem_value = smodule
        tools.set_name_handler(b, np("module_button"), { count = count })
    end
end

---@param container LuaGuiElement
---@param g Graph
---@param config ProductionConfig
---@param grecipe GRecipe
local function install_beacon_modules(container, g, config, grecipe)
    container.clear()

    if config.beacon_name then
        local beacon = prototypes.entity[tools.extract_name(config.beacon_name)]
        if not beacon then return end

        local count = beacon.module_inventory_size
        local allowed = {}
        local modules = prototypes.get_item_filtered { { filter = "type", type = "module" } }

        local recipe = prototypes.recipe[grecipe.name]
        local allowed_effects = recipe.allowed_effects
        local allowed_module_categories = recipe.allowed_module_categories
        for _, module in pairs(modules) do
            for effect, value in pairs(module.module_effects) do
                if effect == "quality" and value <= 0 then
                    goto next
                end
                if not beacon.allowed_effects[effect] then
                    goto skip
                end
                if allowed_effects and not allowed_effects[effect] then
                    goto skip
                end
                if allowed_module_categories and not allowed_module_categories[module.category] then
                    goto skip
                end
                ::next::
            end
            table.insert(allowed, module.name)
            ::skip::
        end

        for i = 1, count do
            local smodule = nil
            if config.beacon_modules and config.beacon_modules[i] then
                smodule = tools.id_to_signal(config.beacon_modules[i])
            end
            local b = container.add { type = "choose-elem-button", elem_type = "item-with-quality", 
                elem_filters = { { filter = "name", name = allowed } } }
            b.elem_value = smodule
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

    local config = grecipe.production_config
    if not config then
        config = machinedb.get_default_config(g, grecipe.name, {}) or {}
    end

    local recipe = prototypes.recipe[grecipe.name]

    ---@type Params.create_standard_panel
    local params = {
        panel_name           = panel_name,
        title                = { np("title"), recipe and "[recipe=" .. grecipe.name .. "]" or "", recipe and recipe.localised_name or "" },
        is_draggable         = true,
        close_button_name    = np("close"),
        close_button_tooltip = np("close_button_tooltip"),
        create_inner_frame   = true
    }
    local frame, recipe_frame = tools.create_standard_panel(player, params)

    recipe_frame.tags = { recipe_name = grecipe.name }
    recipe_frame.name = "recipe_frame"

    local machine = grecipe.machine
    if not machine then
        machine = production.compute_machine(g, grecipe, config)
        if not machine then
            frame.destroy()
            return
        end
        machine.count = 1
    end
    msettings.create_product_line(recipe_frame, machine)

    local config_frame = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }
    config_frame.style.vertically_stretchable = true
    config_frame.style.horizontally_stretchable = true

    local field_table = config_frame.add { type = "table", column_count = 2, name = "field_table" }

    config = tools.table_dup(config)

    local is_default = grecipe.production_config == nil
    local label = field_table.add { type = "label", caption = { np("default_config") } }
    label.style.right_margin = 5
    local b = field_table.add { type = "checkbox", state = is_default, name = "is_default" }
    b.style.height = 40
    tools.set_name_handler(b, np("is_default"))

    local recipe = prototypes.recipe[grecipe.name]
    local category = recipe.category
    machinedb.initialize()
    local machines = machinedb.category_to_machines[category]
    local machine_names = {}
    if machines and #machines ~= 0 then
        local force = player.force --[[@as LuaForce]]
        local search_surface = tools.get_vars(player).extern_surface
        if search_surface and not search_surface.valid then
            search_surface = nil
        end
        for _, m in pairs(machines) do
            if not g.show_only_researched or 
                    machinedb.is_machine_enabled(force, m.name)  or
                    (search_surface and search_surface.count_entities_filtered{name=m.name} > 0)
                     then
                table.insert(machine_names, m.name)
            end
        end
    end

    field_table.add { type = "label", caption = { np("machine") } }
    b = field_table.add { type = "choose-elem-button", elem_type = "entity-with-quality", name = "machine",
        elem_filters = { { filter = "name", name = machine_names } } }
    local signal = tools.id_to_signal(config.machine_name)
    b.elem_value = signal
    tools.set_name_handler(b, np("machine"), { recipe_name = grecipe.name })

    field_table.add { type = "label", caption = { np("modules") } }
    local module_flow = field_table.add { type = "table", column_count = 6, name = "modules" }
    install_modules(module_flow, g, config, grecipe)

    field_table.add { type = "label", caption = { np("beacon") } }
    b = field_table.add { type = "choose-elem-button", elem_type = "entity-with-quality", name = "beacon",
        elem_filters = { { filter = "type", type = "beacon" } } }
    signal = tools.id_to_signal(config.beacon_name)
    b.elem_value = signal
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
            config.beacon_modules = nil
            config.machine_modules = nil
            for name, value in pairs(def_config) do
                config[name] = value
            end

            field_table.machine.elem_value = tools.id_to_signal(config.machine_name)
            install_modules(field_table.modules, g, config, g.recipes[recipe_name])

            field_table.beacon.elem_value = tools.id_to_signal(config.beacon_name)
            install_beacon_modules(field_table.beacon_modules, g, config, g.recipes[recipe_name])

            enable_config(field_table, e.element.state)

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

        local vars = tools.get_vars(player)
        local config = vars.msettings_config
        config.machine_name = tools.signal_to_id(e.element.elem_value)

        install_modules(field_table.modules, g, config, g.recipes[recipe_name])

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

        local vars = tools.get_vars(player)
        local config = vars.msettings_config
        local recipe_name = vars.msettings_recipe_name
        config.beacon_name = tools.signal_to_id(e.element.elem_value)

        install_beacon_modules(field_table.beacon_modules, g, config, g.recipes[recipe_name])
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

    config.machine_name = tools.signal_to_id(field_table.machine.elem_value)
    if not config.machine_name then
        player.print { np("no_machine_set") }
        return nil
    end
    config.machine_modules = {}
    for _, fmod in pairs(field_table.modules.children) do
        local module_id = tools.signal_to_id(fmod.elem_value)
        if module_id then
            table.insert(config.machine_modules, module_id)
        end
    end

    config.beacon_name = tools.signal_to_id(field_table.beacon.elem_value)
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

    local grecipe = g.recipes[recipe_name]
    local machine
    if grecipe then
        machine = grecipe.machine
    end
    if machine and machine.count < 0 then
        machine = nil
    end
    if not machine then
        ---@type ProductionConfig
        local config = vars.msettings_config
        machine = production.compute_machine(g, g.recipes[recipe_name], config)
        if not machine then return end
        machine.count = 1
    end

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
    report_value({ np("report_quality") }, machine.quality)

    local energy = production.get_energy(machine)
    label = report_table.add { type = "label", caption = { np("energy") } }
    label.style.width = 100
    label = report_table.add { type = "label", caption = "[color=cyan]" .. luautil.format_number(energy, true) .. "W[/color]" }
    label.style.width = 100
    label.style.horizontal_align = "right"

end

---@param player LuaPlayer
function msettings.open_selection(player)
    local surface = player.surface

    if not string.find(surface.name, commons.surface_prefix_filter) then
        return
    end
    local g = gutils.get_graph(player)
    local grecipe = g.selected_recipe
    if not grecipe then return end

    if not grecipe.is_product then
        msettings.create(player.index, grecipe)
    else
        local product = g.products[grecipe.name]
        tools.fire_user_event(commons.open_recipe_selection, { g = g, product = product, only_product = true })
    end
end

tools.register_user_event(commons.open_current_selection,
    function(player)
        player.opened = nil
        msettings.open_selection(player);
    end)

---@param e EventData.on_lua_shortcut
local function on_control_click(e)

    local player = game.players[e.player_index]
    msettings.open_selection(player)
end
script.on_event(prefix .. "-control-click", on_control_click)

---@param container LuaGuiElement
---@param machine ProductionMachine
function msettings.create_product_line(container, machine)
end

-- React to production computation
tools.register_user_event(commons.production_compute_event, function(data)
    local g = data.g
    local player = g.player
    local frame = player.gui.screen[panel_name]
    if not frame then return end

    local recipe_frame = tools.get_child(frame, "recipe_frame")
    if not recipe_frame then return end

    local recipe_name = recipe_frame.tags.recipe_name --[[@as string]]
    if not recipe_name then return end

    local grecipe = g.recipes[recipe_name]
    if not grecipe then return end

    local config = grecipe.production_config
    if not config then
        config = machinedb.get_default_config(g, grecipe.name, {}) or {}
    end

    local machine = grecipe.machine
    if not machine then
        machine = production.compute_machine(g, grecipe, config) or {}
        machine.count = 1
    end
    recipe_frame.clear()
    msettings.create_product_line(recipe_frame, machine)
    msettings.report(player)
end)

return msettings

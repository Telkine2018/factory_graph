local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local colors = require("scripts.colors")

local add_debug_info = commons.add_debug_info
local prefix = commons.prefix

local recipe_panel = {}

local function np(name)
    return prefix .. "-recipe-panel." .. name
end

local recipe_panel_name = np("frame ")
commons.recipe_panel_name = recipe_panel_name

tools.add_panel_name(recipe_panel_name)

---@param player_index integer
---@param product Product|Ingredient
---@return LocalisedString
---@return integer
local function get_product_label(player_index, product)
    local size = 0
    local caption = { "" }
    table.insert(caption, "[" .. product.type .. "=" .. product.name .. "] ")
    size = 0

    local s
    if product.amount then
        s = tostring(product.amount)
        size = size + #s
        table.insert(caption, s)
    elseif product.amount_min then
        s = tostring(product.amount_min)
        table.insert(caption, s)
        size = size + #s + 1
        table.insert(caption, "-")
        s = tostring(product.amount_max)
        table.insert(caption, s)
        size = size + #s
    end
    if product.probability and product.probability ~= 1 then
        s = " " .. tostring(product.probability * 100) .. "%"
        table.insert(caption, s)
        size = size + #s
    end

    table.insert(caption, " x ")
    size = size + 3

    local lname
    if product.type == "item" then
        lname = translations.get_item_name(player_index, product.name)
    else
        lname = translations.get_fluid_name(player_index, product.name)
    end
    if not lname then
        lname = product.name
    end
    table.insert(caption, " " .. lname)
    size = size + #lname + 1

    return caption, size
end

---@param player_index integer
---@param grecipe GRecipe
function recipe_panel.create(player_index, grecipe)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)

    ---@type LuaRecipePrototype
    local recipe = game.recipe_prototypes[grecipe.name]

    ---@type LocalisedString
    local name = translations.get_recipe_name(player_index, grecipe.name)

    if add_debug_info then
        name = { "", name, "[", grecipe.name, "]" }
    end

    local frame = player.gui.left.add { type = "frame", caption = name, name = recipe_panel_name }
    frame.style.minimal_width = 300

    local flow = frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    ---@param title LocalisedString?
    local function add_line(title)
        gutils.add_line(flow, title)
    end

    local max = 0
    if recipe.ingredients and #recipe.ingredients > 0 then
        add_line({ np("ingredients") })
        for _, p in pairs(recipe.ingredients) do
            local caption, size = get_product_label(player_index, p)
            if size > max then
                max = size
            end
            if add_debug_info then
                caption = { "", caption, " [", p.name, "]" }
            end
            local label = flow.add { type = "label", caption = caption }
            label.style.bottom_margin = 3
        end
    end

    if recipe.products and #recipe.products > 0 then
        add_line({ np("products") })
        for _, p in pairs(recipe.products) do
            local caption, size = get_product_label(player_index, p)
            if size > max then
                max = size
            end
            if add_debug_info then
                caption = { "", caption, " [", p.name, "]" }
            end
            local label = flow.add { type = "label", caption = caption }
            label.style.bottom_margin = 3
        end
    end

    local label = flow.add { type = "label", caption = { np("speed"), tostring(recipe.energy) } }
    label.style.top_margin = 5

    local category = recipe.category
    local machines = game.get_filtered_entity_prototypes { { filter = "crafting-category", crafting_category = category } }

    add_line({ np("craft-in") })
    for _, machine in pairs(machines) do
        local localised = translations.get_entity_name(player.index, machine.name)
        if (localised) then
            local prototypes = game.get_filtered_recipe_prototypes { { filter = "has-product-item", elem_filters = { { filter = "name", name = machine.name } } } }
            if prototypes and next(prototypes) then
                for _, proto in pairs(prototypes) do
                    if player.force.recipes[proto.name].enabled then
                        goto searched
                    end
                end
                localised = "[color=red]" .. localised .. "[/color]"
                if g.show_only_researched then
                    goto next_recipe
                end
                ::searched::
            end
            local label = flow.add { type = "label", caption = { "", "[img=entity/" .. machine.name .. "] ", localised } }
            label.style.bottom_margin = 3
            ::next_recipe::
        end
    end


    local technologies = game.get_filtered_technology_prototypes { { filter = "unlocks-recipe", recipe = recipe.name } }
    if technologies and #technologies > 0 then
        add_line({ np("technology") })

        for _, tech in pairs(technologies) do
            local name = translations.get_technology_name(player_index, tech.name)
            local label = flow.add { type = "label", caption = { "", "[img=technology/" .. tech.name .. "] ", name } }
            label.style.bottom_margin = 3
        end
    end
end

---@param player LuaPlayer
function recipe_panel.close(player)
    local select_panel = player.gui.left[recipe_panel_name]
    if select_panel then
        select_panel.destroy()
    end
end

return recipe_panel

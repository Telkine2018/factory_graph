local commons = require("scripts.commons")
local tools = require("scripts.tools")
local translations = require("scripts.translations")
local gutils = require("scripts.gutils")
local colors = require("scripts.colors")
local production = require("scripts.production")

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
local function get_product_label(player_index, product)
    local caption = { "" }
    table.insert(caption, "[" .. product.type .. "=" .. product.name .. "] ")

    local s
    if product.amount then
        s = tostring(product.amount)
        table.insert(caption, s)
    elseif product.amount_min then
        s = tostring(product.amount_min)
        table.insert(caption, s)
        table.insert(caption, "-")
        s = tostring(product.amount_max)
        table.insert(caption, s)
    end
    if product.probability and product.probability ~= 1 then
        s = " " .. tostring(product.probability * 100) .. "%"
        table.insert(caption, s)
    end

    table.insert(caption, " x ")

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

    return caption
end

---@param player_index integer
---@param grecipe GRecipe
function recipe_panel.create(player_index, grecipe)
    local player = game.players[player_index]
    local g = gutils.get_graph(player)

    ---@type LuaRecipePrototype
    local recipe = prototypes.recipe[grecipe.name]

    ---@type LocalisedString
    local name = translations.get_recipe_name(player_index, grecipe.name)

    if add_debug_info then
        name = { "", name, "[", grecipe.name, "]" }
    end

    ---@type Params.create_standard_panel
    local params  = {
        panel_name         = recipe_panel_name,
        title              = name,
        create_inner_frame = true,
        container          = player.gui.left
    }
    local _, flow = tools.create_standard_panel(player, params)

    ---@param title LocalisedString?
    local function add_line(title)
        gutils.add_line(flow, title)
    end

    local machine = grecipe.machine
    if machine and machine.machine then
        if machine.count and machine.count > 0 then
            local label = flow.add { type = "label", caption = { np("machine-normal"), tools.fround(machine.count), machine.machine.localised_name } }
            label.style.bottom_margin = 3
        else
            local label = flow.add { type = "label", caption = { np("machine-error"), machine.machine.localised_name } }
            label.style.bottom_margin = 3
        end
    end

    if recipe.ingredients and #recipe.ingredients > 0 then
        add_line({ np("ingredients") })
        for _, p in pairs(recipe.ingredients) do
            local caption
            if machine and machine.count and machine.count > 0 then
                local per_machine = production.get_ingredient_amount(machine, p)
                caption = { np("ingredient"),
                    tools.fround(per_machine * machine.count),
                    "[" .. p.type .. "=" .. p.name .. "]",
                    gutils.get_product_name(player, p.type .. "/" .. p.name),
                    "(" .. tools.fround(per_machine) .. "/m)"
                }
            else
                caption = get_product_label(player_index, p)
                if add_debug_info then
                    caption = { "", caption, " [", p.name, "]" }
                end
            end
            local label = flow.add { type = "label", caption = caption }
            label.style.bottom_margin = 3
        end
    end

    if recipe.products and #recipe.products > 0 then
        add_line({ np("products") })
        for _, p in pairs(recipe.products) do
            if p.type ~= "research-progress" then
                local caption

                if machine and machine.count and machine.count > 0 then
                    local per_machine = production.get_product_amount(machine, p)
                    caption = { np("product"),
                        tools.fround(per_machine * machine.count),
                        "[" .. p.type .. "=" .. p.name .. "]",
                        gutils.get_product_name(player, p.type .. "/" .. p.name),
                        "(" .. tools.fround(per_machine) .. "/m)"
                    }
                else
                    caption = get_product_label(player_index, p)
                    if add_debug_info then
                        caption = { "", caption, " [", p.name, "]" }
                    end
                end
                local label = flow.add { type = "label", caption = caption }
                label.style.bottom_margin = 3
            end
        end
    end

    local label = flow.add { type = "label", caption = { np("speed"), tostring(recipe.energy) } }
    label.style.top_margin = 5

    local category = recipe.category
    local machines = prototypes.get_entity_filtered { { filter = "crafting-category", crafting_category = category } }

    local technologies = prototypes.get_technology_filtered { { filter = "unlocks-recipe", recipe = recipe.name } }
    if technologies and #technologies > 0 then
        add_line({ np("technology") })

        for _, tech in pairs(technologies) do
            local name = translations.get_technology_name(player_index, tech.name)
            local label = flow.add { type = "label", caption = { "", "[img=technology/" .. tech.name .. "] ", name } }
            label.style.bottom_margin = 3
        end
    end

    add_line({ np("craft-in") })
    for _, machine in pairs(machines) do
        local localised = translations.get_entity_name(player.index, machine.name)
        if (localised) then
            local prototypes = prototypes.get_recipe_filtered { { filter = "has-product-item", elem_filters = { { filter = "name", name = machine.name } } } }
            if prototypes and #prototypes > 0 then
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
end

---@param player LuaPlayer
function recipe_panel.close(player)
    local select_panel = player.gui.left[recipe_panel_name]
    if select_panel then
        select_panel.destroy()
    end
end

tools.register_user_event(commons.graph_selection_change_event,
    ---@param data {g:Graph, grecipe:GRecipe}
    function(data)
        recipe_panel.close(data.g.player)
        if data.grecipe then
            recipe_panel.create(data.g.player.index, data.grecipe)
        end
    end
)

return recipe_panel


local dictionary = require("__flib__.dictionary-lite")

-- local dictionary = require("scripts.dictionary-lite")

local commons = require("scripts.commons")
local tools = require("scripts.tools")

local translations = {}

local recipe_name = "recipe_name"
local recipe_description = "recipe_description"

---@param dic_name string
---@param name string
---@param localised string
local function add(dic_name, name, localised)
    if type(localised) == "table" then
        dictionary.add(dic_name, name, localised)
    end
end

---@param type string
---@param prototypes {[string]:any}
local function load_names_and_descriptions(type, prototypes)

    local dic_name = type .. "_name"
    local dic_description = type .. "_description"
    dictionary.new(dic_name)
    dictionary.new(dic_description)

    for name, proto in pairs(prototypes) do
        add(dic_name, name, proto.localised_name)
        add(dic_description, name, proto.localised_description)
    end
end

---@param type string
---@param prototypes {[string]:any}
local function load_names(type, prototypes)

    local dic_name = type .. "_name"
    dictionary.new(dic_name)

    for name, proto in pairs(prototypes) do
        add(dic_name, name, proto.localised_name)
    end
end


local function load_translations()
    load_names_and_descriptions("fluid", game.fluid_prototypes)
    load_names_and_descriptions("item", game.item_prototypes)

    load_names_and_descriptions("recipe_category", game.recipe_category_prototypes)
    load_names_and_descriptions("recipe", game.recipe_prototypes)

    load_names("entity", game.entity_prototypes)
    load_names("technology", game.technology_prototypes)
end

tools.on_init(function()
    dictionary.on_init()
    load_translations()
end)

tools.on_configuration_changed(function(data)
    dictionary.on_configuration_changed()
    load_translations()
end)

for event, handler in pairs(dictionary.events) do
    tools.on_event(event, handler)
end

---@param player_index integer
---@param dic_name string
---@param name string
---@return string?
function translations.get_translation(player_index, dic_name, name)
    local player = game.get_player(player_index) 
    ---@cast player -nil
    local vars = tools.get_vars(player)
    if not vars.translations then
        return nil
    end
    local dic = vars.translations[dic_name]
    if not dic then
        return nil
    end
    return dic[name]
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_recipe_name(player_index, name)
    return translations.get_translation(player_index, "recipe_name", name) or ""
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_recipe_description(player_index, name)
    return translations.get_translation(player_index, "recipe_description", name) or ""
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_fluid_name(player_index, name)
    return translations.get_translation(player_index, "fluid_name", name) or ""
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_fluid_description(player_index, name)
    return translations.get_translation(player_index, "fluid_description", name) or ""
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_item_name(player_index, name)
    return translations.get_translation(player_index, "item_name", name) or ""
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_item_description(player_index, name)
    return translations.get_translation(player_index, "item_description", name)
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_entity_name(player_index, name)
    return translations.get_translation(player_index, "entity_name", name) or ""
end

---@param player_index integer
---@param name string
---@return string?
function translations.get_technology_name(player_index, name)
    return translations.get_translation(player_index, "technology_name", name) or ""
end

---@param player_index integer
---@param dic_name string
---@return table<string, string>
function translations.get_all(player_index, dic_name)
    return dictionary.get_all(player_index)[dic_name]
end

script.on_event(dictionary.on_player_dictionaries_ready, function(e)
    local player = game.players[e.player_index]
    local vars = tools.get_vars(player)
    vars.translations = dictionary.get_all(e.player_index)
  end)
  
return translations


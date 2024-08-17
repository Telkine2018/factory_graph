

local commons = require("scripts.commons")

local prefix = commons.prefix

data:extend(
    {
		{
			type = "int-setting",
			name = prefix .. "-version",
			setting_type = "startup",
			default_value = 1
		},
		{
			type = "int-setting",
			name = prefix .. "-saving-height",
			setting_type = "runtime-per-user",
			default_value = 700,
			minimum_value = 400
		},
		{
			type = "bool-setting",
			name = prefix .. "-saving-auto",
			setting_type = "runtime-per-user",
			default_value = true
		},
		{
			type = "string-setting",
			setting_type = "runtime-global",
			name = prefix .. "-auto_layout",
			allowed_values = { "standard", "htree", "htreei", "vtree", "vtreei"},
			default_value = "htree"
		}

})

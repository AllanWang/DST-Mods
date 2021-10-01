name = "Advanced Tooltips [Tau]"
description = [[
Display a lot more information on item tooltips:
Food hunger/health/sanity values, spoiling time, weapon damage, item durability, armor durability & protection, and clothing insulation.
]]
author = "anuradeux"
version = "2.0.3"

forumthread = ""

api_version = 10
dst_compatible = true

client_only_mod = true
all_clients_require_mod = false

icon_atlas = "modicon.xml"
icon = "modicon.tex"

priority = 3

configuration_options = {
    {
        name = "OPT_ENABLE_DAMAGE",
        label = "Weapon Damage",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_ENABLE_USES",
        label = "Durability Left",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_ENABLE_TEMPERATURE",
        label = "Heatstone Temperature",
        hover = "Only works for the host",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_ENABLE_ARMOR",
        label = "Armor condition",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_ENABLE_INSULATION",
        label = "Clothing Insulation",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_ENABLE_FOOD_VALUES",
        label = "Food Values",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_ENABLE_SPOIL_TIME",
        label = "Food Spoil Time",
        options = {
            {description = "Show", data = true},
            {description = "Hide", data = false}
        },
        default = true
    }, {
        name = "OPT_REPLACE_USES_PERCENTAGE",
        label = "Durability Display Icon",
        hover = "Replace durability icon percentages with remaining amount or time",
        options = {
            {description = "Durability", data = true},
            {description = "Percentage", data = false}
        },
        default = false
    }, {
        name = "OPT_REPLACE_ARMOR_PERCENTAGE",
        label = "Armor Display Icon",
        hover = "Replace armor percentages with remaining armor value",
        options = {
            {description = "HP left", data = true},
            {description = "Percentage", data = false}
        },
        default = false
    }, {
        name = "OPT_TIME_ALWAYS_REAL",
        label = "Time Format",
        hover = "Sets the time formatting",
        options = {
            {description = "Days", data = false},
            {description = "Min:Sec", data = true}
        },
        default = false
    }, {
        name = "OPT_FOOD_COMPACT",
        label = "Compact Food Values",
        hover = "Food values are formatted as (hunger/sanity/health)",
        options = {
            {description = "On", data = true},
            {description = "Off", data = false}
        },
        default = false
    }, {
        name = "OPT_SHOW_MAX",
        label = "Show Maximum Amount",
        hover = "Show the maximum amounts as (current/max)",
        options = {
            {description = "On", data = true},
            {description = "Off", data = false}
        },
        default = true
    }, {
        name = "OPT_USE_FAHRENHEIT",
        label = "Temperature Units",
        hover = "Uses fahrenheit or celcius for temperatures",
        options = {
            {description = "Celcius", data = false},
            {description = "Fahrenheit", data = true}
        },
        default = false
    }
}

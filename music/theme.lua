local THEMES = {
    default = {
        name = "Default",
        tabs = {
            active_bg = colors.white,
            active_text = colors.black,
            inactive_bg = colors.gray,
            inactive_text = colors.white
        },
        progress = {
            bg = colors.gray,
            fg = colors.cyan,
            volume = colors.white
        },
        status = {
            playing = colors.green,
            paused = colors.orange,
            loading = colors.yellow,
            error = colors.red
        },
        scroll = {
            track = colors.gray,
            thumb = colors.lightGray,
            arrow = colors.white
        },
        visualization = {
            low = colors.green,
            mid = colors.yellow,
            high = colors.red
        },
        selected = colors.lightBlue,
        popup_bg = colors.lightGray,
        popup_text = colors.black
    },
    dark = {
        name = "Dark",
        tabs = {
            active_bg = colors.lightGray,
            active_text = colors.white,
            inactive_bg = colors.black,
            inactive_text = colors.gray
        },
        progress = {
            bg = colors.black,
            fg = colors.purple,
            volume = colors.pink
        },
        status = {
            playing = colors.lime,
            paused = colors.yellow,
            loading = colors.orange,
            error = colors.red
        },
        scroll = {
            track = colors.black,
            thumb = colors.gray,
            arrow = colors.white
        },
        visualization = {
            low = colors.blue,
            mid = colors.purple,
            high = colors.pink
        },
        selected = colors.purple,
        popup_bg = colors.gray,
        popup_text = colors.white
    },
    ocean = {
        name = "Ocean",
        tabs = {
            active_bg = colors.lightBlue,
            active_text = colors.white,
            inactive_bg = colors.blue,
            inactive_text = colors.lightBlue
        },
        progress = {
            bg = colors.blue,
            fg = colors.lightBlue,
            volume = colors.cyan
        },
        status = {
            playing = colors.cyan,
            paused = colors.lightBlue,
            loading = colors.white,
            error = colors.red
        },
        scroll = {
            track = colors.blue,
            thumb = colors.lightBlue,
            arrow = colors.white
        },
        visualization = {
            low = colors.cyan,
            mid = colors.lightBlue,
            high = colors.white
        },
        selected = colors.cyan,
        popup_bg = colors.blue,
        popup_text = colors.white
    }
}

local current_colors = THEMES.default

local function apply_theme(theme_name, State)
    if THEMES[theme_name] then
        current_colors = THEMES[theme_name]
        if State then
            State.current_theme = theme_name
            State.settings.theme = theme_name
        end
    end
end

return {
    THEMES = THEMES,
    current_colors = function() return current_colors end,
    apply_theme = apply_theme
}
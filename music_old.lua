-- ========================================
-- CC Music Player v5.0
-- ========================================

-- FORWARD DECLARATIONS - Declare all modules first
local Utils = {}
local Config = {}
local ThemeManager = {}
local StateManager = {}
local DataManager = {}
local EventManager = {}
local NetworkManager = {}
local AudioManager = {}
local MusicPlayer = {}

-- CONFIGURATION
local CONFIG = {
    api_base_url = "http://127.0.0.1:5000",
    buffer_threshold = 20,
    buffer_max = 40,
    retry_delay = 2,
    chunk_request_ahead = 10,
    update_interval = 0.25,
    audio_sample_rate = 48000,
    audio_chunk_size = 2^12,
    version = "5.0",
    update_check_url = "https://raw.githubusercontent.com/edujime23/computercraft-music-player/refs/heads/main/version.txt",

    -- File paths
    queue_file = "music_queue.dat",
    history_file = "music_history.dat",
    favorites_file = "music_favorites.dat",
    settings_file = "music_settings.dat",
    playlists_file = "music_playlists.dat",
    themes_file = "music_themes.dat",
    profiles_file = "music_profiles.dat"
}

-- THEMES
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

local REPEAT_MODES = { OFF = 0, ONE = 1, ALL = 2 }
local TABS = { NOW_PLAYING = 1, SEARCH = 2, QUEUE = 3, PLAYLISTS = 4, HISTORY = 5, FAVORITES = 6, SETTINGS = 7, DIAGNOSTICS = 8 }
local VIS_MODES = { BARS = 1, WAVE = 2, SPECTRUM = 3, VU = 4 }

-- UI LAYOUT CONSTANTS
local TAB_LIST_WIDTH = 15
local TAB_DATA = {
    { id = TABS.NOW_PLAYING,    name = "Now Playing" },
    { id = TABS.SEARCH,       name = "Search" },
    { id = TABS.QUEUE,        name = "Queue" },
    { id = TABS.PLAYLISTS,    name = "Playlists" },
    { id = TABS.HISTORY,      name = "History" },
    { id = TABS.FAVORITES,    name = "Favorites" },
    { id = TABS.SETTINGS,     name = "Settings" },
    { id = TABS.DIAGNOSTICS,  name = "Diagnostics" }
}

-- HOTKEYS
local HOTKEYS = {
    play_pause = keys.p,
    next = keys.n,
    volume_up = keys.equals,
    volume_down = keys.minus,
    favorite = keys.f,
    mini_mode = keys.m,
    search = keys.s,
    queue = keys.q,
    help = keys.h
}

-- INITIALIZATION
local speaker = peripheral.find("speaker")
if not speaker then
    error("No speaker found! Connect a speaker block.")
end

-- STATE MANAGEMENT
local State = {
    -- UI State
    screen = { width = 0, height = 0 },
    current_tab = TABS.NOW_PLAYING,
    waiting_input = false,
    input_text = "",
    input_context = nil,
    status_message = nil,
    status_color = colors.white,
    status_timer = nil,
    mini_mode = false,
    show_popup = false,
    popup_content = nil,
    current_theme = "default",
    show_help = false,

    -- Profile State
    current_profile = "default",
    profiles = { default = { name = "Default User" } },

    -- Navigation State
    selected_index = {
        [TABS.SEARCH] = 1,
        [TABS.QUEUE] = 1,
        [TABS.PLAYLISTS] = 1,
        [TABS.HISTORY] = 1,
        [TABS.FAVORITES] = 1,
        [TABS.SETTINGS] = 1,
        [TABS.DIAGNOSTICS] = 1
    },
    keyboard_nav_active = false,

    -- Search State
    last_query = "",
    last_search_url = nil,
    search_results = nil,
    search_error = nil,
    search_scroll = 0,
    search_filter = "",

    -- Lists State
    queue = {},
    history = {},
    favorites = {},
    playlists = {},
    repeat_mode = REPEAT_MODES.OFF,
    shuffle = false,
    queue_scroll = 0,
    history_scroll = 0,
    favorites_scroll = 0,
    playlists_scroll = 0,
    queue_filter = "",
    history_filter = "",
    favorites_filter = "",

    -- Playlist State
    selected_playlist = nil,
    editing_playlist = false,
    playlist_input = "",

    -- Queue Reordering
    reordering_queue = false,
    reorder_from = nil,
    reorder_to = nil,
    dragging_queue_item = false,
    drag_item_index = nil,

    -- Scroll bar drag state
    dragging_scroll = false,
    drag_scroll_type = nil,
    drag_start_y = 0,
    drag_start_scroll = 0,

    -- Playback State
    session_id = nil,
    is_streaming = false,
    is_playing = false,
    current_song = nil,
    loading = false,
    ended = false,

    -- Audio State
    buffer = {},
    volume = 1.0,
    playback_position = 0,
    total_duration = 0,
    chunks_played = 0,
    samples_per_chunk = CONFIG.audio_chunk_size,
    sample_rate = CONFIG.audio_sample_rate,
    buffer_size_on_pause = 0,
    downloaded_chunks = {},

    -- Visualization
    current_chunk_rms = 0,
    visualization_data = {},
    visualization_mode = VIS_MODES.BARS,
    spectrum_data = {},
    vu_left = 0,
    vu_right = 0,

    -- Connection State
    connection_errors = 0,
    chunk_request_pending = false,
    last_chunk_time = 0,
    avg_chunk_latency = 0,
    total_bytes_received = 0,

    -- Settings
    settings = {
        api_url = CONFIG.api_base_url,
        buffer_size = CONFIG.buffer_max,
        sample_rate = CONFIG.audio_sample_rate,
        chunk_size = CONFIG.audio_chunk_size,
        auto_play_next = true,
        show_visualization = true,
        theme = "default",
        sleep_timer = 0,
        sleep_timer_active = false,
        notifications = true,
        check_updates = true
    },
    settings_scroll = 0,
    editing_setting = nil,

    -- Sleep Timer
    sleep_timer_start = nil
}

-- Store scroll bar info for click detection
local scroll_infos = {}
local current_colors = THEMES.default

-- FORWARD DECLARATIONS
local redraw
local save_state
local load_state
local apply_theme
local show_notification

-- CORE UTILITIES
Utils = {
    -- Error handling with proper logging
    try = function(fn, catch_fn)
        local success, result = pcall(fn)
        if not success then
            if catch_fn then catch_fn(result) end
            return nil, result
        end
        return result
    end,

    -- Safe table access with defaults
    safeGet = function(tbl, key, default)
        if not tbl or type(tbl) ~= "table" then return default end
        local value = tbl[key]
        return value ~= nil and value or default
    end,

    -- Clamp values
    clamp = function(value, min_val, max_val)
        return math.max(min_val, math.min(max_val, value or 0))
    end,

    -- Format time safely
    formatTime = function(seconds)
        if not seconds or type(seconds) ~= "number" or seconds < 0 then
            return "--:--"
        end
        local mins = math.floor(seconds / 60)
        local secs = math.floor(seconds % 60)
        return string.format("%d:%02d", mins, secs)
    end,

    -- Truncate text safely
    truncate = function(text, maxLen)
        text = tostring(text or "")
        return #text > maxLen and (text:sub(1, maxLen - 3) .. "...") or text
    end,

    -- UUID generation for sessions
    uuid = function()
        return string.format("%x%x%x%x",
            math.random(0, 0xffff), math.random(0, 0xffff),
            math.random(0, 0xffff), math.random(0, 0xffff))
    end,

    -- Format bytes
    formatBytes = function(bytes)
        bytes = bytes or 0
        if bytes < 1024 then
            return bytes .. "B"
        elseif bytes < 1024 * 1024 then
            return string.format("%.1fKB", bytes / 1024)
        else
            return string.format("%.1fMB", bytes / (1024 * 1024))
        end
    end,

    -- Shuffle table
    shuffle = function(tbl)
        local shuffled = {}
        for i = 1, #tbl do shuffled[i] = tbl[i] end

        for i = #shuffled, 2, -1 do
            local j = math.random(1, i)
            shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        end
        return shuffled
    end
}

-- FILE OPERATIONS
local function save_table_to_file(tbl, filename)
    local file = fs.open(filename, "w")
    if file then
        file.write(textutils.serialize(tbl))
        file.close()
        return true
    end
    return false
end

local function load_table_from_file(filename)
    if fs.exists(filename) then
        local file = fs.open(filename, "r")
        if file then
            local content = file.readAll()
            file.close()
            local success, result = pcall(textutils.unserialize, content)
            if success and type(result) == "table" then
                return result
            end
        end
    end
    return nil
end

function save_state()
    save_table_to_file(State.queue, CONFIG.queue_file)
    save_table_to_file(State.history, CONFIG.history_file)
    save_table_to_file(State.favorites, CONFIG.favorites_file)
    save_table_to_file(State.settings, CONFIG.settings_file)
    save_table_to_file(State.playlists, CONFIG.playlists_file)
    save_table_to_file(State.profiles, CONFIG.profiles_file)
end

function load_state()
    State.queue = load_table_from_file(CONFIG.queue_file) or {}
    State.history = load_table_from_file(CONFIG.history_file) or {}
    State.favorites = load_table_from_file(CONFIG.favorites_file) or {}
    State.playlists = load_table_from_file(CONFIG.playlists_file) or {}
    State.profiles = load_table_from_file(CONFIG.profiles_file) or { default = { name = "Default User" } }

    local loaded_settings = load_table_from_file(CONFIG.settings_file)
    if loaded_settings then
        local s = State.settings
        s.api_url             = type(loaded_settings.api_url) == "string" and loaded_settings.api_url or CONFIG.api_base_url
        s.buffer_size         = tonumber(loaded_settings.buffer_size) or CONFIG.buffer_max
        s.sample_rate         = tonumber(loaded_settings.sample_rate) or CONFIG.audio_sample_rate
        s.chunk_size          = tonumber(loaded_settings.chunk_size) or CONFIG.audio_chunk_size
        s.auto_play_next      = type(loaded_settings.auto_play_next) == "boolean" and loaded_settings.auto_play_next or true
        s.show_visualization  = type(loaded_settings.show_visualization) == "boolean" and loaded_settings.show_visualization or true
        s.theme               = THEMES[loaded_settings.theme] and loaded_settings.theme or "default"
        s.sleep_timer         = tonumber(loaded_settings.sleep_timer) or 0
        s.notifications       = type(loaded_settings.notifications) == "boolean" and loaded_settings.notifications or true
        s.check_updates       = type(loaded_settings.check_updates) == "boolean" and loaded_settings.check_updates or true
    end

    -- Apply loaded settings
    CONFIG.api_base_url = State.settings.api_url
    CONFIG.buffer_max = State.settings.buffer_size
    CONFIG.audio_sample_rate = State.settings.sample_rate
    CONFIG.audio_chunk_size = State.settings.chunk_size
    apply_theme(State.settings.theme)
end

-- THEME SYSTEM
function apply_theme(theme_name)
    if THEMES[theme_name] then
        current_colors = THEMES[theme_name]
        State.current_theme = theme_name
        State.settings.theme = theme_name
    end
end

-- NOTIFICATIONS
function show_notification(message, duration)
    if State.settings.notifications then
        State.status_message = "♪ " .. message
        State.status_color = current_colors.status.playing
        if State.status_timer then
            os.cancelTimer(State.status_timer)
        end
        if duration then
            State.status_timer = os.startTimer(duration)
        end
        redraw()
    end
end

-- STATUS BAR
local function set_status(message, color, duration)
    State.status_message = message
    State.status_color = color or colors.white

    if State.status_timer then
        os.cancelTimer(State.status_timer)
    end

    if duration then
        State.status_timer = os.startTimer(duration)
    end

    redraw()
end

-- UTILITY FUNCTIONS (Original ones)
local function format_time(seconds)
    if not seconds or type(seconds) ~= "number" or seconds <= 0 then return "--:--" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

local function format_bytes(bytes)
    bytes = bytes or 0
    if bytes < 1024 then
        return bytes .. "B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1fKB", bytes / 1024)
    else
        return string.format("%.1fMB", bytes / (1024 * 1024))
    end
end

local function shuffle_table(tbl)
    local shuffled = {}
    for i = 1, #tbl do shuffled[i] = tbl[i] end

    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    return shuffled
end

local function truncate_text(text, max_length)
    text = text or ""
    if #text > max_length then
        return string.sub(text, 1, max_length - 3) .. "..."
    end
    return text
end

local function find_song_in_favorites(song)
    if not song or not song.id then return nil end
    for i, fav in ipairs(State.favorites) do
        if fav.id == song.id then
            return i
        end
    end
    return nil
end

local function is_favorite(song)
    return find_song_in_favorites(song) ~= nil
end

local function toggle_favorite(song)
    if not song or not song.id then return end
    local idx = find_song_in_favorites(song)
    if idx then
        table.remove(State.favorites, idx)
        set_status("Removed from favorites", current_colors.status.error, 2)
    else
        table.insert(State.favorites, 1, song)
        set_status("Added to favorites", current_colors.status.playing, 2)
    end
    save_state()
end

local function filter_list(list, filter)
    if not filter or filter == "" then return list end

    local filtered = {}
    local filter_lower = string.lower(filter)

    for _, item in ipairs(list) do
        local title_lower = string.lower(item.title or "")
        local artist_lower = string.lower(item.artist or "")

        if string.find(title_lower, filter_lower, 1, true) or
           string.find(artist_lower, filter_lower, 1, true) then
            table.insert(filtered, item)
        end
    end

    return filtered
end

local function draw_progress_bar(x, y, width, progress, bg_color, fg_color)
    paintutils.drawBox(x, y, x + width - 1, y, bg_color)
    local filled = math.floor(width * (progress or 0))
    if filled > 0 then
        paintutils.drawBox(x, y, x + filled - 1, y, fg_color)
    end
end

-- VISUALIZATION
local function update_visualization_data(chunk)
    if not State.settings.show_visualization or not chunk then return end

    -- Calculate RMS (root mean square) for volume level
    local sum = 0
    local sum_left = 0
    local sum_right = 0

    for i = 1, #chunk do
        sum = sum + (chunk[i] ^ 2)
        -- Simulate stereo for VU meter
        if i % 2 == 1 then
            sum_left = sum_left + (chunk[i] ^ 2)
        else
            sum_right = sum_right + (chunk[i] ^ 2)
        end
    end

    State.current_chunk_rms = math.sqrt(sum / #chunk) / 128
    State.vu_left = math.sqrt(sum_left / (#chunk / 2)) / 128
    State.vu_right = math.sqrt(sum_right / (#chunk / 2)) / 128

    -- Add to visualization buffer
    table.insert(State.visualization_data, State.current_chunk_rms)
    if #State.visualization_data > 20 then
        table.remove(State.visualization_data, 1)
    end

    -- Simple spectrum analysis (fake it with RMS variations)
    State.spectrum_data = {}
    for i = 1, 8 do
        State.spectrum_data[i] = State.current_chunk_rms * (0.5 + math.random() * 0.5) * (1 - (i - 1) / 8)
    end
end

local function draw_visualization(x, y, width, height)
    if not State.settings.show_visualization or #State.visualization_data == 0 then
        return
    end

    term.setBackgroundColor(colors.black)

    if State.visualization_mode == VIS_MODES.BARS then
        -- Bar visualization
        local bar_width = math.floor(width / #State.visualization_data)
        for i, value in ipairs(State.visualization_data) do
            local bar_height = math.floor(value * height)
            local bar_x = x + (i - 1) * bar_width

            for h = 0, bar_height - 1 do
                local color = current_colors.visualization.low
                if h > height * 0.66 then
                    color = current_colors.visualization.high
                elseif h > height * 0.33 then
                    color = current_colors.visualization.mid
                end

                term.setCursorPos(bar_x, y + height - h - 1)
                term.setBackgroundColor(color)
                for w = 1, bar_width - 1 do
                    term.write(" ")
                end
            end
        end
    elseif State.visualization_mode == VIS_MODES.WAVE then
        -- Waveform visualization
        for i = 1, width do
            local idx = math.floor((i / width) * #State.visualization_data) + 1
            local value = State.visualization_data[idx] or 0
            local wave_height = math.floor(value * height)

            term.setCursorPos(x + i - 1, y + math.floor(height / 2) - math.floor(wave_height / 2))
            term.setBackgroundColor(current_colors.visualization.mid)
            for h = 1, wave_height do
                term.setCursorPos(x + i - 1, y + math.floor(height / 2) - math.floor(wave_height / 2) + h - 1)
                term.write(" ")
            end
        end
    elseif State.visualization_mode == VIS_MODES.SPECTRUM then
        -- Spectrum analyzer
        local bar_width = math.floor(width / #State.spectrum_data)
        for i, value in ipairs(State.spectrum_data) do
            local bar_height = math.floor(value * height)
            local bar_x = x + (i - 1) * bar_width

            for h = 0, bar_height - 1 do
                term.setCursorPos(bar_x, y + height - h - 1)
                term.setBackgroundColor(current_colors.visualization.low)
                for w = 1, bar_width - 1 do
                    term.write(" ")
                end
            end
        end
    elseif State.visualization_mode == VIS_MODES.VU then
        -- VU Meter
        local meter_width = math.floor((width - 3) / 2)

        -- Left channel
        term.setCursorPos(x, y)
        term.setTextColor(colors.white)
        term.write("L")
        draw_progress_bar(x + 2, y, meter_width, State.vu_left,
                         current_colors.progress.bg, current_colors.visualization.mid)

        -- Right channel
        term.setCursorPos(x, y + 1)
        term.write("R")
        draw_progress_bar(x + 2, y + 1, meter_width, State.vu_right,
                         current_colors.progress.bg, current_colors.visualization.mid)
    end

    term.setBackgroundColor(colors.black)
end

-- POPUP SYSTEM
local function draw_popup(title, content, width, height)
    local w, h = State.screen.width, State.screen.height
    local x = math.floor((w - width) / 2)
    local y = math.floor((h - height) / 2)

    -- Draw background
    paintutils.drawFilledBox(x, y, x + width, y + height, current_colors.popup_bg)

    -- Draw border
    paintutils.drawBox(x, y, x + width, y + height, colors.black)

    -- Draw title
    term.setCursorPos(x + 2, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(" " .. title .. " ")

    -- Draw close button
    term.setCursorPos(x + width - 2, y)
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.write(" X ")

    -- Draw content
    term.setBackgroundColor(current_colors.popup_bg)
    term.setTextColor(current_colors.popup_text)

    local line_y = y + 2
    for line in content:gmatch("[^\n]+") do
        if line_y < y + height then
            term.setCursorPos(x + 2, line_y)
            term.write(truncate_text(line, width - 3))
            line_y = line_y + 1
        end
    end

    return x, y, width, height
end

-- SONG INFO POPUP
local function show_song_info_popup(song)
    if not song then return end

    local info = "Title: " .. (song.title or "Unknown") .. "\n"
    info = info .. "Artist: " .. (song.artist or "Unknown") .. "\n"
    info = info .. "Duration: " .. format_time(song.duration or 0) .. "\n"
    info = info .. "ID: " .. (song.id or "Unknown") .. "\n"

    if song.view_count then
        info = info .. "Views: " .. tostring(song.view_count) .. "\n"
    end

    info = info .. "\nFavorite: " .. (is_favorite(song) and "Yes" or "No")

    State.popup_content = {
        type = "song_info",
        title = "Song Information",
        content = info,
        width = 40,
        height = 10,
        song = song
    }
    State.show_popup = true
    redraw()
end

-- HELP POPUP
local function show_help_popup()
    local help = "=== HOTKEYS ===\n"
    help = help .. "P - Play/Pause\n"
    help = help .. "N - Next Track\n"
    help = help .. "+ - Volume Up\n"
    help = help .. "- - Volume Down\n"
    help = help .. "F - Toggle Favorite\n"
    help = help .. "M - Mini Mode\n"
    help = help .. "S - Go to Search\n"
    help = help .. "Q - Go to Queue\n"
    help = help .. "Tab - Next Tab\n"
    help = help .. "Space - Play/Pause\n"
    help = help .. "Arrows - Navigate\n"
    help = help .. "Enter - Select\n"
    help = help .. "Del - Remove Item\n"
    help = help .. "H - This Help\n"

    State.popup_content = {
        type = "help",
        title = "Help",
        content = help,
        width = 30,
        height = 17
    }
    State.show_popup = true
    redraw()
end

-- MINI MODE
local function draw_mini_mode()
    term.clear()
    local w, h = State.screen.width, State.screen.height

    -- Title
    term.setCursorPos(1, 1)
    term.setBackgroundColor(current_colors.tabs.active_bg)
    term.setTextColor(current_colors.tabs.active_text)
    term.clearLine()
    term.write(" CC Music Player - Mini Mode ")

    term.setCursorPos(w - 10, 1)
    term.setBackgroundColor(colors.gray)
    term.write(" Normal ")

    term.setBackgroundColor(colors.black)

    if State.current_song then
        -- Song info
        term.setCursorPos(2, 3)
        term.setTextColor(colors.white)
        term.write(truncate_text(State.current_song.title or "Unknown", w - 4))

        term.setCursorPos(2, 4)
        term.setTextColor(colors.lightGray)
        term.write(truncate_text(State.current_song.artist or "Unknown", w - 4))

        -- Progress
        if State.total_duration > 0 then
            term.setCursorPos(2, 6)
            term.setTextColor(colors.white)
            term.write(format_time(State.playback_position) .. " / " .. format_time(State.total_duration))
            draw_progress_bar(2, 7, w - 3, State.playback_position / State.total_duration,
                            current_colors.progress.bg, current_colors.progress.fg)
        end

        -- Controls
        term.setCursorPos(2, 9)
        term.setBackgroundColor(State.is_playing and colors.red or colors.green)
        term.setTextColor(colors.white)
        term.write(State.is_playing and " Pause " or " Play ")

        term.setCursorPos(10, 9)
        term.setBackgroundColor(colors.gray)
        term.write(" Next ")

        term.setCursorPos(17, 9)
        term.setBackgroundColor(is_favorite(State.current_song) and colors.yellow or colors.gray)
        term.write(" Fav ")

        -- Volume
        term.setCursorPos(2, 11)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write("Vol: ")
        draw_progress_bar(7, 11, 15, State.volume, current_colors.progress.bg, current_colors.progress.volume)
        term.setCursorPos(24, 11)
        term.write(math.floor(State.volume * 100) .. "%")

        -- Small visualization
        if State.settings.show_visualization and h > 13 then
            draw_visualization(2, 13, w - 3, h - 14)
        end
    else
        term.setCursorPos(2, 3)
        term.setTextColor(colors.gray)
        term.write("No song playing")
    end

    -- Status bar
    if State.status_message then
        term.setCursorPos(1, h)
        term.setBackgroundColor(colors.gray)
        term.clearLine()
        term.setTextColor(State.status_color)
        term.setCursorPos(2, h)
        term.write(truncate_text(State.status_message, w - 4))
    end
end

-- INTERACTIVE SCROLL BAR
local function draw_scroll_bar(x, start_y, height, total_items, visible_items, scroll_pos, scroll_type)
    if total_items <= visible_items then
        scroll_infos[scroll_type] = nil
        return nil
    end

    -- Draw scroll track
    for i = 0, height - 1 do
        term.setCursorPos(x, start_y + i)
        term.setBackgroundColor(current_colors.scroll.track)
        term.setTextColor(colors.black)
        term.write(" ")
    end

    -- Calculate thumb position and size
    local thumb_size = math.max(1, math.floor(height * visible_items / total_items))
    local max_scroll = total_items - visible_items
    local thumb_pos = 0
    if max_scroll > 0 then
        thumb_pos = math.floor((height - thumb_size) * scroll_pos / max_scroll)
    end
    thumb_pos = math.max(0, math.min(thumb_pos, height - thumb_size))

    -- Draw thumb
    for i = 0, thumb_size - 1 do
        term.setCursorPos(x, start_y + thumb_pos + i)
        term.setBackgroundColor(current_colors.scroll.thumb)
        term.setTextColor(colors.black)
        term.write(" ")
    end

    -- Draw arrows
    term.setCursorPos(x, start_y)
    term.setBackgroundColor(current_colors.scroll.track)
    term.setTextColor(current_colors.scroll.arrow)
    term.write("^")

    term.setCursorPos(x, start_y + height - 1)
    term.setBackgroundColor(current_colors.scroll.track)
    term.setTextColor(current_colors.scroll.arrow)
    term.write("v")

    local info = {
        x = x,
        start_y = start_y,
        height = height,
        total_items = total_items,
        visible_items = visible_items,
        scroll_pos = scroll_pos,
        thumb_pos = thumb_pos,
        thumb_size = thumb_size,
        max_scroll = max_scroll
    }

    scroll_infos[scroll_type] = info
    return info
end

-- DOWNLOAD SONG
local function download_song()
    if not State.current_song or #State.downloaded_chunks == 0 then
        set_status("No song to download", current_colors.status.error, 2)
        return
    end

    local filename = "song_" .. State.current_song.id .. ".pcm"
    local file = fs.open(filename, "wb")

    if file then
        for _, chunk in ipairs(State.downloaded_chunks) do
            for _, sample in ipairs(chunk) do
                file.write(sample)
            end
        end
        file.close()
        set_status("Downloaded to " .. filename, current_colors.status.playing, 3)
    else
        set_status("Failed to save file", current_colors.status.error, 2)
    end
end

-- CREATE PLAYLIST
local function create_playlist(name)
    if not name or name == "" then return end

    State.playlists[name] = {
        name = name,
        songs = {},
        created = os.time()
    }
    save_state()
    set_status("Created playlist: " .. name, current_colors.status.playing, 2)
end

-- UPDATE CHECKER
local function check_for_updates()
    if not State.settings.check_updates then return end

    http.request(CONFIG.update_check_url)
    -- Response handled in http_loop
end

-- SLEEP TIMER
local function update_sleep_timer()
    if State.settings.sleep_timer_active and State.sleep_timer_start then
        local elapsed = os.clock() - State.sleep_timer_start
        local remaining = State.settings.sleep_timer * 60 - elapsed

        if remaining <= 0 then
            State.settings.sleep_timer_active = false
            State.is_playing = false
            set_status("Sleep timer expired", colors.white, 3)
            show_notification("Sleep timer expired - playback stopped", 5)
        end
    end
end

-- NETWORK DIAGNOSTICS
local function calculate_network_stats()
    local stats = {
        session_active = State.session_id ~= nil,
        buffer_fill = math.floor((#State.buffer / (State.settings.buffer_size or CONFIG.buffer_max)) * 100),
        connection_errors = State.connection_errors or 0,
        avg_latency = State.avg_chunk_latency or 0,
        bytes_received = State.total_bytes_received or 0,
        chunks_downloaded = State.downloaded_chunks and #State.downloaded_chunks or 0,
        uptime = (State.session_id and (os.clock() - (State.stream_start_time or os.clock()))) or 0
    }
    return stats
end

-- SCROLL HANDLERS
local function handle_list_scroll(direction, list_type)
    local h = State.screen.height
    local start_y, item_height
    if list_type == "search" then
        start_y = 7
        item_height = 2
    elseif list_type == "settings" then
        start_y = 4
        item_height = 3
    else
        start_y = 4
        item_height = 2
    end
    local status_bar_height = 1
    local available_height = h - start_y - status_bar_height
    local items_per_page = math.floor(available_height / item_height)
    items_per_page = math.max(1, items_per_page)

    local list, scroll_var
    if list_type == "search" then
        list = filter_list(State.search_results or {}, State.search_filter)
        scroll_var = "search_scroll"
    elseif list_type == "queue" then
        list = filter_list(State.queue, State.queue_filter)
        scroll_var = "queue_scroll"
    elseif list_type == "history" then
        list = filter_list(State.history, State.history_filter)
        scroll_var = "history_scroll"
    elseif list_type == "favorites" then
        list = filter_list(State.favorites, State.favorites_filter)
        scroll_var = "favorites_scroll"
    elseif list_type == "playlists" then
        local playlist_list = {}
        for name, _ in pairs(State.playlists) do
            table.insert(playlist_list, {title = name})
        end
        list = playlist_list
        scroll_var = "playlists_scroll"
    elseif list_type == "settings" then
        list = {"api_url", "buffer_size", "sample_rate", "chunk_size", "auto_play_next",
                "show_visualization", "theme", "sleep_timer", "notifications", "check_updates"}
        scroll_var = "settings_scroll"
    end

    local max_scroll = math.max(0, #list - items_per_page)

    if direction == "up" then
        if State[scroll_var] > 0 then
            State[scroll_var] = State[scroll_var] - 1
            State.selected_index[State.current_tab] = math.max(1, State.selected_index[State.current_tab] - 1)
            redraw()
        end
    elseif direction == "down" then
        if State[scroll_var] < max_scroll then
            State[scroll_var] = State[scroll_var] + 1
            State.selected_index[State.current_tab] = math.min(#list, State.selected_index[State.current_tab] + 1)
            redraw()
        end
    end
end

-- Scroll bar interaction handlers
local function handle_scroll_bar_click(scroll_info, click_y, scroll_type)
    if not scroll_info then return end

    local relative_y = click_y - scroll_info.start_y

    if relative_y == 0 then
        handle_list_scroll("up", scroll_type)
    elseif relative_y == scroll_info.height - 1 then
        handle_list_scroll("down", scroll_type)
    elseif relative_y >= scroll_info.thumb_pos and relative_y < scroll_info.thumb_pos + scroll_info.thumb_size then
        State.dragging_scroll = true
        State.drag_scroll_type = scroll_type
        State.drag_start_y = click_y
        State.drag_start_scroll = scroll_info.scroll_pos
    else
        local new_scroll
        if relative_y < scroll_info.thumb_pos then
            new_scroll = math.max(0, scroll_info.scroll_pos - scroll_info.visible_items)
        else
            new_scroll = math.min(scroll_info.max_scroll, scroll_info.scroll_pos + scroll_info.visible_items)
        end

        local scroll_var = scroll_type .. "_scroll"
        State[scroll_var] = new_scroll
        redraw()
    end
end

local function handle_scroll_bar_drag(drag_y)
    if not State.dragging_scroll then return end

    local scroll_info = scroll_infos[State.drag_scroll_type]
    if not scroll_info then return end

    local drag_delta = drag_y - State.drag_start_y
    local usable_height = scroll_info.height - scroll_info.thumb_size
    local scroll_delta = 0

    if usable_height > 0 then
        scroll_delta = math.floor(drag_delta * scroll_info.max_scroll / usable_height)
    end

    local new_scroll = math.max(0, math.min(scroll_info.max_scroll, State.drag_start_scroll + scroll_delta))

    local scroll_var = State.drag_scroll_type .. "_scroll"
    State[scroll_var] = new_scroll
    redraw()
end

-- Queue reordering
local function handle_queue_reorder_drag(y)
    if not State.dragging_queue_item or not State.drag_item_index then return end

    local h = State.screen.height
    local start_y = 4
    local status_bar_height = 1
    local available_height = h - start_y - status_bar_height
    local items_per_page = math.floor(available_height / 2)
    items_per_page = math.max(1, items_per_page)

    local hover_index = math.floor((y - start_y) / 2) + 1 + State.queue_scroll
    hover_index = math.max(1, math.min(#State.queue, hover_index))

    if hover_index ~= State.drag_item_index then
        local item = table.remove(State.queue, State.drag_item_index)
        table.insert(State.queue, hover_index, item)
        State.drag_item_index = hover_index
        save_state()
        redraw()
    end
end

-- Playback position tracking
local function reset_playback_timing()
    State.playback_position = 0
    State.chunks_played = 0
    State.buffer_size_on_pause = 0
    State.downloaded_chunks = {}
end

local function calculate_playback_position()
    local chunks_total = State.chunks_played
    if not State.is_playing and State.buffer_size_on_pause > 0 then
        chunks_total = chunks_total - State.buffer_size_on_pause
    end
    local samples_played = chunks_total * State.samples_per_chunk
    State.playback_position = samples_played / State.sample_rate
    if State.total_duration > 0 then
        State.playback_position = math.min(State.playback_position, State.total_duration)
    end
end

local function update_playback_position()
    calculate_playback_position()
end

-- DRAWING FUNCTIONS (Original from v4.3)
local function draw_vertical_tabs(x, y, width, height)
    -- Draw background for the tab list
    paintutils.drawFilledBox(x, y, x + width - 1, y + height - 1, current_colors.tabs.inactive_bg)
    term.setCursorPos(x, 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(truncate_text(" CC Music", width-1))

    local current_y = y + 2
    for i, tab_info in ipairs(TAB_DATA) do
        local is_active = (State.current_tab == tab_info.id)

        if is_active then
            term.setBackgroundColor(current_colors.tabs.active_bg)
            term.setTextColor(current_colors.tabs.active_text)
        else
            term.setBackgroundColor(current_colors.tabs.inactive_bg)
            term.setTextColor(current_colors.tabs.inactive_text)
        end

        term.setCursorPos(x, current_y)
        local text = " " .. tab_info.name
        term.write(truncate_text(text, width))
        current_y = current_y + 2
        if current_y > height then break end
    end
end

local function draw_status_bar(width)
    local h = State.screen.height
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.write(string.rep(" ", width))

    -- Status message
    if State.status_message then
        term.setTextColor(State.status_color)
        local msg = truncate_text(State.status_message, math.max(10, width - 25))
        term.setCursorPos(2, h)
        term.write(msg)
    end

    -- Sleep timer
    if State.settings.sleep_timer_active then
        local elapsed = os.clock() - (State.sleep_timer_start or os.clock())
        local remaining = (State.settings.sleep_timer or 0) * 60 - elapsed
        if remaining > 0 then
            term.setCursorPos(math.max(2, width - 25), h)
            term.setTextColor(colors.yellow)
            term.write("Sleep: " .. format_time(remaining))
        end
    end

    -- Connection status
    term.setCursorPos(math.max(2, width - 10), h)
    if (State.connection_errors or 0) > 0 then
        term.setTextColor(current_colors.status.error)
        term.write("Conn: Err")
    elseif State.is_streaming then
        term.setTextColor(current_colors.status.playing)
        term.write("Conn: OK")
    else
        term.setTextColor(colors.lightGray)
        term.write("Conn: Idle")
    end

    term.setBackgroundColor(colors.black)
end

local function draw_song_info(width)
    term.setCursorPos(2, 3)
    term.setBackgroundColor(colors.black)

    if State.current_song then
        term.setTextColor(colors.white)
        local title = truncate_text(State.current_song.title or "Unknown", width - 12)
        term.write(title)

        -- Info button
        term.setCursorPos(width - 8, 3)
        term.setBackgroundColor(colors.gray)
        term.write(" i ")

        -- Favorite star
        term.setCursorPos(width - 4, 3)
        if is_favorite(State.current_song) then
            term.setTextColor(colors.yellow)
            term.setBackgroundColor(colors.black)
            term.write("*")
        else
            term.setTextColor(colors.gray)
            term.setBackgroundColor(colors.black)
            term.write("o")
        end

        term.setCursorPos(2, 4)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lightGray)
        local artist = truncate_text(State.current_song.artist or "Unknown", width - 4)
        term.write(artist)

        -- Additional metadata
        if State.current_song.duration then
            term.setCursorPos(2, 5)
            term.setTextColor(colors.gray)
            term.write("Duration: " .. format_time(State.current_song.duration))
        end

        -- View count if available
        if State.current_song.view_count and width > 35 then
            term.setCursorPos(20, 5)
            term.write("Views: " .. tostring(State.current_song.view_count))
        end
    else
        term.setTextColor(colors.gray)
        term.write("No song selected")
    end
end

local function draw_playback_status(width)
    term.setCursorPos(2, 7)
    term.setBackgroundColor(colors.black)

    if State.loading then
        term.setTextColor(current_colors.status.loading)
        term.write("Loading...")
    elseif State.connection_errors > 0 then
        term.setTextColor(current_colors.status.error)
        term.write("Connection error (retrying...)")
    elseif State.is_streaming and State.is_playing then
        term.setTextColor(current_colors.status.playing)
        term.write("Playing")
    elseif State.current_song then
        term.setTextColor(current_colors.status.paused)
        term.write("Paused")
    end
end

local function draw_progress(width)
    if State.current_song and State.total_duration > 0 then
        update_playback_position()
        term.setCursorPos(2, 9)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(format_time(State.playback_position) .. " / " .. format_time(State.total_duration))

        draw_progress_bar(2, 10, width - 3, State.playback_position / State.total_duration,
                         current_colors.progress.bg, current_colors.progress.fg)
    end
end

local function draw_volume_control(width)
    term.setCursorPos(2, 12)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Volume:")

    local bar_width = math.min(24, width - 10)
    draw_progress_bar(2, 13, bar_width, State.volume, current_colors.progress.bg, current_colors.progress.volume)

    local percentage = math.floor(100 * (State.volume))
    term.setCursorPos(2 + bar_width + 1, 13)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(percentage .. "%")
end

local function draw_buffer_status(width)
    term.setCursorPos(2, 15)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.cyan)
    local buffer_percent = math.min(100, math.floor((#State.buffer / CONFIG.buffer_max) * 100))
    term.write("Buffer: " .. #State.buffer .. " chunks (" .. buffer_percent .. "%)")
end

local function draw_control_buttons(width)
    local button_y = 17
    local button_x = 2

    -- Play/Pause
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(State.is_playing and colors.red or colors.green)
    term.write(State.is_playing and " Pause " or " Play  ")
    button_x = button_x + 8

    -- Skip
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(" Skip ")
    button_x = button_x + 7

    -- Repeat
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(State.repeat_mode > 0 and colors.green or colors.gray)
    term.setTextColor(colors.white)
    local repeat_icons = {"[-]", "[1]", "[A]"}
    term.write(" " .. repeat_icons[State.repeat_mode + 1] .. " ")
    button_x = button_x + 6

    -- Shuffle
    if button_x + 7 < width then
        term.setCursorPos(button_x, button_y)
        term.setBackgroundColor(State.shuffle and colors.green or colors.gray)
        term.setTextColor(colors.white)
        term.write(" Shuf ")
        button_x = button_x + 7
    end

    -- Favorite
    if State.current_song and button_x + 6 < width then
        term.setCursorPos(button_x, button_y)
        term.setBackgroundColor(is_favorite(State.current_song) and colors.yellow or colors.gray)
        term.setTextColor(colors.white)
        term.write(" Fav ")
        button_x = button_x + 6
    end

    -- Download
    if State.current_song and #State.downloaded_chunks > 0 and button_x + 7 < width then
        term.setCursorPos(button_x, button_y)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write(" Save ")
    end

    -- Visualization mode
    local vis_y = 19
    term.setCursorPos(2, vis_y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    term.write("Vis: ")

    local vis_modes = {"Bars", "Wave", "Spec", "VU"}
    for i, mode in ipairs(vis_modes) do
        local x_pos = 7 + (i-1) * 6
        if x_pos + 4 < width then
            term.setCursorPos(x_pos, vis_y)
            if State.visualization_mode == i then
                term.setBackgroundColor(colors.green)
                term.setTextColor(colors.white)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            term.write(" " .. mode .. " ")
        end
    end

    term.setBackgroundColor(colors.black)
end

local function draw_now_playing(width)
    local h = State.screen.height

    draw_song_info(width)
    draw_playback_status(width)
    draw_progress(width)
    draw_volume_control(width)
    draw_buffer_status(width)
    draw_control_buttons(width)

    -- Draw visualization
    if State.settings.show_visualization and h > 22 then
        draw_visualization(2, 21, width - 3, h - 22)
    end
end

local function draw_search_box(width)
    -- Search box
    paintutils.drawFilledBox(2, 3, width - 1, 5, colors.lightGray)

    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Search for music:")

    term.setCursorPos(3, 4)
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)

    if State.waiting_input and State.input_context == "main_search" then
        term.write(State.input_text)
        if #State.input_text < width - 6 then
            term.setCursorBlink(true)
        end
    else
        if State.last_query ~= "" then
            term.write(State.last_query)
        else
            term.setTextColor(colors.gray)
            term.write("Type your search and press Enter")
        end
    end

    -- Filter box
    if State.search_results and #State.search_results > 0 and width > 30 then
        term.setCursorPos(width - 20, 6)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" Filter: ")

        if State.waiting_input and State.input_context == "search_filter" then
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(State.input_text .. "_")
            term.setCursorBlink(true)
        else
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.write(State.search_filter or "")
        end
    end

    term.setBackgroundColor(colors.black)
    if not State.waiting_input then
      term.setCursorBlink(false)
    end
end

-- Generic list drawer
local function draw_list_items(list, list_type, start_y, with_actions, with_filter, width)
    local h = State.screen.height
    local status_bar_height = 1
    local end_y = h - status_bar_height
    local available_height = end_y - start_y + 1
    local items_per_page = math.floor(available_height / 2) -- 2 lines per item
    items_per_page = math.max(1, items_per_page)

    local scroll_var = list_type .. "_scroll"
    local filter_var = list_type .. "_filter"

    -- Apply filter
    local filtered_list = list
    if with_filter and State[filter_var] and State[filter_var] ~= "" then
        filtered_list = filter_list(list, State[filter_var])
    end

    local max_scroll = math.max(0, #filtered_list - items_per_page)
    State[scroll_var] = math.min(State[scroll_var], max_scroll)
    State[scroll_var] = math.max(0, State[scroll_var])

    if #filtered_list == 0 then
        scroll_infos[list_type] = nil
        term.setCursorPos(2, start_y)
        term.setTextColor(colors.gray)
        if with_filter and State[filter_var] and State[filter_var] ~= "" then
            term.write("No results for filter: " .. State[filter_var])
        end
        return false
    end

    -- Draw scroll bar
    draw_scroll_bar(width, start_y, available_height, #filtered_list, items_per_page, State[scroll_var], list_type)

    for i = 1, items_per_page do
        local idx = i + State[scroll_var]
        local item = filtered_list[idx]
        if not item then break end
        local y = start_y + (i - 1) * 2 -- 2 lines per item

        if y < end_y then
            -- Highlight selected
            if State.keyboard_nav_active and State.selected_index[State.current_tab] == idx then
                paintutils.drawBox(2, y, width - 2, y + 1, current_colors.selected)
            end

            term.setBackgroundColor(colors.black)
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)

            -- Dragged item
            if State.dragging_queue_item and State.drag_item_index == idx and list_type == "queue" then
                term.setBackgroundColor(colors.blue)
            end

            local title = truncate_text(item.title or "Unknown Title", width - 15)
            term.write(idx .. ". " .. title)

            -- Favorite indicator
            if item.id and is_favorite(item) then
                term.setTextColor(colors.yellow)
                term.write(" *")
            end

            term.setCursorPos(5, y + 1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.lightGray)
            local artist = truncate_text(item.artist or "Unknown Artist", width - 15)
            term.write(artist)

            -- Duration
            if item.duration and width > 30 then
                local dur_str = format_time(item.duration)
                term.setCursorPos(width - #dur_str - 8, y)
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.gray)
                term.write(dur_str)
            end

            -- Action buttons
            if with_actions and width > 35 then
                if list_type == "search" or list_type == "history" or list_type == "favorites" then
                    -- Add button
                    term.setCursorPos(width - 6, y + 1)
                    term.setBackgroundColor(colors.green)
                    term.setTextColor(colors.white)
                    term.write(" + ")

                    -- Info button
                    term.setCursorPos(width - 10, y + 1)
                    term.setBackgroundColor(colors.gray)
                    term.write(" i ")
                elseif list_type == "queue" then
                    -- Remove button
                    term.setCursorPos(width - 4, y)
                    term.setBackgroundColor(colors.red)
                    term.setTextColor(colors.white)
                    term.write(" X ")

                    -- Move handle
                    if State.keyboard_nav_active and width > 40 then
                        term.setCursorPos(width - 9, y)
                        term.setBackgroundColor(colors.gray)
                        term.setTextColor(colors.white)
                        term.write(" :: ")
                    end
                end
            end

            term.setBackgroundColor(colors.black)
        end
    end

    return true
end

local function draw_search_results(width)
    if State.search_results and #State.search_results > 0 then
        draw_list_items(State.search_results, "search", 7, true, true, width)
    else
        scroll_infos.search = nil
        if State.search_error then
            term.setCursorPos(2, 7)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.red)
            term.write("Error: " .. State.search_error)
        elseif State.last_search_url then
            term.setCursorPos(2, 7)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.yellow)
            term.write("Searching...")
        end
    end
end

local function draw_search(width)
    draw_search_box(width)
    draw_search_results(width)
end

local function draw_queue_header(width)
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Queue (" .. #State.queue .. " songs):")

    -- Queue controls
    term.setCursorPos(width - 28, 2)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(" Clear ")

    term.setCursorPos(width - 20, 2)
    term.setBackgroundColor(State.shuffle and colors.green or colors.gray)
    term.write(" Shuffle ")

    term.setCursorPos(width - 10, 2)
    term.setBackgroundColor(colors.gray)
    term.write(" Save ")

    -- Filter
    if #State.queue > 0 then
        term.setCursorPos(2, 3)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.write("Filter: ")

        if State.waiting_input and State.input_context == "queue_filter" then
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(State.input_text .. "_")
            term.setCursorBlink(true)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. (State.queue_filter or "") .. " ")
        end
    end

    term.setBackgroundColor(colors.black)
    if not State.waiting_input then term.setCursorBlink(false) end
end

local function draw_queue(width)
    draw_queue_header(width)

    if #State.queue == 0 then
        scroll_infos.queue = nil
        term.setCursorPos(2, 5)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.write("Queue is empty")
        term.setCursorPos(2, 6)
        term.write("Add songs from Search tab")
    else
        draw_list_items(State.queue, "queue", 4, true, true, width)
    end
end

local function draw_playlists(width)
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Playlists:")

    -- New playlist button
    term.setCursorPos(width - 12, 2)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" New ")

    -- Save queue as playlist
    if #State.queue > 0 and width > 30 then
        term.setCursorPos(width - 26, 2)
        term.setBackgroundColor(colors.blue)
        term.write(" Save Queue ")
    end

    term.setBackgroundColor(colors.black)

    if State.editing_playlist then
        term.setCursorPos(2, 3)
        term.setTextColor(colors.white)
        term.write("Playlist name: ")
        term.setBackgroundColor(colors.lightGray)
        term.setTextColor(colors.black)
        term.write(State.playlist_input .. "_")
        term.setCursorBlink(true)
        term.setBackgroundColor(colors.black)
    else
        term.setCursorBlink(false)
    end

    -- List playlists
    local y = State.editing_playlist and 5 or 4
    local playlist_names = {}
    for name, _ in pairs(State.playlists) do
        table.insert(playlist_names, name)
    end

    if #playlist_names == 0 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.gray)
        term.write("No playlists yet")
    else
        for i, name in ipairs(playlist_names) do
            if y < State.screen.height - 1 then
                term.setCursorPos(2, y)
                term.setTextColor(colors.white)
                term.write(i .. ". " .. name)

                if width > 30 then
                    term.setCursorPos(25, y)
                    term.setTextColor(colors.gray)
                    term.write("(" .. #State.playlists[name].songs .. " songs)")
                end

                -- Buttons
                local btn_x = width - 7
                term.setCursorPos(btn_x, y)
                term.setBackgroundColor(colors.red)
                term.write(" X ")

                btn_x = btn_x - 7
                term.setCursorPos(btn_x, y)
                term.setBackgroundColor(colors.blue)
                term.write(" View ")

                btn_x = btn_x - 7
                term.setCursorPos(btn_x, y)
                term.setBackgroundColor(colors.green)
                term.write(" Play ")

                term.setBackgroundColor(colors.black)
                y = y + 2
            end
        end
    end
end

local function draw_history(width)
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Recently Played (" .. #State.history .. " songs):")

    if #State.history > 0 then
        term.setCursorPos(width - 10, 2)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" Clear ")

        -- Filter
        term.setCursorPos(2, 3)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.write("Filter: ")

        if State.waiting_input and State.input_context == "history_filter" then
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(State.input_text .. "_")
            term.setCursorBlink(true)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. (State.history_filter or "") .. " ")
        end
    end

    term.setBackgroundColor(colors.black)
    if not State.waiting_input then term.setCursorBlink(false) end

    if #State.history == 0 then
        scroll_infos.history = nil
        term.setCursorPos(2, 4)
        term.setTextColor(colors.gray)
        term.write("No history yet")
    else
        draw_list_items(State.history, "history", 4, true, true, width)
    end
end

local function draw_favorites(width)
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Favorite Songs (" .. #State.favorites .. " songs):")

    if #State.favorites > 0 then
        term.setCursorPos(width - 10, 2)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" Clear ")

        -- Filter
        term.setCursorPos(2, 3)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.write("Filter: ")

        if State.waiting_input and State.input_context == "favorites_filter" then
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(State.input_text .. "_")
            term.setCursorBlink(true)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. (State.favorites_filter or "") .. " ")
        end
    end

    term.setBackgroundColor(colors.black)
    if not State.waiting_input then term.setCursorBlink(false) end

    if #State.favorites == 0 then
        scroll_infos.favorites = nil
        term.setCursorPos(2, 4)
        term.setTextColor(colors.gray)
        term.write("No favorites yet")
        term.setCursorPos(2, 5)
        term.write("Mark songs as favorite from Now Playing")
    else
        draw_list_items(State.favorites, "favorites", 4, true, true, width)
    end
end

local function draw_settings(width)
    local h = State.screen.height

    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Settings:")

    local settings_list = {
        {key = "api_url", label = "API URL", value = State.settings.api_url, type = "string"},
        {key = "buffer_size", label = "Buffer Size", value = tostring(State.settings.buffer_size), type = "number"},
        {key = "sample_rate", label = "Sample Rate", value = tostring(State.settings.sample_rate), type = "number"},
        {key = "chunk_size", label = "Chunk Size", value = tostring(State.settings.chunk_size), type = "number"},
        {key = "auto_play_next", label = "Auto Play Next", value = State.settings.auto_play_next and "Yes" or "No", type = "boolean"},
        {key = "show_visualization", label = "Show Visualization", value = State.settings.show_visualization and "Yes" or "No", type = "boolean"},
        {key = "theme", label = "Theme", value = State.settings.theme, type = "select", options = {"default", "dark", "ocean"}},
        {key = "sleep_timer", label = "Sleep Timer (min)", value = tostring(State.settings.sleep_timer), type = "number"},
        {key = "notifications", label = "Notifications", value = State.settings.notifications and "Yes" or "No", type = "boolean"},
        {key = "check_updates", label = "Check Updates", value = State.settings.check_updates and "Yes" or "No", type = "boolean"}
    }

    local start_y = 4
    local status_bar_height = 1
    local end_y = h - status_bar_height
    local available_height = end_y - start_y + 1
    local items_per_page = math.floor(available_height / 3) -- 3 lines per setting
    items_per_page = math.max(1, items_per_page)

    draw_scroll_bar(width, start_y, available_height, #settings_list, items_per_page, State.settings_scroll, "settings")

    for i = 1, items_per_page do
        local idx = i + State.settings_scroll
        local setting = settings_list[idx]
        if not setting then break end

        local y = start_y + (i - 1) * 3

        if y < end_y then
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)
            term.write(setting.label .. ":")

            term.setCursorPos(4, y + 1)

            if State.editing_setting == setting.key then
                term.setBackgroundColor(colors.lightGray)
                term.setTextColor(colors.black)
                term.write(State.input_text .. "_")
                term.setCursorBlink(true)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
                term.write(" " .. tostring(setting.value or "") .. " ")
            end

            -- Edit button
            term.setCursorPos(width - 10, y)
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.write(" Edit ")

            -- Special buttons
            if setting.key == "theme" and width > 40 then
                term.setCursorPos(width - 16, y)
                term.setBackgroundColor(colors.green)
                term.write(" Apply ")
            elseif setting.key == "sleep_timer" and width > 40 then
                term.setCursorPos(width - 16, y)
                if State.settings.sleep_timer_active then
                    term.setBackgroundColor(colors.red)
                    term.write(" Stop ")
                else
                    term.setBackgroundColor(colors.green)
                    term.write(" Start ")
                end
            end
        end
        term.setBackgroundColor(colors.black)
    end
    if not State.waiting_input then term.setCursorBlink(false) end

    -- Save button
    term.setCursorPos(width - 12, 2)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" Save All ")

    term.setBackgroundColor(colors.black)
end

local function draw_diagnostics(width)
    local h = State.screen.height

    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Network Diagnostics:")

    local stats = calculate_network_stats()

    local y = 4
    local function draw_stat(label, value, color)
        if y < h - 1 then
            term.setCursorPos(2, y)
            term.setTextColor(colors.lightGray)
            term.write(label .. ":")
            term.setCursorPos(20, y)
            term.setTextColor(color or colors.white)
            term.write(tostring(value))
            y = y + 1
        end
    end

    draw_stat("Session Active", stats.session_active and "Yes" or "No",
              stats.session_active and colors.green or colors.red)
    draw_stat("Buffer Fill", stats.buffer_fill .. "%",
              stats.buffer_fill > 50 and colors.green or colors.yellow)
    draw_stat("Connection Errors", stats.connection_errors,
              stats.connection_errors == 0 and colors.green or colors.red)
    draw_stat("Avg Latency", string.format("%.1fms", (stats.avg_latency or 0) * 1000))
    draw_stat("Bytes Received", format_bytes(stats.bytes_received))
    draw_stat("Chunks Downloaded", stats.chunks_downloaded)
    draw_stat("Session Uptime", format_time(stats.uptime))

    y = y + 1
    if y < h - 1 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.white)
        term.write("Application Info:")
        y = y + 2
    end

    draw_stat("Version", CONFIG.version)
    draw_stat("Current Profile", State.current_profile)
    draw_stat("Theme", State.current_theme)
    draw_stat("Songs in Queue", #State.queue)
    draw_stat("Songs in History", #State.history)
    draw_stat("Favorite Songs", #State.favorites)
    local p_count = 0; for _ in pairs(State.playlists) do p_count = p_count + 1 end
    draw_stat("Playlists", tostring(p_count))

    -- Check for updates button
    term.setCursorPos(width - 15, 2)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.write(" Check Updates ")

    term.setBackgroundColor(colors.black)
end

-- DEFINE REDRAW FUNCTION
function redraw()
    State.screen.width, State.screen.height = term.getSize()

    if State.mini_mode then
        draw_mini_mode()
        return
    end

    local content_width = State.screen.width - TAB_LIST_WIDTH
    term.setBackgroundColor(colors.black)
    term.clear()

    local tab_draw_functions = {
        [TABS.NOW_PLAYING] = draw_now_playing,
        [TABS.SEARCH]      = draw_search,
        [TABS.QUEUE]       = draw_queue,
        [TABS.PLAYLISTS]   = draw_playlists,
        [TABS.HISTORY]     = draw_history,
        [TABS.FAVORITES]   = draw_favorites,
        [TABS.SETTINGS]    = draw_settings,
        [TABS.DIAGNOSTICS] = draw_diagnostics
    }

    local draw_func = tab_draw_functions[State.current_tab]
    if draw_func then
        draw_func(content_width)
    end

    -- Draw the tab list on the right
    draw_vertical_tabs(content_width + 1, 1, TAB_LIST_WIDTH, State.screen.height)

    -- Draw status bar
    draw_status_bar(content_width)

    -- Draw popup if active
    if State.show_popup and State.popup_content then
        local p = State.popup_content
        State.popup_x, State.popup_y, State.popup_w, State.popup_h =
            draw_popup(p.title, p.content, p.width, p.height)
    end
end

-- NETWORK & STREAM HANDLING
local function stop_current_stream()
    if State.session_id then
        http.post(State.settings.api_url .. "/stop_stream/" .. State.session_id, "")
        State.session_id = nil
    end
    State.is_streaming = false
    State.is_playing = false
    State.buffer = {}
    reset_playback_timing()
    State.connection_errors = 0
    State.chunk_request_pending = false
    State.visualization_data = {}
end

local function start_stream(id, song)
    stop_current_stream()

    State.current_song = song
    State.loading = true
    State.ended = false
    State.total_duration = song.duration or 0
    State.stream_start_time = os.clock()
    reset_playback_timing()

    if State.current_song then
        show_notification("Now playing: " .. (song.title or "Unknown"), 3)
    end

    redraw()

    local payload = textutils.serializeJSON({
        id = id,
        audio_config = {
            format = "pcm",
            sample_rate = State.settings.sample_rate,
            chunk_size = State.settings.chunk_size
        }
    })

    http.request({
        url = State.settings.api_url .. "/start_stream",
        body = payload,
        headers = { ["Content-Type"] = "application/json" },
        method = "POST"
    })
end

local function request_chunk()
    if State.session_id and not State.ended and not State.chunk_request_pending and #State.buffer < State.settings.buffer_size then
        State.chunk_request_pending = true
        State.last_chunk_time = os.clock()
        http.request(State.settings.api_url .. "/chunk/" .. State.session_id)
    end
end

local function convert_pcm_chunk(chunk_data)
    local pcm_samples = {}
    for i = 1, #chunk_data do
        local signed_byte = string.byte(chunk_data, i)
        if signed_byte > 127 then
            signed_byte = signed_byte - 256
        end
        pcm_samples[i] = signed_byte
    end
    return pcm_samples
end

-- HTTP RESPONSE HANDLERS
local function handle_stream_start_response(response_text)
    local success, response = pcall(textutils.unserializeJSON, response_text)
    if success and response and response.session_id then
        State.session_id = response.session_id
        State.is_streaming = true
        State.loading = false
        State.connection_errors = 0
        set_status("Stream started", current_colors.status.playing, 2)

        -- Request initial chunks
        for i = 1, CONFIG.chunk_request_ahead do
            request_chunk()
        end
    else
        State.loading = false
        State.current_song = nil
        State.connection_errors = State.connection_errors + 1
        set_status("Failed to start stream", current_colors.status.error, 3)
    end
    redraw()
end

local function handle_chunk_response(data, response_code)
    State.chunk_request_pending = false

    -- Update latency
    local latency = os.clock() - State.last_chunk_time
    State.avg_chunk_latency = (State.avg_chunk_latency * 0.9) + (latency * 0.1)
    State.total_bytes_received = State.total_bytes_received + #data

    if response_code == 204 or #data == 0 then
        State.ended = true
        if State.is_playing then
            os.queueEvent("stream_ended")
        end
    else
        local pcm_samples = convert_pcm_chunk(data)
        table.insert(State.buffer, pcm_samples)
        table.insert(State.downloaded_chunks, pcm_samples)
        State.connection_errors = 0

        -- Request next chunk if buffer not full
        if #State.buffer < CONFIG.buffer_threshold then
            request_chunk()
        end

        -- Start playing if we have enough buffer
        if not State.is_playing and #State.buffer >= CONFIG.buffer_threshold then
            State.is_playing = true
            State.buffer_size_on_pause = 0
            os.queueEvent("playback")
        end
    end
    redraw()
end

local function handle_search_response(response_text)
    State.last_search_url = nil
    State.search_error = nil

    local success, results = pcall(textutils.unserializeJSON, response_text)
    if success and results then
        State.search_results = results
        State.search_scroll = 0
        State.selected_index[TABS.SEARCH] = 1
        set_status("Found " .. #results .. " results", colors.white, 2)
    else
        State.search_error = "Failed to parse results"
        set_status("Search failed", current_colors.status.error, 3)
    end
    redraw()
end

local function handle_update_check_response(response_text)
    local latest_version = response_text:match("^%d+%.%d+")
    if latest_version and latest_version ~= CONFIG.version then
        set_status("Update available: v" .. latest_version, colors.yellow, 5)
        show_notification("Update available: v" .. latest_version, 5)
    else
        set_status("You're on the latest version", colors.green, 3)
    end
end

local function handle_http_success(url, handle)
    local response_text = handle.readAll()
    local response_code = handle.getResponseCode()
    handle.close()

    if url:find("/start_stream") then
        handle_stream_start_response(response_text)
    elseif url:find("/chunk/") then
        handle_chunk_response(response_text, response_code)
    elseif url:find("search=") then
        handle_search_response(response_text)
    elseif url == CONFIG.update_check_url then
        handle_update_check_response(response_text)
    end
end

local function handle_http_failure(url, handle)
    if State.last_search_url and url == State.last_search_url then
        State.search_error = "Connection failed"
        State.last_search_url = nil
        set_status("Search connection failed", current_colors.status.error, 3)
        redraw()
    elseif State.session_id and url:find("/chunk/") then
        State.chunk_request_pending = false
        State.connection_errors = State.connection_errors + 1
        if State.connection_errors < 5 then
            sleep(CONFIG.retry_delay)
            request_chunk()
        else
            set_status("Too many connection errors", current_colors.status.error)
            stop_current_stream()
            redraw()
        end
    end
end

-- PLAYBACK CONTROL
local function play_next_song()
    local next_song = nil

    if State.repeat_mode == REPEAT_MODES.ONE and State.current_song then
        next_song = State.current_song
    elseif #State.queue > 0 then
        if State.shuffle and State.repeat_mode ~= REPEAT_MODES.ONE then
            local idx = math.random(1, #State.queue)
            next_song = table.remove(State.queue, idx)
        else
            next_song = table.remove(State.queue, 1)
            State.queue_scroll = math.max(0, State.queue_scroll - 1)
        end

        if State.repeat_mode == REPEAT_MODES.ALL then
            table.insert(State.queue, next_song)
        end
    elseif State.repeat_mode == REPEAT_MODES.ALL and #State.history > 0 then
        State.queue = State.shuffle and shuffle_table(State.history) or State.history
        State.history = {}
        return play_next_song()
    end

    if next_song then
        if State.current_song and State.repeat_mode ~= REPEAT_MODES.ONE then
            table.insert(State.history, 1, State.current_song)
            if #State.history > 50 then
                table.remove(State.history)
            end
        end
        start_stream(next_song.id, next_song)
        save_state()
    else
        State.current_song = nil
        State.is_playing = false
        reset_playback_timing()
        redraw()
    end
end

-- INPUT HANDLERS (All original ones restored)
local function handle_now_playing_click(x, y, width)
    -- Volume control
    if y == 13 and x >= 2 and x <= 25 then
        State.volume = ((x - 2) / 23)
        State.volume = math.max(0.0, math.min(1.0, State.volume))
        redraw()
        return
    end

    -- Info button
    if State.current_song and y == 3 and x >= width - 8 and x <= width - 6 then
        show_song_info_popup(State.current_song)
        return
    end

    -- Favorite star
    if State.current_song and y == 3 and x >= width - 4 and x <= width - 3 then
        toggle_favorite(State.current_song)
        redraw()
        return
    end

    -- Control buttons
    if y == 17 then
        if x >= 2 and x <= 8 then -- Play/Pause
            if State.is_playing then
                State.is_playing = false
                State.buffer_size_on_pause = #State.buffer
                calculate_playback_position()
            elseif State.current_song and (#State.buffer > 0 or State.ended) then
                State.is_playing = true
                State.buffer_size_on_pause = 0
                os.queueEvent("playback")
            elseif #State.queue > 0 then
                play_next_song()
            end
        elseif x >= 10 and x <= 15 then -- Skip
            if State.settings.auto_play_next or #State.queue > 0 then
                play_next_song()
            else
                stop_current_stream()
                State.current_song = nil
            end
        elseif x >= 17 and x <= 21 then -- Repeat
            State.repeat_mode = (State.repeat_mode + 1) % 3
            set_status("Repeat: " .. ({"Off", "One", "All"})[State.repeat_mode + 1], colors.white, 2)
        elseif x >= 23 and x <= 28 then -- Shuffle
            State.shuffle = not State.shuffle
            set_status("Shuffle: " .. (State.shuffle and "On" or "Off"), colors.white, 2)
        elseif x >= 30 and x <= 35 and State.current_song then -- Favorite
            toggle_favorite(State.current_song)
        elseif x >= 37 and x <= 42 and State.current_song and #State.downloaded_chunks > 0 then -- Download
            download_song()
        end
    end

    -- Visualization mode buttons
    if y == 19 then
        for i = 1, 4 do
            local btn_x = 7 + (i-1) * 6
            if x >= btn_x and x <= btn_x + 4 then
                State.visualization_mode = i
                redraw()
                return
            end
        end
    end

    redraw()
end

local function handle_mini_mode_click(x, y)
    local w = State.screen.width

    -- Exit mini mode
    if y == 1 and x >= w - 10 and x <= w - 3 then
        State.mini_mode = false
        redraw()
        return
    end

    -- Play/Pause
    if y == 9 and x >= 2 and x <= 8 then
        if State.is_playing then
            State.is_playing = false
            State.buffer_size_on_pause = #State.buffer
            calculate_playback_position()
        elseif State.current_song and (#State.buffer > 0 or State.ended) then
            State.is_playing = true
            State.buffer_size_on_pause = 0
            os.queueEvent("playback")
        elseif #State.queue > 0 then
            play_next_song()
        end
    elseif y == 9 and x >= 10 and x <= 15 then -- Next
        play_next_song()
    elseif y == 9 and x >= 17 and x <= 21 then -- Favorite
        if State.current_song then
            toggle_favorite(State.current_song)
        end
    end

    -- Volume
    if y == 11 and x >= 7 and x <= 21 then
        State.volume = ((x - 7) / 14)
        State.volume = math.max(0.0, math.min(1.0, State.volume))
    end

    redraw()
end

local function add_to_queue(song)
    table.insert(State.queue, song)
    set_status("Added to queue", current_colors.status.playing, 2)
    if not State.current_song then
        play_next_song()
    end
    save_state()
    redraw()
end

-- Continue with all the original click handlers and input handlers...
-- [The rest continues with all the original functions exactly as they were]

local function handle_list_click(x, y, list, list_type, start_y, width)
    local h = State.screen.height
    local status_bar_height = 1
    local available_height = h - start_y - status_bar_height
    local items_per_page = math.floor(available_height / 2)
    items_per_page = math.max(1, items_per_page)

    local scroll_var = list_type .. "_scroll"
    local filter_var = list_type .. "_filter"

    -- Apply filter
    local filtered_list = list
    if State[filter_var] and State[filter_var] ~= "" then
        filtered_list = filter_list(list, State[filter_var])
    end

    local index = math.floor((y - start_y) / 2) + 1
    local idx = index + State[scroll_var]

    if idx >= 1 and idx <= #filtered_list then
        local item = filtered_list[idx]
        local item_y = start_y + (index - 1) * 2

        -- Check action buttons
        if list_type == "queue" and width > 35 then
            -- Remove button
            if y == item_y and x >= width - 4 and x <= width - 2 then
                table.remove(State.queue, idx)
                local max_scroll = math.max(0, #State.queue - items_per_page)
                State[scroll_var] = math.min(State[scroll_var], max_scroll)
                set_status("Removed from queue", current_colors.status.error, 2)
                save_state()
                redraw()
                return true
            end
            -- Move handle
            if y == item_y and x >= width - 9 and x <= width - 6 then
                State.dragging_queue_item = true
                State.drag_item_index = idx
                redraw()
                return true
            end
        elseif y == item_y + 1 and x >= width - 6 and x <= width - 4 then
            -- Add button
            add_to_queue(item)
            return true
        elseif y == item_y + 1 and x >= width - 10 and x <= width - 8 then
            -- Info button
            show_song_info_popup(item)
            return true
        end

        -- Double-click to play
        if State.last_click and State.last_click.x == x and State.last_click.y == y
           and os.clock() - State.last_click.time < 0.5 then
            if list_type == "queue" then
                for i = 1, idx - 1 do
                    table.remove(State.queue, 1)
                end
                play_next_song()
            else
                start_stream(item.id, item)
            end
            State.last_click = nil
            return true
        end

        State.last_click = {x = x, y = y, time = os.clock()}
    end

    return false
end

local function handle_search_click(x, y, width)
    -- Check scroll bar
    if scroll_infos.search and x == scroll_infos.search.x then
        handle_scroll_bar_click(scroll_infos.search, y, "search")
        return
    end

    -- Search box
    if y >= 3 and y <= 5 and x >= 2 and x <= width - 1 then
        State.waiting_input = true
        State.input_context = "main_search"
        State.input_text = ""
        State.search_results = nil
        State.search_error = nil
        redraw()
        return
    end

    -- Filter box
    if State.search_results and #State.search_results > 0 and y == 6 and x >= width - 20 and x <= width - 2 then
        State.waiting_input = true
        State.input_context = "search_filter"
        State.input_text = State.search_filter or ""
        redraw()
        return
    end

    -- Results
    if State.search_results then
        handle_list_click(x, y, State.search_results, "search", 7, width)
    end
end

local function handle_queue_click(x, y, width)
    -- Check scroll bar
    if scroll_infos.queue and x == scroll_infos.queue.x then
        handle_scroll_bar_click(scroll_infos.queue, y, "queue")
        return
    end

    -- Clear button
    if y == 2 and x >= width - 28 and x <= width - 22 then
        State.queue = {}
        State.queue_scroll = 0
        set_status("Queue cleared", colors.white, 2)
        save_state()
        redraw()
        return
    end

    -- Shuffle button
    if y == 2 and x >= width - 20 and x <= width - 11 then
        if #State.queue > 0 then
            State.queue = shuffle_table(State.queue)
            set_status("Queue shuffled", colors.white, 2)
            save_state()
            redraw()
        end
        return
    end

    -- Save button
    if y == 2 and x >= width - 10 and x <= width - 5 then
        save_state()
        set_status("Queue saved", current_colors.status.playing, 2)
        return
    end

    -- Filter
    if y == 3 and x >= 10 and x <= width - 2 then
        State.waiting_input = true
        State.input_context = "queue_filter"
        State.input_text = State.queue_filter or ""
        redraw()
        return
    end

    -- Queue items
    handle_list_click(x, y, State.queue, "queue", 4, width)
end

local function handle_playlists_click(x, y, width)
    -- New playlist
    if y == 2 and x >= width - 12 and x <= width - 8 then
        State.editing_playlist = true
        State.waiting_input = true
        State.input_context = "playlist_new"
        State.playlist_input = ""
        redraw()
        return
    end

    -- Save queue as playlist
    if y == 2 and x >= width - 26 and x <= width - 15 and #State.queue > 0 then
        State.editing_playlist = true
        State.waiting_input = true
        State.input_context = "playlist_save_queue"
        State.playlist_input = "Queue " .. os.date("%Y-%m-%d")
        redraw()
        return
    end

    -- Playlist items
    local y_pos = State.editing_playlist and 5 or 4
    local playlist_names = {}
    for name, _ in pairs(State.playlists) do
        table.insert(playlist_names, name)
    end

    for i, name in ipairs(playlist_names) do
        if y >= y_pos and y <= y_pos+1 then
            local btn_x_play = width - 21
            -- Play button
            if x >= btn_x_play and x < btn_x_play + 6 then
                State.queue = {}
                for _, song in ipairs(State.playlists[name].songs) do
                    table.insert(State.queue, song)
                end
                play_next_song()
                set_status("Playing playlist: " .. name, current_colors.status.playing, 2)
                return
            end
            -- View button
            if x >= btn_x_play + 7 and x < btn_x_play + 13 then
                State.selected_playlist = name
                State.current_tab = TABS.QUEUE
                State.queue = {}
                for _, song in ipairs(State.playlists[name].songs) do
                    table.insert(State.queue, song)
                end
                set_status("Loaded playlist: " .. name, colors.white, 2)
                redraw()
                return
            end
            -- Delete button
            if x >= btn_x_play + 14 and x < btn_x_play + 18 then
                State.playlists[name] = nil
                save_state()
                set_status("Deleted playlist: " .. name, current_colors.status.error, 2)
                redraw()
                return
            end
        end
        y_pos = y_pos + 2
    end
end

local function handle_history_click(x, y, width)
    -- Check scroll bar
    if scroll_infos.history and x == scroll_infos.history.x then
        handle_scroll_bar_click(scroll_infos.history, y, "history")
        return
    end

    -- Clear button
    if y == 2 and x >= width - 10 and x <= width - 4 and #State.history > 0 then
        State.history = {}
        State.history_scroll = 0
        set_status("History cleared", colors.white, 2)
        save_state()
        redraw()
        return
    end

    -- Filter
    if y == 3 and x >= 10 and x <= width - 2 then
        State.waiting_input = true
        State.input_context = "history_filter"
        State.input_text = State.history_filter or ""
        redraw()
        return
    end

    -- History items
    handle_list_click(x, y, State.history, "history", 4, width)
end

local function handle_favorites_click(x, y, width)
    -- Check scroll bar
    if scroll_infos.favorites and x == scroll_infos.favorites.x then
        handle_scroll_bar_click(scroll_infos.favorites, y, "favorites")
        return
    end

    -- Clear button
    if y == 2 and x >= width - 10 and x <= width - 4 and #State.favorites > 0 then
        State.favorites = {}
        State.favorites_scroll = 0
        set_status("Favorites cleared", colors.white, 2)
        save_state()
        redraw()
        return
    end

    -- Filter
    if y == 3 and x >= 10 and x <= width - 2 then
        State.waiting_input = true
        State.input_context = "favorites_filter"
        State.input_text = State.favorites_filter or ""
        redraw()
        return
    end

    -- Favorite items
    handle_list_click(x, y, State.favorites, "favorites", 4, width)
end

local function handle_settings_click(x, y, width)
    -- Check for scroll bar click first
    if scroll_infos.settings and x == scroll_infos.settings.x then
        handle_scroll_bar_click(scroll_infos.settings, y, "settings")
        return
    end

    -- Save All button
    if y == 2 and x >= width - 12 and x <= width - 3 then
        CONFIG.api_base_url = State.settings.api_url
        CONFIG.buffer_max = State.settings.buffer_size
        CONFIG.audio_sample_rate = State.settings.sample_rate
        CONFIG.audio_chunk_size = State.settings.chunk_size
        State.samples_per_chunk = State.settings.chunk_size
        State.sample_rate = State.settings.sample_rate
        apply_theme(State.settings.theme)

        save_state()
        set_status("Settings saved", current_colors.status.playing, 2)
        return
    end

    -- Setting items
    local settings_list = {
        {key = "api_url", type = "string"},
        {key = "buffer_size", type = "number"},
        {key = "sample_rate", type = "number"},
        {key = "chunk_size", type = "number"},
        {key = "auto_play_next", type = "boolean"},
        {key = "show_visualization", type = "boolean"},
        {key = "theme", type = "select"},
        {key = "sleep_timer", type = "number"},
        {key = "notifications", type = "boolean"},
        {key = "check_updates", type = "boolean"}
    }

    local start_y = 4
    local index = math.floor((y - start_y) / 3) + 1
    local idx = index + State.settings_scroll

    if idx >= 1 and idx <= #settings_list then
        local setting = settings_list[idx]
        local item_y = start_y + (index - 1) * 3

        -- Edit button
        if y == item_y and x >= width - 10 and x <= width - 5 then
            if setting.type == "boolean" then
                State.settings[setting.key] = not State.settings[setting.key]
                redraw()
            elseif setting.type == "select" and setting.key == "theme" then
                local themes = {"default", "dark", "ocean"}
                local current_idx = 1
                for i, t in ipairs(themes) do
                    if t == State.settings.theme then
                        current_idx = i
                        break
                    end
                end
                State.settings.theme = themes[current_idx % #themes + 1]
                redraw()
            else
                State.editing_setting = setting.key
                State.waiting_input = true
                State.input_context = "setting_edit"
                State.input_text = tostring(State.settings[setting.key])
                redraw()
            end
        end

        -- Special buttons
        if setting.key == "theme" and y == item_y and x >= width - 16 and x <= width - 11 then
            apply_theme(State.settings.theme)
            set_status("Applied theme: " .. State.settings.theme, colors.white, 2)
            redraw()
        elseif setting.key == "sleep_timer" and y == item_y and x >= width - 16 and x <= width - 11 then
            if State.settings.sleep_timer_active then
                State.settings.sleep_timer_active = false
                set_status("Sleep timer stopped", colors.white, 2)
            else
                State.settings.sleep_timer_active = true
                State.sleep_timer_start = os.clock()
                set_status("Sleep timer started: " .. State.settings.sleep_timer .. " minutes", colors.white, 2)
            end
            redraw()
        end
    end
end

local function handle_diagnostics_click(x, y, width)
    -- Check updates button
    if y == 2 and x >= width - 15 and x <= width - 2 then
        check_for_updates()
        set_status("Checking for updates...", colors.yellow, 2)
    end
end

local function handle_popup_click(x, y)
    if not State.show_popup or not State.popup_content then return false end

    -- Close button
    if y == State.popup_y and x >= State.popup_x + State.popup_w - 2 and x <= State.popup_x + State.popup_w then
        State.show_popup = false
        State.popup_content = nil
        redraw()
        return true
    end

    -- Check if click is within popup
    if x >= State.popup_x and x <= State.popup_x + State.popup_w and
       y >= State.popup_y and y <= State.popup_y + State.popup_h then
        return true -- Consume the click
    end

    return false
end

local function handle_input(char, key)
    if not State.waiting_input then return end

    if char then
        State.input_text = State.input_text .. char
        if State.editing_playlist then State.playlist_input = State.input_text end
        redraw()
        return
    end
    if not key then return end

    if key == keys.enter then
        State.waiting_input = false
        term.setCursorBlink(false)
        local context = State.input_context

        if context == "main_search" then
            State.last_query = State.input_text
            if State.last_query ~= "" then
                State.last_search_url = State.settings.api_url .. "/?search=" .. textutils.urlEncode(State.last_query)
                State.search_results = nil
                State.search_error = nil
                set_status("Searching...", current_colors.status.loading)
                http.request(State.last_search_url)
            end
        elseif context == "search_filter" then
            State.search_filter = State.input_text
        elseif context == "queue_filter" then
            State.queue_filter = State.input_text
        elseif context == "history_filter" then
            State.history_filter = State.input_text
        elseif context == "favorites_filter" then
            State.favorites_filter = State.input_text
        elseif context == "playlist_new" or context == "playlist_save_queue" then
             if State.playlist_input ~= "" then
                create_playlist(State.playlist_input)
                if context == "playlist_save_queue" and #State.queue > 0 then
                    local songs_copy = {}
                    for _, s in ipairs(State.queue) do table.insert(songs_copy, s) end
                    State.playlists[State.playlist_input].songs = songs_copy
                    save_state()
                end
            end
            State.editing_playlist = false
            State.playlist_input = ""
        elseif context == "setting_edit" then
            local setting_key = State.editing_setting
            if setting_key then
                if setting_key == "buffer_size" or setting_key == "sample_rate" or
                   setting_key == "chunk_size" or setting_key == "sleep_timer" then
                    local num_value = tonumber(State.input_text)
                    State.settings[setting_key] = num_value or State.settings[setting_key]
                else
                    State.settings[setting_key] = State.input_text
                end
            end
            State.editing_setting = nil
            set_status("Setting updated", colors.white, 2)
        end

        State.input_context = nil
        State.input_text = ""
        redraw()

    elseif key == keys.backspace and #State.input_text > 0 then
        State.input_text = string.sub(State.input_text, 1, #State.input_text - 1)
        if State.editing_playlist then State.playlist_input = State.input_text end
        redraw()
    elseif key == keys.escape then
        State.waiting_input = false
        State.input_text = ""
        State.input_context = nil
        State.editing_setting = nil
        State.editing_playlist = false
        term.setCursorBlink(false)
        redraw()
    end
end

-- Keyboard navigation
local function handle_keyboard_navigation(key)
    State.keyboard_nav_active = true

    if key == keys.up then
        if State.current_tab == TABS.SEARCH then
            State.selected_index[TABS.SEARCH] = math.max(1, State.selected_index[TABS.SEARCH] - 1)
            if State.selected_index[TABS.SEARCH] <= State.search_scroll then
                handle_list_scroll("up", "search")
            end
        elseif State.current_tab == TABS.QUEUE then
            State.selected_index[TABS.QUEUE] = math.max(1, State.selected_index[TABS.QUEUE] - 1)
            if State.selected_index[TABS.QUEUE] <= State.queue_scroll then
                handle_list_scroll("up", "queue")
            end
        elseif State.current_tab == TABS.HISTORY then
            State.selected_index[TABS.HISTORY] = math.max(1, State.selected_index[TABS.HISTORY] - 1)
            if State.selected_index[TABS.HISTORY] <= State.history_scroll then
                handle_list_scroll("up", "history")
            end
        elseif State.current_tab == TABS.FAVORITES then
            State.selected_index[TABS.FAVORITES] = math.max(1, State.selected_index[TABS.FAVORITES] - 1)
            if State.selected_index[TABS.FAVORITES] <= State.favorites_scroll then
                handle_list_scroll("up", "favorites")
            end
        end
    elseif key == keys.down then
        if State.current_tab == TABS.SEARCH and State.search_results then
            State.selected_index[TABS.SEARCH] = math.min(#State.search_results, State.selected_index[TABS.SEARCH] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 8) / 2)
            if State.selected_index[TABS.SEARCH] > State.search_scroll + items_per_page then
                handle_list_scroll("down", "search")
            end
        elseif State.current_tab == TABS.QUEUE then
            State.selected_index[TABS.QUEUE] = math.min(#State.queue, State.selected_index[TABS.QUEUE] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 2)
            if State.selected_index[TABS.QUEUE] > State.queue_scroll + items_per_page then
                handle_list_scroll("down", "queue")
            end
        elseif State.current_tab == TABS.HISTORY then
            State.selected_index[TABS.HISTORY] = math.min(#State.history, State.selected_index[TABS.HISTORY] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 2)
            if State.selected_index[TABS.HISTORY] > State.history_scroll + items_per_page then
                handle_list_scroll("down", "history")
            end
        elseif State.current_tab == TABS.FAVORITES then
            State.selected_index[TABS.FAVORITES] = math.min(#State.favorites, State.selected_index[TABS.FAVORITES] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 2)
            if State.selected_index[TABS.FAVORITES] > State.favorites_scroll + items_per_page then
                handle_list_scroll("down", "favorites")
            end
        end
    elseif key == keys.enter then
        -- Activate selected item
        if State.current_tab == TABS.SEARCH and State.search_results then
            local song = State.search_results[State.selected_index[TABS.SEARCH]]
            if song then add_to_queue(song) end
        elseif State.current_tab == TABS.QUEUE and #State.queue > 0 then
            for i = 1, State.selected_index[TABS.QUEUE] - 1 do
                table.remove(State.queue, 1)
            end
            play_next_song()
        elseif State.current_tab == TABS.HISTORY and #State.history > 0 then
            local song = State.history[State.selected_index[TABS.HISTORY]]
            if song then add_to_queue(song) end
        elseif State.current_tab == TABS.FAVORITES and #State.favorites > 0 then
            local song = State.favorites[State.selected_index[TABS.FAVORITES]]
            if song then add_to_queue(song) end
        end
    elseif key == keys.delete then
        -- Remove selected item
        if State.current_tab == TABS.QUEUE and #State.queue > 0 then
            table.remove(State.queue, State.selected_index[TABS.QUEUE])
            State.selected_index[TABS.QUEUE] = math.min(State.selected_index[TABS.QUEUE], #State.queue)
            State.selected_index[TABS.QUEUE] = math.max(1, State.selected_index[TABS.QUEUE])
            save_state()
        end
    end

    redraw()
end

-- MAIN LOOPS
local function ui_loop()
    while true do
        local event, param1, x, y = os.pullEvent()

        if event == "mouse_click" then
            State.dragging_scroll = false
            State.dragging_queue_item = false
            State.keyboard_nav_active = false

            -- Handle popup first
            if State.show_popup and handle_popup_click(x, y) then
                -- Click was on popup, do nothing else
            elseif State.mini_mode then
                handle_mini_mode_click(x, y)
            else
                local content_width = State.screen.width - TAB_LIST_WIDTH
                if x > content_width then
                    -- Click is in the tab list
                    local tab_y_start = 3
                    local tab_height = 2
                    local clicked_index = math.floor((y - tab_y_start) / tab_height) + 1
                    if clicked_index >= 1 and clicked_index <= #TAB_DATA then
                        State.current_tab = TAB_DATA[clicked_index].id
                        redraw()
                    end
                else
                    -- Click is in the content area
                    local click_handlers = {
                        [TABS.NOW_PLAYING] = handle_now_playing_click,
                        [TABS.SEARCH]      = handle_search_click,
                        [TABS.QUEUE]       = handle_queue_click,
                        [TABS.PLAYLISTS]   = handle_playlists_click,
                        [TABS.HISTORY]     = handle_history_click,
                        [TABS.FAVORITES]   = handle_favorites_click,
                        [TABS.SETTINGS]    = handle_settings_click,
                        [TABS.DIAGNOSTICS] = handle_diagnostics_click
                    }
                    local handler = click_handlers[State.current_tab]
                    if handler then
                        handler(x, y, content_width)
                    end
                end
            end
        elseif event == "mouse_drag" then
            if State.dragging_scroll then
                handle_scroll_bar_drag(y)
            elseif State.dragging_queue_item then
                handle_queue_reorder_drag(y)
            elseif (State.current_tab == TABS.NOW_PLAYING and y == 13 and x >= 2 and x <= 25) or
                   (State.mini_mode and y == 11 and x >= 7 and x <= 21) then
                State.volume = State.mini_mode and ((x - 7) / 14) or ((x - 2) / 23)
                State.volume = math.max(0.0, math.min(1.0, State.volume))
                redraw()
            end
        elseif event == "mouse_up" then
            State.dragging_scroll = false
            State.dragging_queue_item = false
        elseif event == "mouse_scroll" then
            local scroll_map = {
                [TABS.SEARCH] = "search", [TABS.QUEUE] = "queue", [TABS.PLAYLISTS] = "playlists",
                [TABS.HISTORY] = "history", [TABS.FAVORITES] = "favorites", [TABS.SETTINGS] = "settings"
            }
            local scroll_type = scroll_map[State.current_tab]
            if scroll_type then
                handle_list_scroll(param1 == 1 and "down" or "up", scroll_type)
            end
        elseif event == "char" then
            handle_input(param1, nil)
        elseif event == "key" then
            if State.waiting_input then
                handle_input(nil, param1)
            elseif State.show_popup then
                if param1 == keys.escape then
                    State.show_popup = false
                    redraw()
                end
            elseif param1 == keys.escape then
                if State.mini_mode then
                    State.mini_mode = false
                    redraw()
                end
            -- HOTKEYS
            elseif param1 == HOTKEYS.play_pause then
                if State.mini_mode then
                    handle_mini_mode_click(2, 9)
                else
                    handle_now_playing_click(2, 17, State.screen.width - TAB_LIST_WIDTH)
                end
            elseif param1 == HOTKEYS.next then
                play_next_song()
            elseif param1 == HOTKEYS.volume_up then
                State.volume = math.min(1.0, State.volume + 0.1)
                set_status("Volume: " .. math.floor(State.volume * 100) .. "%", colors.white, 1)
                redraw()
            elseif param1 == HOTKEYS.volume_down then
                State.volume = math.max(0.0, State.volume - 0.1)
                set_status("Volume: " .. math.floor(State.volume * 100) .. "%", colors.white, 1)
                redraw()
            elseif param1 == HOTKEYS.favorite and State.current_song then
                toggle_favorite(State.current_song)
            elseif param1 == HOTKEYS.mini_mode then
                State.mini_mode = not State.mini_mode
                redraw()
            elseif param1 == HOTKEYS.search then
                State.current_tab = TABS.SEARCH
                redraw()
            elseif param1 == HOTKEYS.queue then
                State.current_tab = TABS.QUEUE
                redraw()
            elseif param1 == HOTKEYS.help then
                show_help_popup()
            elseif param1 == keys.space and State.current_tab == TABS.NOW_PLAYING then
                handle_now_playing_click(2, 17, State.screen.width - TAB_LIST_WIDTH)
            elseif param1 == keys.tab then
                State.current_tab = (State.current_tab % #TAB_DATA) + 1
                redraw()
            elseif param1 == keys.up or param1 == keys.down or param1 == keys.enter or param1 == keys.delete then
                handle_keyboard_navigation(param1)
            elseif param1 == keys.pageUp then
                local tab_map = {
                    [TABS.SEARCH] = "search", [TABS.QUEUE] = "queue", [TABS.HISTORY] = "history", [TABS.FAVORITES] = "favorites"
                }
                if tab_map[State.current_tab] then
                    for i = 1, 5 do handle_list_scroll("up", tab_map[State.current_tab]) end
                end
            elseif param1 == keys.pageDown then
                local tab_map = {
                    [TABS.SEARCH] = "search", [TABS.QUEUE] = "queue", [TABS.HISTORY] = "history", [TABS.FAVORITES] = "favorites"
                }
                if tab_map[State.current_tab] then
                    for i = 1, 5 do handle_list_scroll("down", tab_map[State.current_tab]) end
                end
            end
        elseif event == "stream_ended" then
            if State.settings.auto_play_next then
                play_next_song()
            else
                State.is_playing = false
                set_status("Playback ended", colors.white, 3)
                show_notification("Playback ended", 3)
                redraw()
            end
        elseif event == "timer" then
            if param1 == State.status_timer then
                State.status_message = nil
                State.status_timer = nil
                redraw()
            end
        elseif event == "playback_update" then
            update_sleep_timer()
            redraw()
        end
    end
end

local function audio_loop()
    while true do
        os.pullEvent("playback")

        while State.is_playing do
            if #State.buffer > 0 then
                local chunk = table.remove(State.buffer, 1)
                if chunk then
                    -- Update visualization
                    update_visualization_data(chunk)

                    local scaled = {}
                    for i = 1, #chunk do
                        local s = math.floor(chunk[i] * State.volume)
                        s = math.max(-128, math.min(127, s))
                        scaled[i] = s
                    end

                    while not speaker.playAudio(scaled, State.volume) do
                        if not State.is_playing then break end
                    end

                    if State.is_playing then
                        State.chunks_played = State.chunks_played + 1
                        if #State.buffer < CONFIG.buffer_threshold and not State.chunk_request_pending then
                            request_chunk()
                        end

                        os.pullEvent("speaker_audio_empty")
                    end
                end
            elseif State.ended then
                State.is_playing = false
                State.buffer_size_on_pause = 0
                os.queueEvent("stream_ended")
                break
            else
                sleep(0.1)
                if not State.chunk_request_pending then
                    request_chunk()
                end
            end
        end
    end
end

local function http_loop()
    while true do
        local event, url, handle = os.pullEvent()
        if event == "http_success" then
            handle_http_success(url, handle)
        elseif event == "http_failure" then
            handle_http_failure(url, handle)
        end
    end
end

local function update_loop()
    while true do
        sleep(CONFIG.update_interval)
        if State.is_playing then
            os.queueEvent("playback_update")
        end
    end
end

-- MAIN EXECUTION
local function main()
    term.clear()
    term.setCursorPos(1, 1)
    print("CC Music Player v5.0 - Ultra Modular with Original UI")
    print("Loading saved state...")

    load_state()
    apply_theme(State.settings.theme)

    if State.settings.check_updates then
        check_for_updates()
    end

    print("Initializing...")
    sleep(0.5)

    redraw()

    parallel.waitForAny(ui_loop, audio_loop, http_loop, update_loop)
end

-- Start the application
main()
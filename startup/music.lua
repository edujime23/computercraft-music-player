-- ========================================
-- CC Music Player v3.0 (Full Feature Set)
-- ========================================

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

    -- File paths
    queue_file = "music_queue.dat",
    history_file = "music_history.dat",
    favorites_file = "music_favorites.dat",
    settings_file = "music_settings.dat"
}

local COLORS = {
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
    selected = colors.lightBlue
}

local REPEAT_MODES = { OFF = 0, ONE = 1, ALL = 2 }
local TABS = { NOW_PLAYING = 1, SEARCH = 2, QUEUE = 3, HISTORY = 4, FAVORITES = 5, SETTINGS = 6 }

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
    status_message = nil,
    status_color = colors.white,
    status_timer = nil,

    -- Navigation State
    selected_index = {
        [TABS.SEARCH] = 1,
        [TABS.QUEUE] = 1,
        [TABS.HISTORY] = 1,
        [TABS.FAVORITES] = 1,
        [TABS.SETTINGS] = 1
    },
    keyboard_nav_active = false,

    -- Search State
    last_query = "",
    last_search_url = nil,
    search_results = nil,
    search_error = nil,
    search_scroll = 0,

    -- Queue State
    queue = {},
    history = {},
    favorites = {},
    repeat_mode = REPEAT_MODES.OFF,
    shuffle = false,
    queue_scroll = 0,
    history_scroll = 0,
    favorites_scroll = 0,

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

    -- Visualization
    current_chunk_rms = 0,
    visualization_data = {},

    -- Connection State
    connection_errors = 0,
    chunk_request_pending = false,

    -- Settings
    settings = {
        api_url = CONFIG.api_base_url,
        buffer_size = CONFIG.buffer_max,
        sample_rate = CONFIG.audio_sample_rate,
        chunk_size = CONFIG.audio_chunk_size,
        auto_play_next = true,
        show_visualization = true
    },
    settings_scroll = 0,
    editing_setting = nil
}

-- Store scroll bar info for click detection
local scroll_infos = {}

-- FORWARD DECLARATIONS
local redraw
local save_state
local load_state

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
            if success then
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
end

function load_state()
    State.queue = load_table_from_file(CONFIG.queue_file) or {}
    State.history = load_table_from_file(CONFIG.history_file) or {}
    State.favorites = load_table_from_file(CONFIG.favorites_file) or {}

    local loaded_settings = load_table_from_file(CONFIG.settings_file)
    if loaded_settings then
        for k, v in pairs(loaded_settings) do
            State.settings[k] = v
        end
        -- Apply loaded settings
        CONFIG.api_base_url = State.settings.api_url
        CONFIG.buffer_max = State.settings.buffer_size
        CONFIG.audio_sample_rate = State.settings.sample_rate
        CONFIG.audio_chunk_size = State.settings.chunk_size
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

-- UTILITY FUNCTIONS
local function format_time(seconds)
    if not seconds or seconds == 0 then return "--:--" end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
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
    if #text > max_length then
        return string.sub(text, 1, max_length - 3) .. "..."
    end
    return text
end

local function find_song_in_favorites(song)
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
    local idx = find_song_in_favorites(song)
    if idx then
        table.remove(State.favorites, idx)
        set_status("Removed from favorites", COLORS.status.error, 2)
    else
        table.insert(State.favorites, 1, song)
        set_status("Added to favorites", COLORS.status.playing, 2)
    end
    save_state()
end

local function draw_progress_bar(x, y, width, progress, bg_color, fg_color)
    paintutils.drawBox(x, y, x + width - 1, y, bg_color)
    local filled = math.floor(width * progress)
    if filled > 0 then
        paintutils.drawBox(x, y, x + filled - 1, y, fg_color)
    end
end

-- VISUALIZATION
local function update_visualization_data(chunk)
    if not State.settings.show_visualization or not chunk then return end

    -- Calculate RMS (root mean square) for volume level
    local sum = 0
    for i = 1, #chunk do
        sum = sum + (chunk[i] ^ 2)
    end
    State.current_chunk_rms = math.sqrt(sum / #chunk) / 128

    -- Add to visualization buffer
    table.insert(State.visualization_data, State.current_chunk_rms)
    if #State.visualization_data > 20 then
        table.remove(State.visualization_data, 1)
    end
end

local function draw_visualization(x, y, width, height)
    if not State.settings.show_visualization or #State.visualization_data == 0 then
        return
    end

    term.setBackgroundColor(colors.black)

    -- Draw visualization bars
    local bar_width = math.floor(width / #State.visualization_data)
    for i, value in ipairs(State.visualization_data) do
        local bar_height = math.floor(value * height)
        local bar_x = x + (i - 1) * bar_width

        for h = 0, bar_height - 1 do
            local color = COLORS.visualization.low
            if h > height * 0.66 then
                color = COLORS.visualization.high
            elseif h > height * 0.33 then
                color = COLORS.visualization.mid
            end

            term.setCursorPos(bar_x, y + height - h - 1)
            term.setBackgroundColor(color)
            for w = 1, bar_width - 1 do
                term.write(" ")
            end
        end
    end

    term.setBackgroundColor(colors.black)
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
        term.setBackgroundColor(COLORS.scroll.track)
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
        term.setBackgroundColor(COLORS.scroll.thumb)
        term.setTextColor(colors.black)
        term.write(" ")
    end

    -- Draw arrows
    term.setCursorPos(x, start_y)
    term.setBackgroundColor(COLORS.scroll.track)
    term.setTextColor(COLORS.scroll.arrow)
    term.write("^")

    term.setCursorPos(x, start_y + height - 1)
    term.setBackgroundColor(COLORS.scroll.track)
    term.setTextColor(COLORS.scroll.arrow)
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

-- SCROLL HANDLERS
local function handle_list_scroll(direction, list_type)
    local h = State.screen.height
    local start_y = (list_type == "search") and 7 or 4
    local status_bar_height = 1
    local available_height = h - start_y - status_bar_height
    local items_per_page = math.floor(available_height / 3)
    items_per_page = math.max(1, items_per_page)

    local list, scroll_var
    if list_type == "search" then
        list = State.search_results or {}
        scroll_var = "search_scroll"
    elseif list_type == "queue" then
        list = State.queue
        scroll_var = "queue_scroll"
    elseif list_type == "history" then
        list = State.history
        scroll_var = "history_scroll"
    elseif list_type == "favorites" then
        list = State.favorites
        scroll_var = "favorites_scroll"
    elseif list_type == "settings" then
        list = {"api_url", "buffer_size", "sample_rate", "chunk_size", "auto_play_next", "show_visualization"}
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
        -- Up arrow
        handle_list_scroll("up", scroll_type)
    elseif relative_y == scroll_info.height - 1 then
        -- Down arrow
        handle_list_scroll("down", scroll_type)
    elseif relative_y >= scroll_info.thumb_pos and relative_y < scroll_info.thumb_pos + scroll_info.thumb_size then
        -- Start dragging thumb
        State.dragging_scroll = true
        State.drag_scroll_type = scroll_type
        State.drag_start_y = click_y
        State.drag_start_scroll = scroll_info.scroll_pos
    else
        -- Click on track (page up/down)
        local new_scroll
        if relative_y < scroll_info.thumb_pos then
            -- Page up
            new_scroll = math.max(0, scroll_info.scroll_pos - scroll_info.visible_items)
        else
            -- Page down
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
    local items_per_page = math.floor(available_height / 3)
    items_per_page = math.max(1, items_per_page)

    -- Calculate which position we're hovering over
    local hover_index = math.floor((y - start_y) / 3) + 1 + State.queue_scroll
    hover_index = math.max(1, math.min(#State.queue, hover_index))

    if hover_index ~= State.drag_item_index then
        -- Move the item
        local item = table.remove(State.queue, State.drag_item_index)
        table.insert(State.queue, hover_index, item)
        State.drag_item_index = hover_index
        save_state()
        redraw()
    end
end

-- Playback position tracking (chunk-accurate)
local function reset_playback_timing()
    State.playback_position = 0
    State.chunks_played = 0
    State.buffer_size_on_pause = 0
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

-- DRAWING FUNCTIONS
local function draw_tabs()
    local w, h = State.screen.width, State.screen.height
    term.setBackgroundColor(COLORS.tabs.inactive_bg)
    term.setTextColor(COLORS.tabs.inactive_text)
    term.setCursorPos(1, 1)
    term.clearLine()

    local tabs = {" Playing ", " Search ", " Queue ", " History ", " Favs ", " Settings "}
    local tab_width = math.floor(w / #tabs)

    for i, name in ipairs(tabs) do
        local x = (i - 1) * tab_width + math.floor((tab_width - #name) / 2) + 1
        term.setCursorPos(x, 1)

        if State.current_tab == i then
            term.setBackgroundColor(COLORS.tabs.active_bg)
            term.setTextColor(COLORS.tabs.active_text)
        else
            term.setBackgroundColor(COLORS.tabs.inactive_bg)
            term.setTextColor(COLORS.tabs.inactive_text)
        end
        term.write(name)
    end

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function draw_status_bar()
    local w, h = State.screen.width, State.screen.height
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.gray)
    term.clearLine()

    if State.status_message then
        term.setTextColor(State.status_color)
        local msg = truncate_text(State.status_message, w - 20)
        term.setCursorPos(2, h)
        term.write(msg)
    end

    -- Connection status
    term.setCursorPos(w - 15, h)
    if State.connection_errors > 0 then
        term.setTextColor(COLORS.status.error)
        term.write("Conn: Error")
    elseif State.is_streaming then
        term.setTextColor(COLORS.status.playing)
        term.write("Conn: OK")
    else
        term.setTextColor(colors.lightGray)
        term.write("Conn: Idle")
    end

    term.setBackgroundColor(colors.black)
end

local function draw_song_info()
    local w = State.screen.width
    term.setCursorPos(2, 3)
    term.setBackgroundColor(colors.black)

    if State.current_song then
        term.setTextColor(colors.white)
        local title = truncate_text(State.current_song.title or "Unknown", w - 8)
        term.write(title)

        -- Favorite star
        term.setCursorPos(w - 4, 3)
        if is_favorite(State.current_song) then
            term.setTextColor(colors.yellow)
            term.write("*")
        else
            term.setTextColor(colors.gray)
            term.write("o")
        end

        term.setCursorPos(2, 4)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lightGray)
        local artist = truncate_text(State.current_song.artist or "Unknown", w - 4)
        term.write(artist)

        -- Additional metadata if available
        if State.current_song.duration then
            term.setCursorPos(2, 5)
            term.setTextColor(colors.gray)
            term.write("Duration: " .. format_time(State.current_song.duration))
        end
    else
        term.setTextColor(colors.gray)
        term.write("No song selected")
    end
end

local function draw_playback_status()
    term.setCursorPos(2, 7)
    term.setBackgroundColor(colors.black)

    if State.loading then
        term.setTextColor(COLORS.status.loading)
        term.write("Loading...")
    elseif State.connection_errors > 0 then
        term.setTextColor(COLORS.status.error)
        term.write("Connection error (retrying...)")
    elseif State.is_streaming and State.is_playing then
        term.setTextColor(COLORS.status.playing)
        term.write("Playing")
    elseif State.current_song then
        term.setTextColor(COLORS.status.paused)
        term.write("Paused")
    end
end

local function draw_progress()
    local w = State.screen.width

    if State.current_song and State.total_duration > 0 then
        update_playback_position()
        term.setCursorPos(2, 9)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(format_time(State.playback_position) .. " / " .. format_time(State.total_duration))

        draw_progress_bar(2, 10, w - 3, State.playback_position / State.total_duration,
                         COLORS.progress.bg, COLORS.progress.fg)
    end
end

local function draw_volume_control()
    term.setCursorPos(2, 12)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Volume:")

    draw_progress_bar(2, 13, 24, State.volume, COLORS.progress.bg, COLORS.progress.volume)

    local percentage = math.floor(100 * (State.volume))
    term.setCursorPos(27, 13)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(percentage .. "%")
end

local function draw_buffer_status()
    term.setCursorPos(2, 15)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.cyan)
    local buffer_percent = math.min(100, math.floor((#State.buffer / CONFIG.buffer_max) * 100))
    term.write("Buffer: " .. #State.buffer .. " chunks (" .. buffer_percent .. "%)")
end

local function draw_control_buttons()
    local button_y = 17
    local button_x = 2

    -- Play/Pause Button
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(State.is_playing and colors.red or colors.green)
    term.write(State.is_playing and " Pause " or " Play  ")
    button_x = button_x + 8

    -- Skip Button
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(" Skip ")
    button_x = button_x + 7

    -- Repeat Button
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(State.repeat_mode > 0 and colors.green or colors.gray)
    term.setTextColor(colors.white)
    local repeat_icons = {"[-]", "[1]", "[A]"}
    term.write(" " .. repeat_icons[State.repeat_mode + 1] .. " ")
    button_x = button_x + 6

    -- Shuffle Button
    term.setCursorPos(button_x, button_y)
    term.setBackgroundColor(State.shuffle and colors.green or colors.gray)
    term.setTextColor(colors.white)
    term.write(" Shuf ")
    button_x = button_x + 7

    -- Favorite Button
    if State.current_song then
        term.setCursorPos(button_x, button_y)
        term.setBackgroundColor(is_favorite(State.current_song) and colors.yellow or colors.gray)
        term.setTextColor(colors.white)
        term.write(" Fav ")
    end

    term.setBackgroundColor(colors.black)
end

local function draw_now_playing()
    local h = State.screen.height

    draw_song_info()
    draw_playback_status()
    draw_progress()
    draw_volume_control()
    draw_buffer_status()
    draw_control_buttons()

    -- Draw visualization if enabled
    if State.settings.show_visualization and h > 22 then
        draw_visualization(2, 19, State.screen.width - 3, h - 20)
    end
end

local function draw_search_box()
    local w = State.screen.width
    paintutils.drawFilledBox(2, 3, w - 1, 5, colors.lightGray)

    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Search for music:")

    term.setCursorPos(3, 4)
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.black)

    if State.waiting_input then
        term.write(State.input_text)
        if #State.input_text < w - 6 then
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

    term.setBackgroundColor(colors.black)
    term.setCursorBlink(false)
end

-- Generic list drawer for search results, queue, history, favorites
local function draw_list_items(list, list_type, start_y, with_actions)
    local w, h = State.screen.width, State.screen.height
    local status_bar_height = 1
    local end_y = h - status_bar_height
    local available_height = end_y - start_y
    local items_per_page = math.floor(available_height / 3)
    items_per_page = math.max(1, items_per_page)

    local scroll_var = list_type .. "_scroll"
    local max_scroll = math.max(0, #list - items_per_page)
    State[scroll_var] = math.min(State[scroll_var], max_scroll)
    State[scroll_var] = math.max(0, State[scroll_var])

    if #list == 0 then
        scroll_infos[list_type] = nil
        return false
    end

    -- Draw scroll bar
    draw_scroll_bar(w, start_y, available_height, #list, items_per_page, State[scroll_var], list_type)

    for i = 1, items_per_page do
        local idx = i + State[scroll_var]
        local item = list[idx]
        if not item then break end
        local y = start_y + (i - 1) * 3

        if y <= end_y - 2 then
            -- Highlight selected item for keyboard navigation
            if State.keyboard_nav_active and State.selected_index[State.current_tab] == idx then
                paintutils.drawBox(2, y, w - 2, y + 1, COLORS.selected)
            end

            term.setBackgroundColor(colors.black)
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)

            -- Draw dragged item differently
            if State.dragging_queue_item and State.drag_item_index == idx and list_type == "queue" then
                term.setBackgroundColor(colors.blue)
            end

            local title = truncate_text(item.title or "Unknown Title", w - 20)
            term.write(idx .. ". " .. title)

            -- Favorite indicator
            if is_favorite(item) then
                term.setTextColor(colors.yellow)
                term.write(" *")
            end

            term.setCursorPos(5, y + 1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.lightGray)
            local artist = truncate_text(item.artist or "Unknown Artist", w - 20)
            term.write(artist)

            -- Duration
            if item.duration then
                local dur_str = format_time(item.duration)
                term.setCursorPos(w - #dur_str - 8, y)
                term.setBackgroundColor(colors.black)
                term.setTextColor(colors.gray)
                term.write(dur_str)
            end

            -- Action buttons
            if with_actions then
                if list_type == "search" or list_type == "history" or list_type == "favorites" then
                    -- Add button
                    term.setCursorPos(w - 10, y + 1)
                    term.setBackgroundColor(colors.green)
                    term.setTextColor(colors.white)
                    term.write(" + ")
                elseif list_type == "queue" then
                    -- Remove button
                    term.setCursorPos(w - 7, y)
                    term.setBackgroundColor(colors.red)
                    term.setTextColor(colors.white)
                    term.write(" X ")

                    -- Move indicator
                    if State.keyboard_nav_active then
                        term.setCursorPos(w - 12, y)
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

local function draw_search_results()
    if State.search_results and #State.search_results > 0 then
        draw_list_items(State.search_results, "search", 7, true)
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

local function draw_search()
    draw_search_box()
    draw_search_results()
end

local function draw_queue_header()
    local w = State.screen.width
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Queue (" .. #State.queue .. " songs):")

    -- Queue controls
    term.setCursorPos(w - 28, 2)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.write(" Clear ")

    term.setCursorPos(w - 20, 2)
    term.setBackgroundColor(State.shuffle and colors.green or colors.gray)
    term.write(" Shuffle ")

    term.setCursorPos(w - 10, 2)
    term.setBackgroundColor(colors.gray)
    term.write(" Save ")

    term.setBackgroundColor(colors.black)
end

local function draw_queue()
    draw_queue_header()

    if #State.queue == 0 then
        scroll_infos.queue = nil
        term.setCursorPos(2, 4)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.gray)
        term.write("Queue is empty")
        term.setCursorPos(2, 5)
        term.write("Add songs from Search tab")
    else
        draw_list_items(State.queue, "queue", 4, true)
    end
end

local function draw_history()
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Recently Played (" .. #State.history .. " songs):")

    -- Clear history button
    if #State.history > 0 then
        local w = State.screen.width
        term.setCursorPos(w - 10, 2)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" Clear ")
    end

    term.setBackgroundColor(colors.black)

    if #State.history == 0 then
        scroll_infos.history = nil
        term.setCursorPos(2, 4)
        term.setTextColor(colors.gray)
        term.write("No history yet")
    else
        draw_list_items(State.history, "history", 4, true)
    end
end

local function draw_favorites()
    term.setCursorPos(2, 2)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Favorite Songs (" .. #State.favorites .. " songs):")

    -- Clear favorites button
    if #State.favorites > 0 then
        local w = State.screen.width
        term.setCursorPos(w - 10, 2)
        term.setBackgroundColor(colors.gray)
        term.setTextColor(colors.white)
        term.write(" Clear ")
    end

    term.setBackgroundColor(colors.black)

    if #State.favorites == 0 then
        scroll_infos.favorites = nil
        term.setCursorPos(2, 4)
        term.setTextColor(colors.gray)
        term.write("No favorites yet")
        term.setCursorPos(2, 5)
        term.write("Mark songs as favorite from Now Playing")
    else
        draw_list_items(State.favorites, "favorites", 4, true)
    end
end

local function draw_settings()
    local w, h = State.screen.width, State.screen.height

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
        {key = "show_visualization", label = "Show Visualization", value = State.settings.show_visualization and "Yes" or "No", type = "boolean"}
    }

    local start_y = 4
    local status_bar_height = 1
    local end_y = h - status_bar_height
    local available_height = end_y - start_y
    local items_per_page = math.floor(available_height / 3)
    items_per_page = math.max(1, items_per_page)

    for i = 1, items_per_page do
        local idx = i + State.settings_scroll
        local setting = settings_list[idx]
        if not setting then break end

        local y = start_y + (i - 1) * 3

        term.setCursorPos(2, y)
        term.setTextColor(colors.white)
        term.write(setting.label .. ":")

        term.setCursorPos(4, y + 1)

        if State.editing_setting == setting.key then
            term.setBackgroundColor(colors.lightGray)
            term.setTextColor(colors.black)
            term.write(State.input_text .. "_")
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. setting.value .. " ")
        end

        -- Edit button
        term.setCursorPos(w - 10, y)
        term.setBackgroundColor(colors.blue)
        term.setTextColor(colors.white)
        term.write(" Edit ")

        term.setBackgroundColor(colors.black)
    end

    -- Save button
    term.setCursorPos(w - 12, 2)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.white)
    term.write(" Save All ")

    term.setBackgroundColor(colors.black)
end

-- DEFINE REDRAW FUNCTION HERE
function redraw()
    State.screen.width, State.screen.height = term.getSize()
    term.clear()
    draw_tabs()

    if State.current_tab == TABS.NOW_PLAYING then
        draw_now_playing()
    elseif State.current_tab == TABS.SEARCH then
        draw_search()
    elseif State.current_tab == TABS.QUEUE then
        draw_queue()
    elseif State.current_tab == TABS.HISTORY then
        draw_history()
    elseif State.current_tab == TABS.FAVORITES then
        draw_favorites()
    elseif State.current_tab == TABS.SETTINGS then
        draw_settings()
    end

    draw_status_bar()
end

-- NETWORK & STREAM HANDLING
local function stop_current_stream()
    if State.session_id then
        http.post(CONFIG.api_base_url .. "/stop_stream/" .. State.session_id, "")
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
    reset_playback_timing()
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
        set_status("Stream started", COLORS.status.playing, 2)

        -- Request initial chunks
        for i = 1, CONFIG.chunk_request_ahead do
            request_chunk()
        end
    else
        State.loading = false
        State.current_song = nil
        State.connection_errors = State.connection_errors + 1
        set_status("Failed to start stream", COLORS.status.error, 3)
    end
    redraw()
end

local function handle_chunk_response(data, response_code)
    State.chunk_request_pending = false

    if response_code == 204 or #data == 0 then
        State.ended = true
        if State.is_playing then
            os.queueEvent("stream_ended")
        end
    else
        local pcm_samples = convert_pcm_chunk(data)
        table.insert(State.buffer, pcm_samples)
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
        set_status("Search failed", COLORS.status.error, 3)
    end
    redraw()
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
    end
end

local function handle_http_failure(url, handle)
    if State.last_search_url and url == State.last_search_url then
        State.search_error = "Connection failed"
        State.last_search_url = nil
        set_status("Search connection failed", COLORS.status.error, 3)
        redraw()
    elseif State.session_id and url:find("/chunk/") then
        State.chunk_request_pending = false
        State.connection_errors = State.connection_errors + 1
        if State.connection_errors < 5 then
            sleep(CONFIG.retry_delay)
            request_chunk()
        else
            set_status("Too many connection errors", COLORS.status.error)
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

-- INPUT HANDLERS
local function handle_now_playing_click(x, y)
    -- Volume control
    if y == 13 and x >= 2 and x <= 25 then
        State.volume = ((x - 2) / 23)
        State.volume = math.max(0.0, math.min(1.0, State.volume))
        redraw()
        return
    end

    -- Favorite star
    if State.current_song and y == 3 and x >= State.screen.width - 4 and x <= State.screen.width - 3 then
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
        end
    end
    redraw()
end

local function add_to_queue(song)
    table.insert(State.queue, song)
    set_status("Added to queue", COLORS.status.playing, 2)
    if not State.current_song then
        play_next_song()
    end
    save_state()
    redraw()
end

local function handle_list_click(x, y, list, list_type, start_y)
    local w = State.screen.width
    local h = State.screen.height
    local status_bar_height = 1
    local available_height = h - start_y - status_bar_height
    local items_per_page = math.floor(available_height / 3)
    items_per_page = math.max(1, items_per_page)

    local scroll_var = list_type .. "_scroll"
    local index = math.floor((y - start_y) / 3) + 1
    local idx = index + State[scroll_var]

    if idx >= 1 and idx <= #list then
        local item = list[idx]
        local item_y = start_y + (index - 1) * 3

        -- Check action buttons
        if list_type == "queue" then
            -- Remove button
            if y == item_y and x >= w - 7 and x <= w - 5 then
                table.remove(list, idx)
                -- Adjust scroll if needed
                local max_scroll = math.max(0, #list - items_per_page)
                State[scroll_var] = math.min(State[scroll_var], max_scroll)
                set_status("Removed from queue", COLORS.status.error, 2)
                save_state()
                redraw()
                return true
            end
            -- Move handle for reordering
            if y == item_y and x >= w - 12 and x <= w - 9 then
                State.dragging_queue_item = true
                State.drag_item_index = idx
                redraw()
                return true
            end
        elseif y == item_y + 1 and x >= w - 10 and x <= w - 8 then
            -- Add button
            add_to_queue(item)
            return true
        end

        -- Double-click to play
        if State.last_click and State.last_click.x == x and State.last_click.y == y
           and os.clock() - State.last_click.time < 0.5 then
            if list_type == "queue" then
                -- Play from queue position
                for i = 1, idx - 1 do
                    table.remove(State.queue, 1)
                end
                play_next_song()
            else
                -- Play immediately
                start_stream(item.id, item)
            end
            State.last_click = nil
            return true
        end

        State.last_click = {x = x, y = y, time = os.clock()}
    end

    return false
end

local function handle_search_click(x, y)
    local w = State.screen.width

    -- Check scroll bar click first
    if scroll_infos.search and x == scroll_infos.search.x then
        handle_scroll_bar_click(scroll_infos.search, y, "search")
        return
    end

    -- Search box
    if y >= 3 and y <= 5 and x >= 2 and x <= w - 1 then
        State.waiting_input = true
        State.input_text = ""
        State.search_results = nil
        State.search_error = nil
        redraw()
        return
    end

    -- Results
    if State.search_results then
        handle_list_click(x, y, State.search_results, "search", 7)
    end
end

local function handle_queue_click(x, y)
    local w = State.screen.width

    -- Check scroll bar click first
    if scroll_infos.queue and x == scroll_infos.queue.x then
        handle_scroll_bar_click(scroll_infos.queue, y, "queue")
        return
    end

    -- Clear button
    if y == 2 and x >= w - 28 and x <= w - 22 then
        State.queue = {}
        State.queue_scroll = 0
        set_status("Queue cleared", colors.white, 2)
        save_state()
        redraw()
        return
    end

    -- Shuffle button
    if y == 2 and x >= w - 20 and x <= w - 11 then
        if #State.queue > 0 then
            State.queue = shuffle_table(State.queue)
            set_status("Queue shuffled", colors.white, 2)
            save_state()
            redraw()
        end
        return
    end

    -- Save button
    if y == 2 and x >= w - 10 and x <= w - 5 then
        save_state()
        set_status("Queue saved", COLORS.status.playing, 2)
        return
    end

    -- Queue items
    handle_list_click(x, y, State.queue, "queue", 4)
end

local function handle_history_click(x, y)
    local w = State.screen.width

    -- Check scroll bar click first
    if scroll_infos.history and x == scroll_infos.history.x then
        handle_scroll_bar_click(scroll_infos.history, y, "history")
        return
    end

    -- Clear button
    if y == 2 and x >= w - 10 and x <= w - 4 and #State.history > 0 then
        State.history = {}
        State.history_scroll = 0
        set_status("History cleared", colors.white, 2)
        save_state()
        redraw()
        return
    end

    -- History items
    handle_list_click(x, y, State.history, "history", 4)
end

local function handle_favorites_click(x, y)
    local w = State.screen.width

    -- Check scroll bar click first
    if scroll_infos.favorites and x == scroll_infos.favorites.x then
        handle_scroll_bar_click(scroll_infos.favorites, y, "favorites")
        return
    end

    -- Clear button
    if y == 2 and x >= w - 10 and x <= w - 4 and #State.favorites > 0 then
        State.favorites = {}
        State.favorites_scroll = 0
        set_status("Favorites cleared", colors.white, 2)
        save_state()
        redraw()
        return
    end

    -- Favorite items
    handle_list_click(x, y, State.favorites, "favorites", 4)
end

local function handle_settings_click(x, y)
    local w = State.screen.width

    -- Save All button
    if y == 2 and x >= w - 12 and x <= w - 3 then
        -- Apply settings
        CONFIG.api_base_url = State.settings.api_url
        CONFIG.buffer_max = State.settings.buffer_size
        CONFIG.audio_sample_rate = State.settings.sample_rate
        CONFIG.audio_chunk_size = State.settings.chunk_size
        State.samples_per_chunk = State.settings.chunk_size
        State.sample_rate = State.settings.sample_rate

        save_state()
        set_status("Settings saved", COLORS.status.playing, 2)
        return
    end

    -- Setting items
    local settings_list = {
        {key = "api_url", type = "string"},
        {key = "buffer_size", type = "number"},
        {key = "sample_rate", type = "number"},
        {key = "chunk_size", type = "number"},
        {key = "auto_play_next", type = "boolean"},
        {key = "show_visualization", type = "boolean"}
    }

    local start_y = 4
    local index = math.floor((y - start_y) / 3) + 1
    local idx = index + State.settings_scroll

    if idx >= 1 and idx <= #settings_list then
        local setting = settings_list[idx]
        local item_y = start_y + (index - 1) * 3

        -- Edit button
        if y == item_y and x >= w - 10 and x <= w - 5 then
            if setting.type == "boolean" then
                State.settings[setting.key] = not State.settings[setting.key]
                redraw()
            else
                State.editing_setting = setting.key
                State.waiting_input = true
                State.input_text = tostring(State.settings[setting.key])
                redraw()
            end
        end
    end
end

local function handle_search_input(char, key)
    if char then
        State.input_text = State.input_text .. char
        redraw()
    elseif key then
        if key == keys.enter then
            State.waiting_input = false
            term.setCursorBlink(false)

            if State.editing_setting then
                local key = State.editing_setting
                if key == "buffer_size" or key == "sample_rate" or key == "chunk_size" then
                    local num_value = tonumber(State.input_text)
                    State.settings[key] = num_value or State.settings[key]
                else
                    State.settings[key] = State.input_text
                end
                State.editing_setting = nil
                set_status("Setting updated", colors.white, 2)
            else
                -- Search
                State.last_query = State.input_text
                if State.last_query ~= "" then
                    State.last_search_url = State.settings.api_url .. "/?search=" .. textutils.urlEncode(State.last_query)
                    State.search_results = nil
                    State.search_error = nil
                    set_status("Searching...", COLORS.status.loading)
                    http.request(State.last_search_url)
                end
            end
            redraw()
        elseif key == keys.backspace and #State.input_text > 0 then
            State.input_text = string.sub(State.input_text, 1, #State.input_text - 1)
            redraw()
        elseif key == keys.escape then
            State.waiting_input = false
            State.input_text = ""
            State.editing_setting = nil
            redraw()
        end
    end
end

-- Keyboard navigation
local function handle_keyboard_navigation(key)
    State.keyboard_nav_active = true

    if key == keys.up then
        if State.current_tab == TABS.SEARCH then
            State.selected_index[TABS.SEARCH] = math.max(1, State.selected_index[TABS.SEARCH] - 1)
            -- Adjust scroll if needed
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
            -- Adjust scroll if needed
            local h = State.screen.height
            local items_per_page = math.floor((h - 8) / 3)
            if State.selected_index[TABS.SEARCH] > State.search_scroll + items_per_page then
                handle_list_scroll("down", "search")
            end
        elseif State.current_tab == TABS.QUEUE then
            State.selected_index[TABS.QUEUE] = math.min(#State.queue, State.selected_index[TABS.QUEUE] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 3)
            if State.selected_index[TABS.QUEUE] > State.queue_scroll + items_per_page then
                handle_list_scroll("down", "queue")
            end
        elseif State.current_tab == TABS.HISTORY then
            State.selected_index[TABS.HISTORY] = math.min(#State.history, State.selected_index[TABS.HISTORY] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 3)
            if State.selected_index[TABS.HISTORY] > State.history_scroll + items_per_page then
                handle_list_scroll("down", "history")
            end
        elseif State.current_tab == TABS.FAVORITES then
            State.selected_index[TABS.FAVORITES] = math.min(#State.favorites, State.selected_index[TABS.FAVORITES] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 3)
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
            -- Play from this position
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

            if y == 1 then
                local tab_width = State.screen.width / 6
                State.current_tab = math.ceil(x / tab_width)
                State.current_tab = math.max(1, math.min(6, State.current_tab))
                redraw()
            elseif State.current_tab == TABS.NOW_PLAYING then
                handle_now_playing_click(x, y)
            elseif State.current_tab == TABS.SEARCH then
                handle_search_click(x, y)
            elseif State.current_tab == TABS.QUEUE then
                handle_queue_click(x, y)
            elseif State.current_tab == TABS.HISTORY then
                handle_history_click(x, y)
            elseif State.current_tab == TABS.FAVORITES then
                handle_favorites_click(x, y)
            elseif State.current_tab == TABS.SETTINGS then
                handle_settings_click(x, y)
            end
        elseif event == "mouse_drag" then
            if State.dragging_scroll then
                handle_scroll_bar_drag(y)
            elseif State.dragging_queue_item then
                handle_queue_reorder_drag(y)
            elseif State.current_tab == TABS.NOW_PLAYING then
                if y == 13 and x >= 2 and x <= 25 then
                    State.volume = ((x - 2) / 23)
                    State.volume = math.max(0.0, math.min(1.0, State.volume))
                    redraw()
                end
            end
        elseif event == "mouse_up" then
            State.dragging_scroll = false
            State.dragging_queue_item = false
        elseif event == "mouse_scroll" then
            if State.current_tab == TABS.SEARCH then
                if param1 == 1 then
                    handle_list_scroll("down", "search")
                else
                    handle_list_scroll("up", "search")
                end
            elseif State.current_tab == TABS.QUEUE then
                if param1 == 1 then
                    handle_list_scroll("down", "queue")
                else
                    handle_list_scroll("up", "queue")
                end
            elseif State.current_tab == TABS.HISTORY then
                if param1 == 1 then
                    handle_list_scroll("down", "history")
                else
                    handle_list_scroll("up", "history")
                end
            elseif State.current_tab == TABS.FAVORITES then
                if param1 == 1 then
                    handle_list_scroll("down", "favorites")
                else
                    handle_list_scroll("up", "favorites")
                end
            elseif State.current_tab == TABS.SETTINGS then
                if param1 == 1 then
                    handle_list_scroll("down", "settings")
                else
                    handle_list_scroll("up", "settings")
                end
            end
        elseif event == "char" and State.waiting_input then
            handle_search_input(param1, nil)
        elseif event == "key" then
            if State.waiting_input then
                handle_search_input(nil, param1)
            elseif param1 == keys.space and State.current_tab == TABS.NOW_PLAYING then
                handle_now_playing_click(2, 17)
            elseif param1 == keys.tab then
                State.current_tab = (State.current_tab % 6) + 1
                redraw()
            elseif param1 == keys.up or param1 == keys.down or param1 == keys.enter or param1 == keys.delete then
                handle_keyboard_navigation(param1)
            elseif param1 == keys.pageUp then
                if State.current_tab == TABS.SEARCH then
                    for i = 1, 5 do handle_list_scroll("up", "search") end
                elseif State.current_tab == TABS.QUEUE then
                    for i = 1, 5 do handle_list_scroll("up", "queue") end
                elseif State.current_tab == TABS.HISTORY then
                    for i = 1, 5 do handle_list_scroll("up", "history") end
                elseif State.current_tab == TABS.FAVORITES then
                    for i = 1, 5 do handle_list_scroll("up", "favorites") end
                end
            elseif param1 == keys.pageDown then
                if State.current_tab == TABS.SEARCH then
                    for i = 1, 5 do handle_list_scroll("down", "search") end
                elseif State.current_tab == TABS.QUEUE then
                    for i = 1, 5 do handle_list_scroll("down", "queue") end
                elseif State.current_tab == TABS.HISTORY then
                    for i = 1, 5 do handle_list_scroll("down", "history") end
                elseif State.current_tab == TABS.FAVORITES then
                    for i = 1, 5 do handle_list_scroll("down", "favorites") end
                end
            end
        elseif event == "stream_ended" then
            if State.settings.auto_play_next then
                play_next_song()
            else
                State.is_playing = false
                set_status("Playback ended", colors.white, 3)
                redraw()
            end
        elseif event == "timer" then
            if param1 == State.status_timer then
                State.status_message = nil
                State.status_timer = nil
                redraw()
            end
        elseif event == "playback_update" then
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
    print("CC Music Player v3.0")
    print("Loading saved state...")

    load_state()

    print("Initializing...")
    sleep(0.5)

    parallel.waitForAny(ui_loop, audio_loop, http_loop, update_loop)
end

-- Start the application
main()
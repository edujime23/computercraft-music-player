local config = require("/music/config")
local State = require("/music/state")
local theme = require("/music/theme")
local utils = require("/music/utils")
local storage = require("/music/storage")

-- Forward declarations for modules to avoid circular dependencies
local audio, network, player

-- Store scroll bar info for click detection
local scroll_infos = {}

-- Helper functions
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

local function show_notification(message, duration)
    if State.settings.notifications then
        State.status_message = "♪ " .. message
        State.status_color = theme.current_colors().status.playing
        if State.status_timer then
            os.cancelTimer(State.status_timer)
        end
        if duration then
            State.status_timer = os.startTimer(duration)
        end
        redraw()
    end
end

-- Utility functions
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
        set_status("Removed from favorites", theme.current_colors().status.error, 2)
    else
        table.insert(State.favorites, 1, song)
        set_status("Added to favorites", theme.current_colors().status.playing, 2)
    end
    storage.save_state()
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

-- POPUP SYSTEM
local function draw_popup(title, content, width, height)
    local w, h = State.screen.width, State.screen.height
    local x = math.floor((w - width) / 2)
    local y = math.floor((h - height) / 2)

    -- Draw background
    paintutils.drawFilledBox(x, y, x + width, y + height, theme.current_colors().popup_bg)

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
    term.setBackgroundColor(theme.current_colors().popup_bg)
    term.setTextColor(theme.current_colors().popup_text)

    local line_y = y + 2
    for line in content:gmatch("[^\n]+") do
        if line_y < y + height then
            term.setCursorPos(x + 2, line_y)
            term.write(utils.truncate(line, width - 3))
            line_y = line_y + 1
        end
    end

    return x, y, width, height
end

local function show_song_info_popup(song)
    if not song then return end

    local info = "Title: " .. (song.title or "Unknown") .. "\n"
    info = info .. "Artist: " .. (song.artist or "Unknown") .. "\n"
    info = info .. "Duration: " .. utils.formatTime(song.duration or 0) .. "\n"
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

-- INTERACTIVE SCROLL BAR
local function draw_scroll_bar(x, start_y, height, total_items, visible_items, scroll_pos, scroll_type)
    if total_items <= visible_items then
        scroll_infos[scroll_type] = nil
        return nil
    end

    local current_colors = theme.current_colors()

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

-- MINI MODE
local function draw_mini_mode()
    term.clear()
    local w, h = State.screen.width, State.screen.height
    local current_colors = theme.current_colors()

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
        term.write(utils.truncate(State.current_song.title or "Unknown", w - 4))

        term.setCursorPos(2, 4)
        term.setTextColor(colors.lightGray)
        term.write(utils.truncate(State.current_song.artist or "Unknown", w - 4))

        -- Progress
        if State.total_duration > 0 then
            term.setCursorPos(2, 6)
            term.setTextColor(colors.white)
            term.write(utils.formatTime(State.playback_position) .. " / " .. utils.formatTime(State.total_duration))
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
        if State.settings.show_visualization and h > 13 and audio then
            audio.draw_visualization(2, 13, w - 3, h - 14)
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
        term.write(utils.truncate(State.status_message, w - 4))
    end
end

-- DRAWING FUNCTIONS
local function draw_vertical_tabs(x, y, width, height)
    local current_colors = theme.current_colors()

    -- Draw background for the tab list
    paintutils.drawFilledBox(x, y, x + width - 1, y + height - 1, current_colors.tabs.inactive_bg)
    term.setCursorPos(x, 1)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write(utils.truncate(" CC Music", width-1))

    local current_y = y + 2
    for i, tab_info in ipairs(config.TAB_DATA) do
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
        term.write(utils.truncate(text, width))
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
        local msg = utils.truncate(State.status_message, math.max(10, width - 25))
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
            term.write("Sleep: " .. utils.formatTime(remaining))
        end
    end

    -- Connection status
    term.setCursorPos(math.max(2, width - 10), h)
    if (State.connection_errors or 0) > 0 then
        term.setTextColor(theme.current_colors().status.error)
        term.write("Conn: Err")
    elseif State.is_streaming then
        term.setTextColor(theme.current_colors().status.playing)
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
        local title = utils.truncate(State.current_song.title or "Unknown", width - 12)
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
        local artist = utils.truncate(State.current_song.artist or "Unknown", width - 4)
        term.write(artist)

        -- Additional metadata
        if State.current_song.duration then
            term.setCursorPos(2, 5)
            term.setTextColor(colors.gray)
            term.write("Duration: " .. utils.formatTime(State.current_song.duration))
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
    local current_colors = theme.current_colors()

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
        if audio then
            audio.update_playback_position()
        end
        term.setCursorPos(2, 9)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        term.write(utils.formatTime(State.playback_position) .. " / " .. utils.formatTime(State.total_duration))

        draw_progress_bar(2, 10, width - 3, State.playback_position / State.total_duration,
                         theme.current_colors().progress.bg, theme.current_colors().progress.fg)
    end
end

local function draw_volume_control(width)
    term.setCursorPos(2, 12)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.write("Volume:")

    local bar_width = math.min(24, width - 10)
    draw_progress_bar(2, 13, bar_width, State.volume, theme.current_colors().progress.bg, theme.current_colors().progress.volume)

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
    local buffer_percent = math.min(100, math.floor((#State.buffer / config.CONFIG.buffer_max) * 100))
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
    if State.settings.show_visualization and h > 22 and audio then
        audio.draw_visualization(2, 21, width - 3, h - 22)
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
                paintutils.drawBox(2, y, width - 2, y + 1, theme.current_colors().selected)
            end

            term.setBackgroundColor(colors.black)
            term.setCursorPos(2, y)
            term.setTextColor(colors.white)

            -- Dragged item
            if State.dragging_queue_item and State.drag_item_index == idx and list_type == "queue" then
                term.setBackgroundColor(colors.blue)
            end

            local title = utils.truncate(item.title or "Unknown Title", width - 15)
            term.write(idx .. ". " .. title)

            -- Favorite indicator
            if item.id and is_favorite(item) then
                term.setTextColor(colors.yellow)
                term.write(" *")
            end

            term.setCursorPos(5, y + 1)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.lightGray)
            local artist = utils.truncate(item.artist or "Unknown Artist", width - 15)
            term.write(artist)

            -- Duration
            if item.duration and width > 30 then
                local dur_str = utils.formatTime(item.duration)
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

    -- Calculate network stats
    local stats = {
        session_active = State.session_id ~= nil,
        buffer_fill = math.floor((#State.buffer / (State.settings.buffer_size or config.CONFIG.buffer_max)) * 100),
        connection_errors = State.connection_errors or 0,
        avg_latency = State.avg_chunk_latency or 0,
        bytes_received = State.total_bytes_received or 0,
        chunks_downloaded = State.downloaded_chunks and #State.downloaded_chunks or 0,
        uptime = (State.session_id and (os.clock() - (State.stream_start_time or os.clock()))) or 0
    }

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
    draw_stat("Bytes Received", utils.formatBytes(stats.bytes_received))
    draw_stat("Chunks Downloaded", stats.chunks_downloaded)
    draw_stat("Session Uptime", utils.formatTime(stats.uptime))

    y = y + 1
    if y < h - 1 then
        term.setCursorPos(2, y)
        term.setTextColor(colors.white)
        term.write("Application Info:")
        y = y + 2
    end

    draw_stat("Version", config.CONFIG.version)
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

    local content_width = State.screen.width - config.TAB_LIST_WIDTH
    term.setBackgroundColor(colors.black)
    term.clear()

    local tab_draw_functions = {
        [config.TABS.NOW_PLAYING] = draw_now_playing,
        [config.TABS.SEARCH]      = draw_search,
        [config.TABS.QUEUE]       = draw_queue,
        [config.TABS.PLAYLISTS]   = draw_playlists,
        [config.TABS.HISTORY]     = draw_history,
        [config.TABS.FAVORITES]   = draw_favorites,
        [config.TABS.SETTINGS]    = draw_settings,
        [config.TABS.DIAGNOSTICS] = draw_diagnostics
    }

    local draw_func = tab_draw_functions[State.current_tab]
    if draw_func then
        draw_func(content_width)
    end

    -- Draw the tab list on the right
    draw_vertical_tabs(content_width + 1, 1, config.TAB_LIST_WIDTH, State.screen.height)

    -- Draw status bar
    draw_status_bar(content_width)

    -- Draw popup if active
    if State.show_popup and State.popup_content then
        local p = State.popup_content
        State.popup_x, State.popup_y, State.popup_w, State.popup_h =
            draw_popup(p.title, p.content, p.width, p.height)
    end
end

-- CLICK HANDLERS
local function add_to_queue(song)
    if player then
        player.add_to_queue(song)
    else
        table.insert(State.queue, song)
        set_status("Added to queue", theme.current_colors().status.playing, 2)
        storage.save_state()
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
        return
    end

    -- Control buttons
    if y == 17 then
        if x >= 2 and x <= 8 then -- Play/Pause
            if State.is_playing then
                State.is_playing = false
                State.buffer_size_on_pause = #State.buffer
                if audio then audio.calculate_playback_position() end
            elseif State.current_song and (#State.buffer > 0 or State.ended) then
                State.is_playing = true
                State.buffer_size_on_pause = 0
                os.queueEvent("playback")
            elseif #State.queue > 0 and player then
                player.play_next_song()
            end
        elseif x >= 10 and x <= 15 then -- Skip
            if player then
                if State.settings.auto_play_next or #State.queue > 0 then
                    player.play_next_song()
                else
                    if network then network.stop_current_stream() end
                    State.current_song = nil
                end
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
            if network then network.download_song() end
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
            if audio then audio.calculate_playback_position() end
        elseif State.current_song and (#State.buffer > 0 or State.ended) then
            State.is_playing = true
            State.buffer_size_on_pause = 0
            os.queueEvent("playback")
        elseif #State.queue > 0 and player then
            player.play_next_song()
        end
    elseif y == 9 and x >= 10 and x <= 15 then -- Next
        if player then player.play_next_song() end
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

-- Continue with more click handlers...
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
                set_status("Removed from queue", theme.current_colors().status.error, 2)
                storage.save_state()
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
            if list_type == "queue" and player then
                for i = 1, idx - 1 do
                    table.remove(State.queue, 1)
                end
                player.play_next_song()
            elseif network then
                network.start_stream(item.id, item)
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
        -- Handle scroll bar click (simplified)
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
        return
    end

    -- Clear button
    if y == 2 and x >= width - 28 and x <= width - 22 then
        State.queue = {}
        State.queue_scroll = 0
        set_status("Queue cleared", colors.white, 2)
        storage.save_state()
        return
    end

    -- Shuffle button
    if y == 2 and x >= width - 20 and x <= width - 11 then
        if #State.queue > 0 then
            State.queue = utils.shuffle(State.queue)
            set_status("Queue shuffled", colors.white, 2)
            storage.save_state()
        end
        return
    end

    -- Save button
    if y == 2 and x >= width - 10 and x <= width - 5 then
        storage.save_state()
        set_status("Queue saved", theme.current_colors().status.playing, 2)
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
                if player then player.play_next_song() end
                set_status("Playing playlist: " .. name, theme.current_colors().status.playing, 2)
                return
            end
            -- View button
            if x >= btn_x_play + 7 and x < btn_x_play + 13 then
                State.selected_playlist = name
                State.current_tab = config.TABS.QUEUE
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
                storage.save_state()
                set_status("Deleted playlist: " .. name, theme.current_colors().status.error, 2)
                redraw()
                return
            end
        end
        y_pos = y_pos + 2
    end
end

local function handle_history_click(x, y, width)
    -- Clear button
    if y == 2 and x >= width - 10 and x <= width - 4 and #State.history > 0 then
        State.history = {}
        State.history_scroll = 0
        set_status("History cleared", colors.white, 2)
        storage.save_state()
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
    -- Clear button
    if y == 2 and x >= width - 10 and x <= width - 4 and #State.favorites > 0 then
        State.favorites = {}
        State.favorites_scroll = 0
        set_status("Favorites cleared", colors.white, 2)
        storage.save_state()
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
    -- Save All button
    if y == 2 and x >= width - 12 and x <= width - 3 then
        config.CONFIG.api_base_url = State.settings.api_url
        config.CONFIG.buffer_max = State.settings.buffer_size
        config.CONFIG.audio_sample_rate = State.settings.sample_rate
        config.CONFIG.audio_chunk_size = State.settings.chunk_size
        State.samples_per_chunk = State.settings.chunk_size
        State.sample_rate = State.settings.sample_rate
        theme.apply_theme(State.settings.theme, State)

        storage.save_state()
        set_status("Settings saved", theme.current_colors().status.playing, 2)
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
            theme.apply_theme(State.settings.theme, State)
            set_status("Applied theme: " .. State.settings.theme, colors.white, 2)
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
        if network then
            network.check_for_updates()
            set_status("Checking for updates...", colors.yellow, 2)
        end
    end
end

-- Initialize module dependencies
local function init_dependencies()
    if not audio then
        local success, audio_module = pcall(require, "/music/audio")
        if success then
            audio = audio_module
        end
    end

    if not network then
        local success, network_module = pcall(require, "/music/network")
        if success then
            network = network_module
        end
    end

    if not player then
        local success, player_module = pcall(require, "/music/player")
        if success then
            player = player_module
        end
    end
end

-- Initialize dependencies when module loads
init_dependencies()

return {
    redraw = redraw,
    draw_mini_mode = draw_mini_mode,
    show_song_info_popup = show_song_info_popup,
    show_help_popup = show_help_popup,
    handle_popup_click = handle_popup_click,
    handle_now_playing_click = handle_now_playing_click,
    handle_mini_mode_click = handle_mini_mode_click,
    handle_search_click = handle_search_click,
    handle_queue_click = handle_queue_click,
    handle_playlists_click = handle_playlists_click,
    handle_history_click = handle_history_click,
    handle_favorites_click = handle_favorites_click,
    handle_settings_click = handle_settings_click,
    handle_diagnostics_click = handle_diagnostics_click,
    set_status = set_status,
    show_notification = show_notification,
    toggle_favorite = toggle_favorite,
    is_favorite = is_favorite,
    filter_list = filter_list,
    draw_progress_bar = draw_progress_bar
}
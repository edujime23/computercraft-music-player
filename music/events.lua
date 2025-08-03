local config = require("/music/config")
local State = require("/music/state")
local theme = require("/music/theme")
local utils = require("/music/utils")
local storage = require("/music/storage")

-- Forward declarations for modules that will be loaded later to avoid circular dependencies
local ui, audio, network, player

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

    if ui then ui.redraw() end
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
        if ui then ui.redraw() end
    end
end

-- List filtering
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

-- Scroll handling
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
            if ui then ui.redraw() end
        end
    elseif direction == "down" then
        if State[scroll_var] < max_scroll then
            State[scroll_var] = State[scroll_var] + 1
            State.selected_index[State.current_tab] = math.min(#list, State.selected_index[State.current_tab] + 1)
            if ui then ui.redraw() end
        end
    end
end

-- Input handling
local function handle_input(char, key)
    if not State.waiting_input then return end

    if char then
        State.input_text = State.input_text .. char
        if State.editing_playlist then State.playlist_input = State.input_text end
        if ui then ui.redraw() end
        return
    end
    if not key then return end

    if key == keys.enter then
        State.waiting_input = false
        term.setCursorBlink(false)
        local context = State.input_context

        if context == "main_search" then
            State.last_query = State.input_text
            if State.last_query ~= "" and network then
                State.last_search_url = State.settings.api_url .. "/?search=" .. textutils.urlEncode(State.last_query)
                State.search_results = nil
                State.search_error = nil
                set_status("Searching...", theme.current_colors().status.loading)
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
             if State.playlist_input ~= "" and player then
                player.create_playlist(State.playlist_input)
                if context == "playlist_save_queue" and #State.queue > 0 then
                    local songs_copy = {}
                    for _, s in ipairs(State.queue) do table.insert(songs_copy, s) end
                    State.playlists[State.playlist_input].songs = songs_copy
                    storage.save_state()
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
        if ui then ui.redraw() end

    elseif key == keys.backspace and #State.input_text > 0 then
        State.input_text = string.sub(State.input_text, 1, #State.input_text - 1)
        if State.editing_playlist then State.playlist_input = State.input_text end
        if ui then ui.redraw() end
    elseif key == keys.escape then
        State.waiting_input = false
        State.input_text = ""
        State.input_context = nil
        State.editing_setting = nil
        State.editing_playlist = false
        term.setCursorBlink(false)
        if ui then ui.redraw() end
    end
end

-- Keyboard navigation
local function handle_keyboard_navigation(key)
    State.keyboard_nav_active = true

    if key == keys.up then
        if State.current_tab == config.TABS.SEARCH then
            State.selected_index[config.TABS.SEARCH] = math.max(1, State.selected_index[config.TABS.SEARCH] - 1)
            if State.selected_index[config.TABS.SEARCH] <= State.search_scroll then
                handle_list_scroll("up", "search")
            end
        elseif State.current_tab == config.TABS.QUEUE then
            State.selected_index[config.TABS.QUEUE] = math.max(1, State.selected_index[config.TABS.QUEUE] - 1)
            if State.selected_index[config.TABS.QUEUE] <= State.queue_scroll then
                handle_list_scroll("up", "queue")
            end
        elseif State.current_tab == config.TABS.HISTORY then
            State.selected_index[config.TABS.HISTORY] = math.max(1, State.selected_index[config.TABS.HISTORY] - 1)
            if State.selected_index[config.TABS.HISTORY] <= State.history_scroll then
                handle_list_scroll("up", "history")
            end
        elseif State.current_tab == config.TABS.FAVORITES then
            State.selected_index[config.TABS.FAVORITES] = math.max(1, State.selected_index[config.TABS.FAVORITES] - 1)
            if State.selected_index[config.TABS.FAVORITES] <= State.favorites_scroll then
                handle_list_scroll("up", "favorites")
            end
        end
    elseif key == keys.down then
        if State.current_tab == config.TABS.SEARCH and State.search_results then
            State.selected_index[config.TABS.SEARCH] = math.min(#State.search_results, State.selected_index[config.TABS.SEARCH] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 8) / 2)
            if State.selected_index[config.TABS.SEARCH] > State.search_scroll + items_per_page then
                handle_list_scroll("down", "search")
            end
        elseif State.current_tab == config.TABS.QUEUE then
            State.selected_index[config.TABS.QUEUE] = math.min(#State.queue, State.selected_index[config.TABS.QUEUE] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 2)
            if State.selected_index[config.TABS.QUEUE] > State.queue_scroll + items_per_page then
                handle_list_scroll("down", "queue")
            end
        elseif State.current_tab == config.TABS.HISTORY then
            State.selected_index[config.TABS.HISTORY] = math.min(#State.history, State.selected_index[config.TABS.HISTORY] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 2)
            if State.selected_index[config.TABS.HISTORY] > State.history_scroll + items_per_page then
                handle_list_scroll("down", "history")
            end
        elseif State.current_tab == config.TABS.FAVORITES then
            State.selected_index[config.TABS.FAVORITES] = math.min(#State.favorites, State.selected_index[config.TABS.FAVORITES] + 1)
            local h = State.screen.height
            local items_per_page = math.floor((h - 5) / 2)
            if State.selected_index[config.TABS.FAVORITES] > State.favorites_scroll + items_per_page then
                handle_list_scroll("down", "favorites")
            end
        end
    elseif key == keys.enter then
        -- Activate selected item
        if State.current_tab == config.TABS.SEARCH and State.search_results and player then
            local song = State.search_results[State.selected_index[config.TABS.SEARCH]]
            if song then player.add_to_queue(song) end
        elseif State.current_tab == config.TABS.QUEUE and #State.queue > 0 and player then
            for i = 1, State.selected_index[config.TABS.QUEUE] - 1 do
                table.remove(State.queue, 1)
            end
            player.play_next_song()
        elseif State.current_tab == config.TABS.HISTORY and #State.history > 0 and player then
            local song = State.history[State.selected_index[config.TABS.HISTORY]]
            if song then player.add_to_queue(song) end
        elseif State.current_tab == config.TABS.FAVORITES and #State.favorites > 0 and player then
            local song = State.favorites[State.selected_index[config.TABS.FAVORITES]]
            if song then player.add_to_queue(song) end
        end
    elseif key == keys.delete then
        -- Remove selected item
        if State.current_tab == config.TABS.QUEUE and #State.queue > 0 then
            table.remove(State.queue, State.selected_index[config.TABS.QUEUE])
            State.selected_index[config.TABS.QUEUE] = math.min(State.selected_index[config.TABS.QUEUE], #State.queue)
            State.selected_index[config.TABS.QUEUE] = math.max(1, State.selected_index[config.TABS.QUEUE])
            storage.save_state()
        end
    end

    if ui then ui.redraw() end
end

-- Main UI event loop
local function ui_loop()
    while true do
        local event, param1, x, y = os.pullEvent()

        if event == "mouse_click" then
            State.dragging_scroll = false
            State.dragging_queue_item = false
            State.keyboard_nav_active = false

            -- Handle popup first
            if State.show_popup and ui and ui.handle_popup_click and ui.handle_popup_click(x, y) then
                -- Click was on popup, do nothing else
            elseif State.mini_mode then
                if ui and ui.handle_mini_mode_click then
                    ui.handle_mini_mode_click(x, y)
                end
            else
                local content_width = State.screen.width - config.TAB_LIST_WIDTH
                if x > content_width then
                    -- Click is in the tab list
                    local tab_y_start = 3
                    local tab_height = 2
                    local clicked_index = math.floor((y - tab_y_start) / tab_height) + 1
                    if clicked_index >= 1 and clicked_index <= #config.TAB_DATA then
                        State.current_tab = config.TAB_DATA[clicked_index].id
                        if ui then ui.redraw() end
                    end
                else
                    -- Click is in the content area
                    if ui then
                        local click_handlers = {
                            [config.TABS.NOW_PLAYING] = ui.handle_now_playing_click,
                            [config.TABS.SEARCH]      = ui.handle_search_click,
                            [config.TABS.QUEUE]       = ui.handle_queue_click,
                            [config.TABS.PLAYLISTS]   = ui.handle_playlists_click,
                            [config.TABS.HISTORY]     = ui.handle_history_click,
                            [config.TABS.FAVORITES]   = ui.handle_favorites_click,
                            [config.TABS.SETTINGS]    = ui.handle_settings_click,
                            [config.TABS.DIAGNOSTICS] = ui.handle_diagnostics_click
                        }
                        local handler = click_handlers[State.current_tab]
                        if handler then
                            handler(x, y, content_width)
                        end
                    end
                end
            end
        elseif event == "mouse_drag" then
            if ui then
                if State.dragging_scroll and ui.handle_scroll_bar_drag then
                    ui.handle_scroll_bar_drag(y)
                elseif State.dragging_queue_item and ui.handle_queue_reorder_drag then
                    ui.handle_queue_reorder_drag(y)
                elseif (State.current_tab == config.TABS.NOW_PLAYING and y == 13 and x >= 2 and x <= 25) or
                       (State.mini_mode and y == 11 and x >= 7 and x <= 21) then
                    State.volume = State.mini_mode and ((x - 7) / 14) or ((x - 2) / 23)
                    State.volume = math.max(0.0, math.min(1.0, State.volume))
                    ui.redraw()
                end
            end
        elseif event == "mouse_up" then
            State.dragging_scroll = false
            State.dragging_queue_item = false
        elseif event == "mouse_scroll" then
            local scroll_map = {
                [config.TABS.SEARCH] = "search", [config.TABS.QUEUE] = "queue", [config.TABS.PLAYLISTS] = "playlists",
                [config.TABS.HISTORY] = "history", [config.TABS.FAVORITES] = "favorites", [config.TABS.SETTINGS] = "settings"
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
                    if ui then ui.redraw() end
                end
            elseif param1 == keys.escape then
                if State.mini_mode then
                    State.mini_mode = false
                    if ui then ui.redraw() end
                end
            -- HOTKEYS
            elseif param1 == config.HOTKEYS.play_pause then
                if ui then
                    if State.mini_mode and ui.handle_mini_mode_click then
                        ui.handle_mini_mode_click(2, 9)
                    elseif ui.handle_now_playing_click then
                        ui.handle_now_playing_click(2, 17, State.screen.width - config.TAB_LIST_WIDTH)
                    end
                end
            elseif param1 == config.HOTKEYS.next then
                if player then player.play_next_song() end
            elseif param1 == config.HOTKEYS.volume_up then
                State.volume = math.min(1.0, State.volume + 0.1)
                set_status("Volume: " .. math.floor(State.volume * 100) .. "%", colors.white, 1)
            elseif param1 == config.HOTKEYS.volume_down then
                State.volume = math.max(0.0, State.volume - 0.1)
                set_status("Volume: " .. math.floor(State.volume * 100) .. "%", colors.white, 1)
            elseif param1 == config.HOTKEYS.favorite and State.current_song and player then
                player.toggle_favorite(State.current_song)
            elseif param1 == config.HOTKEYS.mini_mode then
                State.mini_mode = not State.mini_mode
                if ui then ui.redraw() end
            elseif param1 == config.HOTKEYS.search then
                State.current_tab = config.TABS.SEARCH
                if ui then ui.redraw() end
            elseif param1 == config.HOTKEYS.queue then
                State.current_tab = config.TABS.QUEUE
                if ui then ui.redraw() end
            elseif param1 == config.HOTKEYS.help then
                if ui and ui.show_help_popup then ui.show_help_popup() end
            elseif param1 == keys.space and State.current_tab == config.TABS.NOW_PLAYING then
                if ui and ui.handle_now_playing_click then
                    ui.handle_now_playing_click(2, 17, State.screen.width - config.TAB_LIST_WIDTH)
                end
            elseif param1 == keys.tab then
                State.current_tab = (State.current_tab % #config.TAB_DATA) + 1
                if ui then ui.redraw() end
            elseif param1 == keys.up or param1 == keys.down or param1 == keys.enter or param1 == keys.delete then
                handle_keyboard_navigation(param1)
            elseif param1 == keys.pageUp then
                local tab_map = {
                    [config.TABS.SEARCH] = "search", [config.TABS.QUEUE] = "queue",
                    [config.TABS.HISTORY] = "history", [config.TABS.FAVORITES] = "favorites"
                }
                if tab_map[State.current_tab] then
                    for i = 1, 5 do handle_list_scroll("up", tab_map[State.current_tab]) end
                end
            elseif param1 == keys.pageDown then
                local tab_map = {
                    [config.TABS.SEARCH] = "search", [config.TABS.QUEUE] = "queue",
                    [config.TABS.HISTORY] = "history", [config.TABS.FAVORITES] = "favorites"
                }
                if tab_map[State.current_tab] then
                    for i = 1, 5 do handle_list_scroll("down", tab_map[State.current_tab]) end
                end
            end
        elseif event == "stream_ended" then
            if State.settings.auto_play_next and player then
                player.play_next_song()
            else
                State.is_playing = false
                set_status("Playback ended", colors.white, 3)
                show_notification("Playback ended", 3)
            end
        elseif event == "sleep_timer_expired" then
            set_status("Sleep timer expired", colors.white, 3)
            show_notification("Sleep timer expired - playback stopped", 5)
        elseif event == "timer" then
            if param1 == State.status_timer then
                State.status_message = nil
                State.status_timer = nil
                if ui then ui.redraw() end
            end
        elseif event == "playback_update" then
            if audio then audio.update_sleep_timer() end
            if ui then ui.redraw() end
        elseif event == "request_chunk" then
            if network then network.request_chunk() end
        end
    end
end

-- HTTP event loop
local function http_loop()
    while true do
        local event, url, handle = os.pullEvent()
        if event == "http_success" then
            if network then network.handle_http_success(url, handle) end
        elseif event == "http_failure" then
            if network then network.handle_http_failure(url, handle) end
        end
    end
end

-- Update loop
local function update_loop()
    while true do
        sleep(config.CONFIG.update_interval)
        if State.is_playing then
            os.queueEvent("playback_update")
        end
    end
end

-- Main run function
local function run()
    -- Load modules after they are available to avoid circular dependencies
    ui = require("/music/ui")
    audio = require("/music/audio")
    network = require("/music/network")
    player = require("/music/player")

    parallel.waitForAny(ui_loop, audio.audio_loop, http_loop, update_loop)
end

return {
    run = run,
    ui_loop = ui_loop,
    http_loop = http_loop,
    update_loop = update_loop,
    handle_input = handle_input,
    handle_keyboard_navigation = handle_keyboard_navigation,
    handle_list_scroll = handle_list_scroll,
    set_status = set_status,
    show_notification = show_notification,
    filter_list = filter_list
}
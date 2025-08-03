local config = require("/music/config")
local State = require("/music/state")
local theme = require("/music/theme")
local utils = require("/music/utils")
local storage = require("/music/storage")

-- Forward declarations for modules to avoid circular dependencies
local network, ui

-- Helper functions for status and notifications
local function set_status(message, color, duration)
    State.status_message = message
    State.status_color = color or colors.white

    if State.status_timer then
        os.cancelTimer(State.status_timer)
    end

    if duration then
        State.status_timer = os.startTimer(duration)
    end
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
    end
end

-- FAVORITES MANAGEMENT
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
        show_notification("Removed from favorites", 2)
    else
        table.insert(State.favorites, 1, song)
        set_status("Added to favorites", theme.current_colors().status.playing, 2)
        show_notification("Added to favorites", 2)
    end
    storage.save_state()

    -- Trigger UI redraw if available
    if ui and ui.redraw then
        ui.redraw()
    end
end

-- QUEUE MANAGEMENT
local function add_to_queue(song)
    if not song then return end

    table.insert(State.queue, song)
    set_status("Added to queue", theme.current_colors().status.playing, 2)
    show_notification("Added: " .. (song.title or "Unknown"), 2)

    -- If no song is currently playing, start playing
    if not State.current_song and not State.is_playing then
        play_next_song()
    end

    storage.save_state()

    -- Trigger UI redraw if available
    if ui and ui.redraw then
        ui.redraw()
    end
end

local function remove_from_queue(index)
    if index >= 1 and index <= #State.queue then
        local removed_song = table.remove(State.queue, index)
        set_status("Removed from queue", theme.current_colors().status.error, 2)
        storage.save_state()

        -- Trigger UI redraw if available
        if ui and ui.redraw then
            ui.redraw()
        end

        return removed_song
    end
    return nil
end

local function clear_queue()
    State.queue = {}
    State.queue_scroll = 0
    set_status("Queue cleared", colors.white, 2)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end
end

local function shuffle_queue()
    if #State.queue > 0 then
        State.queue = utils.shuffle(State.queue)
        set_status("Queue shuffled", colors.white, 2)
        storage.save_state()

        if ui and ui.redraw then
            ui.redraw()
        end
    end
end

-- PLAYBACK CONTROL
local function play_next_song()
    local next_song = nil

    -- Handle repeat modes
    if State.repeat_mode == config.REPEAT_MODES.ONE and State.current_song then
        next_song = State.current_song
    elseif #State.queue > 0 then
        if State.shuffle and State.repeat_mode ~= config.REPEAT_MODES.ONE then
            local idx = math.random(1, #State.queue)
            next_song = table.remove(State.queue, idx)
        else
            next_song = table.remove(State.queue, 1)
            State.queue_scroll = math.max(0, State.queue_scroll - 1)
        end

        -- Handle repeat all mode
        if State.repeat_mode == config.REPEAT_MODES.ALL then
            table.insert(State.queue, next_song)
        end
    elseif State.repeat_mode == config.REPEAT_MODES.ALL and #State.history > 0 then
        -- Restart from history
        State.queue = State.shuffle and utils.shuffle(State.history) or {}
        for _, song in ipairs(State.history) do
            table.insert(State.queue, song)
        end
        State.history = {}
        return play_next_song() -- Recursive call to get next song
    end

    if next_song then
        -- Add current song to history (unless it's repeat one mode)
        if State.current_song and State.repeat_mode ~= config.REPEAT_MODES.ONE then
            table.insert(State.history, 1, State.current_song)
            -- Limit history to 50 songs
            if #State.history > 50 then
                table.remove(State.history)
            end
        end

        -- Start streaming the next song
        if network and network.start_stream then
            network.start_stream(next_song.id, next_song)
        else
            -- Fallback if network module not available
            State.current_song = next_song
            show_notification("Now playing: " .. (next_song.title or "Unknown"), 3)
        end

        storage.save_state()
    else
        -- No more songs to play
        State.current_song = nil
        State.is_playing = false

        -- Reset playback timing
        State.playback_position = 0
        State.chunks_played = 0
        State.buffer_size_on_pause = 0
        State.downloaded_chunks = {}

        set_status("Playback queue empty", colors.white, 3)
        show_notification("Queue is empty", 3)
    end

    if ui and ui.redraw then
        ui.redraw()
    end
end

local function play_previous_song()
    if #State.history > 0 then
        -- Move current song back to front of queue
        if State.current_song then
            table.insert(State.queue, 1, State.current_song)
        end

        -- Get previous song from history
        local prev_song = table.remove(State.history, 1)

        if network and network.start_stream then
            network.start_stream(prev_song.id, prev_song)
        else
            State.current_song = prev_song
            show_notification("Playing previous: " .. (prev_song.title or "Unknown"), 3)
        end

        storage.save_state()

        if ui and ui.redraw then
            ui.redraw()
        end
    else
        set_status("No previous song", colors.white, 2)
    end
end

local function toggle_play_pause()
    if State.is_playing then
        State.is_playing = false
        State.buffer_size_on_pause = #State.buffer
        set_status("Paused", theme.current_colors().status.paused, 2)
    elseif State.current_song and (#State.buffer > 0 or State.ended) then
        State.is_playing = true
        State.buffer_size_on_pause = 0
        os.queueEvent("playback")
        set_status("Playing", theme.current_colors().status.playing, 2)
    elseif #State.queue > 0 then
        play_next_song()
    else
        set_status("No songs to play", colors.white, 2)
    end

    if ui and ui.redraw then
        ui.redraw()
    end
end

local function stop_playback()
    if network and network.stop_current_stream then
        network.stop_current_stream()
    else
        State.is_playing = false
        State.is_streaming = false
        State.buffer = {}
        State.playback_position = 0
        State.chunks_played = 0
        State.buffer_size_on_pause = 0
        State.downloaded_chunks = {}
    end

    State.current_song = nil
    set_status("Stopped", colors.white, 2)

    if ui and ui.redraw then
        ui.redraw()
    end
end

-- REPEAT AND SHUFFLE
local function cycle_repeat_mode()
    State.repeat_mode = (State.repeat_mode + 1) % 3
    local mode_names = {"Off", "One", "All"}
    set_status("Repeat: " .. mode_names[State.repeat_mode + 1], colors.white, 2)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end
end

local function toggle_shuffle()
    State.shuffle = not State.shuffle
    set_status("Shuffle: " .. (State.shuffle and "On" or "Off"), colors.white, 2)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end
end

-- PLAYLIST MANAGEMENT
local function create_playlist(name)
    if not name or name == "" then
        set_status("Invalid playlist name", theme.current_colors().status.error, 2)
        return false
    end

    if State.playlists[name] then
        set_status("Playlist already exists", theme.current_colors().status.error, 2)
        return false
    end

    State.playlists[name] = {
        name = name,
        songs = {},
        created = os.time(),
        modified = os.time()
    }

    storage.save_state()
    set_status("Created playlist: " .. name, theme.current_colors().status.playing, 2)
    show_notification("Created playlist: " .. name, 2)

    if ui and ui.redraw then
        ui.redraw()
    end

    return true
end

local function delete_playlist(name)
    if State.playlists[name] then
        State.playlists[name] = nil
        storage.save_state()
        set_status("Deleted playlist: " .. name, theme.current_colors().status.error, 2)

        if ui and ui.redraw then
            ui.redraw()
        end

        return true
    end
    return false
end

local function add_song_to_playlist(playlist_name, song)
    if not State.playlists[playlist_name] or not song then
        return false
    end

    -- Check if song already exists in playlist
    for _, existing_song in ipairs(State.playlists[playlist_name].songs) do
        if existing_song.id == song.id then
            set_status("Song already in playlist", colors.yellow, 2)
            return false
        end
    end

    table.insert(State.playlists[playlist_name].songs, song)
    State.playlists[playlist_name].modified = os.time()
    storage.save_state()

    set_status("Added to " .. playlist_name, theme.current_colors().status.playing, 2)
    return true
end

local function remove_song_from_playlist(playlist_name, song_index)
    if not State.playlists[playlist_name] or not State.playlists[playlist_name].songs[song_index] then
        return false
    end

    local removed_song = table.remove(State.playlists[playlist_name].songs, song_index)
    State.playlists[playlist_name].modified = os.time()
    storage.save_state()

    set_status("Removed from " .. playlist_name, theme.current_colors().status.error, 2)
    return removed_song
end

local function load_playlist_to_queue(playlist_name, replace_queue)
    if not State.playlists[playlist_name] then
        set_status("Playlist not found", theme.current_colors().status.error, 2)
        return false
    end

    if replace_queue then
        State.queue = {}
    end

    for _, song in ipairs(State.playlists[playlist_name].songs) do
        table.insert(State.queue, song)
    end

    storage.save_state()
    set_status("Loaded playlist: " .. playlist_name, colors.white, 2)

    if ui and ui.redraw then
        ui.redraw()
    end

    return true
end

local function play_playlist(playlist_name)
    if load_playlist_to_queue(playlist_name, true) then
        play_next_song()
        set_status("Playing playlist: " .. playlist_name, theme.current_colors().status.playing, 2)
        show_notification("Playing playlist: " .. playlist_name, 3)
        return true
    end
    return false
end

local function save_queue_as_playlist(playlist_name)
    if not playlist_name or playlist_name == "" then
        set_status("Invalid playlist name", theme.current_colors().status.error, 2)
        return false
    end

    if #State.queue == 0 then
        set_status("Queue is empty", theme.current_colors().status.error, 2)
        return false
    end

    -- Create playlist if it doesn't exist
    if not State.playlists[playlist_name] then
        create_playlist(playlist_name)
    end

    -- Copy queue to playlist
    State.playlists[playlist_name].songs = {}
    for _, song in ipairs(State.queue) do
        table.insert(State.playlists[playlist_name].songs, song)
    end

    State.playlists[playlist_name].modified = os.time()
    storage.save_state()

    set_status("Saved queue as: " .. playlist_name, theme.current_colors().status.playing, 2)
    show_notification("Saved queue as: " .. playlist_name, 3)

    if ui and ui.redraw then
        ui.redraw()
    end

    return true
end

-- HISTORY MANAGEMENT
local function clear_history()
    State.history = {}
    State.history_scroll = 0
    set_status("History cleared", colors.white, 2)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end
end

local function clear_favorites()
    State.favorites = {}
    State.favorites_scroll = 0
    set_status("Favorites cleared", colors.white, 2)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end
end

-- VOLUME CONTROL
local function adjust_volume(delta)
    State.volume = utils.clamp(State.volume + delta, 0.0, 1.0)
    local percentage = math.floor(State.volume * 100)
    set_status("Volume: " .. percentage .. "%", colors.white, 1)

    if ui and ui.redraw then
        ui.redraw()
    end
end

local function set_volume(volume)
    State.volume = utils.clamp(volume, 0.0, 1.0)
    local percentage = math.floor(State.volume * 100)
    set_status("Volume: " .. percentage .. "%", colors.white, 1)

    if ui and ui.redraw then
        ui.redraw()
    end
end

-- SLEEP TIMER
local function start_sleep_timer(minutes)
    if not minutes or minutes <= 0 then
        set_status("Invalid sleep timer duration", theme.current_colors().status.error, 2)
        return false
    end

    State.settings.sleep_timer = minutes
    State.settings.sleep_timer_active = true
    State.sleep_timer_start = os.clock()

    set_status("Sleep timer started: " .. minutes .. " minutes", colors.white, 2)
    show_notification("Sleep timer: " .. minutes .. " minutes", 3)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end

    return true
end

local function stop_sleep_timer()
    State.settings.sleep_timer_active = false
    State.sleep_timer_start = nil

    set_status("Sleep timer stopped", colors.white, 2)
    storage.save_state()

    if ui and ui.redraw then
        ui.redraw()
    end
end

-- SEARCH AND FILTER HELPERS
local function search_in_queue(query)
    if not query or query == "" then
        return State.queue
    end

    local results = {}
    local query_lower = string.lower(query)

    for _, song in ipairs(State.queue) do
        local title_lower = string.lower(song.title or "")
        local artist_lower = string.lower(song.artist or "")

        if string.find(title_lower, query_lower, 1, true) or
           string.find(artist_lower, query_lower, 1, true) then
            table.insert(results, song)
        end
    end

    return results
end

local function search_in_history(query)
    if not query or query == "" then
        return State.history
    end

    local results = {}
    local query_lower = string.lower(query)

    for _, song in ipairs(State.history) do
        local title_lower = string.lower(song.title or "")
        local artist_lower = string.lower(song.artist or "")

        if string.find(title_lower, query_lower, 1, true) or
           string.find(artist_lower, query_lower, 1, true) then
            table.insert(results, song)
        end
    end

    return results
end

local function search_in_favorites(query)
    if not query or query == "" then
        return State.favorites
    end

    local results = {}
    local query_lower = string.lower(query)

    for _, song in ipairs(State.favorites) do
        local title_lower = string.lower(song.title or "")
        local artist_lower = string.lower(song.artist or "")

        if string.find(title_lower, query_lower, 1, true) or
           string.find(artist_lower, query_lower, 1, true) then
            table.insert(results, song)
        end
    end

    return results
end

-- UTILITY FUNCTIONS
local function get_current_song_info()
    if not State.current_song then
        return nil
    end

    return {
        title = State.current_song.title or "Unknown",
        artist = State.current_song.artist or "Unknown",
        duration = State.current_song.duration or 0,
        position = State.playback_position or 0,
        is_playing = State.is_playing,
        is_favorite = is_favorite(State.current_song),
        volume = State.volume
    }
end

local function get_queue_info()
    return {
        length = #State.queue,
        shuffle = State.shuffle,
        repeat_mode = State.repeat_mode,
        current_scroll = State.queue_scroll
    }
end

local function get_playback_stats()
    return {
        total_songs_played = #State.history,
        favorite_songs = #State.favorites,
        playlists_count = (function()
            local count = 0
            for _ in pairs(State.playlists) do count = count + 1 end
            return count
        end)(),
        current_session_songs = State.chunks_played and math.floor(State.chunks_played / 100) or 0
    }
end

-- Initialize module dependencies
local function init_dependencies()
    if not network then
        local success, network_module = pcall(require, "/music/network")
        if success then
            network = network_module
        end
    end

    if not ui then
        local success, ui_module = pcall(require, "/music/ui")
        if success then
            ui = ui_module
        end
    end
end

-- Initialize dependencies when module loads
init_dependencies()

return {
    -- Core playback functions
    play_next_song = play_next_song,
    play_previous_song = play_previous_song,
    toggle_play_pause = toggle_play_pause,
    stop_playback = stop_playback,

    -- Queue management
    add_to_queue = add_to_queue,
    remove_from_queue = remove_from_queue,
    clear_queue = clear_queue,
    shuffle_queue = shuffle_queue,

    -- Favorites
    toggle_favorite = toggle_favorite,
    is_favorite = is_favorite,
    find_song_in_favorites = find_song_in_favorites,
    clear_favorites = clear_favorites,

    -- Repeat and shuffle
    cycle_repeat_mode = cycle_repeat_mode,
    toggle_shuffle = toggle_shuffle,

    -- Playlist management
    create_playlist = create_playlist,
    delete_playlist = delete_playlist,
    add_song_to_playlist = add_song_to_playlist,
    remove_song_from_playlist = remove_song_from_playlist,
    load_playlist_to_queue = load_playlist_to_queue,
    play_playlist = play_playlist,
    save_queue_as_playlist = save_queue_as_playlist,

    -- History
    clear_history = clear_history,

    -- Volume control
    adjust_volume = adjust_volume,
    set_volume = set_volume,

    -- Sleep timer
    start_sleep_timer = start_sleep_timer,
    stop_sleep_timer = stop_sleep_timer,

    -- Search and filter
    search_in_queue = search_in_queue,
    search_in_history = search_in_history,
    search_in_favorites = search_in_favorites,

    -- Information functions
    get_current_song_info = get_current_song_info,
    get_queue_info = get_queue_info,
    get_playback_stats = get_playback_stats,

    -- Utility functions
    set_status = set_status,
    show_notification = show_notification
}
local config = require("/music/config")
local theme = require("/music/theme")

local State = {
    -- UI State
    screen = { width = 0, height = 0 },
    current_tab = config.TABS.NOW_PLAYING,
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
        [config.TABS.SEARCH] = 1,
        [config.TABS.QUEUE] = 1,
        [config.TABS.PLAYLISTS] = 1,
        [config.TABS.HISTORY] = 1,
        [config.TABS.FAVORITES] = 1,
        [config.TABS.SETTINGS] = 1,
        [config.TABS.DIAGNOSTICS] = 1
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
    repeat_mode = config.REPEAT_MODES.OFF,
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
    samples_per_chunk = config.CONFIG.audio_chunk_size,
    sample_rate = config.CONFIG.audio_sample_rate,
    buffer_size_on_pause = 0,
    downloaded_chunks = {},

    -- Visualization
    current_chunk_rms = 0,
    visualization_data = {},
    visualization_mode = config.VIS_MODES.BARS,
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
        api_url = config.CONFIG.api_base_url,
        buffer_size = config.CONFIG.buffer_max,
        sample_rate = config.CONFIG.audio_sample_rate,
        chunk_size = config.CONFIG.audio_chunk_size,
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

return State
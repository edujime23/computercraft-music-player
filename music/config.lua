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
    update_check_url = "https://raw.githubusercontent.com/edujime23/computercraft-music-player/refs/heads/main/version.json", -- CHANGED

    -- File paths
    queue_file = "music_queue.dat",
    history_file = "music_history.dat",
    favorites_file = "music_favorites.dat",
    settings_file = "music_settings.dat",
    playlists_file = "music_playlists.dat",
    themes_file = "music_themes.dat",
    profiles_file = "music_profiles.dat",

    -- UPDATER CONFIGURATION
    repo_url = "https://raw.githubusercontent.com/edujime23/computercraft-music-player/main",
    version_url = "https://raw.githubusercontent.com/edujime23/computercraft-music-player/main/version.json", -- CHANGED
    backup_folder = "music_backup",
    temp_folder = "music_temp",
    current_version = "5.0"
}

-- Make current_version point to version
CONFIG.current_version = CONFIG.version

-- Rest of the file stays the same...
local REPEAT_MODES = { OFF = 0, ONE = 1, ALL = 2 }
local TABS = { NOW_PLAYING = 1, SEARCH = 2, QUEUE = 3, PLAYLISTS = 4, HISTORY = 5, FAVORITES = 6, SETTINGS = 7, DIAGNOSTICS = 8 }
local VIS_MODES = { BARS = 1, WAVE = 2, SPECTRUM = 3, VU = 4 }

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

return {
    CONFIG = CONFIG,
    REPEAT_MODES = REPEAT_MODES,
    TABS = TABS,
    VIS_MODES = VIS_MODES,
    TAB_LIST_WIDTH = TAB_LIST_WIDTH,
    TAB_DATA = TAB_DATA,
    HOTKEYS = HOTKEYS
}
local config = require("/music/config")
local State = require("/music/state")

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

local function save_state()
    save_table_to_file(State.queue, config.CONFIG.queue_file)
    save_table_to_file(State.history, config.CONFIG.history_file)
    save_table_to_file(State.favorites, config.CONFIG.favorites_file)
    save_table_to_file(State.settings, config.CONFIG.settings_file)
    save_table_to_file(State.playlists, config.CONFIG.playlists_file)
    save_table_to_file(State.profiles, config.CONFIG.profiles_file)
end

local function load_state()
    State.queue = load_table_from_file(config.CONFIG.queue_file) or {}
    State.history = load_table_from_file(config.CONFIG.history_file) or {}
    State.favorites = load_table_from_file(config.CONFIG.favorites_file) or {}
    State.playlists = load_table_from_file(config.CONFIG.playlists_file) or {}
    State.profiles = load_table_from_file(config.CONFIG.profiles_file) or { default = { name = "Default User" } }

    local loaded_settings = load_table_from_file(config.CONFIG.settings_file)
    if loaded_settings then
        local s = State.settings
        s.api_url             = type(loaded_settings.api_url) == "string" and loaded_settings.api_url or config.CONFIG.api_base_url
        s.buffer_size         = tonumber(loaded_settings.buffer_size) or config.CONFIG.buffer_max
        s.sample_rate         = tonumber(loaded_settings.sample_rate) or config.CONFIG.audio_sample_rate
        s.chunk_size          = tonumber(loaded_settings.chunk_size) or config.CONFIG.audio_chunk_size
        s.auto_play_next      = type(loaded_settings.auto_play_next) == "boolean" and loaded_settings.auto_play_next or true
        s.show_visualization  = type(loaded_settings.show_visualization) == "boolean" and loaded_settings.show_visualization or true
        s.theme               = loaded_settings.theme or "default"
        s.sleep_timer         = tonumber(loaded_settings.sleep_timer) or 0
        s.notifications       = type(loaded_settings.notifications) == "boolean" and loaded_settings.notifications or true
        s.check_updates       = type(loaded_settings.check_updates) == "boolean" and loaded_settings.check_updates or true
    end

    -- Apply loaded settings
    config.CONFIG.api_base_url = State.settings.api_url
    config.CONFIG.buffer_max = State.settings.buffer_size
    config.CONFIG.audio_sample_rate = State.settings.sample_rate
    config.CONFIG.audio_chunk_size = State.settings.chunk_size
end

return {
    save_table_to_file = save_table_to_file,
    load_table_from_file = load_table_from_file,
    save_state = save_state,
    load_state = load_state
}
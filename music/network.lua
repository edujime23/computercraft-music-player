local config = require("/music/config")
local State = require("/music/state")
local theme = require("/music/theme")
local storage = require("/music/storage")
local utils = require("/music/utils")

-- Forward declarations for modules to avoid circular dependencies
local audio, events

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

-- PCM chunk conversion
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

-- Stream management
local function stop_current_stream()
    if State.session_id then
        http.post(State.settings.api_url .. "/stop_stream/" .. State.session_id, "")
        State.session_id = nil
    end
    State.is_streaming = false
    State.is_playing = false
    State.buffer = {}

    -- Reset playback timing
    if audio then
        audio.reset_playback_timing()
    else
        State.playback_position = 0
        State.chunks_played = 0
        State.buffer_size_on_pause = 0
        State.downloaded_chunks = {}
    end

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

    -- Reset playback timing
    if audio then
        audio.reset_playback_timing()
    else
        State.playback_position = 0
        State.chunks_played = 0
        State.buffer_size_on_pause = 0
        State.downloaded_chunks = {}
    end

    if State.current_song then
        show_notification("Now playing: " .. (song.title or "Unknown"), 3)
    end

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

-- Update checker
local function check_for_updates()
    if not State.settings.check_updates then return end
    http.request(config.CONFIG.update_check_url)
end

-- HTTP Response handlers
local function handle_stream_start_response(response_text)
    local success, response = pcall(textutils.unserializeJSON, response_text)
    if success and response and response.session_id then
        State.session_id = response.session_id
        State.is_streaming = true
        State.loading = false
        State.connection_errors = 0
        set_status("Stream started", theme.current_colors().status.playing, 2)

        -- Request initial chunks
        for i = 1, config.CONFIG.chunk_request_ahead do
            request_chunk()
        end
    else
        State.loading = false
        State.current_song = nil
        State.connection_errors = State.connection_errors + 1
        set_status("Failed to start stream", theme.current_colors().status.error, 3)
    end
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

        -- Update visualization if audio module is available
        if audio and audio.update_visualization_data then
            audio.update_visualization_data(pcm_samples)
        end

        -- Request next chunk if buffer not full
        if #State.buffer < config.CONFIG.buffer_threshold then
            request_chunk()
        end

        -- Start playing if we have enough buffer
        if not State.is_playing and #State.buffer >= config.CONFIG.buffer_threshold then
            State.is_playing = true
            State.buffer_size_on_pause = 0
            os.queueEvent("playback")
        end
    end
end

local function handle_search_response(response_text)
    State.last_search_url = nil
    State.search_error = nil

    local success, results = pcall(textutils.unserializeJSON, response_text)
    if success and results then
        State.search_results = results
        State.search_scroll = 0
        State.selected_index[config.TABS.SEARCH] = 1
        set_status("Found " .. #results .. " results", colors.white, 2)
    else
        State.search_error = "Failed to parse results"
        set_status("Search failed", theme.current_colors().status.error, 3)
    end
end

local function handle_update_check_response(response_text)
    -- Parse JSON response instead of plain text
    local success, version_data = pcall(textutils.unserializeJSON, response_text)

    if success and version_data and version_data.main then
        local latest_version = version_data.main
        if utils.compare_versions(latest_version, config.CONFIG.version) > 0 then
            set_status("Update available: v" .. latest_version, colors.yellow, 5)
            show_notification("Update available: v" .. latest_version, 5)
        else
            set_status("You're on the latest version", colors.green, 3)
        end
    else
        -- Fallback: try to parse as plain text (for backward compatibility)
        local latest_version = response_text:match("^%d+%.%d+")
        if latest_version and latest_version ~= config.CONFIG.version then
            set_status("Update available: v" .. latest_version, colors.yellow, 5)
            show_notification("Update available: v" .. latest_version, 5)
        else
            set_status("You're on the latest version", colors.green, 3)
        end
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
    elseif url == config.CONFIG.update_check_url then
        handle_update_check_response(response_text)
    end
end

local function handle_http_failure(url, handle)
    if State.last_search_url and url == State.last_search_url then
        State.search_error = "Connection failed"
        State.last_search_url = nil
        set_status("Search connection failed", theme.current_colors().status.error, 3)
    elseif State.session_id and url:find("/chunk/") then
        State.chunk_request_pending = false
        State.connection_errors = State.connection_errors + 1
        if State.connection_errors < 5 then
            sleep(config.CONFIG.retry_delay)
            request_chunk()
        else
            set_status("Too many connection errors", theme.current_colors().status.error)
            stop_current_stream()
        end
    end
end

-- Network diagnostics
local function calculate_network_stats()
    local stats = {
        session_active = State.session_id ~= nil,
        buffer_fill = math.floor((#State.buffer / (State.settings.buffer_size or config.CONFIG.buffer_max)) * 100),
        connection_errors = State.connection_errors or 0,
        avg_latency = State.avg_chunk_latency or 0,
        bytes_received = State.total_bytes_received or 0,
        chunks_downloaded = State.downloaded_chunks and #State.downloaded_chunks or 0,
        uptime = (State.session_id and (os.clock() - (State.stream_start_time or os.clock()))) or 0
    }
    return stats
end

-- Download song functionality
local function download_song()
    if not State.current_song or #State.downloaded_chunks == 0 then
        set_status("No song to download", theme.current_colors().status.error, 2)
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
        set_status("Downloaded to " .. filename, theme.current_colors().status.playing, 3)
    else
        set_status("Failed to save file", theme.current_colors().status.error, 2)
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

    if not events then
        local success, events_module = pcall(require, "/music/events")
        if success then
            events = events_module
        end
    end
end

-- HTTP loop (can be used independently)
local function http_loop()
    init_dependencies()

    while true do
        local event, url, handle = os.pullEvent()
        if event == "http_success" then
            handle_http_success(url, handle)
        elseif event == "http_failure" then
            handle_http_failure(url, handle)
        end
    end
end

return {
    start_stream = start_stream,
    stop_current_stream = stop_current_stream,
    request_chunk = request_chunk,
    check_for_updates = check_for_updates,
    handle_http_success = handle_http_success,
    handle_http_failure = handle_http_failure,
    calculate_network_stats = calculate_network_stats,
    download_song = download_song,
    convert_pcm_chunk = convert_pcm_chunk,
    http_loop = http_loop,

    -- Response handlers (exported for testing/debugging)
    handle_stream_start_response = handle_stream_start_response,
    handle_chunk_response = handle_chunk_response,
    handle_search_response = handle_search_response,
    handle_update_check_response = handle_update_check_response
}
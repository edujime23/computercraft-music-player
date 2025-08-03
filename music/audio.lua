local config = require("/music/config")
local State = require("/music/state")
local theme = require("/music/theme")

-- Initialize speaker
local speaker = peripheral.find("speaker")
if not speaker then
    error("No speaker found! Connect a speaker block.")
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

-- Visualization
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

    local current_colors = theme.current_colors()
    term.setBackgroundColor(colors.black)

    if State.visualization_mode == config.VIS_MODES.BARS then
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
    elseif State.visualization_mode == config.VIS_MODES.WAVE then
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
    elseif State.visualization_mode == config.VIS_MODES.SPECTRUM then
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
    elseif State.visualization_mode == config.VIS_MODES.VU then
        -- VU Meter
        local meter_width = math.floor((width - 3) / 2)

        -- Left channel
        term.setCursorPos(x, y)
        term.setTextColor(colors.white)
        term.write("L")
        local function draw_progress_bar(x, y, width, progress, bg_color, fg_color)
            paintutils.drawBox(x, y, x + width - 1, y, bg_color)
            local filled = math.floor(width * (progress or 0))
            if filled > 0 then
                paintutils.drawBox(x, y, x + filled - 1, y, fg_color)
            end
        end
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

-- Sleep timer
local function update_sleep_timer()
    if State.settings.sleep_timer_active and State.sleep_timer_start then
        local elapsed = os.clock() - State.sleep_timer_start
        local remaining = State.settings.sleep_timer * 60 - elapsed

        if remaining <= 0 then
            State.settings.sleep_timer_active = false
            State.is_playing = false
            -- Note: We can't call UI functions from here, so we queue an event
            os.queueEvent("sleep_timer_expired")
        end
    end
end

-- Main audio playback loop
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
                        -- Note: We can't directly call network functions from here
                        -- Instead, we queue an event that the network module can handle
                        if #State.buffer < config.CONFIG.buffer_threshold and not State.chunk_request_pending then
                            os.queueEvent("request_chunk")
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
                    os.queueEvent("request_chunk")
                end
            end
        end
    end
end

return {
    audio_loop = audio_loop,
    update_visualization_data = update_visualization_data,
    draw_visualization = draw_visualization,
    reset_playback_timing = reset_playback_timing,
    calculate_playback_position = calculate_playback_position,
    update_playback_position = update_playback_position,
    convert_pcm_chunk = convert_pcm_chunk,
    update_sleep_timer = update_sleep_timer
}
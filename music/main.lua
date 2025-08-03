-- CC Music Player v5.0 - Main Entry Point
-- This file orchestrates the entire application

local config = require("/music/config")
local State = require("/music/state")
local utils = require("/music/utils")
local theme = require("/music/theme")
local storage = require("/music/storage")
local ui = require("/music/ui")
local audio = require("/music/audio")
local network = require("/music/network")
local player = require("/music/player")
local events = require("/music/events")

-- Initialize speaker check
local function check_speaker()
    local speaker = peripheral.find("speaker")
    if not speaker then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("ERROR: No speaker found!")
        print("Please connect a speaker block to continue.")
        print("")
        term.setTextColor(colors.white)
        print("Press any key to retry...")
        os.pullEvent("key")

        -- Retry speaker detection
        speaker = peripheral.find("speaker")
        if not speaker then
            error("No speaker found! Connect a speaker block.")
        end
    end
    return speaker
end

-- Display loading screen
local function show_loading_screen()
    term.clear()
    term.setCursorPos(1, 1)

    -- ASCII Art Title
    term.setTextColor(colors.cyan)
    print("  _____ _____   __  __           _      ")
    print(" / ____/ ____| |  \\/  |         (_)     ")
    print("| |   | |      | \\  / |_   _ ___ _  ___ ")
    print("| |   | |      | |\\/| | | | / __| |/ __|")
    print("| |___| |____  | |  | | |_| \\__ \\ | (__ ")
    print(" \\_____\\_____| |_|  |_|\\__,_|___/_|\\___|")
    print("")

    term.setTextColor(colors.white)
    print("CC Music Player v" .. config.CONFIG.version)
    print("Ultra Modular Edition")
    print("")
    term.setTextColor(colors.lightGray)
    print("Initializing modules...")
end

-- Load and validate all modules
local function validate_modules()
    local modules = {
        config = config,
        State = State,
        utils = utils,
        theme = theme,
        storage = storage,
        ui = ui,
        audio = audio,
        network = network,
        player = player,
        events = events
    }

    local missing_modules = {}

    for name, module in pairs(modules) do
        if not module then
            table.insert(missing_modules, name)
        end
    end

    if #missing_modules > 0 then
        error("Missing modules: " .. table.concat(missing_modules, ", "))
    end

    print("✓ All modules loaded successfully")
end

-- Initialize application state
local function initialize_state()
    print("✓ Checking speaker...")
    check_speaker()

    print("✓ Loading saved state...")
    storage.load_state()

    print("✓ Applying theme: " .. State.settings.theme)
    theme.apply_theme(State.settings.theme, State)

    -- Initialize screen dimensions
    State.screen.width, State.screen.height = term.getSize()

    print("✓ State initialized")
end

-- Perform startup checks
local function startup_checks()
    print("✓ Performing startup checks...")

    -- Check if update checking is enabled
    if State.settings.check_updates then
        print("✓ Checking for updates...")
        network.check_for_updates()
    end

    -- Validate audio settings
    if State.settings.sample_rate <= 0 or State.settings.chunk_size <= 0 then
        print("! Warning: Invalid audio settings detected, using defaults")
        State.settings.sample_rate = config.CONFIG.audio_sample_rate
        State.settings.chunk_size = config.CONFIG.audio_chunk_size
        storage.save_state()
    end

    -- Validate buffer settings
    if State.settings.buffer_size <= 0 then
        print("! Warning: Invalid buffer size, using default")
        State.settings.buffer_size = config.CONFIG.buffer_max
        storage.save_state()
    end

    -- Check API URL
    if not State.settings.api_url or State.settings.api_url == "" then
        print("! Warning: No API URL configured, using default")
        State.settings.api_url = config.CONFIG.api_base_url
        storage.save_state()
    end

    print("✓ Startup checks completed")
end

-- Show startup statistics
local function show_startup_stats()
    print("")
    term.setTextColor(colors.yellow)
    print("=== Startup Statistics ===")
    term.setTextColor(colors.white)

    local stats = player.get_playback_stats()
    print("Songs in Queue: " .. #State.queue)
    print("Songs in History: " .. #State.history)
    print("Favorite Songs: " .. #State.favorites)
    print("Playlists: " .. stats.playlists_count)
    print("Current Theme: " .. State.current_theme)
    print("API URL: " .. State.settings.api_url)

    if #State.queue > 0 then
        term.setTextColor(colors.green)
        print("Ready to play " .. #State.queue .. " songs!")
    else
        term.setTextColor(colors.cyan)
        print("Use the Search tab to find music!")
    end

    term.setTextColor(colors.white)
    print("")
end

-- Show controls help
local function show_initial_help()
    term.setTextColor(colors.lightGray)
    print("=== Quick Help ===")
    print("P - Play/Pause  |  N - Next Song  |  +/- - Volume")
    print("F - Favorite    |  M - Mini Mode   |  H - Full Help")
    print("S - Search      |  Q - Queue       |  Tab - Next Tab")
    print("")
    term.setTextColor(colors.white)
end

-- Handle startup errors gracefully
local function safe_startup()
    local function startup_sequence()
        show_loading_screen()
        sleep(0.5)

        validate_modules()
        sleep(0.3)

        initialize_state()
        sleep(0.3)

        startup_checks()
        sleep(0.3)

        show_startup_stats()
        sleep(0.5)

        show_initial_help()
    end

    local success, error_msg = pcall(startup_sequence)

    if not success then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("STARTUP ERROR:")
        print(error_msg)
        print("")
        term.setTextColor(colors.white)
        print("Please check your installation and try again.")
        print("Press any key to exit...")
        os.pullEvent("key")
        error("Startup failed: " .. error_msg)
    end
end

-- Shutdown handler
local function cleanup_on_exit()
    -- Save current state
    print("Saving state...")
    storage.save_state()

    -- Stop any active streams
    if State.session_id then
        print("Stopping active stream...")
        network.stop_current_stream()
    end

    -- Clear screen
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("CC Music Player stopped.")
    print("Thank you for using CC Music Player!")
end

-- Main application entry point
local function main()
    -- Set up error handling
    local function run_with_error_handling()
        -- Perform safe startup
        safe_startup()

        -- Clear screen and start UI
        term.clear()
        term.setCursorPos(1, 1)

        -- Initial UI draw
        ui.redraw()

        -- Show welcome notification
        if State.settings.notifications then
            ui.show_notification("Welcome to CC Music Player v" .. config.CONFIG.version, 3)
        end

        -- Start the main event loops
        print("Starting event loops...")
        events.run()
    end

    -- Run application with error handling
    local success, error_msg = pcall(run_with_error_handling)

    if not success then
        -- Handle runtime errors
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.red)
        print("RUNTIME ERROR:")
        print(error_msg)
        print("")
        term.setTextColor(colors.yellow)
        print("Debug Information:")
        print("Current Tab: " .. (State.current_tab or "Unknown"))
        print("Current Song: " .. (State.current_song and State.current_song.title or "None"))
        print("Queue Length: " .. #State.queue)
        print("Is Playing: " .. tostring(State.is_playing))
        print("Buffer Size: " .. #State.buffer)
        print("")
        term.setTextColor(colors.white)
        print("The application will attempt to save your data...")

        -- Try to save state before exiting
        pcall(cleanup_on_exit)

        print("")
        print("Press any key to exit...")
        os.pullEvent("key")

        error("Application crashed: " .. error_msg)
    end

    -- Normal shutdown
    cleanup_on_exit()
end

-- Performance monitoring (optional)
local function monitor_performance()
    local start_time = os.clock()
    local start_memory = 0 -- ComputerCraft doesn't have memory monitoring, but we can track other metrics

    -- Add performance monitoring if needed
    local function get_performance_stats()
        return {
            uptime = os.clock() - start_time,
            buffer_efficiency = State.is_streaming and (#State.buffer / (State.settings.buffer_size or 20)) or 0,
            connection_quality = State.connection_errors == 0 and "Good" or "Poor",
            songs_processed = #State.history
        }
    end

    return get_performance_stats
end

-- Version compatibility check
local function check_version_compatibility()
    -- Check if we're running on a compatible ComputerCraft version
    if not http then
        print("! Warning: HTTP API not available. Some features may not work.")
    end

    if not peripheral then
        error("Peripheral API not available. This version of ComputerCraft is not supported.")
    end

    if not fs then
        error("Filesystem API not available. This version of ComputerCraft is not supported.")
    end

    -- Check Lua version features
    if not textutils.serializeJSON then
        print("! Warning: JSON serialization not available. Using legacy format.")
    end
end

-- Development mode features
local function setup_development_mode()
    if State.settings.debug_mode then
        -- Enable debug logging
        _G.DEBUG = true

        -- Add performance monitoring
        _G.get_performance_stats = monitor_performance()

        -- Add debug commands
        _G.debug_state = function() return State end
        _G.debug_config = function() return config end

        print("Debug mode enabled")
    end
end

-- Initialize development features if enabled
pcall(setup_development_mode)

-- Perform version compatibility check
check_version_compatibility()

-- Start the application
main()
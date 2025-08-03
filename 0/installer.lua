-- CC Music Player Installer
-- Downloads and sets up the complete music player from GitHub

local INSTALL_CONFIG = {
    repo_url = "https://raw.githubusercontent.com/edujime23/computercraft-music-player/main",
    repo_api = "https://api.github.com/repos/edujime23/computercraft-music-player/contents",
    install_folder = "music",
    temp_folder = "install_temp"
}

-- Installation UI
local function draw_install_ui(title, message, progress)
    term.clear()
    local w, h = term.getSize()

    -- Draw border
    paintutils.drawBox(1, 1, w, h, colors.green)
    paintutils.drawFilledBox(2, 2, w-1, h-1, colors.lime)

    -- Title
    term.setCursorPos(math.floor((w - #title) / 2), 3)
    term.setBackgroundColor(colors.lime)
    term.setTextColor(colors.black)
    term.write(title)

    -- Message
    local lines = {}
    for line in message:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    local start_y = math.floor((h - #lines - 6) / 2)
    for i, line in ipairs(lines) do
        term.setCursorPos(math.floor((w - #line) / 2), start_y + i)
        term.write(line)
    end

    -- Progress bar
    if progress then
        local bar_width = w - 10
        local bar_y = start_y + #lines + 3
        local filled = math.floor(bar_width * progress)

        term.setCursorPos(5, bar_y)
        term.write("Progress: " .. math.floor(progress * 100) .. "%")

        term.setCursorPos(5, bar_y + 1)
        term.setBackgroundColor(colors.gray)
        for i = 1, bar_width do
            term.write(" ")
        end

        term.setCursorPos(5, bar_y + 1)
        term.setBackgroundColor(colors.green)
        for i = 1, filled do
            term.write(" ")
        end

        term.setBackgroundColor(colors.lime)
    end
end

local function wait_for_key()
    term.setCursorPos(1, term.getSize())
    term.setTextColor(colors.black)
    term.write("Press any key to continue...")
    os.pullEvent("key")
end

-- Download functions
local function download_file(url, filename)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        response.close()

        local file = fs.open(filename, "w")
        if file then
            file.write(content)
            file.close()
            return true, content
        end
    end
    return false, nil
end

local function explore_repository()
    -- Get music folder structure
    local response = http.get(INSTALL_CONFIG.repo_api .. "/music")
    if not response then
        return nil
    end

    local content = response.readAll()
    response.close()

    local files = textutils.unserializeJSON(content)
    if not files then
        return nil
    end

    local structure = {
        files = {},
        folders = {}
    }

    for _, item in ipairs(files) do
        if item.type == "file" and item.name:match("%.lua$") then
            table.insert(structure.files, {
                name = item.name,
                path = "music/" .. item.name,
                download_url = item.download_url
            })
        elseif item.type == "dir" then
            table.insert(structure.folders, item.name)
            -- TODO: Recursively explore subdirectories
        end
    end

    return structure
end

local function download_fallback_structure()
    -- Fallback file list if API fails
    return {
        files = {
            {name = "config.lua", path = "music/config.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/config.lua"},
            {name = "state.lua", path = "music/state.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/state.lua"},
            {name = "utils.lua", path = "music/utils.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/utils.lua"},
            {name = "theme.lua", path = "music/theme.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/theme.lua"},
            {name = "storage.lua", path = "music/storage.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/storage.lua"},
            {name = "ui.lua", path = "music/ui.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/ui.lua"},
            {name = "audio.lua", path = "music/audio.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/audio.lua"},
            {name = "network.lua", path = "music/network.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/network.lua"},
            {name = "player.lua", path = "music/player.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/player.lua"},
            {name = "events.lua", path = "music/events.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/events.lua"},
            {name = "main.lua", path = "music/main.lua", download_url = INSTALL_CONFIG.repo_url .. "/music/main.lua"}
        },
        folders = {}
    }
end

local function install_files(structure)
    local total_files = #structure.files
    local completed = 0
    local failed_files = {}

    -- Create music directory
    if not fs.exists(INSTALL_CONFIG.install_folder) then
        fs.makeDir(INSTALL_CONFIG.install_folder)
    end

    -- Create additional folders
    for _, folder in ipairs(structure.folders) do
        local folder_path = INSTALL_CONFIG.install_folder .. "/" .. folder
        if not fs.exists(folder_path) then
            fs.makeDir(folder_path)
        end
    end

    -- Download files
    for i, file in ipairs(structure.files) do
        draw_install_ui("Installing CC Music Player",
            "Downloading: " .. file.name .. "\n" ..
            "File " .. i .. " of " .. total_files,
            completed / total_files)

        local success = download_file(file.download_url, file.path)
        if success then
            completed = completed + 1
        else
            table.insert(failed_files, file.name)
        end

        sleep(0.1) -- Small delay for visual feedback
    end

    return completed, failed_files
end

local function create_entry_point()
    -- Create main music.lua file
    local file = fs.open("music.lua", "w")
    if file then
        file.write('-- CC Music Player Entry Point\n')
        file.write('-- Auto-generated by installer\n\n')
        file.write('require("/music/main")\n')
        file.close()
        return true
    end
    return false
end

local function create_versions_file(structure)
    -- Create versions.json for future updates
    local versions = {
        main = "5.0",
        modules = {}
    }

    for _, file in ipairs(structure.files) do
        local module_name = file.name:gsub("%.lua$", "")
        versions.modules[module_name] = "5.0"
    end

    local file = fs.open("versions.json", "w")
    if file then
        file.write(textutils.serializeJSON(versions))
        file.close()
        return true
    end
    return false
end

local function check_prerequisites()
    -- Check HTTP API
    if not http then
        draw_install_ui("Installation Error",
            "HTTP API is not enabled!\n" ..
            "Enable it in ComputerCraft config to install.", nil)
        wait_for_key()
        return false
    end

    -- Check for speaker
    local speaker = peripheral.find("speaker")
    if not speaker then
        draw_install_ui("Warning",
            "No speaker detected!\n" ..
            "Connect a speaker to use audio features.\n" ..
            "Installation will continue...", nil)
        sleep(3)
    end

    return true
end

local function check_existing_installation()
    if fs.exists("music") or fs.exists("music.lua") then
        draw_install_ui("Existing Installation",
            "Music player files already exist!\n" ..
            "This will overwrite your current installation.\n\n" ..
            "Continue? (Y/N)", nil)

        while true do
            local event, key = os.pullEvent("key")
            if key == keys.y then
                return true
            elseif key == keys.n or key == keys.escape then
                return false
            end
        end
    end
    return true
end

local function show_welcome()
    draw_install_ui("CC Music Player Installer",
        "Welcome to CC Music Player v5.0!\n\n" ..
        "This installer will download and set up\n" ..
        "the complete music player system.\n\n" ..
        "Features:\n" ..
        "• Stream music from YouTube\n" ..
        "• Queue management\n" ..
        "• Playlists and favorites\n" ..
        "• Audio visualization\n" ..
        "• Multiple themes\n\n" ..
        "Press any key to continue...", nil)
    wait_for_key()
end

local function show_completion(completed, total, failed_files)
    local message = "Installation Complete!\n\n"
    message = message .. "Downloaded: " .. completed .. " / " .. total .. " files\n"

    if #failed_files > 0 then
        message = message .. "Failed: " .. #failed_files .. " files\n"
        message = message .. "(" .. table.concat(failed_files, ", ") .. ")\n\n"
        message = message .. "You may need to run the installer again\n"
        message = message .. "or check your internet connection."
    else
        message = message .. "\nAll files downloaded successfully!\n\n"
        message = message .. "To start the music player, run:\n"
        message = message .. "music.lua\n\n"
        message = message .. "For auto-updates, run:\n"
        message = message .. "update.lua"
    end

    draw_install_ui("Installation Complete", message, nil)
    wait_for_key()
end

-- Main installation process
local function main()
    -- Show welcome
    show_welcome()

    -- Check prerequisites
    if not check_prerequisites() then
        return
    end

    -- Check existing installation
    if not check_existing_installation() then
        draw_install_ui("Installation Cancelled", "Installation cancelled by user.", nil)
        wait_for_key()
        return
    end

    -- Explore repository structure
    draw_install_ui("Preparing Installation", "Exploring repository structure...", nil)
    local structure = explore_repository()

    if not structure then
        draw_install_ui("Using Fallback", "Could not access GitHub API.\nUsing fallback file list...", nil)
        sleep(2)
        structure = download_fallback_structure()
    end

    -- Install files
    local completed, failed_files = install_files(structure)

    -- Create entry point
    draw_install_ui("Finalizing Installation", "Creating entry point...", 0.9)
    create_entry_point()

    -- Create versions file
    create_versions_file(structure)

    -- Show completion
    show_completion(completed, #structure.files, failed_files)
end

-- Run installer
main()
-- CC Music Player Update System
-- Handles automatic updates from GitHub repository
local config = require("/music/config")

-- UI for update system
local function draw_update_ui(title, message, options)
    term.clear()
    local w, h = term.getSize()

    -- Draw border
    paintutils.drawBox(1, 1, w, h, colors.blue)
    paintutils.drawFilledBox(2, 2, w-1, h-1, colors.lightBlue)

    -- Title
    term.setCursorPos(math.floor((w - #title) / 2), 3)
    term.setBackgroundColor(colors.lightBlue)
    term.setTextColor(colors.black)
    term.write(title)

    -- Message
    local lines = {}
    for line in message:gmatch("[^\n]+") do
        table.insert(lines, line)
    end

    local start_y = math.floor((h - #lines - 4) / 2)
    for i, line in ipairs(lines) do
        term.setCursorPos(math.floor((w - #line) / 2), start_y + i)
        term.write(line)
    end

    -- Options
    if options then
        local option_y = start_y + #lines + 3
        for i, option in ipairs(options) do
            local x = math.floor((w - #option) / 2)
            term.setCursorPos(x, option_y + i - 1)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. option .. " ")
            term.setBackgroundColor(colors.lightBlue)
            term.setTextColor(colors.black)
        end
    end
end

local function wait_for_choice(options)
    while true do
        local event, key = os.pullEvent("key")
        if key >= keys.one and key <= keys.nine then
            local choice = key - keys.one + 1
            if choice <= #options then
                return choice
            end
        elseif key == keys.enter then
            return 1
        elseif key == keys.escape then
            return #options
        end
    end
end

-- Version management
local function parse_version(version_str)
    if not version_str then return {0, 0, 0} end
    local parts = {}
    for part in version_str:gmatch("([^%.]+)") do
        table.insert(parts, tonumber(part) or 0)
    end
    while #parts < 3 do
        table.insert(parts, 0)
    end
    return parts
end

local function compare_versions(v1, v2)
    local ver1 = parse_version(v1)
    local ver2 = parse_version(v2)

    for i = 1, 3 do
        if ver1[i] > ver2[i] then return 1 end
        if ver1[i] < ver2[i] then return -1 end
    end
    return 0
end

local function get_local_versions()
    local versions = {
        main = config.current_version
    }

    -- Check each module for version info
    local modules = {
        "config", "state", "utils", "theme", "storage",
        "ui", "audio", "network", "player", "events", "main"
    }

    for _, module in ipairs(modules) do
        local file_path = "/music/" .. module .. ".lua"
        if fs.exists(file_path) then
            local file = fs.open(file_path, "r")
            if file then
                local content = file.readAll()
                file.close()

                -- Look for version string in file
                local version = content:match('VERSION%s*=%s*"([^"]+)"') or
                               content:match("VERSION%s*=%s*'([^']+)'") or
                               content:match("version%s*:%s*\"([^\"]+)\"") or
                               config.current_version
                versions[module] = version
            end
        end
    end

    return versions
end

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

local function get_remote_versions()
    local success, content = download_file(config.version_url, "temp_versions.json")
    if success then
        fs.delete("temp_versions.json")
        local versions = textutils.unserializeJSON(content)
        return versions
    end
    return nil
end

local function explore_remote_structure()
    -- Get the file tree from GitHub API
    local api_url = "https://api.github.com/repos/edujime23/computercraft-music-player/contents/music"
    local response = http.get(api_url)

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
        end
    end

    return structure
end

local function backup_current_installation()
    if fs.exists(config.backup_folder) then
        fs.delete(config.backup_folder)
    end

    fs.makeDir(config.backup_folder)

    -- Backup music folder
    if fs.exists("music") then
        fs.copy("music", config.backup_folder .. "/music")
    end

    -- Backup main file
    if fs.exists("music.lua") then
        fs.copy("music.lua", config.backup_folder .. "/music.lua")
    end

    return true
end

local function restore_backup()
    if fs.exists(config.backup_folder .. "/music") then
        if fs.exists("music") then
            fs.delete("music")
        end
        fs.copy(config.backup_folder .. "/music", "music")
    end

    if fs.exists(config.backup_folder .. "/music.lua") then
        if fs.exists("music.lua") then
            fs.delete("music.lua")
        end
        fs.copy(config.backup_folder .. "/music.lua", "music.lua")
    end
end

local function download_updates(remote_versions, local_versions, structure)
    local updated_files = {}
    local failed_files = {}

    -- Create temp directory
    if fs.exists(config.temp_folder) then
        fs.delete(config.temp_folder)
    end
    fs.makeDir(config.temp_folder)
    fs.makeDir(config.temp_folder .. "/music")

    -- Download updated files
    for _, file in ipairs(structure.files) do
        local module_name = file.name:gsub("%.lua$", "")
        local remote_version = remote_versions.modules and remote_versions.modules[module_name]
        local local_version = local_versions[module_name]

        local should_update = false

        if not local_version then
            should_update = true -- New file
        elseif remote_version and compare_versions(remote_version, local_version) > 0 then
            should_update = true -- Newer version
        elseif not fs.exists("music/" .. file.name) then
            should_update = true -- Missing file
        end

        if should_update then
            local success, content = download_file(file.download_url, config.temp_folder .. "/" .. file.path)
            if success then
                table.insert(updated_files, file.path)
            else
                table.insert(failed_files, file.path)
            end
        end
    end

    return updated_files, failed_files
end

local function apply_updates(updated_files)
    local success_count = 0

    for _, file_path in ipairs(updated_files) do
        local temp_path = config.temp_folder .. "/" .. file_path
        local target_path = file_path

        if fs.exists(temp_path) then
            -- Create directory if needed
            local dir = fs.getDir(target_path)
            if dir ~= "" and not fs.exists(dir) then
                fs.makeDir(dir)
            end

            -- Copy file
            if fs.exists(target_path) then
                fs.delete(target_path)
            end
            fs.copy(temp_path, target_path)
            success_count = success_count + 1
        end
    end

    -- Cleanup temp folder
    fs.delete(config.temp_folder)

    return success_count
end

local function perform_update(remote_versions, local_versions)
    draw_update_ui("Updating", "Preparing update...", nil)

    -- Backup current installation
    if not backup_current_installation() then
        draw_update_ui("Update Failed", "Could not create backup.\nUpdate cancelled for safety.", {"OK"})
        wait_for_choice({"OK"})
        return false
    end

    draw_update_ui("Updating", "Exploring remote file structure...", nil)

    -- Get remote structure
    local structure = explore_remote_structure()
    if not structure then
        draw_update_ui("Update Failed", "Could not get remote file list.\nTrying fallback method...", nil)
        sleep(2)
        -- Fallback: use known structure
        structure = {
            files = {
                {name = "config.lua", path = "music/config.lua", download_url = config.repo_url .. "/music/config.lua"},
                {name = "state.lua", path = "music/state.lua", download_url = config.repo_url .. "/music/state.lua"},
                {name = "utils.lua", path = "music/utils.lua", download_url = config.repo_url .. "/music/utils.lua"},
                {name = "theme.lua", path = "music/theme.lua", download_url = config.repo_url .. "/music/theme.lua"},
                {name = "storage.lua", path = "music/storage.lua", download_url = config.repo_url .. "/music/storage.lua"},
                {name = "ui.lua", path = "music/ui.lua", download_url = config.repo_url .. "/music/ui.lua"},
                {name = "audio.lua", path = "music/audio.lua", download_url = config.repo_url .. "/music/audio.lua"},
                {name = "network.lua", path = "music/network.lua", download_url = config.repo_url .. "/music/network.lua"},
                {name = "player.lua", path = "music/player.lua", download_url = config.repo_url .. "/music/player.lua"},
                {name = "events.lua", path = "music/events.lua", download_url = config.repo_url .. "/music/events.lua"},
                {name = "main.lua", path = "music/main.lua", download_url = config.repo_url .. "/music/main.lua"}
            },
            folders = {}
        }
    end

    draw_update_ui("Updating", "Downloading updated files...", nil)

    -- Download updates
    local updated_files, failed_files = download_updates(remote_versions, local_versions, structure)

    if #failed_files > 0 then
        local error_msg = "Failed to download:\n" .. table.concat(failed_files, "\n") .. "\n\nRestore backup?"
        draw_update_ui("Update Error", error_msg, {"1. Restore Backup", "2. Continue Anyway"})
        local choice = wait_for_choice({"Restore Backup", "Continue Anyway"})

        if choice == 1 then
            restore_backup()
            draw_update_ui("Update Cancelled", "Backup restored successfully.", {"OK"})
            wait_for_choice({"OK"})
            return false
        end
    end

    if #updated_files == 0 then
        draw_update_ui("No Updates Applied", "No files needed updating.", {"OK"})
        wait_for_choice({"OK"})
        return false
    end

    draw_update_ui("Updating", "Applying updates...", nil)

    -- Apply updates
    local success_count = apply_updates(updated_files)

    -- Update main entry point if needed
    if not fs.exists("music.lua") then
        local file = fs.open("music.lua", "w")
        if file then
            file.write('require("/music/main")')
            file.close()
        end
    end

    draw_update_ui("Update Complete",
        "Successfully updated " .. success_count .. " files!\n\n" ..
        "Files updated:\n" .. table.concat(updated_files, "\n") .. "\n\n" ..
        "Restart the music player to use new version.",
        {"OK"})
    wait_for_choice({"OK"})

    return true
end

local function check_for_updates()
    draw_update_ui("CC Music Player Updater", "Checking for updates...", nil)
    sleep(1)

    -- Get versions
    local local_versions = get_local_versions()
    local remote_versions = get_remote_versions()

    if not remote_versions then
        draw_update_ui("Update Check Failed", "Could not connect to update server.\nCheck your internet connection.", {"OK"})
        wait_for_choice({"OK"})
        return false
    end

    -- Check if update is available
    local main_update_available = compare_versions(remote_versions.main or "5.0", local_versions.main) > 0
    local module_updates = {}

    if remote_versions.modules then
        for module, remote_ver in pairs(remote_versions.modules) do
            local local_ver = local_versions[module]
            if not local_ver or compare_versions(remote_ver, local_ver) > 0 then
                module_updates[module] = remote_ver
            end
        end
    end

    if not main_update_available and next(module_updates) == nil then
        draw_update_ui("No Updates Available", "You are running the latest version!\nCurrent: " .. local_versions.main, {"OK"})
        wait_for_choice({"OK"})
        return false
    end

    -- Show update info
    local update_info = "Updates available:\n\n"
    if main_update_available then
        update_info = update_info .. "Main: " .. local_versions.main .. " → " .. (remote_versions.main or "5.0") .. "\n"
    end

    for module, version in pairs(module_updates) do
        update_info = update_info .. module .. ": " .. (local_versions[module] or "unknown") .. " → " .. version .. "\n"
    end

    update_info = update_info .. "\nDo you want to update?"

    draw_update_ui("Update Available", update_info, {"1. Yes, Update", "2. No, Cancel"})
    local choice = wait_for_choice({"Yes, Update", "No, Cancel"})

    if choice ~= 1 then
        return false
    end

    return perform_update(remote_versions, local_versions)
end

-- Main execution
local function main()
    if not http then
        term.clear()
        term.setCursorPos(1, 1)
        print("HTTP API is not enabled!")
        print("Enable it in ComputerCraft config to use the updater.")
        return
    end

    check_for_updates()
end

main()
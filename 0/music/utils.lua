local utils = {}

function utils.try(fn, catch_fn)
    local success, result = pcall(fn)
    if not success then
        if catch_fn then catch_fn(result) end
        return nil, result
    end
    return result
end

function utils.safeGet(tbl, key, default)
    if not tbl or type(tbl) ~= "table" then return default end
    local value = tbl[key]
    return value ~= nil and value or default
end

function utils.clamp(value, min_val, max_val)
    return math.max(min_val, math.min(max_val, value or 0))
end

function utils.formatTime(seconds)
    if not seconds or type(seconds) ~= "number" or seconds < 0 then
        return "--:--"
    end
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

function utils.truncate(text, maxLen)
    text = tostring(text or "")
    return #text > maxLen and (text:sub(1, maxLen - 3) .. "...") or text
end

function utils.uuid()
    return string.format("%x%x%x%x",
        math.random(0, 0xffff), math.random(0, 0xffff),
        math.random(0, 0xffff), math.random(0, 0xffff))
end

function utils.formatBytes(bytes)
    bytes = bytes or 0
    if bytes < 1024 then
        return bytes .. "B"
    elseif bytes < 1024 * 1024 then
        return string.format("%.1fKB", bytes / 1024)
    else
        return string.format("%.1fMB", bytes / (1024 * 1024))
    end
end

function utils.shuffle(tbl)
    local shuffled = {}
    for i = 1, #tbl do shuffled[i] = tbl[i] end
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    return shuffled
end

-- NEW: Version comparison functions (moved from network.lua)
function utils.parse_version(version_str)
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

function utils.compare_versions(v1, v2)
    local ver1 = utils.parse_version(v1)
    local ver2 = utils.parse_version(v2)

    for i = 1, 3 do
        if ver1[i] > ver2[i] then return 1 end
        if ver1[i] < ver2[i] then return -1 end
    end
    return 0
end

function utils.cleanup_screen()
    -- Reset terminal to default state
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

return utils
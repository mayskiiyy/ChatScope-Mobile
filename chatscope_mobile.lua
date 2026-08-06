script_name("ChatScope Mobile")
script_author("Mayskiy")
script_version("1.1.0")

require "moonloader"

local imgui = require "mimgui"
local ffi = require "ffi"
local bit = require "bit"
local encoding = require "encoding"
local sampev = require "lib.samp.events"

encoding.default = "CP1251"
local u8 = encoding.UTF8
local new, ffi_string = imgui.new, ffi.string

local MAX_HISTORY_LINES = 2000
local CONFIG_DIRECTORY = getWorkingDirectory() .. "/config"
local CONFIG_PATH = CONFIG_DIRECTORY .. "/chatscope_mobile.cfg"
local LEGACY_CONFIG_PATH = CONFIG_DIRECTORY .. "/simple_cf.cfg"

local history = {}
local global_filters = {}
local visual_filters = {}
local history_filters = {}
local folders = {}

local show_filter_window = new.bool(false)
local show_history_window = new.bool(false)

local add_filter_buffer = new.char[256]()
local folder_name_buffer = new.char[64]()
local folder_patterns_buffer = new.char[512]()
local search_buffer = new.char[256]()

local function clear_table(value)
    for index = #value, 1, -1 do
        value[index] = nil
    end
end

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function contains_value(list, value)
    for _, item in ipairs(list) do
        if item == value then
            return true
        end
    end
    return false
end

local function add_unique(list, value)
    value = trim(value)
    if value == "" or contains_value(list, value) then
        return false
    end

    table.insert(list, value)
    return true
end

local function escape_config_field(value)
    return value:gsub("\\", "\\\\"):gsub("|", "\\|")
end

local function split_escaped_pair(line)
    local left, right = {}, {}
    local target = left
    local escaped = false
    local separator_found = false

    for index = 1, #line do
        local character = line:sub(index, index)
        if escaped then
            table.insert(target, character)
            escaped = false
        elseif character == "\\" then
            escaped = true
        elseif character == "|" and not separator_found then
            separator_found = true
            target = right
        else
            table.insert(target, character)
        end
    end

    if escaped then
        table.insert(target, "\\")
    end

    if not separator_found then
        return nil, nil
    end

    return table.concat(left), table.concat(right)
end

local function save_config()
    local file, error_message = io.open(CONFIG_PATH, "w")
    if not file then
        print("[ChatScope Mobile] Could not save config: " .. tostring(error_message))
        return false
    end

    local function write_list(section_name, list)
        file:write("[", section_name, "]\n")
        for _, value in ipairs(list) do
            file:write(value, "\n")
        end
    end

    write_list("GLOBAL", global_filters)
    write_list("VISUAL", visual_filters)
    write_list("HISTORY", history_filters)

    file:write("[FOLDERS]\n")
    for _, folder in ipairs(folders) do
        file:write(
            escape_config_field(folder.name),
            "|",
            escape_config_field(folder.patterns_raw),
            "\n"
        )
    end

    file:close()
    return true
end

local function load_config_file(path)
    local file = io.open(path, "r")
    if not file then
        return false
    end

    clear_table(global_filters)
    clear_table(visual_filters)
    clear_table(history_filters)
    clear_table(folders)

    local section = ""
    for raw_line in file:lines() do
        local line = raw_line:gsub("\r$", "")
        local section_name = line:match("^%[([^%]]+)%]$")

        if section_name then
            section = section_name
        elseif line ~= "" then
            if section == "GLOBAL" then
                add_unique(global_filters, line)
            elseif section == "VISUAL" then
                add_unique(visual_filters, line)
            elseif section == "HISTORY" then
                add_unique(history_filters, line)
            elseif section == "FOLDERS" then
                local name, patterns_raw = split_escaped_pair(line)
                if name and patterns_raw and trim(name) ~= "" and trim(patterns_raw) ~= "" then
                    table.insert(folders, {
                        name = trim(name),
                        patterns_raw = trim(patterns_raw)
                    })
                end
            end
        end
    end

    file:close()
    return true
end

local function load_config()
    if load_config_file(CONFIG_PATH) then
        return
    end

    if load_config_file(LEGACY_CONFIG_PATH) then
        save_config()
        print("[ChatScope Mobile] Migrated legacy config to chatscope_mobile.cfg")
    end
end

local function strip_samp_colors(text)
    return text:gsub("{%x%x%x%x%x%x}", "")
end

local function glob_to_lua_pattern(glob)
    local escaped = glob:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1")
    return "^" .. escaped:gsub("%*", ".*") .. "$"
end

local function matches_any_pattern(text, patterns)
    local clean_text = strip_samp_colors(text)
    for _, pattern in ipairs(patterns) do
        if pattern ~= "" and clean_text:find(glob_to_lua_pattern(pattern)) then
            return true
        end
    end
    return false
end

local function parse_folder_patterns(patterns_raw)
    local patterns = {}

    if patterns_raw:find(";", 1, true) then
        for pattern in patterns_raw:gmatch("([^;]+)") do
            add_unique(patterns, pattern)
        end
    else
        -- Backward compatibility with the original space-separated format.
        for pattern in patterns_raw:gmatch("%S+") do
            add_unique(patterns, pattern)
        end
    end

    return patterns
end

local function matches_folder(text, patterns_raw)
    return matches_any_pattern(text, parse_folder_patterns(patterns_raw))
end

local function color_to_imvec4(color)
    local red = bit.band(bit.rshift(color, 24), 0xFF) / 255
    local green = bit.band(bit.rshift(color, 16), 0xFF) / 255
    local blue = bit.band(bit.rshift(color, 8), 0xFF) / 255
    local alpha = bit.band(color, 0xFF) / 255

    if alpha == 0 then
        alpha = 1
    end

    return imgui.ImVec4(red, green, blue, alpha)
end

local function add_to_history(text, color)
    if matches_any_pattern(text, history_filters) then
        return
    end

    table.insert(history, {
        message = strip_samp_colors(text),
        color = color_to_imvec4(color),
        timestamp = os.date("%H:%M:%S")
    })

    while #history > MAX_HISTORY_LINES do
        table.remove(history, 1)
    end
end

local function process_message(color, text)
    if matches_any_pattern(text, global_filters) then
        return false
    end

    add_to_history(text, color)
    return not matches_any_pattern(text, visual_filters)
end

function sampev.onServerMessage(color, text)
    return process_message(color, text)
end

function sampev.onChatMessage(player_id, text)
    local nickname = sampGetPlayerNickname(player_id)
    if not nickname then
        nickname = "Unknown"
    end

    return process_message(0xFFFFFFFF, string.format("%s[%d]: %s", nickname, player_id, text))
end

local function draw_filter_tab(label, list, id_suffix)
    if not imgui.BeginTabItem(label) then
        return
    end

    imgui.InputText("Pattern##" .. id_suffix, add_filter_buffer, 256)
    if imgui.Button("Add##" .. id_suffix, imgui.ImVec2(-1, 0)) then
        local value = u8:decode(ffi_string(add_filter_buffer))
        if add_unique(list, value) then
            save_config()
            ffi.fill(add_filter_buffer, 256, 0)
        end
    end

    imgui.BeginChild("filter_list##" .. id_suffix, imgui.ImVec2(0, 220), true)
    local remove_index = nil

    for index, value in ipairs(list) do
        if imgui.Button("X##" .. id_suffix .. index) then
            remove_index = index
        end
        imgui.SameLine()
        imgui.TextWrapped(u8(value))
    end

    if remove_index then
        table.remove(list, remove_index)
        save_config()
    end

    imgui.EndChild()
    imgui.EndTabItem()
end

local function draw_folders_tab()
    if not imgui.BeginTabItem("Folders") then
        return
    end

    imgui.InputText("Name", folder_name_buffer, 64)
    imgui.InputText("Patterns (separate with ;)", folder_patterns_buffer, 512)

    if imgui.Button("Create folder", imgui.ImVec2(-1, 0)) then
        local name = trim(u8:decode(ffi_string(folder_name_buffer)))
        local patterns_raw = trim(u8:decode(ffi_string(folder_patterns_buffer)))

        if name ~= "" and patterns_raw ~= "" then
            table.insert(folders, {name = name, patterns_raw = patterns_raw})
            save_config()
            ffi.fill(folder_name_buffer, 64, 0)
            ffi.fill(folder_patterns_buffer, 512, 0)
        end
    end

    imgui.Separator()
    local remove_index = nil

    for index, folder in ipairs(folders) do
        if imgui.Button("X##folder" .. index) then
            remove_index = index
        end
        imgui.SameLine()
        imgui.TextWrapped(u8(folder.name .. " — " .. folder.patterns_raw))
    end

    if remove_index then
        table.remove(folders, remove_index)
        save_config()
    end

    imgui.EndTabItem()
end

local function draw_history_list(folder, search_query, child_id)
    imgui.BeginChild(child_id, imgui.ImVec2(0, 0), true)
    local was_at_bottom = imgui.GetScrollY() >= imgui.GetScrollMaxY() - 4

    for index, entry in ipairs(history) do
        local visible = true

        if folder and not matches_folder(entry.message, folder.patterns_raw) then
            visible = false
        end

        if search_query ~= "" and not entry.message:lower():find(search_query, 1, true) then
            visible = false
        end

        if visible then
            imgui.TextDisabled("[" .. entry.timestamp .. "]")
            imgui.SameLine()
            imgui.PushStyleColor(imgui.Col.Text, entry.color)

            local selectable_label = u8(entry.message) .. "##history_" .. child_id .. "_" .. index
            if imgui.Selectable(selectable_label) then
                setClipboardText(u8(entry.message))
                sampAddChatMessage("{00BFFF}[ChatScope]{FFFFFF} Message copied.", -1)
            end

            imgui.PopStyleColor()
        end
    end

    if was_at_bottom then
        imgui.SetScrollHereY(1.0)
    end

    imgui.EndChild()
end

imgui.OnFrame(function()
    return show_filter_window[0] or show_history_window[0]
end, function()
    imgui.GetStyle().ScrollbarSize = 25.0

    if show_filter_window[0] then
        imgui.SetNextWindowSize(imgui.ImVec2(620, 430), imgui.Cond.FirstUseEver)
        imgui.Begin("ChatScope — Filters", show_filter_window)

        if imgui.BeginTabBar("filter_tabs") then
            draw_filter_tab("Global", global_filters, "global")
            draw_filter_tab("Visual only", visual_filters, "visual")
            draw_filter_tab("History only", history_filters, "history")
            draw_folders_tab()
            imgui.EndTabBar()
        end

        imgui.End()
    end

    if show_history_window[0] then
        imgui.SetNextWindowSize(imgui.ImVec2(750, 500), imgui.Cond.FirstUseEver)
        imgui.Begin("ChatScope — History", show_history_window)
        imgui.InputText("Search", search_buffer, 256)

        local search_query = u8:decode(ffi_string(search_buffer)):lower()
        if imgui.BeginTabBar("history_tabs") then
            if imgui.BeginTabItem("All") then
                draw_history_list(nil, search_query, "all_messages")
                imgui.EndTabItem()
            end

            for index, folder in ipairs(folders) do
                if imgui.BeginTabItem(u8(folder.name) .. "##folder_tab_" .. index) then
                    draw_history_list(folder, search_query, "folder_messages_" .. index)
                    imgui.EndTabItem()
                end
            end

            imgui.EndTabBar()
        end

        imgui.End()
    end
end)

function main()
    while not isSampLoaded() do
        wait(500)
    end

    if not doesDirectoryExist(CONFIG_DIRECTORY) then
        createDirectory(CONFIG_DIRECTORY)
    end

    load_config()

    sampRegisterChatCommand("cf", function()
        show_filter_window[0] = not show_filter_window[0]
    end)

    sampRegisterChatCommand("ch", function()
        show_history_window[0] = not show_history_window[0]
    end)

    sampAddChatMessage(
        string.format("{00BFFF}[ChatScope]{FFFFFF} v%s loaded. Use /ch and /cf.", thisScript().version),
        -1
    )

    wait(-1)
end

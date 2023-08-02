--[[
----------------------------------------------------------------------------------------------------------------------------------------
Open Broadcaster Software®️
OBS > Tools > Scripts
'ORIGINAL by insin'
https://github.com/insin
'UPDATED by Neshaiy'
https://github.com/Neshaiy
sources-move
***************************************************************************************************************************************
Version 1
Published / Released: 2023-08-02 05:00
***************************************************************************************************************************************
]]

local obs = obslua
local bit = require('bit')

-- Variables to control the behavior
local move_type = 'dvd_bounce'
local source_name = ''
local start_on_scene_change = false
local hotkey_id = obs.OBS_INVALID_HOTKEY_ID

-- Variables to handle the movement
local active = false
local scene_item = nil
local original_pos = nil
local scene_width = nil
local scene_height = nil

-- DVD Bounce settings
local speed = 10
local moving_down = true
local moving_right = true

-- Throw & Bounce settings
local throw_speed_x = 100
local throw_speed_y = 50
local velocity_x = 0
local velocity_y = 0
local wait_frames = 1

-- Physics settings
local gravity = 0.98
local air_drag = 0.99
local ground_friction = 0.95
local elasticity = 0.8

-- Variable to track the state of random_bounce
local random_bounce_active = false

-- Variable to track the state of the hotkey
local hotkey_active = false

-- Function to find the scene item
local function find_scene_item()
    local source = obs.obs_frontend_get_current_scene()
    if not source then
        print('There is no current scene')
        return
    end
    scene_width = obs.obs_source_get_width(source)
    scene_height = obs.obs_source_get_height(source)
    local scene = obs.obs_scene_from_source(source)
    obs.obs_source_release(source)
    scene_item = obs.obs_scene_find_source(scene, source_name)
    if scene_item then
        original_pos = get_scene_item_pos(scene_item)
        return true
    end
    print(source_name .. ' not found')
    return false
end

-- Function to describe the script
function script_description()
    return 'Move a selected source around its scene.\n\nORIGINAL by insin  UPDATED by Neshaiy\n\nVersion 1'
end

-- Function to define the properties of the script
function script_properties()
    local props = obs.obs_properties_create()
    local source = obs.obs_properties_add_list(
        props,
        'source',
        'Source:',
        obs.OBS_COMBO_TYPE_EDITABLE,
        obs.OBS_COMBO_FORMAT_STRING)
    for _, name in ipairs(get_source_names()) do
        obs.obs_property_list_add_string(source, name, name)
    end
    local move_type = obs.obs_properties_add_list(
        props,
        'move_type',
        'Move Type:',
        obs.OBS_COMBO_TYPE_LIST,
        obs.OBS_COMBO_FORMAT_STRING)
    obs.obs_property_list_add_string(move_type, 'DVD Bounce', 'dvd_bounce')
    obs.obs_property_list_add_string(move_type, 'Throw & Bounce', 'throw_bounce')
    obs.obs_property_list_add_string(move_type, 'Random Bounce', 'random_bounce')
    obs.obs_properties_add_int_slider(props, 'speed', 'DVD Bounce Speed:', 1, 30, 1)
    obs.obs_properties_add_int_slider(props, 'throw_speed_x', 'Max Throw Speed (X):', 1, 200, 1)
    obs.obs_properties_add_int_slider(props, 'throw_speed_y', 'Max Throw Speed (Y):', 1, 100, 1)
    obs.obs_properties_add_bool(props, 'start_on_scene_change', 'Start on scene change')
    return props
end

-- Function to set default settings
function script_defaults(settings)
    obs.obs_data_set_default_string(settings, 'move_type', move_type)
    obs.obs_data_set_default_int(settings, 'speed', speed)
    obs.obs_data_set_default_int(settings, 'throw_speed_x', throw_speed_x)
    obs.obs_data_set_default_int(settings, 'throw_speed_y', throw_speed_y)
end

-- Function to update the settings
function script_update(settings)
    local old_source_name = source_name
    source_name = obs.obs_data_get_string(settings, 'source')
    local old_move_type = move_type
    move_type = obs.obs_data_get_string(settings, 'move_type')
    speed = obs.obs_data_get_int(settings, 'speed')
    throw_speed_x = obs.obs_data_get_int(settings, 'throw_speed_x')
    throw_speed_y = obs.obs_data_get_int(settings, 'throw_speed_y')
    start_on_scene_change = obs.obs_data_get_bool(settings, 'start_on_scene_change')
    if old_source_name ~= source_name or old_move_type ~= move_type then
        restart_if_active()
    end
end

-- Function to load the script
function script_load(settings)
    hotkey_id = obs.obs_hotkey_register_frontend('toggle_bounce', 'Toggle Bounce', function(pressed)
        if pressed then
            hotkey_active = not hotkey_active
            toggle()
        end
    end)

    local hotkey_save_array = obs.obs_data_get_array(settings, 'toggle_hotkey')
    obs.obs_hotkey_load(hotkey_id, hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)

    obs.obs_frontend_add_event_callback(on_event)
end

-- Function to handle frontend events
function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED then
        if start_on_scene_change then
            scene_changed()
        end
    elseif event == obs.OBS_FRONTEND_EVENT_EXIT then
        if active then
            toggle()
        end
    end
end

-- Function to save the script settings
function script_save(settings)
    local hotkey_save_array = obs.obs_hotkey_save(hotkey_id)
    obs.obs_data_set_array(settings, 'toggle_hotkey', hotkey_save_array)
    obs.obs_data_array_release(hotkey_save_array)
end

-- Function to execute the movement on every tick
function script_tick(seconds)
    if active and hotkey_active then
        if move_type == 'dvd_bounce' then
            move_scene_item(scene_item)
        elseif move_type == 'throw_bounce' then
            throw_scene_item(scene_item)
        elseif move_type == 'random_bounce' then
            random_bounce_scene_item(scene_item)
        end
    end
end

-- Function to get the names of all sources
function get_source_names()
    local sources = obs.obs_enum_sources()
    local source_names = {}
    if sources then
        for _, source in ipairs(sources) do
            local capability_flags = obs.obs_source_get_output_flags(source)
            if bit.band(capability_flags, obs.OBS_SOURCE_DO_NOT_SELF_MONITOR) == 0 and
                capability_flags ~= bit.bor(obs.OBS_SOURCE_AUDIO, obs.OBS_SOURCE_DO_NOT_DUPLICATE) then
                table.insert(source_names, obs.obs_source_get_name(source))
            end
        end
    end
    obs.source_list_release(sources)
    table.sort(source_names, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return source_names
end

-- Helper functions to get scene item properties
function get_scene_item_crop(scene_item)
    local crop = obs.obs_sceneitem_crop()
    obs.obs_sceneitem_get_crop(scene_item, crop)
    return crop
end

function get_scene_item_pos(scene_item)
    local pos = obs.vec2()
    obs.obs_sceneitem_get_pos(scene_item, pos)
    return pos
end

function get_scene_item_scale(scene_item)
    local scale = obs.vec2()
    obs.obs_sceneitem_get_scale(scene_item, scale)
    return scale
end

function get_scene_item_dimensions(scene_item)
    local pos = get_scene_item_pos(scene_item)
    local scale = get_scene_item_scale(scene_item)
    local crop = get_scene_item_crop(scene_item)
    local source = obs.obs_sceneitem_get_source(scene_item)
    local width = round((obs.obs_source_get_width(source) - crop.left - crop.right) * scale.x)
    local height = round((obs.obs_source_get_height(source) - crop.top - crop.bottom) * scale.y)
    return pos, width, height
end

-- Function to move the scene item
function move_scene_item(scene_item)
    local pos, width, height = get_scene_item_dimensions(scene_item)
    local next_pos = obs.vec2()

    if moving_right and pos.x + width < scene_width then
        next_pos.x = math.min(pos.x + speed, scene_width - width)
    else
        moving_right = false
        next_pos.x = math.max(pos.x - speed, 0)
        if next_pos.x == 0 then
            moving_right = true
        end
    end

    if moving_down and pos.y + height < scene_height then
        next_pos.y = math.min(pos.y + speed, scene_height - height)
    else
        moving_down = false
        next_pos.y = math.max(pos.y - speed, 0)
        if next_pos.y == 0 then
            moving_down = true
        end
    end

    obs.obs_sceneitem_set_pos(scene_item, next_pos)
end

-- Function to simulate throw and bounce movement
function throw_scene_item(scene_item)
    if velocity_x == 0 and velocity_y == 0 then
        wait_frames = wait_frames - 1
        if wait_frames == 0 then
            velocity_x = math.random(-throw_speed_x, throw_speed_x)
            velocity_y = -round(throw_speed_y * 0.5) - math.random(round(throw_speed_y * 0.5))
        end
        return
    end

    if velocity_y == 0 and velocity_x < 0.75 then
        velocity_x = 0
        wait_frames = 60 * 1
        return
    end

    local pos, width, height = get_scene_item_dimensions(scene_item)
    local next_pos = obs.vec2()

    local was_bottomed = pos.y == scene_height - height

    next_pos.x = pos.x + velocity_x
    next_pos.y = pos.y + velocity_y

    if next_pos.y >= scene_height - height then
        next_pos.y = scene_height - height
        if was_bottomed then
            velocity_y = 0
        else
            velocity_y = -(velocity_y * elasticity)
        end
    end

    if next_pos.x >= scene_width - width or next_pos.x <= 0 then
        if next_pos.x <= 0 then
            next_pos.x = 0
        else
            next_pos.x = scene_width - width
        end
        velocity_x = -(velocity_x * elasticity)
    end

    if velocity_y ~= 0 then
        velocity_y = velocity_y + gravity
        velocity_y = velocity_y * air_drag
    end
    velocity_x = velocity_x * air_drag

    if next_pos.y == scene_height - height then
        velocity_x = velocity_x * ground_friction
    end

    obs.obs_sceneitem_set_pos(scene_item, next_pos)
end

-- Function to move the scene item to a random position
function random_bounce_scene_item(scene_item)
    if not random_bounce_active then
        local pos, width, height = get_scene_item_dimensions(scene_item)
        local next_pos = obs.vec2()

        next_pos.x = math.random(scene_width - width)
        next_pos.y = math.random(scene_height - height)

        obs.obs_sceneitem_set_pos(scene_item, next_pos)

        random_bounce_active = true
    end
end

-- Function to toggle the movement
function toggle()
    if not toggle_active then
        -- Activate the movement
        find_scene_item()
        if scene_item then
            active = true
            if move_type == 'throw_bounce' then
                velocity_x = math.random(-throw_speed_x, throw_speed_x)
                velocity_y = -math.random(throw_speed_y)
            elseif move_type == 'random_bounce' then
                random_bounce_active = false
            end
        end
    else
        -- Deactivate the movement
        active = false
        velocity_x = 0
        velocity_y = 0
        random_bounce_active = false -- Reset the state of random_bounce
        if scene_item then
            obs.obs_sceneitem_set_pos(scene_item, original_pos)
        end
        scene_item = nil
    end
    toggle_active = not toggle_active -- Toggle the state
end

-- Function to restart if the movement is active
function restart_if_active()
    local was_active = active
    if active then
        toggle()
    end
    find_scene_item()
    if was_active then
        toggle()
    end
end

-- Function to handle scene change
function scene_changed()
    if active then
        toggle()
    end
    find_scene_item()
    toggle()
end

-- Function to round a number
function round(n)
    return math.floor(n + 0.5)
end
----------------------------------------------------------------
-- COUNTERMEASURES SYSTEM
----------------------------------------------------------------
-- This module will handle the dispensing of countermeasures
-- This module models the AN/ALE-29A Chaff Dispensing System
----------------------------------------------------------------

dofile(LockOn_Options.common_script_path.."devices_defs.lua")
dofile(LockOn_Options.script_path.."command_defs.lua")
dofile(LockOn_Options.script_path.."Systems/electric_system_api.lua")
dofile(LockOn_Options.script_path.."utils.lua")

local CMS = GetSelf()

local update_rate = 0.006
make_default_activity(update_rate)

startup_print("countermeasures: load")

function debug_print(x)
    -- print_message_to_user(x)
    -- log.alert(x)
end

-- countermeasure state
local chaff_count = 0
local flare_count = 0
local cm_bank1_show = 0
local cm_bank2_show = 0
local cm_banksel = 0
local cm_auto = false
local cm_enabled = false
local ECM_status = false
local flare_pos = 0
local chaff_pos = 0
local cms_dispense = false
local burst_counter = 0
local salvo_counter = 0

-- cms programmer settings
local cms_bursts_setting = 4
local cms_burst_interval_setting = 0.2
local cms_salvos_setting = 8
local cms_salvo_interval_setting = 2

-- cms programmer settings array
local cms_bursts_setting_array = { 1, 2, 3, 4 }
local cms_burst_interval_array = { 0.2, 0.3, 0.4, 0.5}
local cms_salvos_setting_array = { 8, 12, 16, 20, 24, 28, 32 }
local cms_salvo_interval_setting_array = { 2, 4, 6, 8, 10, 12, 14 }

-- timers
local time_ticker = 0
local last_burst_time = 0

CMS:listen_command(device_commands.cm_pwr)
CMS:listen_command(device_commands.cm_bank)
CMS:listen_command(device_commands.cm_adj1)
CMS:listen_command(device_commands.cm_adj2)
CMS:listen_command(device_commands.cm_auto)
CMS:listen_command(iCommandActiveJamming)
CMS:listen_command(iCommandPlaneDropFlareOnce)
CMS:listen_command(iCommandPlaneDropChaffOnce)
CMS:listen_command(Keys.CmDrop)
CMS:listen_command(Keys.CmBankSelectRotate)
CMS:listen_command(Keys.CmBankSelect)
CMS:listen_command(Keys.CmAutoModeToggle)
CMS:listen_command(Keys.CmBank1AdjUp)
CMS:listen_command(Keys.CmBank1AdjDown)
CMS:listen_command(Keys.CmBank2AdjUp)
CMS:listen_command(Keys.CmBank2AdjDown)
CMS:listen_command(Keys.CmPowerToggle)

local cm_bank1_Xx = get_param_handle("CM_BANK1_Xx")
local cm_bank1_xX = get_param_handle("CM_BANK1_xX")
local cm_bank2_Xx = get_param_handle("CM_BANK2_Xx")
local cm_bank2_xX = get_param_handle("CM_BANK2_xX")

function cm_draw_bank1( count )
    local tens = math.floor(count/10 + 0.02)
    local ones = math.floor(count%10 + 0.02)

    --print_message_to_user("b1: "..tens.." "..ones)
    cm_bank1_Xx:set(tens/10)
    cm_bank1_xX:set(ones/10)
end

function cm_draw_bank2( count )
    local tens = math.floor(count/10 + 0.02)
    local ones = math.floor(count%10 + 0.02)

    --print_message_to_user("b2: "..tens.." "..ones)
    cm_bank2_Xx:set(tens/10)
    cm_bank2_xX:set(ones/10)
end

function update_countermeasures_display()
    cm_draw_bank1(cm_bank1_show)
    cm_draw_bank2(cm_bank2_show)
end

function release_countermeasure()
    debug_print("releasing countermeasures")
    if cm_banksel == 1 or cm_banksel == 3 then
        chaff_count = CMS:get_chaff_count()
        if chaff_count > 0 then
            CMS:drop_chaff(1, chaff_pos)  -- first param is count, second param is dispenser number (see chaff_flare_dispenser in aircraft definition)
            cm_bank1_show = (cm_bank1_show - 1) % 100
        end
    end
    if cm_banksel == 2 or cm_banksel == 3 then
        flare_count = CMS:get_flare_count()
        if flare_count > 0 then
            CMS:drop_flare(1, flare_pos)  -- first param is count, second param is dispenser number (see chaff_flare_dispenser in aircraft definition)
            cm_bank2_show = (cm_bank2_show - 1) % 100
        end
    end
end

function post_initialize()
    cm_bank1_show = CMS:get_chaff_count()
    cm_bank2_show = CMS:get_flare_count()
	flare_count = 0

end -- post_initialize()


function update()

    time_ticker = time_ticker + update_rate

    -- check if monitored dc bus power is available
    -- check if AN/ALE-29A panel is on
    if get_elec_mon_dc_ok() and cm_enabled then

        -- check if dispense is true
        if cms_dispense then
            -- continue burst sequence if not completed
            if burst_counter < cms_bursts_setting then
                -- debug_print("running burst sequence")
                -- check if burst interval is reached
                if (time_ticker - last_burst_time) > cms_burst_interval_setting then
                    debug_print("dropping flare")
                    release_countermeasure()
                    last_burst_time = time_ticker
                    burst_counter = burst_counter + 1
                    
                    -- check if burst sequence complete. Mark end time if completed.
                    if burst_counter == cms_bursts_setting then
                        last_salvo_time = time_ticker
                    end
                end
            -- start new salvo if interval reached
            elseif salvo_counter < cms_salvos_setting then
                -- restart burst sequence if salvo interval is met
                if (time_ticker - last_salvo_time) > cms_salvo_interval_setting then
                    salvo_counter = salvo_counter + 1
                    if salvo_counter == cms_salvos_setting then
                        debug_print("sequence complete: salvo")
                        cms_dispense = false
                    else
                        debug_print("starting next salvo "..salvo_counter)
                        burst_counter = 0
                    end
                end
            -- stop dispensing if bursts and salvos completed
            elseif burst_counter == cms_bursts_setting and salvo_counter == cms_salvos_setting then
                debug_print("sequence complete")
                cms_dispense = false
                salvo_counter = 0
                burst_counter = 0
            end

        end -- cms_dispense


    end -- get_elec_mon_dc_ok() and 
        

    update_countermeasures_display()
end -- update()

function SetCommand(command, value)

    if command == device_commands.cm_pwr then
        cm_enabled = (value > 0) and true or false

    elseif command == device_commands.cm_bank then
        if value == -1 then cm_banksel = 1 -- bank 1
        elseif value == 1 then cm_banksel = 2 -- bank 2
        else cm_banksel = 3 -- both
        end

    elseif command == device_commands.cm_auto then
        cm_auto = (value > 0) and true or false

    elseif command == device_commands.cm_adj1 then
        --print_message_to_user("value = "..value)
        cm_bank1_show = round(cm_bank1_show + 5*value)
        cm_bank1_show = cm_bank1_show % 100

    elseif command == device_commands.cm_adj2 then
        --print_message_to_user("value = "..value)
        cm_bank2_show = round(cm_bank2_show + 5*value)
        cm_bank2_show = cm_bank2_show % 100

    elseif command == Keys.CmDrop then
        if cm_enabled and get_elec_mon_dc_ok() then
            debug_print("dispense set to true")
            cms_dispense = true
            if cm_banksel == 1 or cm_banksel == 3 then
                chaff_count = CMS:get_chaff_count()
                if chaff_count > 0 then
                    -- CMS:drop_chaff(1, chaff_pos)  -- first param is count, second param is dispenser number (see chaff_flare_dispenser in aircraft definition)
                    cm_bank1_show = (cm_bank1_show - 1) % 100
                end
            end
            if cm_banksel == 2 or cm_banksel == 3 then
                flare_count = CMS:get_flare_count()
                if flare_count > 0 then
                    -- CMS:drop_flare(1, flare_pos)  -- first param is count, second param is dispenser number (see chaff_flare_dispenser in aircraft definition)
                    cm_bank2_show = (cm_bank2_show - 1) % 100
                end
            end
        end

    elseif command == Keys.CmBankSelect then
        CMS:performClickableAction(device_commands.cm_bank, value, false)

    elseif command == Keys.CmBankSelectRotate then
        --up goes to middle (0), middle goes to down (+1), down goes to up (-1)
        if cm_banksel == 1 then
            CMS:performClickableAction(device_commands.cm_bank, 0, false)
        elseif cm_banksel == 2 then
            CMS:performClickableAction(device_commands.cm_bank, -1, false)
        elseif cm_banksel == 3 then
            CMS:performClickableAction(device_commands.cm_bank, 1, false)
        end

    elseif command == Keys.CmAutoModeToggle then
        if cm_auto then
            CMS:performClickableAction(device_commands.cm_auto, 0, false)
        else
            CMS:performClickableAction(device_commands.cm_auto, 1, false)
        end

    elseif command == Keys.CmBank1AdjUp then
        CMS:performClickableAction(device_commands.cm_adj1, 0.15, false)

    elseif command == Keys.CmBank1AdjDown then
        CMS:performClickableAction(device_commands.cm_adj1, -0.15, false)
    
    elseif command == Keys.CmBank2AdjUp then
        CMS:performClickableAction(device_commands.cm_adj2, 0.15, false)
    
    elseif command == Keys.CmBank2AdjDown then
        CMS:performClickableAction(device_commands.cm_adj2, -0.15, false)
    
    elseif command == Keys.CmPowerToggle then
        if cm_enabled then
            CMS:performClickableAction(device_commands.cm_pwr, 0, false)
        else
            CMS:performClickableAction(device_commands.cm_pwr, 1, false)
        end
    
    elseif command == iCommandActiveJamming then
        if ECM_status then
            CMS:set_ECM_status(false)
        else
            CMS:set_ECM_status(true)
        end
    end
end -- setCommand()

startup_print("countermeasures: load complete")

need_to_be_closed = false -- close lua state after initialization
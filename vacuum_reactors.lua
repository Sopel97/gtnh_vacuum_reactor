local computer = require("computer")
local component = require("component")
local sides = require("sides")
local event = require("event")
local term = require("term")

local gpu = component.gpu

local REACTOR_COMPONENT_UNKNOWN = 0
local REACTOR_COMPONENT_COOLANT_CELL = 1
local REACTOR_COMPONENT_FUEL_ROD = 2

local REACTOR_COMPONENT_CLASSIFICATION = {
    ["IC2:reactorCoolantSimple"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["IC2:reactorCoolantTriple"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["IC2:reactorCoolantSix"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.60k_NaK_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.180k_NaK_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.360k_NaK_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.60k_Helium_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.180k_Helium_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.360k_Helium_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.180k_Space_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.360k_Space_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.540k_Space_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.1080k_Space_Coolantcell"] = REACTOR_COMPONENT_COOLANT_CELL,
    ["gregtech:gt.reactorUraniumSimple"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.reactorUraniumDual"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.reactorUraniumQuad"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.Thoriumcell"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.Double_Thoriumcell"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.Quad_Thoriumcell"] = REACTOR_COMPONENT_FUEL_ROD,
    ["IC2:reactorUraniumSimpledepleted"] = REACTOR_COMPONENT_FUEL_ROD,
    ["IC2:reactorUraniumDualdepleted"] = REACTOR_COMPONENT_FUEL_ROD,
    ["IC2:reactorUraniumQuaddepleted"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.Thoriumcelldep"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.Double_Thoriumcelldep"] = REACTOR_COMPONENT_FUEL_ROD,
    ["gregtech:gt.Quad_Thoriumcelldep"] = REACTOR_COMPONENT_FUEL_ROD,
}

local REACTOR_FUEL_ROD_DEPLETED = {
    ["IC2:reactorUraniumSimpledepleted"] = true,
    ["IC2:reactorUraniumDualdepleted"] = true,
    ["IC2:reactorUraniumQuaddepleted"] = true,
    ["gregtech:gt.Thoriumcelldep"] = true,
    ["gregtech:gt.Double_Thoriumcelldep"] = true,
    ["gregtech:gt.Quad_Thoriumcelldep"] = true,
    -- idk make a PR with the rest or smth I don't care myself
}

local function classify_reactor_item(item)
    local classification = REACTOR_COMPONENT_CLASSIFICATION[item.name]
    if classification == nil then
        classification = REACTOR_COMPONENT_UNKNOWN
    end
    return classification
end

local function print_table(tbl)
    for k, v in pairs(tbl) do
        print(tostring(k) .. ": " .. tostring(v))
    end
end

local function get_short_address(component)
    return string.sub(component.address, 1, 8)
end

local C = REACTOR_COMPONENT_COOLANT_CELL
local R = REACTOR_COMPONENT_FUEL_ROD
local U = REACTOR_COMPONENT_UNKNOWN

-- erp=BCEj5P3DyjOJIWP/m9OQN1GXSMrIH6aXuU6m1XksoaLtro68rJkpMeaigDB71vzXY/WCrVrkAEd+xzKsA5Vm2mfVEv8qj8+Px9Nah63IfEtoOglJD20KUjLu/eQ1TwBsg1PF+0nzb0ZyC5+cd+y/s8s9zAqWjwTwTuSR05z+QkYufhYpGDHU3ZPv+RSQSsR+DgM=
local REACTOR_PATTERN = {
    { C, R, R, R, C, R, R, C, R },
    { R, R, C, R, R, R, R, C, R },
    { C, R, R, R, R, C, R, R, R },
    { U, R, R, C, R, R, R, R, C },
    { U, C, R, R, R, R, C, R, R },
    { U, C, R, R, C, R, R, R, C }
}

local REACTOR_ROWS = #REACTOR_PATTERN
local REACTOR_COLS = #(REACTOR_PATTERN[1])

local REACTOR_SIZE = REACTOR_ROWS * REACTOR_COLS

local REACTOR_HEAT_READINGS_UPDATE_PERIOD = 3
local REACTOR_OUTPUT_READINGS_UPDATE_PERIOD = 10
local LSC_READINGS_UPDATE_PERIOD = 10
local DASHBOARD_UPDATE_PERIOD = 2

local LSC_HYSTERESIS_MIN = 0.5
local LSC_HYSTERESIS_MAX = 0.95

local COOLING_CELL_DEPLETED_THRESHOLD = 0.95 -- USE AT LEAST 360k COOLANT CELLS!!!
local MAX_REACTOR_OPERATING_HEAT_PCT = 0.5
local MAX_REPLACED_COOLANT_PER_TICK = 8

local START_UPTIME = computer.uptime()

local LOGS = {}
local LOGS_HISTORY_SIZE = 10

local function pop_last_log_message()
    if #LOGS > 0 then
        table.remove(LOGS, 1)
    end
end

local function set_log_history_size(new_size)
    new_size = math.max(new_size, 1)
    LOGS_HISTORY_SIZE = new_size
    while #LOGS >= LOGS_HISTORY_SIZE do
        pop_last_log_message()
    end
end

local function log(log_type, message)
    -- TODO: Maybe real time. I don't like the solution with creating a temporary file and reading its time.
    local full_message = os.date("%Y-%m-%d %X - " .. log_type .. ": " .. message)
    if #LOGS >= LOGS_HISTORY_SIZE then
        pop_last_log_message()
    end
    table.insert(LOGS, full_message)
end

local function log_info(message)
    log("INFO", message)
end

local function log_warning(message)
    log("WARNING", message)
end

local function log_error(message)
    log("ERROR", message)
end

local function is_cooling_cell_depleted(item)
    if item.damage == nil then
        return true
    end

    local depletion = item.damage / item.maxDamage
    return depletion >= COOLING_CELL_DEPLETED_THRESHOLD
end

local function is_fuel_rod_depleted(item)
    local s = REACTOR_FUEL_ROD_DEPLETED[item.name]
    if s ~= nil and s then
        return true
    end
    return false
end

local function get_expected_reactor_component(slot)
    local row = (slot - 1) // REACTOR_COLS + 1
    local col = (slot - 1) % REACTOR_COLS + 1
    return REACTOR_PATTERN[row][col]
end

local function find_slot_for_depleted_cooling_cell(reactor)
    -- We need to find the first empty slot.

    local items = reactor.transposer.getAllStacks(reactor.transposer_sides.depleted_cooling_cells_side)
    local slot = 1
    while true do
        local item = items()
        if item == nil then
            break
        end

        if next(item) == nil then
            return slot
        end

        slot = slot + 1
    end

    return nil
end

local function find_slot_for_depleted_fuel_rod(reactor, rod)
    -- We need to find the first empty slot.

    local items = reactor.transposer.getAllStacks(reactor.transposer_sides.general_provider)
    local slot = 1
    while true do
        local item = items()
        if item == nil then
            break
        end

        if next(item) == nil then
            return slot
        end

        if item.name == rod.name and item.size < 64 then
            return slot
        end

        slot = slot + 1
    end

    return nil
end

local function find_cooling_cell_provider_slot(reactor)
    local items = reactor.transposer.getAllStacks(reactor.transposer_sides.full_cooling_cells_side)
    local slot = 1
    while true do
        local item = items()
        if item == nil then
            break
        end

        if next(item) ~= nil then
            local classification = classify_reactor_item(item)
            if classification == REACTOR_COMPONENT_COOLANT_CELL then
                return slot
            end
        end

        slot = slot + 1
    end

    return nil
end

local function find_fuel_rod_provider_slot(reactor)
    local items = reactor.transposer.getAllStacks(reactor.transposer_sides.general_provider)
    local slot = 1
    while true do
        local item = items()
        if item == nil then
            break
        end

        if next(item) ~= nil then
            local classification = classify_reactor_item(item)
            if classification == REACTOR_COMPONENT_FUEL_ROD and not is_fuel_rod_depleted(item) then
                return slot
            end
        end

        slot = slot + 1
    end

    return nil
end

local function replace_depleted_cooling_cell(reactor, item, slot)
    -- First identify slots that we will use.
    -- This is because we need to perform the transfer as fast as possible, but these calls take time.
    local slot_for_depleted_cooling_cell = nil
    if item ~= nil then
        slot_for_depleted_cooling_cell = find_slot_for_depleted_cooling_cell(reactor)
        if slot_for_depleted_cooling_cell == nil then
            return "No space for depleted cooling cell."
        end
    end

    local new_cooling_cell_slot = find_cooling_cell_provider_slot(reactor)
    if new_cooling_cell_slot == nil then
        return "No cooling cell in the provider."
    end

    if slot_for_depleted_cooling_cell ~= nil then
        reactor.transposer.transferItem(reactor.transposer_sides.reactor_chamber, reactor.transposer_sides.depleted_cooling_cells_side, 1, slot, slot_for_depleted_cooling_cell)
    end

    reactor.transposer.transferItem(reactor.transposer_sides.full_cooling_cells_side, reactor.transposer_sides.reactor_chamber, 1, new_cooling_cell_slot, slot)

    log_info("Replaced cooling cell in reactor " .. get_short_address(reactor.transposer) .. " in slot " .. tostring(slot))

    return nil
end

local function replace_depleted_fuel_rod(reactor, item, slot)
    -- First identify slots that we will use.
    -- This is because we need to perform the transfer as fast as possible, but these calls take time.
    local slot_for_depleted_fuel_rod = nil
    if item ~= nil then
        slot_for_depleted_fuel_rod = find_slot_for_depleted_fuel_rod(reactor, item)
        if slot_for_depleted_fuel_rod == nil then
            return "No space for depleted fuel rod. Shutting down."
        end
    end

    local new_fuel_rod_slot = find_fuel_rod_provider_slot(reactor)
    if new_fuel_rod_slot == nil then
        return "No fuel rod in the provider. Shutting down."
    end

    if slot_for_depleted_fuel_rod ~= nil then
        reactor.transposer.transferItem(reactor.transposer_sides.reactor_chamber, reactor.transposer_sides.general_provider, 1, slot, slot_for_depleted_fuel_rod)
    end

    reactor.transposer.transferItem(reactor.transposer_sides.general_provider, reactor.transposer_sides.reactor_chamber, 1, new_fuel_rod_slot, slot)

    log_info("Replaced fuel rod in reactor " .. get_short_address(reactor.transposer) .. " in slot " .. tostring(slot))

    return nil
end

local function try_replace_coolant(reactor, reactor_items)
    local n_replaced = 0
    for i=0,53 do
        local slot = i + 1
        local item = reactor_items[i]

        local expected_classification = get_expected_reactor_component(slot)
        if expected_classification == REACTOR_COMPONENT_COOLANT_CELL then
            if item == nil or next(item) == nil or is_cooling_cell_depleted(item) then
                local error = replace_depleted_cooling_cell(reactor, item, slot)
                if error ~= nil then
                    return error
                end
                n_replaced = n_replaced + 1
                if n_replaced >= MAX_REPLACED_COOLANT_PER_TICK then
                    break
                end
            end
        end
    end

    return nil
end

local function try_replace_one_fuel_rod(reactor, reactor_items)
    for i=0,53 do
        local slot = i + 1
        local item = reactor_items[i]

        local expected_classification = get_expected_reactor_component(slot)
        if expected_classification == REACTOR_COMPONENT_FUEL_ROD then
            if item == nil or next(item) == nil or is_fuel_rod_depleted(item) then
                return replace_depleted_fuel_rod(reactor, item, slot)
            end
        end
    end

    return nil
end

local function parse_fuzzy_int(str)
    local filtered_str = string.gsub(str, "([^0-9]+)", "")
    return math.floor(tonumber(filtered_str))
end

local function print_table(tbl)
    for k, v in pairs(tbl) do
        print(tostring(k) .. ": " .. tostring(v))
    end
end

local function get_lsc_proxy()
    local gt_machines = component.list("gt_machine", true)

    for address, component_name in pairs(gt_machines) do
        local proxy = component.proxy(address)
        local machine_name = proxy.getName()
        print("Found gt_machine: " .. machine_name)
        if machine_name == "multimachine.supercapacitor" then
            print("Found LSC: " .. address)
            return proxy
        end
    end

    return nil
end

local function is_item_stack_empty(item_stack)
    return next(item_stack) == nil
end

local function get_last_occupied_slot_id(transposer_proxy, side)
    local slots = transposer_proxy.getAllStacks(side).getAll()
    local last_slot_id = -1
    for slot_id, item_stack in pairs(slots) do
        if not is_item_stack_empty(item_stack) and slot_id > last_slot_id then
            last_slot_id = slot_id
        end
    end
    -- Convert to 1-based indexing
    if last_slot_id == -1 then
        return nil
    else
        return last_slot_id + 1
    end
end

local function is_inventory_empty(transposer_proxy, side)
    local slots = transposer_proxy.getAllStacks(side).getAll()
    for slot_id, item_stack in pairs(slots) do
        if not is_item_stack_empty(item_stack) then
            return false
        end
    end
    return true
end

local function transfer_inventory(transposer_proxy, source_side, destination_side)
    if source_side == destination_side then
        return
    end

    local last_slot_id = get_last_occupied_slot_id(transposer_proxy, source_side)

    if last_slot_id == nil then
        return
    end

    local destination_size = transposer_proxy.getInventorySize(destination_side)

    if last_slot_id > destination_size then
        error("Insufficient space in the destination inventory.")
    end

    if not is_inventory_empty(transposer_proxy, destination_side) then
        error("Destination inventory is not empty.")
    end

    for slot_id = 1, last_slot_id do
        transposer_proxy.transferItem(source_side, destination_side, 64, slot_id, slot_id)
    end
end

local function get_transposer_sides(transposer_proxy)
    local transposer_sides = {}

    for side=0,5 do
        local name = transposer_proxy.getInventoryName(side)
        if name ~= nil then
            local size = transposer_proxy.getInventorySize(side)
            if name == "blockReactorChamber" then
                print("Found reactor chamber inventory with " .. tostring(size) .. " slots.")
                if size ~= REACTOR_SIZE then
                    error("Reactor chamber size mismatches configuration.")
                end
                transposer_sides.reactor_chamber = side
            elseif name == "tile.IronChest" then
                print("Found temporary storage inventory with " .. tostring(size) .. " slots.")
                transposer_sides.temp_storage = side
            elseif name == "tile.appliedenergistics2.BlockInterface" then
                print("Found general provider inventory with " .. tostring(size) .. " slots.")
                transposer_sides.general_provider = side
            elseif name == "tile.chest" then
                local items = transposer_proxy.getAllStacks(side)
                while true do
                    local item = items()
                    if item == nil then
                        break
                    end

                    if next(item) ~= nil then
                        local classification = classify_reactor_item(item)
                        if classification == REACTOR_COMPONENT_COOLANT_CELL and not is_cooling_cell_depleted(item) then
                            print("Found chest for full cooling cells with " .. tostring(size) .. " slots.")
                            if transposer_sides.full_cooling_cells_side ~= nil then
                                error("Found multiple chests for full cooling cells.")
                            end
                            transposer_sides.full_cooling_cells_side = side
                            break
                        end
                    end
                end

                if transposer_sides.full_cooling_cells_side ~= side then
                    print("Found chest for depleted cooling cells with " .. tostring(size) .. " slots.")
                    if transposer_sides.depleted_cooling_cells_side ~= nil then
                        error("Found multiple chests for depleted cooling cells.")
                    end
                    transposer_sides.depleted_cooling_cells_side = side
                end
            end
        end
    end

    return transposer_sides
end

local function is_reactor_transposer(transposer_sides)
    return transposer_sides.reactor_chamber ~= nil and transposer_sides.temp_storage ~= nil and transposer_sides.general_provider ~= nil and transposer_sides.full_cooling_cells_side ~= nil and transposer_sides.depleted_cooling_cells_side ~= nil
end

local function store_reactor_chamber(reactor_transposer)
    -- The transposer must have a reactor chamber and exactly one iron chest attached.
    transfer_inventory(reactor_transposer.proxy, reactor_transposer.sides.reactor_chamber, reactor_transposer.sides.temp_storage)
end

local function load_reactor_chamber(reactor_transposer)
    -- The transposer must have a reactor chamber and exactly one iron chest attached.
    transfer_inventory(reactor_transposer.proxy, reactor_transposer.sides.temp_storage, reactor_transposer.sides.reactor_chamber)
end

local function find_reactor_chambers()
    local reactor_chambers = {}

    for address, name in component.list("reactor_chamber", "true") do
        local proxy = component.proxy(address)
        print("Found reactor chamber: " .. address)
        table.insert(reactor_chambers, proxy)
    end

    return reactor_chambers
end

local function find_reactor_transposers()
    local reactor_transposers = {}

    for address, name in component.list("transposer", true) do
        local proxy = component.proxy(address)
        local sides = get_transposer_sides(proxy)
        if is_reactor_transposer(sides) then
            print("Found reactor transposer: " .. address)
            table.insert(reactor_transposers, {
                proxy = proxy,
                sides = sides
            })
        end
    end

    return reactor_transposers
end

local function find_redstone_ios()
    local redstone_ios = {}

    for address, name in component.list("redstone", "true") do
        local proxy = component.proxy(address)
        print("Found redstone I/O: " .. address)
        table.insert(redstone_ios, proxy)
    end

    return redstone_ios
end

local function find_reactor_plating_slot(transposer_proxy, side)
    local slots = transposer_proxy.getAllStacks(side).getAll()
    for slot_id, item_stack in pairs(slots) do
        if not is_item_stack_empty(item_stack) and item_stack.name == "IC2:reactorPlating" then
            return slot_id + 1
        end
    end
    return nil
end

local function identify_controlled_reactors(reactor_chambers, reactor_transposers, redstone_ios)
    local reactors = {}

    print("Attempting to identify controlled reactors.")

    print("Disabling all redstone IOs.")

    -- Make sure all reactors are disabled
    for _, redstone_io in ipairs(redstone_ios) do
        redstone_io.setOutput({ 0, 0, 0, 0, 0, 0 })
    end

    for _, redstone_io in ipairs(redstone_ios) do
        print("Searching for a Reactor Chamber matching Redstone IO [" .. redstone_io.address .. "].")
        redstone_io.setOutput({ 15, 15, 15, 15, 15, 15 })

        os.sleep(1.2) -- wait for the reactor to turn on

        local found = false
        for _, reactor_chamber in ipairs(reactor_chambers) do
            if reactor_chamber.producesEnergy() then
                if found then
                    error("Found multiple Reactor Chambers connected to a single Redstone IO [" .. redstone_io.address .. "].")
                end

                print("Found Reactor Chamber [" .. reactor_chamber.address .. "] matching Redstone IO [" .. redstone_io.address .. "].")

                table.insert(reactors, {
                    redstone_io = redstone_io,
                    reactor_chamber = reactor_chamber,
                    base_max_heat = reactor_chamber.getMaxHeat(),
                    max_observed_heat = reactor_chamber.getHeat(),
                })

                found = true
            end
        end

        redstone_io.setOutput({ 0, 0, 0, 0, 0, 0 })
    end

    for _, reactor_transposer in ipairs(reactor_transposers) do
        print("Searching for a Reactor Chamber matching Transposer [" .. reactor_transposer.proxy.address .. "].")

        local reactor_plating_slot = find_reactor_plating_slot(reactor_transposer.proxy, reactor_transposer.sides.general_provider)
        if reactor_plating_slot == nil then
            error("Could not find reactor plating item in the general provider inventory.")
        end

        reactor_transposer.proxy.transferItem(reactor_transposer.sides.general_provider, reactor_transposer.sides.reactor_chamber, 1, reactor_plating_slot, 1)

        os.sleep(1.2) -- wait for the reactor to update

        local found = false
        for _, reactor in ipairs(reactors) do
            if reactor.reactor_chamber.getMaxHeat() > reactor.base_max_heat then
                if found then
                    error("Found multiple Reactor Chambers connected to a single Transposer [" .. reactor_transposer.proxy.address .. "].")
                end

                print("Found Reactor Chamber [" .. reactor.reactor_chamber.address .. "] matching Transposer [" .. reactor_transposer.proxy.address .. "].")

                reactor.transposer = reactor_transposer.proxy
                reactor.transposer_sides = reactor_transposer.sides

                found = true
            end
        end

        reactor_transposer.proxy.transferItem(reactor_transposer.sides.reactor_chamber, reactor_transposer.sides.general_provider, 1, 1, reactor_plating_slot)
    end

    for _, reactor in ipairs(reactors) do
        if reactor.redstone_io == nil then
            error("Found reactor without redstone IO.")
        end

        if reactor.reactor_chamber == nil then
            error("Found reactor without reactor chamber.")
        end

        if reactor.transposer == nil then
            error("Found reactor without transposer.")
        end

        -- Populate with all required information
        reactor.enabled = true
        reactor.status = reactor.reactor_chamber.producesEnergy() and "Working" or "Idle"
        reactor.current_heat = reactor.reactor_chamber.getHeat()
        reactor.max_heat = reactor.reactor_chamber.getMaxHeat()
        reactor.output_eut = reactor.reactor_chamber.getReactorEUOutput()

        print("Found reactor: \n\t - Reactor chamber: " .. reactor.reactor_chamber.address .. "\n\t - Transposer: " .. reactor.transposer.address .. "\n\t - Redstone IO: " .. reactor.redstone_io.address)
    end

    return reactors
end

local function set_reactor_enabled(reactor, enabled)
    local redstone = reactor.redstone_io
    if enabled then
        if redstone.getOutput(sides.top) ~= 15 then
            redstone.setOutput({ 15, 15, 15, 15, 15, 15 })
            log_info("Enabled reactor " .. get_short_address(reactor.transposer))
        end
    else
        if redstone.getOutput(sides.top) ~= 0 then
            redstone.setOutput({ 0, 0, 0, 0, 0, 0 })
            log_info("Disabled reactor " .. get_short_address(reactor.transposer))
        end
    end
end

local function set_reactors_enabled(reactors, enabled)
    for _, reactor in ipairs(reactors) do
        set_reactor_enabled(reactor, enabled)
    end
end

local function initialize_reactors()
    print("Initializing reactors...")

    local reactor_chambers = find_reactor_chambers()
    local reactor_transposers = find_reactor_transposers()
    local redstone_ios = find_redstone_ios()

    for _, reactor_transposer in ipairs(reactor_transposers) do
        print("Storing reactor chamber for transposer: " .. reactor_transposer.proxy.address)
        store_reactor_chamber(reactor_transposer)
    end

    local reactors = identify_controlled_reactors(reactor_chambers, reactor_transposers, redstone_ios)

    set_reactors_enabled(reactors, false)

    for _, reactor_transposer in ipairs(reactor_transposers) do
        print("Loading reactor chamber for transposer: " .. reactor_transposer.proxy.address)
        load_reactor_chamber(reactor_transposer)
    end

    return reactors
end

local function is_reactor_inventory_in_operating_condition(reactor, reactor_items)
    if reactor.current_heat >= reactor.max_heat * MAX_REACTOR_OPERATING_HEAT_PCT then
        return false, "SHUTDOWN: Reactor overheated."
    end

    for i=0,53 do
        local slot = i + 1
        local item = reactor_items[i]

        local classification = classify_reactor_item(item)
        local expected_classification = get_expected_reactor_component(slot)
        if classification ~= expected_classification then
            return false, "SHUTDOWN: Invalid component."
        end
    end
    return true, nil
end

local function update_reactor_heat_readings(reactor)
    reactor.current_heat = reactor.reactor_chamber.getHeat()
end

local function update_reactor_output_readings(reactor)
    reactor.output_eut = reactor.reactor_chamber.getReactorEUOutput()
end

local function tick_reactor(reactor, tick, should_work)
    if tick % REACTOR_HEAT_READINGS_UPDATE_PERIOD == 0 then
        update_reactor_heat_readings(reactor)
    end

    if tick % REACTOR_OUTPUT_READINGS_UPDATE_PERIOD == 0 then
        update_reactor_output_readings(reactor)
    end

    local reactor_items = reactor.transposer.getAllStacks(reactor.transposer_sides.reactor_chamber).getAll()

    local is_ok, status = is_reactor_inventory_in_operating_condition(reactor, reactor_items)
    should_work = should_work and reactor.enabled and is_ok
    set_reactor_enabled(reactor, should_work)

    if status == nil then
        status = should_work and "Working" or "Idle"
    end
    reactor.status = status

    local error = try_replace_coolant(reactor, reactor_items)
    if error ~= nil then
        set_reactor_enabled(reactor, false)
        reactor.enabled = false
        reactor.status = "ERROR: " .. error
        log_error(get_short_address(reactor.transposer) .. " " .. error)
        log_info("Reactor " .. get_short_address(reactor.transposer) .. " put offline due to error.")
    end

    -- Throttle rod replacement, because coolant is the most important.
    local error = try_replace_one_fuel_rod(reactor, reactor_items)
    if error ~= nil then
        set_reactor_enabled(reactor, false)
        reactor.enabled = false
        reactor.status = "ERROR: " .. error
        log_error(get_short_address(reactor.transposer) .. " " .. error)
        log_info("Reactor " .. get_short_address(reactor.transposer) .. " put offline due to error.")
    end
end

local function tick_reactors(lsc, reactors, tick)
    local should_work = lsc.needs_powergen
    for _, reactor in ipairs(reactors) do
        tick_reactor(reactor, tick, should_work)
    end
end

local function update_lsc_readings(lsc)
    local sensor_info = lsc.controller.getSensorInformation()
    lsc.status = {
        used_capacity_eu = parse_fuzzy_int(sensor_info[2]),
        total_capacity_eu = parse_fuzzy_int(sensor_info[3]),
        passive_loss_eut = parse_fuzzy_int(sensor_info[4]),
        avg_input_eut = parse_fuzzy_int(string.gsub(sensor_info[7], "(last 5 seconds)", "")),
        avg_output_eut = parse_fuzzy_int(string.gsub(sensor_info[8], "(last 5 seconds)", "")),
        needs_maintenance = (string.find(sensor_info[9], "Has Problems") ~= nil)
    }

    if lsc.needs_powergen == nil then
        lsc.needs_powergen = false
    end

    local used_capacity_pct = lsc.status.used_capacity_eu / lsc.status.total_capacity_eu
    if not lsc.needs_powergen and used_capacity_pct < LSC_HYSTERESIS_MIN then
        log_info("LSC drained to lower energy limit.")
        lsc.needs_powergen = true
    elseif lsc.needs_powergen and used_capacity_pct > LSC_HYSTERESIS_MAX then
        log_info("LSC filled to upper energy limit.")
        lsc.needs_powergen = false
    end
end

local function tick_lsc(lsc, tick)
    if tick % LSC_READINGS_UPDATE_PERIOD == 0 then
        update_lsc_readings(lsc)
    end
end

local function rect_contains_point(min_x, min_y, max_x, max_y, x, y)
    return x >= min_x and y >= min_y and x <= max_x and y <= max_y
end

local function widget_contains_point(widget, x, y)
    return rect_contains_point(widget.min_x, widget.min_y, widget.max_x, widget.max_y, x, y)
end

local function draw_widgets(widgets, tick)
    for _, widget in ipairs(widgets) do
        widget.draw(widget, tick)
    end
end

local DEFAULT_FRAME_CHARSET = {
    vertical = "│",
    horizontal = "─",
    top_left = "╭",
    top_right = "╮",
    bottom_left = "╰",
    bottom_right = "╯"
}

local function draw_window(title, min_x, min_y, max_x, max_y, frame_charset)
    if frame_charset == nil then
        frame_charset = DEFAULT_FRAME_CHARSET
    end

    gpu.set(min_x, min_y, frame_charset.top_left)
    gpu.set(min_x, max_y, frame_charset.bottom_left)
    gpu.set(max_x, min_y, frame_charset.top_right)
    gpu.set(max_x, max_y, frame_charset.bottom_right)
    gpu.fill(min_x + 1, min_y, max_x - min_x - 1, 1, frame_charset.horizontal)
    gpu.fill(min_x + 1, max_y, max_x - min_x - 1, 1, frame_charset.horizontal)
    gpu.fill(min_x, min_y + 1, 1, max_y - min_y - 1, frame_charset.vertical)
    gpu.fill(max_x, min_y + 1, 1, max_y - min_y - 1, frame_charset.vertical)

    -- TODO: trim, maybe center
    gpu.set(min_x + 2, min_y, title)
end

local function format_seconds(seconds_total)
    seconds_total = math.floor(seconds_total)
    local hours = math.floor(seconds_total / 3600)
    local minutes = math.floor((seconds_total - hours * 3600) / 60)
    local seconds = seconds_total % 60

    return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function create_widgets(lsc, reactors)
    local screen_width, screen_height = gpu.getResolution()
    local widgets = {}

    local y = 2

    local lsc_widget = {
        name = "lsc_widget",
        min_x = 2,
        min_y = y,
        max_x = screen_width - 1,
        max_y = y + 7,
        lsc = lsc,
        on_touch = function(widget, x, y) end,
        draw = function(widget, tick)
            local uptime = computer.uptime() - START_UPTIME

            local lsc = widget.lsc
            local lsc_status = lsc.status
            local lsc_fill_pct = math.floor(lsc_status.used_capacity_eu / lsc_status.total_capacity_eu * 100)

            local empty_or_full_message = ""
            local average_net_input_eut = lsc_status.avg_input_eut - lsc_status.avg_output_eut - lsc_status.passive_loss_eut
            if average_net_input_eut > 0 then
                local full_in_seconds = (lsc_status.total_capacity_eu - lsc_status.used_capacity_eu) / average_net_input_eut / 20
                empty_or_full_message = "; Full in " .. format_seconds(full_in_seconds)
            elseif average_net_input_eut < 0 then
                local empty_in_seconds = lsc_status.used_capacity_eu / -average_net_input_eut / 20
                empty_or_full_message = "; Empty in " .. format_seconds(full_in_seconds)
            end

            draw_window("LSC", widget.min_x, widget.min_y, widget.max_x, widget.max_y)
            gpu.set(widget.min_x + 2, widget.min_y + 1, "Tick: " .. tostring(tick) .. "; Uptime: " .. string.format("%.02f", uptime) .. "s")
            gpu.set(widget.min_x + 2, widget.min_y + 2, "LSC: " .. tostring(lsc_status.used_capacity_eu) .. "EU / " .. tostring(lsc_status.total_capacity_eu) .. "EU   (" .. tostring(lsc_fill_pct) .. "%)")
            gpu.set(widget.min_x + 2, widget.min_y + 3, "Passive loss: " .. tostring(lsc_status.passive_loss_eut) .. "EU/t")
            gpu.set(widget.min_x + 2, widget.min_y + 4, "I/O [EU/t]: +" .. tostring(lsc_status.avg_input_eut) .. " -" .. tostring(lsc_status.avg_output_eut) .. " -" .. tostring(lsc_status.passive_loss_eut) .. " = " .. tostring(avg_net_input_eut) .. "EU/t" .. empty_or_full_message)
            gpu.set(widget.min_x + 2, widget.min_y + 5, "LSC needs maintenenance: " .. tostring(lsc_status.needs_maintenance))
            gpu.set(widget.min_x + 2, widget.min_y + 6, "LSC needs powergen: " .. tostring(lsc.needs_powergen))
        end
    }
    table.insert(widgets, lsc_widget)

    y = y + 7 + 2
    -- later allow clicking a row to go into a detailed overview ?
        -- unless would be too laggy
        -- render the reactor
        -- calculate estimated stats
    local num_reactors = #reactors
    local reactors_widget = {
        name = "reactors_widget",
        min_x = 2,
        min_y = y,
        max_x = screen_width - 2,
        max_y = y + num_reactors + 2,
        reactors = reactors,
        on_touch = function(widget, x, y)
            local i = 1 + y - (widget.min_y + 2)
            local reactors = widget.reactors
            if i >= 1 and i <= #reactors then
                local reactor = reactors[i]
                reactor.enabled = not reactor.enabled
                if reactor.enabled then
                    log_info("Reactor " .. get_short_address(reactor.transposer) .. " put online by user.")
                else
                    log_info("Reactor " .. get_short_address(reactor.transposer) .. " put offline by user.")
                end
            end
        end,
        draw = function(widget, tick)
            local reactor_display_header_line1 = "   │ Transposer │   Output   │ Heat │ Status"
            local reactor_display_header_line2 = "───┼────────────┼────────────┼──────┼──────────────────────────────────────────"
            local reactor_display_format = " %s | %8s   | %6dEU/t │ %3d%% │ %s"

            gpu.set(widget.min_x, widget.min_y, reactor_display_header_line1)
            gpu.set(widget.min_x, widget.min_y + 1, reactor_display_header_line2)

            local yy = widget.min_y + 2
            local reactors = widget.reactors
            for _, reactor in ipairs(reactors) do
                local eut = reactor.output_eut
                local heat_pct = math.floor(reactor.current_heat / reactor.max_heat * 100)
                local enabled = reactor.enabled and "☑" or "☐"
                local status = reactor.status
                local transposer_uuid8 = get_short_address(reactor.transposer)

                local background_color = 0x000000
                if reactor.enabled and status == "Working" then
                    background_color = 0x00FF00
                elseif reactor.enabled and status == "Idle" then
                    background_color = 0x0077EE
                elseif not reactor.enabled then
                    background_color = 0xFF0000
                end

                local old_background_color, was_pallete = gpu.setBackground(background_color)
                gpu.fill(widget.min_x, yy, widget.max_x - widget.min_x - 1, 1, " ")
                gpu.set(widget.min_x, yy, string.format(reactor_display_format, enabled, transposer_uuid8, eut, heat_pct, status))
                gpu.setBackground(old_background_color, was_pallete)

                yy = yy + 1
            end
        end
    }
    table.insert(widgets, reactors_widget)

    y = y + num_reactors + 2 + 1
    set_log_history_size(screen_height - y)
    local logs_widget = {
        name = "logs_widget",
        min_x = 1,
        min_y = y,
        max_x = screen_width - 1,
        max_y = screen_height,
        on_touch = function(widget, x, y) end,
        draw = function(widget, tick)
            gpu.set(widget.min_x, widget.min_y, "LOGS:")
            for i, msg in ipairs(LOGS) do
                gpu.set(widget.min_x, widget.min_y + i, LOGS[i])
            end
        end
    }
    table.insert(widgets, logs_widget)

    return widgets
end

local function render_dashboard(widgets, tick)
    if tick % DASHBOARD_UPDATE_PERIOD == 0 then
        term.clear()
        draw_widgets(widgets, tick)
    end
end

local function computer_has_sufficient_energy()
    local current_energy = computer.energy()
    local max_energy = computer.maxEnergy()
    return current_energy > max_energy * 0.5
end

local function main()

    local resx, resy = gpu.maxResolution()
    if resx < 80 or resy < 25 then
        error("Insufficient screen size. At least 80x25 is required.")
    end

    -- Maybe support other resolutions in the future.
    gpu.setResolution(80, 25)

    local lsc = { controller = get_lsc_proxy() }
    update_lsc_readings(lsc)

    local reactors = initialize_reactors()

    local widgets = create_widgets(lsc, reactors)

    local function guarded_main()
        set_reactors_enabled(reactors, false)

        local keep_alive = true

        local function on_touch_event(event, address, x, y, button, player)
            for _, widget in ipairs(widgets) do
                if widget_contains_point(widget, x, y) then
                    widget.on_touch(widget, x, y)
                end
            end
        end

        local touch_event_id = event.listen("touch", on_touch_event)
        local interrupted_event_id = event.listen("interrupted", function() keep_alive = false end)

        local tick = 0

        while keep_alive do
            if not computer_has_sufficient_energy() then
                error("Insufficient computer energy. Stopping.")
            end

            tick_lsc(lsc, tick)
            tick_reactors(lsc, reactors, tick)

            render_dashboard(widgets, tick)

            event.pull(0)

            tick = tick + 1

            os.sleep(0.05)
        end

        term.clear()
        print("Script interrupted. Executing graceful shutdown...")

        event.cancel(interrupted_event_id)
        event.cancel(touch_event_id)

        set_reactors_enabled(reactors, false)
    end

    local status, err = pcall(guarded_main)
    if not status then
        set_reactors_enabled(reactors, false)
        term.clear()
        print(err)
    end

    set_reactors_enabled(reactors, false)
end

main()
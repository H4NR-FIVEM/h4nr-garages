local menu = exports['feather-menu-v2']
local Notify, Call = GarageCalls.Notify, GarageCalls.Call
RegisterNetEvent('h4nr-garages:notify', function(key)
    Notify(key)
end)
local currentHint
-- E opens the list at the garage point; R parks.
local function Hint(garageId, canOpen, canPark)
    local key = garageId and ('%s:%s:%s'):format(garageId, canOpen, canPark)
    if key == currentHint then
        return
    end
    currentHint = key
    if not key then
        exports['feather-toolkit']:ClearControlHints()
        return
    end
    local controls = {}
    if canOpen then
        controls[#controls + 1] = { key = 'E', label = T('open_label') }
    end
    if canPark then
        controls[#controls + 1] = { key = 'R', label = T('store_label') }
    end
    exports['feather-toolkit']:SetControlHints({
        tabs = { { title = GarageConfig.Garages[garageId].label, controls = controls } },
        activeTab = 1,
    })
end
-- Points are saved at ground or at player height, so the arrow is placed from the ground. The
-- ground is only known once its collision has loaded, and over water it is the seabed.
local markerHeights = { [true] = {}, [false] = {} }
local function MarkerHeight(garage, driving, at)
    local height = markerHeights[driving][garage]
    if not height then
        local found, ground = GetGroundZFor_3dCoord(at.x, at.y, at.z + 2.0, false)
        if not found then
            return at.z + 1.0
        end
        height = math.max(ground, at.z - 1.5) + GarageConfig.Marker.height
        markerHeights[driving][garage] = height
    end
    return height
end
local function Marker(garage, driving, at)
    local spec = GarageConfig.Marker
    DrawMarker(
        spec.type,
        at.x,
        at.y,
        MarkerHeight(garage, driving, at),
        0.0,
        0.0,
        0.0,
        180.0,
        0.0,
        0.0,
        spec.scale,
        spec.scale,
        spec.scale,
        spec.color[1],
        spec.color[2],
        spec.color[3],
        spec.color[4],
        true,
        true,
        2,
        false,
        nil,
        nil,
        false
    )
end
local function Park(garageId, assetId, vehicle)
    if Call('store', GarageCalls.StoreParams(garageId, assetId, vehicle)) then
        Notify('parked')
    end
end
-- The empty vehicle the player stands beside, if it is in this garage's range and they hold its
-- key. Prompts only: the server decides again when parking.
local beside = { scannedAt = nil, vehicle = nil, assetId = nil, allowed = false, checkedAt = nil, checking = false }
local function BesideVehicle(coords, garage, spawn)
    local reach = GarageConfig.ParkDistance + GarageConfig.BesideDistance
    if #(coords - garage.coords) > reach and #(coords - spawn) > reach then
        return nil
    end
    local now = GetGameTimer()
    if not beside.scannedAt or now - beside.scannedAt >= 500 then
        beside.scannedAt = now
        local candidate = lib.getClosestVehicle(coords, GarageConfig.BesideDistance, false)
        local assetId = candidate and Entity(candidate).state.h4nrAssetId
        local empty = assetId and GetPedInVehicleSeat(candidate, -1) == 0
        if not empty then
            candidate, assetId = nil, nil
        end
        if beside.vehicle ~= candidate then
            beside.vehicle, beside.assetId, beside.allowed, beside.checkedAt = candidate, assetId, false, nil
        end
    end
    local vehicle, assetId = beside.vehicle, beside.assetId
    if not vehicle or not DoesEntityExist(vehicle) then
        return nil
    end
    local at = GetEntityCoords(vehicle)
    if #(at - garage.coords) > GarageConfig.ParkDistance and #(at - spawn) > GarageConfig.ParkDistance then
        return nil
    end
    if not beside.checking and (not beside.checkedAt or now - beside.checkedAt >= GarageConfig.Key.checkMs) then
        beside.checking, beside.checkedAt = true, now
        CreateThread(function()
            local reply = FeatherRPC:CallAsync('h4nr-garages:canDrive', { assetId = assetId })
            beside.checking = false
            if beside.vehicle == vehicle then
                beside.allowed = type(reply) == 'table' and reply.ok == true and reply.value.allowed == true
            end
        end)
    end
    return beside.allowed and vehicle or nil, assetId
end
local function Resolve(netId)
    local deadline = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(netId) and GetGameTimer() < deadline do
        Wait(50)
    end
    if not NetworkDoesEntityExistWithNetworkId(netId) then
        return nil
    end
    local vehicle = NetToVeh(netId)
    while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < deadline do
        NetworkRequestControlOfEntity(vehicle)
        Wait(50)
    end
    return NetworkHasControlOfEntity(vehicle) and vehicle or nil
end
RegisterNetEvent('h4nr-garages:ready', function(netId, props)
    CreateThread(function()
        local vehicle = Resolve(netId)
        if not vehicle then
            return Notify('failed')
        end
        lib.setVehicleProperties(vehicle, props)
        if GetResourceState('h4nr-fuel') == 'started' then
            exports['h4nr-fuel']:SetFuel(vehicle, props.fuelLevel or 100)
        end
        SetVehicleOnGroundProperly(vehicle)
        SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
        SetVehicleEngineOn(vehicle, false, true, true)
    end)
end)
RegisterNetEvent('h4nr-garages:engine', function(netId, running)
    CreateThread(function()
        local vehicle = Resolve(netId)
        if vehicle and GetPedInVehicleSeat(vehicle, -1) == PlayerPedId() then
            SetVehicleEngineOn(vehicle, running, true, not running)
        end
    end)
end)
-- The server decides from the key. Blocked until it answers, and when it cannot answer.
local drive = { vehicle = nil, allowed = false, checkedAt = nil, checking = false, told = false }
local function DriveAllowed(vehicle, assetId)
    if drive.vehicle ~= vehicle then
        drive.vehicle, drive.allowed, drive.checkedAt, drive.told = vehicle, false, nil, false
    end
    local now = GetGameTimer()
    if not drive.checking and (not drive.checkedAt or now - drive.checkedAt >= GarageConfig.Key.checkMs) then
        drive.checking, drive.checkedAt = true, now
        CreateThread(function()
            local reply = FeatherRPC:CallAsync('h4nr-garages:canDrive', { assetId = assetId })
            drive.checking = false
            if drive.vehicle == vehicle then
                drive.allowed = type(reply) == 'table' and reply.ok == true and reply.value.allowed == true
                if not drive.allowed and not drive.told then
                    drive.told = true
                    Notify('key_not_here')
                elseif drive.allowed then
                    drive.told = false
                end
            end
        end)
    end
    return drive.allowed
end
local function Key(action)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if vehicle == 0 then
        vehicle = lib.getClosestVehicle(GetEntityCoords(PlayerPedId()), 10.0, false)
    end
    if not vehicle then
        return
    end
    local assetId = Entity(vehicle).state.h4nrAssetId
    if not assetId then
        return
    end
    local result = Call('keys', { assetId = assetId, action = action })
    if result and action == 'lock' then
        Notify(result.locked and 'locked' or 'unlocked')
    end
end
-- For panels: the same operation as the engine key, so the key rule applies everywhere.
exports('ToggleEngine', function(vehicle)
    local assetId = Entity(vehicle).state.h4nrAssetId
    local result = assetId and Call('keys', { assetId = assetId, action = 'engine' })
    if not result then
        return nil
    end
    return result.running
end)
RegisterCommand('feathervehiclelock', function()
    CreateThread(function()
        Key('lock')
    end)
end, false)
RegisterCommand('feathervehicleengine', function()
    CreateThread(function()
        Key('engine')
    end)
end, false)
RegisterKeyMapping('feathervehiclelock', T('lock_key'), 'keyboard', 'U')
RegisterKeyMapping('feathervehicleengine', T('engine_key'), 'keyboard', 'G')
CreateThread(function()
    for _, garage in pairs(GarageConfig.Garages) do
        local blip = AddBlipForCoord(garage.coords.x, garage.coords.y, garage.coords.z)
        SetBlipSprite(blip, garage.sprite)
        SetBlipColour(blip, 3)
        SetBlipScale(blip, 0.65)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(garage.label)
        EndTextCommandSetBlipName(blip)
    end
    while true do
        local pause = 500
        local ped = PlayerPedId()
        local shownHint = false
        GaragePanel.Watch(ped, GetEntityCoords(ped))
        if not GaragePanel.Busy() and exports['feather-character']:HasActiveCharacter() then
            local coords, vehicle = GetEntityCoords(ped), GetVehiclePedIsIn(ped, false)
            for garageId, garage in pairs(GarageConfig.Garages) do
                local spawn = vector3(garage.spawn.x, garage.spawn.y, garage.spawn.z)
                local at = vehicle == 0 and garage.coords or spawn
                if #(coords - at) <= GarageConfig.Marker.drawDistance then
                    pause = 0
                    Marker(garage, vehicle ~= 0, at)
                end
                local near = #(coords - garage.coords) <= GarageConfig.Distance
                    or (vehicle ~= 0 and #(coords - spawn) <= 8.0)
                local canPark = vehicle ~= 0
                    and GetPedInVehicleSeat(vehicle, -1) == ped
                    and Entity(vehicle).state.h4nrAssetId ~= nil
                local empty, emptyAsset
                if vehicle == 0 then
                    empty, emptyAsset = BesideVehicle(coords, garage, spawn)
                end
                if (empty or near and (vehicle == 0 or canPark)) and not menu:IsInputCaptured() then
                    pause = 0
                    shownHint = true
                    local canOpen = vehicle == 0 and near
                    Hint(garageId, canOpen, vehicle ~= 0 or empty ~= nil)
                    if canOpen and IsControlJustReleased(0, 38) then
                        Hint(nil)
                        GaragePanel.Open(garageId)
                    elseif IsControlJustReleased(0, 45) or IsControlJustReleased(0, 80) then
                        -- R is 45 on foot and 80 in a vehicle.
                        if empty then
                            Hint(nil)
                            Park(garageId, emptyAsset, empty)
                        elseif vehicle ~= 0 then
                            Hint(nil)
                            local assetId = Entity(vehicle).state.h4nrAssetId
                            if assetId then
                                Park(garageId, assetId, vehicle)
                            else
                                Notify('forbidden')
                            end
                        end
                    end
                    break
                end
            end
        end
        if not shownHint or GaragePanel.Busy() then
            Hint(nil)
        end
        -- Prevent GTA's automatic engine start while the server says it is off, and keep
        -- a driver without the key from moving a car someone else left running.
        local vehicle = GetVehiclePedIsIn(ped, false)
        local assetId = vehicle ~= 0 and Entity(vehicle).state.h4nrAssetId
        if assetId and GetPedInVehicleSeat(vehicle, -1) == ped then
            local allowed = DriveAllowed(vehicle, assetId)
            if not allowed or Entity(vehicle).state.h4nrGarageEngine == false then
                SetVehicleEngineOn(vehicle, false, true, true)
                pause = 0
            end
            if not allowed then
                DisableControlAction(0, 71, true)
                DisableControlAction(0, 72, true)
            end
        else
            drive.vehicle = nil
        end
        Wait(pause)
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        Hint(nil)
    end
end)

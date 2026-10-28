local assets, core = exports['feather-assets'], exports['feather-core']
local live, playersBusy = {}, {}
local function Character(source)
    local result = core:GetSessionContext(source)
    return result.ok and result.value.characterId or nil
end
local function Near(source, coords, margin)
    local ped = GetPlayerPed(source)
    return ped ~= 0 and #(GetEntityCoords(ped) - coords) <= margin
end
local function Vehicle(assetId)
    local entity = live[assetId]
    if entity and DoesEntityExist(entity) then return entity end
    live[assetId] = nil
    for _, candidate in ipairs(GetAllVehicles()) do
        if Entity(candidate).state.h4nrAssetId == assetId then
            live[assetId] = candidate
            return candidate
        end
    end
end
local function Owns(source, assetId)
    local character = Character(source)
    if not character or not Garage.Uuid(assetId) then return false end
    local check = assets:CheckInterest({ assetId = assetId, holderType = 'character', holderId = character })
    return check.ok and check.value.matched and check.value.assetStatus == 'active'
end
local function AtGarage(source, garageId)
    local garage = GarageConfig.Garages[garageId]
    if not garage or GetPlayerRoutingBucket(source) ~= 0 then return nil end
    local spawn = vector3(garage.spawn.x, garage.spawn.y, garage.spawn.z)
    if not Near(source, garage.coords, GarageConfig.Distance + 2) and not Near(source, spawn, 10) then return nil end
    return garage
end
local function SpawnType(model, assetType)
    -- Trusted catalogue supplied by the shop; classify motorcycles and helicopters
    -- on the server via a temporary model entity when FiveM knows no type yet.
    local probe = CreateVehicle(joaat(model), 0.0, 0.0, -200.0, 0.0, true, true)
    if not probe or probe == 0 then return nil end
    local deadline = GetGameTimer() + 3000
    while not DoesEntityExist(probe) and GetGameTimer() < deadline do Wait(50) end
    if not DoesEntityExist(probe) then DeleteEntity(probe); return nil end
    local kind = GetVehicleType(probe)
    DeleteEntity(probe)
    local allowed = { vehicle = { automobile = true, bike = true, trailer = true },
        boat = { boat = true, submarine = true }, aircraft = { heli = true, plane = true } }
    return allowed[assetType] and allowed[assetType][kind] and kind or nil
end
local function List(source, params)
    local garage = AtGarage(source, params.garage)
    local character = Character(source)
    if not garage or not character then return Garage.Err('too_far') end
    if params.cursor ~= nil and (type(params.cursor) ~= 'string' or #params.cursor > 256) then return Garage.Err('invalid_input') end
    local result = assets:ListAssetsByHolder({ holderType = 'character', holderId = character,
        assetType = garage.assetType, limit = 20, cursor = params.cursor })
    if not result.ok then return result end
    local items = {}
    for _, asset in ipairs(result.value.items) do
        local row = Garage.Row(asset.assetId)
        if row and row.status ~= 'registering' then
            items[#items + 1] = { assetId = asset.assetId, model = asset.modelKey,
                plate = asset.identifiers.plate, garage = row.garage, state = row.status,
                available = asset.status == 'active' and row.garage == params.garage }
        end
    end
    return Garage.Ok({ items = items, nextCursor = result.value.nextCursor })
end
-- Coordinates are resolved server-side from current ownership, even when the
-- entity is outside the owner's streaming range. No arbitrary holder is accepted.
local function Locations(source, params)
    local character = Character(source)
    if not character then return Garage.Err('forbidden') end
    if params.cursor ~= nil and not Garage.Uuid(params.cursor) then return Garage.Err('invalid_input') end
    local result = assets:ListAssetsByHolder({ holderType = 'character', holderId = character,
        limit = 50, cursor = params.cursor })
    if not result.ok then return result end
    local entities, items = {}, {}
    local bucket = GetPlayerRoutingBucket(source)
    for _, vehicle in ipairs(GetAllVehicles()) do
        local assetId = Entity(vehicle).state.h4nrAssetId
        if assetId and GetEntityRoutingBucket(vehicle) == bucket then entities[assetId] = vehicle end
    end
    for _, asset in ipairs(result.value.items) do
        local vehicle = entities[asset.assetId]
        if vehicle and asset.managerResource == GetCurrentResourceName() and asset.status ~= 'retired'
            and DoesEntityExist(vehicle) then
            local at = GetEntityCoords(vehicle)
            items[#items + 1] = { assetId = asset.assetId, plate = asset.identifiers and asset.identifiers.plate,
                coords = { x = at.x, y = at.y, z = at.z } }
        end
    end
    if Character(source) ~= character then return Garage.Err('forbidden') end
    return Garage.Ok({ characterId = character, items = items, nextCursor = result.value.nextCursor })
end
local function Retrieve(source, params)
    local garage = AtGarage(source, params.garage)
    if not garage or not Owns(source, params.assetId) then return Garage.Err('forbidden') end
    return Garage.Lock(params.assetId, function()
        local row = Garage.Row(params.assetId)
        local read = assets:GetAsset({ assetId = params.assetId })
        if not row or not read.ok then return Garage.Err('unavailable') end
        local asset = read.value
        if row.garage ~= params.garage or asset.assetType ~= garage.assetType then return Garage.Err('invalid_garage') end
        if Vehicle(params.assetId) then return Garage.Err('already_out') end
        if row.status == 'out' or row.status == 'spawning' or row.status == 'storing' then
            MySQL.update.await("UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ? AND status IN ('out','spawning','storing')", { params.assetId })
            row.status = 'stored'
        end
        if row.status ~= 'stored' then return Garage.Err('busy') end
        for _, other in ipairs(GetAllVehicles()) do
            if #(GetEntityCoords(other) - vector3(garage.spawn.x, garage.spawn.y, garage.spawn.z)) < 4.0 then
                return Garage.Err('spawn_blocked')
            end
        end
        local kind = SpawnType(asset.modelKey, asset.assetType)
        if not kind then return Garage.Err('spawn_failed') end
        if not Owns(source, params.assetId) or not AtGarage(source, params.garage) then return Garage.Err('forbidden') end
        local changed = MySQL.update.await([[UPDATE h4nr_feather_vehicles SET status = 'spawning'
            WHERE asset_id = ? AND status = 'stored']], { params.assetId })
        if changed ~= 1 then return Garage.Err('busy') end
        local props = json.decode(row.props_json)
        props.plate, props.model = asset.identifiers.plate, joaat(asset.modelKey)
        props.fuelLevel = props.fuelLevel or 100.0
        local ok, netId, entity = pcall(FeatherVehicles.spawnVehicle, {
            model = asset.modelKey, type = kind, spawnSource = garage.spawn, props = props, bucket = 0 })
        if not ok or not netId then
            MySQL.update.await("UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ? AND status = 'spawning'", { params.assetId })
            return Garage.Err('spawn_failed')
        end
        live[params.assetId] = entity
        Entity(entity).state:set('h4nrAssetId', params.assetId, true)
        Entity(entity).state:set('h4nrGarageEngine', false, true)
        SetEntityOrphanMode(entity, 2)
        SetVehicleDoorsLocked(entity, 1)
        MySQL.update.await("UPDATE h4nr_feather_vehicles SET status = 'out' WHERE asset_id = ?", { params.assetId })
        if not Owns(source, params.assetId) then
            SetVehicleDoorsLocked(entity, 2)
            return Garage.Err('forbidden')
        end
        TriggerClientEvent('h4nr-garages:ready', source, netId, props)
        return Garage.Ok({ netId = netId })
    end)
end
local function Store(source, params)
    local garage = AtGarage(source, params.garage)
    if not garage or not Owns(source, params.assetId) then return Garage.Err('forbidden') end
    return Garage.Lock(params.assetId, function()
        local vehicle = Vehicle(params.assetId)
        local ped = GetPlayerPed(source)
        local read = assets:GetAsset({ assetId = params.assetId })
        if not vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped or not read.ok
            or read.value.assetType ~= garage.assetType or GetEntityRoutingBucket(vehicle) ~= 0
            or not Near(source, GetEntityCoords(vehicle), 6) then return Garage.Err('forbidden') end
        if type(params.props) ~= 'table' then return Garage.Err('invalid_input') end
        local props = params.props
        props.model, props.plate = joaat(read.value.modelKey), read.value.identifiers.plate
        for key, range in pairs({ engineHealth = {-4000, 1000}, bodyHealth = {0, 1000}, fuelLevel = {0, 100} }) do
            if type(props[key]) ~= 'number' or props[key] ~= props[key] or props[key] < range[1] or props[key] > range[2] then
                return Garage.Err('invalid_input')
            end
        end
        local encoded = json.encode(props)
        if #encoded > 16384 then return Garage.Err('invalid_input') end
        -- Persist before deletion. Recovery never marks a surviving entity stored.
        MySQL.update.await([[UPDATE h4nr_feather_vehicles SET props_json = ?, garage = ?, status = 'storing'
            WHERE asset_id = ?]], { encoded, params.garage, params.assetId })
        DeleteEntity(vehicle)
        local deadline = GetGameTimer() + 3000
        while DoesEntityExist(vehicle) and GetGameTimer() < deadline do Wait(50) end
        if DoesEntityExist(vehicle) then
            MySQL.update.await("UPDATE h4nr_feather_vehicles SET status = 'out' WHERE asset_id = ?", { params.assetId })
            return Garage.Err('unavailable')
        end
        live[params.assetId] = nil
        MySQL.update.await("UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ?", { params.assetId })
        return Garage.Ok(true)
    end)
end
local function Keys(source, params)
    if not Owns(source, params.assetId) then return Garage.Err('forbidden') end
    local vehicle = Vehicle(params.assetId)
    if not vehicle or not Near(source, GetEntityCoords(vehicle), 12)
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(source) then return Garage.Err('too_far') end
    if params.action == 'lock' then
        local locked = GetVehicleDoorLockStatus(vehicle) ~= 2
        SetVehicleDoorsLocked(vehicle, locked and 2 or 1)
        return Garage.Ok({ locked = locked })
    elseif params.action == 'engine' and GetPedInVehicleSeat(vehicle, -1) == GetPlayerPed(source) then
        local running = not Entity(vehicle).state.h4nrGarageEngine
        Entity(vehicle).state:set('h4nrGarageEngine', running, true)
        TriggerClientEvent('h4nr-garages:engine', source, NetworkGetNetworkIdFromEntity(vehicle), running)
        return Garage.Ok({ running = running })
    end
    return Garage.Err('forbidden')
end
for name, handler in pairs({ list = List, locations = Locations, retrieve = Retrieve, store = Store, keys = Keys }) do
    local operation = handler
    FeatherRPC:Register('h4nr-garages:' .. name, function(params, respond, source)
        if not Garage.ready then return respond(Garage.Err('unavailable')) end
        if type(params) ~= 'table' then return respond(Garage.Err('invalid_input')) end
        if playersBusy[source] then return respond(Garage.Err('busy')) end
        playersBusy[source] = true
        local ok, result = pcall(operation, source, params)
        playersBusy[source] = nil
        if not ok then print('[h4nr-garages] request failed: ' .. tostring(result)) end
        respond(ok and result or Garage.Err('unavailable'))
    end)
end
CreateThread(function()
    local ok, problem = pcall(function()
        Garage.Migrate()
        local ready = assets:AwaitReady(30000)
        assert(ready.ok, ready.code)
        local rows = MySQL.query.await("SELECT asset_id FROM h4nr_feather_vehicles WHERE status IN ('spawning','storing','out')") or {}
        for _, row in ipairs(rows) do
            MySQL.update.await('UPDATE h4nr_feather_vehicles SET status = ? WHERE asset_id = ?',
                { Vehicle(row.asset_id) and 'out' or 'stored', row.asset_id })
        end
        Garage.ready = true
    end)
    if not ok then print('[h4nr-garages] startup failed: ' .. tostring(problem)) end
end)

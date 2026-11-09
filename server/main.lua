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
    if entity and DoesEntityExist(entity) then
        return entity
    end
    live[assetId] = nil
    for _, candidate in ipairs(GetAllVehicles()) do
        if Entity(candidate).state.h4nrAssetId == assetId then
            live[assetId] = candidate
            return candidate
        end
    end
end
exports('GetWorkVehicle', function(request)
    if GetInvokingResource() ~= 'petrolist_job' or type(request) ~= 'table' or not Garage.Uuid(request.assetId) then
        return Garage.Err('forbidden')
    end
    local entity = live[request.assetId]
    if not entity or not DoesEntityExist(entity) then return Garage.Err('vehicle_not_out') end
    return Garage.Ok({ netId = NetworkGetNetworkIdFromEntity(entity) })
end)
local function Owns(source, assetId)
    local character = Character(source)
    if not character or not Garage.Uuid(assetId) then
        return false
    end
    local check = assets:CheckInterest({ assetId = assetId, holderType = 'character', holderId = character })
    return check.ok and check.value.matched and check.value.assetStatus == 'active'
end
-- Using a vehicle follows the key, not ownership. See server/keys.lua.
local function CanOperate(source, assetId)
    local character = Character(source)
    if not character or not Garage.Uuid(assetId) then
        return false, 'forbidden'
    end
    local read = assets:GetAsset({ assetId = assetId })
    local owner = read.ok and read.value.status == 'active' and read.value.owner
    if not owner or owner.holderType ~= 'character' then
        return false, 'forbidden'
    end
    if GarageKeys.Allows(character, assetId, owner.holderId) then
        return true
    end
    return false, character == owner.holderId and 'key_not_here' or 'forbidden'
end
-- Answers another resource's question about a live vehicle. The state bag alone proves nothing,
-- because a client that owns an entity can write it: the entity must also be the one this
-- resource knows for that asset, and the asset must be out of the garage.
exports('GetVehicleAccess', function(request)
    if not GarageConfig.TrustedAccessReaders[GetInvokingResource()] or type(request) ~= 'table' then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    local entity = request.entity
    local assetId = type(entity) == 'number' and DoesEntityExist(entity) and Entity(entity).state.h4nrAssetId
    if not Garage.Uuid(assetId) or Vehicle(assetId) ~= entity then
        return Garage.Err('not_registered')
    end
    local row = DB.one('SELECT status FROM h4nr_feather_vehicles WHERE asset_id = ?', assetId)
    local read = assets:GetAsset({ assetId = assetId })
    local owner = read.ok and read.value.status == 'active' and read.value.owner
    if not row or row.status ~= 'out' or not owner or owner.holderType ~= 'character' then
        return Garage.Err('not_registered')
    end
    local character = Character(request.source)
    return Garage.Ok({
        assetId = assetId,
        hasKey = character ~= nil and GarageKeys.Allows(character, assetId, owner.holderId),
    })
end)
function GarageKeys.OnKeyMoved(assetId)
    local vehicle = Vehicle(assetId)
    if vehicle then
        Entity(vehicle).state:set('h4nrGarageEngine', false, true)
    end
end
local function AtGarage(source, garageId)
    local garage = GarageConfig.Garages[garageId]
    if not garage or GetPlayerRoutingBucket(source) ~= 0 then
        return nil
    end
    local spawn = vector3(garage.spawn.x, garage.spawn.y, garage.spawn.z)
    if not Near(source, garage.coords, GarageConfig.Distance + 2) and not Near(source, spawn, 10) then
        return nil
    end
    return garage
end
local function InParkRange(garage, vehicle)
    local at = GetEntityCoords(vehicle)
    local spawn = vector3(garage.spawn.x, garage.spawn.y, garage.spawn.z)
    return #(at - garage.coords) <= GarageConfig.ParkDistance or #(at - spawn) <= GarageConfig.ParkDistance
end
local function SpawnType(model, assetType)
    -- Trusted catalogue supplied by the shop; classify motorcycles and helicopters
    -- on the server via a temporary model entity when FiveM knows no type yet.
    local probe = CreateVehicle(joaat(model), 0.0, 0.0, -200.0, 0.0, true, true)
    if not probe or probe == 0 then
        return nil
    end
    local deadline = GetGameTimer() + 3000
    while not DoesEntityExist(probe) and GetGameTimer() < deadline do
        Wait(50)
    end
    if not DoesEntityExist(probe) then
        DeleteEntity(probe)
        return nil
    end
    local kind = GetVehicleType(probe)
    DeleteEntity(probe)
    local allowed = {
        vehicle = { automobile = true, bike = true, trailer = true },
        boat = { boat = true, submarine = true },
        aircraft = { heli = true, plane = true },
    }
    return allowed[assetType] and allowed[assetType][kind] and kind or nil
end
-- The h4nr-feather state-bag handler passes color1/color2 to SET_VEHICLE_COLOURS, which
-- only takes paint indexes. Custom RGB paint and dents reach the car through the ready event.
local function SpawnProps(props)
    local copy = {}
    for key, value in pairs(props) do
        if key ~= 'deformation' and ((key ~= 'color1' and key ~= 'color2') or type(value) == 'number') then
            copy[key] = value
        end
    end
    return copy
end
local function IsWrecked(vehicle)
    return GetVehicleEngineHealth(vehicle) <= GarageConfig.Wreck.engineHealth
end
-- Seconds until a wreck can go to the service, 0 when it can, nil for a vehicle that is no wreck.
-- The start lives on the entity, so it survives restarting this resource and ends with the wreck.
local function WreckSeconds(vehicle)
    local since = Entity(vehicle).state.h4nrWreckedAt
    if not since or not IsWrecked(vehicle) then
        return nil
    end
    return math.max(0, since + GarageConfig.Wreck.waitSeconds - os.time())
end
-- The state of the last parking, as percentages. A vehicle never parked has none of these.
local function Condition(encoded)
    local ok, props = pcall(json.decode, encoded)
    if not ok or type(props) ~= 'table' then
        return nil
    end
    local function Percent(value, full)
        return type(value) == 'number' and value == value and math.floor(math.max(0, math.min(value / full, 1)) * 100 + 0.5)
            or nil
    end
    return {
        engine = Percent(props.engineHealth, 1000),
        body = Percent(props.bodyHealth, 1000),
        fuel = Percent(props.fuelLevel, 100),
    }
end
local function List(source, params)
    local garage = AtGarage(source, params.garage)
    local character = Character(source)
    if not garage or not character then
        return Garage.Err('too_far')
    end
    if params.cursor ~= nil and (type(params.cursor) ~= 'string' or #params.cursor > 256) then
        return Garage.Err('invalid_input')
    end
    local result = assets:ListAssetsByHolder({
        holderType = 'character',
        holderId = character,
        assetType = garage.assetType,
        limit = 20,
        cursor = params.cursor,
    })
    if not result.ok then
        return result
    end
    local items = {}
    local held = GarageKeys.Held(character)
    for _, asset in ipairs(result.value.items) do
        local row = Garage.Row(asset.assetId)
        if row and row.status ~= 'registering' then
            local vehicle = row.status == 'out' and asset.status == 'active' and Vehicle(asset.assetId)
            local wreck = vehicle and WreckSeconds(vehicle) or nil
            local parkable = vehicle
                and not wreck
                and GetPedInVehicleSeat(vehicle, -1) == 0
                and GetEntityRoutingBucket(vehicle) == 0
                and InParkRange(garage, vehicle)
            items[#items + 1] = {
                assetId = asset.assetId,
                parkNetId = parkable and NetworkGetNetworkIdFromEntity(vehicle) or nil,
                wreck = wreck,
                model = asset.modelKey,
                plate = asset.identifiers.plate,
                garage = row.garage,
                state = row.status,
                onStreet = vehicle and true or false,
                condition = row.status == 'stored' and Condition(row.props_json) or nil,
                available = asset.status == 'active',
                rekey = asset.status == 'active' and GarageKeys.RekeyState(asset.assetId, character, held) or nil,
            }
        end
    end
    -- Slots go with the first page only: the panel reads them once per refresh.
    local slots = not params.cursor and GarageSlots.Snapshot(character, garage.assetType, Vehicle) or nil
    return Garage.Ok({
        items = items,
        nextCursor = result.value.nextCursor,
        rekeyPrice = GarageConfig.Rekey.price,
        slots = slots and slots.limited and slots or nil,
    })
end
-- Coordinates are resolved server-side from current ownership, even when the
-- entity is outside the owner's streaming range. No arbitrary holder is accepted.
local function Locations(source, params)
    local character = Character(source)
    if not character then
        return Garage.Err('forbidden')
    end
    if params.cursor ~= nil and not Garage.Uuid(params.cursor) then
        return Garage.Err('invalid_input')
    end
    local result = assets:ListAssetsByHolder({
        holderType = 'character',
        holderId = character,
        limit = 50,
        cursor = params.cursor,
    })
    if not result.ok then
        return result
    end
    local entities, items = {}, {}
    local held = GarageKeys.Held(character)
    local bucket = GetPlayerRoutingBucket(source)
    for _, vehicle in ipairs(GetAllVehicles()) do
        local assetId = Entity(vehicle).state.h4nrAssetId
        if assetId and GetEntityRoutingBucket(vehicle) == bucket then
            entities[assetId] = vehicle
        end
    end
    for _, asset in ipairs(result.value.items) do
        local vehicle = entities[asset.assetId]
        if
            vehicle
            and asset.managerResource == GetCurrentResourceName()
            and asset.status ~= 'retired'
            and DoesEntityExist(vehicle)
        then
            local at = GetEntityCoords(vehicle)
            items[#items + 1] = {
                assetId = asset.assetId,
                plate = asset.identifiers and asset.identifiers.plate,
                coords = { x = at.x, y = at.y, z = at.z },
                netId = NetworkGetNetworkIdFromEntity(vehicle),
                lent = GarageKeys.IsLent(asset.assetId, character, held),
            }
        end
    end
    -- Cars of other owners whose current key this character carries, once per refresh.
    if not params.cursor then
        for assetId in pairs(held or {}) do
            local vehicle = entities[assetId]
            local read = vehicle and DoesEntityExist(vehicle) and assets:GetAsset({ assetId = assetId })
            local asset = read and read.ok and read.value
            local owner = asset and asset.status == 'active' and asset.owner
            if owner and owner.holderId ~= character and GarageKeys.IsCurrent(assetId, owner.holderId) then
                local at = GetEntityCoords(vehicle)
                items[#items + 1] = {
                    assetId = assetId,
                    plate = asset.identifiers and asset.identifiers.plate,
                    coords = { x = at.x, y = at.y, z = at.z },
                    netId = NetworkGetNetworkIdFromEntity(vehicle),
                    keyHolder = true,
                }
            end
        end
    end
    if Character(source) ~= character then
        return Garage.Err('forbidden')
    end
    return Garage.Ok({ characterId = character, items = items, nextCursor = result.value.nextCursor })
end
local function SpotFree(at, assetType)
    local point = vector3(at.x, at.y, at.z)
    for _, other in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(other) - point) < GarageConfig.SpawnClearance[assetType] then
            return false
        end
    end
    return true
end
-- The asset and row of a vehicle that can come out, after clearing the status of a lost entity.
local function Retrievable(assetId, garage)
    local row = Garage.Row(assetId)
    local read = assets:GetAsset({ assetId = assetId })
    if not row or not read.ok then
        return nil, Garage.Err('unavailable')
    end
    local asset = read.value
    if asset.assetType ~= garage.assetType then
        return nil, Garage.Err('invalid_garage')
    end
    if Vehicle(assetId) then
        return nil, Garage.Err('already_out')
    end
    if row.status == 'out' or row.status == 'spawning' or row.status == 'storing' then
        DB.exec(
            "UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ? AND status IN ('out','spawning','storing')",
            assetId
        )
        row.status = 'stored'
    end
    if row.status ~= 'stored' then
        return nil, Garage.Err('busy')
    end
    return asset, row
end
-- Runs with the garage's spawn point reserved, see Retrieve. With `hitch` the vehicle is a trailer
-- placed at hitch.at, and the client attaches it to the truck hitch.towNetId.
local function TakeOut(source, params, garage, asset, row, hitch)
    local at = hitch and hitch.at or garage.spawn
    if not SpotFree(at, garage.assetType) then
        return Garage.Err('spawn_blocked')
    end
    local kind = SpawnType(asset.modelKey, asset.assetType)
    if not kind then
        return Garage.Err('spawn_failed')
    end
    if not Owns(source, params.assetId) or not AtGarage(source, params.garage) then
        return Garage.Err('forbidden')
    end
    local changed = DB.exec(
        [[UPDATE h4nr_feather_vehicles SET status = 'spawning'
        WHERE asset_id = ? AND status = 'stored']],
        params.assetId
    )
    if changed ~= 1 then
        return Garage.Err('busy')
    end
    local issued = GarageKeys.Issue(asset, Character(source))
    if not issued.ok then
        DB.exec(
            "UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ? AND status = 'spawning'",
            params.assetId
        )
        return issued
    end
    local props = json.decode(row.props_json)
    props.plate, props.model = asset.identifiers.plate, joaat(asset.modelKey)
    props.fuelLevel = props.fuelLevel or 100.0
    local ok, netId, entity = pcall(FeatherVehicles.spawnVehicle, {
        model = asset.modelKey,
        type = kind,
        spawnSource = at,
        props = SpawnProps(props),
        bucket = 0,
    })
    if not ok or not netId then
        GarageKeys.Void(params.assetId)
        DB.exec(
            "UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ? AND status = 'spawning'",
            params.assetId
        )
        return Garage.Err('spawn_failed')
    end
    live[params.assetId] = entity
    Entity(entity).state:set('h4nrAssetId', params.assetId, true)
    Entity(entity).state:set('h4nrGarageEngine', false, true)
    SetEntityOrphanMode(entity, 2)
    SetVehicleDoorsLocked(entity, 1)
    DB.exec("UPDATE h4nr_feather_vehicles SET status = 'out' WHERE asset_id = ?", params.assetId)
    if not Owns(source, params.assetId) then
        SetVehicleDoorsLocked(entity, 2)
        return Garage.Err('forbidden')
    end
    if hitch then
        TriggerClientEvent('h4nr-garages:hitch', source, hitch.towNetId, netId, props)
    else
        TriggerClientEvent('h4nr-garages:ready', source, netId, props)
    end
    return Garage.Ok({ netId = netId })
end
local function BehindSpawn(spawn)
    local radians, gap = math.rad(spawn.w), GarageConfig.Towing.behind
    return vector4(spawn.x + math.sin(radians) * gap, spawn.y - math.cos(radians) * gap, spawn.z, spawn.w)
end
-- May this truck come out with that trailer? Nil when it may, otherwise the refusal.
local function TrailerRefusal(source, params, asset)
    local towing = GarageConfig.Towing
    if params.trailer == params.assetId or not Owns(source, params.trailer) then
        return 'forbidden'
    end
    local read = assets:GetAsset({ assetId = params.trailer })
    if not read.ok then
        return 'unavailable'
    end
    if not towing.tractors[asset.modelKey:lower()] or not towing.trailers[read.value.modelKey:lower()] then
        return 'invalid_input'
    end
end
local function TakeOutTrailer(source, params, garage, towNetId)
    return Garage.Lock(params.trailer, function()
        local asset, row = Retrievable(params.trailer, garage)
        if not asset then
            return row
        end
        local trailerParams = { garage = params.garage, assetId = params.trailer }
        return TakeOut(source, trailerParams, garage, asset, row, { at = BehindSpawn(garage.spawn), towNetId = towNetId })
    end)
end
local function Retrieve(source, params)
    local garage = AtGarage(source, params.garage)
    if not garage or not Owns(source, params.assetId) then
        return Garage.Err('forbidden')
    end
    return Garage.Lock(params.assetId, function()
        local asset, row = Retrievable(params.assetId, garage)
        if not asset then
            return row
        end
        if params.trailer ~= nil then
            local refusal = TrailerRefusal(source, params, asset)
            if refusal then
                return Garage.Err(refusal)
            end
        end
        -- One request per player at a time (playersBusy), and only the owner takes a car out,
        -- so the count cannot change between this check and the new entity.
        local slots = GarageSlots.Snapshot(Character(source), asset.assetType, Vehicle)
        if not slots then
            return Garage.Err('unavailable')
        end
        if slots.limited and slots.out + (params.trailer and 2 or 1) > slots.outLimit then
            return Garage.Err('out_limit')
        end
        -- Taking out yields between the free-space check and the new entity, so two different cars
        -- could both pass the check. The point stays reserved until this car exists.
        return Garage.Lock('spawn:' .. params.garage, function()
            if params.trailer and not SpotFree(BehindSpawn(garage.spawn), garage.assetType) then
                return Garage.Err('spawn_blocked')
            end
            local taken = TakeOut(source, params, garage, asset, row)
            if taken.ok and params.trailer then
                -- The truck is already out and stays out; the driver is told about the trailer.
                local trailer = TakeOutTrailer(source, params, garage, taken.value.netId)
                if not trailer.ok then
                    taken.value.trailerProblem = trailer.code or 'failed'
                end
            end
            return taken
        end, 'spawn_blocked')
    end)
end
-- Saves the condition, removes the entity and takes the key. Runs under the asset's lock.
local function ParkEntity(assetId, vehicle, garageId, read, props)
    if type(props) ~= 'table' then
        return Garage.Err('invalid_input')
    end
    -- Parking would save the burnt state over the last good one.
    if IsWrecked(vehicle) then
        return Garage.Err('wrecked')
    end
    props.model, props.plate = joaat(read.value.modelKey), read.value.identifiers.plate
    for key, range in pairs({ engineHealth = { -4000, 1000 }, bodyHealth = { 0, 1000 }, fuelLevel = { 0, 100 } }) do
        if
            type(props[key]) ~= 'number'
            or props[key] ~= props[key]
            or props[key] < range[1]
            or props[key] > range[2]
        then
            return Garage.Err('invalid_input')
        end
    end
    local encoded = json.encode(props)
    if #encoded > 16384 then
        return Garage.Err('invalid_input')
    end
    -- Persist before deletion. Recovery never marks a surviving entity stored.
    DB.exec(
        [[UPDATE h4nr_feather_vehicles SET props_json = ?, garage = ?, status = 'storing'
        WHERE asset_id = ?]],
        encoded,
        garageId,
        assetId
    )
    DeleteEntity(vehicle)
    local deadline = GetGameTimer() + 3000
    while DoesEntityExist(vehicle) and GetGameTimer() < deadline do
        Wait(50)
    end
    if DoesEntityExist(vehicle) then
        DB.exec("UPDATE h4nr_feather_vehicles SET status = 'out' WHERE asset_id = ?", assetId)
        return Garage.Err('unavailable')
    end
    live[assetId] = nil
    GarageKeys.Void(assetId)
    DB.exec("UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ?", assetId)
    return Garage.Ok(true)
end
-- The trailer the client says is hitched: it must be the player's to operate and still by the truck.
local function ParkTrailer(source, truckAssetId, garageId, garage, request, truckAt)
    local assetId = type(request) == 'table' and request.assetId
    if assetId == truckAssetId or not CanOperate(source, assetId) then
        return Garage.Err('forbidden')
    end
    return Garage.Lock(assetId, function()
        local vehicle = Vehicle(assetId)
        local read = assets:GetAsset({ assetId = assetId })
        if
            not vehicle
            or not read.ok
            or read.value.assetType ~= garage.assetType
            or not GarageConfig.Towing.trailers[read.value.modelKey:lower()]
            or GetPedInVehicleSeat(vehicle, -1) ~= 0
            or GetEntityRoutingBucket(vehicle) ~= 0
            or #(GetEntityCoords(vehicle) - truckAt) > GarageConfig.Towing.parkReach
        then
            return Garage.Err('forbidden')
        end
        return ParkEntity(assetId, vehicle, garageId, read, request.props)
    end)
end
local function Store(source, params)
    local garage = GarageConfig.Garages[params.garage]
    if not garage or GetPlayerRoutingBucket(source) ~= 0 then
        return Garage.Err('forbidden')
    end
    local allowed, refusal = CanOperate(source, params.assetId)
    if not allowed then
        return Garage.Err(refusal)
    end
    return Garage.Lock(params.assetId, function()
        local vehicle = Vehicle(params.assetId)
        local ped = GetPlayerPed(source)
        local read = assets:GetAsset({ assetId = params.assetId })
        local driver = vehicle and GetPedInVehicleSeat(vehicle, -1)
        -- Driven in, or left empty near the garage and parked from its panel or from beside it.
        local placed = driver == ped and Near(source, GetEntityCoords(vehicle), 6) and AtGarage(source, params.garage)
            or driver == 0
                and InParkRange(garage, vehicle)
                and (
                    AtGarage(source, params.garage)
                    or Near(source, GetEntityCoords(vehicle), GarageConfig.BesideDistance + 2)
                )
        if
            not placed
            or not read.ok
            or read.value.assetType ~= garage.assetType
            or GetEntityRoutingBucket(vehicle) ~= 0
        then
            return Garage.Err('forbidden')
        end
        local truckAt = GetEntityCoords(vehicle)
        local parked = ParkEntity(params.assetId, vehicle, params.garage, read, params.props)
        if parked.ok and params.trailer ~= nil then
            local trailer = ParkTrailer(source, params.assetId, params.garage, garage, params.trailer, truckAt)
            if not trailer.ok then
                return Garage.Ok({ trailerLeft = true })
            end
        end
        return parked
    end)
end
local function Keys(source, params)
    local allowed, refusal = CanOperate(source, params.assetId)
    if not allowed then
        return Garage.Err(refusal)
    end
    local vehicle = Vehicle(params.assetId)
    if
        not vehicle
        or not Near(source, GetEntityCoords(vehicle), 12)
        or GetEntityRoutingBucket(vehicle) ~= GetPlayerRoutingBucket(source)
    then
        return Garage.Err('too_far')
    end
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
-- Tells whoever is carrying the key, so they can bring it back during the wait.
local function WarnKeyHolder(instance)
    for _, player in ipairs(GetPlayers()) do
        local source = tonumber(player)
        local character = Character(source)
        if character and exports['feather-inventory']:initiate().Instances.GetItemForCharacter(character, instance).ok then
            TriggerClientEvent('h4nr-garages:notify', source, 'rekey_warning')
            return
        end
    end
end
local function Rekey(source, params)
    if not AtGarage(source, params.garage) or not Owns(source, params.assetId) then
        return Garage.Err('forbidden')
    end
    local character = Character(source)
    local held = GarageKeys.Held(character)
    if not held then
        return Garage.Err('unavailable')
    end
    return Garage.Lock(params.assetId, function()
        local state = GarageKeys.RekeyState(params.assetId, character, held)
        if not state then
            return Garage.Err('rekey_not_needed')
        end
        if state.state == 'none' then
            local instance = GarageKeys.RequestRekey(params.assetId)
            WarnKeyHolder(instance)
            return Garage.Ok({ state = 'waiting', seconds = GarageConfig.Rekey.waitSeconds })
        end
        if state.state == 'waiting' then
            return Garage.Err('rekey_waiting')
        end
        if params.method ~= 'cash' and params.method ~= 'bank' then
            return Garage.Err('invalid_input')
        end
        local vehicle = Vehicle(params.assetId)
        if vehicle and GetPedInVehicleSeat(vehicle, -1) ~= 0 then
            return Garage.Err('vehicle_in_use')
        end
        local charged = GaragePayments.Charge({
            characterId = character,
            source = source,
            method = params.method,
            dollars = GarageConfig.Rekey.price,
            referenceId = params.assetId,
            key = ('rekey:%s:%s'):format(params.assetId, GarageKeys.Generation(params.assetId)),
        })
        if not charged.ok then
            return charged
        end
        if vehicle then
            DeleteEntity(vehicle)
            local deadline = GetGameTimer() + 3000
            while DoesEntityExist(vehicle) and GetGameTimer() < deadline do
                Wait(50)
            end
            -- The charge is idempotent on this generation: confirming again pays nothing more.
            if DoesEntityExist(vehicle) then
                return Garage.Err('unavailable')
            end
            live[params.assetId] = nil
        end
        GarageKeys.Void(params.assetId)
        DB.exec("UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ?", params.assetId)
        return Garage.Ok({ state = 'done' })
    end)
end
local function BuySlot(source, params)
    local character = Character(source)
    local garage = AtGarage(source, params.garage)
    if not garage or not character then
        return Garage.Err('too_far')
    end
    if not GarageConfig.Slots.limits[garage.assetType] then
        return Garage.Err('invalid_input')
    end
    return GarageSlots.Buy(source, character, params.kind)
end
-- For trusted shops, before any money moves: may this character receive one more vehicle?
exports('GetVehicleSlots', function(request)
    if not GarageConfig.TrustedShops[GetInvokingResource()] or type(request) ~= 'table' then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    if not Garage.Uuid(request.holderId) or type(request.assetType) ~= 'string' then
        return Garage.Err('invalid_input')
    end
    local slots = GarageSlots.Snapshot(request.holderId, request.assetType, Vehicle)
    if not slots then
        return Garage.Err('unavailable')
    end
    slots.canReceive = not slots.limited or not slots.ownedLimit or slots.owned < slots.ownedLimit
    return Garage.Ok(slots)
end)
-- Read by the driver's client: whoever sits at the wheel needs the key, whatever the engine state.
local function CanDrive(source, params)
    local allowed = CanOperate(source, params.assetId)
    return Garage.Ok({ allowed = allowed })
end
-- Removes the wreck and puts the vehicle back as stored. Its last saved state is left untouched,
-- so it comes out the way it was before it burnt.
local function RecoverWreck(source, params)
    local garage = AtGarage(source, params.garage)
    if not garage or not Owns(source, params.assetId) then
        return Garage.Err('forbidden')
    end
    return Garage.Lock(params.assetId, function()
        local vehicle = Vehicle(params.assetId)
        local seconds = vehicle and WreckSeconds(vehicle)
        if not seconds then
            return Garage.Err('not_wrecked')
        end
        if seconds > 0 then
            return Garage.Err('wreck_waiting')
        end
        local read = assets:GetAsset({ assetId = params.assetId })
        if not read.ok or read.value.assetType ~= garage.assetType then
            return Garage.Err('invalid_garage')
        end
        DeleteEntity(vehicle)
        local deadline = GetGameTimer() + 3000
        while DoesEntityExist(vehicle) and GetGameTimer() < deadline do
            Wait(50)
        end
        if DoesEntityExist(vehicle) then
            return Garage.Err('unavailable')
        end
        live[params.assetId] = nil
        GarageKeys.Void(params.assetId)
        DB.exec("UPDATE h4nr_feather_vehicles SET status = 'stored' WHERE asset_id = ?", params.assetId)
        return Garage.Ok(true)
    end)
end
for name, handler in pairs({
    canDrive = CanDrive,
    list = List,
    locations = Locations,
    retrieve = Retrieve,
    store = Store,
    keys = Keys,
    rekey = Rekey,
    recoverWreck = RecoverWreck,
    buySlot = BuySlot,
}) do
    local operation = handler
    local mutating = name ~= 'list' and name ~= 'locations' and name ~= 'canDrive'
    local route = name
    FeatherRPC:Register('h4nr-garages:' .. name, function(params, respond, source)
        if not Garage.ready then
            return respond(Garage.Err('not_ready'))
        end
        if type(params) ~= 'table' then
            return respond(Garage.Err('invalid_input'))
        end
        if mutating and playersBusy[source] then
            return respond(Garage.Err('busy'))
        end
        if mutating then
            playersBusy[source] = true
        end
        local ok, result = pcall(operation, source, params)
        if mutating then
            playersBusy[source] = nil
        end
        if not ok then
            print('[h4nr-garages] request failed: ' .. tostring(result))
        end
        if ok and route == 'list' and type(result) == 'table' and not result.ok then
            print(('[h4nr-garages] list refused: source=%s code=%s'):format(source, tostring(result.code)))
        end
        respond(ok and result or Garage.Err('unavailable'))
    end)
end
-- Takes the key of a vehicle that vanished from the street. Two misses in a row, so a vehicle
-- changing hands for a moment keeps its key; only 'out' rows, because others are mid-operation.
local missingKeys = {}
function Garage.VoidLostKeys()
    local missing = {}
    for _, assetId in ipairs(GarageKeys.ActiveAssets()) do
        local row = not Vehicle(assetId) and Garage.Row(assetId)
        if row and row.status == 'out' then
            if missingKeys[assetId] then
                Garage.Lock(assetId, function()
                    local current = Garage.Row(assetId)
                    if not Vehicle(assetId) and current and current.status == 'out' then
                        GarageKeys.Void(assetId)
                    end
                    return Garage.Ok(true)
                end)
            else
                missing[assetId] = true
            end
        end
    end
    missingKeys = missing
end
local function CheckLostKeys()
    if Garage.ready then
        local ok, problem = pcall(Garage.VoidLostKeys)
        if not ok then
            print('[h4nr-garages] lost key check failed: ' .. tostring(problem))
        end
    end
    SetTimeout(GarageConfig.Key.lostCheckMs, CheckLostKeys)
end
SetTimeout(GarageConfig.Key.lostCheckMs, CheckLostKeys)
-- Starts a wreck's wait when it burns, whether or not anyone has the garage open. A vehicle
-- repaired in the meantime starts over if it burns again.
function Garage.CheckWrecks()
    for _, vehicle in ipairs(GetAllVehicles()) do
        local state = Entity(vehicle).state
        if state.h4nrAssetId then
            local wrecked = IsWrecked(vehicle)
            if wrecked and not state.h4nrWreckedAt then
                state:set('h4nrWreckedAt', os.time(), true)
            elseif not wrecked and state.h4nrWreckedAt then
                state:set('h4nrWreckedAt', nil, true)
            end
        end
    end
end
local function WatchWrecks()
    local ok, problem = pcall(Garage.CheckWrecks)
    if not ok then
        print('[h4nr-garages] wreck check failed: ' .. tostring(problem))
    end
    SetTimeout(GarageConfig.Wreck.checkMs, WatchWrecks)
end
SetTimeout(GarageConfig.Wreck.checkMs, WatchWrecks)
CreateThread(function()
    local ok, problem = pcall(function()
        Garage.Migrate()
        GarageKeys.Migrate()
        GarageSlots.Migrate()
        local ready = assets:AwaitReady(30000)
        assert(ready.ok, ready.code)
        local inventoryReady = exports['feather-inventory']:AwaitReady(30000)
        assert(inventoryReady.ok, inventoryReady.code)
        GarageKeys.Start()
        local rows = DB.query("SELECT asset_id FROM h4nr_feather_vehicles WHERE status IN ('spawning','storing','out')")
            or {}
        for _, row in ipairs(rows) do
            DB.exec(
                'UPDATE h4nr_feather_vehicles SET status = ? WHERE asset_id = ?',
                Vehicle(row.asset_id) and 'out' or 'stored',
                row.asset_id
            )
        end
        for _, assetId in ipairs(GarageKeys.ActiveAssets()) do
            if not Vehicle(assetId) then
                GarageKeys.Void(assetId)
            end
        end
        Garage.ready = true
    end)
    if not ok then
        print('[h4nr-garages] startup failed: ' .. tostring(problem))
    end
end)

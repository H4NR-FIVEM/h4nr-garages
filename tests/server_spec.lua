-- Actual garage modules, modelled SQL and domain boundaries. No FXServer claim.
local passed = 0
local function check(name, condition)
    assert(condition, 'FAIL: ' .. name)
    passed = passed + 1
end
local function copy(value)
    if type(value) ~= 'table' then
        return value
    end
    local result = {}
    for k, v in pairs(value) do
        result[k] = copy(v)
    end
    return result
end
local jsonValues = {}
json = {
    encode = function(value)
        jsonValues[#jsonValues + 1] = copy(value)
        return 'J' .. #jsonValues
    end,
    decode = function(value)
        return copy(assert(jsonValues[tonumber(value:sub(2))]))
    end,
}
local meta = {}
meta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, meta)
end
meta.__len = function(a)
    return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, meta)
end
function vector4(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w }, meta)
end
local A, B = '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222'
local orderId = '33333333-3333-3333-3333-333333333333'
local assetId = '44444444-4444-4444-4444-444444444444'
local rows, assetsById, receipts, claims = {}, {}, {}, {}
local failSaveAsset, failStore, failAssignResponse = false, false, false
local registerCalls, assigned = 0, 0
local api, rpc, threads = {}, {}, {}
local caller = 'h4nr-vehicleshop'
local function findRow(id)
    for _, row in pairs(rows) do
        if row.asset_id == id then
            return row
        end
    end
end
local MySQL = { query = {}, insert = {}, single = {}, update = {} }
local keyRows = {}
function MySQL.query.await(sql)
    if sql:find('CREATE TABLE') then
        return {}
    end
    if sql:find('h4nr_feather_vehicle_keys') then
        local active = {}
        for _, row in pairs(keyRows) do
            if row.status == 'active' then
                active[#active + 1] = copy(row)
            end
        end
        return active
    end
    local result = {}
    for _, row in pairs(rows) do
        if row.status == 'out' or row.status == 'spawning' or row.status == 'storing' then
            result[#result + 1] = copy(row)
        end
    end
    return result
end
function MySQL.single.await(sql, p)
    if sql:find('h4nr_feather_vehicle_keys') then
        return copy(keyRows[p[1]])
    end
    return copy(sql:find('WHERE order_id') and rows[p[1]] or findRow(p[1]))
end
function MySQL.insert.await(_, p)
    assert(not rows[p[1]])
    rows[p[1]] = {
        order_id = p[1],
        asset_type = p[2],
        model_key = p[3],
        buyer_id = p[4],
        purchase_props = p[5],
        props_json = p[6],
        plate = p[7],
        garage = p[8],
        status = 'registering',
    }
    return 1
end
function MySQL.update.await(sql, p)
    if sql:find('INSERT INTO h4nr_feather_vehicle_keys') then
        local row = keyRows[p[1]] or { asset_id = p[1], generation = 0 }
        row.generation, row.key_instance_id, row.owner_id, row.issued_to, row.status =
            row.generation + 1, nil, p[2], p[3], 'void'
        keyRows[p[1]] = row
        return 1
    elseif sql:find('h4nr_feather_vehicle_keys SET key_instance_id') then
        keyRows[p[2]].key_instance_id, keyRows[p[2]].status = p[1], 'active'
        return 1
    elseif sql:find('h4nr_feather_vehicle_keys SET status') then
        if keyRows[p[1]] then
            keyRows[p[1]].status = 'void'
        end
        return 1
    elseif sql:find('SET asset_id') then
        if failSaveAsset then
            failSaveAsset = false
            error('injected SQL failure after Asset commit')
        end
        rows[p[2]].asset_id = p[1]
        return 1
    elseif sql:find('SET plate') then
        if failStore then
            failStore = false
            error('injected SQL failure after plate commit')
        end
        rows[p[2]].plate, rows[p[2]].status = p[1], 'stored'
        return 1
    elseif sql:find('SET props_json') then
        local row = assert(findRow(p[3]))
        row.props_json, row.garage, row.status = p[1], p[2], 'storing'
        return 1
    elseif sql:find('SET status = %?') then
        findRow(p[2]).status = p[1]
        return 1
    else
        local status = assert(sql:match("SET status = '(%a+)'"), sql)
        local previous = sql:match("AND status = '(%a+)'")
        local row = assert(findRow(p[1]))
        if previous and row.status ~= previous then
            return 0
        end
        row.status = status
        return 1
    end
end
-- feather-mysql surface over the modeled statements above.
DB = {
    query = function(sql, ...)
        return MySQL.query.await(sql, { ... })
    end,
    one = function(sql, ...)
        return MySQL.single.await(sql, { ... })
    end,
    insert = function(sql, ...)
        return MySQL.insert.await(sql, { ... })
    end,
    exec = function(sql, ...)
        if sql:find('CREATE TABLE') then
            return 0
        end
        return MySQL.update.await(sql, { ... })
    end,
}
local domainEnv = setmetatable({ exports = function() end }, { __index = _G })
assert(loadfile(ROOT .. '/../../[feather]/feather-assets/server/foundation.lua', 't', domainEnv))()
local assets = {}
function assets:AwaitReady()
    return { ok = true }
end
function assets:GetAsset(p)
    return assetsById[p.assetId] and { ok = true, value = copy(assetsById[p.assetId]) }
        or { ok = false, code = 'asset_not_found' }
end
function assets:RegisterAsset(p)
    assert(domainEnv.Assets.Token(p.requestId, 128), 'real Assets request ID validator')
    assert(domainEnv.Assets.ModelKey(p.modelKey), 'real Assets model validator')
    registerCalls = registerCalls + 1
    if receipts[p.requestId] then
        return { ok = true, value = copy(receipts[p.requestId]) }
    end
    local asset = {
        assetId = assetId,
        assetType = p.assetType,
        modelKey = p.modelKey,
        managerResource = 'h4nr-garages',
        provenanceType = p.provenanceType,
        provenanceId = p.provenanceId,
        status = 'active',
        revision = 1,
        owner = { holderType = p.holderType, holderId = p.holderId },
        identifiers = {},
    }
    assetsById[assetId], receipts[p.requestId] = asset, copy(asset)
    return { ok = true, value = copy(asset) }
end
function assets:AssignAssetIdentifier(p)
    assert(domainEnv.Assets.Token(p.requestId, 128), 'real Assets identifier request ID validator')
    local asset = assert(assetsById[p.assetId])
    if claims[p.value] and claims[p.value] ~= p.assetId then
        return { ok = false, code = 'identifier_in_use' }
    end
    if p.expectedRevision ~= asset.revision then
        return { ok = false, code = 'revision_conflict' }
    end
    assigned = assigned + 1
    claims[p.value], asset.identifiers.plate, asset.revision = p.assetId, p.value, asset.revision + 1
    if failAssignResponse then
        failAssignResponse = false
        return { ok = false, code = 'transaction_failed' }
    end
    return { ok = true, value = copy(asset) }
end
function assets:CheckInterest(p)
    local asset = assetsById[p.assetId]
    return {
        ok = true,
        value = { matched = asset and asset.owner.holderId == p.holderId, assetStatus = asset and asset.status },
    }
end
function assets:ListAssetsByHolder(p)
    local items = {}
    for _, asset in pairs(assetsById) do
        if asset.owner.holderId == p.holderId then
            items[#items + 1] = copy(asset)
        end
    end
    return { ok = true, value = { items = items } }
end
-- Modelled Inventory contract: unique instances in inventories, guards and destruction.
local characterInventories = { [A] = 1, [B] = 2 }
local TRUNK = 3
local instances, nextInstance, inventoryFull, failGrant, failDestroy = {}, 100, false, false, false
local destroyGuards, itemMovedHandlers = {}, {}
local grantIds = {}
local inventoryApi = {
    Guards = {
        RegisterDestroyGuard = function(name, fn)
            destroyGuards[name] = fn
            return { ok = true, value = true }
        end,
        UnregisterDestroyGuard = function(name)
            destroyGuards[name] = nil
        end,
    },
    Instances = {
        GetInstance = function(id)
            local item = instances[id]
            return item and { ok = true, value = { id = id, inventoryId = item.inventoryId, metadata = item.metadata } }
                or { ok = false, error = { code = 'NOT_FOUND' } }
        end,
        GetItemForCharacter = function(character, id)
            local item = instances[id]
            if item and item.inventoryId == characterInventories[character] then
                return { ok = true, value = { id = id } }
            end
            return { ok = false, error = { code = 'NOT_FOUND' } }
        end,
    },
    Inventory = {
        GetContainerLifecycle = function(id)
            return { ok = true, value = { location = id == TRUNK and 'trunk' or 'character' } }
        end,
        InventoryCanHoldById = function()
            return { ok = true, value = { accepted = not inventoryFull } }
        end,
        GetInventoryItems = function(id)
            local rows = {}
            for instanceId, item in pairs(instances) do
                if item.inventoryId == id then
                    rows[#rows + 1] = { id = instanceId, name = 'vehicle_key' }
                end
            end
            return { ok = true, value = rows }
        end,
    },
    Items = {
        GetDefinitions = function()
            return { ok = true, value = { { id = 77, name = 'vehicle_key', instance_mode = 'unique' } } }
        end,
    },
    DestroyInstances = function(context, spec)
        assert(spec.expectedLocation == (spec.inventoryId == TRUNK and 'trunk' or 'character'))
        if failDestroy then
            return { ok = false, error = { code = 'internal' } }
        end
        for _, id in ipairs(spec.instanceIds) do
            for _, guard in pairs(destroyGuards) do
                if guard({ id = id }, context) ~= true then
                    return { ok = false, error = { code = 'denied' } }
                end
            end
            instances[id] = nil
        end
        return { ok = true, value = spec.instanceIds }
    end,
}
local inventory = {}
function inventory:initiate()
    return inventoryApi
end
function inventory:AwaitReady()
    return { ok = true }
end
function inventory:GetCharacterInventory(character)
    return { ok = true, value = { id = characterInventories[character] } }
end
function inventory:GrantCharacterUniqueItemOnce(request)
    assert(request.definitionId == 77 and request.itemName == 'vehicle_key')
    assert(not grantIds[request.grantId], 'a new key always has a new grant ID')
    if failGrant then
        return { ok = false, error = { code = 'internal' } }
    end
    grantIds[request.grantId] = true
    nextInstance = nextInstance + 1
    instances[nextInstance] = { inventoryId = characterInventories[request.characterId], metadata = request.metadata }
    return { ok = true, value = { instanceId = nextInstance } }
end
local core = {
    GetSessionContext = function(_, source)
        return { ok = true, value = { characterId = source == 1 and A or B } }
    end,
}
exports = setmetatable({}, {
    __index = function(_, name)
        return ({ ['feather-assets'] = assets, ['feather-core'] = core, ['feather-inventory'] = inventory })[name]
    end,
    __call = function(_, name, fn)
        api[name] = fn
    end,
})
function GetInvokingResource()
    return caller
end
function GetCurrentResourceName()
    return 'h4nr-garages'
end
function CreateThread(fn)
    threads[#threads + 1] = fn
end
function Wait() end
local eventHandlers = {}
function AddEventHandler(name, fn)
    eventHandlers[name] = fn
end
FeatherRPC = {
    Register = function(_, name, fn)
        rpc[name] = fn
    end,
}
dofile(ROOT .. '/config/shared.lua')
dofile(ROOT .. '/server/registration.lua')
dofile(ROOT .. '/server/keys.lua')
local request = {
    orderId = orderId,
    assetType = 'vehicle',
    modelKey = 'f-one49d',
    holderType = 'character',
    holderId = A,
    plate = 'LS12 ABC',
    props = { color1 = 27, color2 = 0 },
    garage = 'pillboxgarage',
}
check('not ready refuses registration', api.RegisterPurchasedVehicle(request).code == 'unavailable')
Garage.ready = true
caller = 'evil'
check('untrusted caller refused', api.RegisterPurchasedVehicle(request).code == 'forbidden')
caller = 'h4nr-vehicleshop'
local bad = copy(request)
bad.holderType = 'organization'
check('unsupported holder refused', not api.RegisterPurchasedVehicle(bad).ok)
bad = copy(request)
bad.props.color1 = 900
check('invalid paint refused', not api.RegisterPurchasedVehicle(bad).ok)
bad = copy(request)
bad.garage = 'marina'
check('wrong garage type refused', api.RegisterPurchasedVehicle(bad).code == 'invalid_garage')
claims[request.plate] = 'other'
check('plate conflict mapped for shop retry', api.RegisterPurchasedVehicle(request).code == 'identifier_taken')
check('failed plate still has a single asset', rows[orderId].asset_id == assetId and registerCalls == 1)
request.plate = 'LS99 XYZ'
failAssignResponse = true
check('unknown plate outcome retained for retry', not api.RegisterPurchasedVehicle(request).ok)
local result = api.RegisterPurchasedVehicle(request)
check('retry recovers committed plate', result.ok and result.value.plate == 'LS99 XYZ')
check('retry creates no extra asset or identifier', registerCalls == 1 and assigned == 1)
check(
    'purchase stored with presentation outside Assets',
    rows[orderId].status == 'stored' and not assetsById[assetId].props
)
local repeatResult = api.RegisterPurchasedVehicle(request)
check('completed registration replays', repeatResult.ok and repeatResult.value.assetId == assetId)
bad = copy(request)
bad.holderId = B
check('changed buyer cannot replay order', api.RegisterPurchasedVehicle(bad).code == 'idempotency_conflict')
assetsById[assetId].owner.holderId = B
check('receipt replays after subsequent sale', api.RegisterPurchasedVehicle(request).ok)
assetsById[assetId].owner.holderId = A
-- Lost local writes after domain commit: registration receipt must be recoverable.
rows, assetsById, receipts, claims = {}, {}, {}, {}
registerCalls, assigned = 0, 0
failSaveAsset = true
check('SQL failure after registration returns retryable failure', not api.RegisterPurchasedVehicle(request).ok)
check('retry after lost asset link succeeds', api.RegisterPurchasedVehicle(request).ok and assigned == 1)
rows[orderId].status = 'registering'
failStore = true
-- Existing plate means final local state can be resumed without touching Assets.
check('SQL failure after identifier returns retryable failure', not api.RegisterPurchasedVehicle(request).ok)
check('retry after identifier commit succeeds', api.RegisterPurchasedVehicle(request).ok and assigned == 1)
check(
    'capability advertises actual readiness',
    api.GetCapabilities().value.purchaseRegistration == 1
        and api.GetCapabilities().value.keyItems == 1
        and api.GetCapabilities().value.ready
)
-- Runtime/native boundary -----------------------------------------------------
local coords = { [1] = GarageConfig.Garages.pillboxgarage.coords, [2] = GarageConfig.Garages.pillboxgarage.coords }
local entities, states, drivers, locks = {}, {}, {}, {}
local nextEntity, clock, spawnCount = 10, 0, 0
function GetPlayerPed(source)
    return source
end
function GetEntityCoords(entity)
    return coords[entity] or vector3(0, 0, 0)
end
local playerBuckets, entityBuckets = {}, {}
function GetPlayerRoutingBucket(source)
    return playerBuckets[source] or 0
end
function GetEntityRoutingBucket(entity)
    return entityBuckets[entity] or 0
end
function GetAllVehicles()
    local all = {}
    for id in pairs(entities) do
        all[#all + 1] = id
    end
    return all
end
function DoesEntityExist(entity)
    return entities[entity] == true
end
function Entity(entity)
    states[entity] = states[entity]
        or setmetatable({}, {
            __index = {
                set = function(self, k, v)
                    self[k] = v
                end,
            },
        })
    return { state = states[entity] }
end
function GetGameTimer()
    clock = clock + 1000
    return clock
end
function joaat()
    return 123
end
function CreateVehicle()
    nextEntity = nextEntity + 1
    entities[nextEntity] = true
    return nextEntity
end
function GetVehicleType()
    return 'automobile'
end
local refuseDelete = false
function DeleteEntity(entity)
    if not refuseDelete then
        entities[entity] = nil
    end
end
function SetEntityOrphanMode() end
function SetVehicleDoorsLocked(entity, value)
    locks[entity] = value
end
function GetVehicleDoorLockStatus(entity)
    return locks[entity] or 1
end
function NetworkGetNetworkIdFromEntity(entity)
    return entity + 100
end
function GetPedInVehicleSeat(entity)
    return drivers[entity]
end
local events = {}
function TriggerClientEvent(name, source, ...)
    events[#events + 1] = { name = name, source = source, args = { ... } }
end
FeatherVehicles = {
    spawnVehicle = function(spec)
        spawnCount = spawnCount + 1
        local entity = CreateVehicle()
        coords[entity] = vector3(spec.spawnSource.x, spec.spawnSource.y, spec.spawnSource.z)
        return entity + 100, entity
    end,
}
dofile(ROOT .. '/server/main.lua')
for _, fn in ipairs(threads) do
    fn()
end
local function call(name, params, source)
    local result
    rpc['h4nr-garages:' .. name](params, function(value)
        result = value
    end, source or 1)
    return result
end
check('startup ready', Garage.ready)
-- A yielding map-location read must never block the interactive garage list.
local originalList = assets.ListAssetsByHolder
local pauseRead = true
assets.ListAssetsByHolder = function(self, request)
    if pauseRead then
        pauseRead = false
        coroutine.yield()
    end
    return originalList(self, request)
end
local locationResult
local pendingRead = coroutine.create(function()
    locationResult = call('locations', {})
end)
assert(coroutine.resume(pendingRead))
check('garage list stays available during a map poll', call('list', { garage = 'pillboxgarage' }).ok)
assert(coroutine.resume(pendingRead))
check('overlapping map poll finishes independently', locationResult.ok)
assets.ListAssetsByHolder = originalList

check('parked cars have no live map location', #call('locations', {}).value.items == 0)
check('invalid location cursor rejected', call('locations', { cursor = 'invalid' }).code == 'invalid_input')
check('owner sees purchased vehicle', #call('list', { garage = 'pillboxgarage' }).value.items == 1)
check('other character cannot see vehicle', #call('list', { garage = 'pillboxgarage' }, 2).value.items == 0)
local spec = { garage = 'pillboxgarage', assetId = assetId }
check('other character cannot retrieve', call('retrieve', spec, 2).code == 'forbidden')
assetsById[assetId].status = 'held'
check('impounded vehicle cannot retrieve', call('retrieve', spec).code == 'forbidden')
assetsById[assetId].status = 'active'
local originalGet = assets.GetAsset
local pauseMutation = true
assets.GetAsset = function(self, request)
    if pauseMutation then
        pauseMutation = false
        coroutine.yield()
    end
    return originalGet(self, request)
end
local spawned
local pendingMutation = coroutine.create(function()
    spawned = call('retrieve', spec)
end)
assert(coroutine.resume(pendingMutation))
check(
    'mutations stay serialized during a yielding retrieval',
    call('keys', { assetId = assetId, action = 'lock' }).code == 'busy'
)
check(
    'read cannot release an active mutation lock',
    call('list', { garage = 'pillboxgarage' }).ok
        and call('keys', { assetId = assetId, action = 'lock' }).code == 'busy'
)
assert(coroutine.resume(pendingMutation))
assets.GetAsset = originalGet

check('owner retrieves once', spawned.ok and spawnCount == 1 and rows[orderId].status == 'out')
check('double retrieval cannot duplicate entity', call('retrieve', spec).code == 'already_out' and spawnCount == 1)
local entity = spawned.value.netId - 100
check('entity identity uses asset UUID', Entity(entity).state.h4nrAssetId == assetId)
coords[1] = vector3(5000, 5000, 30)
local location = call('locations', {}).value.items[1]
check(
    'owner receives car coordinates from anywhere',
    location and location.assetId == assetId and location.coords.x == coords[entity].x and location.plate == 'LS99 XYZ'
)
check('another player cannot query owner locations', #call('locations', { holderId = A }, 2).value.items == 0)
entityBuckets[entity] = 7
check('locations do not cross private sessions', #call('locations', {}).value.items == 0)
entityBuckets[entity] = nil
assetsById[assetId].owner.holderId = B
check('former owner loses tracking after sale', #call('locations', {}).value.items == 0)
check('new owner gains tracking after sale', #call('locations', {}, 2).value.items == 1)
assetsById[assetId].owner.holderId = A

coords[1], coords[2] = coords[entity], coords[entity]
check('non-owner cannot lock', call('keys', { assetId = assetId, action = 'lock' }, 2).code == 'forbidden')
check('owner locks', call('keys', { assetId = assetId, action = 'lock' }).value.locked and locks[entity] == 2)
check('owner unlocks', not call('keys', { assetId = assetId, action = 'lock' }).value.locked and locks[entity] == 1)
check(
    'owner outside driver seat cannot start engine',
    call('keys', { assetId = assetId, action = 'engine' }).code == 'forbidden'
)
drivers[entity] = 1
check('owner starts engine', call('keys', { assetId = assetId, action = 'engine' }).value.running)
spec.props = { engineHealth = 900, bodyHealth = 800, fuelLevel = 55, color1 = 27, color2 = 0, plate = 'FORGED' }
refuseDelete = true
check('failed entity deletion does not mark stored', not call('store', spec).ok and rows[orderId].status == 'out')
refuseDelete = false
check(
    'owner parks at spawn point',
    call('store', spec).ok and rows[orderId].status == 'stored' and not entities[entity]
)
check('parking removes location', #call('locations', {}).value.items == 0)
local saved = json.decode(rows[orderId].props_json)
check('server preserves authoritative plate', saved.plate == 'LS99 XYZ')
check('damage and fuel persist', saved.engineHealth == 900 and saved.fuelLevel == 55)
coords[1] = GarageConfig.Garages.pillboxgarage.coords
check('parked vehicle retrieves again', call('retrieve', spec).ok and spawnCount == 2)
caller = 'foreign'
check('work vehicle export refuses unrelated callers', api.GetWorkVehicle({assetId=assetId}).code == 'forbidden')
caller = 'petrolist_job'
local workVehicle = api.GetWorkVehicle({assetId=assetId})
check('work vehicle export resolves the server live registry', workVehicle.ok and type(workVehicle.value.netId)=='number')
check('work vehicle export validates persistent identity', api.GetWorkVehicle({assetId='not-a-uuid'}).code == 'forbidden')
caller = 'h4nr-vehicleshop'
-- Physical keys ---------------------------------------------------------------
local function activeKey()
    return keyRows[assetId].status == 'active' and tonumber(keyRows[assetId].key_instance_id) or nil
end
local function give(id, inventoryId)
    local from = instances[id].inventoryId
    instances[id].inventoryId = inventoryId
    eventHandlers['Feather:Inventory:ItemMoved']({ instanceId = id, fromInventoryId = from, toInventoryId = inventoryId })
end
local keyId = activeKey()
local vehicleNow = next(entities)
check('retrieval puts one key in the inventory', keyId and instances[keyId].inventoryId == 1)
check('the key carries asset, plate and generation', instances[keyId].metadata.assetId == assetId
    and instances[keyId].metadata.plate == 'LS99 XYZ' and instances[keyId].metadata.generation == keyRows[assetId].generation)
check('the key is labelled with the plate', instances[keyId].metadata.label == 'Cheie · LS99 XYZ')
coords[1], coords[2] = coords[vehicleNow], coords[vehicleNow]
drivers[vehicleNow] = 1
check('holder owner may lock and start', call('keys', { assetId = assetId, action = 'lock' }).ok)
check('no key, no access for a stranger', call('keys', { assetId = assetId, action = 'lock' }, 2).code == 'forbidden')
Entity(vehicleNow).state:set('h4nrGarageEngine', true, true)
give(keyId, 2)
check('giving the key stops a running engine', Entity(vehicleNow).state.h4nrGarageEngine == false)
check('owner without the key is refused', call('keys', { assetId = assetId, action = 'lock' }).code == 'key_not_here')
check('new holder can lock', call('keys', { assetId = assetId, action = 'lock' }, 2).ok)
drivers[vehicleNow] = 1
check('owner in the seat cannot start without the key',
    call('keys', { assetId = assetId, action = 'engine' }).code == 'key_not_here')
drivers[vehicleNow] = 2
check('new holder can start', call('keys', { assetId = assetId, action = 'engine' }, 2).value.running)
local ownerBlip = call('locations', {}).value.items[1]
check('owner blip shows the key was given', ownerBlip.lent == true and not ownerBlip.keyHolder)
local holderBlip = call('locations', {}, 2).value.items[1]
check('holder sees the car through the key', holderBlip.keyHolder and holderBlip.assetId == assetId
    and holderBlip.plate == 'LS99 XYZ')
check('later location pages do not repeat held keys',
    #call('locations', { cursor = '55555555-5555-5555-5555-555555555555' }, 2).value.items == 0)
give(keyId, TRUNK)
check('key in a trunk does not work for the owner', call('keys', { assetId = assetId, action = 'lock' }).code == 'key_not_here')
check('key in a trunk does not work for the former holder', call('keys', { assetId = assetId, action = 'lock' }, 2).code == 'forbidden')
check('key in a trunk counts as given', call('locations', {}).value.items[1].lent == true)
check('key in a trunk gives nobody a holder blip', #call('locations', {}, 2).value.items == 0)
give(keyId, 1)
check('getting the key back restores use', call('keys', { assetId = assetId, action = 'lock' }).ok)
check('getting the key back restores the blip', not call('locations', {}).value.items[1].lent)
local guard = destroyGuards['h4nr-garages:vehicle-key']
check('players cannot destroy an active key', guard({ id = keyId }, { actorSource = 1 }) == false)
check('server cleanup may destroy an active key', guard({ id = keyId }, { resource = 'feather-inventory' }) == true)
check('unrelated items are not guarded', guard({ id = 1 }, { actorSource = 1 }) == true)
give(keyId, 2)
drivers[vehicleNow] = 1
local storeSpec = { garage = 'pillboxgarage', assetId = assetId,
    props = { engineHealth = 900, bodyHealth = 800, fuelLevel = 55, color1 = 27, color2 = 0 } }
coords[1], coords[2] = GarageConfig.Garages.pillboxgarage.coords, GarageConfig.Garages.pillboxgarage.coords
coords[vehicleNow] = coords[1]
check('owner without the key cannot park', call('store', storeSpec).code == 'key_not_here')
drivers[vehicleNow] = 2
check('another player with the key can park', call('store', storeSpec, 2).ok and rows[orderId].status == 'stored')
check('parking takes the key wherever it is', not instances[keyId] and keyRows[assetId].status == 'void')
check('the car stays with its owner', assetsById[assetId].owner.holderId == A)
check('a voided key has no guard', guard({ id = keyId }, { actorSource = 1 }) == true)
-- Refusals leave no car without a key and no key without a car.
local generation = keyRows[assetId].generation
inventoryFull = true
local spawnsBefore = spawnCount
check('full inventory refuses retrieval', call('retrieve', spec).code == 'inventory_full')
check('full inventory spawns nothing', spawnCount == spawnsBefore and rows[orderId].status == 'stored')
check('full inventory spends no generation', keyRows[assetId].generation == generation)
inventoryFull = false
failGrant = true
check('failed grant refuses retrieval', call('retrieve', spec).code == 'key_unavailable')
check('failed grant spawns nothing', spawnCount == spawnsBefore and rows[orderId].status == 'stored')
failGrant = false
local originalSpawn = FeatherVehicles.spawnVehicle
FeatherVehicles.spawnVehicle = function()
    return nil
end
check('failed spawn refuses retrieval', call('retrieve', spec).code == 'spawn_failed')
check('failed spawn takes the key back', not activeKey() and next(instances) == nil)
FeatherVehicles.spawnVehicle = originalSpawn
-- A car that vanished: the next retrieval replaces its key.
check('retrieval after failures works', call('retrieve', spec).ok)
local firstKey = activeKey()
entities[next(entities)] = nil
check('vanished car can be retrieved again', call('retrieve', spec).ok)
local secondKey = activeKey()
check('the old key of a vanished car is gone', firstKey ~= secondKey and not instances[firstKey] and instances[secondKey])
-- A voided key that cannot be destroyed stays useless.
local carNow = next(entities)
coords[1], coords[2] = coords[carNow], coords[carNow]
GarageKeys.Issue(assetsById[assetId], A)
local spare = activeKey()
failDestroy = true
GarageKeys.Issue(assetsById[assetId], A)
failDestroy = false
check('an undestroyed old key stays in the inventory', instances[spare] ~= nil)
check('an undestroyed old key is no longer the active one', activeKey() ~= spare)
instances[activeKey()].inventoryId = 2
check('an undestroyed old key does not open the car', call('keys', { assetId = assetId, action = 'lock' }).code == 'key_not_here')
instances[activeKey()].inventoryId = 1
-- A key from a former owner never counts; the current owner keeps access.
assetsById[assetId].owner.holderId = B
check('former owner with an old key is refused', call('keys', { assetId = assetId, action = 'lock' }).code == 'forbidden')
check('new owner has access without the old key', call('keys', { assetId = assetId, action = 'lock' }, 2).ok)
assetsById[assetId].owner.holderId = A
-- Vehicles taken out before keys existed stay usable by their owner only.
GarageKeys.Void(assetId)
check('owner uses a car with no key record', call('keys', { assetId = assetId, action = 'lock' }).ok)
check('stranger cannot use a car with no key record', call('keys', { assetId = assetId, action = 'lock' }, 2).code == 'forbidden')
-- Restart: a surviving car keeps its key, a vanished one loses it.
GarageKeys.Issue(assetsById[assetId], A)
local survivor = activeKey()
for _, fn in ipairs(threads) do
    fn()
end
check('restart keeps the key of a surviving car', activeKey() == survivor and instances[survivor])
check('restart keeps the key rule', call('keys', { assetId = assetId, action = 'lock' }, 2).code == 'forbidden')
entities[next(entities)] = nil
for _, fn in ipairs(threads) do
    fn()
end
check('restart voids the key of a vanished car', not activeKey() and not instances[survivor])
check('restart returns the vanished car to the garage', rows[orderId].status == 'stored')
destroyGuards['h4nr-garages:vehicle-key'] = nil
eventHandlers.onResourceStart('feather-inventory')
threads[#threads]()
check('inventory restart restores the guard', destroyGuards['h4nr-garages:vehicle-key'] ~= nil)
print(('server_spec: %d checks passed'):format(passed))

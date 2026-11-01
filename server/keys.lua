-- The physical key proves use: whoever carries the active instance may operate the vehicle.
-- Inventory owns the item; this table only records which instance is currently valid.
GarageKeys = {}
local ITEM, GUARD = 'vehicle_key', 'h4nr-garages:vehicle-key'
-- Mirrors the active rows. Inventory guards must not query or yield.
local byAsset, byInstance = {}, {}
local function Inventory()
    return exports['feather-inventory']:initiate()
end
local function Remember(assetId, instance, owner, rekeyAt)
    instance = tonumber(instance)
    byAsset[assetId], byInstance[instance] = { instance = instance, owner = owner, rekeyAt = tonumber(rekeyAt) }, assetId
end
local function Forget(assetId)
    local entry = byAsset[assetId]
    if entry then
        byAsset[assetId], byInstance[entry.instance] = nil, nil
    end
    return entry
end
local function Read(fn)
    local ok, result = pcall(fn)
    return ok and type(result) == 'table' and result.ok and result.value or nil
end
function GarageKeys.Migrate()
    DB.exec([[
        CREATE TABLE IF NOT EXISTS h4nr_feather_vehicle_keys (
            asset_id CHAR(36) NOT NULL PRIMARY KEY,
            generation INT UNSIGNED NOT NULL,
            key_instance_id BIGINT UNSIGNED NULL,
            owner_id CHAR(36) NOT NULL,
            issued_to CHAR(36) NOT NULL,
            status ENUM('active','void') NOT NULL,
            rekey_requested_at INT UNSIGNED NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
-- Players cannot throw an active key away. Server cleanup (no actor) still can, and a
-- voided key is an ordinary item, so nobody gets stuck with one.
function GarageKeys.InstallGuard()
    local api = Inventory()
    local installed = api.Guards.RegisterDestroyGuard(GUARD, function(instance, context)
        local id = type(instance) == 'table' and tonumber(instance.id)
        if id and byInstance[id] and type(context) == 'table' and context.actorSource then
            return false, GarageConfig.Key.destroyRefused
        end
        return true
    end)
    assert(installed.ok, 'vehicle key guard refused')
end
function GarageKeys.Start()
    byAsset, byInstance = {}, {}
    local rows = DB.query(
        "SELECT asset_id, key_instance_id, owner_id, rekey_requested_at FROM h4nr_feather_vehicle_keys WHERE status = 'active'"
    ) or {}
    for _, row in ipairs(rows) do
        Remember(row.asset_id, row.key_instance_id, row.owner_id, row.rekey_requested_at)
    end
    GarageKeys.InstallGuard()
end
function GarageKeys.ActiveAssets()
    local ids = {}
    for assetId in pairs(byAsset) do
        ids[#ids + 1] = assetId
    end
    return ids
end
function GarageKeys.Void(assetId)
    DB.exec(
        "UPDATE h4nr_feather_vehicle_keys SET status = 'void', rekey_requested_at = NULL WHERE asset_id = ? AND status = 'active'",
        assetId
    )
    local entry = Forget(assetId)
    if not entry then
        return
    end
    local ok, problem = pcall(function()
        local api = Inventory()
        local instance = api.Instances.GetInstance(entry.instance)
        if not instance.ok then
            return
        end
        local container = api.Inventory.GetContainerLifecycle(instance.value.inventoryId)
        assert(container.ok, 'container unavailable')
        local destroyed = api.DestroyInstances({ resource = GetCurrentResourceName(), reason = 'h4nr_garages.key_void' }, {
            inventoryId = instance.value.inventoryId,
            expectedLocation = container.value.location,
            instanceIds = { entry.instance },
        })
        assert(destroyed.ok, 'destroy refused')
    end)
    if not ok then
        print(('[h4nr-garages] voided key %s stays as an inert item: %s'):format(entry.instance, tostring(problem)))
    end
end
local function Definition()
    local definitions = Read(function()
        return Inventory().Items.GetDefinitions()
    end)
    for _, definition in pairs(definitions or {}) do
        if definition.name == ITEM and definition.instance_mode == 'unique' and not definition.archived_at then
            return tonumber(definition.id)
        end
    end
end
function GarageKeys.Issue(asset, characterId)
    local assetId = asset.assetId
    GarageKeys.Void(assetId)
    local definitionId = Definition()
    local inventory = Read(function()
        return exports['feather-inventory']:GetCharacterInventory(characterId)
    end)
    if not definitionId or not inventory then
        return Garage.Err('key_unavailable')
    end
    local capacity = Read(function()
        return Inventory().Inventory.InventoryCanHoldById({ { item = ITEM, quantity = 1 } }, inventory.id)
    end)
    if not capacity then
        return Garage.Err('key_unavailable')
    end
    if not capacity.accepted then
        return Garage.Err('inventory_full')
    end
    -- The generation is stored before the item exists: a crash in between leaves an
    -- item that no active row names, which never validates.
    DB.exec(
        [[INSERT INTO h4nr_feather_vehicle_keys (asset_id, generation, owner_id, issued_to, status)
        VALUES (?, 1, ?, ?, 'void')
        ON DUPLICATE KEY UPDATE generation = generation + 1, key_instance_id = NULL,
        owner_id = VALUES(owner_id), issued_to = VALUES(issued_to), status = 'void']],
        assetId,
        asset.owner.holderId,
        characterId
    )
    local generation = DB.one('SELECT generation FROM h4nr_feather_vehicle_keys WHERE asset_id = ?', assetId).generation
    local plate = asset.identifiers and asset.identifiers.plate or ''
    local granted = exports['feather-inventory']:GrantCharacterUniqueItemOnce({
        grantId = ('vehiclekey:%s:%s'):format(assetId, generation),
        characterId = characterId,
        definitionId = definitionId,
        itemName = ITEM,
        metadata = {
            version = 1,
            label = GarageConfig.Key.label:format(plate),
            assetId = assetId,
            plate = plate,
            model = asset.modelKey,
            generation = generation,
        },
    })
    if type(granted) ~= 'table' or not granted.ok then
        return Garage.Err('key_unavailable')
    end
    DB.exec(
        "UPDATE h4nr_feather_vehicle_keys SET key_instance_id = ?, status = 'active' WHERE asset_id = ?",
        granted.value.instanceId,
        assetId
    )
    Remember(assetId, granted.value.instanceId, asset.owner.holderId)
    return Garage.Ok(true)
end
-- A key issued under another owner does not count. With no current key (vehicle taken
-- out before keys existed, or moved by an admin) the owner still has access.
local function Current(assetId, owner)
    local entry = byAsset[assetId]
    return entry and entry.owner == owner and entry or nil
end
function GarageKeys.Allows(characterId, assetId, owner)
    local entry = Current(assetId, owner)
    if not entry then
        return characterId == owner
    end
    return Read(function()
        return Inventory().Instances.GetItemForCharacter(characterId, entry.instance)
    end) ~= nil
end
-- Asset IDs of the keys in this character's own inventory, with one read per call.
function GarageKeys.Held(characterId)
    local inventory = Read(function()
        return exports['feather-inventory']:GetCharacterInventory(characterId)
    end)
    local rows = inventory
        and Read(function()
            return Inventory().Inventory.GetInventoryItems(inventory.id)
        end)
    if not rows then
        return nil
    end
    local held = {}
    for _, row in pairs(rows) do
        local assetId = byInstance[tonumber(row.id)]
        if assetId then
            held[assetId] = true
        end
    end
    return held
end
function GarageKeys.IsLent(assetId, owner, held)
    return Current(assetId, owner) ~= nil and held ~= nil and not held[assetId]
end
function GarageKeys.IsCurrent(assetId, owner)
    return Current(assetId, owner) ~= nil
end
-- Recovery for an owner whose key is with someone else, or lost. Nothing is charged until
-- the wait is over and the owner confirms in person, so an abandoned request costs nothing.
local function ClearRekey(assetId, entry)
    if entry.rekeyAt then
        entry.rekeyAt = nil
        DB.exec('UPDATE h4nr_feather_vehicle_keys SET rekey_requested_at = NULL WHERE asset_id = ?', assetId)
    end
end
-- nil when not applicable (no current key, or the owner holds it, which ends any request).
function GarageKeys.RekeyState(assetId, owner, held)
    local entry = Current(assetId, owner)
    if not entry or not held then
        return nil
    end
    if held[assetId] then
        ClearRekey(assetId, entry)
        return nil
    end
    if not entry.rekeyAt then
        return { state = 'none' }
    end
    local left = entry.rekeyAt + GarageConfig.Rekey.waitSeconds - os.time()
    return left > 0 and { state = 'waiting', seconds = left } or { state = 'ready' }
end
function GarageKeys.RequestRekey(assetId)
    local entry = byAsset[assetId]
    entry.rekeyAt = os.time()
    DB.exec('UPDATE h4nr_feather_vehicle_keys SET rekey_requested_at = ? WHERE asset_id = ?', entry.rekeyAt, assetId)
    return entry.instance
end
function GarageKeys.Generation(assetId)
    return DB.one('SELECT generation FROM h4nr_feather_vehicle_keys WHERE asset_id = ?', assetId).generation
end
-- Handing the key over stops a running engine, so the previous holder cannot keep driving.
AddEventHandler('Feather:Inventory:ItemMoved', function(fact)
    local assetId = type(fact) == 'table' and byInstance[tonumber(fact.instanceId)]
    if assetId and fact.fromInventoryId ~= fact.toInventoryId and GarageKeys.OnKeyMoved then
        GarageKeys.OnKeyMoved(assetId)
    end
end)
AddEventHandler('onResourceStart', function(resource)
    if resource ~= 'feather-inventory' or not Garage.ready then
        return
    end
    CreateThread(function()
        local ready = exports['feather-inventory']:AwaitReady(30000)
        if not ready.ok or not pcall(GarageKeys.InstallGuard) then
            print('[h4nr-garages] vehicle key guard not restored after feather-inventory restart')
        end
    end)
end)
AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        pcall(function()
            Inventory().Guards.UnregisterDestroyGuard(GUARD)
        end)
    end
end)

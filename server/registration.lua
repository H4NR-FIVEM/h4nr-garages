-- Assets owns ownership; this table owns the purchase workflow and presentation.
Garage = { ready = false }
local assets = exports['feather-assets']
local busy = {}
function Garage.Ok(value)
    return { ok = true, value = value }
end
function Garage.Err(code)
    return { ok = false, code = code }
end
function Garage.Uuid(value)
    return type(value) == 'string'
        and #value == 36
        and value:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end
function Garage.Lock(key, fn)
    if busy[key] then
        return Garage.Err('busy')
    end
    busy[key] = true
    local ok, result = pcall(fn)
    busy[key] = nil
    if not ok then
        print('[h4nr-garages] operation failed: ' .. tostring(result))
        return Garage.Err('unavailable')
    end
    return result
end
function Garage.Row(assetId)
    return DB.one('SELECT * FROM h4nr_feather_vehicles WHERE asset_id = ?', assetId)
end
function Garage.Migrate()
    DB.exec([[
        CREATE TABLE IF NOT EXISTS h4nr_feather_vehicles (
            order_id CHAR(36) NOT NULL PRIMARY KEY,
            asset_id CHAR(36) NULL UNIQUE,
            asset_type VARCHAR(16) NOT NULL,
            model_key VARCHAR(100) NOT NULL,
            buyer_id CHAR(36) NOT NULL,
            purchase_props VARCHAR(512) NOT NULL,
            props_json MEDIUMTEXT NOT NULL,
            plate VARCHAR(8) NOT NULL,
            garage VARCHAR(64) NOT NULL,
            status ENUM('registering','stored','spawning','out','storing') NOT NULL DEFAULT 'registering',
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
local function OwnedPurchase(asset, row)
    return asset.managerResource == 'h4nr-garages'
        and asset.provenanceType == 'shop_purchase'
        and asset.provenanceId == row.order_id
        and asset.assetType == row.asset_type
        and asset.modelKey == row.model_key
        and asset.status == 'active'
        and asset.owner
        and asset.owner.holderType == 'character'
        and asset.owner.holderId == row.buyer_id
end
function Garage.Register(request)
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    if
        type(request) ~= 'table'
        or not Garage.Uuid(request.orderId)
        or not Garage.Uuid(request.holderId)
        or request.holderType ~= 'character'
        or type(request.modelKey) ~= 'string'
        or #request.modelKey > 100
        or not request.modelKey:match('^[A-Za-z0-9][A-Za-z0-9_%-]*$')
        or type(request.plate) ~= 'string'
        or #request.plate < 1
        or #request.plate > 8
        or not request.plate:match('^[A-Z0-9 ]+$')
        or not request.plate:find('[A-Z0-9]')
        or type(request.props) ~= 'table'
    then
        return Garage.Err('invalid_input')
    end
    local garageId = request.garage or GarageConfig.DefaultGarage[request.assetType]
    local definition = GarageConfig.Garages[garageId]
    if not definition or definition.assetType ~= request.assetType then
        return Garage.Err('invalid_garage')
    end
    local props = request.props
    for _, key in ipairs({ 'color1', 'color2' }) do
        if type(props[key]) ~= 'number' or props[key] % 1 ~= 0 or props[key] < 0 or props[key] > 160 then
            return Garage.Err('invalid_input')
        end
    end
    props = { color1 = props.color1, color2 = props.color2 }
    return Garage.Lock('order:' .. request.orderId, function()
        local row = DB.one('SELECT * FROM h4nr_feather_vehicles WHERE order_id = ?', request.orderId)
        if not row then
            local encoded = json.encode(props)
            DB.insert(
                [[INSERT INTO h4nr_feather_vehicles
                (order_id,asset_type,model_key,buyer_id,purchase_props,props_json,plate,garage)
                VALUES (?,?,?,?,?,?,?,?)]],
                request.orderId,
                request.assetType,
                request.modelKey,
                request.holderId,
                encoded,
                encoded,
                request.plate,
                garageId
            )
            row = DB.one('SELECT * FROM h4nr_feather_vehicles WHERE order_id = ?', request.orderId)
        end
        local original = json.decode(row.purchase_props)
        if
            row.asset_type ~= request.assetType
            or row.model_key ~= request.modelKey
            or row.buyer_id ~= request.holderId
            or original.color1 ~= props.color1
            or original.color2 ~= props.color2
            or row.garage ~= garageId
        then
            return Garage.Err('idempotency_conflict')
        end
        -- A completed purchase replays its delivery receipt even after a later sale.
        if row.status ~= 'registering' then
            return Garage.Ok({ assetId = row.asset_id, plate = row.plate, garage = row.garage })
        end
        local asset
        if row.asset_id then
            local read = assets:GetAsset({ assetId = row.asset_id })
            if not read.ok then
                return read
            end
            asset = read.value
        else
            local registered = assets:RegisterAsset({
                requestId = 'shop:' .. row.order_id,
                assetType = row.asset_type,
                modelKey = row.model_key,
                holderType = 'character',
                holderId = row.buyer_id,
                provenanceType = 'shop_purchase',
                provenanceId = row.order_id,
                reasonCode = 'h4nr_garages.purchase',
                referenceType = 'h4nr_vehicleshop_order',
                referenceId = row.order_id,
            })
            if registered.ok then
                asset = registered.value
            elseif registered.code == 'asset_exists' and registered.details and registered.details.assetId then
                local read = assets:GetAsset({ assetId = registered.details.assetId })
                if not read.ok then
                    return read
                end
                asset = read.value
            else
                return registered
            end
            if not OwnedPurchase(asset, row) then
                return Garage.Err('purchase_mismatch')
            end
            DB.exec('UPDATE h4nr_feather_vehicles SET asset_id = ? WHERE order_id = ?', asset.assetId, row.order_id)
        end
        local current = assets:GetAsset({ assetId = asset.assetId })
        if not current.ok then
            return current
        end
        asset = current.value
        if not OwnedPurchase(asset, row) then
            return Garage.Err('purchase_mismatch')
        end
        local plate = asset.identifiers and asset.identifiers.plate
        if not plate then
            -- Revision in the key permits a safe retry after an unrelated revision change.
            local assigned = assets:AssignAssetIdentifier({
                assetId = asset.assetId,
                expectedRevision = asset.revision,
                identifierType = 'plate',
                value = request.plate,
                requestId = ('plate:%s:%s:%s'):format(row.order_id, request.plate:gsub(' ', '_'), asset.revision),
                reasonCode = 'h4nr_garages.purchase_plate',
                referenceType = 'h4nr_vehicleshop_order',
                referenceId = row.order_id,
            })
            if not assigned.ok then
                return assigned.code == 'identifier_in_use' and Garage.Err('identifier_taken') or assigned
            end
            plate = assigned.value.identifiers.plate
        end
        DB.exec(
            [[UPDATE h4nr_feather_vehicles SET plate = ?, status = 'stored'
            WHERE order_id = ? AND status = 'registering']],
            plate,
            row.order_id
        )
        return Garage.Ok({ assetId = asset.assetId, plate = plate, garage = row.garage })
    end)
end
exports('RegisterPurchasedVehicle', function(request)
    if not GarageConfig.TrustedShops[GetInvokingResource()] then
        return Garage.Err('forbidden')
    end
    return Garage.Register(request)
end)
exports('GetCapabilities', function()
    local health = exports['feather-assets']:AwaitReady(0)
    return Garage.Ok({ ready = Garage.ready and health.ok == true, purchaseRegistration = 1, ownerKeys = 1 })
end)

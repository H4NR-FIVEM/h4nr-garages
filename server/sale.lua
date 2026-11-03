-- Sale support for trusted shops. The shop owns the offer and the money; the garage owns
-- the vehicle. A reserved vehicle cannot be taken out, so it cannot move between payment
-- and transfer. Ownership only changes here (Assets plan, D1).
local assets = exports['feather-assets']
local function Trusted(request)
    return GarageConfig.TrustedShops[GetInvokingResource()] and type(request) == 'table'
end
local function Valid(request)
    return Garage.Uuid(request.saleId) and Garage.Uuid(request.assetId)
end
-- Vehicles of one character that can be sold now, across every Assets page.
exports('ListParkedVehicles', function(request)
    if not Trusted(request) or not Garage.Uuid(request.holderId) then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    local items, cursor = {}, nil
    repeat
        local page = assets:ListAssetsByHolder({
            holderType = 'character',
            holderId = request.holderId,
            limit = 50,
            cursor = cursor,
        })
        if not page.ok then
            return page
        end
        for _, asset in ipairs(page.value.items) do
            local row = Garage.Row(asset.assetId)
            if row and row.status == 'stored' and asset.status == 'active' and asset.managerResource == 'h4nr-garages' then
                items[#items + 1] = {
                    assetId = asset.assetId,
                    assetType = asset.assetType,
                    model = asset.modelKey,
                    plate = asset.identifiers and asset.identifiers.plate,
                    garage = row.garage,
                }
            end
        end
        cursor = page.value.nextCursor
    until not cursor
    return Garage.Ok({ items = items })
end)
exports('ReserveForSale', function(request)
    if not Trusted(request) or not Valid(request) or not Garage.Uuid(request.sellerId) then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    return Garage.Lock(request.assetId, function()
        local row = Garage.Row(request.assetId)
        if not row then
            return Garage.Err('unavailable')
        end
        if row.status == 'sale_reserved' and row.sale_id == request.saleId then
            return Garage.Ok(true)
        end
        if row.status ~= 'stored' then
            return Garage.Err('vehicle_not_parked')
        end
        local check = assets:CheckInterest({
            assetId = request.assetId,
            holderType = 'character',
            holderId = request.sellerId,
        })
        if not check.ok or not check.value.matched or check.value.assetStatus ~= 'active' then
            return Garage.Err('forbidden')
        end
        local changed = DB.exec(
            "UPDATE h4nr_feather_vehicles SET status = 'sale_reserved', sale_id = ? WHERE asset_id = ? AND status = 'stored'",
            request.saleId,
            request.assetId
        )
        return changed == 1 and Garage.Ok(true) or Garage.Err('vehicle_not_parked')
    end)
end)
-- Releasing a reservation this sale does not hold is a successful no-op, so retries are safe.
exports('ReleaseSaleReservation', function(request)
    if not Trusted(request) or not Valid(request) then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    return Garage.Lock(request.assetId, function()
        DB.exec(
            "UPDATE h4nr_feather_vehicles SET status = 'stored', sale_id = NULL WHERE asset_id = ? AND status = 'sale_reserved' AND sale_id = ?",
            request.assetId,
            request.saleId
        )
        return Garage.Ok(true)
    end)
end)
-- Idempotent: repeating after a lost reply finds the buyer already holding the vehicle.
exports('TransferReservedVehicle', function(request)
    if
        not Trusted(request)
        or not Valid(request)
        or not Garage.Uuid(request.sellerId)
        or not Garage.Uuid(request.buyerId)
    then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    return Garage.Lock(request.assetId, function()
        local read = assets:GetAsset({ assetId = request.assetId })
        if not read.ok then
            return read
        end
        local asset, row = read.value, Garage.Row(request.assetId)
        if not row then
            return Garage.Err('unavailable')
        end
        local reserved = row.status == 'sale_reserved' and row.sale_id == request.saleId
        if not (asset.owner and asset.owner.holderId == request.buyerId) then
            if not reserved then
                return Garage.Err('reservation_lost')
            end
            -- Revision in the key permits a safe retry after an unrelated revision change.
            local moved = assets:TransferOwnership({
                requestId = ('sale:%s:%s'):format(request.saleId, asset.revision),
                assetId = request.assetId,
                expectedRevision = asset.revision,
                fromHolderType = 'character',
                fromHolderId = request.sellerId,
                toHolderType = 'character',
                toHolderId = request.buyerId,
                reasonCode = 'h4nr_garages.sale',
                referenceType = 'h4nr_vehicleshop_sale',
                referenceId = request.saleId,
            })
            if not moved.ok then
                return moved
            end
        end
        if reserved then
            DB.exec(
                "UPDATE h4nr_feather_vehicles SET status = 'stored', sale_id = NULL WHERE asset_id = ? AND sale_id = ?",
                request.assetId,
                request.saleId
            )
        end
        return Garage.Ok({ garage = row.garage })
    end)
end)
-- How many live vehicles of a model exist, so a shop can tell whether it may drop that model.
-- Retired vehicles keep their row, so Assets decides which ones still count.
exports('CountVehiclesByModel', function(request)
    if not Trusted(request) or type(request.modelKey) ~= 'string' then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    local count = 0
    for _, row in ipairs(DB.query('SELECT asset_id FROM h4nr_feather_vehicles WHERE model_key = ?', request.modelKey) or {}) do
        local read = row.asset_id and assets:GetAsset({ assetId = row.asset_id })
        if not read then
            count = count + 1
        elseif not read.ok then
            return read
        elseif read.value.status ~= 'retired' then
            count = count + 1
        end
    end
    return Garage.Ok({ count = count })
end)
-- Trade-in: the dealer takes a reserved vehicle off the road for good. The row keeps its
-- sale_id afterwards, which is what lets a retry after a lost reply prove it is the same sale.
exports('RetireReservedVehicle', function(request)
    if not Trusted(request) or not Valid(request) or not Garage.Uuid(request.sellerId) then
        return Garage.Err('forbidden')
    end
    if not Garage.ready then
        return Garage.Err('unavailable')
    end
    return Garage.Lock(request.assetId, function()
        local read = assets:GetAsset({ assetId = request.assetId })
        if not read.ok then
            return read
        end
        local asset, row = read.value, Garage.Row(request.assetId)
        if not row then
            return Garage.Err('unavailable')
        end
        if row.status ~= 'sale_reserved' or row.sale_id ~= request.saleId then
            return Garage.Err('reservation_lost')
        end
        if asset.status ~= 'retired' then
            if not (asset.owner and asset.owner.holderId == request.sellerId) then
                return Garage.Err('forbidden')
            end
            local retired = assets:RetireAsset({
                requestId = ('tradein:%s:%s'):format(request.saleId, asset.revision),
                assetId = request.assetId,
                expectedRevision = asset.revision,
                reasonCode = 'h4nr_garages.trade_in',
                referenceType = 'h4nr_vehicleshop_tradein',
                referenceId = request.saleId,
            })
            if not retired.ok then
                return retired
            end
        end
        GarageKeys.Void(request.assetId)
        return Garage.Ok(true)
    end)
end)

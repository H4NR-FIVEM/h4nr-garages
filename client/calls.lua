-- Garage RPC and notification helpers shared by the panel and the world interaction.
GarageCalls = {}
function GarageCalls.Message(key)
    local message = T(key)
    if message == Locales.en_us.failed or message == (Locales[GarageConfig.DefaultLang] or {}).failed then
        message = message .. ' (' .. tostring(key):sub(1, 64) .. ')'
    end
    return message
end
function GarageCalls.Notify(key)
    exports['feather-notify']:ShowNotification({ style = 'right', message = GarageCalls.Message(key), duration = 4000 })
end
-- Returns the value, or nil and the refusal code.
function GarageCalls.Request(name, params)
    local result, transport = FeatherRPC:CallAsync('h4nr-garages:' .. name, params)
    if type(result) ~= 'table' or not result.ok then
        local failure = type(result) == 'table' and result or type(transport) == 'table' and transport or {}
        local code = failure.code or (type(failure.error) == 'table' and failure.error.code) or 'invalid_response'
        print(('[h4nr-garages] RPC %s refused: code=%s'):format(name, tostring(code)))
        return nil, code
    end
    return result.value
end
function GarageCalls.Call(name, params)
    local value, code = GarageCalls.Request(name, params)
    if code then
        GarageCalls.Notify(code)
    end
    return value
end
local function ParkingProps(vehicle)
    local read = exports['feather-toolkit']:GetVehicleProperties(vehicle)
    -- Without properties the server refuses the parking, so nothing is lost.
    local props = read.ok and read.value or {}
    if GetResourceState('h4nr-fuel') == 'started' then
        props.fuelLevel = exports['h4nr-fuel']:GetFuel(vehicle)
    end
    return props
end
-- A trailer hitched to the vehicle is parked with it; the server decides again.
function GarageCalls.StoreParams(garageId, assetId, vehicle)
    local params = { garage = garageId, assetId = assetId, props = ParkingProps(vehicle) }
    local hitched, trailer = GetVehicleTrailerVehicle(vehicle)
    local trailerAsset = hitched and trailer ~= 0 and Entity(trailer).state.h4nrAssetId
    if trailerAsset then
        params.trailer = { assetId = trailerAsset, props = ParkingProps(trailer) }
    end
    return params
end
function GarageCalls.ParkedMessage(value)
    return type(value) == 'table' and value.trailerLeft and 'parked_trailer_left' or 'parked'
end

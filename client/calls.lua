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
function GarageCalls.StoreParams(garageId, assetId, vehicle)
    local props = lib.getVehicleProperties(vehicle)
    if GetResourceState('h4nr-fuel') == 'started' then
        props.fuelLevel = exports['h4nr-fuel']:GetFuel(vehicle)
    end
    return { garage = garageId, assetId = assetId, props = props }
end

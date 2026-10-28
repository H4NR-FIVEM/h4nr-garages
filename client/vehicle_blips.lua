-- Use coordinate blips so an owned car remains visible beyond streaming range.
GarageVehicleBlips = {}
local blips = {}
local config = GarageConfig.VehicleBlip

function GarageVehicleBlips.Clear()
    for _, entry in pairs(blips) do RemoveBlip(entry.handle) end
    blips = {}
end

function GarageVehicleBlips.Update(items)
    local seen = {}
    for _, item in ipairs(items) do
        seen[item.assetId] = true
        local entry = blips[item.assetId]
        local coords = item.coords
        if not entry then
            local handle = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(handle, config.sprite)
            SetBlipColour(handle, config.color)
            SetBlipScale(handle, config.scale)
            SetBlipAsShortRange(handle, false)
            entry = { handle = handle }
            blips[item.assetId] = entry
        else
            SetBlipCoords(entry.handle, coords.x, coords.y, coords.z)
        end
        local title = GarageConfig.DefaultLang == 'ro' and 'Vehiculul meu' or 'My vehicle'
        local label = title .. (item.plate and (' · ' .. item.plate) or '')
        if entry.label ~= label then
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentString(label)
            EndTextCommandSetBlipName(entry.handle)
            entry.label = label
        end
    end
    for assetId, entry in pairs(blips) do
        if not seen[assetId] then RemoveBlip(entry.handle); blips[assetId] = nil end
    end
end

function GarageVehicleBlips.Refresh()
    if not config.enabled or not exports['feather-character']:HasActiveCharacter() then
        return GarageVehicleBlips.Clear()
    end
    local cursor, characterId
    local seenCursors, items = {}, {}
    repeat
        local called, result = pcall(function()
            return FeatherRPC:CallAsync('h4nr-garages:locations', { cursor = cursor })
        end)
        if not called or type(result) ~= 'table' or not result.ok or type(result.value) ~= 'table' then
            return GarageVehicleBlips.Clear()
        end
        local page = result.value
        if characterId and page.characterId ~= characterId then return GarageVehicleBlips.Clear() end
        characterId = page.characterId
        for _, item in ipairs(page.items) do items[#items + 1] = item end
        cursor = page.nextCursor
        if cursor and seenCursors[cursor] then return GarageVehicleBlips.Clear() end
        if cursor then seenCursors[cursor] = true end
    until not cursor
    if not exports['feather-character']:HasActiveCharacter() then return GarageVehicleBlips.Clear() end
    GarageVehicleBlips.Update(items)
end

CreateThread(function()
    while true do
        GarageVehicleBlips.Refresh()
        Wait(math.max(1000, config.refreshMs))
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'feather-character' or resource == 'feather-core' then
        GarageVehicleBlips.Clear()
    end
end)

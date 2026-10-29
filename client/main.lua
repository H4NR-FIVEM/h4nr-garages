local menu = exports['feather-menu-v2']
local activeMenu, opening = nil, false
local function Notify(key)
    local message = T(key)
    if message == Locales.en_us.failed or message == (Locales[GarageConfig.DefaultLang] or {}).failed then
        message = message .. ' (' .. tostring(key):sub(1, 64) .. ')'
    end
    exports['feather-notify']:ShowNotification({ style = 'right', message = message, duration = 4000 })
end
local function Call(name, params)
    local result, transport = FeatherRPC:CallAsync('h4nr-garages:' .. name, params)
    if type(result) ~= 'table' or not result.ok then
        local failure = type(result) == 'table' and result or type(transport) == 'table' and transport or {}
        local code = failure.code or (type(failure.error) == 'table' and failure.error.code) or 'invalid_response'
        print(('[h4nr-garages] RPC %s refused: code=%s'):format(name, tostring(code)))
        Notify(code)
        return nil
    end
    return result.value
end
local currentHint
local function Hint(garageId, storing)
    local key = garageId and (garageId .. (storing and ':store' or ':open'))
    if key == currentHint then
        return
    end
    currentHint = key
    if not key then
        exports['feather-toolkit']:ClearControlHints()
        return
    end
    exports['feather-toolkit']:SetControlHints({
        tabs = {
            {
                title = GarageConfig.Garages[garageId].label,
                controls = { { key = 'E', label = T(storing and 'store_label' or 'open_label') } },
            },
        },
        activeTab = 1,
    })
end
local function Marker(at)
    local spec = GarageConfig.Marker
    DrawMarker(
        spec.type,
        at.x,
        at.y,
        at.z + 0.1,
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
local function Value(result)
    if not result.ok then
        error(result.code)
    end
    return result.value
end
local function Close()
    if activeMenu then
        local previous = activeMenu
        activeMenu = nil
        menu:DestroyMenu(previous)
    end
end
local function Open(garageId, cursor)
    if opening then
        return
    end
    opening = true
    local ok, problem = pcall(function()
        local ready = menu:AwaitReady(5000)
        if not ready.ok then
            Notify('menu_not_ready')
            return
        end
        local data = Call('list', { garage = garageId, cursor = cursor })
        if not data then
            return
        end
        if type(data) ~= 'table' or type(data.items) ~= 'table' then
            print('[h4nr-garages] RPC list returned invalid item data')
            Notify('invalid_response')
            return
        end
        Close()
        local id = Value(menu:CreateMenu({
            key = 'h4nr-garages',
            closable = true,
            theme = { preset = 'modern' },
            size = { width = '28rem', maxHeight = '80vh' },
        })).menuId
        activeMenu = id
        local page = Value(menu:CreatePage(id, { key = 'vehicles' })).pageId
        local elementIndex = 0
        local function Add(kind, spec, callback)
            elementIndex = elementIndex + 1
            spec.key = 'item-' .. elementIndex
            Value(menu:AddElement(id, page, kind, spec, callback))
        end
        Add('header', { value = GarageConfig.Garages[garageId].label, slot = 'header' })
        for _, item in ipairs(data.items) do
            local assetId = item.assetId
            local usable = item.available and (item.state == 'stored' or item.state == 'out')
            Add('button', {
                label = ('%s · %s · %s'):format(item.model, item.plate or '', T(item.state)),
                disabled = not usable,
            }, function()
                CreateThread(function()
                    local result = Call('retrieve', { garage = garageId, assetId = assetId })
                    if result then
                        Close()
                    end
                end)
            end)
        end
        if #data.items == 0 then
            Add('textdisplay', { value = T('unavailable') })
        end
        if data.nextCursor then
            Add('button', { label = T('next') }, function()
                CreateThread(function()
                    Open(garageId, data.nextCursor)
                end)
            end)
        end
        Add('button', { label = T('close'), slot = 'footer' }, Close)
        Value(menu:RegisterMenuLifecycle(id, function(event)
            if event.event == 'closed' and activeMenu == id then
                Close()
            end
        end))
        Value(menu:OpenMenu(id, { pageId = page }))
    end)
    opening = false
    if not ok then
        print('[h4nr-garages] menu: ' .. tostring(problem))
        Close()
        Notify('failed')
    end
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
        if not activeMenu and not opening and exports['feather-character']:HasActiveCharacter() then
            local coords, vehicle = GetEntityCoords(ped), GetVehiclePedIsIn(ped, false)
            for garageId, garage in pairs(GarageConfig.Garages) do
                local spawn = vector3(garage.spawn.x, garage.spawn.y, garage.spawn.z)
                local at = vehicle == 0 and garage.coords or spawn
                if #(coords - at) <= GarageConfig.Marker.drawDistance then
                    pause = 0
                    Marker(at)
                end
                local near = #(coords - garage.coords) <= GarageConfig.Distance
                    or (vehicle ~= 0 and #(coords - spawn) <= 8.0)
                local canPark = vehicle ~= 0
                    and GetPedInVehicleSeat(vehicle, -1) == ped
                    and Entity(vehicle).state.h4nrAssetId ~= nil
                if near and (vehicle == 0 or canPark) and not menu:IsInputCaptured() then
                    pause = 0
                    shownHint = true
                    Hint(garageId, vehicle ~= 0)
                    if IsControlJustReleased(0, 38) then
                        Hint(nil)
                        if vehicle == 0 then
                            Open(garageId)
                        else
                            local assetId = Entity(vehicle).state.h4nrAssetId
                            if assetId then
                                local props = lib.getVehicleProperties(vehicle)
                                if GetResourceState('h4nr-fuel') == 'started' then
                                    props.fuelLevel = exports['h4nr-fuel']:GetFuel(vehicle)
                                end
                                if Call('store', { garage = garageId, assetId = assetId, props = props }) then
                                    Notify('parked')
                                end
                            else
                                Notify('forbidden')
                            end
                        end
                    end
                    break
                end
            end
        end
        if not shownHint or activeMenu or opening then
            Hint(nil)
        end
        -- Prevent GTA's automatic engine start while the server says it is off.
        local vehicle = GetVehiclePedIsIn(ped, false)
        if
            vehicle ~= 0
            and Entity(vehicle).state.h4nrAssetId
            and Entity(vehicle).state.h4nrGarageEngine == false
            and GetPedInVehicleSeat(vehicle, -1) == ped
        then
            SetVehicleEngineOn(vehicle, false, true, true)
            pause = 0
        end
        Wait(pause)
    end
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() or resource == 'feather-menu-v2' then
        Hint(nil)
        Close()
    end
end)

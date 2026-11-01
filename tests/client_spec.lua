-- Client showroom against the real Feather Menu v2 implementation (its Lua side;
-- NUI clicks are sent through its elementAction callback). Natives are stubs.
local root = ROOT
local menuRoot = root .. '/../../[feather]/feather-menu-v2'
local passed = 0
local function check(name, condition)
    if not condition then
        error('FAIL: ' .. name, 2)
    end
    passed = passed + 1
end

local vmeta = {}
vmeta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta)
end
vmeta.__len = function(a)
    return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
end
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vmeta)
end
function vector4(x, y, z, w)
    return setmetatable({ x = x, y = y, z = z, w = w }, vmeta)
end

-- Menu v2 provider ------------------------------------------------------------
local api, nui, events = {}, {}, {}
local invoking = 'h4nr-garages'
function GetCurrentResourceName()
    return 'feather-menu-v2'
end
function GetInvokingResource()
    return invoking
end
function GetGameTimer()
    return 0
end
function GetResourceMetadata()
    return 'test'
end
exports = function(name, fn)
    api[name] = fn
end
function RegisterNUICallback(name, fn)
    nui[name] = fn
end
local stopHandlers = {}
function AddEventHandler(name, fn)
    events[name] = fn
    if name == 'onClientResourceStop' or name == 'onResourceStop' then
        stopHandlers[#stopHandlers + 1] = fn
    end
end
function SendNUIMessage() end
function SetNuiFocus() end
function SetNuiFocusKeepInput() end
function CreateThread() end
function Wait()
    coroutine.yield()
end
dofile(menuRoot .. '/client/results.lua')
dofile(menuRoot .. '/client/validation.lua')
dofile(menuRoot .. '/client/main.lua')
nui.ready({}, function() end)
function GetCurrentResourceName()
    return 'h4nr-garages'
end

local backgroundTasks = {}
-- Threads run until their first Wait; that is enough for these flows.
function CreateThread(fn)
    local co = coroutine.create(fn)
    backgroundTasks[#backgroundTasks + 1] = co
    local ok, problem = coroutine.resume(co)
    if not ok then
        error(problem, 0)
    end
end

-- Other providers -------------------------------------------------------------
local notes, hints, rpcCalls, replies = {}, {}, {}, {}
local providers = {
    ['feather-notify'] = {
        ShowNotification = function(spec)
            notes[#notes + 1] = spec.message
        end,
    },
    ['feather-toolkit'] = {
        SetControlHints = function(spec)
            hints[#hints + 1] = spec
        end,
        ClearControlHints = function()
            hints[#hints + 1] = false
        end,
        CreateBlip = function()
            return { ok = true, value = { handle = 1, id = 1 } }
        end,
    },
    ['feather-character'] = {
        HasActiveCharacter = function()
            return true
        end,
    },
}
exports = setmetatable({}, {
    __call = function(_, name, fn)
        api[name] = fn
    end,
    __index = function(_, name)
        if name == 'feather-menu-v2' then
            return setmetatable({}, {
                __index = function(_, method)
                    assert(api[method], method)
                    return function(_, ...)
                        return api[method](...)
                    end
                end,
            })
        end
        local provider = assert(providers[name], name)
        return setmetatable({}, {
            __index = function(_, method)
                local fn = assert(provider[method], name .. ':' .. method)
                return function(_, ...)
                    return fn(...)
                end
            end,
        })
    end,
})
FeatherRPC = {
    CallAsync = function(_, name, params)
        rpcCalls[#rpcCalls + 1] = { name = name, params = params }
        local reply = replies[name]
        if type(reply) == 'function' then
            return reply(params)
        end
        return reply
    end,
}
local netEvents = {}
function RegisterNetEvent(name, fn)
    netEvents[name] = fn
end

-- Natives -----------------------------------------------------------------------
local classes = { t20 = 7, zentorno = 7, adder = 7, sultanrs = 1, blista = 0 }
local hashes, names = {}, {}
function joaat(model)
    local key = model:lower()
    if not hashes[key] then
        hashes[key] = #names + 1
        names[#names + 1] = key
    end
    return hashes[key]
end
local function modelOf(hash)
    return names[hash]
end
-- Only a few models "exist", so categories are predictable; T20..Zentorno are Super.
local exist = { t20 = true, zentorno = true, adder = true, sultanrs = true, blista = true }
for i = 1, 14 do
    exist['super' .. i] = true
    classes['super' .. i] = 7
end
function IsModelInCdimage(hash)
    return exist[modelOf(hash)] == true
end
function IsModelAVehicle()
    return true
end
function GetVehicleClassFromName(hash)
    return classes[modelOf(hash)] or 0
end
function GetDisplayNameFromVehicleModel(hash)
    return modelOf(hash):upper()
end
function GetMakeNameFromVehicleModel()
    return 'PEGASSI'
end
function GetLabelText(label)
    return label == 'PEGASSI' and 'Pegassi' or 'NULL'
end
function GetVehicleModelEstimatedMaxSpeed()
    return 60.0
end
function GetVehicleModelAcceleration()
    return 0.35
end
function GetVehicleModelMaxBraking()
    return 1.0
end
function GetVehicleModelMaxTraction()
    return 2.8
end
function GetVehicleModelNumberOfSeats()
    return 2
end
for _, name in ipairs({
    'IsThisModelABoat',
    'IsThisModelAJetski',
    'IsThisModelAHeli',
    'IsThisModelAPlane',
    'IsThisModelABike',
    'IsThisModelABicycle',
}) do
    _G[name] = function()
        return false
    end
end
local ped = { coords = vector3(-33.0, -1103.0, 26.4), visible = true, frozen = false }
function PlayerPedId()
    return 1
end
function GetEntityCoords()
    return ped.coords
end
function GetEntityHeading()
    return 90.0
end
function SetEntityCoords(_, x, y, z)
    ped.coords = vector3(x, y, z)
end
function SetEntityHeading() end
function FreezeEntityPosition(entity, value)
    if entity == 1 then
        ped.frozen = value
    end
end
function SetEntityVisible(_, value)
    ped.visible = value
end
local vehicles, created = {}, {}
function CreateVehicle(hash)
    local id = 100 + #created + 1
    created[#created + 1] = modelOf(hash)
    vehicles[id] = { model = modelOf(hash) }
    return id
end
function DoesEntityExist(entity)
    return entity == 1 or vehicles[entity] ~= nil
end
function DeleteEntity(entity)
    vehicles[entity] = nil
end
local colours = {}
function SetVehicleColours(_, a, b)
    colours[#colours + 1] = { a, b }
end
function GetModelDimensions()
    return vector3(-1, -2.3, -0.6), vector3(1, 2.3, 0.6)
end
local camActive = false
function RenderScriptCams(active)
    camActive = active
end
function IsScreenFadedOut()
    return true
end
function IsScreenFadedIn()
    return true
end
function HasModelLoaded()
    return true
end
function CreateCam()
    return 9
end
for _, name in ipairs({
    'DoScreenFadeOut',
    'DoScreenFadeIn',
    'RequestCollisionAtCoord',
    'SetEntityInvincible',
    'SetFocusPosAndVel',
    'SetCamFov',
    'SetCamCoord',
    'PointCamAtCoord',
    'DisplayRadar',
    'RequestModel',
    'SetModelAsNoLongerNeeded',
    'SetEntityCollision',
    'SetVehicleOnGroundProperly',
    'SetVehicleDirtLevel',
    'SetVehicleNumberPlateText',
    'SetVehicleLights',
    'DestroyCam',
    'ClearFocus',
}) do
    _G[name] = function() end
end

-- Garage client against the real Menu v2 provider.
local commands = {}
function RegisterCommand(name, fn)
    commands[name] = fn
end
function RegisterKeyMapping() end
function GetResourceState()
    return 'stopped'
end
local currentVehicle = 0
function GetVehiclePedIsIn()
    return currentVehicle
end
function GetPedInVehicleSeat()
    return 1
end
function Entity()
    return { state = { h4nrAssetId = '11111111-1111-1111-1111-111111111111', h4nrGarageEngine = true } }
end
local markers = {}
function DrawMarker(kind, x, y, z)
    markers[#markers + 1] = { kind = kind, x = x, y = y, z = z }
end
function AddBlipForCoord()
    return 1
end
for _, name in ipairs({
    'SetBlipSprite',
    'SetBlipColour',
    'SetBlipScale',
    'SetBlipAsShortRange',
    'BeginTextCommandSetBlipName',
    'AddTextComponentString',
    'EndTextCommandSetBlipName',
    'BeginTextCommandDisplayHelp',
    'AddTextComponentSubstringPlayerName',
    'EndTextCommandDisplayHelp',
}) do
    _G[name] = function() end
end
local pressed = true
function IsControlJustReleased()
    local result = pressed
    pressed = false
    return result
end
lib = {
    getClosestVehicle = function()
        return nil
    end,
}
local id = '11111111-1111-1111-1111-111111111111'
replies['h4nr-garages:list'] = {
    ok = true,
    value = {
        items = {
            { assetId = id, model = 't20', plate = 'LS12 ABC', state = 'stored', available = true },
            { assetId = 'other', model = 'adder', plate = 'LS99 XYZ', state = 'stored', available = false },
        },
    },
}
replies['h4nr-garages:retrieve'] = { ok = true, value = { netId = 12 } }
dofile(root .. '/config/shared.lua')
dofile(root .. '/locale.lua')
dofile(root .. '/languages/ro.lua')
dofile(root .. '/languages/en_us.lua')
ped.coords = GarageConfig.Garages.pillboxgarage.coords
dofile(root .. '/client/main.lua')
local currentMenu = api.GetHealth().value.activeMenuId
check('garage opens actual Menu v2', currentMenu ~= nil)
local state = api.GetMenuState(currentMenu).value
local page = state.pages[1]
check('garage label in Romanian', page.elements[1].data.value == 'Pillbox — Garaj')
local car = page.elements[2]
check('registered plate shown', car.data.label:find('LS12 ABC', 1, true) ~= nil)
check('available car enabled', not car.data.disabled)
check('unavailable car disabled', page.elements[3].data.disabled)
local response
nui.elementAction(
    { menuId = currentMenu, pageId = page.pageId, elementId = car.elementId, event = 'activate' },
    function(r)
        response = r
    end
)
check('retrieve button uses real menu callback', response.ok)
check(
    'retrieval references asset UUID',
    rpcCalls[#rpcCalls].name == 'h4nr-garages:retrieve'
        and rpcCalls[#rpcCalls].params.assetId == id
        and rpcCalls[#rpcCalls].params.garage == 'pillboxgarage'
)
check('successful retrieval releases menu focus', api.GetHealth().value.activeMenuId == nil)
check('owner key commands registered', commands.feathervehiclelock and commands.feathervehicleengine)
check(
    'job-style arrow marks the garage',
    markers[1].kind == 2 and markers[1].x == GarageConfig.Garages.pillboxgarage.coords.x
)
local sawHint = false
for _, hint in ipairs(hints) do
    if hint and hint.tabs[1].controls[1].key == 'E' and hint.tabs[1].controls[1].label == T('open_label') then
        sawHint = true
    end
end
check('on-foot prompt explains E interaction', sawHint)
local mainTask = backgroundTasks[1]
local function frame()
    local ok, problem = coroutine.resume(mainTask)
    assert(ok, problem)
end
currentVehicle = 77
ped.coords = vector3(
    GarageConfig.Garages.pillboxgarage.spawn.x,
    GarageConfig.Garages.pillboxgarage.spawn.y,
    GarageConfig.Garages.pillboxgarage.spawn.z
)
frame()
check('driver sees parking marker at the spawn point', markers[#markers].x == ped.coords.x)
check('driver prompt offers E to park', hints[#hints].tabs[1].controls[1].label == T('store_label'))
currentVehicle = 0
ped.coords = GarageConfig.Garages.pillboxgarage.coords
pressed = true
replies['h4nr-garages:list'] = function()
    return nil, { code = 'timeout' }
end
frame()
check('transport errors show a precise translated cause', notes[#notes] == T('timeout'))
pressed = true
replies['h4nr-garages:list'] = { ok = false, code = 'test_unknown_code' }
frame()
check('unknown server refusal exposes its stable code', notes[#notes]:find('test_unknown_code', 1, true) ~= nil)
-- Recovery with a new key
local function openRekey(rekey)
    replies['h4nr-garages:list'] = {
        ok = true,
        value = {
            rekeyPrice = 2500,
            items = { { assetId = id, model = 't20', plate = 'LS12 ABC', state = 'out', available = true, rekey = rekey } },
        },
    }
    pressed = true
    frame()
    local menuId = api.GetHealth().value.activeMenuId
    return menuId, api.GetMenuState(menuId).value.pages[1]
end
local function click(menuId, opened, element)
    nui.elementAction(
        { menuId = menuId, pageId = opened.pageId, elementId = element.elementId, event = 'activate' },
        function() end
    )
end
replies['h4nr-garages:rekey'] = { ok = true, value = { state = 'waiting', seconds = 600 } }
local menuId, opened = openRekey({ state = 'none' })
check('recovery is offered with the plate', opened.elements[3].data.label == T('rekey_request'):format('LS12 ABC'))
click(menuId, opened, opened.elements[3])
check('the first press sends no payment method', rpcCalls[#rpcCalls].name == 'h4nr-garages:rekey'
    and rpcCalls[#rpcCalls].params.assetId == id and rpcCalls[#rpcCalls].params.method == nil)
check('the first press explains the wait', notes[#notes] == T('rekey_requested'))
menuId, opened = openRekey({ state = 'waiting', seconds = 61 })
check('the wait rounds up to minutes and cannot be pressed',
    opened.elements[3].data.label == T('rekey_wait'):format('LS12 ABC', 2) and opened.elements[3].data.disabled)
api.DestroyMenu(menuId)
menuId, opened = openRekey({ state = 'ready' })
check('both payment methods show the price', opened.elements[3].data.label == T('rekey_pay_cash'):format('LS12 ABC', 2500)
    and opened.elements[4].data.label == T('rekey_pay_bank'):format('LS12 ABC', 2500))
replies['h4nr-garages:rekey'] = { ok = true, value = { state = 'done' } }
click(menuId, opened, opened.elements[4])
check('paying sends the chosen method', rpcCalls[#rpcCalls].params.method == 'bank')
check('recovery confirms the result', notes[#notes] == T('rekey_done'))
local streamed = true
function NetworkDoesEntityExistWithNetworkId()
    return streamed
end
function NetToVeh(netId)
    return netId + 1000
end
lib.getVehicleProperties = function(vehicle)
    return { fromVehicle = vehicle }
end
replies['h4nr-garages:store'] = { ok = true, value = true }
local function openParkable()
    replies['h4nr-garages:list'] = {
        ok = true,
        value = {
            items = {
                { assetId = id, model = 'hydra', plate = 'LS56 FEU', state = 'out', available = false, parkNetId = 7 },
            },
        },
    }
    pressed = true
    frame()
    local menuId = api.GetHealth().value.activeMenuId
    return menuId, api.GetMenuState(menuId).value.pages[1]
end
menuId, opened = openParkable()
check('a car in range offers parking, even from another garage',
    opened.elements[2].data.label:find(T('store_label'), 1, true) and not opened.elements[2].data.disabled)
click(menuId, opened, opened.elements[2])
check('the menu parks the listed car with its own properties', rpcCalls[#rpcCalls].name == 'h4nr-garages:store'
    and rpcCalls[#rpcCalls].params.assetId == id and rpcCalls[#rpcCalls].params.props.fromVehicle == 1007)
check('parking from the menu confirms and closes', notes[#notes] == T('parked') and api.GetHealth().value.activeMenuId == nil)
streamed = false
menuId, opened = openParkable()
local callsBefore = #rpcCalls
click(menuId, opened, opened.elements[2])
check('a car that left the stream is not parked', #rpcCalls == callsBefore and notes[#notes] == T('too_far'))
print(('client_spec: %d checks passed'):format(passed))

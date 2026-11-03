-- Client world interaction and the garage panel's Lua side. Natives and the page are stubs;
-- tests/browser_spec.mjs covers the page itself.
local root = ROOT
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

local nui, events = {}, {}
function GetCurrentResourceName()
    return 'h4nr-garages'
end
function GetGameTimer()
    return 0
end
function RegisterNUICallback(name, fn)
    nui[name] = fn
end
function AddEventHandler(name, fn)
    events[name] = events[name] or {}
    table.insert(events[name], fn)
end
local sent, focused = {}, false
function SendNUIMessage(message)
    sent[#sent + 1] = message
end
function SetNuiFocus(enabled)
    focused = enabled
end
function SetNuiFocusKeepInput() end
function Wait()
    coroutine.yield()
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
local restored = {}
local providers = {
    ['feather-notify'] = {
        ShowNotification = function(spec)
            notes[#notes + 1] = spec.message
        end,
    },
    ['feather-toolkit'] = {
        GetVehicleProperties = function(entity)
            return { ok = true, value = { fromVehicle = entity } }
        end,
        SetVehicleProperties = function(entity, props)
            restored[#restored + 1] = { entity = entity, props = props }
            return { ok = true, value = true }
        end,
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
    ['feather-menu-v2'] = {
        IsInputCaptured = function()
            return false
        end,
    },
}
local exported = {}
exports = setmetatable({}, {
    __call = function(_, name, fn)
        exported[name] = fn
    end,
    __index = function(_, name)
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
local hashes, names = {}, {}
function joaat(model)
    local key = model:lower()
    if not hashes[key] then
        hashes[key] = #names + 1
        names[#names + 1] = key
    end
    return hashes[key]
end
function GetDisplayNameFromVehicleModel(hash)
    return names[hash]:upper()
end
function GetLabelText(label)
    return label == 'T20' and 'T20 Progen' or 'NULL'
end
local ped = { coords = vector3(-33.0, -1103.0, 26.4) }
function PlayerPedId()
    return 1
end
function GetEntityCoords()
    return ped.coords
end
local dead = false
function IsEntityDead()
    return dead
end

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
local seatTaken = 1
function GetPedInVehicleSeat()
    return seatTaken
end
function DoesEntityExist()
    return true
end
vehicleState = { h4nrAssetId = '11111111-1111-1111-1111-111111111111', h4nrGarageEngine = true }
function Entity()
    return { state = vehicleState }
end
engineStops, disabledControls = 0, {}
function SetVehicleEngineOn(_, on)
    if on == false then
        engineStops = engineStops + 1
    end
end
function DisableControlAction(_, control)
    disabledControls[control] = true
end
local groundZ
function GetGroundZFor_3dCoord()
    return groundZ ~= nil, groundZ or 0.0
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
local pressed, pressedControl = true, 38
function IsControlJustReleased(_, control)
    if control ~= pressedControl then
        return false
    end
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
            { assetId = id, model = 't20', plate = 'LS12 ABC', state = 'stored', available = true, garage = 'pillboxgarage' },
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
dofile(root .. '/client/calls.lua')
dofile(root .. '/client/nui.lua')
local function reply(fn)
    local answer
    fn(function(value)
        answer = value
    end)
    return answer
end
local function lastSent(action)
    for index = #sent, 1, -1 do
        if sent[index].action == action then
            return sent[index]
        end
    end
end
local function row(view, assetId)
    for _, item in ipairs(view.items) do
        if item.id == assetId then
            return item
        end
    end
end
local function act(assetId, action, method, session)
    return reply(function(cb)
        nui.action({ session = session or lastSent('open').session, assetId = assetId, id = action, method = method }, cb)
    end)
end
reply(function(cb)
    nui.ready({}, cb)
end)
dofile(root .. '/client/main.lua')
check('the panel opens with focus', focused and lastSent('open').label == 'Pillbox — Garaj')
check('the panel names what kind of place it is', lastSent('open').kind == T('kind_vehicle'))
local view = lastSent('view')
local car = row(view, id)
check('the plate is shown', car.plate == 'LS12 ABC')
check('the game label replaces the model key', car.name == 'T20 Progen')
check('a model without a label keeps its key', row(view, 'other').name == 'adder')
check('a stored car can be retrieved', car.actions[1].id == 'retrieve' and car.group == 'stored')
check('an unavailable car offers nothing and says so', #row(view, 'other').actions == 0 and row(view, 'other').reason == T('unavailable'))
check('names are sorted', view.items[1].name == 'T20 Progen')
check('an action the car does not offer is refused', not act(id, 'park').ok and #rpcCalls == 1)
check('an unknown car is refused', not act('nobody', 'retrieve').ok and #rpcCalls == 1)
check('an old page is refused', not act(id, 'retrieve', nil, -1).ok and #rpcCalls == 1)
replies['h4nr-garages:retrieve'] = { ok = false, code = 'spawn_blocked' }
local refused = act(id, 'retrieve')
check('a refusal stays in the panel', not refused.ok and refused.message == T('spawn_blocked') and focused and #notes == 0)
replies['h4nr-garages:retrieve'] = { ok = true, value = { netId = 12 } }
local retrieved = act(id, 'retrieve')
check('the panel closes after retrieval', retrieved.closed and not focused and lastSent('close') ~= nil)
check(
    'retrieval references asset UUID',
    rpcCalls[#rpcCalls].name == 'h4nr-garages:retrieve'
        and rpcCalls[#rpcCalls].params.assetId == id
        and rpcCalls[#rpcCalls].params.garage == 'pillboxgarage'
)
check('a closed panel accepts nothing', not act(id, 'retrieve').ok)
check('owner key commands registered', commands.feathervehiclelock and commands.feathervehicleengine)
check(
    'job-style arrow marks the garage',
    markers[1].kind == 2 and markers[1].x == GarageConfig.Garages.pillboxgarage.coords.x
        and GarageConfig.Marker.scale == 0.2 and GarageConfig.Marker.color[4] == 155
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
check('before the ground loads the arrow still shows', markers[#markers].z == ped.coords.z + 1.0)
groundZ = ped.coords.z - 1.0
frame()
local arrowHeight = groundZ + GarageConfig.Marker.height
check('the arrow stands at job height above the ground', markers[#markers].z == arrowHeight)
groundZ = 90.0
frame()
check('the ground is read once', markers[#markers].z == arrowHeight)
local pillboxSpawn = ped.coords
local water = GarageConfig.Garages.marina.spawn
ped.coords = vector3(water.x, water.y, water.z)
groundZ = -20.0
frame()
check('over water the arrow stays above the seabed', markers[#markers].z == water.z - 1.5 + GarageConfig.Marker.height)
ped.coords = pillboxSpawn
frame()
check('driver prompt offers R to park', hints[#hints].tabs[1].controls[1].key == 'R' and hints[#hints].tabs[1].controls[1].label == T('store_label'))
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
-- Driving needs the key even when someone left the engine running.
vehicleState = { h4nrAssetId = id, h4nrGarageEngine = true }
clock = 100000
function GetGameTimer()
    return clock
end
engineStops, disabledControls = 0, {}
currentVehicle = 88
ped.coords = vector3(0, 0, 0)
replies['h4nr-garages:canDrive'] = { ok = true, value = { allowed = false } }
frame()
check('the wheel asks the server', rpcCalls[#rpcCalls].name == 'h4nr-garages:canDrive' and rpcCalls[#rpcCalls].params.assetId == id)
check('a running engine stops for a driver without the key', engineStops > 0)
check('a driver without the key cannot accelerate', disabledControls[71] and disabledControls[72])
check('the driver is told why', notes[#notes] == T('key_not_here'))
local told, asked = #notes, #rpcCalls
frame()
check('the check is rate limited', #rpcCalls == asked)
clock = clock + GarageConfig.Key.checkMs
frame()
check('the check repeats', #rpcCalls == asked + 1)
check('the refusal is not repeated', #notes == told)
replies['h4nr-garages:canDrive'] = { ok = true, value = { allowed = true } }
clock = clock + GarageConfig.Key.checkMs
frame()
engineStops, disabledControls = 0, {}
frame()
check('with the key a running engine is left alone', engineStops == 0 and not disabledControls[71])
vehicleState.h4nrGarageEngine = false
frame()
check('with the key a stopped engine still waits for G', engineStops > 0 and not disabledControls[71])
vehicleState.h4nrGarageEngine = true
replies['h4nr-garages:canDrive'] = function()
    return nil, { code = 'timeout' }
end
clock = clock + GarageConfig.Key.checkMs
frame()
engineStops = 0
frame()
check('a failed check blocks driving', engineStops > 0 and disabledControls[71])
currentVehicle = 0
frame()
replies['h4nr-garages:canDrive'] = { ok = true, value = { allowed = true } }
currentVehicle = 88
engineStops = 0
frame()
check('getting back in starts a new check', rpcCalls[#rpcCalls].name == 'h4nr-garages:canDrive')
currentVehicle = 0
vehicleState = {}
ped.coords = GarageConfig.Garages.pillboxgarage.coords
frame()
-- Status and actions per situation
local function open(items, rekeyPrice)
    GaragePanel.Close()
    replies['h4nr-garages:list'] = { ok = true, value = { items = items, rekeyPrice = rekeyPrice } }
    pressed = true
    frame()
    return lastSent('view'), lastSent('open').session
end
local function vehicle(extra)
    local item = { assetId = id, model = 't20', plate = 'LS12 ABC', state = 'out', available = true, garage = 'pillboxgarage' }
    for key, value in pairs(extra) do
        item[key] = value
    end
    return item
end
view = open({ vehicle({ state = 'stored', garage = 'burtongarage', condition = { engine = 90, body = 80, fuel = 55 } }) })
check('a stored car says where it is', view.items[1].status == T('stored_at'):format('Burton — Garaj'))
check('the condition reaches the page', view.items[1].condition.fuel == 55)
view = open({ vehicle({ onStreet = true }) })
check('a car on the street points to the map', #view.items[1].actions == 0 and view.items[1].reason == T('on_street'))
view = open({ vehicle({ onStreet = false }) })
check('a car no longer on the street can come back', view.items[1].actions[1].id == 'retrieve' and view.items[1].status == T('out_lost'))
view = open({ vehicle({ state = 'sale_reserved' }) })
check('a reserved car offers nothing', #view.items[1].actions == 0 and view.items[1].status == T('sale_reserved'))
view = open({ vehicle({ state = 'spawning' }) })
check('a state in progress has its own text', view.items[1].status == T('working') and #view.items[1].actions == 0)
-- Recovery with a new key
replies['h4nr-garages:rekey'] = { ok = true, value = { state = 'waiting', seconds = 600 } }
local session
view, session = open({ vehicle({ rekey = { state = 'none' } }) }, 2500)
check('recovery is offered and priced', view.items[1].actions[1].label == T('rekey_request')
    and view.items[1].reason == T('rekey_explain'):format(2500) and view.items[1].status == T('key_elsewhere'))
replies['h4nr-garages:list'] = { ok = true, value = { items = { vehicle({ rekey = { state = 'waiting', seconds = 61 } }) } } }
local first = act(id, 'rekey')
check('the first press sends no payment method', rpcCalls[#rpcCalls - 1].name == 'h4nr-garages:rekey'
    and rpcCalls[#rpcCalls - 1].params.assetId == id and rpcCalls[#rpcCalls - 1].params.method == nil)
check('the first press explains the wait', first.ok and first.message == T('rekey_requested') and focused)
view = lastSent('view')
check('the wait rounds up to minutes and cannot be pressed',
    view.items[1].actions[1].label == T('rekey_wait'):format(2) and view.items[1].actions[1].disabled)
check('a disabled action is refused', not act(id, 'rekey').ok)
view = open({ vehicle({ rekey = { state = 'ready' } }) }, 2500)
check('both payment methods show the price', view.items[1].actions[1].label == T('rekey_pay_cash'):format(2500)
    and view.items[1].actions[2].label == T('rekey_pay_bank'):format(2500))
check('a payment method must be one offered', not act(id, 'rekey', 'crypto').ok)
replies['h4nr-garages:rekey'] = { ok = true, value = { state = 'done' } }
local paid = act(id, 'rekey', 'bank')
check('paying sends the chosen method', rpcCalls[#rpcCalls - 1].params.method == 'bank')
check('recovery confirms the result', paid.message == T('rekey_done'))
-- Parking from the panel
local streamed = true
function NetworkDoesEntityExistWithNetworkId()
    return streamed
end
function NetToVeh(netId)
    return netId + 1000
end
replies['h4nr-garages:store'] = { ok = true, value = true }
local function parkable(extra)
    return vehicle({ model = 'hydra', plate = 'LS56 FEU', available = false, parkNetId = 7, rekey = extra })
end
view = open({ parkable() })
check('a car in range offers parking, even from another garage', view.items[1].nearby and view.items[1].actions[1].id == 'park')
local parked = act(id, 'park')
check('the panel parks the listed car with its own properties', rpcCalls[#rpcCalls].name == 'h4nr-garages:store'
    and rpcCalls[#rpcCalls].params.assetId == id and rpcCalls[#rpcCalls].params.props.fromVehicle == 1007)
check('parking confirms and closes', parked.closed and notes[#notes] == T('parked') and not focused)
view = open({ parkable({ state = 'none' }) })
check('a car whose key is elsewhere offers recovery, not parking', not view.items[1].nearby and view.items[1].actions[1].id == 'rekey')
streamed = false
open({ parkable() })
local callsBefore = #rpcCalls
local gone = act(id, 'park')
check('a car that left the stream is not parked', #rpcCalls == callsBefore and gone.message == T('too_far'))
-- Paging, and the panel's end of life
GaragePanel.Close()
replies['h4nr-garages:list'] = function(params)
    if params.cursor then
        return { ok = true, value = { items = { vehicle({ assetId = 'second' }) } } }
    end
    return { ok = true, value = { items = { vehicle({}) }, nextCursor = 'next' } }
end
pressed = true
frame()
check('every page reaches the panel', #lastSent('view').items == 2)
check('the open panel closes when the player dies', (function()
    dead = true
    frame()
    dead = false
    return not focused
end)())
open({ vehicle({}) })
ped.coords = vector3(0, 0, 0)
frame()
check('the open panel closes when the player is moved away', not focused)
ped.coords = GarageConfig.Garages.pillboxgarage.coords
open({ vehicle({}) })
reply(function(cb)
    nui.close({}, cb)
end)
check('the page can close the panel', not focused)
open({ vehicle({}) })
for _, handler in ipairs(events.onClientResourceStop) do
    handler('h4nr-garages')
end
check('stopping the resource releases focus', not focused)
-- Swapping cars: the old one is parked first.
streamed = true
local parkedOld = vehicle({ assetId = 'old', model = 'adder', plate = 'LS11 AAA', available = false, parkNetId = 7 })
local stored = vehicle({ state = 'stored' })
ped.coords = GarageConfig.Garages.pillboxgarage.coords
view = open({ parkedOld, stored })
car = row(view, id)
check('a stored car offers to park the old one', car.actions[1].id == 'swap' and car.actions[1].label == T('swap'):format('adder'))
check('a stored car can also come out beside the old one', car.actions[2].id == 'retrieve')
check('the old car itself does not offer a swap', #row(view, 'old').actions == 1 and row(view, 'old').actions[1].id == 'park')
local before = #rpcCalls
replies['h4nr-garages:retrieve'] = { ok = true, value = { netId = 12 } }
local swapped = act(id, 'swap')
check('the old car is parked before the new one comes out', rpcCalls[before + 1].name == 'h4nr-garages:store'
    and rpcCalls[before + 1].params.assetId == 'old' and rpcCalls[before + 2].name == 'h4nr-garages:retrieve'
    and rpcCalls[before + 2].params.assetId == id)
check('the swap closes the panel', swapped.closed and not focused)
open({ parkedOld, stored })
replies['h4nr-garages:store'] = { ok = false, code = 'key_not_here' }
before = #rpcCalls
local kept = act(id, 'swap')
check('a refused parking takes nothing out', kept.message == T('key_not_here') and #rpcCalls == before + 1 and focused)
replies['h4nr-garages:store'] = { ok = true, value = true }
replies['h4nr-garages:retrieve'] = { ok = false, code = 'spawn_blocked' }
local views = #sent
local half = act(id, 'swap')
check('a refused retrieval reports and refreshes the list', half.message == T('spawn_blocked') and #sent > views and focused)
replies['h4nr-garages:retrieve'] = { ok = true, value = { netId = 12 } }
view = open({ stored })
check('with no old car there is only retrieval', #view.items[1].actions == 1 and view.items[1].actions[1].id == 'retrieve')
GaragePanel.Close()
-- On foot beside the car: R parks it, E opens the list.
local function hint()
    return hints[#hints] and hints[#hints].tabs[1].controls or {}
end
local allowed = true
replies['h4nr-garages:canDrive'] = function()
    return { ok = true, value = { allowed = allowed } }
end
replies['h4nr-garages:list'] = { ok = true, value = { items = { stored } } }
seatTaken, clock = 0, clock + 1000
vehicleState = { h4nrAssetId = id }
lib.getClosestVehicle = function()
    return 55
end
frame()
clock = clock + 1000
frame()
check('beside your empty car at the point, E opens the list and R parks',
    hint()[1].key == 'E' and hint()[1].label == T('open_label') and hint()[2].key == 'R' and hint()[2].label == T('store_label'))
before = #rpcCalls
pressed, pressedControl = true, 45
frame()
local storing
for index = before + 1, #rpcCalls do
    if rpcCalls[index].name == 'h4nr-garages:store' then
        storing = rpcCalls[index]
    end
end
check('R parks the car beside you', storing and storing.params.assetId == id and storing.params.props.fromVehicle == 55)
pressed, pressedControl = true, 38
frame()
check('E opens the list beside the car', focused)
GaragePanel.Close()
pressedControl = 38
-- Away from the point, but beside the car and inside the garage's range.
local point = GarageConfig.Garages.pillboxgarage.coords
ped.coords = vector3(point.x + 20, point.y, point.z)
clock = clock + 1000
frame()
check('away from the point R still parks, with no list', hint()[1].key == 'R' and hint()[2] == nil)
pressed = true
frame()
check('away from the point E does nothing', not focused and pressed)
pressed = false
allowed = false
clock = clock + GarageConfig.Key.checkMs + 1000
frame()
clock = clock + 1000
frame()
check('without the key no parking is offered', hints[#hints] == false)
allowed = true
seatTaken = 1
clock = clock + GarageConfig.Key.checkMs + 1000
frame()
clock = clock + 1000
frame()
check('a car with a driver is not offered', hints[#hints] == false)
-- At the wheel R parks, in the vehicle's own R control, and E no longer does.
seatTaken, currentVehicle = 1, 77
vehicleState = { h4nrAssetId = id }
ped.coords = pillboxSpawn
before = #rpcCalls
replies['h4nr-garages:canDrive'] = { ok = true, value = { allowed = true } }
pressed, pressedControl = true, 38
frame()
check('at the wheel E does not park', pressed and #rpcCalls <= before + 1 and rpcCalls[#rpcCalls].name ~= 'h4nr-garages:store')
pressed, pressedControl = true, 80
frame()
check('at the wheel R parks', rpcCalls[#rpcCalls].name == 'h4nr-garages:store')
pressed, pressedControl, currentVehicle = false, 38, 0
-- The car comes out as it was parked, through Toolkit.
local readyProps = { engineHealth = 300, deformation = { { 1, 2, 0, 0.2 } } }
function NetworkHasControlOfEntity()
    return true
end
function SetVehicleOnGroundProperly() end
function SetPedIntoVehicle() end
netEvents['h4nr-garages:ready'](12, readyProps)
check('a retrieved car gets its saved properties', restored[#restored].entity == 1012 and restored[#restored].props == readyProps)
print(('client_spec: %d checks passed'):format(passed))

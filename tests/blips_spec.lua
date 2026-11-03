local passed = 0
local function check(name, condition)
    assert(condition, name)
    passed = passed + 1
end
GarageConfig =
    { DefaultLang = 'ro', VehicleBlip = { enabled = true, refreshMs = 5000, followMs = 250, sprite = 225, color = 3, lentColor = 47, keyHolderColor = 5, scale = 0.75 } }
local activeCharacter, handles, nextHandle, removed, threads, events = true, {}, 0, {}, {}, {}
function CreateThread(fn)
    threads[#threads + 1] = fn
end
function AddEventHandler(name, fn)
    events[name] = fn
end
function GetCurrentResourceName()
    return 'h4nr-garages'
end
function AddBlipForCoord(x, y, z)
    nextHandle = nextHandle + 1
    handles[nextHandle] = { coords = { x, y, z } }
    return nextHandle
end
function SetBlipCoords(id, x, y, z)
    handles[id].coords = { x, y, z }
end
function RemoveBlip(id)
    removed[id] = true
    handles[id] = nil
end
function SetBlipSprite(id, value)
    handles[id].sprite = value
end
function SetBlipColour(id, value)
    handles[id].color = value
end
function SetBlipScale(id, value)
    handles[id].scale = value
end
function SetBlipAsShortRange(id, value)
    handles[id].short = value
end
function SetBlipDisplay(id, value)
    handles[id].display = value
end
local playerVehicle = 0
function PlayerPedId()
    return 1
end
function GetVehiclePedIsIn()
    return playerVehicle
end
local entityAsset = 'near'
function Entity()
    return { state = { h4nrAssetId = entityAsset } }
end
local label
function BeginTextCommandSetBlipName() end
function AddTextComponentString(value)
    label = value
end
function EndTextCommandSetBlipName(id)
    handles[id].label = label
end
exports = { ['feather-character'] = {
    HasActiveCharacter = function()
        return activeCharacter
    end,
} }
local pages, calls = {}, {}
FeatherRPC = {
    CallAsync = function(_, name, params)
        assert(name == 'h4nr-garages:locations')
        calls[#calls + 1] = params
        return table.remove(pages, 1)
    end,
}
dofile(ROOT .. '/client/vehicle_blips.lua')
local function item(id, x)
    return { assetId = id, plate = 'LS12 ABC', coords = { x = x, y = 20, z = 30 } }
end
GarageVehicleBlips.Update({ item('car', 10) })
check(
    'creates long range car blip without a streamed entity',
    handles[1].coords[1] == 10 and handles[1].short == false and handles[1].sprite == 225
)
check('plate identifies the car on the map', handles[1].label == 'Vehiculul meu · LS12 ABC')
GarageVehicleBlips.Update({ item('car', 1000) })
check('moving car updates existing blip', nextHandle == 1 and handles[1].coords[1] == 1000)
GarageVehicleBlips.Update({})
check('parking removes blip', removed[1] and not handles[1])
pages = {
    { ok = true, value = { characterId = 'A', items = { item('first', 10) }, nextCursor = 'next' } },
    { ok = true, value = { characterId = 'A', items = { item('second', 20) } } },
}
GarageVehicleBlips.Refresh()
check('all owned pages are tracked', handles[2] and handles[3] and calls[#calls].cursor == 'next')
pages = { { ok = false, code = 'unavailable' } }
GarageVehicleBlips.Refresh()
check('failed ownership query clears stale tracking', not next(handles))
pages = {
    { ok = true, value = { characterId = 'A', items = { item('first', 10) }, nextCursor = 'next' } },
    { ok = true, value = { characterId = 'B', items = { item('second', 20) } } },
}
GarageVehicleBlips.Refresh()
check('character switch cannot combine locations from two characters', not next(handles))
GarageVehicleBlips.Update({ item('car', 30) })
activeCharacter = false
GarageVehicleBlips.Refresh()
check('logout removes tracking', not next(handles))
GarageVehicleBlips.Update({ item('car', 30) })
events.onClientResourceStop('h4nr-garages')
check('resource stop cleans up blips', not next(handles))
activeCharacter = true
GarageConfig.VehicleBlip.enabled = false
local before = #calls
GarageVehicleBlips.Refresh()
check('disabled tracker makes no server calls', #calls == before)
GarageConfig.VehicleBlip.enabled = true
GarageVehicleBlips.Clear()
local lent = item('car', 1)
lent.lent = true
GarageVehicleBlips.Update({ lent })
local handle = handles[nextHandle]
check('owner blip changes when the key is given', handle.color == 47 and handle.label == 'Vehiculul meu · LS12 ABC (cheie dată)')
GarageVehicleBlips.Update({ item('car', 1) })
check('owner blip returns when the key comes back', handle.color == 3 and handle.label == 'Vehiculul meu · LS12 ABC')
local held = item('other', 1)
held.keyHolder = true
GarageVehicleBlips.Update({ held })
handle = handles[nextHandle]
check('holder gets a key blip', handle.color == 5 and handle.label == 'Cheie · LS12 ABC')
-- Streamed cars follow the entity between server reads.
GarageVehicleBlips.Clear()
local streamed, entityCoords = true, { x = 500, y = 600, z = 70 }
function NetworkDoesEntityExistWithNetworkId()
    return streamed
end
function NetToVeh(netId)
    return netId + 1000
end
function GetEntityCoords()
    return entityCoords
end
local near = item('near', 10)
near.netId = 7
GarageVehicleBlips.Update({ near })
handle = handles[nextHandle]
check('a streamed car replaces the older server position at once', handle.coords[1] == 500)
entityCoords = { x = 900, y = 600, z = 70 }
GarageVehicleBlips.Follow()
check('a streamed car moves between server reads', handle.coords[1] == 900)
streamed = false
GarageVehicleBlips.Follow()
check('a car out of range keeps its last position', handle.coords[1] == 900)
GarageVehicleBlips.Update({ near })
check('a car out of range uses the server position', handle.coords[1] == 10)
streamed, entityAsset = true, 'someone else'
GarageVehicleBlips.Follow()
check('a reused network ID is not followed', handle.coords[1] == 10)
entityAsset = 'near'
GarageVehicleBlips.Update({ item('near', 20) })
GarageVehicleBlips.Follow()
check('without a network ID the server position stands', handle.coords[1] == 20)
-- The blip is for finding the car, so it hides while the player sits in that car.
GarageVehicleBlips.Clear()
entityAsset = 'near'
GarageVehicleBlips.Update({ item('near', 1), item('parked', 2) })
local nearId = nextHandle - 1
local nearBlip, parkedBlip = handles[nearId], handles[nextHandle]
check('outside the car its blip shows', nearBlip.display == 2 and parkedBlip.display == 2)
playerVehicle = 44
GarageVehicleBlips.Follow()
check('getting in hides only that car\'s blip', nearBlip.display == 0 and parkedBlip.display == 2)
GarageVehicleBlips.Update({ item('near', 3), item('parked', 2) })
check('a server read keeps it hidden and tracked', nearBlip.display == 0 and nearBlip.coords[1] == 3)
entityAsset = nil
GarageVehicleBlips.Follow()
check('another car does not hide it', nearBlip.display == 2)
entityAsset = 'near'
GarageVehicleBlips.Follow()
playerVehicle = 0
GarageVehicleBlips.Follow()
check('getting out shows it again', nearBlip.display == 2)
playerVehicle = 44
GarageVehicleBlips.Follow()
GarageVehicleBlips.Update({ item('parked', 2) })
check('a despawned car loses its blip, even while hidden', removed[nearId] and not handles[nearId] and handles[nextHandle])
playerVehicle = 0
print(('blips_spec: %d checks passed'):format(passed))

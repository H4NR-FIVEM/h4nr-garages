local passed = 0
local function check(name, condition) assert(condition, name); passed = passed + 1 end
GarageConfig = { DefaultLang = 'ro', VehicleBlip = { enabled=true, refreshMs=5000, sprite=225, color=3, scale=0.75 } }
local activeCharacter, handles, nextHandle, removed, threads, events = true, {}, 0, {}, {}, {}
function CreateThread(fn) threads[#threads+1] = fn end
function AddEventHandler(name, fn) events[name] = fn end
function GetCurrentResourceName() return 'h4nr-garages' end
function AddBlipForCoord(x,y,z)
    nextHandle=nextHandle+1; handles[nextHandle]={coords={x,y,z}}; return nextHandle
end
function SetBlipCoords(id,x,y,z) handles[id].coords={x,y,z} end
function RemoveBlip(id) removed[id]=true; handles[id]=nil end
function SetBlipSprite(id,value) handles[id].sprite=value end
function SetBlipColour(id,value) handles[id].color=value end
function SetBlipScale(id,value) handles[id].scale=value end
function SetBlipAsShortRange(id,value) handles[id].short=value end
local label
function BeginTextCommandSetBlipName() end
function AddTextComponentString(value) label=value end
function EndTextCommandSetBlipName(id) handles[id].label=label end
exports={['feather-character']={HasActiveCharacter=function() return activeCharacter end}}
local pages, calls = {}, {}
FeatherRPC={CallAsync=function(_,name,params)
    assert(name=='h4nr-garages:locations')
    calls[#calls+1]=params
    return table.remove(pages,1)
end}
dofile(ROOT .. '/feather/client/vehicle_blips.lua')
local function item(id,x) return {assetId=id,plate='LS12 ABC',coords={x=x,y=20,z=30}} end
GarageVehicleBlips.Update({item('car',10)})
check('creates long range car blip without a streamed entity', handles[1].coords[1]==10 and handles[1].short==false and handles[1].sprite==225)
check('plate identifies the car on the map', handles[1].label=='Vehiculul meu · LS12 ABC')
GarageVehicleBlips.Update({item('car',1000)})
check('moving car updates existing blip', nextHandle==1 and handles[1].coords[1]==1000)
GarageVehicleBlips.Update({})
check('parking removes blip', removed[1] and not handles[1])
pages={{ok=true,value={characterId='A',items={item('first',10)},nextCursor='next'}},
    {ok=true,value={characterId='A',items={item('second',20)}}}}
GarageVehicleBlips.Refresh()
check('all owned pages are tracked', handles[2] and handles[3] and calls[#calls].cursor=='next')
pages={{ok=false,code='unavailable'}}
GarageVehicleBlips.Refresh()
check('failed ownership query clears stale tracking', not next(handles))
pages={{ok=true,value={characterId='A',items={item('first',10)},nextCursor='next'}},
    {ok=true,value={characterId='B',items={item('second',20)}}}}
GarageVehicleBlips.Refresh()
check('character switch cannot combine locations from two characters', not next(handles))
GarageVehicleBlips.Update({item('car',30)})
activeCharacter=false
GarageVehicleBlips.Refresh()
check('logout removes tracking', not next(handles))
GarageVehicleBlips.Update({item('car',30)})
events.onClientResourceStop('h4nr-garages')
check('resource stop cleans up blips', not next(handles))
activeCharacter=true
GarageConfig.VehicleBlip.enabled=false
local before=#calls
GarageVehicleBlips.Refresh()
check('disabled tracker makes no server calls', #calls==before)
print(('blips_spec: %d checks passed'):format(passed))

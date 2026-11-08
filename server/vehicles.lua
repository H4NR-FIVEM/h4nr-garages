-- Creates a job or showroom vehicle on the server and hands back its network ID.
FeatherVehicles = {}

function FeatherVehicles.spawnVehicle(spec)
    local pos = spec.spawnSource
    if type(pos) == 'number' then
        pos = GetEntityCoords(pos)
    end
    local model = type(spec.model) == 'string' and joaat(spec.model) or spec.model
    local vehicle = CreateVehicleServerSetter(model, spec.type or 'automobile', pos.x, pos.y, pos.z, pos.w or 0.0)
    if not vehicle or vehicle == 0 then
        return nil
    end
    local deadline = GetGameTimer() + 5000
    while not DoesEntityExist(vehicle) and GetGameTimer() < deadline do
        Wait(50)
    end
    if not DoesEntityExist(vehicle) then
        return nil
    end
    if spec.props and spec.props.plate then
        SetVehicleNumberPlateText(vehicle, spec.props.plate)
    end
    if spec.props then
        Entity(vehicle).state:set('h4nrVehicleProps', spec.props, true)
    end
    if spec.bucket then
        SetEntityRoutingBucket(vehicle, spec.bucket)
    end
    if spec.warp then
        local ped = type(spec.warp) == 'number' and spec.warp
            or spec.ped
            or (type(spec.spawnSource) == 'number' and spec.spawnSource)
        if ped and ped ~= 0 then
            SetPedIntoVehicle(ped, vehicle, -1)
        end
    end
    return NetworkGetNetworkIdFromEntity(vehicle), vehicle
end

-- Feather Core RPC for this resource, loaded inside it so Core sees the real caller.
FeatherRPC = {}

function FeatherRPC:Register(name, callback)
    local server = IsDuplicityVersion()
    return exports['feather-core']:RegisterRPC(name, callback, {
        contract = 1,
        requireCharacter = server,
        maxCalls = 40,
        maxPayloadBytes = 65536,
        direction = server and 'client_to_server' or 'server_to_client',
    })
end

function FeatherRPC:CallAsync(name, params, target)
    return exports['feather-core']:CallRPCAsync(name, params or {}, target)
end

function FeatherRPC:Call(name, params, callback, target)
    return exports['feather-core']:CallRPC(name, params or {}, callback, target)
end

function FeatherRPC:Notify(name, params, target)
    return exports['feather-core']:NotifyRPC(name, params or {}, target)
end

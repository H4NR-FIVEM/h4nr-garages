-- Garage panel. Lua decides what each vehicle offers and the page only draws it. The page sends
-- back an asset and an action, checked against this list, and the server decides the rest.
GaragePanel = {}
local Request, Notify, Message = GarageCalls.Request, GarageCalls.Notify, GarageCalls.Message
local pageReady, opening, panel, sequence = false, false, nil, 0
local TEXTS = {
    'search',
    'filter_all',
    'filter_stored',
    'filter_out',
    'section_nearby',
    'section_vehicles',
    'engine',
    'body',
    'fuel',
    'close',
    'no_vehicles',
    'no_match',
    'slots_out',
    'slots_owned',
    'slots_premium',
    'slot_confirm',
}
local function Focus(enabled)
    SetNuiFocusKeepInput(false)
    SetNuiFocus(enabled, enabled)
end
local function VehicleName(model)
    local text = GetLabelText(GetDisplayNameFromVehicleModel(joaat(model)))
    return text and text ~= 'NULL' and text ~= '' and text or model
end
local function Action(id, label, extra)
    local action = extra or {}
    action.id, action.label = id, label
    return action
end
local function OutFull(slots)
    return slots ~= nil and slots.out >= slots.outLimit
end
-- A truck can take any trailer that could itself come out. The trailer counts as a vehicle out, and
-- `method` carries its asset, since the page sends back only an id and a method. The page draws
-- `towing` actions as checkboxes: unticked, the truck comes out alone.
local function Towing(item, trailers, slots)
    local actions = {}
    if not GarageConfig.Towing.tractors[item.model:lower()] then
        return actions, false
    end
    local short = slots ~= nil and slots.out + 2 > slots.outLimit
    for _, trailer in ipairs(trailers) do
        actions[#actions + 1] = Action('retrieve', T('retrieve_with'):format(VehicleName(trailer.model), trailer.plate or ''), {
            method = trailer.assetId,
            towing = true,
            disabled = short or nil,
        })
    end
    return actions, short and actions[1] ~= nil
end
-- Why a retrieval is limited (when so), then its buttons. Parking the car in the way comes first.
-- With every out slot taken only the swap is left, since it parks a car before taking this one out.
local function Retrieval(item, old, slots, trailers)
    local full = OutFull(slots)
    local towing, short = Towing(item, trailers, slots)
    local actions = {}
    if old then
        actions[1] = Action('swap', T('swap'):format(old.name))
    end
    actions[#actions + 1] = Action('retrieve', T('retrieve'), { disabled = full or nil })
    for _, action in ipairs(towing) do
        actions[#actions + 1] = action
    end
    if full and not old then
        return T('out_limit_reason'), actions
    end
    return short and not full and T('trailer_slots_reason') or nil, actions
end
-- Status line, why nothing can be done (when so) and the buttons of one vehicle.
local function Describe(item, price, old, slots, trailers)
    if item.rekey then
        if item.rekey.state == 'waiting' then
            local minutes = math.ceil(item.rekey.seconds / 60)
            return T('key_elsewhere'), 'warn', T('rekey_requested'), { Action('rekey', T('rekey_wait'):format(minutes), { disabled = true }) }
        elseif item.rekey.state == 'ready' then
            return T('key_elsewhere'), 'warn', T('rekey_ready'), {
                Action('rekey', T('rekey_pay_cash'):format(price), { method = 'cash' }),
                Action('rekey', T('rekey_pay_bank'):format(price), { method = 'bank' }),
            }
        end
        return T('key_elsewhere'), 'warn', T('rekey_explain'):format(price), { Action('rekey', T('rekey_request')) }
    end
    if item.parkNetId then
        return T('nearby'), 'ok', nil, { Action('park', T('store_label')) }
    end
    if not item.available then
        return T('unavailable'), 'muted', T('unavailable'), {}
    end
    if item.state == 'stored' then
        local garage = GarageConfig.Garages[item.garage]
        local reason, actions = Retrieval(item, old, slots, trailers)
        return garage and T('stored_at'):format(garage.label) or T('stored'), 'ok', reason, actions
    elseif item.state == 'out' then
        if item.onStreet then
            return T('out'), 'muted', T('on_street'), {}
        end
        local reason, actions = Retrieval(item, old, slots, trailers)
        return T('out_lost'), 'warn', reason, actions
    elseif item.state == 'sale_reserved' then
        return T('sale_reserved'), 'muted', T('sale_reserved'), {}
    end
    return T('working'), 'muted', T('busy'), {}
end
-- The parkable car closest to the spawn point: the one most likely to be in the way.
local function ClosestParkable(items, garageId)
    local spawn, best, bestDistance = GarageConfig.Garages[garageId].spawn, nil, nil
    local point = vector3(spawn.x, spawn.y, spawn.z)
    for _, item in ipairs(items) do
        if item.parkNetId and not item.rekey and NetworkDoesEntityExistWithNetworkId(item.parkNetId) then
            local distance = #(GetEntityCoords(NetToVeh(item.parkNetId)) - point)
            if not bestDistance or distance < bestDistance then
                best, bestDistance = item, distance
            end
        end
    end
    return best and { assetId = best.assetId, netId = best.parkNetId, name = VehicleName(best.model) } or nil
end
local function View(items, price, garageId, slots)
    local list, byId = {}, {}
    local old = ClosestParkable(items, garageId)
    panel.old = old
    local trailers = {}
    for _, item in ipairs(items) do
        local free = item.state == 'stored' or (item.state == 'out' and not item.onStreet)
        if free and item.available and not item.rekey and GarageConfig.Towing.trailers[item.model:lower()] then
            trailers[#trailers + 1] = item
        end
    end
    for _, item in ipairs(items) do
        local status, tone, reason, actions = Describe(item, price, old, slots, trailers)
        local group = item.state == 'stored' and 'stored' or 'out'
        list[#list + 1] = {
            id = item.assetId,
            name = VehicleName(item.model),
            plate = item.plate or '',
            status = status,
            tone = tone,
            reason = reason,
            condition = item.condition,
            group = group,
            nearby = actions[1] ~= nil and actions[1].id == 'park',
            actions = actions,
        }
        byId[item.assetId] = { source = item, actions = actions }
    end
    table.sort(list, function(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.plate < b.plate
    end)
    return list, byId
end
-- Every vehicle at once, so that search and the filters see all of them. Slots come with page one.
local function Fetch(garageId)
    local items, cursor, price, slots = {}, nil, 0, nil
    repeat
        local page, code = Request('list', { garage = garageId, cursor = cursor })
        if not page then
            return nil, nil, code
        end
        if not cursor and type(page.slots) == 'table' then
            slots = page.slots
        end
        if type(page) ~= 'table' or type(page.items) ~= 'table' then
            print('[h4nr-garages] RPC list returned invalid item data')
            return nil, nil, 'invalid_response'
        end
        for _, item in ipairs(page.items) do
            items[#items + 1] = item
        end
        cursor, price = page.nextCursor, page.rekeyPrice or price
    until not cursor
    return items, price, nil, slots
end
-- The meters and the premium offers the page may draw; the page sends back only an offer id.
local function SlotView(slots)
    if not slots then
        return nil, {}
    end
    local offers, allowed = {}, {}
    for _, kind in ipairs({ 'out', 'owned' }) do
        local offer = type(slots.offers) == 'table' and slots.offers[kind]
        if offer and offer.left > 0 then
            offers[#offers + 1] = { id = kind, label = T('slot_buy_' .. kind):format(offer.price) }
            allowed[kind] = true
        end
    end
    local meters = { { label = T('slots_out'), used = slots.out, limit = slots.outLimit } }
    if slots.ownedLimit then
        meters[2] = { label = T('slots_owned'), used = slots.owned, limit = slots.ownedLimit }
    end
    return {
        meters = meters,
        offers = offers,
    }, allowed
end
local function Send(items, price, slots)
    local list, byId = View(items, price, panel.garage, slots)
    local view, offers = SlotView(slots)
    panel.items, panel.offers = byId, offers
    SendNUIMessage({ action = 'view', session = panel.session, items = list, slots = view })
end
local function Texts()
    local texts = {}
    for _, key in ipairs(TEXTS) do
        texts[key] = T(key)
    end
    return texts
end
function GaragePanel.Close()
    local wasOpen = panel ~= nil
    panel = nil
    if wasOpen then
        Focus(false)
        SendNUIMessage({ action = 'close' })
    end
end
function GaragePanel.Busy()
    return opening or panel ~= nil
end
function GaragePanel.Open(garageId)
    if GaragePanel.Busy() then
        return
    end
    opening = true
    local ok, problem = pcall(function()
        local deadline = GetGameTimer() + 5000
        while not pageReady and GetGameTimer() < deadline do
            Wait(50)
        end
        if not pageReady then
            return Notify('menu_not_ready')
        end
        local items, price, code, slots = Fetch(garageId)
        if not items then
            return Notify(code)
        end
        local garage = GarageConfig.Garages[garageId]
        sequence = sequence + 1
        panel = { session = sequence, garage = garageId, items = {}, offers = {} }
        SendNUIMessage({
            action = 'open',
            session = panel.session,
            label = garage.label,
            kind = T('kind_' .. garage.assetType),
            texts = Texts(),
        })
        Send(items, price, slots)
        Focus(true)
    end)
    opening = false
    if not ok then
        print('[h4nr-garages] panel: ' .. tostring(problem))
        GaragePanel.Close()
        Notify('failed')
    end
end
-- The panel holds the player still, but it must not outlive being killed or moved away.
function GaragePanel.Watch(ped, coords)
    if not panel then
        return
    end
    local garage = GarageConfig.Garages[panel.garage]
    if IsEntityDead(ped) or #(coords - garage.coords) > GarageConfig.PanelDistance then
        GaragePanel.Close()
    end
end
local function Reload(session, garageId)
    local items, price, _, slots = Fetch(garageId)
    if items and panel and panel.session == session then
        Send(items, price, slots)
    end
end
local function Run(session, garageId, assetId, entry, action)
    local value, code
    if action.id == 'retrieve' then
        value, code = Request('retrieve', { garage = garageId, assetId = assetId, trailer = action.method })
        if value and value.trailerProblem then
            Notify('trailer_failed')
        end
    elseif action.id == 'swap' then
        local old = panel and panel.old
        if not old or not NetworkDoesEntityExistWithNetworkId(old.netId) then
            return { ok = false, message = Message('too_far') }
        end
        local stored, refusal = Request('store', GarageCalls.StoreParams(garageId, old.assetId, NetToVeh(old.netId)))
        if not stored then
            return { ok = false, message = Message(refusal) }
        end
        value, code = Request('retrieve', { garage = garageId, assetId = assetId })
        -- The old car is parked either way, and the list must say so.
        if code then
            Reload(session, garageId)
        end
    elseif action.id == 'park' then
        local netId = entry.source.parkNetId
        if not NetworkDoesEntityExistWithNetworkId(netId) then
            return { ok = false, message = Message('too_far') }
        end
        value, code = Request('store', GarageCalls.StoreParams(garageId, assetId, NetToVeh(netId)))
        if value then
            Notify(GarageCalls.ParkedMessage(value))
        end
    else
        value, code = Request('rekey', { garage = garageId, assetId = assetId, method = action.method })
        if value then
            local notice = Message(value.state == 'done' and 'rekey_done' or 'rekey_requested')
            Reload(session, garageId)
            return { ok = true, message = notice }
        end
    end
    if code or not value then
        return { ok = false, message = Message(code or 'invalid_response') }
    end
    if panel and panel.session == session then
        GaragePanel.Close()
    end
    return { ok = true, closed = true }
end
RegisterNUICallback('ready', function(_, cb)
    pageReady = true
    cb({ ok = true })
end)
RegisterNUICallback('close', function(_, cb)
    GaragePanel.Close()
    cb({ ok = true })
end)
RegisterNUICallback('action', function(data, cb)
    if not panel or type(data) ~= 'table' or data.session ~= panel.session then
        return cb({ ok = false, message = Message('failed') })
    end
    if panel.pending then
        return cb({ ok = false, message = Message('busy') })
    end
    local entry = panel.items[data.assetId]
    local chosen
    for _, action in ipairs(entry and entry.actions or {}) do
        if action.id == data.id and action.method == data.method and not action.disabled then
            chosen = action
        end
    end
    if not chosen then
        return cb({ ok = false, message = Message('failed') })
    end
    local current = panel
    current.pending = true
    CreateThread(function()
        local called, result = pcall(Run, current.session, current.garage, data.assetId, entry, chosen)
        current.pending = false
        if not called then
            print('[h4nr-garages] panel action: ' .. tostring(result))
            result = { ok = false, message = Message('failed') }
        end
        cb(result)
    end)
end)
-- A premium slot. The page asks for confirmation before it calls this.
RegisterNUICallback('slot', function(data, cb)
    if not panel or type(data) ~= 'table' or data.session ~= panel.session or not panel.offers[data.id] then
        return cb({ ok = false, message = Message('failed') })
    end
    if panel.pending then
        return cb({ ok = false, message = Message('busy') })
    end
    local current = panel
    current.pending = true
    CreateThread(function()
        local called, value, code = pcall(Request, 'buySlot', { garage = current.garage, kind = data.id })
        current.pending = false
        if not called then
            print('[h4nr-garages] slot purchase: ' .. tostring(value))
            return cb({ ok = false, message = Message('failed') })
        end
        if not value then
            return cb({ ok = false, message = Message(code or 'invalid_response') })
        end
        Reload(current.session, current.garage)
        cb({ ok = true, message = Message('slot_bought') })
    end)
end)
AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        GaragePanel.Close()
    end
end)

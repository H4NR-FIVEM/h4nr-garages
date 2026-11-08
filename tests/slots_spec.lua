-- server/slots.lua with modelled Assets, SQL and payments. No FXServer claim.
local passed = 0
local function check(name, condition)
    assert(condition, 'FAIL: ' .. name)
    passed = passed + 1
end
local C = '11111111-1111-1111-1111-111111111111'
local function Id(n)
    return ('00000000-0000-0000-0000-%012d'):format(n)
end
local assetList, rows, slotRows, charges = {}, {}, {}, {}
local chargeCode = nil
local pageSize = 2
local assets = {}
function assets:ListAssetsByHolder(request)
    local start = request.cursor and tonumber(request.cursor:sub(-12)) or 0
    local items = {}
    for _, asset in ipairs(assetList) do
        local n = tonumber(asset.assetId:sub(-12))
        if n > start and asset.assetType == request.assetType and #items < pageSize then
            items[#items + 1] = asset
        end
    end
    local last = items[#items]
    local more = last and tonumber(last.assetId:sub(-12)) < #assetList
    return { ok = true, value = { items = items, nextCursor = more and last.assetId or nil } }
end
exports = setmetatable({}, {
    __index = function()
        return assets
    end,
})
local commands, restricted, notified = {}, {}, {}
function RegisterCommand(name, handler, isRestricted)
    commands[name], restricted[name] = handler, isRestricted
end
function TriggerClientEvent(name, source, key)
    notified[#notified + 1] = { name = name, source = source, key = key }
end
function assets:GetSessionContext(source)
    if source == 7 then
        return { ok = true, value = { characterId = C } }
    end
    return { ok = false, code = 'no_session' }
end
DB = {
    one = function(_, id)
        local row = slotRows[id]
        return row and {
            bought_out = row.bought_out,
            bought_owned = row.bought_owned,
            granted_out = row.granted_out,
            granted_owned = row.granted_owned,
        }
    end,
    exec = function(sql, id, value)
        if sql:find('CREATE TABLE') then
            return 0
        end
        local column = sql:match('%(character_id, ([%w_]+)%)')
        slotRows[id] = slotRows[id] or { bought_out = 0, bought_owned = 0, granted_out = 0, granted_owned = 0 }
        if sql:find('GREATEST') then
            slotRows[id][column] = math.max(slotRows[id][column], value)
        else
            slotRows[id][column] = value
        end
        return 1
    end,
}
Garage = {
    Ok = function(value)
        return { ok = true, value = value }
    end,
    Err = function(code)
        return { ok = false, code = code }
    end,
    Uuid = function(value)
        return type(value) == 'string' and #value == 36
    end,
    Row = function(id)
        return rows[id]
    end,
}
GaragePayments = {
    ChargePremium = function(spec)
        if chargeCode then
            return Garage.Err(chargeCode)
        end
        if not charges[spec.key] then
            charges[spec.key] = spec.amount
        end
        return Garage.Ok(true)
    end,
}
function vector3(x, y, z)
    return { x = x, y = y, z = z }
end
function vector4(x, y, z, w)
    return { x = x, y = y, z = z, w = w }
end
dofile(ROOT .. '/config/shared.lua')
GarageConfig.Slots = {
    limits = { vehicle = { out = 3, owned = 5 } },
    premium = { currency = 'tokens', out = { price = 500, max = 2 }, owned = { price = 300, max = 1 } },
}
dofile(ROOT .. '/server/slots.lua')

local liveIds = {}
local function isLive(id)
    return liveIds[id] == true
end
local function Add(status, live, extra)
    local id = Id(#assetList + 1)
    assetList[#assetList + 1] = {
        assetId = id,
        assetType = extra and extra.assetType or 'vehicle',
        managerResource = extra and extra.manager or 'h4nr-garages',
        status = extra and extra.assetStatus or 'active',
    }
    rows[id] = { status = status }
    liveIds[id] = live
    return id
end

check('boats have no limit', GarageSlots.Snapshot(C, 'boat', isLive).limited == false)
local snap = GarageSlots.Snapshot(C, 'vehicle', isLive)
check('empty character', snap.limited and snap.out == 0 and snap.owned == 0 and snap.outLimit == 3 and snap.ownedLimit == 5)

Add('out', true)
Add('out', true)
Add('spawning', false)
Add('out', false) -- marked out, but the car is gone: no out slot
Add('stored', false)
Add('stored', false, { assetStatus = 'retired' })
Add('stored', false, { manager = 'other' })
Add('stored', false, { assetType = 'boat' })
snap = GarageSlots.Snapshot(C, 'vehicle', isLive)
check('counts across pages', snap.owned == 5)
check('lost car does not take an out slot, spawning does', snap.out == 3)
check('offers show what is left', snap.offers.out.left == 2 and snap.offers.owned.left == 1 and snap.offers.out.price == 500)

local bought = GarageSlots.Buy(1, C, 'out')
check('buy out slot', bought.ok and bought.value.bought == 1)
check('charged once with a numbered key', charges[('slots:%s:out:1'):format(C)] == 500)
snap = GarageSlots.Snapshot(C, 'vehicle', isLive)
check('bought slot raises the out limit', snap.outLimit == 4 and snap.offers.out.left == 1)
check('second purchase has a new key', GarageSlots.Buy(1, C, 'out').ok and charges[('slots:%s:out:2'):format(C)] == 500)
check('max reached', GarageSlots.Buy(1, C, 'out').code == 'slots_max')
chargeCode = 'no_premium'
check('refused charge changes nothing', GarageSlots.Buy(1, C, 'owned').code == 'no_premium' and GarageSlots.Limits(C, 'vehicle').owned == 5)
chargeCode = nil
check('owned slot', GarageSlots.Buy(1, C, 'owned').ok and GarageSlots.Limits(C, 'vehicle').owned == 6)
check('unknown kind', GarageSlots.Buy(1, C, 'anything').code == 'invalid_input')

check('grant sets, not adds', GarageSlots.Grant(C, 'owned', 4).ok and GarageSlots.Grant(C, 'owned', 4).ok)
check('granted slots count', GarageSlots.Limits(C, 'vehicle').owned == 10)
check('grant does not consume bought keys', GarageSlots.Snapshot(C, 'vehicle', isLive).offers.owned.left == 0)
check('grant can be removed', GarageSlots.Grant(C, 'owned', 0).ok and GarageSlots.Limits(C, 'vehicle').owned == 6)
check('grant validates', GarageSlots.Grant(C, 'out', -1).code == 'invalid_input' and GarageSlots.Grant('x', 'out', 1).code == 'invalid_input')

assets.ListAssetsByHolder = function()
    return { ok = false, code = 'unavailable' }
end
check('unreadable count is nil', GarageSlots.Snapshot(C, 'vehicle', isLive) == nil)
-- Without `owned` in the limits only the cars out are capped.
local cappedOwned = GarageConfig.Slots.limits.vehicle.owned
GarageConfig.Slots.limits.vehicle.owned = nil
local noCap = GarageSlots.Limits(C, 'vehicle')
check('no cap on cars held', noCap.owned == nil and noCap.out ~= nil)
GarageConfig.Slots.limits.vehicle.owned = cappedOwned
-- Admins set slots by player id, in game or from the console.
check('the command is restricted to admins', restricted.garageslots == true)
commands.garageslots(3, { '7', 'out', '4' })
check('an admin grants slots to an online player', slotRows[C].granted_out == 4)
check('the admin is told', notified[#notified].source == 3 and notified[#notified].key == 'slots_granted')
commands.garageslots(0, { C:upper(), 'owned', '2' })
check('the console still takes a character id', slotRows[C].granted_owned == 2)
commands.garageslots(3, { '8', 'out', '9' })
check('a player without a character is refused', slotRows[C].granted_out == 4 and notified[#notified].key == 'slots_grant_usage')
commands.garageslots(3, { '7', 'all', '9' })
check('a wrong kind is refused', slotRows[C].granted_out == 4 and notified[#notified].key == 'slots_grant_usage')
print(('slots_spec: %d checks passed'):format(passed))

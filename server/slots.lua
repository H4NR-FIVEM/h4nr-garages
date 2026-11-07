-- Vehicle slots of a character: how many vehicles of a type may be out at once (`out`) and how
-- many it may hold (`owned`). The base comes from GarageConfig.Slots.limits; extra slots are
-- bought with the premium currency (`bought_*`) or set by staff from the console (`granted_*`).
-- Bought counts only grow, so each purchase has its own idempotency key.
GarageSlots = {}
local assets = exports['feather-assets']
local COLUMNS = { out = 'bought_out', owned = 'bought_owned' }
local GRANTS = { out = 'granted_out', owned = 'granted_owned' }
function GarageSlots.Migrate()
    DB.exec([[
        CREATE TABLE IF NOT EXISTS h4nr_garage_slots (
            character_id CHAR(36) NOT NULL PRIMARY KEY,
            bought_out INT UNSIGNED NOT NULL DEFAULT 0,
            bought_owned INT UNSIGNED NOT NULL DEFAULT 0,
            granted_out INT UNSIGNED NOT NULL DEFAULT 0,
            granted_owned INT UNSIGNED NOT NULL DEFAULT 0,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end
local function Extra(characterId)
    local row = DB.one('SELECT * FROM h4nr_garage_slots WHERE character_id = ?', characterId) or {}
    local function N(key)
        return tonumber(row[key]) or 0
    end
    return {
        bought = { out = N('bought_out'), owned = N('bought_owned') },
        granted = { out = N('granted_out'), owned = N('granted_owned') },
    }
end
-- nil when this type has no limit.
function GarageSlots.Limits(characterId, assetType)
    local base = GarageConfig.Slots.limits[assetType]
    if not base then
        return nil
    end
    local extra = Extra(characterId)
    return {
        out = base.out + extra.bought.out + extra.granted.out,
        owned = base.owned + extra.bought.owned + extra.granted.owned,
        bought = extra.bought,
    }
end
-- Counts across every Assets page. A car marked out that no longer exists (isLive false) does not
-- take a slot: taking it out again only replaces it. nil when Assets cannot be read.
function GarageSlots.Usage(characterId, assetType, isLive)
    local usage, cursor = { out = 0, owned = 0 }, nil
    repeat
        local page = assets:ListAssetsByHolder({
            holderType = 'character',
            holderId = characterId,
            assetType = assetType,
            limit = 50,
            cursor = cursor,
        })
        if not page.ok then
            return nil
        end
        for _, asset in ipairs(page.value.items) do
            if asset.managerResource == 'h4nr-garages' and asset.status ~= 'retired' then
                usage.owned = usage.owned + 1
                local row = Garage.Row(asset.assetId)
                local status = row and row.status
                if status == 'spawning' or (status == 'out' and isLive(asset.assetId)) then
                    usage.out = usage.out + 1
                end
            end
        end
        cursor = page.value.nextCursor
    until not cursor
    return usage
end
-- { limited = false } for a type without limits; nil when the count cannot be read.
function GarageSlots.Snapshot(characterId, assetType, isLive)
    local limits = GarageSlots.Limits(characterId, assetType)
    if not limits then
        return { limited = false }
    end
    local usage = GarageSlots.Usage(characterId, assetType, isLive)
    if not usage then
        return nil
    end
    local offers = {}
    for kind in pairs(COLUMNS) do
        local offer = GarageConfig.Slots.premium[kind]
        if offer and offer.max > 0 then
            offers[kind] = { price = offer.price, left = math.max(offer.max - limits.bought[kind], 0) }
        end
    end
    return {
        limited = true,
        out = usage.out,
        outLimit = limits.out,
        owned = usage.owned,
        ownedLimit = limits.owned,
        offers = offers,
    }
end
-- One more slot of `kind` for the premium currency. A retry after a lost reply pays nothing more:
-- the key names the purchase number, and the row takes the highest number paid.
function GarageSlots.Buy(source, characterId, kind)
    local column, offer = COLUMNS[kind], GarageConfig.Slots.premium[kind]
    if not column or not offer then
        return Garage.Err('invalid_input')
    end
    local bought = Extra(characterId).bought[kind]
    if bought >= offer.max then
        return Garage.Err('slots_max')
    end
    local number = bought + 1
    local charged = GaragePayments.ChargePremium({
        characterId = characterId,
        source = source,
        amount = offer.price,
        referenceId = characterId,
        key = ('slots:%s:%s:%d'):format(characterId, kind, number),
    })
    if not charged.ok then
        return charged
    end
    DB.exec(
        ('INSERT INTO h4nr_garage_slots (character_id, %s) VALUES (?, ?) ON DUPLICATE KEY UPDATE %s = GREATEST(%s, VALUES(%s))'):format(
            column,
            column,
            column,
            column
        ),
        characterId,
        number
    )
    return Garage.Ok({ kind = kind, bought = number })
end
-- Staff or a store: sets the granted extra (not added to it), so running it twice is harmless.
function GarageSlots.Grant(characterId, kind, amount)
    local column = GRANTS[kind]
    if not column or not Garage.Uuid(characterId) or type(amount) ~= 'number' or amount < 0 or amount % 1 ~= 0 then
        return Garage.Err('invalid_input')
    end
    DB.exec(
        ('INSERT INTO h4nr_garage_slots (character_id, %s) VALUES (?, ?) ON DUPLICATE KEY UPDATE %s = VALUES(%s)'):format(
            column,
            column,
            column
        ),
        characterId,
        amount
    )
    return Garage.Ok(true)
end
-- Server console only: garageslots <characterId> <out|owned> <amount>
RegisterCommand('garageslots', function(source, args)
    if source ~= 0 then
        return
    end
    local result = GarageSlots.Grant(args[1] and args[1]:lower(), args[2], tonumber(args[3]))
    print(
        result.ok and ('[h4nr-garages] %s: granted %s slots = %s'):format(args[1], args[2], args[3])
            or '[h4nr-garages] usage: garageslots <characterId> <out|owned> <amount>'
    )
end, true)

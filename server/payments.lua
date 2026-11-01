-- Payments through feather-economy, in cents. The caller's idempotency key means a retry
-- after a timeout or a failed step can never charge twice.
GaragePayments = {}
local economy = exports['feather-economy']
local reasons = { cash = 'h4nr_garages.rekey', bank = 'h4nr_garages.rekey_bank' }
local reasonsReady = false
local function Ok(result)
    return type(result) == 'table' and result.ok == true
end
-- Wallet -> system sink is a v1 movement; bank -> sink needs an operated reason.
local function ReadyReasons()
    if reasonsReady then
        return true
    end
    local result = Ok(economy:AwaitReady(30000))
        and economy:RegisterOperatedReasons({ reasons = { [reasons.bank] = 'bank_to_sink' } })
    reasonsReady = Ok(result)
    return reasonsReady
end
local function Account(characterId, method)
    local function Select(accounts)
        for _, row in ipairs(accounts or {}) do
            if
                row.currency == 'dollars'
                and row.status == 'open'
                and row.accountType == (method == 'bank' and 'bank' or 'wallet')
                and (method ~= 'bank' or row.accountRef == 'h4nr')
            then
                return row
            end
        end
    end
    local found = economy:FindAccountsByOwner({ ownerType = 'character', ownerId = characterId })
    local existing = Ok(found) and Select(found.value)
    if existing then
        return existing
    end
    local created = method == 'bank'
            and economy:EnsureCharacterBankAccounts({ characterId = characterId, accountRef = 'h4nr' })
        or economy:EnsureCharacterWallets({ characterId = characterId })
    return Ok(created) and Select(created.value) or nil
end
-- spec: characterId, source, method, dollars, referenceId, key.
function GaragePayments.Charge(spec)
    if not reasons[spec.method] then
        return Garage.Err('invalid_input')
    end
    if spec.method == 'bank' and not ReadyReasons() then
        return Garage.Err('unavailable')
    end
    local account = Account(spec.characterId, spec.method)
    local sink = economy:GetSystemAccount({ currency = 'dollars', accountType = 'system_sink' })
    if not account or not Ok(sink) then
        return Garage.Err('unavailable')
    end
    local result = economy:Transfer({
        fromAccountId = account.accountId,
        toAccountId = sink.value.accountId,
        currency = 'dollars',
        amount = spec.dollars * 100,
        reasonCode = reasons[spec.method],
        referenceType = 'h4nr_garages_rekey',
        referenceId = spec.referenceId,
        idempotencyKey = spec.key,
    }, { actorCharacterId = spec.characterId, actorSource = spec.source, correlationId = spec.referenceId })
    if Ok(result) then
        return Garage.Ok(true)
    end
    local code = type(result) == 'table' and result.code or 'unavailable'
    return Garage.Err(code == 'insufficient_funds' and 'no_money' or 'unavailable')
end
-- Economy keeps operated reasons in memory: register again after it restarts.
AddEventHandler('onResourceStart', function(resource)
    if resource == 'feather-economy' then
        reasonsReady = false
    end
end)

-- Fallback language. ro and en_us have the same keys (tests/run.py checks).
Locales = Locales or {}

Locales.en_us = {
    retrieve = 'Retrieve vehicle',
    stored = 'Stored',
    out = 'Out',
    unavailable = 'Vehicle unavailable here',
    failed = 'Operation failed. Try again.',
    forbidden = 'You do not have access to this vehicle.',
    spawn_blocked = 'The spawn point is occupied.',
    already_out = 'Vehicle is already out.',
    parked = 'Vehicle stored.',
    next = 'Next page',
    close = 'Close',
    prompt = '~INPUT_CONTEXT~ Garage',
    store = '~INPUT_CONTEXT~ Store vehicle',
    locked = 'Vehicle locked.',
    unlocked = 'Vehicle unlocked.',
    lock_key = 'Lock / unlock vehicle',
    engine_key = 'Toggle engine',
}

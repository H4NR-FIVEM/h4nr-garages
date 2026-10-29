-- Fallback language. ro and en_us have the same keys (tests/run.py checks).
Locales = Locales or {}

Locales.en_us = {
    open_label = 'Open garage',
    store_label = 'Store vehicle',

    busy = 'Another vehicle operation is finishing. Try again.',
    too_far = 'Move closer to the garage in the public session.',
    not_ready = 'The garage is still starting. Try again.',
    menu_not_ready = 'The garage menu is still loading. Try again.',
    timeout = 'The garage did not respond in time. Try again.',
    character_required = 'Select a character before opening the garage.',
    authorization_denied = 'The garage cannot access the vehicle registry.',
    invalid_response = 'The garage received an invalid response.',

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

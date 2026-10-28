-- Default language. ro and en_us have the same keys (tests/run.py checks).
Locales = Locales or {}

Locales.ro = {
    retrieve = 'Scoate vehiculul',
    stored = 'Parcat',
    out = 'Scos',
    unavailable = 'Vehicul indisponibil aici',
    failed = 'Operația nu a reușit. Încearcă din nou.',
    forbidden = 'Nu ai acces la acest vehicul.',
    spawn_blocked = 'Locul de scoatere este ocupat.',
    already_out = 'Vehiculul este deja scos.',
    parked = 'Vehicul parcat.',
    next = 'Pagina următoare',
    close = 'Închide',
    prompt = '~INPUT_CONTEXT~ Garaj',
    store = '~INPUT_CONTEXT~ Parchează vehiculul',
    locked = 'Vehicul încuiat.',
    unlocked = 'Vehicul descuiat.',
    lock_key = 'Încuie / descuie vehiculul',
    engine_key = 'Pornește / oprește motorul',
}

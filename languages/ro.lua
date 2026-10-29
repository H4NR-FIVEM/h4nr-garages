-- Default language. ro and en_us have the same keys (tests/run.py checks).
Locales = Locales or {}

Locales.ro = {
    open_label = 'Deschide garajul',
    store_label = 'Parchează vehiculul',

    busy = 'Se finalizează altă operație la vehicul. Încearcă din nou.',
    too_far = 'Apropie-te de garaj în sesiunea publică.',
    not_ready = 'Garajul încă se inițializează. Încearcă din nou.',
    menu_not_ready = 'Meniul garajului încă se încarcă. Încearcă din nou.',
    timeout = 'Garajul nu a răspuns la timp. Încearcă din nou.',
    character_required = 'Selectează un personaj înainte să deschizi garajul.',
    authorization_denied = 'Garajul nu are acces la registrul vehiculelor.',
    invalid_response = 'Garajul a primit un răspuns invalid.',

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

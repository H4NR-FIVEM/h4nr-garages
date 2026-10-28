# h4nr-garages — Feather FiveM

Garaje publice pentru vehicule, bărci și aeronave, înregistrarea cumpărărilor din
`h4nr-vehicleshop` și cheile proprietarului. Meniul folosește Feather Menu v2,
preset `modern` (Neon Vice). Limba implicită este româna, cu rezervă `en_us`.

## Pornire

După serviciile Feather (inclusiv Character, Assets și Admin), oxmysql, ox_lib,
h4nr-feather, Menu v2 și Notify:

```cfg
ensure h4nr-garages
ensure h4nr-vehicleshop
```

Politicile din `feather-admin` trebuie să permită `assets.asset.manage` pentru
`h4nr-garages`, iar Assets trebuie să-l admită în trustedReaders și trustedManagers.
Aceste intrări există deja în configurația locală FiveM. `h4nr-fuel` este opțional.
La pornire se creează doar tabelul propriu `h4nr_feather_vehicles`; proprietatea
este în Assets. Nu se citesc și nu se modifică tabelele QB `player_vehicles`.

Configurarea activă este `feather/config.lua`: locații, tipuri și garaje implicite.
Manifestul încarcă numai fișierele din `feather/`; vechile fișiere QB și UI-ul
original rămân local pentru referință și nu fac parte din noul pachet Git.
Nu există import automat al vehiculelor vechi.

## În joc

- Cumpără la PDM, marina sau LSIA. Vehiculul este livrat în garaj, nu pe stradă.
- La marcajul garajului, **E** deschide lista proprie. Alege vehiculul pentru a-l scoate.
- **G** pornește/oprește motorul; **U** încuie/descuie mașina apropiată.
  Tastele se pot schimba în setările FiveM.
- Ca șofer, apasă **E** lângă punctul de scoatere sau garaj pentru a parca.
- La parcare se păstrează proprietățile GTA, avariile și combustibilul.
- Vehiculele proprii scoase au un blip albastru „Vehiculul meu · NUMĂR” pe hartă,
  inclusiv când sunt departe. Poziția se actualizează la 5 secunde. Blipul dispare
  la parcare, dispariția entității, ieșirea personajului sau pierderea proprietății.
  Sunt urmărite numai vehiculele din aceeași sesiune; test drive-urile nu sunt incluse.
  Configurare: `GarageConfig.VehicleBlip` (enabled, refreshMs, sprite, color, scale).

Locații implicite: Pillbox pentru mașini, Puerto del Sol pentru bărci și LSIA
pentru aeronave. Accesul public este disponibil în bucketul 0. Scoaterea este
refuzată dacă locul este ocupat, bunul nu este activ sau vehiculul este deja afară.
Cheile proprietarului se verifică în Assets la fiecare comandă; nu există un sold
sau un inventar separat de chei. Cheile delegate, hotwire, flotele organizațiilor,
transferurile, sechestrul și integrarea atelierelor nu sunt incluse în acest pachet.

## Contract pentru shop

Numai resursele din `GarageConfig.TrustedShops` pot apela:

```lua
exports['h4nr-garages']:RegisterPurchasedVehicle({
    orderId = '<uuid>', assetType = 'vehicle', modelKey = 't20',
    holderType = 'character', holderId = '<uuid>', plate = 'LS12 ABC',
    props = { color1 = 27, color2 = 0 }, garage = 'pillboxgarage'
})
-- { ok = true, value = { assetId, plate, garage } } | { ok = false, code }
```

Repetarea aceleiași comenzi returnează aceeași livrare. Dacă numărul este ocupat,
`identifier_taken` permite o reluare cu alt număr pentru același bun. După atribuirea
numărului se păstrează numărul confirmat, inclusiv după un răspuns pierdut.
Schimbarea cumpărătorului, modelului, culorilor sau garajului aceleiași comenzi
este refuzată. Înregistrarea din fundal funcționează și cu personajul offline.
`GetCapabilities()` întoarce `{ok=true,value={ready,purchaseRegistration=1,ownerKeys=1}}`.

## Verificare

```sh
python3 tests/run.py
```

64 de verificări: 45 server (inclusiv validatoarele reale Assets), 10 pentru
blipuri și 9 client
peste Menu v2 real, cu SQL/nativele simulate. Sintaxa tuturor fișierelor Lua
este verificată. Testele nu reprezintă acceptare în joc.

Verificarea în joc încă necesară: cumpărare numerar/bancă, reluare după eroare,
scoatere/parcare, culori, modificări, combustibil, tastele U/G, blipurile de aproape/departe și dispariția la parcare, reconnect și restart
cu vehicul afară, toate cele trei tipuri și refuzul accesului unui al doilea personaj.
La restart, vehiculele încă existente sunt reatașate prin `asset_id`; cele dispărute
redevin disponibile în garaj. Nu se promite salvarea poziției sau a avariilor produse
după ultima parcare dacă FXServer se oprește brusc.

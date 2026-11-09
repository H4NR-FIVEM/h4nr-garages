# h4nr-garages

Public garages for cars, boats and aircraft on the Feather Framework for FiveM. The resource also registers vehicles bought in `h4nr-vehicleshop` and handles physical vehicle keys. The garage is a dedicated NUI panel in `web/`, approved by the owner, using `feather-theme` tokens and the player's accent (Neon Vice). The default language is Romanian, with `en_us` as fallback.

## Requirements

- `feather-mysql`, `ox_lib`
- Feather Core, Character, Assets, Inventory, Economy, Admin, Menu v2 and Notify
- Optional: `h4nr-fuel`

## Installation

```cfg
ensure h4nr-garages
ensure h4nr-vehicleshop
```

- In `feather-admin`, the policies must allow `assets.asset.manage` for `h4nr-garages`, and Feather Assets must list it in `trustedReaders` and `trustedManagers`. These entries already exist in the local FiveM configuration.
- On start the resource creates only its own tables, `h4nr_feather_vehicles` and `h4nr_feather_vehicle_keys`. Ownership lives in Feather Assets. The old QB `player_vehicles` table is never read or written, and old vehicles are not imported automatically.
- The live configuration is `config/shared.lua`: locations, vehicle types and default garages. Texts are in `languages/`. The old QB implementation is no longer kept in this folder.

## In game

- Buy at PDM, the marina or LSIA. The vehicle is delivered to a garage, not to the street.
- A car garage has one point. Stand there and press **E** to open your list and pick a vehicle: it appears on that point. Boats and aircraft keep a separate point for the player. Any garage of that vehicle type works, wherever the vehicle was parked, at no cost.
- The panel lists every vehicle of that type with its real name, plate, where it is and, when parked, its engine, body and fuel from the last parking. Search by model or plate, or filter by stored and out. Up and Down move the selection, Enter in the search box runs the main action, Escape closes. The main button follows the selected vehicle, and when nothing can be done the panel says why. Refusals appear in the panel, not as notifications.
- Taking a vehicle out puts its key in your inventory. It is refused when you have no room for the key.
- **G** starts or stops the engine; **U** locks or unlocks the nearest car you hold the key for. Both can be rebound in the FiveM key settings.
- As the driver with the key and the engine running, press **G** near the spawn point or garage to park (with the engine off, G starts it). Parking takes the key, wherever it is. A trailer hitched to the truck is parked with it and loses its key too; if it cannot be, the truck is still stored and the driver is told.
- On foot beside an empty vehicle you hold the key for, within `GarageConfig.ParkDistance` of the garage, press **G** to park it. At the garage point, **E** opens the list, where the car beside you can be parked too. A truck with a stored trailer shows a checkbox for it; ticked, the trailer is placed behind the truck and hitched, and counts as a vehicle out (`GarageConfig.Towing`). The keys and their controls are in `GarageConfig.Interact`.
- Only one vehicle comes out of a garage at a time, and only when `GarageConfig.SpawnClearance` around the spawn point is free (6 m for cars, 12 m for boats, 20 m for aircraft). Otherwise the retrieval is refused and nothing changes.
- Picking another vehicle while one stands in range offers **Take out and park** that one first, as well as plain retrieval. If the parking is refused nothing comes out. If the retrieval is then refused, the old vehicle stays parked. A vehicle farther away is not touched.
- On foot, an empty vehicle of yours within `GarageConfig.ParkDistance` (30 m) of the garage marker or spawn point appears first in the panel, under **Park near you**, with **Store vehicle** as its action. It works at any garage of that vehicle type and needs the key as well.
- Parking keeps the GTA vehicle properties, damage, dents and fuel, saved and restored by `feather-toolkit`. Dents come back similar, not identical. An older save loads unchanged and simply has no dents.
- A burnt-out vehicle (`GarageConfig.Wreck`) cannot be parked. Its panel entry counts down 20 minutes, then **Bring to the service** removes the wreck and returns the vehicle to the garage with the state of its last parking, free of charge. The wait is kept on the entity, so a wreck that disappears can simply be taken out again.
- Your vehicles that are out have a green "My vehicle · PLATE" blip, even far away. The blip is hidden while you sit in that vehicle and comes back when you get out. Within streaming range the blip follows the car every 250 ms; farther away the position comes from the server every 5 seconds. The blip goes away when you park, the vehicle despawns, you log out or you lose ownership. Only vehicles from the current session are tracked; test drives are not. When the key is with someone else the blip changes to "My vehicle · PLATE (key given)", and the player carrying it sees "Key · PLATE". Settings: `GarageConfig.VehicleBlip` (`enabled`, `refreshMs`, `followMs`, `sprite`, `color`, `lentColor`, `keyHolderColor`, `scale`).

Default locations: Pillbox for cars, Puerto del Sol for boats and LSIA for aircraft. Public access is in routing bucket 0. Taking a vehicle out is refused when the spot is blocked, the asset is not active or the vehicle is already out.

## Vehicle slots

Per character, from `GarageConfig.Slots`: by default at most **2 cars out** at once and **no cap**
on cars held (set `owned` in `limits` to add one). Boats and aircraft have no limit. The garage panel shows both meters and sells extra slots for
the premium currency (`tokens`); the purchase needs a confirming second click. Shops ask
`GetVehicleSlots` before charging, so a full garage refuses a purchase or a sale without taking
money. Admins (`command.garageslots`, which `group.admin` already has) grant slots in game or from
the server console:

```
/garageslots <player id|characterId> <out|owned> <amount>
```

The amount replaces the granted extra (0 removes it); bought slots are kept separately.

## Vehicle keys

The physical key decides who may use a vehicle. Whoever has the `vehicle_key` item in their personal inventory can lock, start and park the car; the owner without it cannot, and sees "You do not have the key". A key in a trunk, a stash or on the ground works for nobody until someone picks it up.

- A vehicle has at most one active key. Each new key gets a new generation in `h4nr_feather_vehicle_keys`, so older ones stop counting even if their item survives.
- A driver without the key cannot move the vehicle, even if someone left the engine running: the client asks the server when the driver sits down and every `GarageConfig.Key.checkMs` (3 s), and stays blocked if the server cannot answer. Passengers are not affected.
- Keys are given with the normal inventory action. Giving one away stops a running engine.
- Players cannot destroy an active key. A voided one is an ordinary item.
- A key from a previous owner never counts. A vehicle with no current key (taken out before this version, or moved by an admin) stays usable by its owner.
- **Recovery with a new key**: if the key is with someone else or lost, the owner asks for a new one from the list at a garage of that vehicle type. The player carrying the key is warned if online. After `GarageConfig.Rekey.waitSeconds` (600) the owner returns and pays `GarageConfig.Rekey.price` ($2500) in cash or by card. The old key is destroyed and the vehicle returns to the garage with the properties of its last parking. Nothing is charged before that point. Getting the key back cancels the request, and a vehicle with a driver is refused.
- Taking a vehicle out when its old entity is gone replaces the key. A vehicle missing from the street on two checks in a row (`GarageConfig.Key.lostCheckMs`, 30 s) loses its key, and so do vehicles found missing on startup.
- `exports['h4nr-garages']:ToggleEngine(vehicle)` on the client gives panels the same check as the G key. `h4nr-vehiclecontrol` uses it.

This is a gameplay barrier, not anti-cheat: a modified client can still start an engine locally, but it gets no parking or sale.

Hotwiring, organisation fleets, impounds and mechanic shops are not part of this resource.

## Contract for shops

Only resources listed in `GarageConfig.TrustedShops` can call:

```lua
exports['h4nr-garages']:RegisterPurchasedVehicle({
    orderId = '<uuid>', assetType = 'vehicle', modelKey = 't20',
    holderType = 'character', holderId = '<uuid>', plate = 'LS12 ABC',
    props = { color1 = 27, color2 = 0 }, garage = 'pillboxgarage'
})
-- { ok = true, value = { assetId, plate, garage } } | { ok = false, code }
```

- Repeating the same order returns the same delivery.
- If the plate is taken, `identifier_taken` lets the shop retry with another plate for the same asset. Once a plate is assigned, the confirmed plate is kept, even after a lost reply.
- Changing the buyer, model, colours or garage of an existing order is refused.
- Registration in the background works with the character offline.

Sale support, for the same trusted shops. The shop owns the offer and the money; the garage owns the vehicle and is the only resource that changes its owner:

```lua
exports['h4nr-garages']:ListParkedVehicles({ holderId = '<uuid>' })
-- { ok = true, value = { items = { { assetId, assetType, model, plate, garage } } } }
exports['h4nr-garages']:ReserveForSale({ saleId = '<uuid>', assetId = '<uuid>', sellerId = '<uuid>' })
exports['h4nr-garages']:ReleaseSaleReservation({ saleId = '<uuid>', assetId = '<uuid>' })
exports['h4nr-garages']:TransferReservedVehicle({ saleId = '<uuid>', assetId = '<uuid>', sellerId = '<uuid>', buyerId = '<uuid>' })
-- { ok = true, value = { garage } } | { ok = false, code }
```

- Only a parked vehicle can be reserved. A reserved vehicle (`sale_reserved`) cannot be taken out, and the reservation survives a restart.
- All three calls can be repeated safely. A transfer whose reply was lost finds the buyer already holding the vehicle. `reservation_lost` means the sale no longer holds it.
- The vehicle stays in the same garage with its properties, damage and fuel.

Trade-in, for the same trusted shops, on a vehicle already reserved with `ReserveForSale`:

```lua
exports['h4nr-garages']:RetireReservedVehicle({ saleId = '<uuid>', assetId = '<uuid>', sellerId = '<uuid>' })
-- { ok = true, value = true } | { ok = false, code }
```

- The asset is retired in Assets, which is final, and its key is voided. Its plate stays reserved for ever.
- The call can be repeated safely. The garage row stays `sale_reserved` with the same `sale_id`, so it can never be taken out and a retry after a lost reply still succeeds.
- `reservation_lost` means this sale does not hold the vehicle, and nothing was retired.

`ChangeVehiclePlate({ saleId, assetId, ownerId, plate })` gives a vehicle reserved with `ReserveForSale` a new plate, in one commit in Assets. It can be repeated safely. `identifier_taken` means another vehicle holds or once held that plate, and nothing changed. Everything else about the vehicle is stored by asset, and spawning reads the plate from Assets.

`CountVehiclesByModel({ modelKey = 't20' })` returns `{ ok = true, value = { count } }`, the vehicles of a model that are not retired. A shop uses it before dropping a model.

`GetCapabilities()` returns `{ ok = true, value = { ready, purchaseRegistration = 1, keyItems = 1, vehicleSale = 1, vehicleTradeIn = 1, plateChange = 1 } }`.

## Tests

```sh
python3 tests/run.py
```

215 checks: 165 server checks (including the real Feather Assets validators), 13 for blips and 37 client checks on the real Menu v2, with SQL, Inventory and natives simulated. The syntax of every Lua file is checked too.

Still check in game: buying with cash and bank, retrying after an error, taking out and parking, colours, mods, fuel, the U and G keys, giving a key to another player and getting it back, a key in a trunk and on the ground, a full inventory, the F3 engine button, a key recovery with the wait and payment, blips near and far and their removal on parking, reconnecting and restarting with a vehicle out, all three vehicle types, and a second character being refused.

After a restart, vehicles that still exist are re-attached by `asset_id`, and vehicles that are gone return to the garage. Position and damage after the last parking are not guaranteed to be saved if FXServer stops abruptly.

## License

GPL-3.0, see `LICENSE`.


Model names may include hyphens (for example `f-one49d`) with Feather Assets
0.2.2 or later. Version 2.0.2 admits these names through the purchase registration
contract; ownership and spawning continue to use the exact original model name.


## Marcaje, prompt și deschiderea listei — 2.0.3

La maximum 25 m se vede o săgeată verde ca la joburi. Pe jos, aceasta marchează
intrarea garajului; la volan, marchează punctul de parcare/scoatere. Promptul
Feather Toolkit arată E — Deschide garajul sau E — Parchează vehiculul. Parcarea
este oferită doar șoferului unui vehicul gestionat de garaj; serverul verifică în
continuare proprietatea, distanța și sesiunea. `GarageConfig.Marker` configurează
tipul, raza de afișare, mărimea și culoarea.

Lista și coordonatele pentru blipuri sunt citiri și nu mai ocupă blocajul pentru
operațiile pe vehicul. Retrieve/store/keys rămân serializate. Testele reproduc un
poll de hartă suspendat în timp ce se deschide lista și confirmă că o citire nu
eliberează blocajul unei mutații în curs. Meniul așteaptă readiness NUI.

Transportul RPC (inclusiv al doilea rezultat nil/error) și refuzurile serverului
sunt diagnosticate explicit. În locul unui eșec generic, apar traduceri pentru
busy, timeout, sesiune, distanță, readiness și autorizare; codurile necunoscute sunt
incluse în mesaj. F8 raportează `[h4nr-garages] RPC list refused: code=...`, iar
serverul înregistrează refuzurile listei fără datele inventarului sau identități.
Cauza exactă a incidentului raportat în joc nu a fost confirmată printr-un cod live;
remedierea concurenței și mesajele au fost validate offline, nu în FiveM.

După actualizare: `refresh`, apoi `restart h4nr-garages`. Toolkit trebuie pornit;
este acum dependență declarată. Nu s-a efectuat restart de către agent.

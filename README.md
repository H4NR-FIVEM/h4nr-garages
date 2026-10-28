# h4nr-garages

Public garages for cars, boats and aircraft on the Feather Framework for FiveM. The resource also registers vehicles bought in `h4nr-vehicleshop` and handles the owner's keys. Menus use Feather Menu v2 with the `modern` preset (Neon Vice). The default language is Romanian, with `en_us` as fallback.

## Requirements

- `feather-mysql`, `ox_lib`
- Feather Core, Character, Assets, Admin, Menu v2 and Notify
- `h4nr-feather`
- Optional: `h4nr-fuel`

## Installation

```cfg
ensure h4nr-garages
ensure h4nr-vehicleshop
```

- In `feather-admin`, the policies must allow `assets.asset.manage` for `h4nr-garages`, and Feather Assets must list it in `trustedReaders` and `trustedManagers`. These entries already exist in the local FiveM configuration.
- On start the resource creates only its own table, `h4nr_feather_vehicles`. Ownership lives in Feather Assets. The old QB `player_vehicles` table is never read or written, and old vehicles are not imported automatically.
- The live configuration is `feather/config.lua`: locations, vehicle types and default garages. The manifest only loads files from `feather/`.

## In game

- Buy at PDM, the marina or LSIA. The vehicle is delivered to a garage, not to the street.
- At a garage marker, press **E** to open your list and pick a vehicle to take it out.
- **G** starts or stops the engine; **U** locks or unlocks the nearest of your cars. Both keys can be rebound in the FiveM key settings.
- As the driver, press **E** near the spawn point or garage to park.
- Parking keeps the GTA vehicle properties, damage and fuel.
- Your vehicles that are out have a blue "My vehicle · PLATE" blip, even far away. The position refreshes every 5 seconds. The blip goes away when you park, the vehicle despawns, you log out or you lose ownership. Only vehicles from the current session are tracked; test drives are not. Settings: `GarageConfig.VehicleBlip` (`enabled`, `refreshMs`, `sprite`, `color`, `scale`).

Default locations: Pillbox for cars, Puerto del Sol for boats and LSIA for aircraft. Public access is in routing bucket 0. Taking a vehicle out is refused when the spot is blocked, the asset is not active or the vehicle is already out.

Owner keys are checked in Feather Assets on every command; there is no separate key item. Delegated keys, hotwiring, organisation fleets, transfers, impounds and mechanic shops are not part of this resource.

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

`GetCapabilities()` returns `{ ok = true, value = { ready, purchaseRegistration = 1, ownerKeys = 1 } }`.

## Tests

```sh
python3 tests/run.py
```

64 checks: 45 server checks (including the real Feather Assets validators), 10 for blips and 9 client checks on the real Menu v2, with SQL and natives simulated. The syntax of every Lua file is checked too.

Still check in game: buying with cash and bank, retrying after an error, taking out and parking, colours, mods, fuel, the U and G keys, blips near and far and their removal on parking, reconnecting and restarting with a vehicle out, all three vehicle types, and a second character being refused.

After a restart, vehicles that still exist are re-attached by `asset_id`, and vehicles that are gone return to the garage. Position and damage after the last parking are not guaranteed to be saved if FXServer stops abruptly.

## License

GPL-3.0, see `LICENSE`.

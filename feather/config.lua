GarageConfig = {
    DefaultLang = 'ro',
    Distance = 3.0,
    TrustedShops = { ['h4nr-vehicleshop'] = true },
    DefaultGarage = { vehicle = 'pillboxgarage', boat = 'marina', aircraft = 'lsia' },
    Garages = {
        pillboxgarage = { label = 'Pillbox — Garaj', assetType = 'vehicle',
            coords = vector3(215.8, -810.1, 30.7), spawn = vector4(229.7, -800.1, 30.6, 157.0), sprite = 357 },
        marina = { label = 'Puerto del Sol — Port', assetType = 'boat',
            coords = vector3(-718.5, -1326.8, 1.6), spawn = vector4(-727.5, -1367.8, 0.5, 136.6), sprite = 410 },
        lsia = { label = 'LSIA — Hangar', assetType = 'aircraft',
            coords = vector3(-1605.7, -3139.5, 13.9), spawn = vector4(-1591.9, -3121.9, 13.9, 229.3), sprite = 359 }
    }
}

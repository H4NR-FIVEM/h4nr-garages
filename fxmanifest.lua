fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'iseeyoucopy'
description 'Feather vehicle registration, public garages and owner keys'
version '2.0.1'

shared_scripts {
    '@ox_lib/init.lua',
    '@h4nr-feather/shared.lua',
    'config/shared.lua',
}

client_scripts {
    'locale.lua',
    'languages/*.lua',
    'client/main.lua',
    'client/vehicle_blips.lua',
}

server_scripts {
    '@feather-mysql/lib/DB.lua',
    'server/registration.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'feather-mysql',
    'h4nr-feather',
    'feather-core',
    'feather-assets',
    'feather-character',
    'feather-menu-v2',
    'feather-notify',
}

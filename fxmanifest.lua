fx_version 'cerulean'
game 'gta5'
lua54 'yes'
author 'iseeyoucopy'
description 'Feather vehicle registration, public garages and owner keys'
version '2.0.0'
shared_scripts { '@ox_lib/init.lua', '@h4nr-feather/shared.lua', 'feather/config.lua' }
server_scripts { '@oxmysql/lib/MySQL.lua', 'feather/server/registration.lua', 'feather/server/main.lua' }
client_scripts { 'feather/client/main.lua' }
dependencies { 'ox_lib', 'oxmysql', 'h4nr-feather', 'feather-core', 'feather-assets', 'feather-character',
    'feather-menu-v2', 'feather-notify' }
-- Legacy QB files remain on disk for reference; they are not loaded.

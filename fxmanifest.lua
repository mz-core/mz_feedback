fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mz_feedback'
author 'Mazus'
description 'Feedback seguro de players com texto, imagens e painel de moderacao.'
version '1.0.0'

ui_page 'web/index.html'

shared_scripts {
  'shared/config.lua'
}

client_scripts {
  'client/main.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/validation.lua',
  'server/prepare.lua',
  'server/main.lua'
}

files {
  'web/index.html',
  'web/style.css',
  'web/app.js'
}

dependencies {
  'oxmysql',
  'mz_core',
  'mz_notify',
  'screenshot-basic'
}

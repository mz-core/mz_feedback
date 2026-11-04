Config = {}

Config.Command = 'feedback'
Config.StaffCommand = 'feedbacks'
Config.StaffPermission = 'staff.panel.open'

Config.TextMinLength = 20
Config.TextMaxLength = 2000
Config.MaxImages = 3
Config.MaxImageBytes = 350 * 1024
Config.MaxTotalImageBytes = 900 * 1024
Config.MaxSourceImageBytes = 8 * 1024 * 1024
Config.MaxImageWidth = 1600
Config.MaxImageHeight = 1200

Config.SubmitCooldownSeconds = 120
Config.MaxSubmissionsPerHour = 5
Config.StaffListLimit = 50
Config.LatentBytesPerSecond = 256 * 1024

Config.AllowedMimeTypes = {
  ['image/jpeg'] = true,
  ['image/png'] = true,
  ['image/webp'] = true
}

Config.Categories = {
  bug = 'Problema / bug',
  suggestion = 'Sugestao',
  gameplay = 'Jogabilidade',
  other = 'Outro'
}

Config.Statuses = {
  new = 'Novo',
  reviewing = 'Em analise',
  resolved = 'Resolvido',
  rejected = 'Arquivado'
}

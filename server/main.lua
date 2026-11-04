local recentSubmissions = {}
local submissionsInFlight = {}

local ERROR_MESSAGES = {
  invalid_payload = 'Os dados enviados sao invalidos.',
  invalid_category = 'Selecione uma categoria valida.',
  invalid_text_encoding = 'O texto possui caracteres invalidos.',
  text_too_short = ('Escreva pelo menos %d caracteres.'):format(Config.TextMinLength),
  text_too_long = ('O texto pode ter no maximo %d caracteres.'):format(Config.TextMaxLength),
  too_many_images = ('Envie no maximo %d imagens.'):format(Config.MaxImages),
  unsupported_image_type = 'Uma imagem usa um formato nao permitido.',
  invalid_image = 'Uma das imagens e invalida.',
  invalid_image_encoding = 'Uma das imagens esta corrompida.',
  image_signature_mismatch = 'O conteudo de uma imagem nao corresponde ao formato informado.',
  image_too_large = ('Cada imagem pode ter no maximo %d KB.'):format(math.floor(Config.MaxImageBytes / 1024)),
  images_total_too_large = ('As imagens podem somar no maximo %d KB.'):format(math.floor(Config.MaxTotalImageBytes / 1024)),
  cooldown = 'Aguarde antes de enviar outro feedback.',
  hourly_limit = 'Voce atingiu o limite de feedbacks desta hora.',
  database_error = 'Nao foi possivel salvar agora. Tente novamente em instantes.',
  identity_unavailable = 'Seu personagem ativo nao pode ser validado agora.',
  permission_denied = 'Voce nao tem permissao para acessar os feedbacks.',
  not_found = 'Feedback nao encontrado.',
  invalid_status = 'Status invalido.'
}

local function notify(sourceId, notifyType, title, message)
  TriggerClientEvent('mz_notify:client:show', sourceId, {
    type = notifyType,
    title = title,
    message = message,
    duration = 6000
  })
end

local function resolveIdentity(sourceId)
  local ok, identity = pcall(function()
    return exports['mz_core']:ResolvePlayerIdentity(sourceId)
  end)

  if ok and type(identity) == 'table' and identity.ok == true then
    local fullName = (('%s %s'):format(identity.firstname or '', identity.lastname or ''))
      :gsub('^%s+', '')
      :gsub('%s+$', '')
    return {
      accountId = tonumber(identity.accountId),
      characterId = tonumber(identity.characterId),
      name = fullName ~= '' and fullName or tostring(GetPlayerName(sourceId) or ('ID ' .. tostring(sourceId)))
    }
  end

  return nil, 'identity_unavailable'
end

local function hasStaffPermission(sourceId)
  if GetResourceState('mz_core') ~= 'started' then
    return false
  end

  local ok, allowed = pcall(function()
    return exports['mz_core']:HasGlobalPermission(sourceId, Config.StaffPermission)
  end)
  return ok and allowed == true
end

local function rateAllowed(sourceId, accountId)
  local now = os.time()
  local key = tonumber(accountId) or ('source:' .. tostring(sourceId))
  local bucket = recentSubmissions[key] or {}
  local active = {}

  for _, timestamp in ipairs(bucket) do
    if now - timestamp < 3600 then
      active[#active + 1] = timestamp
    end
  end

  recentSubmissions[key] = active
  local latest = active[#active]
  if latest and now - latest < Config.SubmitCooldownSeconds then
    return false, 'cooldown', Config.SubmitCooldownSeconds - (now - latest)
  end
  if #active >= Config.MaxSubmissionsPerHour then
    return false, 'hourly_limit'
  end

  return true
end

local function recordRate(accountId)
  local bucket = recentSubmissions[accountId] or {}
  bucket[#bucket + 1] = os.time()
  recentSubmissions[accountId] = bucket
end

local function databaseRateAllowed(accountId)
  local row = MySQL.single.await([[
    SELECT
      COUNT(*) AS submission_count,
      COALESCE(TIMESTAMPDIFF(SECOND, MAX(created_at), CURRENT_TIMESTAMP), 999999) AS seconds_since_last
    FROM mz_feedback_reports
    WHERE account_id = ?
      AND created_at >= DATE_SUB(CURRENT_TIMESTAMP, INTERVAL 1 HOUR)
  ]], { accountId }) or {}

  local count = tonumber(row.submission_count) or 0
  local secondsSinceLast = tonumber(row.seconds_since_last) or 999999
  if secondsSinceLast < Config.SubmitCooldownSeconds then
    return false, 'cooldown', Config.SubmitCooldownSeconds - secondsSinceLast
  end
  if count >= Config.MaxSubmissionsPerHour then
    return false, 'hourly_limit'
  end
  return true
end

local function submissionResult(sourceId, requestId, ok, errorCode, data)
  TriggerClientEvent('mz_feedback:client:submissionResult', sourceId, {
    requestId = tostring(requestId or ''),
    ok = ok == true,
    error = errorCode,
    message = errorCode and (ERROR_MESSAGES[errorCode] or 'Nao foi possivel concluir.') or nil,
    data = data
  })
end

RegisterNetEvent('mz_feedback:server:submit', function(payload)
  local sourceId = tonumber(source)
  if not sourceId or sourceId <= 0 then return end

  local requestId = type(payload) == 'table' and tostring(payload.requestId or '') or ''
  if #requestId > 80 then requestId = requestId:sub(1, 80) end

  local validated, validationError = MZFeedbackValidation.validateSubmission(payload)
  if not validated then
    submissionResult(sourceId, requestId, false, validationError)
    return
  end

  if submissionsInFlight[sourceId] then
    submissionResult(sourceId, requestId, false, 'cooldown')
    return
  end
  submissionsInFlight[sourceId] = true

  local identity = resolveIdentity(sourceId)
  if not identity or not identity.accountId or not identity.characterId then
    submissionsInFlight[sourceId] = nil
    submissionResult(sourceId, requestId, false, 'identity_unavailable')
    return
  end
  local allowed, rateError, remaining = rateAllowed(sourceId, identity.accountId)
  if not allowed then
    local message = ERROR_MESSAGES[rateError]
    if rateError == 'cooldown' and remaining then
      message = ('Aguarde %d segundos antes de enviar novamente.'):format(remaining)
    end
    TriggerClientEvent('mz_feedback:client:submissionResult', sourceId, {
      requestId = requestId,
      ok = false,
      error = rateError,
      message = message
    })
    submissionsInFlight[sourceId] = nil
    return
  end

  local databaseRateOk, databaseAllowed, databaseRateError, databaseRemaining = pcall(
    databaseRateAllowed,
    identity.accountId
  )
  if not databaseRateOk then
    submissionsInFlight[sourceId] = nil
    submissionResult(sourceId, requestId, false, 'database_error')
    return
  end
  if not databaseAllowed then
    local message = ERROR_MESSAGES[databaseRateError]
    if databaseRateError == 'cooldown' and databaseRemaining then
      message = ('Aguarde %d segundos antes de enviar novamente.'):format(databaseRemaining)
    end
    TriggerClientEvent('mz_feedback:client:submissionResult', sourceId, {
      requestId = requestId,
      ok = false,
      error = databaseRateError,
      message = message
    })
    submissionsInFlight[sourceId] = nil
    return
  end

  local inserted, reportId = pcall(function()
    return MySQL.insert.await([[
      INSERT INTO mz_feedback_reports
        (account_id, character_id, player_name, category, message, status, image_count)
      VALUES (?, ?, ?, ?, ?, 'new', ?)
    ]], {
      identity.accountId,
      identity.characterId,
      identity.name,
      validated.category,
      validated.message,
      #validated.images
    })
  end)

  reportId = tonumber(reportId)
  if not inserted or not reportId then
    submissionsInFlight[sourceId] = nil
    submissionResult(sourceId, requestId, false, 'database_error')
    return
  end

  local imagesOk = true
  for _, image in ipairs(validated.images) do
    local ok, imageId = pcall(function()
      return MySQL.insert.await([[
        INSERT INTO mz_feedback_images (feedback_id, mime_type, byte_size, image_data)
        VALUES (?, ?, ?, ?)
      ]], { reportId, image.mimeType, image.byteSize, image.dataUrl })
    end)
    if not ok or not tonumber(imageId) then
      imagesOk = false
      break
    end
  end

  if not imagesOk then
    submissionsInFlight[sourceId] = nil
    pcall(function()
      MySQL.query.await('DELETE FROM mz_feedback_reports WHERE id = ?', { reportId })
    end)
    submissionResult(sourceId, requestId, false, 'database_error')
    return
  end

  recordRate(identity.accountId)
  submissionsInFlight[sourceId] = nil
  submissionResult(sourceId, requestId, true, nil, { id = reportId })
  notify(sourceId, 'success', 'Feedback enviado', ('Obrigado! Seu protocolo e #%d.'):format(reportId))
end)

RegisterNetEvent('mz_feedback:server:list', function()
  local sourceId = tonumber(source)
  if not sourceId or not hasStaffPermission(sourceId) then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.permission_denied)
    return
  end

  local rows = MySQL.query.await([[
    SELECT id, account_id, character_id, player_name, category, message, status, image_count, created_at, updated_at
    FROM mz_feedback_reports
    ORDER BY id DESC
    LIMIT ?
  ]], { Config.StaffListLimit }) or {}

  TriggerLatentClientEvent('mz_feedback:client:listResult', sourceId, Config.LatentBytesPerSecond, rows)
end)

RegisterNetEvent('mz_feedback:server:requestStaffOpen', function()
  local sourceId = tonumber(source)
  if not sourceId then return end

  if not hasStaffPermission(sourceId) then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.permission_denied)
    return
  end

  TriggerClientEvent('mz_feedback:client:staffOpenAllowed', sourceId)
end)

RegisterNetEvent('mz_feedback:server:detail', function(feedbackId)
  local sourceId = tonumber(source)
  if not sourceId or not hasStaffPermission(sourceId) then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.permission_denied)
    return
  end

  feedbackId = tonumber(feedbackId)
  if not feedbackId or feedbackId <= 0 then return end

  local report = MySQL.single.await([[
    SELECT id, account_id, character_id, player_name, category, message, status, image_count,
           reviewer_account_id, reviewer_character_id, created_at, updated_at
    FROM mz_feedback_reports
    WHERE id = ?
    LIMIT 1
  ]], { feedbackId })

  if not report then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.not_found)
    return
  end

  report.images = MySQL.query.await([[
    SELECT id, mime_type, byte_size, image_data
    FROM mz_feedback_images
    WHERE feedback_id = ?
    ORDER BY id ASC
  ]], { feedbackId }) or {}

  TriggerLatentClientEvent('mz_feedback:client:detailResult', sourceId, Config.LatentBytesPerSecond, report)
end)

RegisterNetEvent('mz_feedback:server:updateStatus', function(feedbackId, requestedStatus)
  local sourceId = tonumber(source)
  if not sourceId or not hasStaffPermission(sourceId) then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.permission_denied)
    return
  end

  feedbackId = tonumber(feedbackId)
  local status = MZFeedbackValidation.normalizeStatus(requestedStatus)
  if not feedbackId or feedbackId <= 0 or not status then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.invalid_status)
    return
  end

  local reviewer = resolveIdentity(sourceId)
  if not reviewer then
    notify(sourceId, 'error', 'Feedbacks', 'Identidade runtime indisponivel.')
    return
  end
  local changed = MySQL.update.await([[
    UPDATE mz_feedback_reports
    SET status = ?, reviewer_account_id = ?, reviewer_character_id = ?
    WHERE id = ?
  ]], { status, reviewer.accountId, reviewer.characterId, feedbackId })

  if not changed or changed < 1 then
    notify(sourceId, 'error', 'Feedbacks', ERROR_MESSAGES.not_found)
    return
  end

  TriggerClientEvent('mz_feedback:client:statusResult', sourceId, {
    id = feedbackId,
    status = status
  })
  notify(sourceId, 'success', 'Feedbacks', 'Status atualizado.')
end)

AddEventHandler('playerDropped', function()
  local sourceId = tonumber(source)
  if sourceId then
    recentSubmissions[tostring(sourceId)] = nil
    submissionsInFlight[sourceId] = nil
  end
end)

local uiOpen = false
local currentMode = nil

local function setFocus(enabled)
  SetNuiFocus(enabled, enabled)
  SetNuiFocusKeepInput(false)
end

local function openUi(mode)
  uiOpen = true
  currentMode = mode
  setFocus(true)
  SendNUIMessage({
    action = 'open',
    mode = mode,
    config = {
      command = Config.Command,
      textMinLength = Config.TextMinLength,
      textMaxLength = Config.TextMaxLength,
      maxImages = Config.MaxImages,
      maxImageBytes = Config.MaxImageBytes,
      maxTotalImageBytes = Config.MaxTotalImageBytes,
      maxSourceImageBytes = Config.MaxSourceImageBytes,
      maxImageWidth = Config.MaxImageWidth,
      maxImageHeight = Config.MaxImageHeight,
      categories = Config.Categories,
      statuses = Config.Statuses
    }
  })

  if mode == 'staff' then
    TriggerServerEvent('mz_feedback:server:list')
  end
end

local function closeUi()
  uiOpen = false
  currentMode = nil
  setFocus(false)
  SendNUIMessage({ action = 'close' })
end

RegisterCommand(Config.Command, function()
  openUi('submit')
end, false)

RegisterCommand(Config.StaffCommand, function()
  TriggerServerEvent('mz_feedback:server:requestStaffOpen')
end, false)

RegisterKeyMapping(Config.Command, 'Abrir formulario de feedback', 'keyboard', 'F10')

RegisterNUICallback('close', function(_, callback)
  closeUi()
  callback({ ok = true })
end)

RegisterNUICallback('submit', function(data, callback)
  if type(data) ~= 'table' then
    callback({ ok = false, error = 'invalid_payload' })
    return
  end

  local images = type(data.images) == 'table' and data.images or {}
  if #images > Config.MaxImages then
    callback({ ok = false, error = 'too_many_images' })
    return
  end

  local requestId = ('%d:%d'):format(GetPlayerServerId(PlayerId()), GetGameTimer())
  data.requestId = requestId
  TriggerLatentServerEvent('mz_feedback:server:submit', Config.LatentBytesPerSecond, data)
  callback({ ok = true, pending = true, requestId = requestId })
end)

RegisterNUICallback('captureScreenshot', function(_, callback)
  if GetResourceState('screenshot-basic') ~= 'started' then
    callback({ ok = false, message = 'A captura de tela nao esta disponivel.' })
    return
  end

  exports['screenshot-basic']:requestScreenshot({
    encoding = 'jpg',
    quality = 0.82
  }, function(dataUrl)
    if type(dataUrl) ~= 'string' or dataUrl:sub(1, 23) ~= 'data:image/jpeg;base64,' then
      callback({ ok = false, message = 'Nao foi possivel capturar a tela.' })
      return
    end
    callback({ ok = true, dataUrl = dataUrl })
  end)
end)

RegisterNUICallback('requestDetail', function(data, callback)
  if currentMode ~= 'staff' then
    callback({ ok = false })
    return
  end

  TriggerServerEvent('mz_feedback:server:detail', tonumber(data and data.id))
  callback({ ok = true })
end)

RegisterNUICallback('updateStatus', function(data, callback)
  if currentMode ~= 'staff' then
    callback({ ok = false })
    return
  end

  TriggerServerEvent('mz_feedback:server:updateStatus', tonumber(data and data.id), data and data.status)
  callback({ ok = true })
end)

RegisterNetEvent('mz_feedback:client:submissionResult', function(result)
  SendNUIMessage({ action = 'submissionResult', result = result })
  if result and result.ok == true then
    closeUi()
  end
end)

RegisterNetEvent('mz_feedback:client:listResult', function(rows)
  SendNUIMessage({ action = 'staffList', rows = rows or {} })
end)

RegisterNetEvent('mz_feedback:client:staffOpenAllowed', function()
  openUi('staff')
end)

RegisterNetEvent('mz_feedback:client:detailResult', function(report)
  SendNUIMessage({ action = 'staffDetail', report = report })
end)

RegisterNetEvent('mz_feedback:client:statusResult', function(result)
  SendNUIMessage({ action = 'statusResult', result = result })
end)

CreateThread(function()
  Wait(1000)
  SendNUIMessage({
    action = 'boot',
    command = Config.Command,
    key = 'F10'
  })
end)

AddEventHandler('onResourceStop', function(resourceName)
  if resourceName ~= GetCurrentResourceName() then return end
  if uiOpen then setFocus(false) end
end)

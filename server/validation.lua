MZFeedbackValidation = {}

local function trim(value)
  return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

local function utf8Length(value)
  local ok, length = pcall(utf8.len, value)
  if not ok or not length then
    return nil
  end
  return length
end

local function decodedSize(base64)
  local padding = base64:sub(-2) == '==' and 2 or (base64:sub(-1) == '=' and 1 or 0)
  return math.floor(#base64 * 3 / 4) - padding
end

local alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local alphabetIndex = {}
for index = 1, #alphabet do
  alphabetIndex[alphabet:sub(index, index)] = index - 1
end

local function decodePrefix(base64, wantedBytes)
  local output = {}
  local accumulator = 0
  local bits = 0

  for index = 1, math.min(#base64, 32) do
    local character = base64:sub(index, index)
    if character == '=' then break end

    local value = alphabetIndex[character]
    if value == nil then return nil end

    accumulator = accumulator * 64 + value
    bits = bits + 6

    while bits >= 8 do
      bits = bits - 8
      local divisor = 2 ^ bits
      local byte = math.floor(accumulator / divisor) % 256
      output[#output + 1] = string.char(byte)
      accumulator = accumulator % divisor

      if #output >= wantedBytes then
        return table.concat(output)
      end
    end
  end

  return table.concat(output)
end

local function magicMatches(mimeType, prefix)
  if mimeType == 'image/jpeg' then
    return prefix:sub(1, 3) == string.char(0xFF, 0xD8, 0xFF)
  end

  if mimeType == 'image/png' then
    return prefix:sub(1, 8) == string.char(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
  end

  if mimeType == 'image/webp' then
    return prefix:sub(1, 4) == 'RIFF' and prefix:sub(9, 12) == 'WEBP'
  end

  return false
end

function MZFeedbackValidation.validateImage(dataUrl)
  if type(dataUrl) ~= 'string' then
    return nil, 'invalid_image'
  end

  local mimeType, base64 = dataUrl:match('^data:([^;]+);base64,(.+)$')
  if not mimeType or not Config.AllowedMimeTypes[mimeType] then
    return nil, 'unsupported_image_type'
  end

  local maxEncodedLength = math.ceil(Config.MaxImageBytes / 3) * 4 + 4
  if #base64 > maxEncodedLength or #base64 < 16 then
    return nil, 'image_too_large'
  end

  if #base64 % 4 ~= 0 or base64:find('[^A-Za-z0-9+/=]') then
    return nil, 'invalid_image_encoding'
  end

  local firstPadding = base64:find('=', 1, true)
  if firstPadding then
    local padding = base64:match('(=*)$') or ''
    if #padding > 2 or firstPadding ~= (#base64 - #padding + 1) then
      return nil, 'invalid_image_encoding'
    end
  end

  local byteSize = decodedSize(base64)
  if byteSize <= 0 or byteSize > Config.MaxImageBytes then
    return nil, 'image_too_large'
  end

  local prefix = decodePrefix(base64, 12)
  if not prefix or not magicMatches(mimeType, prefix) then
    return nil, 'image_signature_mismatch'
  end

  return {
    mimeType = mimeType,
    byteSize = byteSize,
    dataUrl = dataUrl
  }
end

function MZFeedbackValidation.validateSubmission(payload)
  if type(payload) ~= 'table' then
    return nil, 'invalid_payload'
  end

  local category = trim(payload.category):lower()
  if not Config.Categories[category] then
    return nil, 'invalid_category'
  end

  local message = trim(payload.message)
  if #message > Config.TextMaxLength * 4 then
    return nil, 'text_too_long'
  end
  local messageLength = utf8Length(message)
  if not messageLength then
    return nil, 'invalid_text_encoding'
  end
  if messageLength < Config.TextMinLength then
    return nil, 'text_too_short'
  end
  if messageLength > Config.TextMaxLength then
    return nil, 'text_too_long'
  end

  local rawImages = payload.images
  if rawImages == nil then rawImages = {} end
  if type(rawImages) ~= 'table' or #rawImages > Config.MaxImages then
    return nil, 'too_many_images'
  end

  local images = {}
  local totalBytes = 0
  for index = 1, #rawImages do
    local image, imageError = MZFeedbackValidation.validateImage(rawImages[index])
    if not image then
      return nil, imageError
    end

    totalBytes = totalBytes + image.byteSize
    if totalBytes > Config.MaxTotalImageBytes then
      return nil, 'images_total_too_large'
    end
    images[#images + 1] = image
  end

  return {
    category = category,
    message = message,
    images = images,
    totalBytes = totalBytes
  }
end

function MZFeedbackValidation.normalizeStatus(status)
  status = trim(status):lower()
  if Config.Statuses[status] then
    return status
  end
  return nil
end

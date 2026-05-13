-- MusicCraft Radio Receiver
-- Broadcast Receiver v3
-- CC:Tweaked / ATM10 / No Computronics

local RADIO_PROTOCOL = "musiccraft.radio.v1"
local DISCOVERY_PROTOCOL = "musiccraft.radio.discovery.v1"
local ROLE_PREFIX = "musiccraft-rx"
local CONFIG_PATH = "musiccraft_receiver.cfg"

local DEFAULT_CONFIG = {
  volume = 1.0,
  prebufferChunks = 8,
  maxBufferChunks = 64,
  listening = true,
}

local dfpwm = require("cc.audio.dfpwm")

local function copyDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then target[k] = v end
  end
  return target
end

local function loadConfig()
  if fs.exists(CONFIG_PATH) then
    local h = fs.open(CONFIG_PATH, "r")
    local text = h.readAll()
    h.close()

    local ok, data = pcall(textutils.unserialize, text)
    if ok and type(data) == "table" then
      return copyDefaults(data, DEFAULT_CONFIG)
    end
  end

  return copyDefaults({}, DEFAULT_CONFIG)
end

local config = loadConfig()

local function saveConfig()
  local h = fs.open(CONFIG_PATH, "w")
  h.write(textutils.serialize(config))
  h.close()
end

local function sanitizeName(name)
  name = tostring(name or ""):lower()
  name = name:gsub("%s+", "-")
  name = name:gsub("[^%w%-_]", "")
  name = name:gsub("%-+", "-")
  name = name:gsub("^%-", "")
  name = name:gsub("%-$", "")
  return name
end

local function openWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)
      if modem and modem.isWireless and modem.isWireless() then
        if not rednet.isOpen(name) then rednet.open(name) end
        return name
      end
    end
  end

  error("No wireless modem found.")
end

local function ensureComputerLabel()
  local label = os.getComputerLabel()

  if label and label ~= "" then
    return sanitizeName(label)
  end

  local generated = ROLE_PREFIX .. "-" .. tostring(os.getComputerID())
  os.setComputerLabel(generated)
  return generated
end

local function claimUniqueHostname()
  local baseName = ensureComputerLabel()

  if not baseName:find("^" .. ROLE_PREFIX) then
    baseName = ROLE_PREFIX .. "-" .. baseName
  end

  local desiredName = baseName
  local existingId = rednet.lookup(RADIO_PROTOCOL, desiredName)

  if existingId and existingId ~= os.getComputerID() then
    desiredName = baseName .. "-" .. tostring(os.getComputerID())
    os.setComputerLabel(desiredName)
  end

  pcall(function() rednet.host(RADIO_PROTOCOL, desiredName) end)
  return desiredName
end

local speaker = peripheral.find("speaker")
if not speaker then
  error("No attached speaker found.")
end

local modemName = openWirelessModem()
local HOSTNAME = claimUniqueHostname()

local state = {
  streamId = nil,
  title = nil,
  decoder = nil,
  buffer = {},
  expectedSeq = 1,
  receiving = false,
  playing = false,
  ended = false,
  underruns = 0,
  chunksReceived = 0,
  chunksPlayed = 0,
  lastSender = nil,
  lastStatus = "",
}

local function drawStatus()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("MusicCraft Radio Receiver")
  print("=========================")
  print("Name:      " .. HOSTNAME)
  print("ID:        " .. os.getComputerID())
  print("Modem:     " .. tostring(modemName))
  print("Protocol:  " .. RADIO_PROTOCOL)
  print("Listening: " .. tostring(config.listening))
  print("Volume:    " .. tostring(config.volume))
  print("Prebuffer: " .. tostring(config.prebufferChunks))
  print("Buffer:    " .. tostring(#state.buffer) .. " / " .. tostring(config.maxBufferChunks))
  print("Receiving: " .. tostring(state.receiving))
  print("Playing:   " .. tostring(state.playing))
  print("Title:     " .. tostring(state.title or "-"))
  print("Stream:    " .. tostring(state.streamId or "-"))
  print("Received:  " .. tostring(state.chunksReceived))
  print("Played:    " .. tostring(state.chunksPlayed))
  print("Underruns: " .. tostring(state.underruns))
  print()
  print("Keys: b listen | +/- volume | [/] prebuffer | s stop | q quit")
  print()
  print(state.lastStatus or "")
end

local function resetStream(msg, senderId)
  speaker.stop()

  state.streamId = msg.streamId
  state.title = msg.title or "Unknown Stream"
  state.decoder = dfpwm.make_decoder()
  state.buffer = {}
  state.expectedSeq = 1
  state.receiving = true
  state.playing = false
  state.ended = false
  state.underruns = 0
  state.chunksReceived = 0
  state.chunksPlayed = 0
  state.lastSender = senderId
  state.lastStatus = "Starting stream."

  drawStatus()
end

local function pushChunk(msg)
  if not config.listening then return end
  if not state.receiving then return end
  if msg.streamId ~= state.streamId then return end
  if type(msg.data) ~= "string" then return end

  if msg.seq ~= state.expectedSeq then
    state.lastStatus = "Out-of-order chunk. Expected " .. state.expectedSeq .. ", got " .. tostring(msg.seq)
    return
  end

  if #state.buffer >= config.maxBufferChunks then
    table.remove(state.buffer, 1)
    state.lastStatus = "Buffer full; dropped oldest chunk."
  end

  table.insert(state.buffer, msg.data)
  state.expectedSeq = state.expectedSeq + 1
  state.chunksReceived = state.chunksReceived + 1
end

local function stopStream(reason)
  speaker.stop()

  state.lastStatus = "Stream stopped: " .. tostring(reason or "unknown")
  state.receiving = false
  state.playing = false
  state.ended = true
  state.buffer = {}

  drawStatus()
end

local function radioLoop()
  while true do
    local senderId, msg, protocol = rednet.receive(RADIO_PROTOCOL)

    if protocol == RADIO_PROTOCOL and type(msg) == "table" and msg.mc == "musiccraft" and msg.version == 1 then
      if msg.type == "start" then
        if config.listening then resetStream(msg, senderId) end

      elseif msg.type == "audio" then
        pushChunk(msg)

      elseif msg.type == "end" then
        if msg.streamId == state.streamId then
          state.ended = true
          state.lastStatus = "End received from transmitter."
          drawStatus()
        end

      elseif msg.type == "stop" then
        if not msg.streamId or msg.streamId == state.streamId then
          stopStream("transmitter stop")
        end
      end
    end
  end
end

local function discoveryLoop()
  while true do
    local senderId, msg, protocol = rednet.receive(DISCOVERY_PROTOCOL)

    if protocol == DISCOVERY_PROTOCOL and type(msg) == "table" then
      if msg.mc == "musiccraft" and msg.version == 1 and msg.type == "discover_receivers" then
        rednet.send(senderId, {
          mc = "musiccraft",
          version = 1,
          type = "receiver_announce",
          name = HOSTNAME,
          label = os.getComputerLabel(),
          computerId = os.getComputerID(),
          speakerCount = speaker and 1 or 0,
          bufferDepth = #state.buffer,
          receiving = state.receiving,
          playing = state.playing,
          listening = config.listening,
          volume = config.volume,
          prebufferChunks = config.prebufferChunks,
        }, DISCOVERY_PROTOCOL)
      end
    end
  end
end

local function waitForSpeaker(buffer)
  while not speaker.playAudio(buffer, config.volume) do
    os.pullEvent("speaker_audio_empty")
  end
end

local function playbackLoop()
  local redrawCounter = 0

  while true do
    if state.receiving and not state.playing then
      if #state.buffer >= config.prebufferChunks then
        state.playing = true
        state.lastStatus = "Prebuffer complete. Starting playback."
        drawStatus()
      else
        sleep(0.05)
      end

    elseif state.receiving and state.playing then
      local chunk = table.remove(state.buffer, 1)

      if chunk then
        local decoded = state.decoder(chunk)
        waitForSpeaker(decoded)
        state.chunksPlayed = state.chunksPlayed + 1

        redrawCounter = redrawCounter + 1
        if redrawCounter >= 10 then
          redrawCounter = 0
          drawStatus()
        end

      elseif state.ended then
        stopStream("stream ended")

      else
        state.underruns = state.underruns + 1
        state.lastStatus = "Buffer underrun #" .. state.underruns
        state.playing = false
        drawStatus()
        sleep(0.1)
      end

    else
      sleep(0.1)
    end
  end
end

local function inputLoop()
  while true do
    local e, key = os.pullEvent("key")

    if key == keys.q then
      speaker.stop()
      saveConfig()
      term.clear()
      term.setCursorPos(1, 1)
      print("Receiver stopped.")
      return

    elseif key == keys.b then
      config.listening = not config.listening
      if not config.listening then stopStream("receiver left broadcast") end
      saveConfig()
      drawStatus()

    elseif key == keys.s then
      stopStream("local stop")

    elseif key == keys.equals or key == keys.numPadAdd then
      config.volume = math.min(1.0, math.floor((config.volume + 0.1) * 10 + 0.5) / 10)
      saveConfig()
      drawStatus()

    elseif key == keys.minus or key == keys.numPadSubtract then
      config.volume = math.max(0.0, math.floor((config.volume - 0.1) * 10 + 0.5) / 10)
      saveConfig()
      drawStatus()

    elseif key == keys.leftBracket then
      config.prebufferChunks = math.max(1, config.prebufferChunks - 1)
      saveConfig()
      drawStatus()

    elseif key == keys.rightBracket then
      config.prebufferChunks = math.min(32, config.prebufferChunks + 1)
      saveConfig()
      drawStatus()
    end
  end
end

drawStatus()
parallel.waitForAny(radioLoop, discoveryLoop, playbackLoop, inputLoop)

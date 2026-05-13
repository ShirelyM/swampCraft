-- VERIFY_MARKER: MC_RADIO_RX_V13_CONTINUOUS_SESSION
-- MusicCraft Radio Receiver v13
-- CC:Tweaked / ATM10 / Continuous Broadcast DFPWM Receiver

local RADIO_PROTOCOL = "musiccraft.radio.v1"
local ROLE_PREFIX = "musiccraft-rx"
local CONFIG_PATH = "musiccraft_receiver.cfg"
local RADIO_SEQ_MAX = 65535

local DEFAULT_CONFIG = {
  volume = 1.0,
  prebufferChunks = 12,
  maxBufferChunks = 160,
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
    if ok and type(data) == "table" then return copyDefaults(data, DEFAULT_CONFIG) end
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

  error("No attached wireless modem found.")
end

local function ensureComputerLabel()
  local label = os.getComputerLabel()
  if label and label ~= "" then return sanitizeName(label) end

  local generated = ROLE_PREFIX .. "-" .. tostring(os.getComputerID())
  os.setComputerLabel(generated)
  return generated
end

local function claimUniqueHostname()
  local baseName = ensureComputerLabel()
  if not baseName:find("^" .. ROLE_PREFIX) then baseName = ROLE_PREFIX .. "-" .. baseName end

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
if not speaker then error("No attached speaker found.") end

local modemName = openWirelessModem()
local HOSTNAME = claimUniqueHostname()

local state = {
  sessionId = nil,
  title = nil,
  album = nil,
  artist = nil,
  queuePos = nil,
  queueLen = nil,
  trackIndex = nil,

  decoder = nil,
  buffer = {},
  expectedSeq = nil,
  seqMax = RADIO_SEQ_MAX,

  receiving = false,
  playing = false,

  underruns = 0,
  chunksReceived = 0,
  chunksPlayed = 0,
  chunksDropped = 0,
  outOfOrder = 0,

  lastStatus = "Idle.",
}

local function seqNext(seq)
  return (seq % state.seqMax) + 1
end

local function seqDistanceForward(fromSeq, toSeq)
  if not fromSeq or not toSeq then return nil end
  local maxSeq = state.seqMax or RADIO_SEQ_MAX
  if toSeq >= fromSeq then return toSeq - fromSeq end
  return (maxSeq - fromSeq) + toSeq
end

local function isSeqOlder(seq, expected)
  if not seq or not expected then return false end
  local maxSeq = state.seqMax or RADIO_SEQ_MAX
  local forward = seqDistanceForward(expected, seq)
  if forward == 0 then return false end
  return forward > (maxSeq / 2)
end

local function drawStatus()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("MusicCraft Radio Receiver v13")
  print("==============================")
  print("Name:       " .. HOSTNAME)
  print("ID:         " .. os.getComputerID())
  print("Modem:      " .. tostring(modemName))
  print("Listening:  " .. tostring(config.listening))
  print("Volume:     " .. tostring(config.volume))
  print("Prebuffer:  " .. tostring(config.prebufferChunks))
  print("Max Buffer: " .. tostring(config.maxBufferChunks))
  print("Buffer:     " .. tostring(#state.buffer))
  print("Receiving:  " .. tostring(state.receiving))
  print("Playing:    " .. tostring(state.playing))
  print("Title:      " .. tostring(state.title or "-"))
  print("Artist:     " .. tostring(state.artist or "-"))
  print("Album:      " .. tostring(state.album or "-"))
  print("Queue:      " .. tostring(state.queuePos or "-") .. "/" .. tostring(state.queueLen or "-"))
  print("Session:    " .. tostring(state.sessionId or "-"))
  print("Expected:   " .. tostring(state.expectedSeq or "-"))
  print("Received:   " .. tostring(state.chunksReceived))
  print("Played:     " .. tostring(state.chunksPlayed))
  print("Dropped:    " .. tostring(state.chunksDropped))
  print("OutOrder:   " .. tostring(state.outOfOrder))
  print("Underruns:  " .. tostring(state.underruns))
  print()
  print("Keys: b listen | +/- vol | [/] prebuf | {/} maxbuf | s stop | q quit")
  print()
  print(state.lastStatus or "")
end

local function hardResetSession(sessionId, startSeq, reason)
  pcall(function() speaker.stop() end)

  state.sessionId = sessionId
  state.decoder = dfpwm.make_decoder()
  state.buffer = {}
  state.expectedSeq = tonumber(startSeq or 1) or 1

  state.receiving = true
  state.playing = false

  state.underruns = 0
  state.chunksReceived = 0
  state.chunksPlayed = 0
  state.chunksDropped = 0
  state.outOfOrder = 0

  state.lastStatus = reason or ("Joined session at seq " .. tostring(state.expectedSeq) .. ".")
  drawStatus()
end

local function stopSession(reason)
  pcall(function() speaker.stop() end)

  state.receiving = false
  state.playing = false
  state.buffer = {}
  state.expectedSeq = nil
  state.decoder = nil
  state.sessionId = nil
  state.lastStatus = "Stopped: " .. tostring(reason or "unknown")

  drawStatus()
end

local function updateMetadata(msg)
  state.title = msg.title or state.title
  state.album = msg.album or state.album
  state.artist = msg.artist or state.artist
  state.queuePos = msg.queuePos or state.queuePos
  state.queueLen = msg.queueLen or state.queueLen
  state.trackIndex = msg.trackIndex or state.trackIndex
end

local function handleSessionStart(msg)
  if not config.listening then return end
  if not msg.sessionId then return end

  state.seqMax = tonumber(msg.seqMax or RADIO_SEQ_MAX) or RADIO_SEQ_MAX

  if state.sessionId ~= msg.sessionId or not state.receiving or not state.decoder then
    hardResetSession(msg.sessionId, tonumber(msg.seq or 1) or 1, "New broadcast session.")
  else
    state.lastStatus = "Session heartbeat/start refreshed."
    drawStatus()
  end
end

local function handleMetadata(msg)
  if not config.listening then return end
  if not msg.sessionId then return end

  state.seqMax = tonumber(msg.seqMax or state.seqMax or RADIO_SEQ_MAX) or RADIO_SEQ_MAX

  if state.sessionId ~= msg.sessionId then
    -- Metadata is side-band. It can identify the current station/session, but it
    -- should not reset decoder or playback unless this is clearly a new session.
    hardResetSession(msg.sessionId, 1, "Metadata for new session; waiting for audio.")
  end

  updateMetadata(msg)
  drawStatus()
end

local function handleAudio(msg)
  if not config.listening then return end
  if not msg.sessionId then return end
  if type(msg.data) ~= "string" then return end

  local seq = tonumber(msg.seq)
  if not seq then return end

  state.seqMax = tonumber(msg.seqMax or state.seqMax or RADIO_SEQ_MAX) or RADIO_SEQ_MAX

  if state.sessionId ~= msg.sessionId or not state.receiving or not state.decoder then
    hardResetSession(msg.sessionId, seq, "Late-joined broadcast at seq " .. tostring(seq) .. ".")
  end

  if not state.expectedSeq then state.expectedSeq = seq end

  if seq ~= state.expectedSeq then
    if isSeqOlder(seq, state.expectedSeq) then
      state.chunksDropped = state.chunksDropped + 1
      state.lastStatus = "Dropped old/out-of-window seq " .. tostring(seq) .. "."
      return
    else
      local missed = seqDistanceForward(state.expectedSeq, seq) or 0
      if missed > 0 then
        state.outOfOrder = state.outOfOrder + 1
        state.chunksDropped = state.chunksDropped + missed
      end
      state.expectedSeq = seq
      state.lastStatus = "Skipped forward to seq " .. tostring(seq) .. "."
    end
  end

  if #state.buffer >= config.maxBufferChunks then
    table.remove(state.buffer, 1)
    state.chunksDropped = state.chunksDropped + 1
    state.lastStatus = "Buffer full; dropped oldest chunk."
  end

  table.insert(state.buffer, msg.data)
  state.expectedSeq = seqNext(seq)
  state.chunksReceived = state.chunksReceived + 1
end

local function radioLoop()
  while true do
    local senderId, msg, protocol = rednet.receive(RADIO_PROTOCOL)

    if protocol == RADIO_PROTOCOL and type(msg) == "table" and msg.mc == "musiccraft" and msg.version == 1 then
      if msg.type == "session_start" then
        handleSessionStart(msg)

      elseif msg.type == "metadata" then
        handleMetadata(msg)

      elseif msg.type == "audio" then
        handleAudio(msg)

      elseif msg.type == "heartbeat" then
        if msg.sessionId == state.sessionId then
          state.lastStatus = "Heartbeat received."
        end

      elseif msg.type == "stop" then
        if not msg.sessionId or msg.sessionId == state.sessionId then
          stopSession(msg.reason or "transmitter stop")
        end
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
        state.lastStatus = "Prebuffer complete. Playing."
        drawStatus()
      else
        sleep(0.03)
      end

    elseif state.receiving and state.playing then
      local chunk = table.remove(state.buffer, 1)

      if chunk then
        local decoded = state.decoder(chunk)
        waitForSpeaker(decoded)
        state.chunksPlayed = state.chunksPlayed + 1

        redrawCounter = redrawCounter + 1
        if redrawCounter >= 8 then
          redrawCounter = 0
          drawStatus()
        end
      else
        state.underruns = state.underruns + 1
        state.playing = false
        state.lastStatus = "Playback starvation #" .. tostring(state.underruns) .. ". Rebuffering."
        drawStatus()
        sleep(0.05)
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
      pcall(function() speaker.stop() end)
      saveConfig()
      term.clear()
      term.setCursorPos(1, 1)
      print("Receiver stopped.")
      return

    elseif key == keys.b then
      config.listening = not config.listening
      if not config.listening then stopSession("receiver left broadcast") end
      saveConfig()
      drawStatus()

    elseif key == keys.s then
      stopSession("local stop")

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
      config.prebufferChunks = math.min(64, config.prebufferChunks + 1)
      saveConfig()
      drawStatus()

    elseif key == keys.leftBrace then
      config.maxBufferChunks = math.max(32, config.maxBufferChunks - 16)
      saveConfig()
      drawStatus()

    elseif key == keys.rightBrace then
      config.maxBufferChunks = math.min(512, config.maxBufferChunks + 16)
      saveConfig()
      drawStatus()
    end
  end
end

drawStatus()
parallel.waitForAny(radioLoop, playbackLoop, inputLoop)

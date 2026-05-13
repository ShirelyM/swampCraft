-- VERIFY_MARKER: MC_RADIO_RX_V14_MULTI_SPEAKER_MONITOR
-- MusicCraft Radio Receiver v14
-- CC:Tweaked / ATM10 / Continuous Broadcast DFPWM Receiver
-- Adds wired-network multi-speaker playback and optional monitor Now Playing UI.

local RADIO_PROTOCOL = "musiccraft.radio.v1"
local ROLE_PREFIX = "musiccraft-rx"
local CONFIG_PATH = "musiccraft_receiver.cfg"
local RADIO_SEQ_MAX = 65535

local DEFAULT_CONFIG = {
  volume = 1.0,
  prebufferChunks = 12,
  maxBufferChunks = 160,
  listening = true,
  autoRefreshSpeakers = true,
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

local modemName = openWirelessModem()
local HOSTNAME = claimUniqueHostname()

local mon = peripheral.find("monitor")
if mon then mon.setTextScale(1) end

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

  speakers = {},
  speakerNames = {},
  speakerCount = 0,
  lastSpeakerRefresh = 0,

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

local function trim(s, n)
  s = tostring(s or "")
  if n <= 0 then return "" end
  if #s <= n then return s end
  if n <= 3 then return s:sub(1, n) end
  return s:sub(1, n - 3) .. "..."
end

local function refreshSpeakers(force)
  local now = os.clock()
  if not force and now - state.lastSpeakerRefresh < 2 then return end

  state.lastSpeakerRefresh = now
  state.speakers = {}
  state.speakerNames = {}

  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "speaker" then
      local wrapped = peripheral.wrap(name)
      if wrapped then
        table.insert(state.speakers, wrapped)
        table.insert(state.speakerNames, name)
      end
    end
  end

  state.speakerCount = #state.speakers
end

local function stopSpeakers()
  refreshSpeakers(true)
  for _, s in ipairs(state.speakers) do
    pcall(function() s.stop() end)
  end
end

local function writeTermLine(label, value)
  print(label .. tostring(value))
end

local function drawMonitor()
  if not mon then return end

  local w, h = mon.getSize()
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
  mon.clear()

  local function writeAt(x, y, text, fg, bg)
    if y < 1 or y > h then return end
    mon.setCursorPos(x, y)
    mon.setTextColor(fg or colors.white)
    mon.setBackgroundColor(bg or colors.black)
    mon.write(trim(text, math.max(0, w - x + 1)))
  end

  local function fill(y, bg)
    if y < 1 or y > h then return end
    mon.setCursorPos(1, y)
    mon.setBackgroundColor(bg)
    mon.write(string.rep(" ", w))
  end

  fill(1, colors.blue)
  writeAt(2, 1, "MusicCraft Radio", colors.white, colors.blue)

  local status = "Idle"
  if not config.listening then
    status = "Muted / Not Listening"
  elseif state.playing then
    status = "Playing"
  elseif state.receiving then
    status = "Buffering"
  end

  writeAt(2, 3, "Status:  " .. status, colors.lime)
  writeAt(2, 4, "Artist:  " .. tostring(state.artist or "-"))
  writeAt(2, 5, "Album:   " .. tostring(state.album or "-"))
  writeAt(2, 6, "Song:    " .. tostring(state.title or "-"), colors.yellow)

  if h >= 9 then
    writeAt(2, 8, "Speakers: " .. tostring(state.speakerCount) .. "  Buffer: " .. tostring(#state.buffer))
    writeAt(2, 9, "Volume:   " .. tostring(config.volume))
  end

  if h >= 11 then
    writeAt(2, 11, "Queue:    " .. tostring(state.queuePos or "-") .. "/" .. tostring(state.queueLen or "-"))
  end

  if h >= 13 then
    writeAt(2, 13, "Session:  " .. tostring(state.sessionId or "-"))
  end

  if h >= 15 then
    writeAt(2, 15, trim(state.lastStatus or "", w - 2), colors.lightGray)
  end
end

local function drawStatus()
  refreshSpeakers(false)

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)

  print("MusicCraft Radio Receiver v14")
  print("==============================")
  writeTermLine("Name:       ", HOSTNAME)
  writeTermLine("ID:         ", os.getComputerID())
  writeTermLine("Modem:      ", modemName)
  writeTermLine("Listening:  ", config.listening)
  writeTermLine("Volume:     ", config.volume)
  writeTermLine("Prebuffer:  ", config.prebufferChunks)
  writeTermLine("Max Buffer: ", config.maxBufferChunks)
  writeTermLine("Speakers:   ", state.speakerCount)
  writeTermLine("Buffer:     ", #state.buffer)
  writeTermLine("Receiving:  ", state.receiving)
  writeTermLine("Playing:    ", state.playing)
  writeTermLine("Title:      ", state.title or "-")
  writeTermLine("Artist:     ", state.artist or "-")
  writeTermLine("Album:      ", state.album or "-")
  writeTermLine("Queue:      ", tostring(state.queuePos or "-") .. "/" .. tostring(state.queueLen or "-"))
  writeTermLine("Session:    ", state.sessionId or "-")
  writeTermLine("Expected:   ", state.expectedSeq or "-")
  writeTermLine("Received:   ", state.chunksReceived)
  writeTermLine("Played:     ", state.chunksPlayed)
  writeTermLine("Dropped:    ", state.chunksDropped)
  writeTermLine("OutOrder:   ", state.outOfOrder)
  writeTermLine("Underruns:  ", state.underruns)
  print()
  print("Keys: b listen | +/- vol | [/] prebuf | {/} maxbuf | a auto-speakers | s stop | q quit")
  print()
  print(state.lastStatus or "")

  drawMonitor()
end

local function hardResetSession(sessionId, startSeq, reason)
  stopSpeakers()

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
  stopSpeakers()

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

local function waitForAllSpeakers(buffer)
  refreshSpeakers(false)

  if state.speakerCount == 0 then
    state.lastStatus = "No speakers found. Connect local or wired-network speakers."
    drawStatus()
    sleep(0.5)
    return false
  end

  local pending = {}
  for i = 1, #state.speakers do pending[i] = true end

  while true do
    local waiting = false
    local playedAny = false

    for i, speaker in ipairs(state.speakers) do
      if pending[i] then
        local ok = false
        pcall(function()
          ok = speaker.playAudio(buffer, config.volume)
        end)

        if ok then
          pending[i] = false
          playedAny = true
        else
          waiting = true
        end
      end
    end

    if not waiting then return true end

    -- If at least one speaker accepted the buffer, allow the full speaker event
    -- cycle before trying the remaining speakers again.
    os.pullEvent("speaker_audio_empty")
    if config.autoRefreshSpeakers then refreshSpeakers(false) end
  end
end

local function playbackLoop()
  local redrawCounter = 0

  while true do
    if config.autoRefreshSpeakers then refreshSpeakers(false) end

    if state.receiving and not state.playing then
      if #state.buffer >= config.prebufferChunks then
        state.playing = true
        state.lastStatus = "Prebuffer complete. Playing to " .. tostring(state.speakerCount) .. " speaker(s)."
        drawStatus()
      else
        sleep(0.03)
      end

    elseif state.receiving and state.playing then
      local chunk = table.remove(state.buffer, 1)

      if chunk then
        local decoded = state.decoder(chunk)
        local ok = waitForAllSpeakers(decoded)
        if ok then state.chunksPlayed = state.chunksPlayed + 1 end

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
      stopSpeakers()
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

    elseif key == keys.a then
      config.autoRefreshSpeakers = not config.autoRefreshSpeakers
      refreshSpeakers(true)
      saveConfig()
      drawStatus()

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

refreshSpeakers(true)
drawStatus()
parallel.waitForAny(radioLoop, playbackLoop, inputLoop)

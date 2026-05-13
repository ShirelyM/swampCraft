-- VERIFY_MARKER: MC_RADIO_TX_V13_CONTINUOUS_SESSION
-- MusicCraft Media Center v13 Broadcast TX
-- CC:Tweaked / ATM10 / Streaming DFPWM / Monitor GUI / Broadcast Radio Transmitter

local MASTER_CODEX_URL = "https://raw.githubusercontent.com/ShirelyM/swampCraft/refs/heads/dev/musicCraft/music/masterCodex.csv"

local STREAM_CHUNK_SIZE = 8 * 1024
local RADIO_SEQ_MAX = 65535
local RADIO_METADATA_EVERY_CHUNKS = 24

local DEFAULT_VOLUME_LEVEL = 5
local MIN_VOLUME_LEVEL = 1
local MAX_VOLUME_LEVEL = 10

local LOOP_OFF = "Off"
local LOOP_SONG = "Song"
local LOOP_QUEUE = "Queue"


local RADIO_PROTOCOL = "musiccraft.radio.v1"

local dfpwm = require("cc.audio.dfpwm")

local mon = peripheral.find("monitor")
local display = mon or term

if mon then mon.setTextScale(1) end

local state = {
  library = { artists = {}, albumsByArtist = {}, albums = {} },
  speakers = {},
  buttons = {},
  itemButtons = {},

  view = "artists",
  selectedArtist = nil,
  selectedAlbum = nil,

  currentAlbum = nil,
  currentIndex = nil,
  currentTrack = nil,

  queue = {},
  queuePos = 0,

  playing = false,
  paused = false,
  stopRequested = false,
  quit = false,

  scroll = 1,

  command = nil,
  commandId = 0,

  volumeLevel = DEFAULT_VOLUME_LEVEL,
  shuffleOn = false,
  loopMode = LOOP_OFF,
  radioEnabled = false,

  bytesRead = 0,
  totalBytes = nil,

  wirelessOpen = false,
  radioSessionId = nil,
  radioSeq = 1,

  status = "",

  lastTouchTime = 0,
  lastTouchX = nil,
  lastTouchY = nil
}

local C = {
  bg = colors.gray,
  bg2 = colors.lightGray,
  borderOuter = colors.yellow,
  borderInner = colors.black,
  text = colors.white,
  textDark = colors.black,
  accent = colors.lime,
  selected = colors.cyan,
  danger = colors.red,
  button = colors.lightGray,
  play = colors.green,
  pause = colors.orange,
  active = colors.cyan,
  progressBg = colors.black,
  progressNormal = colors.green,
  progressPaused = colors.yellow,
  progressShuffle = colors.cyan,
  progressLoop = colors.orange,
  broadcast = colors.purple
}

local function speakerVolume()
  return state.volumeLevel / 10
end

local function clear()
  display.setBackgroundColor(C.bg)
  display.setTextColor(C.text)
  display.clear()
  display.setCursorPos(1, 1)
end

local function writeAt(x, y, text, fg, bg)
  display.setCursorPos(x, y)
  display.setTextColor(fg or C.text)
  display.setBackgroundColor(bg or C.bg)
  display.write(text)
end

local function fill(x, y, w, h, bg)
  display.setBackgroundColor(bg)
  for yy = y, y + h - 1 do
    display.setCursorPos(x, yy)
    display.write(string.rep(" ", math.max(0, w)))
  end
end

local function trim(s, n)
  s = tostring(s or "")
  if n <= 3 then return s:sub(1, n) end
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

local function urlEncodePathPart(s)
  s = tostring(s or "")
  return s:gsub("([^%w%-_%.~/])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function splitCsvLine(line)
  local out, cur, quoted = {}, "", false

  for i = 1, #line do
    local c = line:sub(i, i)
    if c == "\"" then
      quoted = not quoted
    elseif c == "," and not quoted then
      table.insert(out, cur)
      cur = ""
    else
      cur = cur .. c
    end
  end

  table.insert(out, cur)
  return out
end

local function httpReadText(url)
  local r, err = http.get(url)
  if not r then error("HTTP failed: " .. tostring(err)) end
  local text = r.readAll()
  r.close()
  return text
end

local function refreshSpeakers()
  state.speakers = { peripheral.find("speaker") }
end

local function stopSpeakers()
  for _, s in ipairs(state.speakers) do
    pcall(function() s.stop() end)
  end
end

local function openWirelessModem()
  if state.wirelessOpen then return true end

  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      local modem = peripheral.wrap(name)
      if modem and modem.isWireless and modem.isWireless() then
        if not rednet.isOpen(name) then rednet.open(name) end
        state.wirelessOpen = true
        state.status = "Wireless modem open: " .. name
        return true
      end
    end
  end

  state.status = "No wireless modem found."
  return false
end

local function makeSessionId()
  local t = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
  return tostring(os.getComputerID()) .. "-" .. tostring(t)
end

local function radioBroadcast(msg)
  if not openWirelessModem() then return false end
  msg.mc = "musiccraft"
  msg.version = 1
  rednet.broadcast(msg, RADIO_PROTOCOL)
  return true
end

local function nextRadioSeq()
  local seq = state.radioSeq or 1
  state.radioSeq = (seq % RADIO_SEQ_MAX) + 1
  return seq
end

local function ensureRadioSession()
  if not state.radioEnabled then return false end
  if not openWirelessModem() then return false end

  if not state.radioSessionId then
    state.radioSessionId = makeSessionId()
    state.radioSeq = 1
    radioBroadcast({
      type = "session_start",
      sessionId = state.radioSessionId,
      seq = state.radioSeq,
      chunkSize = STREAM_CHUNK_SIZE,
      seqMax = RADIO_SEQ_MAX
    })
  end

  return true
end

local function radioStop(reason)
  if state.radioSessionId then
    radioBroadcast({ type = "stop", sessionId = state.radioSessionId, reason = reason or "user_stop" })
  else
    radioBroadcast({ type = "stop", reason = reason or "user_stop" })
  end
  state.radioSessionId = nil
  state.radioSeq = 1
end

local function radioSendMetadata(item)
  if not item or not ensureRadioSession() then return end

  radioBroadcast({
    type = "metadata",
    sessionId = state.radioSessionId,
    title = item.track.title,
    album = item.album.album,
    artist = item.album.artist,
    queuePos = state.queuePos,
    queueLen = #state.queue,
    trackIndex = item.index,
    chunkSize = STREAM_CHUNK_SIZE,
    seqMax = RADIO_SEQ_MAX
  })
end

local function radioSendAudio(chunk)
  if not chunk or not ensureRadioSession() then return end

  local seq = nextRadioSeq()
  radioBroadcast({
    type = "audio",
    sessionId = state.radioSessionId,
    seq = seq,
    data = chunk,
    chunkSize = STREAM_CHUNK_SIZE,
    seqMax = RADIO_SEQ_MAX
  })
end

local function loadAlbumTracks(albumRecord)
  if albumRecord.tracks then return albumRecord.tracks end

  local text = httpReadText(albumRecord.codexUrl)
  local lines = {}

  for line in text:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  local folderLink = ""
  if lines[2] then
    local meta = splitCsvLine(lines[2])
    folderLink = meta[3] or ""
  end

  local tracks = {}
  local inTracks = false

  for _, line in ipairs(lines) do
    local cols = splitCsvLine(line)

    if cols[1] == "trackNumber" then
      inTracks = true
    elseif inTracks and cols[1] and cols[1] ~= "" then
      local track = {
        trackNumber = tonumber(cols[1]) or #tracks + 1,
        title = cols[2] or ("Track " .. tostring(#tracks + 1)),
        fileName = cols[3] or "",
        album = albumRecord
      }

      track.url = folderLink .. urlEncodePathPart(track.fileName)
      table.insert(tracks, track)
    end
  end

  table.sort(tracks, function(a, b) return a.trackNumber < b.trackNumber end)
  albumRecord.tracks = tracks
  return tracks
end

local function loadMasterCodex()
  local text = httpReadText(MASTER_CODEX_URL)
  local library = { artists = {}, albumsByArtist = {}, albums = {} }
  local seenArtists = {}
  local firstRow = true

  for line in text:gmatch("[^\r\n]+") do
    local cols = splitCsvLine(line)
    local artist = cols[1]
    local album = cols[2]
    local codexUrl = cols[3]
    local isHeader = firstRow and artist and artist:lower():find("artist")
    firstRow = false

    if not isHeader and artist and album and codexUrl and artist ~= "" and album ~= "" and codexUrl ~= "" then
      local record = { artist = artist, album = album, codexUrl = codexUrl, tracks = nil }
      table.insert(library.albums, record)

      if not seenArtists[artist] then
        seenArtists[artist] = true
        table.insert(library.artists, artist)
        library.albumsByArtist[artist] = {}
      end

      table.insert(library.albumsByArtist[artist], record)
    end
  end

  table.sort(library.artists)
  for _, artist in ipairs(library.artists) do
    table.sort(library.albumsByArtist[artist], function(a, b) return a.album < b.album end)
  end

  return library
end

local function inside(b, x, y)
  return b and x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h
end

local function drawButton(id, x, y, w, label, bg, fg)
  bg = bg or C.button
  fg = fg or C.textDark
  label = trim(label, w)

  local padLeft = math.floor((w - #label) / 2)
  local padRight = w - #label - padLeft
  local text = string.rep(" ", math.max(0, padLeft)) .. label .. string.rep(" ", math.max(0, padRight))

  writeAt(x, y, text, fg, bg)
  state.buttons[id] = { x = x, y = y, w = w, h = 1 }
end

local function drawFrame()
  local w, h = display.getSize()

  clear()

  fill(1, 1, w, 1, C.borderOuter)
  fill(1, h, w, 1, C.borderOuter)
  fill(1, 1, 1, h, C.borderOuter)
  fill(w, 1, 1, h, C.borderOuter)

  fill(2, 2, w - 2, 1, C.borderInner)
  fill(2, h - 1, w - 2, 1, C.borderInner)
  fill(2, 2, 1, h - 2, C.borderInner)
  fill(w - 1, 2, 1, h - 2, C.borderInner)

  local title = " MusicCraft Media Center "
  writeAt(math.floor((w - #title) / 2), 1, title, C.borderOuter, C.borderInner)
end

local function getVisibleList()
  if state.view == "artists" then
    return state.library.artists
  elseif state.view == "albums" then
    return state.library.albumsByArtist[state.selectedArtist] or {}
  elseif state.view == "songs" and state.selectedAlbum then
    return loadAlbumTracks(state.selectedAlbum)
  end

  return {}
end

local function getHeader()
  if state.view == "artists" then
    return "Artists"
  elseif state.view == "albums" then
    return state.selectedArtist or "Albums"
  elseif state.view == "songs" and state.selectedAlbum then
    return state.selectedAlbum.artist .. " > " .. state.selectedAlbum.album
  end

  return "Library"
end

local function progressColor()
  if state.radioEnabled then
    return C.broadcast
  elseif state.paused then
    return C.progressPaused
  elseif state.shuffleOn then
    return C.progressShuffle
  elseif state.loopMode ~= LOOP_OFF then
    return C.progressLoop
  end

  return C.progressNormal
end

local function drawProgressBar(x, y, w)
  local pct = 0

  if state.totalBytes and state.totalBytes > 0 then
    pct = math.max(0, math.min(1, state.bytesRead / state.totalBytes))
  end

  local percentText = tostring(math.floor(pct * 100)) .. "%"
  local barW = math.max(5, w - 5)
  local filled = math.floor(barW * pct)

  fill(x, y, barW, 1, C.progressBg)
  if filled > 0 then fill(x, y, filled, 1, progressColor()) end
  writeAt(x + barW + 1, y, percentText, C.text, C.bg)
end

local function drawGui()
  local w, h = display.getSize()

  local panelW = 14
  local panelX = w - panelW
  local buttonX = panelX + 1

  local listX, listY = 4, 5
  local listW = panelX - listX - 2
  local listH = h - 12

  state.buttons = {}
  state.itemButtons = {}

  drawFrame()
  writeAt(4, 3, trim(getHeader(), listW), C.accent, C.bg)

  fill(panelX - 1, 2, 1, h - 3, C.borderInner)

  local ppLabel = ">"
  local ppColor = C.play
  if state.playing and not state.paused then
    ppLabel = "||"
    ppColor = C.pause
  end

  drawButton("previous", buttonX, 4, 2, "<<", C.button)
  drawButton("play_pause", buttonX + 3, 4, 2, ppLabel, ppColor, C.textDark)
  drawButton("stop", buttonX + 7, 4, 2, "[]", C.danger, C.text)
  drawButton("next", buttonX + 10, 4, 2, ">>", C.button)

  drawButton("radio", buttonX, 6, 12, "Radio:" .. (state.radioEnabled and "On" or "Off"), state.radioEnabled and C.broadcast or C.button, state.radioEnabled and C.text or C.textDark)
  drawButton("shuffle", buttonX, 8, 12, "Shuffle", state.shuffleOn and C.active or C.button)
  drawButton("loop", buttonX, 10, 12, "Loop: " .. state.loopMode, state.loopMode ~= LOOP_OFF and C.active or C.button)

  drawButton("vol_down", buttonX, 12, 2, "-", C.button)
  drawButton("vol_mid", buttonX + 4, 12, 4, tostring(state.volumeLevel), C.button)
  drawButton("vol_up", buttonX + 10, 12, 2, "+", C.button)

  drawButton("up", buttonX, 14, 4, "Up", C.button)
  drawButton("down", buttonX + 8, 14, 4, "Dn", C.button)

  if state.view ~= "artists" then
    drawButton("back", buttonX, h - 3, 12, "Back", C.button)
  end

  local list = getVisibleList()

  for row = 0, listH - 1 do
    local i = state.scroll + row
    local item = list[i]
    local y = listY + row

    if item then
      local bg = row % 2 == 0 and C.bg2 or C.bg
      local fg = row % 2 == 0 and C.textDark or C.text
      local text = ""

      if state.view == "artists" then
        text = item
      elseif state.view == "albums" then
        text = item.album
      elseif state.view == "songs" then
        text = item.trackNumber .. ". " .. item.title

        if state.currentAlbum == state.selectedAlbum and i == state.currentIndex then
          bg, fg = C.selected, C.textDark
        end
      end

      fill(listX, y, listW, 1, bg)
      writeAt(listX + 1, y, trim(text, listW - 2), fg, bg)
      state.itemButtons[i] = { x = listX, y = y, w = listW, h = 1 }
    end
  end

  local now = "Now Playing: " .. (state.currentTrack and state.currentTrack.title or "Nothing")
  writeAt(4, h - 6, trim(now, listW), C.text, C.bg)
  writeAt(4, h - 5, trim("Status: " .. tostring(state.status or ""), listW), C.text, C.bg)
  drawProgressBar(4, h - 4, listW)
end

local function shuffleList(list)
  local out = {}
  for i = 1, #list do out[i] = list[i] end

  for i = #out, 2, -1 do
    local j = math.random(i)
    out[i], out[j] = out[j], out[i]
  end

  return out
end

local function addAlbumToQueue(queue, albumRecord)
  local tracks = loadAlbumTracks(albumRecord)

  for i, track in ipairs(tracks) do
    table.insert(queue, { album = albumRecord, index = i, track = track })
  end
end

local function buildQueueFromContext(startIndex, shuffled)
  local queue = {}

  if state.view == "songs" and state.selectedAlbum then
    local tracks = loadAlbumTracks(state.selectedAlbum)

    for i = startIndex or 1, #tracks do
      table.insert(queue, { album = state.selectedAlbum, index = i, track = tracks[i] })
    end

  elseif state.view == "albums" and state.selectedArtist then
    local albums = state.library.albumsByArtist[state.selectedArtist] or {}
    for _, albumRecord in ipairs(albums) do addAlbumToQueue(queue, albumRecord) end

  elseif state.view == "artists" then
    for _, albumRecord in ipairs(state.library.albums) do addAlbumToQueue(queue, albumRecord) end

  elseif state.currentAlbum then
    local tracks = loadAlbumTracks(state.currentAlbum)
    for i = state.currentIndex or 1, #tracks do
      table.insert(queue, { album = state.currentAlbum, index = i, track = tracks[i] })
    end
  end

  if shuffled then queue = shuffleList(queue) end
  return queue
end

local function startQueue(queue, startPos)
  if #queue == 0 then return end

  state.commandId = state.commandId + 1
  state.command = { id = state.commandId, queue = queue, startPos = startPos or 1 }

  state.queue = queue
  state.queuePos = startPos or 1
  state.stopRequested = true
  state.paused = false
  state.bytesRead = 0
  state.totalBytes = nil

  stopSpeakers()
  -- Only send radio stop for user-directed restarts/skips; no artificial stop between natural tracks.
  drawGui()
end

local function requestContextPlay()
  if state.paused then
    state.paused = false
    drawGui()
    return
  end

  if state.playing then
    state.paused = true
    stopSpeakers()
    drawGui()
    return
  end

  local startIndex = 1
  if state.view == "songs" and state.selectedAlbum and state.currentAlbum == state.selectedAlbum and state.currentIndex then
    startIndex = state.currentIndex
  end

  startQueue(buildQueueFromContext(startIndex, state.shuffleOn), 1)
end

local function requestShuffle()
  state.shuffleOn = not state.shuffleOn
  if state.shuffleOn then
    startQueue(buildQueueFromContext(1, true), 1)
  else
    drawGui()
  end
end

local function cycleLoop()
  if state.loopMode == LOOP_OFF then
    state.loopMode = LOOP_SONG
  elseif state.loopMode == LOOP_SONG then
    state.loopMode = LOOP_QUEUE
  else
    state.loopMode = LOOP_OFF
  end

  drawGui()
end

local function toggleRadio()
  state.radioEnabled = not state.radioEnabled

  if state.radioEnabled then
    if ensureRadioSession() then
      if state.currentTrack and state.currentAlbum then
        radioSendMetadata({ album = state.currentAlbum, index = state.currentIndex or 0, track = state.currentTrack })
      end
      state.status = "Radio on; local playback remains active."
    else
      state.radioEnabled = false
      state.status = "Radio unavailable; no wireless modem."
    end
  else
    radioStop("radio_off")
    state.status = "Radio off; local playback continues."
  end

  drawGui()
end

local function requestNext()
  if #state.queue > 0 and state.queuePos < #state.queue then
    startQueue(state.queue, state.queuePos + 1)
  elseif state.currentAlbum and state.currentIndex then
    local tracks = loadAlbumTracks(state.currentAlbum)
    if state.currentIndex < #tracks then
      startQueue({ { album = state.currentAlbum, index = state.currentIndex + 1, track = tracks[state.currentIndex + 1] } }, 1)
    end
  end
end

local function requestPrevious()
  if #state.queue > 0 and state.queuePos > 1 then
    startQueue(state.queue, state.queuePos - 1)
  elseif state.currentAlbum and state.currentIndex and state.currentIndex > 1 then
    local tracks = loadAlbumTracks(state.currentAlbum)
    startQueue({ { album = state.currentAlbum, index = state.currentIndex - 1, track = tracks[state.currentIndex - 1] } }, 1)
  end
end

local function playBufferAll(buffer, commandId)
  local pending = {}
  for i = 1, #state.speakers do pending[i] = true end

  while true do
    if state.quit or state.stopRequested or state.commandId ~= commandId then return false end
    if state.paused then return false end

    local waiting = false

    for i, speaker in ipairs(state.speakers) do
      if pending[i] then
        if speaker.playAudio(buffer, speakerVolume()) then
          pending[i] = false
        else
          waiting = true
        end
      end
    end

    if not waiting then return true end
    os.pullEvent("speaker_audio_empty")
  end
end

local function getContentLength(response)
  if not response.getResponseHeaders then return nil end
  local headers = response.getResponseHeaders()
  if not headers then return nil end
  return tonumber(headers["Content-Length"] or headers["content-length"])
end

local function playQueueItemStream(response, item, commandId)
  local decoder = dfpwm.make_decoder()
  local chunksSinceMetadata = RADIO_METADATA_EVERY_CHUNKS

  while not state.quit and not state.stopRequested and state.commandId == commandId do
    if state.paused then
      sleep(0.1)
    else
      local chunk = response.read(STREAM_CHUNK_SIZE)
      if not chunk then break end

      state.bytesRead = state.bytesRead + #chunk

      if state.radioEnabled then
        if chunksSinceMetadata >= RADIO_METADATA_EVERY_CHUNKS then
          radioSendMetadata(item)
          chunksSinceMetadata = 0
        end
        radioSendAudio(chunk)
        chunksSinceMetadata = chunksSinceMetadata + 1
      end

      local ok = playBufferAll(decoder(chunk), commandId)

      if not ok then
        while state.paused and not state.quit and not state.stopRequested and state.commandId == commandId do sleep(0.1) end
        if state.stopRequested or state.quit or state.commandId ~= commandId then break end
      end
    end
  end
end

local function playQueueItem(item, commandId)
  refreshSpeakers()

  if #state.speakers == 0 then
    state.status = "No local speakers found."
    drawGui()
    sleep(1)
    return false
  end

  state.currentAlbum = item.album
  state.currentIndex = item.index
  state.currentTrack = item.track
  state.playing = true
  state.paused = false
  state.stopRequested = false
  state.bytesRead = 0
  state.totalBytes = nil
  state.status = state.radioEnabled and "Playing locally + broadcasting..." or "Playing locally..."

  drawGui()

  local response, err = http.get(item.track.url, nil, true)

  if not response then
    state.playing = false
    state.status = "HTTP failed: " .. tostring(err)
    drawGui()
    sleep(2)
    return false
  end

  state.totalBytes = getContentLength(response)
  local lastDrawPct = -1

  local function progressLoop()
    while not state.quit and not state.stopRequested and state.commandId == commandId and state.playing do
      if state.totalBytes and state.totalBytes > 0 then
        local pct = math.floor((state.bytesRead / state.totalBytes) * 100)
        if pct ~= lastDrawPct and pct % 2 == 0 then
          lastDrawPct = pct
          drawGui()
        end
      end
      sleep(0.25)
    end
  end

  radioSendMetadata(item)
  parallel.waitForAny(function() playQueueItemStream(response, item, commandId) end, progressLoop)

  response.close()
  state.playing = false

  if state.stopRequested or state.commandId ~= commandId then
    stopSpeakers()
  end

  drawGui()
  return not state.stopRequested and state.commandId == commandId and not state.quit
end

local function playerLoop()
  while not state.quit do
    if state.command then
      local cmd = state.command
      state.command = nil
      state.stopRequested = false
      local pos = cmd.startPos or 1

      while pos <= #cmd.queue and not state.quit and state.commandId == cmd.id do
        state.queue = cmd.queue
        state.queuePos = pos

        local completed = playQueueItem(cmd.queue[pos], cmd.id)
        if not completed then break end

        if state.loopMode == LOOP_SONG then
          -- stay on same queue position
        else
          pos = pos + 1
          if pos > #cmd.queue and state.loopMode == LOOP_QUEUE then pos = 1 end
        end
      end
    else
      sleep(0.1)
    end
  end
end

local function goBack()
  if state.view == "songs" then
    state.view = "albums"
    state.selectedAlbum = nil
    state.scroll = 1
  elseif state.view == "albums" then
    state.view = "artists"
    state.selectedArtist = nil
    state.scroll = 1
  end

  drawGui()
end

local function selectItem(index)
  local list = getVisibleList()
  local item = list[index]
  if not item then return end

  if state.view == "artists" then
    state.selectedArtist = item
    state.selectedAlbum = nil
    state.view = "albums"
    state.scroll = 1
    drawGui()

  elseif state.view == "albums" then
    state.selectedAlbum = item
    state.view = "songs"
    state.scroll = 1
    loadAlbumTracks(item)
    drawGui()

  elseif state.view == "songs" then
    startQueue(buildQueueFromContext(index, state.shuffleOn), 1)
  end
end

local function isTouchBounce(x, y)
  local now = os.clock()

  if state.lastTouchX == x and state.lastTouchY == y and now - state.lastTouchTime < 0.35 then return true end

  state.lastTouchX = x
  state.lastTouchY = y
  state.lastTouchTime = now
  return false
end

local function handleTouch(x, y)
  if isTouchBounce(x, y) then return end

  for id, b in pairs(state.buttons) do
    if inside(b, x, y) then
      if id == "play_pause" then
        requestContextPlay()

      elseif id == "stop" then
        state.command = nil
        state.stopRequested = true
        state.paused = false
        state.playing = false
        stopSpeakers()
        radioStop("user_stop")
        drawGui()

      elseif id == "next" then
        requestNext()

      elseif id == "previous" then
        requestPrevious()

      elseif id == "radio" then
        toggleRadio()

      elseif id == "shuffle" then
        requestShuffle()

      elseif id == "loop" then
        cycleLoop()

      elseif id == "vol_down" then
        state.volumeLevel = math.max(MIN_VOLUME_LEVEL, state.volumeLevel - 1)
        drawGui()

      elseif id == "vol_up" then
        state.volumeLevel = math.min(MAX_VOLUME_LEVEL, state.volumeLevel + 1)
        drawGui()

      elseif id == "back" then
        goBack()

      elseif id == "up" then
        if state.scroll > 1 then state.scroll = state.scroll - 1 end
        drawGui()

      elseif id == "down" then
        local list = getVisibleList()
        if state.scroll < #list then state.scroll = state.scroll + 1 end
        drawGui()
      end

      return
    end
  end

  for index, b in pairs(state.itemButtons) do
    if inside(b, x, y) then
      selectItem(index)
      return
    end
  end
end

local function uiLoop()
  while not state.quit do
    local e, p1, p2, p3 = os.pullEvent()

    if e == "monitor_touch" then
      handleTouch(p2, p3)

    elseif e == "char" then
      if p1 == "q" then
        state.quit = true
        state.stopRequested = true
        stopSpeakers()
        radioStop("quit")
        clear()

      elseif p1 == "p" then
        requestContextPlay()

      elseif p1 == "s" then
        state.command = nil
        state.stopRequested = true
        state.paused = false
        state.playing = false
        stopSpeakers()
        radioStop("user_stop")
        drawGui()

      elseif p1 == "n" then
        requestNext()

      elseif p1 == "r" then
        toggleRadio()

      elseif p1 == "b" then
        goBack()

      elseif p1 == "+" then
        state.volumeLevel = math.min(MAX_VOLUME_LEVEL, state.volumeLevel + 1)
        drawGui()

      elseif p1 == "-" then
        state.volumeLevel = math.max(MIN_VOLUME_LEVEL, state.volumeLevel - 1)
        drawGui()
      end
    end
  end
end

local function main()
  if not http then error("HTTP is disabled.") end

  math.randomseed(os.epoch and os.epoch("utc") or os.clock())

  refreshSpeakers()
  clear()
  writeAt(1, 1, "Loading master codex...", C.text, C.bg)

  state.library = loadMasterCodex()
  drawGui()

  parallel.waitForAny(uiLoop, playerLoop)
end

main()

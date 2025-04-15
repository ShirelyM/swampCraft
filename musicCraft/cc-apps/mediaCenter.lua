-- This hotness was developed by SwampDonkey. You are free to use at your leisure. 
-- If you have ideas for improvements, feel free to float them.
 
PLAYER_BANNER = "MusicCraft Media Center"
---------------------------------------------
BACKGROUND = colors.gray
BACKGROUND_ALT = colors.lightGray
OUTER_BORDER = colors.yellow
INNER_BORDER = colors.black
TEXT = colors.white
TEXT_ALT = colors.black
DISABLED_BUTTON = colors.lightGray
PLAY_BUTTON = colors.green
PAUSE_BUTTON = colors.red
---------------------------------------------
TAPE_DRIVE = "tape_drive"
SCREEN_TOUCH = "monitor_touch"
CHAR = "char"
---------------------------------------------
-- TODO - Get rid of this hard peripheral definition
mon = peripheral.wrap("right")
---------------------------------------------
perps = peripheral.getNames()
 
---------------------------------------------
ARTIST_VIEW = "artists"
ALBUM_VIEW = "albums"
SONG_VIEW = "songs"
---------------------------------------------
OUTER_BORDER_WIDTH = 1
INNER_BORDER_WIDTH = 1
BORDER_WIDTH = OUTER_BORDER_WIDTH + INNER_BORDER_WIDTH
CONTROL_PANEL_WIDTH = 9
CONTROL_WIDTH = CONTROL_PANEL_WIDTH + 2 * INNER_BORDER_WIDTH
---------------------------------------------
local mediaData = {} 
local buttons = {}
local viewerButtons = {}
local currentView = ARTIST_VIEW
local currentArtist = ""
local currentAlbum = ""
local currentSong = ""
local currentTapeDrive
 
 
xMax, yMax = mon.getSize()
---------------------------------------------
local viewHeight = yMax - BORDER_WIDTH * 2
local lineMax = xMax - (CONTROL_WIDTH + OUTER_BORDER_WIDTH)
local startIndex = 1
local lastIndex = 0
---------------------------------------------
-- TODO - Expand shell interface for media center, so it can also be used on tablet
term.setCursorPos(1,1)
term.clear()
print(PLAYER_BANNER.. "\n")
 
function checkDisplaySize()
  if xMax < 29 or yMax < 19 then
    print("The MusicCraft Media Center requires your monitor to be at least 3x3")
    exit()
  end
end
 
-- vertical Boolean. If true draws vertical line. If false draws horizontal line.
-- color             Color value for line background
-- length            Number of cells to draw the line through
function drawBorder(vertical, color, xStart, yStart, length)
  mon.setBackgroundColor(color)
  mon.setCursorPos(xStart, yStart)
  
  if vertical then
    local y = yStart
    for x = 1, length do
      mon.write(" ")
      mon.setCursorPos(xStart, y)
      y = y + 1
    end 
  else
    local borderString = ""
    for x = 1, length do
      borderString = borderString.. " "
    end 
    mon.write(borderString)
  end
end
 
-- Draw Media Center Frame
function drawOuterBorders()
  -- Draw outer border
  playerBanner = " ".. PLAYER_BANNER.. " "
  leftLength = math.floor((xMax - #playerBanner) / 2)
  rightLength = xMax - leftLength - #playerBanner
 
  drawBorder(false, OUTER_BORDER, 1, 1, leftLength)
  mon.setBackgroundColor(INNER_BORDER) -- TODO - Let these colors be customizable
  mon.setTextColor(OUTER_BORDER)
  mon.write(playerBanner)
 
  -- TODO - Can this be cleaned up?
  drawBorder(false, OUTER_BORDER, leftLength + #playerBanner + 1, 1, xMax)
  drawBorder(true, OUTER_BORDER, xMax, 1, yMax)
  drawBorder(true, OUTER_BORDER, 1, 1, yMax)
  drawBorder(false, OUTER_BORDER, 1, yMax, xMax)
end
 
function drawInnerBorders()
  -- Draw inner borders
  -- TODO - Can this be cleaned up?
  drawBorder(false, INNER_BORDER, 2, 2, xMax - 2)
  drawBorder(true, INNER_BORDER, xMax - 1, 2, yMax - 2)
  drawBorder(true, INNER_BORDER, 2, 2, yMax - 2)
  drawBorder(false, INNER_BORDER, 2, yMax - 1, xMax - 2)
  drawBorder(true, INNER_BORDER, xMax - 11, 2, yMax - 2)
  drawBorder(false, INNER_BORDER, xMax - 11, math.floor(yMax / 2) + 1, 10)
end
 
function drawBorders()
  mon.setBackgroundColor(BACKGROUND)
  mon.clear()
  drawOuterBorders()
  drawInnerBorders()
end
 
function drawButton(backgroundColor, textColor, text, xStart, yStart, length, method)
  mon.setBackgroundColor(backgroundColor)
  mon.setTextColor(textColor)
  mon.setCursorPos(xStart, yStart)
  
  if #text > length then
    print("Text: '".. text.. "' is longer than button length")
    io.read()
    exit()
  else
    local buttonText = ""
    local leftSpace = math.floor((length - #text) / 2)
    for x = 1, leftSpace do
      buttonText = buttonText.. " "
    end
    
    buttonText = buttonText.. text
    rightSpace = length - leftSpace - #text
    for x = 1, rightSpace do
      buttonText = buttonText.. " "
    end
    
    buttons[text] = {xStart, yStart, length, method}
    mon.write(buttonText)
  end
end
 
function createMediaData()
    for k, id in pairs(perps) do
        if peripheral.getType(id) == TAPE_DRIVE then
          a = peripheral.wrap(id)
          if a.getLabel() ~= nil then
            local albumData = {}
            local count = 1
            local artist
            local album
            for d in string.gmatch(a.getLabel(), "([^-]+)") do
              --if count == 1 then
              --  artist = string.gsub(d, "%s+", "")
              --else
              --  album = string.gsub(d, "%s+", "")
              --end
              if count == 1 then
                artist = d
              else
                album = d
              end
              count = count + 1
            end
            
            if mediaData[artist] == nil then
              mediaData[artist] = {}
            end
            mediaData[artist][album] = {id, createAlbumInfo(a)}
            
          end
        end
    end
end
 
function createAlbumInfo(tapeDrive)
    searchInfo = true
    local trackInfo = ""
     
    tapeDrive.seek(tapeDrive.getSize())
     
    -- Read Track Info from Tape
    local INFO_END = "%"
     
    -- TODO - Migrate this to a function
    while searchInfo do
      tapeDrive.seek(-1)
      ascii = tapeDrive.read(1)
      if ascii ~= INFO_END then
        trackInfo = trackInfo.. ascii
      else
        break
      end
      tapeDrive.seek(-1)
    end
     
    -- Create albumInfo array
    local albumInfo = {}
     
    for t in string.gmatch(trackInfo, "([^;]+)") do
      local trackInfo = {}
      for i in string.gmatch(t, "([^,]+)") do
        trackInfo[#trackInfo + 1] = i
      end
    albumInfo[#albumInfo + 1] = trackInfo
    end
    return albumInfo
end
 
function drawControlButtons(backgroundColor, textColor)
  drawButton(backgroundColor, textColor, ">", xMax - 8, 4 , 1, play)
  drawButton(backgroundColor, textColor, "||", xMax - 5, 4 , 2, pause)
  drawButton(backgroundColor, textColor, "Shuffle", xMax - 9, 6 , 7, shuffle)
  drawButton(backgroundColor, textColor, "Loop", xMax - 9, 8, 7, loop)
end
 
function drawSettingsButtons(backgroundColor, textColor)
  drawButton(backgroundColor, textColor, "<<<", xMax - 9, yMax - 7, 3, scrollUp)
  drawButton(backgroundColor, textColor, ">>>", xMax - 5, yMax - 7, 3, scrollDown)
  drawButton(backgroundColor, textColor, "Config", xMax - 9, yMax - 5, 7, config)
  drawButton(backgroundColor, textColor, "Back", xMax - 9, yMax - 3, 7, back)  
end
 
 
-- TODO - Alphabetize artists and document clickable area for selection
function drawViewer()
  viewerButtons = {}
  local xStart = 3
  local method, lineString
  local yValue = 3
  local lineCount = 1
  local alternate = false
 
  clearViewer() 
  if currentView == ARTIST_VIEW then
    array = mediaData
    method = drawViewer
  elseif currentView == ALBUM_VIEW then
    array = mediaData[currentArtist]
    method = drawViewer
  elseif currentView == SONG_VIEW then
    array = mediaData[currentArtist][currentAlbum][2]
    method = playSong
  else
    print("Invalid View Type")
  end
  
  lastIndex = #array
 
  local iteration = 1
  for k,v in pairs(array) do
    if lineCount <= viewHeight and iteration >= startIndex then
      if currentView == SONG_VIEW then
        lineString = " ".. v[1].. ". ".. v[2]
      else
        lineString = " ".. k
      end
      for x = xStart, lineMax - #lineString do
        lineString = lineString.. " "
      end
      mon.setCursorPos(3, yValue)
      if alternate then
         mon.setBackgroundColor(BACKGROUND)
         mon.setTextColor(TEXT)
         alternate = false
      else
        mon.setBackgroundColor(BACKGROUND_ALT)
        mon.setTextColor(TEXT_ALT)
        alternate = true
      end
      mon.write(lineString)
      if currentView == SONG_VIEW then
        viewerButtons[v[2]] = {3, yValue, lineMax, method}
      else
        viewerButtons[k] = {3, yValue, lineMax, method}
      end
      yValue = yValue + 1
      lineCount = lineCount + 1
    end
    iteration = iteration + 1
  end
end
 
function clearViewer()
  local yStart = 3
  local xStart = 3
  local yEnd = yMax - BORDER_WIDTH
  local lineClear = ""
  for x = xStart, lineMax,  1 do
    lineClear = lineClear.. " "
  end
 
  mon.setBackgroundColor(BACKGROUND)
  for y = yStart, yEnd do
    mon.setCursorPos(xStart, y)
    mon.write(lineClear)
  end
end
 
function seek()
  return
end
 
function play()
  if currentTapeDrive ~= nil then
    currentTapeDrive.play()
  end
end
 
function pause()
  for k, v in pairs(peripheral.getNames()) do
    if peripheral.getType(v) == TAPE_DRIVE then
      tape = peripheral.wrap(v)
      tape.stop()
    end
  end
end
 
function shuffle()
  print("Shuffle")
end
 
function shuffleAlbum()
  print("Shuffle Album")
end
 
function shuffleArtists()
  print("Shuffle Artists")
end
 
function shuffleAll()
  print("Shuffle All")
end
 
function loop()
  print("Loop")
end
 
function scrollUp()
  if startIndex > 1 then
    startIndex = startIndex - 1
    drawViewer()
  end
end
 
function scrollDown()
  indexDiff = lastIndex - startIndex
  if indexDiff >= viewHeight then
    startIndex = startIndex + 1
    drawViewer()
  end
end
 
function config()
  print("Config")
end
 
function back()
  startIndex = 1
  if currentView == ALBUM_VIEW then
    currentArtist = ""
    currentView = ARTIST_VIEW
    drawViewer()
  elseif currentView == SONG_VIEW then
    currentAlbum = ""
    currentView = ALBUM_VIEW
    drawViewer()
  else
    return
  end
end
 
function playSong()
  pause()
 
  id = mediaData[currentArtist][currentAlbum][1]
  currentTapeDrive = peripheral.wrap(id)
  currentTapeDrive.seek(-currentTapeDrive.getSize())
  albumInfo = mediaData[currentArtist][currentAlbum][2]
  trackInfo = findTrackData(albumInfo, currentSong)
  currentTapeDrive.seek(tonumber(trackInfo[3]))
  currentTapeDrive.play()
end
 
function findTrackData(albumData, song)
   for k,v in pairs(albumData) do
     if v[2] == song then
       return v
     end
   end
end
 
function processTouch(x, y)
  for k, v in pairs(buttons) do
    if y == v[2] and (x >= v[1] and x<= (v[1] + v[3])) then
      v[4]()
      return
    end
  end
  for k, v in pairs(viewerButtons) do
    if y == v[2] and (x >= v[1] and x<= (v[1] + v[3])) then
      if currentView == ARTIST_VIEW then
        currentArtist = k
        currentView = ALBUM_VIEW
        v[4]()
        return
      elseif currentView == ALBUM_VIEW then
        currentAlbum = k
        currentView = SONG_VIEW
        v[4]()
        return
      elseif currentView == SONG_VIEW then
        currentSong = k
        v[4]()
        return
      else
        return
      end
    end
  end
end
 
function initScreen()
  drawBorders()
  drawControlButtons(colors.lightGray, colors.black)
  drawSettingsButtons(colors.lightGray, colors.black)
  drawViewer()
end
 
function run()
  checkDisplaySize()
  createMediaData()
  initScreen()
  repeat
    event, p1, p2, p3 = os.pullEvent()
    if event == SCREEN_TOUCH then
      processTouch(p2, p3)
    end
  until event == CHAR and p1 == ("x")
end
 
run()
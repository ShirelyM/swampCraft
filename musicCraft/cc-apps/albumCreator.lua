TAPE_DRIVE = "tape_drive"
 
-- Used for Parsing
local lines = {}
local count = 0
local albumInfo = {}
local artist
local album
 
-- Used for Album Creation
local memUsed = 0.0
local startPos = 0
local prefix, tape
 
-- Temporary. Will Remove to be generic
file = http.get("https://raw.githubusercontent.com/shirelyM/swampCraft/dev/musicCraft/theOffspring/americana/musicCodex.csv")
mcFile = file.readAll()
file.close()
 
-- Detect Tape Drive. Assumes drive has a blank tape.
perps = peripheral.getNames()
for k, v in pairs(perps) do
  if peripheral.getType(v) == TAPE_DRIVE then
    tape = peripheral.wrap(v)
    if tape.getLabel() == "" then
      break
    end
  end  
end
 
if tape.getLabel() ~= "" then
  print("WARNING: Tape is not empty. You must use a blank tape or wipe the existing tape first!")
  return
end
  
-- Parse .csv for album and song link information
for w in string.gmatch(mcFile, "([^\n]+)") do
    if count > 3 then
      lines[#lines+1] = w
      local trackInfo = {}
   
      for c in string.gmatch(w, "([^,]+)") do
        trackInfo[#trackInfo + 1] = c
      end
      albumInfo[#albumInfo + 1] = trackInfo
      count = count + 1
    elseif count == 1 then
      local a = 1
      for c in string.gmatch(w, "([^,]+)") do
        if a == 1 then
          artist = c
        elseif a == 2 then
          album = c
        elseif a == 3 then
          prefix = c
        else
        end
        a = a + 1
      end
      count = count + 1
    else
      count = count + 1
    end
  end
 
 
 
-- Album Creation starts here
local tapeSize = tape.getSize()
 
-- Set Label
local title = artist.. " - ".. album
tape.setLabel(title)
print(title) 
 
-- Write Tracks
local infoString = ""
local endInfo = "%"
local trackBreak = ";"
 
tape.seek(-tape.getPosition())
 
local trackNum = 1
 
for k,v in pairs(albumInfo) do
  local trackInfo = ""
  
  local fileName = v[3]
  songLink = prefix.. fileName
  songLink = string.gsub(songLink, "%s+", "%%20")
  local response = http.get(songLink, nil, true)
  
  tempFile = response.readAll()
  startPos = tape.getPosition()
  tape.write(tempFile)
  
  memUsed = tape.getPosition() / tapeSize * 100
  
  print("Track ".. trackNum.. " start: ".. startPos.. " | ".. memUsed.. "% Full")
  
  
  response.close()
  
  trackInfo = trackInfo.. trackNum.. ",".. albumInfo[trackNum][2].. ",".. startPos.. ",".. tape.getPosition().. trackBreak  
  infoString = infoString.. trackInfo      
  trackNum = trackNum + 1
end
 
infoString = infoString.. endInfo
 
-- Write indexing info to end of tape
tape.seek(tape.getSize())
for i = 1, #infoString do
  tape.seek(-1)
  local c = string.sub(infoString,i,i)
  value = string.byte(c)
  tape.write(value)
  tape.seek(-1)
end
 
tape.seek(-tape.getSize())
 
io.read()
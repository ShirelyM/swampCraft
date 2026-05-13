-- MusicCraft Updater
-- Put this tiny file on Pastebin once.
-- After that, update files from GitHub instead of re-uploading to Pastebin.

local OWNER = "ShirelyM"
local REPO = "swampCraft"
local BRANCH = "dev"

-- Adjust this folder to wherever you place these Lua files in your GitHub repo.
local GITHUB_BASE_PATH = "musicCraft/cc-apps/atm10/radio"

local FILES = {
  {
    name = "media_center_radio.lua",
    path = "media_center_radio.lua",
    startup = false
  }
}

local function rawUrl(path)
  return "https://raw.githubusercontent.com/"
    .. OWNER .. "/"
    .. REPO .. "/refs/heads/"
    .. BRANCH .. "/"
    .. GITHUB_BASE_PATH .. "/"
    .. path
end

local function downloadFile(remotePath, localPath)
  local url = rawUrl(remotePath)

  print("Downloading:")
  print(url)
  print(" -> " .. localPath)

  local response, err = http.get(url)
  if not response then
    print("FAILED: " .. tostring(err))
    return false
  end

  local data = response.readAll()
  response.close()

  local handle = fs.open(localPath, "w")
  if not handle then
    print("FAILED: could not open " .. localPath)
    return false
  end

  handle.write(data)
  handle.close()

  print("OK: " .. localPath)
  return true
end

local function printMenu()
  print()
  print("MusicCraft Updater")
  print("==================")
  print("1) Update Media Center transmitter")
  print("2) Update Radio Receiver")
  print("3) Update Both")
  print("4) Set startup to Media Center")
  print("5) Set startup to Receiver")
  print("6) Exit")
  print()
  write("Choice: ")
end

if not http then
  error("HTTP is disabled.")
end

while true do
  printMenu()
  local choice = read()

  if choice == "1" then
    downloadFile("media_center_radio.lua", "media_center_radio.lua")

  elseif choice == "2" then
    downloadFile("radio_receiver.lua", "radio_receiver.lua")

  elseif choice == "3" then
    downloadFile("media_center_radio.lua", "media_center_radio.lua")
    downloadFile("radio_receiver.lua", "radio_receiver.lua")

  elseif choice == "4" then
    local h = fs.open("startup.lua", "w")
    h.write('shell.run("media_center_radio.lua")\n')
    h.close()
    print("startup.lua now launches media_center_radio.lua")

  elseif choice == "5" then
    local h = fs.open("startup.lua", "w")
    h.write('shell.run("radio_receiver.lua")\n')
    h.close()
    print("startup.lua now launches radio_receiver.lua")

  elseif choice == "6" or choice == "q" then
    print("Done.")
    break

  else
    print("Invalid choice.")
  end
end

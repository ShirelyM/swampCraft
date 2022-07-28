DOOR_PASSWORD = "0p3n"

while true do
   term.clear()
   term.setCursorPos(1,1)
   print("Please Enter Password: ")
   input = read("*")
   if input == DOOR_PASSWORD then
      redstone.setOutput("right", true)
      sleep(5)
      redstone.setOutput("right", false)
   end
end

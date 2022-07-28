local monitor = peripheral.wrap("right")

local isRunning = true

while isRunning == true do
   monitor.clear()
   monitor.setCursorPos(1,1)
   monitor.write("Welcome to Swamps Lab!")
   sleep(7)
   monitor.setCursorPos(1,4)
   monitor.write("Swamp is now developing SwampNet")
   sleep(7)
   monitor.setCursorPos(1,7)
   monitor.write("Follow the Lab Rules!")
   sleep(7)
   monitor.setCursorPos(1,10)
   monitor.write("Make sure to use your VPN!")
   sleep(7)
   monitor.setCursorPos(1,13)
   monitor.write("Stay Safe!")
   sleep(7)
   monitor.setCursorPos(1,16)
   monitor.write("Have Fun!")
   sleep(7)
end   

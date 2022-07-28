os.loadAPI("turtleCraft/smartTurtle.lua")
os.loadAPI("turtleNav.lua")
rednet.open("left")

while true do
   msg = rednet.receive("turtleNet")
   sleep(1)
   if msg then
      print("A turtleNet message was received!")
      turtleNav.calibrate()
   else
      print("No turtleNet messages")
   end
end

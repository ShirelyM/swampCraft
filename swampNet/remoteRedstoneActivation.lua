redstone.setOutput("right", true)
rednet.open("left")

while true do
   id, msg, distance, protocol = rednet.receive("swampNet", 1)

   if msg then
      if (id == 58 or id == 65) and msg == "openLab" then
         redstone.setOutput("right", false)
         sleep(6)
         redstone.setOutput("right", true)
      end
   end
end

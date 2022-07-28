redstone.setOutput("right", true)

rednet.open("left")

while true do
   id, msg, d, protocol = rednet.receive("swampNet", 1)

   if msg then
      if (id == 58 or id == 65) and msg == "openVault" then
         print("msg")
         redstone.setOutput("right", false)
         sleep(5)
         redstone.setOutput("right", true)

      end
   end
end


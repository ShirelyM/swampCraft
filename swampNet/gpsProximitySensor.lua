rednet.open("left")
msg = {}

while true do
   term.clear()
   term.setCursorPos(1,1)
   print("Restricted Area")
   id, msg = rednet.receive("swampNet", 1)
   if msg then
      x, y, z = gps.locate()
      dx = x - msg.x
      dy = y - msg.y
      dz = z - msg.z
      dist = math.sqrt(dx^2 + dy^2 + dz^2)
      if dist <= 4 then
         redstone.setOutput("back", true)
         sleep(5)
         redstone.setOutput("back", false)
      end
   end
end

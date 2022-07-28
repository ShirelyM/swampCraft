os.loadAPI("turtleCraft/smartTurtle.lua")

--"east", "west", "north", "south"
orientation = nil

function selfLocate()
   if gps.locate() then
      return gps.locate()
   end
end

function calibrate()
   --Use x/z values to determine cardinal directions.
   local x1, y1, z1 = gps.locate()
   smartTurtle.turnLeft(4)
   smartTurtle.moveBackward(1)
   smartTurtle.turnRight(4)
   
   local x2, y2, z2 = gps.locate()
   
   local x = x2 - x1
   local z = z2 - z1
   
   if z > 0 then
      orientation = "north"
   elseif z < 0 then
      orientation = "south"
   elseif x > 0 then
      orientation = "west"
   elseif x < 0 then
      orientation = "east"
   end
   
   smartTurtle.moveForward(1)   
   print(orientation)
end

function orientation()
   print(orientation)
end

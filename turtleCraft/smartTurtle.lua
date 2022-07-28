function moveForward(distance)
   for i=1, distance do
      turtle.forward()
   end
end

function moveBackward(distance)
   for i=1, distance do
      turtle.back()
   end
end

function moveUp(distance)
   for i=1, distance do
      turtle.up()
   end
end

function moveDown(distance)
   for i=1, distance do
      turtle.down()
   end
end

function turnLeft(numTimes)
   for i=1, numTimes do
      turtle.turnLeft()
   end
end

function turnRight(numTimes)
   for i=1, numTimes do
      turtle.turnRight()
   end
end

function digColumn(height, digUp)
   checkFuel()
   for i=1, height do
      if digUp then
         if turtle.detectUp() then
            turtle.digUp()
         end
         moveUp(1)
      end
      
      if not digUp then
         if turtle.detectDown() then
            turtle.digDown()
         end
         moveDown(1)
      end
   end
end   

function detectAndDig()
   while turtle.detect() do
      turtle.dig()
      sleep(0.1)
   end
end

function digForward(length)
   for i=1, length do
      detectAndDig()
      moveForward(1)
   end
end

function digSlice(height, width, startTop, startLeft)
   if not startTop then
      digForward(1)
      if startLeft then
         turnRight(1)
      end
      if not startLeft then
         turnLeft(1)
      end
      digColumn(height-1, true)
   end
   if startTop then
      digForward(1)
      if startLeft then
         turnRight(1)
      end
      if not startLeft then
         turnLeft(1)
      end
      digColumn(height-1, false)
      moveUp(height-1)
   end
 
   for i=1, (width-1) do
      digForward(1)
      digColumn(height-1, false)
      moveUp(height-1)
   end
   if startLeft then
      turnLeft(1)
   else
      turnRight(1)
   end 
      
end

function digTunnel(height, width, length)
   for i=1, length do
      if i%2 == 1 then
         startLeft=true
      else
         startLeft=false
      end
      if i == 1 then
         digSlice(height, width, false, true)
      else
         digSlice(height, width, true, startLeft)
      end
   end
end

function refuel()
   for i=1, 16 do
      turtle.select(i)
      detail = turtle.getItemDetail()
      if detail then
         if detail["name"] == "minecraft:coal" then
            turtle.refuel()
         end   
      end
   end
end

function checkFuel()
   if turtle.getFuelLevel()/turtle.getFuelLimit() < 0.2 then
      refuel()   
   end
end

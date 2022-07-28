function clear(monitor)
   monitor.clear()
end

function findStringEnd(inputString, startIndex, maxWidth)
   i = startIndex + maxWidth
   c1 = string.sub(inputString, i-1, i-1)
   c2 = string.sub(inputString, i, i)
   
   if (c2 == " " or c1 == " ") then
      return (i-1)
   else
      j = i-1
      c3 = ""
      while (c3 != " " and j != 1) do
         j = j-1
         c3 = string.sub(inputString, j, j)
      end
      return j
   end
end     

function displayText(monitor, displayText)
   x,y = monitor.getSize()
   len = string.len(displayText)
   numLines = len/x
   start = 1
   finish = findStringEnd(displayText, start, x)
      
   for i=1, numLines do
      monitor.setCursorPos(1, i)
      
      if i != 1 then
         start = finish + 1
         finish = findStringEnd(displayText, start, x)
         
      if i < numLines then
         monitor.write(string.sub(displayText, start, finish))
      else
         monitor.write(string.sub(displayText, start, len))
      end
   end
end     

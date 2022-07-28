os.loadAPI("turtleCraft/smartTurtle.lua")
term.clear()
print("Hello and welcome to your tunnel bot's command hub")
print("\nThe gravel problem has been fixed and turtles can now self refuel if coal is available in the inventory")
print("\nPlease place your tunnel bot ground level and on the left side of the tunnel start")
sleep(13)
term.clear()
print("Please enter tunnel height: ")
x = tonumber(io.read())
term.clear()

print("Please enter tunnel width: ")
y = tonumber(io.read())
term.clear()

print("Please enter tunnel length: ")
z = tonumber(io.read())
term.clear()

print("Congratulations, your tunnel bot will now dig a " .. x .. "x" .. y .. "x" .. z .. " tunnel!")

smartTurtle.digTunnel(x,y,z)

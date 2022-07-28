os.loadAPI("labDisplay/monitor.lua")
reactor = peripheral.wrap("BigReactors-Reactor_0")
--mon1 = peripheral.wrap("monitor_11")
mon1 = peripheral.wrap("monitor_2")
--displays = {mon1, mon2}
 
REACTOR_STATUS_LINE = 1
REACTOR_CHARGE_LINE = 3
FUEL_TEMP_LINE      = 5
CASING_TEMP_LINE    = 7
FUEL_AMOUNT_LINE    = 9
WASTE_AMOUNT_LINE   = 11
 
function monitorReactorCharge()
   reactorCharge = reactor.getEnergyStats()["energyStored"]/reactor.getEnergyStats()["energyCapacity"] * 100
   
   if reactorCharge < 50 and not reactor.getActive() then
      reactor.setActive(true)
   elseif reactorCharge > 75 and reactor.getActive() then
      reactor.setActive(false)
   end
   
   displayReactorCharge(reactorCharge)
end
 
function displayReactorActivity()
   if reactor.getActive() then
      reactorStatus = "Online"
   else
      reactorStatus = "Offline"
   end
   
   text = "Reactor Status: " .. reactorStatus
   monitor.displayLine(mon1, text, REACTOR_STATUS_LINE)
   print(text)
end
 
function displayReactorCharge(reactorCharge)
   text = "Reactor Charge: " .. reactorCharge .. "%"
   monitor.displayLine(mon1, text, REACTOR_CHARGE_LINE)
   print(text)
end
 
function displayFuelTemperature()
   text = "Fuel Temp: " .. reactor.getFuelTemperature() .. " C"
   monitor.displayLine(mon1, text, FUEL_TEMP_LINE)
   print(text)
end
 
function displayCasingTemperature()
   text = "Casing Temp: " .. reactor.getCasingTemperature() .. " C"
   monitor.displayLine(mon1, text, CASING_TEMP_LINE)
   print(text)
end
 
function displayFuelAmount()
   text = "Fuel Amount: " .. reactor.getFuelAmount() .. ""
   monitor.displayLine(mon1, text, FUEL_AMOUNT_LINE)
   print(text)
end
 
function displayWasteAmount()
   text = "Waste Amount: " .. reactor.getWasteAmount() .. ""
   monitor.displayLine(mon1, text, WASTE_AMOUNT_LINE)
   print(text)
end
 
function displayAll()
   print("\nARMS - Autonomous Reactor Management System\n")
   displayReactorActivity()
   monitorReactorCharge()
   displayFuelTemperature()
   displayCasingTemperature()
   displayFuelAmount()
   displayWasteAmount()
   print("\n\n\n\n\n\n\n\n")
end
 
function main()
   isRunning = true
 
   while isRunning do
      --isConnected = reactor.getConnected()
      mon1.clear()
      displayAll()
      sleep(1)
   end
end
 
main()

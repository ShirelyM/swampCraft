-- Peripheral Device Types
DRIVE       = "drive"
MODEM       = "modem"
MONITOR     = "monitor"
TAPE_DRIVE  = "tape_drive"

-- Return an array of peripherals of the specified type.
-- deviceType   Type of device to be searched for on the network
function identifyDevices(deviceType)
  devices = {}
  for i,id in pairs(peripheral.getNames()) do
    if peripheral.getType(id) == deviceType then
      devices[id] = peripheral.wrap(temp)
    end
  end
  return devices
end

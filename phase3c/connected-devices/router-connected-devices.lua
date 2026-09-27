local interface = "br-lan"
local probe_timeout_seconds = 1

local function candidate_ipv4_addresses()
  local addresses = {}
  local command = io.popen("ip neigh show dev " .. interface .. " 2>/dev/null")
  if command then
    for line in command:lines() do
      local address = line:match("^(%d+%.%d+%.%d+%.%d+)")
      if address then
        addresses[address] = true
      end
    end
    command:close()
  end

  local leases = io.open("/tmp/dhcp.leases", "r")
  if leases then
    for line in leases:lines() do
      local address = line:match("^%S+%s+%S+%s+(%d+%.%d+%.%d+%.%d+)")
      if address then
        addresses[address] = true
      end
    end
    leases:close()
  end

  return addresses
end

local function active_devices()
  local devices = {}
  for address in pairs(candidate_ipv4_addresses()) do
    local command = io.popen(
      "arping -I " .. interface .. " -c 1 -w " .. probe_timeout_seconds .. " " .. address .. " 2>/dev/null"
    )
    if command then
      for line in command:lines() do
        local mac = line:match("%[(%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)%]")
        if mac then
          devices[mac:lower()] = true
        end
      end
      command:close()
    end
  end

  local count = 0
  for _ in pairs(devices) do
    count = count + 1
  end
  return count
end

local function scrape()
  metric("router_lan_active_devices", "gauge", nil, active_devices())
end

return { scrape = scrape }

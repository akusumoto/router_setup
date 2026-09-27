local interface = "br-lan"

local function connected_devices()
  local devices = {}
  local command = io.popen("ip neigh show dev " .. interface .. " 2>/dev/null")
  if command then
    for line in command:lines() do
      local mac = line:match("lladdr (%x%x:%x%x:%x%x:%x%x:%x%x:%x%x)")
      if mac and not line:match(" FAILED$") and not line:match(" INCOMPLETE$") then
        devices[mac:lower()] = true
      end
    end
    command:close()
  end

  local count = 0
  for _ in pairs(devices) do
    count = count + 1
  end
  return count
end

local function scrape()
  metric("router_lan_connected_devices", "gauge", nil, connected_devices())
end

return { scrape = scrape }

-- Per-LAN-IPv4 usage inferred from conntrack metadata. No packet payloads,
-- DNS names, MAC addresses, or DHCP hostnames are exported.
local state_file = "/tmp/router_device_usage.state"
local lan_interface = "br-lan"

local function command_output(command_line)
  local command = io.popen(command_line)
  if not command then
    error("unable to start command: " .. command_line)
  end
  local output = command:read("*a")
  local ok = command:close()
  if not ok then
    error("command failed: " .. command_line)
  end
  return output
end

local function lan_network()
  local output = command_output("ip -4 -o addr show dev " .. lan_interface .. " 2>/dev/null")
  local address, prefix = output:match("inet%s+(%d+%.%d+%.%d+%.%d+)/(%d+)")
  if not address or not prefix then
    error("no IPv4 address found on " .. lan_interface)
  end
  return address, tonumber(prefix)
end

local function ipv4_octets(address)
  local a, b, c, d = address:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  return tonumber(a), tonumber(b), tonumber(c), tonumber(d)
end

local function belongs_to_lan(address, lan_address, prefix)
  local address_octets = { ipv4_octets(address) }
  local lan_octets = { ipv4_octets(lan_address) }
  if not address_octets[4] or not lan_octets[4] then
    return false
  end

  for position = 1, 4 do
    local bits = math.max(0, math.min(8, prefix - ((position - 1) * 8)))
    if bits > 0 then
      local block_size = 2 ^ (8 - bits)
      if math.floor(address_octets[position] / block_size) ~= math.floor(lan_octets[position] / block_size) then
        return false
      end
    end
  end
  return true
end

local function load_state()
  local device_totals = {}
  local flow_bytes = {}
  local file = io.open(state_file, "r")
  if not file then
    return device_totals, flow_bytes
  end

  for line in file:lines() do
    local device, total = line:match("^D\t([^\t]+)\t(%d+)$")
    if device then
      device_totals[device] = tonumber(total)
    else
      local flow, bytes = line:match("^F\t([^\t]+)\t(%d+)$")
      if flow then
        flow_bytes[flow] = tonumber(bytes)
      end
    end
  end
  file:close()
  return device_totals, flow_bytes
end

local function save_state(device_totals, flow_bytes)
  local temporary_file = state_file .. ".tmp"
  local file = assert(io.open(temporary_file, "w"))
  for device, total in pairs(device_totals) do
    file:write("D\t", device, "\t", total, "\n")
  end
  for flow, bytes in pairs(flow_bytes) do
    file:write("F\t", flow, "\t", bytes, "\n")
  end
  file:close()
  assert(os.rename(temporary_file, state_file))
end

local function collect()
  local lan_address, prefix = lan_network()
  local device_totals, previous_flow_bytes = load_state()
  local current_flow_bytes = {}
  local active_connections = {}

  for line in command_output("conntrack -L -o extended 2>/dev/null"):gmatch("[^\n]+") do
    local protocol = line:match("^%S+%s+%d+%s+(%S+)") or "unknown"
    local source, destination = line:match("src=(%d+%.%d+%.%d+%.%d+) dst=(%d+%.%d+%.%d+%.%d+)")
    if source and destination and belongs_to_lan(source, lan_address, prefix) then
      local source_port = line:match("sport=(%d+)") or line:match("id=(%d+)") or ""
      local destination_port = line:match("dport=(%d+)") or ""
      local flow = protocol .. "|" .. source .. "|" .. destination .. "|" .. source_port .. "|" .. destination_port
      local bytes = 0
      for value in line:gmatch("bytes=(%d+)") do
        bytes = bytes + tonumber(value)
      end

      current_flow_bytes[flow] = bytes
      active_connections[source] = (active_connections[source] or 0) + 1
      device_totals[source] = device_totals[source] or 0

      local previous = previous_flow_bytes[flow]
      if previous then
        device_totals[source] = device_totals[source] + math.max(0, bytes - previous)
      end
    end
  end

  save_state(device_totals, current_flow_bytes)
  return device_totals, active_connections
end

local function scrape()
  local device_totals, active_connections = collect()
  local traffic_metric = metric("router_lan_device_traffic_bytes_total", "counter")
  local connection_metric = metric("router_lan_device_active_connections", "gauge")

  for device, total in pairs(device_totals) do
    traffic_metric({ device = device }, total)
  end
  for device, connections in pairs(active_connections) do
    connection_metric({ device = device }, connections)
  end
end

return { scrape = scrape }
